defmodule GaliciaLocal.WorkerHealth do
  @moduledoc """
  Minimal Plug-based health check server for the content worker.

  Serves `/health` on a configurable port (default 4001) so monitoring
  services can verify the worker is alive and Oban is processing jobs.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  get "/health" do
    checks = health_checks()

    status = if checks.healthy, do: 200, else: 503

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(checks))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp health_checks do
    oban_status = check_oban()
    db_status = check_database()

    %{
      healthy: oban_status.ok and db_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      oban: oban_status,
      database: db_status
    }
  end

  defp check_oban do
    try do
      query = """
      SELECT state, COUNT(*) as count
      FROM oban_jobs
      WHERE state IN ('available', 'executing', 'scheduled', 'retryable')
      GROUP BY state
      """

      %{rows: rows} = GaliciaLocal.Repo.query!(query)
      counts = Map.new(rows, fn [state, count] -> {state, count} end)

      latest_query = """
      SELECT MAX(completed_at)
      FROM oban_jobs
      WHERE state = 'completed'
      """

      %{rows: [[last_completed]]} = GaliciaLocal.Repo.query!(latest_query)

      %{
        ok: true,
        available: Map.get(counts, "available", 0),
        executing: Map.get(counts, "executing", 0),
        scheduled: Map.get(counts, "scheduled", 0),
        retryable: Map.get(counts, "retryable", 0),
        last_completed: last_completed && NaiveDateTime.to_iso8601(last_completed)
      }
    rescue
      e ->
        %{ok: false, error: Exception.message(e)}
    end
  end

  defp check_database do
    try do
      %{rows: [[1]]} = GaliciaLocal.Repo.query!("SELECT 1")
      true
    rescue
      _ -> false
    end
  end

  @doc """
  Returns a child spec for starting the health check server under a supervisor.
  Wraps Bandit start to handle port conflicts gracefully.
  """
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link do
    port = Application.get_env(:galicia_local, :worker_health_port, 4001)

    case Bandit.start_link(plug: __MODULE__, port: port, scheme: :http) do
      {:ok, pid} ->
        require Logger
        Logger.info("WorkerHealth listening on port #{port}")
        {:ok, pid}

      {:error, reason} ->
        require Logger
        Logger.warning("WorkerHealth failed to start on port #{port}: #{inspect(reason)}, continuing without health endpoint")
        :ignore
    end
  end
end
