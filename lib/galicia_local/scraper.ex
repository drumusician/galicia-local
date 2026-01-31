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

  alias GaliciaLocal.Directory.{City, Category}
  alias GaliciaLocal.Scraper.Spiders.PaginasAmarillas
  alias GaliciaLocal.Scraper.Workers.GooglePlacesWorker

  @spiders %{
    paginas_amarillas: PaginasAmarillas
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
    "language-schools" => "academias idiomas"
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
    "language-schools" => ["academias idiomas", "escuela idiomas", "clases inglés"],
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
    category_search = Map.get(@category_translations, category.slug, category.name_es || category.slug)

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

  ## Example

      city = City.get_by_slug!("ourense")
      category = Category.get_by_slug!("lawyers")
      {:ok, job} = Scraper.search_google_places(city, category)
  """
  def search_google_places(%City{} = city, %Category{} = category) do
    sub_queries = Map.get(@category_sub_queries, category.slug, [])

    queries =
      if sub_queries == [] do
        # Fallback: single query with Spanish translation
        category_es = Map.get(@category_translations, category.slug, category.name_es || category.slug)
        ["#{category_es} #{city.name}"]
      else
        Enum.map(sub_queries, fn sq -> "#{sq} #{city.name}" end)
      end

    Logger.info("Queuing #{length(queries)} Google Places searches for #{category.name} in #{city.name}")

    jobs =
      Enum.map(queries, fn query ->
        {:ok, job} =
          %{
            query: query,
            city_id: city.id,
            category_id: category.id
          }
          |> GooglePlacesWorker.new()
          |> Oban.insert()

        job
      end)

    {:ok, jobs}
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
  """
  def search_google_places_city(%City{} = city) do
    categories = Category.list!()

    jobs =
      Enum.flat_map(categories, fn category ->
        {:ok, category_jobs} = search_google_places(city, category)
        Enum.map(category_jobs, fn job -> {category.name, job.id} end)
      end)

    {:ok, jobs}
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
end
