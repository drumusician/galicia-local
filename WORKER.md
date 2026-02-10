# Content Worker (Hetzner VPS)

Dedicated headless worker that runs the heavy content pipeline (discovery, research, enrichment, translations) separately from the production web app.

## Architecture

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Content Worker     │     │   Supabase DB    │     │  Prod App   │
│  (Hetzner CAX21)    │────▶│   (shared)       │◀────│  (Fly.io)   │
│                     │     │                  │     │             │
│  - Oban queues      │     │  businesses      │     │  Read-only  │
│  - Claude CLI       │     │  translations    │     │  web server │
│  - Web scraping     │     │  reviews         │     │  Phoenix    │
│  - No web server    │     │                  │     │             │
│  Helsinki, €8/mo    │     │                  │     │  $5/mo      │
└─────────────────────┘     └──────────────────┘     └─────────────┘
```

- **Prod** (`Fly.io`): Only serves the website. Oban queues disabled (`queues: false`).
- **Worker** (`Hetzner CAX21, 4 vCPU, 8GB RAM`): Runs all heavy Oban queues. No web server. Writes directly to Supabase.
- **Database** (`Supabase`): Shared PostgreSQL. Worker pool_size=5 to stay within connection limits.

## Autonomous Pipeline

When you add a new region/city in the admin UI, the worker handles everything automatically:

```
Region/city added in admin UI
        ↓
RegionDiscoveryScheduler (daily 02:00 UTC)
  → finds cities with < 5 businesses
  → queues OverpassImportWorker per city
        ↓
Overpass imports → hundreds of businesses (status: pending)
        ↓
BatchResearchWorker → WebsiteCrawlWorker + WebSearchWorker
  → crawls websites, runs web searches
  → businesses become "researched"
        ↓
Enrichment scheduler (every 30 min)
  → Claude CLI enriches businesses
  → description, summary, scores, tips, highlights
  → businesses become "enriched"
        ↓
Translation scheduler (every 30 min)
  → Claude CLI translates to es/nl
        ↓
Everything is in Supabase → prod reads it immediately
```

## Oban Queues

| Queue | Concurrency | Purpose |
|---|---|---|
| `default` | 5 | General background tasks |
| `discovery` | 2 | Overpass API imports |
| `scraper` | 3 | Web scraping |
| `research` | 3 | Website crawling, web search |
| `business_enrich_pending` | 1 | Claude CLI: enrich researched businesses |
| `business_enrich_researched` | 1 | Claude CLI: enrich researched businesses |
| `business_enrich_pending_no_website` | 1 | Claude CLI: enrich businesses without website |
| `business_translate_all_locales` | 1 | Claude CLI: translate to all locales |
| `translations` | 1 | Claude CLI: individual translations |

Claude CLI queues are kept at concurrency 1 to stay within Max plan rate limits. The enrichment queues are mutually exclusive (a business matches only one trigger), so effective concurrent Claude calls is 2-3.

## Scheduled Jobs

| Schedule | Job | Description |
|---|---|---|
| `0 2 * * *` | `RegionDiscoveryScheduler` | Daily: discover businesses for underpopulated cities |
| `*/30 * * * *` | Enrichment triggers (AshOban) | Enrich pending/researched businesses via Claude CLI |
| `*/30 * * * *` | Translation triggers (AshOban) | Translate enriched businesses via Claude CLI |

## VPS Details

- **Provider**: Hetzner
- **Plan**: CAX21 (Arm64/Ampere, 4 vCPU, 8GB RAM)
- **Location**: Helsinki
- **OS**: Ubuntu 24.04 LTS
- **IP**: `89.167.60.204`
- **User**: `deploy`

## Key Files

| File | Purpose |
|---|---|
| `config/worker.exs` | Worker environment config (queues, schedulers, data dirs) |
| `config/runtime.exs` | Database URL, secrets (shared with prod) |
| `lib/galicia_local/application.ex` | Conditional startup: worker vs web mode |
| `lib/galicia_local/worker_health.ex` | Health check endpoint on port 4001 |
| `lib/galicia_local/workers/region_discovery_scheduler.ex` | Autonomous region discovery |
| `scripts/setup_worker.sh` | Fresh VPS provisioning script |
| `scripts/deploy_worker.sh` | Deployment script (stop, pull, compile, start) |
| `systemd/galicia-worker.service` | systemd service definition |

## Health Check

The worker exposes a health endpoint on port 4001:

```bash
curl http://localhost:4001/health
```

Returns:
```json
{
  "healthy": true,
  "timestamp": "2026-02-10T21:20:42Z",
  "oban": {
    "ok": true,
    "available": 0,
    "executing": 2,
    "scheduled": 0,
    "retryable": 0,
    "last_completed": "2026-02-10T21:19:30"
  },
  "database": true
}
```

## Deploying

SSH into the VPS as root and run:

```bash
bash /opt/galicia-local/scripts/deploy_worker.sh
```

This stops the worker, pulls latest code, recompiles (with `--force` for `compile_env` changes), and restarts.

## Manual Operations

```bash
# Check status
sudo systemctl status galicia-worker

