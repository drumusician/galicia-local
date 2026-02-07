# Plan: Cost Reduction & Free Data Pipeline

## Context
We're reducing the cost of the business data pipeline. Previously everything ran through paid APIs (Google Places ~$17/1000 businesses, Claude API for enrichment, DeepL for translation). We're replacing these with free alternatives where possible.

## Completed

### 1. OpenStreetMap / Overpass API Integration (FREE business discovery)
Replaces Google Places API for discovering businesses.

**New files:**
- `lib/galicia_local/scraper/overpass.ex` — Overpass API client with OSM tag mappings for 25 categories, Overpass QL query builder, response normalization (name, address, phone, website, lat/lon, opening hours), opening hours parser
- `lib/galicia_local/scraper/workers/overpass_worker.ex` — Oban worker: creates ScrapeJob, calls Overpass API, deduplicates by `osm_id` in `raw_data`, creates businesses with `source: :openstreetmap`, queues WebsiteCrawlWorker for websites

**Modified files:**
- `lib/galicia_local/directory/types/scrape_source.ex` — Added `:openstreetmap` enum value (stored as text, no migration needed)
- `lib/galicia_local/scraper.ex` — Added `search_overpass/3`, `search_overpass_city/2` with auto bbox from city lat/lon + radius
- `lib/galicia_local_web/live/admin/scraper_live.ex` — Added "OpenStreetMap (Free)" radio button, wired start_scrape + scrape_all_city events

**Tested:** Searched bakeries in Ourense — found 17, created 11 businesses. Scrape job recorded correctly.

### 2. Database Dump Script
- `scripts/dump_prod_db.sh` — Prompts for host/password, runs pg_dump with --format=custom

### 3. Production Database Synced Locally
Synced via `fly ssh console` + `COPY TO STDOUT` + `\copy FROM`.

**Method:** Connected to prod DB through Fly.io's Elixir runtime, dumped each table as CSV via PostgreSQL COPY, imported into local dev DB via psql `\copy FROM`.

**Files:** `tmp/prod_sync/` — CSV dumps + `import.sql` script

**Re-sync command:**
```bash
# To re-sync later, re-run the CSV dumps via fly ssh and then:
cd tmp/prod_sync && psql -U postgres -d galicia_local_dev -f import.sql
```

**Current data (2026-02-07):**
- 7,838 businesses (93% enriched, 529 pending)
- 12,264 business translations
- 42 cities across 2 regions (Galicia + Netherlands)
- 26 categories with 78 translations

**Enrichment gaps identified:**
- 529 businesses in "researching" status (missing descriptions)
- 423 businesses "rejected" (low category fit)
- 1,809 enriched businesses missing ES translations
- 26 NL-region businesses missing NL translations
- Top unenriched cities: Amsterdam (107), Ferrol (45), Utrecht (42), Santiago (35)

## Next Steps

### 4. Claude Max Plan for Enrichment (replaces Claude API)
User has a Claude Max plan (unlimited). Ideas discussed:
- **Option A:** Use Claude Code CLI (`claude -p "enrich this business"`) from within Oban workers or a mix task
- **Option B:** Generate a JSON/CSV export of businesses needing enrichment, process via Claude Code interactively, then import results back
- **Option C:** Build a mix task that reads businesses from DB, calls Claude Code CLI per business, writes enriched data back
- This would eliminate the ~$0.027/business Claude API enrichment cost entirely

### 5. Future: Batch Translation Optimization
- DeepL costs could be reduced by batching translations (multiple fields/businesses per API call)
- Or use Claude Max for translation too (generate multilingual content in one LLM call)
- Current cost: DeepL charges per character, batching wouldn't save much unless we switch to Claude

## Architecture Reference

```
Business Pipeline:
1. Discovery:   Google Places ($) | OpenStreetMap (FREE) | Páginas Amarillas
2. Research:    WebsiteCrawlWorker → Tavily web search ($0.001/search)
3. Enrichment:  Claude API ($0.027/business) → TODO: Claude Max (FREE)
4. Translation: DeepL API (per-character) → TODO: Claude Max (FREE)
```

## Key Files
- `lib/galicia_local/scraper.ex` — Main scraper interface
- `lib/galicia_local/scraper/overpass.ex` — OSM Overpass client
- `lib/galicia_local/scraper/google_places.ex` — Google Places client
- `lib/galicia_local/scraper/workers/` — Oban workers (overpass, google_places, website_crawl)
- `lib/galicia_local/directory/business.ex` — Business resource with Oban triggers for enrichment/translation
- `lib/galicia_local/directory/business/changes/enrich_with_llm.ex` — LLM enrichment Change module
- `lib/galicia_local_web/live/admin/scraper_live.ex` — Admin scraper UI
