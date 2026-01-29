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

    # Crawl the website starting from the main URL
    case crawl_pages(url) do
      {:ok, pages} ->
        has_english = detect_english_version(pages)

        results = %{
          pages_crawled: length(pages),
          has_english_version: has_english,
          total_content_length: Enum.reduce(pages, 0, &(&1.content_length + &2)),
          metadata: extract_metadata(pages),
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

        # Find internal links (excluding already seen and error pages)
        internal_links =
          main_page.links
          |> Enum.filter(&same_host?(&1, uri.host))
          |> Enum.reject(&skip_url?/1)
          |> Enum.map(&normalize_url_for_dedup/1)
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))
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
        page = %{
          url: url,
          title: extract_title(document),
          description: extract_description(document),
          language: extract_language(document),
          content: extract_content(document),
          content_length: 0,
          headings: extract_headings(document),
          links: extract_links(document, url)
        }

        page = %{page | content_length: String.length(page.content)}
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
