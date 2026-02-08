defmodule GaliciaLocal.Scraper.Workers.WebsiteCrawlWorker do
  @moduledoc """
  Oban worker for crawling business websites using Req and Floki.

  This is Step 2 of the data pipeline:
  1. Google Places API → Get business data
  2. Website Crawling → Extract full website content
  3. Web Search → Gather external sources
  4. LLM Enrichment → Deep analysis

  ## Usage

      %{business_id: "uuid"}
      |> GaliciaLocal.Scraper.Workers.WebsiteCrawlWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :research,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args, :queue, :worker]]

  require Logger

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocal.Scraper.Workers.WebSearchWorker

  @research_dir "priv/research"
  @max_pages 20
  @english_patterns ["/en/", "/en-", "/english/", "?lang=en", "&lang=en", "/en.html"]

  # Pages we want to crawl first (high-value content)
  @priority_patterns [
    {"about", 10},
    {"sobre", 10},
    {"over-ons", 10},
    {"quem-somos", 10},
    {"menu", 9},
    {"carta", 9},
    {"ementa", 9},
    {"menukaart", 9},
    {"services", 8},
    {"servicios", 8},
    {"servicos", 8},
    {"diensten", 8},
    {"contact", 7},
    {"contacto", 7},
    {"kontakt", 7},
    {"team", 6},
    {"equipo", 6},
    {"equipa", 6},
    {"history", 5},
    {"historia", 5},
    {"geschiedenis", 5},
    {"gallery", 4},
    {"galeria", 4},
    {"photos", 4},
    {"fotos", 4},
    {"prices", 3},
    {"precios", 3},
    {"precos", 3},
    {"prijzen", 3},
    {"hours", 3},
    {"horario", 3},
    {"openingstijden", 3},
    {"reviews", 2},
    {"testimonials", 2},
    {"opiniones", 2}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"business_id" => business_id}}) do
    Logger.info("Starting website crawl for business: #{business_id}")

    with {:ok, business} <- load_business(business_id),
         {:ok, _} <- update_status(business, :researching),
         :ok <- ensure_research_dir(business_id),
         {:ok, results} <- crawl_website(business),
         :ok <- save_results(business_id, results) do
      Logger.info("Website crawl complete for #{business.name}: #{results.pages_crawled} pages")

      # Queue web search worker
      queue_web_search(business_id)

      :ok
    else
      {:error, :no_website} ->
        Logger.info("No website for business #{business_id}, skipping to web search")
        queue_web_search(business_id)
        :ok

      {:error, reason} ->
        Logger.error("Website crawl failed for #{business_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_business(business_id) do
    case Business.get_by_id(business_id, load: [:city, :category]) do
      {:ok, business} -> {:ok, business}
      {:error, _} -> {:error, :business_not_found}
    end
  end

  defp update_status(business, status) do
    business
    |> Ash.Changeset.for_update(:update, %{status: status})
    |> Ash.update()
  end

  defp crawl_website(%{website: nil}), do: {:error, :no_website}
  defp crawl_website(%{website: ""}), do: {:error, :no_website}

  defp crawl_website(business) do
    url = normalize_url(business.website)
    Logger.info("Crawling website: #{url}")

    case crawl_pages(url) do
      {:ok, pages} ->
        has_english = detect_english_version(pages)

        # Aggregate structured data from all pages
        all_structured =
          pages
          |> Enum.flat_map(fn p -> p.structured_data || [] end)
          |> Enum.uniq()

        # Aggregate social proof from all pages
        all_testimonials =
          pages
          |> Enum.flat_map(fn p -> (p.social_proof && p.social_proof.testimonials) || [] end)
          |> Enum.uniq()
          |> Enum.take(10)

        all_awards =
          pages
          |> Enum.flat_map(fn p -> (p.social_proof && p.social_proof.awards) || [] end)
          |> Enum.uniq()
          |> Enum.take(10)

        results = %{
          pages_crawled: length(pages),
          has_english_version: has_english,
          total_content_length: Enum.reduce(pages, 0, &(&1.content_length + &2)),
          metadata: extract_metadata(pages),
          structured_data: if(all_structured == [], do: nil, else: all_structured),
          social_proof:
            if(all_testimonials == [] and all_awards == [],
              do: nil,
              else: %{testimonials: all_testimonials, awards: all_awards}
            ),
          pages: pages
        }

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp crawl_pages(start_url) do
    uri = URI.parse(start_url)

    # Start with the main page
    case fetch_and_parse(start_url) do
      {:ok, main_page} ->
        # Track seen URLs to avoid duplicates
        seen = MapSet.new([normalize_url_for_dedup(start_url), normalize_url_for_dedup(main_page.url)])

        # Find internal links, prioritizing high-value pages
        internal_links =
          main_page.links
          |> Enum.filter(&same_host?(&1, uri.host))
          |> Enum.reject(&skip_url?/1)
          |> Enum.map(&normalize_url_for_dedup/1)
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))
          |> Enum.sort_by(&page_priority/1, :desc)
          |> Enum.take(@max_pages - 1)

        # Crawl additional pages
        additional_pages =
          internal_links
          |> Enum.map(fn link ->
            Process.sleep(500)  # Be polite
            fetch_and_parse(link)
          end)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, page} -> page end)

        {:ok, [main_page | additional_pages]}

      {:error, reason} ->
        Logger.warning("Failed to fetch main page #{start_url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Normalize URL for deduplication (remove trailing slash, fragment)
  defp normalize_url_for_dedup(url) do
    url
    |> String.split("#")
    |> List.first()
    |> String.trim_trailing("/")
  end

  defp fetch_and_parse(url) do
    case Req.get(url,
      receive_timeout: 15_000,
      redirect: true,
      max_redirects: 5,
      headers: [{"user-agent", "Mozilla/5.0 (compatible; GaliciaLocalBot/1.0)"}]
    ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        parse_page(url, body)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_page(url, html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        content = extract_content(document)

        page = %{
          url: url,
          title: extract_title(document),
          description: extract_description(document),
          language: extract_language(document),
          content: content,
          content_length: String.length(content),
          headings: extract_headings(document),
          links: extract_links(document, url),
          structured_data: extract_structured_data(document),
          social_proof: extract_social_proof(document)
        }

        {:ok, page}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp extract_title(document) do
    document
    |> Floki.find("title")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_description(document) do
    document
    |> Floki.find("meta[name='description']")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_language(document) do
    document
    |> Floki.find("html")
    |> Floki.attribute("lang")
    |> List.first()
  end

  defp extract_content(document) do
    document
    |> Floki.filter_out("script")
    |> Floki.filter_out("style")
    |> Floki.filter_out("nav")
    |> Floki.filter_out("footer")
    |> Floki.filter_out("header")
    |> Floki.filter_out("aside")
    |> Floki.filter_out("noscript")
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_headings(document) do
    document
    |> Floki.find("h1, h2, h3")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(20)
  end

  defp extract_links(document, base_url) do
    uri = URI.parse(base_url)
    base = "#{uri.scheme}://#{uri.host}"

    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> Enum.map(&normalize_link(&1, base))
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&skip_url?/1)
    |> Enum.uniq()
  end

  # Extract schema.org JSON-LD structured data
  defp extract_structured_data(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.map(&script_text/1)
    |> Enum.flat_map(fn json_text ->
      case Jason.decode(json_text) do
        {:ok, data} when is_list(data) -> data
        {:ok, %{"@graph" => graph}} when is_list(graph) -> graph
        {:ok, data} when is_map(data) -> [data]
        _ -> []
      end
    end)
    |> Enum.filter(&relevant_schema_type?/1)
    |> Enum.map(&extract_schema_fields/1)
    |> case do
      [] -> nil
      items -> items
    end
  end

  # Floki.text/1 returns "" for script tags; extract from children directly
  defp script_text({_tag, _attrs, children}) do
    children
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
  end

  defp script_text(_), do: ""

  @relevant_types ~w(
    LocalBusiness Restaurant Bar CafeOrCoffeeShop Bakery
    FoodEstablishment Store AutoRepair BeautySalon
    HealthAndBeautyBusiness LegalService FinancialService
    MedicalBusiness Dentist Physician Pharmacy
    LodgingBusiness Hotel ProfessionalService
    SportsActivityLocation FitnessCenter
    Organization Place TouristAttraction
  )

  defp relevant_schema_type?(%{"@type" => type}) when is_binary(type) do
    type in @relevant_types
  end

  defp relevant_schema_type?(%{"@type" => types}) when is_list(types) do
    Enum.any?(types, &(&1 in @relevant_types))
  end

  defp relevant_schema_type?(_), do: false

  defp extract_schema_fields(data) do
    data
    |> Map.take([
      "@type",
      "name",
      "description",
      "priceRange",
      "servesCuisine",
      "openingHours",
      "openingHoursSpecification",
      "telephone",
      "email",
      "address",
      "geo",
      "aggregateRating",
      "review",
      "menu",
      "acceptsReservations",
      "paymentAccepted",
      "amenityFeature",
      "hasMap"
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Extract social proof: testimonials, awards, certifications
  defp extract_social_proof(document) do
    testimonials = extract_testimonials(document)
    awards = extract_awards(document)

    if testimonials == [] and awards == [] do
      nil
    else
      %{testimonials: testimonials, awards: awards}
    end
  end

  defp extract_testimonials(document) do
    # Look for common testimonial patterns
    selectors = [
      "[class*='testimonial']",
      "[class*='review']",
      "[class*='opinion']",
      "[class*='resena']",
      "blockquote"
    ]

    selectors
    |> Enum.flat_map(fn selector ->
      document
      |> Floki.find(selector)
      |> Enum.map(&Floki.text/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.length(&1) < 20))
      |> Enum.map(&String.slice(&1, 0, 500))
    end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp extract_awards(document) do
    award_patterns = ~r/(?i)(award|prize|certif|michelin|star|recognition|accolade|premio|certificad|galardón|reconocimiento|prijs|onderscheiding)/

    # Check headings and image alts for award mentions
    headings =
      document
      |> Floki.find("h1, h2, h3, h4, h5, h6")
      |> Enum.map(&Floki.text/1)
      |> Enum.filter(&Regex.match?(award_patterns, &1))
      |> Enum.map(&String.trim/1)

    img_alts =
      document
      |> Floki.find("img")
      |> Floki.attribute("alt")
      |> Enum.filter(&(is_binary(&1) and Regex.match?(award_patterns, &1)))

    (headings ++ img_alts)
    |> Enum.uniq()
    |> Enum.take(10)
  end

  # Score links by priority - high-value pages first
  defp page_priority(url) do
    url_lower = String.downcase(url)

    @priority_patterns
    |> Enum.find_value(0, fn {pattern, score} ->
      if String.contains?(url_lower, pattern), do: score
    end)
  end

  defp normalize_link(nil, _base), do: nil
  defp normalize_link("", _base), do: nil
  defp normalize_link("#" <> _, _base), do: nil
  defp normalize_link("javascript:" <> _, _base), do: nil
  defp normalize_link("mailto:" <> _, _base), do: nil
  defp normalize_link("tel:" <> _, _base), do: nil

  defp normalize_link(url, base) do
    cond do
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      String.starts_with?(url, "/") -> base <> url
      true -> nil
    end
  end

  defp same_host?(url, host) do
    case URI.parse(url) do
      %URI{host: ^host} -> true
      _ -> false
    end
  end

  defp skip_url?(url) do
    skip_extensions = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".css", ".js", ".ico"]
    skip_patterns = ["/wp-admin", "/wp-login", "/admin", "/login", "/cart", "/checkout", "/error", "/404", "/500"]

    Enum.any?(skip_extensions, &String.ends_with?(url, &1)) ||
      Enum.any?(skip_patterns, &String.contains?(url, &1))
  end

  defp detect_english_version(pages) do
    Enum.any?(pages, fn page ->
      # Check URL for English patterns
      url_has_english = Enum.any?(@english_patterns, &String.contains?(page.url, &1))

      # Check language attribute
      lang_is_english = page.language && String.starts_with?(to_string(page.language), "en")

      url_has_english || lang_is_english
    end)
  end

  defp extract_metadata(pages) do
    main_page = List.first(pages) || %{}

    %{
      title: main_page[:title],
      description: main_page[:description],
      languages_detected:
        pages
        |> Enum.map(& &1[:language])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp normalize_url(url) do
    cond do
      String.starts_with?(url, "http://") -> url
      String.starts_with?(url, "https://") -> url
      true -> "https://" <> url
    end
  end

  defp ensure_research_dir(business_id) do
    dir = Path.join([@research_dir, business_id])

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp save_results(business_id, results) do
    path = Path.join([@research_dir, business_id, "website.json"])

    data = %{
      crawled_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      pages_crawled: results.pages_crawled,
      has_english_version: results.has_english_version,
      total_content_length: results.total_content_length,
      metadata: results.metadata,
      structured_data: results.structured_data,
      social_proof: results.social_proof,
      pages:
        Enum.map(results.pages, fn page ->
          %{
            url: page.url,
            title: page.title,
            description: page.description,
            language: page.language,
            content_length: page.content_length,
            headings: page.headings,
            content: String.slice(page.content || "", 0, 10_000)
          }
        end)
    }

    case File.write(path, Jason.encode!(data, pretty: true)) do
      :ok ->
        Logger.info("Saved website crawl results to #{path}")
        :ok

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  defp queue_web_search(business_id) do
    %{business_id: business_id}
    |> WebSearchWorker.new()
    |> Oban.insert()
  end

  @doc """
  Returns the path to the research directory for a business.
  """
  def research_path(business_id) do
    Path.join([@research_dir, business_id])
  end

  @doc """
  Returns the path to the website crawl results file.
  """
  def website_results_path(business_id) do
    Path.join([research_path(business_id), "website.json"])
  end

  @doc """
  Loads the website crawl results for a business if they exist.
  """
  def load_website_results(business_id) do
    path = website_results_path(business_id)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
