defmodule GaliciaLocal.Research.Tavily do
  @moduledoc """
  Client for the Tavily Search API.

  Tavily provides an AI-optimized search API that returns clean, structured
  results perfect for feeding into LLMs.

  ## Configuration

  Set the `TAVILY_API_KEY` environment variable.

  ## Usage

      GaliciaLocal.Research.Tavily.search("restaurant name pontevedra reviews")
      # => {:ok, %{results: [...], query: "..."}}
  """

  require Logger

  @base_url "https://api.tavily.com"
  @default_timeout 30_000

  @doc """
  Performs a search using the Tavily API.

  ## Options

    * `:search_depth` - "basic" (default) or "advanced" for deeper search
    * `:include_domains` - List of domains to include (e.g., ["linkedin.com"])
    * `:exclude_domains` - List of domains to exclude
    * `:max_results` - Maximum number of results (default: 5)
    * `:include_answer` - Include AI-generated answer (default: false)
    * `:include_raw_content` - Include full page content (default: false)

  ## Returns

    * `{:ok, %{query: String, results: [...]}}` on success
    * `{:error, reason}` on failure
  """
  def search(query, opts \\ []) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.warning("TAVILY_API_KEY not set, returning mock results")
      {:ok, mock_results(query)}
    else
      perform_search(query, api_key, opts)
    end
  end

  defp perform_search(query, api_key, opts) do
    search_depth = Keyword.get(opts, :search_depth, "basic")
    max_results = Keyword.get(opts, :max_results, 5)
    include_domains = Keyword.get(opts, :include_domains, [])
    exclude_domains = Keyword.get(opts, :exclude_domains, [])
    include_answer = Keyword.get(opts, :include_answer, false)
    include_raw_content = Keyword.get(opts, :include_raw_content, false)

    body =
      %{
        api_key: api_key,
        query: query,
        search_depth: search_depth,
        max_results: max_results,
        include_answer: include_answer,
        include_raw_content: include_raw_content
      }
      |> maybe_add(:include_domains, include_domains)
      |> maybe_add(:exclude_domains, exclude_domains)

    case Req.post("#{@base_url}/search",
           json: body,
           receive_timeout: @default_timeout
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Tavily API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Tavily request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add(map, _key, []), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp parse_response(body) do
    %{
      query: body["query"],
      answer: body["answer"],
      results:
        Enum.map(body["results"] || [], fn r ->
          %{
            title: r["title"],
            url: r["url"],
            content: r["content"],
            score: r["score"],
            raw_content: r["raw_content"]
          }
        end)
    }
  end

  defp get_api_key do
    Application.get_env(:galicia_local, :tavily_api_key) ||
      System.get_env("TAVILY_API_KEY")
  end

  defp mock_results(query) do
    %{
      query: query,
      answer: nil,
      results: [
        %{
          title: "Mock result for: #{query}",
          url: "https://example.com/mock",
          content:
            "This is a mock result. Set TAVILY_API_KEY environment variable for real results.",
          score: 0.5,
          raw_content: nil
        }
      ]
    }
  end

  @doc """
  Performs multiple searches in parallel and combines results.

  Useful for gathering information from different angles about a business.

  ## Example

      queries = [
        "\\"Business Name\\" Pontevedra reviews",
        "\\"Business Name\\" specialization",
        "\\"Business Name\\" news"
      ]
      GaliciaLocal.Research.Tavily.search_multiple(queries)
  """
  def search_multiple(queries, opts \\ []) do
    tasks =
      Enum.map(queries, fn query ->
        Task.async(fn -> {query, search(query, opts)} end)
      end)

    results =
      tasks
      |> Task.await_many(@default_timeout * 2)
      |> Enum.map(fn {query, result} ->
        case result do
          {:ok, data} -> %{query: query, success: true, data: data}
          {:error, reason} -> %{query: query, success: false, error: reason}
        end
      end)

    successful = Enum.filter(results, & &1.success)
    failed = Enum.reject(results, & &1.success)

    if length(failed) > 0 do
      Logger.warning("#{length(failed)} Tavily searches failed")
    end

    {:ok,
     %{
       total_queries: length(queries),
       successful: length(successful),
       failed: length(failed),
       results: successful
     }}
  end
end
