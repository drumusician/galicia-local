defmodule GaliciaLocal.Accounts.StaleSignupCleanup do
  @moduledoc """
  Periodically deletes registrations that were never confirmed.

  Automated signups create a user row and burn a Postmark send each time. The
  rows are harmless individually but they accumulate, and they make the real
  member count impossible to read at a glance.

  This runs as a plain `GenServer` rather than an Oban job on purpose: both the
  web and worker environments set `queues: false, plugins: false`, so there is
  no cron plugin available to schedule against.

  Only users matching `:stale_unconfirmed` are removed — never confirmed, never
  an admin, and with no favourites, reviews, suggestions, claims or owned
  businesses. Deletion is deliberately conservative; leaving a spam row behind
  costs nothing, removing a real account costs a lot.
  """

  use GenServer

  require Logger

  alias GaliciaLocal.Accounts.User

  @default_retention_days 7
  @default_interval :timer.hours(12)

  # Fly machines can stop when idle, so a long timer is not guaranteed to fire.
  # Sweeping shortly after boot means a machine that wakes up catches up.
  @initial_delay :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs a sweep immediately and returns the number of users deleted.

  Exposed for manual runs from a release console.
  """
  def sweep_now(retention_days \\ nil) do
    sweep(retention_days || retention_days())
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :sweep, @initial_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    try do
      sweep(retention_days())
    rescue
      error ->
        Logger.error("Stale signup cleanup failed: #{Exception.message(error)}")
    end

    Process.send_after(self(), :sweep, interval())
    {:noreply, state}
  end

  defp sweep(retention_days) do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 24 * 60 * 60, :second)

    query = Ash.Query.for_read(User, :stale_unconfirmed, %{cutoff: cutoff}, authorize?: false)

    case Ash.count(query, authorize?: false) do
      {:ok, 0} ->
        0

      {:ok, count} ->
        result = Ash.bulk_destroy(query, :destroy, %{}, authorize?: false, stop_on_error?: false)

        Logger.info(
          "Stale signup cleanup: deleted #{count - result.error_count} unconfirmed " <>
            "users older than #{retention_days} days (#{result.error_count} failed)"
        )

        count - result.error_count

      {:error, error} ->
        Logger.error("Stale signup cleanup could not count users: #{inspect(error)}")
        0
    end
  end

  defp retention_days do
    Application.get_env(:galicia_local, :unconfirmed_user_retention_days, @default_retention_days)
  end

  defp interval do
    Application.get_env(:galicia_local, :stale_signup_cleanup_interval, @default_interval)
  end
end
