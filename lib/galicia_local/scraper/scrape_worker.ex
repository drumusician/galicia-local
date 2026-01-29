defmodule GaliciaLocal.Scraper.ScrapeWorker do
  @moduledoc """
  Oban worker for scraping businesses from Google Places.

  Usage:
      # Scrape lawyers in Ourense
      %{
        query: "abogados Ourense",
        city_id: city.id,
        category_id: lawyers_category.id
      }
      |> GaliciaLocal.Scraper.ScrapeWorker.new()
      |> Oban.insert()

      # Or use the helper function
      GaliciaLocal.Scraper.scrape_city_category(city, category)
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.Directory.{Business, City, Category, ScrapeJob}
  alias GaliciaLocal.Scraper.GooglePlaces

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    query = args["query"]
    city_id = args["city_id"]
    category_id = args["category_id"]

    Logger.info("Starting scrape job: #{query}")

    # Load city and category for context
    city = if city_id, do: City.get_by_id!(city_id), else: nil
    category = if category_id, do: Category.get_by_id!(category_id), else: nil

    # Create scrape job record
    {:ok, scrape_job} =
      ScrapeJob.create(%{
        source: :google_places,
        query: query,
        city_id: city_id,
        category_id: category_id
      })

    # Build location from city if available
    location =
      if city && city.latitude && city.longitude do
        {Decimal.to_float(city.latitude), Decimal.to_float(city.longitude)}
      else
        nil
      end

    # Perform the search
    case GooglePlaces.search_with_details(query, location: location) do
      {:ok, places} ->
        Logger.info("Found #{length(places)} places for: #{query}")

        # Create businesses from places
        {created, _errors} =
          places
          |> Enum.map(fn place ->
            create_business_from_place(place, city, category)
          end)
          |> Enum.split_with(fn
            {:ok, _} -> true
            _ -> false
          end)

        # Mark job completed
        ScrapeJob.mark_completed!(scrape_job, length(places), length(created))

        Logger.info("Scrape complete: #{length(created)} businesses created")
        :ok

      {:error, reason} ->
        Logger.error("Scrape failed: #{inspect(reason)}")
        ScrapeJob.mark_failed!(scrape_job, inspect(reason))
        {:error, reason}
    end
  end

  defp create_business_from_place(place, city, category) do
    # Generate a slug from the name
    slug =
      place.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 100)

    # Extract reviews text for LLM enrichment
    reviews_text =
      (place[:reviews] || [])
      |> Enum.map(& &1[:text])
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n---\n")

    attrs = %{
      name: place.name,
      slug: slug,
      address: place.address,
      phone: place[:phone],
      website: place[:website],
      google_maps_url: place[:google_maps_url],
      latitude: place[:latitude],
      longitude: place[:longitude],
      rating: place[:rating],
      review_count: place[:review_count] || 0,
      price_level: place[:price_level],
      opening_hours: place[:opening_hours],
      description_es: place[:editorial_summary],
      status: :pending,
      source: :google_places,
      raw_data: %{
        place_id: place[:place_id],
        types: place[:types],
        reviews: place[:reviews],
        reviews_text: reviews_text
      },
      city_id: city && city.id,
      category_id: category && category.id
    }

    # Check if business already exists (by slug + city)
    case Business.create(attrs) do
      {:ok, business} ->
        Logger.info("Created business: #{business.name}")
        {:ok, business}

      {:error, %Ash.Error.Invalid{errors: errors}} = error ->
        # Check if it's a uniqueness error
        if Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidChanges{}, &1)) do
          Logger.debug("Business already exists: #{place.name}")
          {:skip, :already_exists}
        else
          Logger.warning("Failed to create business #{place.name}: #{inspect(errors)}")
          error
        end

      error ->
        Logger.warning("Failed to create business #{place.name}: #{inspect(error)}")
        error
    end
  end
end
