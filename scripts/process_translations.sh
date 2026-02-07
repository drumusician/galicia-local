#!/bin/bash
# Process translation batches using Claude Code CLI
# Usage:
#   ./scripts/process_translations.sh nl 1 10    # Dutch batches 1-10
#   ./scripts/process_translations.sh es 1 5     # Spanish batches 1-5
#   ./scripts/process_translations.sh nl 50 100  # Dutch batches 50-100

# Ensure we use Max plan, not API key
unset ANTHROPIC_API_KEY

LOCALE="${1:?Usage: $0 <locale> <start_batch> <end_batch>}"
START="${2:?Usage: $0 <locale> <start_batch> <end_batch>}"
END="${3:?Usage: $0 <locale> <start_batch> <end_batch>}"

LANG_NAME="Dutch"
[[ "$LOCALE" == "es" ]] && LANG_NAME="Spanish"

DIR="tmp/content_batches/translate_${LOCALE}"

echo "Processing ${LANG_NAME} translation batches ${START}-${END}"
echo "================================================"

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

  claude --print "You are a professional translator. Read the JSON file at $(pwd)/${INPUT}.

Translate ALL businesses from English to ${LANG_NAME}. For each business translate: description, summary, highlights, warnings, integration_tips, cultural_notes.

Guidelines: natural professional ${LANG_NAME}, keep proper nouns unchanged, keep translations concise.

Write result to $(pwd)/${OUTPUT} as:
{\"target_locale\": \"${LOCALE}\", \"translations\": [{\"business_id\": \"uuid\", \"description\": \"...\", \"summary\": \"...\", \"highlights\": [...], \"warnings\": [...], \"integration_tips\": [...], \"cultural_notes\": [...]}]}

Process ALL businesses. Valid JSON only." --allowedTools Read,Write

  if [[ -f "$OUTPUT" ]]; then
    COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d.get('translations',[])))" 2>/dev/null || echo "?")
    echo "OK: ${COUNT} translations written to ${OUTPUT}"
  else
    echo "FAIL: No output file created"
  fi
done

echo ""
echo "Done! Import with: mix content.import translations --dir ${DIR}"
