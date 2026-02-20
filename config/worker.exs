import Config

# Worker environment: headless content pipeline
# No web server — only Oban workers for discovery, enrichment, and translation.
# Connects to the same Supabase database as production.
#
# NOTE: Worker VPS is DISABLED (2026-02-20). All Oban processing and
# automatic discovery/enrichment/translation is paused to reduce costs.
# The worker VPS (89.167.60.204) should be stopped via:
#   ssh deploy@89.167.60.204 'sudo systemctl stop galicia-worker'

# No web server
config :galicia_local, GaliciaLocalWeb.Endpoint, server: false

# Disable ALL Oban processing on worker — paused to reduce costs.
# Was running discovery, enrichment, and translation jobs automatically.
config :galicia_local, Oban,
  queues: false,
  plugins: false

# Enrichment & translation schedulers DISABLED
# config :galicia_local, enrich_scheduler_cron: "*/30 * * * *"
# config :galicia_local, translate_all_scheduler_cron: "*/30 * * * *"

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

# AppSignal disabled — worker is not running
config :appsignal, :config, active: false
