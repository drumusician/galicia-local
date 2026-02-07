# Content Generation & Prod Sync Workflow

## Overview

Content is generated locally using Claude Code (Max plan) — no Anthropic API or DeepL costs.
The pipeline is: **Export → Process → Import → Sync to prod**.

## 1. Export Batches

```bash
# Export businesses needing enrichment (default batch size: 10)
mix content.export enrichments
mix content.export enrichments --region galicia --limit 100

# Export businesses needing translations (default batch size: 25)
mix content.export translations --locale es
mix content.export translations --locale nl
mix content.export translations --locale nl --region netherlands --limit 50
```

Output goes to `tmp/content_batches/{enrich,translate_es,translate_nl}/`.

## 2. Process with Claude Code

### From a terminal (recommended for large batches)

```bash
# Enrichments
./scripts/process_enrichments.sh 1 53        # Process batches 1-53

# Translations
./scripts/process_translations.sh nl 1 50    # Dutch batches 1-50
./scripts/process_translations.sh es 1 100   # Spanish batches 1-100
```

Scripts skip already-completed batches (checks for `_result.json` files), so you can safely re-run or resume after interruption.

### From within Claude Code (parallel agents)

Ask Claude Code to process batches in parallel using Task agents — useful for smaller runs or when you want to monitor progress interactively.

## 3. Import Results

```bash
# Import enrichments
mix content.import enrichments --dir tmp/content_batches/enrich
mix content.import enrichments --dir tmp/content_batches/enrich --dry-run

# Import translations
mix content.import translations --dir tmp/content_batches/translate_es
mix content.import translations --dir tmp/content_batches/translate_nl

# Import a single file
mix content.import enrichments --file tmp/content_batches/enrich/batch_001_result.json
```

## 4. Sync to Production

```bash
# 1. Save timestamp BEFORE making changes (if not already set)
mix prod_sync.save_timestamp

# 2. After importing, export changes as SQL
mix prod_sync.export > tmp/prod_sync/changes.sql

# 3. Review the SQL
cat tmp/prod_sync/changes.sql

# 4. Push to production
mix prod_sync.push tmp/prod_sync/changes.sql

# 5. Save new timestamp for next sync
mix prod_sync.save_timestamp
```

The sync timestamp is stored at `tmp/prod_sync/last_sync.txt`.

## Full Workflow Example

```bash
# Export what needs doing
mix content.export enrichments
mix content.export translations --locale es
mix content.export translations --locale nl

# Process (run these in separate terminals for parallelism)
./scripts/process_enrichments.sh 1 53
./scripts/process_translations.sh es 1 272
./scripts/process_translations.sh nl 1 205

# Import results
mix content.import enrichments --dir tmp/content_batches/enrich
mix content.import translations --dir tmp/content_batches/translate_es
mix content.import translations --dir tmp/content_batches/translate_nl

# Push to prod
mix prod_sync.export > tmp/prod_sync/changes.sql
mix prod_sync.push tmp/prod_sync/changes.sql
mix prod_sync.save_timestamp
```

## Adding New Businesses (OSM Scraping)

Oban enrichment/translation schedulers are **disabled in dev** to avoid API costs.
After scraping new businesses via OSM:

1. Re-run `mix content.export enrichments` to pick up the new businesses
2. Process and import as above
3. Then export translations for the newly enriched businesses
4. Sync to prod

## Notes

- Enrichment batch size: 10 businesses (includes reviews, more context per business)
- Translation batch size: 25 businesses (simpler task, can handle more per batch)
- Scripts use `claude --print --allowedTools Read,Write` for non-interactive processing
- Import is idempotent: enrichments skip already-enriched businesses, translations upsert
- Prod sync exports only changes since the last saved timestamp
