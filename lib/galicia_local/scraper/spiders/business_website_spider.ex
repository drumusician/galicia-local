defmodule GaliciaLocal.Scraper.Spiders.BusinessWebsiteSpider do
  @moduledoc """
  Crawly spider for crawling business websites to extract content for LLM enrichment.

  This spider crawls all pages within a business's website domain, extracting
  text content and detecting English language versions.

  ## Usage

      # Start the spider with a business website
      Crawly.Engine.start_spider(__MODULE__, url: "https://example.com", business_id: "uuid")

  The spider stores results via the callback module specified in options.
  """

  use Crawly.Spider

  require Logger

  @max_pages 50
  @english_patterns ["/en/", "/en-", "/english/", "?lang=en", "&lang=en", "/en.html"]

  @impl Crawly.Spider
  def base_url do
    context = get_context()
    context[:base_url] || "https://example.com"
  end

  @impl Crawly.Spider
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    business_id = Keyword.fetch!(opts, :business_id)

    # Parse the base URL for domain filtering
    uri = URI.parse(url)
    base_url = "#{uri.scheme}://#{uri.host}"

    # Store context for later use
    context = %{
      business_id: business_id,
      base_url: base_url,
      host: uri.host,
      pages_crawled: 0,
      pages: [],
      has_english_version: false,
      metadata: %{
        title: nil,
        description: nil,
        languages_detected: []
      }
    }

    :persistent_term.put({__MODULE__, :context}, context)

    Logger.info("Starting BusinessWebsiteSpider for #{url} (business: #{business_id})")

    [start_urls: [url]]
  end

  @impl Crawly.Spider
  def parse_item(response) do
    context = get_context()

    # Check if we've hit the page limit
    if context.pages_crawled >= @max_pages do
      Logger.info("Reached max pages (#{@max_pages}) for #{context.host}")
      %Crawly.ParsedItem{items: [], requests: []}
    else
      parse_page(response, context)
    end
  end

  defp parse_page(response, context) do
    {:ok, document} = Floki.parse_document(response.body)

    # Extract page content
    page_data = extract_page_content(response.request_url, document)

    # Check for English version
    has_english = detect_english_version(response.request_url, document)

    # Update context
    updated_context = %{
      context
      | pages_crawled: context.pages_crawled + 1,
        pages: [page_data | context.pages],
        has_english_version: context.has_english_version || has_english,
        metadata: merge_metadata(context.metadata, page_data)
    }

    :persistent_term.put({__MODULE__, :context}, updated_context)

    # Find internal links to crawl
    requests = find_internal_links(document, context.base_url, context.host)

    Logger.debug(
      "Crawled page #{context.pages_crawled + 1}: #{response.request_url} (#{length(requests)} new links)"
    )

    # Return the page data as an item
    %Crawly.ParsedItem{
      items: [page_data],
      requests: requests
    }
  end

  defp extract_page_content(url, document) do
    # Extract title
    title =
      document
      |> Floki.find("title")
      |> Floki.text()
      |> String.trim()

    # Extract meta description
    description =
      document
      |> Floki.find("meta[name='description']")
      |> Floki.attribute("content")
      |> List.first()

    # Extract main content (remove scripts, styles, nav, footer)
    content =
      document
      |> remove_non_content_elements()
      |> Floki.text(sep: " ")
      |> clean_text()

    # Extract headings for structure
    headings =
      document
      |> Floki.find("h1, h2, h3")
      |> Enum.map(&Floki.text/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(20)

    # Detect language from html lang attribute
    lang =
      document
      |> Floki.find("html")
      |> Floki.attribute("lang")
      |> List.first()

    %{
      url: url,
      title: title,
      description: description,
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

  defp detect_english_version(url, document) do
    # Check URL for English patterns
    url_has_english = Enum.any?(@english_patterns, &String.contains?(url, &1))

    # Check for language switcher links
    language_links =
      document
      |> Floki.find("a[hreflang='en'], a[href*='/en/'], a[href*='/english/']")
      |> length()

    # Check html lang attribute
    lang =
      document
      |> Floki.find("html")
      |> Floki.attribute("lang")
      |> List.first()
      |> to_string()

    lang_is_english = String.starts_with?(lang, "en")

    url_has_english || language_links > 0 || lang_is_english
  end

  defp find_internal_links(document, base_url, host) do
    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> Enum.map(&normalize_url(&1, base_url))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&same_host?(&1, host))
    |> Enum.reject(&skip_url?/1)
    |> Enum.uniq()
    |> Enum.take(20)
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

  defp same_host?(url, host) do
    case URI.parse(url) do
      %URI{host: ^host} -> true
      _ -> false
    end
  end

  defp skip_url?(url) do
    skip_extensions = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".css", ".js", ".ico"]
    skip_patterns = ["/wp-admin", "/wp-login", "/admin", "/login", "/cart", "/checkout"]

    Enum.any?(skip_extensions, &String.ends_with?(url, &1)) ||
      Enum.any?(skip_patterns, &String.contains?(url, &1))
  end

  defp merge_metadata(existing, page_data) do
    %{
      title: existing.title || page_data.title,
      description: existing.description || page_data.description,
      languages_detected:
        (existing.languages_detected ++ [page_data.language])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp get_context do
    :persistent_term.get({__MODULE__, :context}, %{
      business_id: nil,
      base_url: "https://example.com",
      host: "example.com",
      pages_crawled: 0,
      pages: [],
      has_english_version: false,
      metadata: %{}
    })
  end

  @doc """
  Returns the final crawl results after the spider has finished.
  Call this after the spider completes to get aggregated data.
  """
  def get_results do
    context = get_context()

    %{
      business_id: context.business_id,
      pages_crawled: context.pages_crawled,
      has_english_version: context.has_english_version,
      metadata: context.metadata,
      pages: Enum.reverse(context.pages),
      total_content_length: Enum.reduce(context.pages, 0, &(&1.content_length + &2))
    }
  end

  @doc """
  Clears the spider context. Call after retrieving results.
  """
  def clear_context do
    :persistent_term.erase({__MODULE__, :context})
  end

  @impl Crawly.Spider
  def override_settings do
    [
      closespider_itemcount: @max_pages,
      concurrent_requests_per_domain: 2,
      follow_redirects: true,
      closespider_timeout: 60
    ]
  end
end
