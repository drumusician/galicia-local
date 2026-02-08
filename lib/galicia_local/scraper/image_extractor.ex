defmodule GaliciaLocal.Scraper.ImageExtractor do
  @moduledoc """
  Extracts image URLs from business websites.

  Fetches the HTML of a website and extracts meaningful images:
  1. Open Graph image (og:image meta tag)
  2. Twitter card image (twitter:image meta tag)
  3. Large images from <img> tags (filtered for quality)

  Returns up to 5 image URLs, prioritizing og:image first.
  """

  require Logger

  @request_timeout 15_000
  @max_body_size 2_000_000
  @max_images 5
  @min_dimension 200

  # Patterns that indicate non-content images (logos, icons, tracking pixels, etc.)
  @skip_patterns [
    "logo",
    "icon",
    "favicon",
    "sprite",
    "pixel",
    "tracking",
    "badge",
    "banner-ad",
    "advertisement",
    "widget",
    "button",
    "arrow",
    "spacer",
    "blank",
    "1x1",
    "avatar",
    "gravatar",
    "emoji",
    "social",
    "facebook",
    "twitter",
    "instagram",
    "linkedin",
    "pinterest",
    "youtube",
    "google",
    "analytics",
    "cloudflare",
    "statcounter",
    "doubleclick",
    "adsense",
    "hotjar"
  ]

  # File extensions that are typically not photos
  @skip_extensions [".svg", ".gif", ".ico", ".webp"]

  @doc """
  Extract image URLs from a website.
  Returns `{:ok, [url_string]}` or `{:error, reason}`.
  """
  def extract_images(website_url) when is_binary(website_url) do
    url = normalize_url(website_url)

    case fetch_html(url) do
      {:ok, html, final_url} ->
        images =
          []
          |> add_og_images(html, final_url)
          |> add_body_images(html, final_url)
          |> Enum.uniq()
          |> Enum.take(@max_images)

        {:ok, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract_images(_), do: {:error, :invalid_url}

  # --- HTML Fetching ---

  defp fetch_html(url) do
    case Req.get(url,
           receive_timeout: @request_timeout,
           max_retries: 0,
           redirect: true,
           max_redirects: 5,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (compatible; StartLocalBot/1.0; +https://startlocal.app)"},
             {"accept", "text/html,application/xhtml+xml"}
           ]
         ) do
      {:ok, %{status: status, body: body, headers: headers}} when status in 200..299 ->
        content_type = get_header(headers, "content-type")

        if is_binary(body) and html_content?(content_type) do
          html = truncate_body(body)
          {:ok, html, url}
        else
          {:error, :not_html}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_header(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp get_header(headers, name) when is_list(headers) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> value
      nil -> ""
    end
  end

  defp html_content?(content_type), do: String.contains?(content_type, "html")

  defp truncate_body(body) when byte_size(body) > @max_body_size,
    do: binary_part(body, 0, @max_body_size)

  defp truncate_body(body), do: body

  # --- OG / Meta Images ---

  defp add_og_images(images, html, base_url) do
    og_urls =
      Regex.scan(
        ~r/<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']/i,
        html
      )
      |> Enum.concat(
        Regex.scan(
          ~r/<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["'](?:og:image|twitter:image)["']/i,
          html
        )
      )
      |> Enum.map(fn [_, url] -> resolve_url(url, base_url) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&skip_url?/1)

    images ++ og_urls
  end

  # --- Body Images ---

  defp add_body_images(images, html, base_url) do
    body_urls =
      Regex.scan(~r/<img[^>]+src=["']([^"']+)["'][^>]*>/i, html)
      |> Enum.map(fn match ->
        url = Enum.at(match, 1)
        full_tag = Enum.at(match, 0)
        {url, full_tag}
      end)
      |> Enum.reject(fn {url, tag} -> skip_url?(url) or skip_tag?(tag) end)
      |> Enum.sort_by(fn {_url, tag} -> image_score(tag) end, :desc)
      |> Enum.map(fn {url, _tag} -> resolve_url(url, base_url) end)
      |> Enum.reject(&is_nil/1)

    images ++ body_urls
  end

  # --- URL Resolution ---

  defp resolve_url(url, base_url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      String.starts_with?(url, "//") ->
        "https:" <> url

      String.starts_with?(url, "/") ->
        case URI.parse(base_url) do
          %URI{scheme: scheme, host: host} when not is_nil(host) ->
            "#{scheme}://#{host}#{url}"

          _ ->
            nil
        end

      String.starts_with?(url, "data:") ->
        nil

      true ->
        # Relative URL
        base = String.replace(base_url, ~r/[^\/]+$/, "")
        base <> url
    end
  end

  defp normalize_url(url) do
    url = String.trim(url)

    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") -> url
      true -> "https://" <> url
    end
  end

  # --- Filtering ---

  defp skip_url?(url) do
    url_lower = String.downcase(url)

    Enum.any?(@skip_patterns, &String.contains?(url_lower, &1)) or
      Enum.any?(@skip_extensions, &String.ends_with?(url_lower, &1)) or
      String.contains?(url_lower, "data:image")
  end

  defp skip_tag?(tag) do
    tag_lower = String.downcase(tag)

    # Skip images with very small explicit dimensions
    case extract_dimensions(tag_lower) do
      {w, h} when w < @min_dimension and h < @min_dimension -> true
      _ -> false
    end
  end

  defp extract_dimensions(tag) do
    width =
      case Regex.run(~r/width=["']?(\d+)/, tag) do
        [_, w] -> String.to_integer(w)
        _ -> 999
      end

    height =
      case Regex.run(~r/height=["']?(\d+)/, tag) do
        [_, h] -> String.to_integer(h)
        _ -> 999
      end

    {width, height}
  end

  # Score images: prefer larger explicit dimensions and content-area images
  defp image_score(tag) do
    tag_lower = String.downcase(tag)
    {w, h} = extract_dimensions(tag_lower)

    base = min(w, 2000) + min(h, 2000)

    # Boost images that look like content images
    boost =
      cond do
        String.contains?(tag_lower, "hero") -> 500
        String.contains?(tag_lower, "main") -> 400
        String.contains?(tag_lower, "featured") -> 400
        String.contains?(tag_lower, "gallery") -> 300
        String.contains?(tag_lower, "photo") -> 300
        String.contains?(tag_lower, "product") -> 200
        true -> 0
      end

    base + boost
  end
end
