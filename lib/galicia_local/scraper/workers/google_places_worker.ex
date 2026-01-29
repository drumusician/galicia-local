defmodule GaliciaLocal.Scraper.Workers.GooglePlacesWorker do
  @moduledoc """
  Oban worker for scraping businesses from Google Places API.

  This is Step 1 of the data pipeline:
  1. Google Places API → Get business data with reviews
  2. Save to database with status :pending
  3. Queue website scraping (Crawly)
  4. Queue LLM enrichment (AshAI)

  ## Usage

      %{
        query: "abogados",
        city_id: "uuid",
        category_id: "uuid"
      }
      |> GaliciaLocal.Scraper.Workers.GooglePlacesWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.Directory.{Business, City, Category, ScrapeJob}
  alias GaliciaLocal.Scraper.GooglePlaces
  alias GaliciaLocal.Scraper.Workers.WebsiteCrawlWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    query = args["query"]
    city_id = args["city_id"]
    category_id = args["category_id"]

    Logger.info("Starting Google Places search: #{query}")

    # Load city for location context
    city = if city_id, do: City.get_by_id!(city_id), else: nil
    category = if category_id, do: Category.get_by_id!(category_id), else: nil

    # Create scrape job record
    {:ok, scrape_job} =
      ScrapeJob.create(%{
        source: :google_maps,
        query: query,
        city_id: city_id,
        category_id: category_id
      })

    # Build location from city
    location =
      if city && city.latitude && city.longitude do
        {Decimal.to_float(city.latitude), Decimal.to_float(city.longitude)}
      else
        nil
      end

    # Search with full details (includes reviews)
    case GooglePlaces.search_with_details(query, location: location) do
      {:ok, places} ->
        Logger.info("Found #{length(places)} places for: #{query}")

        # Create businesses from places
        results =
          Enum.map(places, fn place ->
            create_or_update_business(place, city, category)
          end)

        created = Enum.count(results, fn {status, _} -> status == :created end)
        updated = Enum.count(results, fn {status, _} -> status == :updated end)

        # Mark job completed
        ScrapeJob.mark_completed!(scrape_job, length(places), created)

        Logger.info("Google Places scrape complete: #{created} created, #{updated} updated")
        :ok

      {:error, reason} ->
        Logger.error("Google Places search failed: #{inspect(reason)}")
        ScrapeJob.mark_failed!(scrape_job, inspect(reason))
        {:error, reason}
    end
  end

  defp create_or_update_business(place, city, category) do
    # Generate a slug from the name
    slug =
      place.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 100)

    # Analyze reviews for language hints
    reviews = place[:reviews] || []
    {english_detected, english_confidence} = analyze_reviews_for_english(reviews)

    # Build reviews text for LLM enrichment later
    reviews_text =
      reviews
      |> Enum.map(fn r -> "[#{r[:language]}] #{r[:author]} (#{r[:rating]}★): #{r[:text]}" end)
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
      review_count: place[:review_count] || length(reviews),
      price_level: place[:price_level],
      opening_hours: place[:opening_hours],
      description_es: place[:editorial_summary],
      speaks_english: english_detected,
      speaks_english_confidence: english_confidence,
      status: :pending,
      photo_urls: place[:photos] || [],
      source: :google_maps,
      raw_data: %{
        place_id: place[:place_id],
        types: place[:types],
        reviews: reviews,
        reviews_text: reviews_text,
        business_status: place[:business_status]
      },
      city_id: city && city.id,
      category_id: category && category.id
    }

    # Try to create, if fails due to uniqueness, update instead
    case Business.create(attrs) do
      {:ok, business} ->
        Logger.info("Created business: #{business.name}")
        # Queue website scraping if has website
        if business.website, do: queue_website_scrape(business)
        {:created, business}

      {:error, %Ash.Error.Invalid{}} ->
        # Business might already exist, try to find and update
        Logger.debug("Business might exist: #{place.name}, skipping")
        {:skipped, place.name}

      error ->
        Logger.warning("Failed to create business #{place.name}: #{inspect(error)}")
        {:error, error}
    end
  end

  # Analyze reviews to detect if business likely speaks English
  defp analyze_reviews_for_english(reviews) when length(reviews) == 0, do: {nil, nil}

  defp analyze_reviews_for_english(reviews) do
    english_reviews =
      Enum.filter(reviews, fn r ->
        lang = r[:language] || ""
        String.starts_with?(lang, "en")
      end)

    english_count = length(english_reviews)
    _total_count = length(reviews)

    cond do
      english_count >= 3 ->
        # Multiple English reviews = strong signal
        {true, Decimal.from_float(0.9)}

      english_count >= 1 ->
        # At least one English review
        {true, Decimal.from_float(0.7)}

      # Check if any review mentions English in text
      Enum.any?(reviews, fn r ->
        text = String.downcase(r[:text] || "")
        String.contains?(text, ["english", "inglés", "speak english", "habla inglés"])
      end) ->
        {true, Decimal.from_float(0.6)}

      true ->
        # No English signal
        {false, Decimal.from_float(0.3)}
    end
  end

  # Queue website scraping and research pipeline
  defp queue_website_scrape(business) do
    Logger.info("Queuing website research for: #{business.name} (#{business.website})")

    %{business_id: business.id}
    |> WebsiteCrawlWorker.new()
    |> Oban.insert()
  end
end
