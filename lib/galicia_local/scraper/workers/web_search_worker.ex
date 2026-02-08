defmodule GaliciaLocal.Scraper.Workers.WebSearchWorker do
  @moduledoc """
  Oban worker for gathering external information about businesses via web search.

  This is Step 3 of the data pipeline:
  1. Google Places API → Get business data
  2. Website Crawling → Extract full website content
  3. Web Search → Gather external sources (this worker)
  4. LLM Enrichment → Deep analysis

  ## Usage

      %{business_id: "uuid"}
      |> GaliciaLocal.Scraper.Workers.WebSearchWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :research,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args, :queue, :worker]]

  require Logger

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocal.Research.DuckDuckGo

  @research_dir "priv/research"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"business_id" => business_id}}) do
    Logger.info("Starting web search for business: #{business_id}")

    with {:ok, business} <- load_business(business_id),
         :ok <- ensure_research_dir(business_id),
         {:ok, results} <- perform_searches(business),
         :ok <- save_results(business_id, results),
         {:ok, _} <- update_status(business, :researched) do
      Logger.info("Web search complete for #{business.name}: #{results.successful} queries successful")
      :ok
    else
      {:error, reason} ->
        Logger.error("Web search failed for #{business_id}: #{inspect(reason)}")
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

  defp perform_searches(business) do
    queries = build_search_queries(business)
    Logger.info("Performing #{length(queries)} search queries for #{business.name}")

    DuckDuckGo.search_multiple(queries, max_results: 5)
  end

  defp build_search_queries(business) do
    name = business.name
    city_name = get_city_name(business)
    category_name = get_category_name(business)

    [
      # Combined reviews, reputation and expertise
      "\"#{name}\" #{city_name} #{category_name} reviews opinions",
      # Local Galician media mentions
      "\"#{name}\" #{city_name} site:lavozdegalicia.es OR site:farodevigo.es OR site:atlantico.net"
    ]
  end

  defp get_city_name(business) do
    case business.city do
      %{name: name} -> name
      _ -> "Galicia"
    end
  end

  defp get_category_name(business) do
    case business.category do
      %{name: name} -> name
      _ -> "business"
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
    path = Path.join([@research_dir, business_id, "search.json"])

    data = %{
      searched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_queries: results.total_queries,
      successful: results.successful,
      failed: results.failed,
      queries:
        Enum.map(results.results, fn r ->
          %{
            query: r.query,
            results:
              Enum.map(r.data.results, fn result ->
                %{
                  title: result.title,
                  url: result.url,
                  content: result.content,
                  score: result.score
                }
              end)
          }
        end)
    }

    case File.write(path, Jason.encode!(data, pretty: true)) do
      :ok ->
        Logger.info("Saved web search results to #{path}")
        :ok

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  @doc """
  Returns the path to the search results file.
  """
  def search_results_path(business_id) do
    Path.join([@research_dir, business_id, "search.json"])
  end

  @doc """
  Loads the web search results for a business if they exist.
  """
  def load_search_results(business_id) do
    path = search_results_path(business_id)

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
