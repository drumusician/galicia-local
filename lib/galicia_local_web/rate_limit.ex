defmodule GaliciaLocalWeb.RateLimit do
  @moduledoc """
  A small fixed-window rate limiter backed by ETS.

  Deliberately dependency-free and in-memory. Counters are per-instance rather
  than shared, so with multiple machines the effective limit is the configured
  limit times the number of machines. That is fine for the thing this guards
  against — bulk automated signups — and avoids putting a database write on
  every request we are trying not to pay for.
  """

  use GenServer

  @table __MODULE__
  @purge_interval :timer.minutes(10)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Counts a hit against `key` and reports whether it is over `limit`.

  Returns `:ok`, or `{:error, retry_after_seconds}` once the caller has
  exceeded `limit` hits within the current `window_ms` window.

  Fails open: if the limiter is not running, every call is allowed. A missing
  supervisor child should not take signups down with it.
  """
  def check(key, limit, window_ms) do
    now = System.system_time(:millisecond)
    window = div(now, window_ms)
    expires_at = (window + 1) * window_ms

    # Each record carries its own expiry so that buckets with different window
    # sizes can share the table and still be purged correctly.
    count =
      :ets.update_counter(@table, {key, window}, {2, 1}, {{key, window}, 0, expires_at})

    if count > limit do
      {:error, div(expires_at - now, 1000) + 1}
    else
      :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    schedule_purge()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:purge, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_purge()
    {:noreply, state}
  end

  defp schedule_purge, do: Process.send_after(self(), :purge, @purge_interval)
end
