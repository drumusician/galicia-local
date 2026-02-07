#!/usr/bin/env bash
#
# Dump the production database to a local file.
# Usage: ./scripts/dump_prod_db.sh
#
# The dump file can be restored locally with:
#   pg_restore --clean --no-owner -d galicia_local_dev dump_prod_YYYYMMDD.dump
#
# Or for a fresh restore:
#   dropdb galicia_local_dev
#   createdb galicia_local_dev
#   pg_restore --no-owner -d galicia_local_dev dump_prod_YYYYMMDD.dump
#   mix ash_postgres.migrate
#
set -euo pipefail

DUMP_FILE="dump_prod_$(date +%Y%m%d_%H%M%S).dump"

echo "=== Production Database Dump ==="
echo ""
echo "This will create a pg_dump from your production database."
echo "No data will be modified — this is a read-only operation."
echo ""

# Prompt for connection details
read -p "Database host (e.g. db.xxxxx.supabase.co): " DB_HOST
read -p "Database name [postgres]: " DB_NAME
DB_NAME=${DB_NAME:-postgres}
read -p "Database user [postgres]: " DB_USER
DB_USER=${DB_USER:-postgres}
read -p "Database port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -sp "Database password: " DB_PASS
echo ""

echo ""
echo "Dumping to: ${DUMP_FILE}"
echo "This may take a minute..."

PGPASSWORD="$DB_PASS" pg_dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname="$DB_NAME" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --verbose \
  "$DUMP_FILE" 2>&1 | tail -5

echo ""
echo "Done! Dump saved to: ${DUMP_FILE}"
echo "Size: $(du -h "$DUMP_FILE" | cut -f1)"
echo ""
echo "To restore locally:"
echo "  pg_restore --clean --no-owner -d galicia_local_dev ${DUMP_FILE}"
