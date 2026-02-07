#!/bin/bash
# Process enrichment batches using Claude Code CLI
# Usage:
#   ./scripts/process_enrichments.sh 1 10     # Batches 1-10
#   ./scripts/process_enrichments.sh 20 53    # Batches 20-53

# Ensure we use Max plan, not API key
unset ANTHROPIC_API_KEY

START="${1:?Usage: $0 <start_batch> <end_batch>}"
END="${2:?Usage: $0 <start_batch> <end_batch>}"

DIR="tmp/content_batches/enrich"

echo "Processing enrichment batches ${START}-${END}"
echo "============================================="

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

  claude --print "You are an analyst for a directory helping newcomers INTEGRATE into local life.

Read $(pwd)/${INPUT}. For each business, analyze the data and generate enrichment content.

Philosophy: We celebrate authentic local businesses. Low newcomer_friendly_score is NOT negative.
- Region 'galicia': Spanish/Galician, siesta, tapas culture
- Region 'netherlands': Dutch, directness, appointment culture

For each business generate JSON with: business_id, description (2-3 sentences), summary (max 100 chars), local_gem_score (0-1), newcomer_friendly_score (0-1), speaks_english (bool), speaks_english_confidence (0-1), languages_spoken ([]), languages_taught ([]), integration_tips ([]), cultural_notes ([]), service_specialties ([]), highlights ([]), warnings ([]), sentiment_summary, review_insights ({common_praise, common_concerns, notable_quotes, reviewer_demographics}), quality_score (0-1), category_fit_score (0-1), suggested_category_slug (null or slug if fit<0.5).

If no reviews available, be conservative with scores.

Write to $(pwd)/${OUTPUT} as: {\"enrichments\": [...]}
Process ALL businesses. Valid JSON only." --allowedTools Read,Write

  if [[ -f "$OUTPUT" ]]; then
    COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d.get('enrichments',[])))" 2>/dev/null || echo "?")
    echo "OK: ${COUNT} enrichments written to ${OUTPUT}"
  else
    echo "FAIL: No output file created"
  fi
done

echo ""
echo "Done! Import with: mix content.import enrichments --dir ${DIR}"