# View logs
journalctl -u galicia-worker -f

# Stop/start
sudo systemctl stop galicia-worker
sudo systemctl start galicia-worker

# Health check
curl http://localhost:4001/health

# Connect to database
sudo -u deploy bash -c 'set -a && source /opt/galicia-local/.env && set +a && psql "$DATABASE_URL"'
```

## Environment Variables (.env)

The worker reads from `/opt/galicia-local/.env`:

| Variable | Description |
|---|---|
| `DATABASE_URL` | Supabase transaction pooler connection string |
| `SECRET_KEY_BASE` | Phoenix secret (required even without web server) |
| `TOKEN_SIGNING_SECRET` | Auth token signing secret |
| `POSTMARK_API_KEY` | Email service (for notifications) |
| `APPSIGNAL_PUSH_API_KEY` | AppSignal monitoring |
| `PHX_HOST` | `startlocal.app` |
| `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived Claude CLI token (1 year) |
| `POOL_SIZE` | Database connection pool size (default: 5) |

## Fresh VPS Setup

For setting up a new worker from scratch:

1. Create a Hetzner CAX21 server (Ubuntu 24.04, Helsinki)
2. SSH in as root
3. Run the setup script: `bash scripts/setup_worker.sh`
4. Edit `/opt/galicia-local/.env` with actual secrets
5. Install Claude CLI: `sudo -u deploy bash -c 'curl -fsSL https://claude.ai/install.sh | bash'`
6. Authenticate Claude: `sudo -u deploy claude /login` (use setup-token for long-lived token)
7. Add `CLAUDE_CODE_OAUTH_TOKEN` to `.env`
8. Add Claude to PATH: `sudo -u deploy bash -c 'echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc'`
9. Start: `sudo systemctl start galicia-worker`
10. Verify: `curl http://localhost:4001/health`

## Troubleshooting

**Worker not appearing as Oban peer**: Check database connectivity with `curl http://localhost:4001/health`. Verify `DATABASE_URL` in `.env` uses the transaction pooler URL (not direct connection).

**Max client connections reached**: Reduce `POOL_SIZE` in `.env`. Default is 5. Supabase has a 90 connection limit shared between prod and worker.

**Claude CLI "not found"**: Ensure `/home/deploy/.local/bin` is in the systemd service PATH (see `galicia-worker.service`).

**Claude CLI "not logged in"**: Check `CLAUDE_CODE_OAUTH_TOKEN` is in `.env` and service was restarted after adding it.

**Port 4001 already in use**: Crawly's built-in HTTP API defaults to port 4001. This is disabled in `worker.exs` with `config :crawly, start_http_api?: false`. If the error persists, a previous process may still be holding the port — wait a few seconds or check with `ss -tlnp | grep 4001`.

**Jobs piling up but not executing**: Check if the relevant queue is configured in `worker.exs`. Check logs for errors with `journalctl -u galicia-worker --since "10 min ago"`.
