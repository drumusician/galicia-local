defmodule GaliciaLocal.Scraper.Workers.OverpassWorker do
  @moduledoc """
  Oban worker for discovering businesses via OpenStreetMap Overpass API.

  Free alternative to Google Places. Searches OSM data by category
  within a geographic bounding box.

  ## Usage

      %{
        category_slug: "restaurants",
        city_id: "uuid",
        category_id: "uuid",
        bbox_south: 42.3,
        bbox_west: -8.0,
        bbox_north: 42.4,
        bbox_east: -7.8
      }
      |> OverpassWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.Directory.{Business, City, Category, ScrapeJob}
  alias GaliciaLocal.Scraper.Overpass
  alias GaliciaLocal.Scraper.Workers.WebsiteCrawlWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    category_slug = args["category_slug"]
    city_id = args["city_id"]
    category_id = args["category_id"]

    bbox = {
      args["bbox_south"],
      args["bbox_west"],
      args["bbox_north"],
      args["bbox_east"]
    }

    Logger.info("Starting Overpass search: #{category_slug} in bbox")

    city = if city_id, do: City.get_by_id!(city_id), else: nil
    category = if category_id, do: Category.get_by_id!(category_id), else: nil
    region_id = city && city.region_id

    {:ok, scrape_job} =
      ScrapeJob.create(%{
        source: :openstreetmap,
        query: "OSM #{category_slug}",
        city_id: city_id,
        category_id: category_id,
        region_id: region_id,
        bounds_south: args["bbox_south"],
        bounds_west: args["bbox_west"],
        bounds_north: args["bbox_north"],
        bounds_east: args["bbox_east"]
      })

    case Overpass.search(category_slug, bbox) do
      {:ok, elements} ->
        Logger.info("Overpass found #{length(elements)} #{category_slug} elements")

        results =
          Enum.map(elements, fn element ->
            create_or_update_business(element, city, category)
          end)

        created = Enum.count(results, fn {status, _} -> status == :created end)

        ScrapeJob.mark_completed!(scrape_job, length(elements), created)

        Logger.info("Overpass import complete: #{created} created out of #{length(elements)} found")
        :ok

      {:error, reason} ->
        Logger.error("Overpass search failed: #{inspect(reason)}")
        ScrapeJob.mark_failed!(scrape_job, inspect(reason))
        {:error, reason}
    end
  end

  defp create_or_update_business(element, city, category) do
    slug =
      element.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 100)

    attrs = %{
      name: element.name,
      slug: slug,
      address: element.address,
      phone: element.phone,
      website: element.website,
      email: element.email,
      google_maps_url: element.google_maps_url,
      latitude: element.latitude,
      longitude: element.longitude,
      opening_hours: element.opening_hours,
      status: :pending,
      source: :openstreetmap,
      raw_data: %{
        osm_id: element.osm_id,
        opening_hours_raw: element.opening_hours_raw,
        raw_tags: element.raw_tags
      },
      city_id: city && city.id,
      category_id: category && category.id,
      region_id: city && city.region_id
    }

    existing = find_by_osm_id(element.osm_id, city)

    case existing do
      nil ->
        case Business.create(attrs) do
          {:ok, business} ->
            Logger.info("Created business from OSM: #{business.name}")
            if business.website, do: queue_website_scrape(business)
            {:created, business}

          {:error, %Ash.Error.Invalid{}} ->
            Logger.debug("Business already exists: #{element.name}, skipping")
            {:skipped, element.name}

          error ->
            Logger.warning("Failed to create business #{element.name}: #{inspect(error)}")
            {:error, error}
        end

      business ->
        Logger.debug("Updating existing OSM business: #{business.name}")
        case Ash.update(business, Map.drop(attrs, [:slug, :status, :source])) do
          {:ok, updated} -> {:updated, updated}
          {:error, _} -> {:skipped, business.name}
        end
    end
  end

  defp find_by_osm_id(nil, _city), do: nil
  defp find_by_osm_id(osm_id, city) do
    import Ecto.Query

    query =
      from b in "businesses",
        where: fragment("raw_data->>'osm_id' = ?", ^osm_id),
        select: type(b.id, :string)

    query =
      if city,
        do: where(query, [b], b.city_id == type(^city.id, Ecto.UUID)),
        else: query

    case GaliciaLocal.Repo.one(query) do
      nil -> nil
      id -> Business.get_by_id!(id)
    end
  end

  defp queue_website_scrape(business) do
    Logger.info("Queuing website research for OSM business: #{business.name} (#{business.website})")

    %{business_id: business.id}
    |> WebsiteCrawlWorker.new()
    |> Oban.insert()
  end
end
