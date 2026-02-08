defmodule GaliciaLocal.Scraper.Tavily do
  @moduledoc """
  Tavily Search API client for finding real business directory sites.

  Uses the Tavily API (free tier: 1000 queries/month) to search for
  actual directory listing pages that can be crawled.

  Requires `TAVILY_API_KEY` environment variable.
  """

  require Logger

  @tavily_url "https://api.tavily.com/search"
  @request_timeout 30_000

  @doc """
  Search for business directory sites for a city.
  Returns `{:ok, [%{url, name, description, selected}]}` or `{:error, reason}`.

  The returned format matches the existing URL selection UI in the regions wizard.
  """
  def search_directory_sites(city_name, country_code) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      query = "business directory listing #{city_name} #{country_name(country_code)}"
      Logger.info("Tavily search: #{query}")

      body = %{
        api_key: api_key,
        query: query,
        search_depth: "basic",
        max_results: 8,
        include_answer: false,
        include_raw_content: false
      }

      case Req.post(@tavily_url,
             json: body,
             receive_timeout: @request_timeout,
             headers: [{"content-type", "application/json"}]
           ) do
        {:ok, %{status: 200, body: %{"results" => results}}} ->
          urls =
            results
            |> Enum.reject(&skip_result?/1)
            |> Enum.map(fn r ->
              %{
                "url" => r["url"],
                "name" => r["title"] || "Unknown",
                "description" => String.slice(r["content"] || "", 0, 200),
                "selected" => true
              }
            end)

          Logger.info("Tavily found #{length(urls)} directory sites for #{city_name}")
          {:ok, urls}

        {:ok, %{status: 401}} ->
          {:error, :invalid_api_key}

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Tavily error #{status}: #{inspect(body) |> String.slice(0, 200)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("Tavily request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_api_key do
    Application.get_env(:galicia_local, :tavily_api_key) ||
      System.get_env("TAVILY_API_KEY")
  end

  defp skip_result?(result) do
    url = result["url"] || ""

    # Skip Google, social media, and generic sites that aren't crawlable directories
    skip_domains = [
      "google.com",
      "google.es",
      "google.nl",
      "facebook.com",
      "instagram.com",
      "twitter.com",
      "x.com",
      "linkedin.com",
      "youtube.com",
      "wikipedia.org",
      "reddit.com"
    ]

    Enum.any?(skip_domains, &String.contains?(url, &1))
  end

  defp country_name("ES"), do: "Spain"
  defp country_name("NL"), do: "Netherlands"
  defp country_name("PT"), do: "Portugal"
  defp country_name("FR"), do: "France"
  defp country_name("DE"), do: "Germany"
  defp country_name("IT"), do: "Italy"
  defp country_name("GB"), do: "United Kingdom"
  defp country_name(code), do: code
end
