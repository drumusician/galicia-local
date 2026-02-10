defmodule GaliciaLocal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    oban_config = Application.fetch_env!(:galicia_local, Oban)

    # In prod, queues: false means we want Oban completely passive —
    # bypass AshOban.config which would inject scheduler plugins.
    oban_child =
      if oban_config[:queues] == false do
        {Oban, oban_config}
      else
        {Oban,
         AshOban.config(
           Application.fetch_env!(:galicia_local, :ash_domains),
           oban_config
         )}
      end

    base_children = [
      GaliciaLocalWeb.Telemetry,
      GaliciaLocal.Repo,
      {DNSCluster, query: Application.get_env(:galicia_local, :dns_cluster_query) || :ignore},
      oban_child,
      {Phoenix.PubSub, name: GaliciaLocal.PubSub}
    ]

    children =
      if Application.get_env(:galicia_local, :worker_health_port) do
        # Worker mode: no Phoenix endpoint, no scraper processes
        base_children ++ worker_children()
      else
        base_children ++
          [
            GaliciaLocal.Scraper.ApiCache,
            GaliciaLocal.Scraper.CrawlMonitor,
            GaliciaLocal.Scraper.CrawlResume,
            GaliciaLocalWeb.Endpoint,
            {AshAuthentication.Supervisor, [otp_app: :galicia_local]}
          ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GaliciaLocal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # In worker mode, start the health check endpoint
  defp worker_children do
    if Application.get_env(:galicia_local, :worker_health_port) do
      [GaliciaLocal.WorkerHealth]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GaliciaLocalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
