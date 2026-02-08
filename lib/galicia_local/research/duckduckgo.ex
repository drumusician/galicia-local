defmodule GaliciaLocal.Research.DuckDuckGo do
  @moduledoc """
  Free web search using DuckDuckGo HTML search.

  Replaces Tavily for the research pipeline. Scrapes DuckDuckGo's HTML search
  results page, then optionally fetches and extracts content from top results.

  No API key needed - uses the public HTML search endpoint.

  ## Usage

      GaliciaLocal.Research.DuckDuckGo.search("restaurant name pontevedra reviews")
      # => {:ok, %{query: "...", results: [%{title, url, content, score}]}}
  """

  require Logger

  @search_url "https://html.duckduckgo.com/html/"
  @request_timeout 15_000

  @doc """
  Performs a DuckDuckGo search and returns parsed results.

  Returns the same format as the old Tavily module for drop-in compatibility.

  ## Options

    * `:max_results` - Maximum number of results (default: 5)
    * `:fetch_content` - Whether to fetch full page content for top results (default: true)
    * `:fetch_limit` - How many result pages to actually fetch content from (default: 3)
  """
  def search(query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 5)
    fetch_content = Keyword.get(opts, :fetch_content, true)
    fetch_limit = Keyword.get(opts, :fetch_limit, 3)

    case do_search(query, max_results) do
      {:ok, results} ->
        results =
          if fetch_content do
            enrich_with_content(results, fetch_limit)
          else
            results
          end

        {:ok, %{query: query, answer: nil, results: results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs multiple searches and combines results (same interface as old Tavily.search_multiple).
  """
  def search_multiple(queries, opts \\ []) do
    tasks =
      Enum.map(queries, fn query ->
        Task.async(fn ->
          # Stagger requests to be polite to DDG
          Process.sleep(:rand.uniform(1000))
          {query, search(query, opts)}
        end)
      end)

    results =
      tasks
      |> Task.await_many(60_000)
      |> Enum.map(fn {query, result} ->
        case result do
          {:ok, data} -> %{query: query, success: true, data: data}
          {:error, reason} -> %{query: query, success: false, error: reason}
        end
      end)

    successful = Enum.filter(results, & &1.success)
    failed = Enum.reject(results, & &1.success)

    if length(failed) > 0 do
      Logger.warning("#{length(failed)} DuckDuckGo searches failed")
    end

    {:ok,
     %{
       total_queries: length(queries),
       successful: length(successful),
       failed: length(failed),
       results: successful
     }}
  end

  defp do_search(query, max_results) do
    Logger.info("DuckDuckGo search: #{query}")

    case Req.post(@search_url,
           form: [q: query],
           headers: [
             {"user-agent",
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
             {"accept", "text/html,application/xhtml+xml"},
             {"accept-language", "en-US,en;q=0.9"}
           ],
           receive_timeout: @request_timeout,
           redirect: true,
           max_redirects: 3
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        results = parse_search_results(body, max_results)
        Logger.info("DuckDuckGo found #{length(results)} results for: #{query}")
        {:ok, results}

      {:ok, %Req.Response{status: 202, body: body}} when is_binary(body) ->
        # DDG sometimes returns 202 with results
        results = parse_search_results(body, max_results)
        Logger.info("DuckDuckGo found #{length(results)} results for: #{query}")
        {:ok, results}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("DuckDuckGo returned status #{status} for: #{query}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("DuckDuckGo request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_search_results(html, max_results) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find(".result")
        |> Enum.take(max_results)
        |> Enum.map(&parse_result/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp parse_result(element) do
    title =
      element
      |> Floki.find(".result__a")
      |> Floki.text()
      |> String.trim()

    url =
      element
      |> Floki.find(".result__a")
      |> Floki.attribute("href")
      |> List.first()
      |> extract_real_url()

    snippet =
      element
      |> Floki.find(".result__snippet")
      |> Floki.text()
      |> String.trim()

    if url && title != "" do
      %{
        title: title,
        url: url,
        content: snippet,
        score: nil,
        raw_content: nil
      }
    else
      nil
    end
  end

  # DDG HTML wraps URLs in a redirect - extract the actual URL
  defp extract_real_url(nil), do: nil

  defp extract_real_url(url) do
    cond do
      String.contains?(url, "uddg=") ->
        url
        |> URI.parse()
        |> Map.get(:query, "")
        |> URI.decode_query()
        |> Map.get("uddg")
        |> case do
          nil -> clean_url(url)
          decoded -> decoded
        end

      String.starts_with?(url, "//") ->
        "https:" <> url

      String.starts_with?(url, "http") ->
        url

      true ->
        nil
    end
  end

  defp clean_url(url) do
    if String.starts_with?(url, "http"), do: url, else: nil
  end

  # Fetch actual page content for top results to get richer data
  defp enrich_with_content(results, fetch_limit) do
    {to_fetch, rest} = Enum.split(results, fetch_limit)

    enriched =
      to_fetch
      |> Enum.map(fn result ->
        case fetch_page_content(result.url) do
          {:ok, content} ->
            %{result | raw_content: content}

          {:error, _} ->
            result
        end
      end)

    enriched ++ rest
  end

  defp fetch_page_content(url) do
    case Req.get(url,
           receive_timeout: 10_000,
           redirect: true,
           max_redirects: 3,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        content = extract_page_text(body)
        {:ok, String.slice(content, 0, 5000)}

      _ ->
        {:error, :fetch_failed}
    end
  end

  defp extract_page_text(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.filter_out("script")
        |> Floki.filter_out("style")
        |> Floki.filter_out("nav")
        |> Floki.filter_out("footer")
        |> Floki.filter_out("header")
        |> Floki.filter_out("aside")
        |> Floki.text(sep: " ")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      {:error, _} ->
        ""
    end
  end
end
