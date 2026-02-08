defmodule GaliciaLocal.Scraper.Spiders.DiscoverySpider do
  @moduledoc """
  Generic discovery spider that crawls any website and saves raw page content
  to files for later extraction by Claude Code.

  This spider does NOT parse business data — it saves pages as-is.
  Claude Code processes the saved pages to extract structured business listings.

  ## Usage

      Crawly.Engine.start_spider(__MODULE__,
        seed_urls: ["https://example.nl/bedrijven"],
        crawl_id: "abc123",
        max_pages: 100
      )

  Pages are saved to `tmp/discovery_crawls/<crawl_id>/page_NNNN.json`.
  """

  use Crawly.Spider

  require Logger

  @default_max_pages 200

  @impl Crawly.Spider
  def base_url do
    context = get_context()
    context[:base_url] || "https://example.com"
  end

  @impl Crawly.Spider
  def init(opts) do
    seed_urls = Keyword.fetch!(opts, :seed_urls)
    crawl_id = Keyword.get(opts, :crawl_id, generate_crawl_id())
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)

    # Parse base URL from first seed, collect all hosts for multi-domain crawling
    uri = URI.parse(List.first(seed_urls))
    base_url = "#{uri.scheme}://#{uri.host}"

    allowed_hosts =
      seed_urls
      |> Enum.map(&URI.parse/1)
      |> Enum.map(& &1.host)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    context = %{
      crawl_id: crawl_id,
      base_url: base_url,
      host: uri.host,
      allowed_hosts: allowed_hosts,
      max_pages: max_pages,
      pages_crawled: 0,
      city_id: Keyword.get(opts, :city_id),
      category_id: Keyword.get(opts, :category_id),
      region_id: Keyword.get(opts, :region_id)
    }

    :persistent_term.put({__MODULE__, :context}, context)

    # Write metadata file
    meta_dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)
    File.mkdir_p!(meta_dir)

    metadata = %{
      crawl_id: crawl_id,
      seed_urls: seed_urls,
      max_pages: max_pages,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      city_id: context.city_id,
      category_id: context.category_id,
      region_id: context.region_id
    }

    File.write!(
      Path.join(meta_dir, "metadata.json"),
      Jason.encode!(metadata, pretty: true)
    )

    # Create DB record for tracking
    GaliciaLocal.Directory.DiscoveryCrawl.create(%{
      crawl_id: crawl_id,
      seed_urls: seed_urls,
      max_pages: max_pages,
      city_id: context.city_id,
      region_id: context.region_id
    })

    Logger.info("Starting DiscoverySpider [#{crawl_id}]: #{length(seed_urls)} seed URLs, max #{max_pages} pages")

    [start_urls: seed_urls]
  end

  @impl Crawly.Spider
  def parse_item(response) do
    context = get_context()

    if context.pages_crawled >= context.max_pages do
      Logger.info("[#{context.crawl_id}] Reached max pages (#{context.max_pages})")
      %Crawly.ParsedItem{items: [], requests: []}
    else
      parse_page(response, context)
    end
  end

  defp parse_page(response, context) do
    case Floki.parse_document(response.body) do
      {:ok, document} ->
        # Extract page content
        page_data = extract_page_content(response.request_url, document)

        # Find internal links to follow (on any allowed host)
        requests = find_internal_links(document, context.base_url, context.allowed_hosts)

        # Skip pages with no meaningful content (JS-rendered SPAs return empty HTML)
        if page_data.content_length < 50 do
          Logger.info("[#{context.crawl_id}] Skipping empty page: #{response.request_url}")

          %Crawly.ParsedItem{items: [], requests: requests}
        else
          # Update counter only for pages with content
          updated_context = %{context | pages_crawled: context.pages_crawled + 1}
          :persistent_term.put({__MODULE__, :context}, updated_context)

          Logger.info(
            "[#{context.crawl_id}] Page #{updated_context.pages_crawled}: #{response.request_url} " <>
              "(#{page_data.content_length} chars, #{length(requests)} links)"
          )

          # Add crawl_id so the SaveToFile pipeline knows where to write
          item = Map.put(page_data, :crawl_id, context.crawl_id)

          %Crawly.ParsedItem{items: [item], requests: requests}
        end

      {:error, reason} ->
        Logger.warning("[#{context.crawl_id}] Failed to parse #{response.request_url}: #{inspect(reason)}")
        %Crawly.ParsedItem{items: [], requests: []}
    end
  end

  defp extract_page_content(url, document) do
    title =
      document
      |> Floki.find("title")
      |> Floki.text()
      |> String.trim()

    description =
      document
      |> Floki.find("meta[name='description']")
      |> Floki.attribute("content")
      |> List.first()

    content =
      document
      |> remove_non_content_elements()
      |> Floki.text(sep: " ")
      |> clean_text()
      |> String.slice(0, 50_000)

    headings =
      document
      |> Floki.find("h1, h2, h3")
      |> Enum.map(&Floki.text/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(30)

    lang =
      document
      |> Floki.find("html")
      |> Floki.attribute("lang")
      |> List.first()

    %{
      url: url,
      title: title,
      meta_description: description,
      content: content,
      headings: headings,
      language: lang,
      content_length: String.length(content)
    }
  end

  defp remove_non_content_elements(document) do
    document
    |> Floki.filter_out("script")
    |> Floki.filter_out("style")
    |> Floki.filter_out("nav")
    |> Floki.filter_out("footer")
    |> Floki.filter_out("header")
    |> Floki.filter_out("aside")
    |> Floki.filter_out("noscript")
    |> Floki.filter_out("[role='navigation']")
    |> Floki.filter_out("[role='banner']")
    |> Floki.filter_out("[role='contentinfo']")
  end

  defp clean_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\n+/, "\n")
    |> String.trim()
  end

  defp find_internal_links(document, base_url, allowed_hosts) do
    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> Enum.map(&normalize_url(&1, base_url))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&allowed_host?(&1, allowed_hosts))
    |> Enum.reject(&skip_url?/1)
    |> Enum.uniq()
    |> Enum.take(30)
    |> Enum.map(&Crawly.Utils.request_from_url/1)
  end

  defp normalize_url(nil, _base), do: nil
  defp normalize_url("", _base), do: nil
  defp normalize_url("#" <> _, _base), do: nil
  defp normalize_url("javascript:" <> _, _base), do: nil
  defp normalize_url("mailto:" <> _, _base), do: nil
  defp normalize_url("tel:" <> _, _base), do: nil

  defp normalize_url(url, base_url) do
    cond do
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      String.starts_with?(url, "/") -> base_url <> url
      true -> nil
    end
  end

  defp allowed_host?(url, allowed_hosts) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host in allowed_hosts
      _ -> false
    end
  end

  defp skip_url?(url) do
    skip_extensions = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".css", ".js", ".ico", ".xml", ".zip"]
    skip_patterns = ["/wp-admin", "/wp-login", "/admin", "/login", "/cart", "/checkout", "/feed", "/rss"]

    Enum.any?(skip_extensions, &String.ends_with?(url, &1)) ||
      Enum.any?(skip_patterns, &String.contains?(url, &1))
  end

  defp get_context do
    :persistent_term.get({__MODULE__, :context}, %{
      crawl_id: "unknown",
      base_url: "https://example.com",
      host: "example.com",
      allowed_hosts: ["example.com"],
      max_pages: @default_max_pages,
      pages_crawled: 0
    })
  end

  defp generate_crawl_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @doc "Get current crawl progress"
  def progress do
    context = get_context()
    %{crawl_id: context.crawl_id, pages_crawled: context.pages_crawled, max_pages: context.max_pages}
  end

  @doc "Clear spider context after crawl completes"
  def clear_context do
    :persistent_term.erase({__MODULE__, :context})
  end

  @impl Crawly.Spider
  def override_settings do
    [
      closespider_itemcount: @default_max_pages,
      concurrent_requests_per_domain: 1,
      follow_redirects: true,
      # Use non-integer to disable Crawly's closespider_timeout check.
      # The guard `when current <= limit and is_integer(limit)` won't match.
      closespider_timeout: :disabled,
      middlewares: [
        # No DomainFilter — we allow multiple seed domains and filter in find_internal_links
        Crawly.Middlewares.UniqueRequest,
        {Crawly.Middlewares.UserAgent,
         user_agents: [
           "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
         ]},
        {Crawly.Middlewares.RequestOptions, [timeout: 30_000, recv_timeout: 30_000]}
      ],
      pipelines: [
        {Crawly.Pipelines.Validate, fields: [:url, :content, :crawl_id]},
        GaliciaLocal.Scraper.Pipelines.SaveToFile
      ]
    ]
  end
end
