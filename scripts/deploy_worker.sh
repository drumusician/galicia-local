#!/bin/bash
# Deploy script for the Content Worker
# Run as deploy user: sudo -u deploy bash scripts/deploy_worker.sh
#
# Pulls latest code, compiles, migrates, and restarts the worker service.

set -euo pipefail

APP_DIR="/opt/galicia-local"
export MIX_ENV=worker
export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"

cd "$APP_DIR"

echo "=== Deploying Content Worker ==="

# Pull latest code
echo "--- Pulling latest code ---"
git pull origin master

# Install dependencies
echo "--- Installing dependencies ---"
mix deps.get --only $MIX_ENV

# Compile
echo "--- Compiling ---"
mix compile

# Run migrations
echo "--- Running migrations ---"
mix ecto.migrate

# Restart service
echo "--- Restarting worker service ---"
sudo systemctl restart galicia-worker

echo ""
echo "=== Deploy complete! ==="
echo "Check status: sudo systemctl status galicia-worker"
echo "Check logs:   journalctl -u galicia-worker -f"
