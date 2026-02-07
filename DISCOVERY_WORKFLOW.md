# Discovery Spider Workflow

Crawl directory websites and extract business listings using Crawly + Claude Code.

**Crawly = legs** (fetches pages), **Claude Code = brain** (extracts structured data).

## Pipeline Overview

```
1. Crawl      mix discovery.crawl ...          -> tmp/discovery_crawls/<id>/
2. Export     mix discovery.export ...          -> tmp/discovery_batches/<id>/
3. Process    ./scripts/process_discovery.sh    -> batch_NNN_result.json
4. Import     mix discovery.import ...          -> businesses in DB
```

## Step 1: Crawl

Crawl a directory website and save raw pages to disk.

```bash
# Single URL
mix discovery.crawl https://leiden.opendi.nl/ --city leiden --max-pages 200

# Multiple seed URLs
mix discovery.crawl https://site1.nl https://site2.nl --city amsterdam --max-pages 300

# From seed file
mix discovery.crawl --seed-file seeds/leiden.txt --city leiden --max-pages 200

# With custom crawl ID
mix discovery.crawl https://leiden.opendi.nl/ --city leiden --crawl-id leiden-opendi
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--city SLUG` | Target city slug | - |
| `--category SLUG` | Target category slug | - |
| `--region SLUG` | Target region slug | inferred from city |
| `--max-pages N` | Maximum pages to crawl | 200 |
| `--crawl-id ID` | Custom crawl ID | auto-generated |
| `--seed-file FILE` | Read URLs from file (one per line) | - |

### Output

Pages saved to `tmp/discovery_crawls/<crawl_id>/`:
- `metadata.json` — crawl config and context
- `page_0001.json` ... `page_NNNN.json` — raw page content

## Step 2: Export

Batch crawled pages into JSON files for Claude Code processing.

```bash
mix discovery.export --crawl-id <crawl_id>
mix discovery.export --crawl-id <crawl_id> --batch-size 10
```

Default batch size is 5 pages per batch (pages can be large).

### Output

Batches written to `tmp/discovery_batches/<crawl_id>/`:
- `batch_001.json` ... `batch_NNN.json`

Each batch includes context (all city slugs, all category slugs) so Claude can match businesses.

## Step 3: Process with Claude Code

Run Claude Code (Max plan) to extract business listings from each batch.

```bash
# Process all batches
./scripts/process_discovery.sh <crawl_id> 1 <N>

# Process a range
./scripts/process_discovery.sh <crawl_id> 5 10
```

**Important:** Uses `claude --print` with Max plan (script unsets `ANTHROPIC_API_KEY`).

Skips batches that already have a `_result.json` file, so it's safe to re-run.

### Output

For each `batch_NNN.json`, creates `batch_NNN_result.json`:
```json
{
  "businesses": [
    {
      "name": "Restaurant De Troubadour",
      "address": "Breestraat 56, 2311 CS Leiden",
      "phone": "071 514 1000",
      "website": "https://example.nl",
      "email": "info@example.nl",
      "city_slug": "leiden",
      "category_slug": "restaurants",
      "description": "Bourgondisch restaurant in het centrum",
      "source_url": "https://leiden.opendi.nl/636493.html"
    }
  ],
  "pages_processed": 5,
  "businesses_found": 42
}
```

## Step 4: Import

Create businesses in the database from the extracted results.

```bash
# Dry run first
mix discovery.import --dir tmp/discovery_batches/<crawl_id> --dry-run

# Import for real
mix discovery.import --dir tmp/discovery_batches/<crawl_id>

# Import single file
mix discovery.import --file tmp/discovery_batches/<crawl_id>/batch_001_result.json
```

Businesses are created with:
- `status: :pending` (ready for enrichment)
- `source: :discovery_spider`
- Duplicates are skipped automatically (Ash identity)

## Full Example

```bash
# 1. Crawl opendi for Leiden
mix discovery.crawl https://leiden.opendi.nl/ --city leiden --max-pages 200
# Output: Crawl ID: bb545232208bc1cb

# 2. Export to batches
mix discovery.export --crawl-id bb545232208bc1cb
# Output: 40 batches

# 3. Process with Claude Code (in separate terminal)
./scripts/process_discovery.sh bb545232208bc1cb 1 40

# 4. Preview what will be imported
mix discovery.import --dir tmp/discovery_batches/bb545232208bc1cb --dry-run

# 5. Import
mix discovery.import --dir tmp/discovery_batches/bb545232208bc1cb
```

## Tips

- **Broad vs targeted crawls**: A broad crawl from the homepage discovers mixed categories. For specific categories, use category page URLs as seeds.
- **Max pages**: 200 is a good default. Increase for large directories.
- **Batch size**: Keep at 5 for large pages (opendi category listings). Use 10 for smaller pages.
- **Re-running**: The process script skips existing results. Delete `_result.json` files to reprocess.
- **Multiple directories**: Run separate crawls per directory, each gets its own crawl ID.

## Known Good Sources (Netherlands)

| Source | URL Pattern | Notes |
|--------|-------------|-------|
| Opendi | `<city>.opendi.nl/` | 8k+ listings, structured data |
| Leidenkrant | `leidenkrant.nl/bedrijvengids/` | A-Z directory |
| Leiden Onderneemt | `leidenonderneemt.nl/` | Local business platform |
| Informatiegids | `informatiegids-nederland.nl/plaats/<city>` | Names, addresses, phones |
| Bedrijvengids NL | `bedrijvengids-nl.nl/plaats/<city>/` | General directory |
| LeukeTip | `leuketip.com/cities/<city>/restaurants` | Curated, high quality |
