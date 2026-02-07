#!/bin/bash
# Process discovery batches using Claude Code CLI
# Usage:
#   ./scripts/process_discovery.sh abc123 1 10    # Crawl abc123, batches 1-10

# Ensure we use Max plan, not API key
unset ANTHROPIC_API_KEY

CRAWL_ID="${1:?Usage: $0 <crawl_id> <start_batch> <end_batch>}"
START="${2:?Usage: $0 <crawl_id> <start_batch> <end_batch>}"
END="${3:?Usage: $0 <crawl_id> <start_batch> <end_batch>}"

DIR="tmp/discovery_batches/${CRAWL_ID}"

if [[ ! -d "$DIR" ]]; then
  echo "ERROR: Directory not found: $DIR"
  echo "Run 'mix discovery.export --crawl-id ${CRAWL_ID}' first"
  exit 1
fi

echo "Processing discovery batches ${START}-${END} for crawl ${CRAWL_ID}"
echo "================================================================"

for i in $(seq "$START" "$END"); do
  BATCH=$(printf "batch_%03d" "$i")
  INPUT="${DIR}/${BATCH}.json"
  OUTPUT="${DIR}/${BATCH}_result.json"

  if [[ ! -f "$INPUT" ]]; then
    echo "SKIP: $INPUT not found"
    continue
  fi

  if [[ -f "$OUTPUT" ]]; then
    echo "SKIP: $OUTPUT already exists"
    continue
  fi

  echo ""
  echo "--- Batch $i ---"

  claude --print "You are a data extraction specialist for a business directory helping newcomers integrate into local life.

Read the JSON file at $(pwd)/${INPUT}. It contains web pages crawled from a directory website.

For each page, extract ALL individual business listings you can find. For each business provide:
- name (required - skip if no name found)
- address (if available)
- phone (if available)
- website (if available)
- email (if available)
- city_slug (match to one of the cities in the context.all_cities array)
- category_slug (match to one of the slugs in context.all_category_slugs array)
- description (brief, from what's on the page)
- source_url (the page URL where you found this listing)

Guidelines:
- Extract EVERY business listing on each page
- If a page is a listing/search results page, extract all results
- If a page is a single business detail page, extract that one business
- If a page has no business listings (homepage, about page, etc.), return empty array
- Match city_slug by looking at the address or page context
- Match category_slug by the type of business/service
- Skip businesses that are clearly outside the target region
- If unsure about city or category, use your best guess or null

Write result to $(pwd)/${OUTPUT} as:
{\"businesses\": [{\"name\": \"...\", \"address\": \"...\", \"phone\": \"...\", \"website\": \"...\", \"email\": \"...\", \"city_slug\": \"...\", \"category_slug\": \"...\", \"description\": \"...\", \"source_url\": \"...\"}], \"pages_processed\": N, \"businesses_found\": N}

Process ALL pages in the batch. Valid JSON only." --allowedTools Read,Write

  if [[ -f "$OUTPUT" ]]; then
    COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d.get('businesses',[])))" 2>/dev/null || echo "?")
    echo "OK: ${COUNT} businesses extracted to ${OUTPUT}"
  else
    echo "FAIL: No output file created"
  fi
done

echo ""
echo "Done! Import with: mix discovery.import --dir ${DIR}"
