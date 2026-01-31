defmodule GaliciaLocal.Scraper.ApiCache do
  @moduledoc """
  ETS-based cache for Google Places API responses.
  Prevents redundant API calls for identical queries.
  """
  use GenServer
  require Logger

  @table :api_cache
  @default_ttl_hours 24

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns cached result or calls fetch_fn and caches the result.
  Only successful {:ok, _} responses are cached.
  """
  def get_or_fetch(key, fetch_fn, ttl_hours \\ @default_ttl_hours) do
    case lookup(key, ttl_hours) do
      {:ok, cached} ->
        Logger.debug("API cache hit: #{inspect(key |> elem(0))}")
        cached

      :miss ->
        Logger.debug("API cache miss: #{inspect(key |> elem(0))}")
        result = fetch_fn.()

        case result do
          {:ok, _} -> insert(key, result)
          _ -> :ok
        end

        result
    end
  end

  @doc """
  Returns cache statistics.
  """
  def stats do
    size = :ets.info(@table, :size)
    %{entries: size}
  end

  @doc """
  Clears the entire cache.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end

  # Private

  defp lookup(key, ttl_hours) do
    case :ets.lookup(@table, key) do
      [{^key, value, inserted_at}] ->
        age_hours = System.monotonic_time(:second) - inserted_at
        if age_hours < ttl_hours * 3600, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  end

  defp insert(key, value) do
    :ets.insert(@table, {key, value, System.monotonic_time(:second)})
  end
end
