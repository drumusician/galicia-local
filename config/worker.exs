import Config

# Worker environment: headless content pipeline
# No web server — only Oban workers for discovery, enrichment, and translation.
# Connects to the same Supabase database as production.

# No web server
config :galicia_local, GaliciaLocalWeb.Endpoint, server: false

# All heavy queues enabled with appropriate concurrency
config :galicia_local, Oban,
  queues: [
    default: 5,
    discovery: 2,
    scraper: 3,
    research: 3,
    business_enrich_pending: 1,
    business_enrich_researched: 1,
    business_enrich_pending_no_website: 1,
    business_translate_all_locales: 1,
    translations: 2
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Daily at 02:00 UTC — discover businesses for underpopulated cities
       {"0 2 * * *", GaliciaLocal.Workers.RegionDiscoveryScheduler}
     ]},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ]

# Enrichment & translation schedulers
# Run every 30 min to avoid flooding the database with jobs
config :galicia_local, enrich_scheduler_cron: "*/30 * * * *"
config :galicia_local, translate_all_scheduler_cron: "*/30 * * * *"

# Research data on persistent disk
config :galicia_local, research_data_dir: "/data/research"
config :galicia_local, discovery_data_dir: "/data/discovery"

# Configure Swoosh API Client (needed for compilation)
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Disable Crawly's built-in HTTP API (defaults to port 4001, conflicts with health check)
config :crawly, start_http_api?: false

# Worker health check port
config :galicia_local, worker_health_port: 4001

# Do not print debug messages
config :logger, level: :info

# AppSignal active for worker too
config :appsignal, :config, active: true
