defmodule GaliciaLocal.Scraper do
  @moduledoc """
  Main interface for scraping business listings.

  ## Data Pipeline

  1. **Google Places API** (recommended) - Get authoritative business data
     ```
     GaliciaLocal.Scraper.search_google_places(city, category)
     ```

  2. **Crawly Spiders** - Scrape business directories
     ```
     GaliciaLocal.Scraper.scrape(:paginas_amarillas, city: "ourense", category: "abogados")
     ```

  ## Usage Examples

      # Search Google Places for lawyers in Ourense (recommended)
      city = GaliciaLocal.Directory.City.get_by_slug!("ourense")
      category = GaliciaLocal.Directory.Category.get_by_slug!("lawyers")
      GaliciaLocal.Scraper.search_google_places(city, category)

      # Or use Crawly spider for Páginas Amarillas
      GaliciaLocal.Scraper.scrape(:paginas_amarillas, city: "ourense", category: "abogados")

      # Check status
      GaliciaLocal.Scraper.status()
  """

  require Logger

  alias GaliciaLocal.Directory.{City, Category, CategoryTranslation}
  alias GaliciaLocal.Scraper.Spiders.{PaginasAmarillas, DiscoverySpider}
  alias GaliciaLocal.Scraper.Workers.{GooglePlacesWorker, OverpassWorker}

  @spiders %{
    paginas_amarillas: PaginasAmarillas,
    discovery: DiscoverySpider
  }

  # Spanish translations for common categories
  @category_translations %{
    "lawyers" => "abogados",
    "accountants" => "contables",
    "real-estate" => "inmobiliarias",
    "doctors" => "medicos",
    "dentists" => "dentistas",
    "restaurants" => "restaurantes",
    "cafes" => "cafeterias",
    "supermarkets" => "supermercados",
    "plumbers" => "fontaneros",
    "electricians" => "electricistas",
    "veterinarians" => "veterinarios",
    "hair-salons" => "peluquerias",
    "car-services" => "talleres",
    "wineries" => "bodegas",
    "bakeries" => "panaderias",
    "butchers" => "carnicerias",
    "markets" => "mercados",
    "language-schools" => "escuela español para extranjeros"
  }

  # Sub-queries per category to get more comprehensive results
  # Each query is searched separately, results are deduplicated by place_id
  @category_sub_queries %{
    "restaurants" => ["restaurantes", "tapas", "marisquería", "pizzería", "asador", "sidrería", "pulpería"],
    "cafes" => ["cafeterías", "café", "pastelería", "chocolatería"],
    "lawyers" => ["abogados", "bufete abogados", "asesoría legal", "notaría"],
    "accountants" => ["contables", "asesoría fiscal", "gestoría"],
    "doctors" => ["médicos", "clínica médica", "centro de salud", "médico de familia"],
    "dentists" => ["dentistas", "clínica dental", "ortodoncia"],
    "real-estate" => ["inmobiliarias", "agencia inmobiliaria", "venta pisos"],
    "supermarkets" => ["supermercados", "hipermercado", "tienda alimentación"],
    "plumbers" => ["fontaneros", "fontanería", "instalaciones sanitarias"],
    "electricians" => ["electricistas", "instalaciones eléctricas"],
    "veterinarians" => ["veterinarios", "clínica veterinaria"],
    "hair-salons" => ["peluquerías", "salón de belleza", "barbería"],
    "car-services" => ["talleres", "taller mecánico", "taller coches", "ITV"],
    "wineries" => ["bodegas", "vinoteca", "enoteca"],
    "bakeries" => ["panaderías", "panadería", "horno de pan"],
    "butchers" => ["carnicerías", "carnicería"],
    "markets" => ["mercados", "mercado municipal", "mercado de abastos"],
    "language-schools" => ["academia español extranjeros", "clases español", "escuela gallego", "cursos idiomas español", "escuela oficial idiomas"],
    "cider-houses" => ["sidrerías", "sidrería"]
  }

  # City name translations (Spanish names for search)
  @city_translations %{
    "ourense" => "ourense",
    "pontevedra" => "pontevedra",
    "santiago-de-compostela" => "santiago-de-compostela",
    "vigo" => "vigo",
    "a-coruna" => "a-coruna",
    "lugo" => "lugo"
  }

  @doc """
  Start a scraping spider with the given options.

  ## Options
    - :city - City name or slug (required)
    - :category - Category name or slug for search
    - :city_id - UUID of the city in database
    - :category_id - UUID of the category in database
  """
  def scrape(spider_name, opts \\ []) when is_atom(spider_name) do
    case Map.get(@spiders, spider_name) do
      nil ->
        {:error, "Unknown spider: #{spider_name}. Available: #{inspect(Map.keys(@spiders))}"}

      spider_module ->
        Logger.info("Starting spider #{spider_name} with opts: #{inspect(opts)}")

        case Crawly.Engine.start_spider(spider_module, opts) do
          :ok ->
            {:ok, spider_name}

          {:error, :spider_already_started} ->
            Logger.warning("Spider #{spider_name} is already running")
            {:error, :already_running}

          error ->
            error
        end
    end
  end

  @doc """
  Scrape businesses for a city and category from the database.
  Automatically translates to Spanish search terms.
  """
  def scrape_city_category(%City{} = city, %Category{} = category, spider \\ :paginas_amarillas) do
    city_search = Map.get(@city_translations, city.slug, city.slug)
    category_search = Map.get(@category_translations, category.slug, get_category_es_name(category))

    scrape(spider,
      city: city_search,
      city_id: city.id,
      category: category_search,
      category_id: category.id
    )
  end

  @doc """
  Scrape all categories for a given city.
  """
  def scrape_city(%City{} = city, spider \\ :paginas_amarillas) do
    categories = Category.list!()

    results =
      Enum.map(categories, fn category ->
        # Add some delay between starting spiders
        Process.sleep(2000)
        {category.name, scrape_city_category(city, category, spider)}
      end)

    {:ok, results}
  end

  @doc """
  Get the status of running spiders.
  """
  def status do
    Crawly.Engine.running_spiders()
  end

  @doc """
  Stop a running spider.
  """
  def stop(spider_name) when is_atom(spider_name) do
    case Map.get(@spiders, spider_name) do
      nil -> {:error, "Unknown spider"}
      spider_module -> Crawly.Engine.stop_spider(spider_module)
    end
  end

  @doc """
  Stop all running spiders.
  """
  def stop_all do
    Enum.each(@spiders, fn {_name, module} ->
      Crawly.Engine.stop_spider(module)
    end)
    :ok
  end

  @doc """
  Get available spiders.
  """
  def available_spiders, do: Map.keys(@spiders)

  @doc """
  Get Spanish category translation.
  """
  def translate_category(slug) do
    Map.get(@category_translations, slug, slug)
  end

  # =============================================================================
  # Discovery Spider — Crawl + Claude Code Extraction
  # =============================================================================

  @doc """
  Start a discovery crawl on the given seed URLs.
  Pages are saved to `tmp/discovery_crawls/<crawl_id>/` for later
  processing by Claude Code.

  ## Options
    - :crawl_id - Custom crawl ID (default: auto-generated)
    - :city_id - UUID of target city
    - :category_id - UUID of target category
    - :region_id - UUID of target region
    - :max_pages - Max pages to crawl (default: 200)

  ## Example

      Scraper.crawl_directory(["https://example.nl/bedrijven"],
        city_id: city.id, category_id: category.id, max_pages: 100)
  """
  def crawl_directory(seed_urls, opts \\ []) when is_list(seed_urls) do
    crawl_id = Keyword.get(opts, :crawl_id, generate_crawl_id())

    spider_opts = [
      seed_urls: seed_urls,
      crawl_id: crawl_id,
      max_pages: Keyword.get(opts, :max_pages, 200),
      city_id: Keyword.get(opts, :city_id),
      category_id: Keyword.get(opts, :category_id),
      region_id: Keyword.get(opts, :region_id)
    ]

    case Crawly.Engine.start_spider(DiscoverySpider, spider_opts) do
      :ok ->
        Logger.info("Discovery crawl started: #{crawl_id}")
        {:ok, crawl_id}

      {:error, :spider_already_started} ->
        Logger.warning("Discovery spider is already running")
        {:error, :already_running}

      error ->
        error
    end
  end

  defp generate_crawl_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # =============================================================================
  # Google Places API Integration (Recommended)
  # =============================================================================

  @doc """
  Search Google Places for businesses and queue for processing.
  This is the recommended method for getting high-quality business data.

  Returns an Oban job that will:
  1. Search Google Places API
  2. Save businesses to database
  3. Analyze reviews for language detection
  4. Queue website scraping (if website exists)

  ## Options
    - :bounds - {south, west, north, east} tuple for geographic restriction

  ## Example

      city = City.get_by_slug!("ourense")
      category = Category.get_by_slug!("lawyers")
      {:ok, job} = Scraper.search_google_places(city, category)

      # With bounding box restriction
      {:ok, job} = Scraper.search_google_places(city, category, bounds: {42.0, -9.0, 43.5, -7.0})
  """
  def search_google_places(%City{} = city, %Category{} = category, opts \\ []) do
    # Load region for locale detection
    city = Ash.load!(city, [:region])
    locale = get_search_locale(city.region)
    bounds = Keyword.get(opts, :bounds)

    # Get localized queries from CategoryTranslation table
    queries = get_localized_queries(category, locale, city.name)

    Logger.info("Queuing #{length(queries)} Google Places searches for #{category.name} in #{city.name} (locale: #{locale})" <>
      if(bounds, do: " with bounds", else: ""))

    jobs =
      Enum.map(queries, fn query ->
        job_args =
          %{
            query: query,
            city_id: city.id,
            category_id: category.id
          }
          |> maybe_add_bounds(bounds)

        {:ok, job} =
          job_args
          |> GooglePlacesWorker.new()
          |> Oban.insert()

        job
      end)

    {:ok, jobs}
  end

  defp maybe_add_bounds(args, nil), do: args
  defp maybe_add_bounds(args, {south, west, north, east}) do
    Map.merge(args, %{
      bounds_south: south,
      bounds_west: west,
      bounds_north: north,
      bounds_east: east
    })
  end

  @doc """
  Search Google Places with a custom query.
  """
  def search_google_places_custom(query, opts \\ []) do
    city_id = Keyword.get(opts, :city_id)
    category_id = Keyword.get(opts, :category_id)

    %{
      query: query,
      city_id: city_id,
      category_id: category_id
    }
    |> GooglePlacesWorker.new()
    |> Oban.insert()
  end

  @doc """
  Search all categories in a city via Google Places.
  Creates multiple Oban jobs.

  ## Options
    - :bounds - {south, west, north, east} tuple for geographic restriction
  """
  def search_google_places_city(%City{} = city, opts \\ []) do
    categories = Category.list!()
    bounds = Keyword.get(opts, :bounds)

    jobs =
      Enum.flat_map(categories, fn category ->
        {:ok, category_jobs} = search_google_places(city, category, bounds: bounds)
        Enum.map(category_jobs, fn job -> {category.name, job.id} end)
      end)

    {:ok, jobs}
  end

  # =============================================================================
  # OpenStreetMap / Overpass API Integration (Free)
  # =============================================================================

  @doc """
  Search OpenStreetMap via Overpass API for businesses in a city.
  Free alternative to Google Places.

  Calculates a bounding box from the city's coordinates and queues
  an Oban job for the Overpass API search.

  ## Options
    - :radius_km - Search radius in km (default: 10)

  ## Example

      city = City.get_by_slug!("ourense")
      category = Category.get_by_slug!("restaurants")
      {:ok, job} = Scraper.search_overpass(city, category)
  """
  def search_overpass(%City{} = city, %Category{} = category, opts \\ []) do
    alias GaliciaLocal.Scraper.Overpass

    unless Overpass.has_tags?(category.slug) do
      Logger.warning("No OSM tags for category: #{category.slug}")
      {:error, :no_osm_tags}
    else
      radius_km = Keyword.get(opts, :radius_km, 10)
      {south, west, north, east} = bbox_from_city(city, radius_km)

      Logger.info("Queuing Overpass search for #{category.name} in #{city.name} (#{radius_km}km radius)")

      job_args = %{
        category_slug: category.slug,
        city_id: city.id,
        category_id: category.id,
        bbox_south: south,
        bbox_west: west,
        bbox_north: north,
        bbox_east: east
      }

      {:ok, job} =
        job_args
        |> OverpassWorker.new()
        |> Oban.insert()

      {:ok, [job]}
    end
  end

  @doc """
  Search all categories with OSM tags for a city via Overpass API.

  ## Options
    - :radius_km - Search radius in km (default: 10)
  """
  def search_overpass_city(%City{} = city, opts \\ []) do
    alias GaliciaLocal.Scraper.Overpass

    categories = Category.list!()

    jobs =
      categories
      |> Enum.filter(fn cat -> Overpass.has_tags?(cat.slug) end)
      |> Enum.flat_map(fn category ->
        case search_overpass(city, category, opts) do
          {:ok, category_jobs} ->
            Enum.map(category_jobs, fn job -> {category.name, job.id} end)
          {:error, _} ->
            []
        end
      end)

    {:ok, jobs}
  end

  # Calculate bounding box from city lat/lon + radius in km
  defp bbox_from_city(city, radius_km) do
    lat = Decimal.to_float(city.latitude)
    lon = Decimal.to_float(city.longitude)

    # ~111km per degree latitude, ~85km per degree longitude at ~40°N
    lat_offset = radius_km / 111.0
    lon_offset = radius_km / (111.0 * :math.cos(lat * :math.pi() / 180))

    {lat - lat_offset, lon - lon_offset, lat + lat_offset, lon + lon_offset}
  end

  @doc """
  Get Oban job status for scraper queue.
  """
  def job_status do
    import Ecto.Query

    GaliciaLocal.Repo.all(
      from j in Oban.Job,
        where: j.queue == "scraper",
        where: j.state in ["available", "executing", "scheduled"],
        select: %{id: j.id, state: j.state, args: j.args, inserted_at: j.inserted_at}
    )
  end

  # =============================================================================
  # Localization Helpers
  # =============================================================================

  @doc """
  Get the search locale for a region.
  Uses the first non-English locale, falling back to default_locale.
  """
  def get_search_locale(region) do
    region.supported_locales
    |> Enum.find(fn l -> l != "en" end)
    |> Kernel.||(region.default_locale)
  end

  @doc """
  Get localized search queries for a category and locale.
  Falls back to hardcoded translations if no database translation exists.
  """
  def get_localized_queries(category, locale, city_name) do
    case CategoryTranslation.get_for_category_locale(category.id, locale) do
      {:ok, translation} when not is_nil(translation) ->
        if translation.search_queries != nil and translation.search_queries != [] do
          Enum.map(translation.search_queries, &"#{&1} #{city_name}")
        else
          get_fallback_queries(category, city_name)
        end

      _ ->
        get_fallback_queries(category, city_name)
    end
  end

  defp get_fallback_queries(category, city_name) do
    cond do
      category.search_queries != nil and category.search_queries != [] ->
        Enum.map(category.search_queries, fn sq -> "#{sq} #{city_name}" end)

      Map.has_key?(@category_sub_queries, category.slug) ->
        Enum.map(@category_sub_queries[category.slug], fn sq -> "#{sq} #{city_name}" end)

      true ->
        category_es =
          category.search_translation ||
            Map.get(@category_translations, category.slug, get_category_es_name(category))

        ["#{category_es} #{city_name}"]
    end
  end

  defp get_category_es_name(category) do
    case GaliciaLocal.Directory.CategoryTranslation.get_for_category_locale(category.id, "es") do
      {:ok, %{name: name}} when is_binary(name) and name != "" -> name
      _ -> category.slug
    end
  end
end
