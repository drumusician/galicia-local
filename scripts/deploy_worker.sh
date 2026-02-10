#!/bin/bash
# Deploy script for the Content Worker
# Run as root: bash /opt/galicia-local/scripts/deploy_worker.sh
#
# Stops the worker, pulls latest code, compiles, and restarts.

set -euo pipefail

APP_DIR="/opt/galicia-local"

echo "=== Deploying Content Worker ==="

# Stop service first
echo "--- Stopping worker service ---"
sudo systemctl stop galicia-worker

# Run the rest as deploy user
sudo -u deploy bash -c "
  export MIX_ENV=worker
  export PATH=\"\$HOME/.asdf/bin:\$HOME/.asdf/shims:\$PATH\"
  cd $APP_DIR

  echo '--- Pulling latest code ---'
  git pull origin master

  echo '--- Installing dependencies ---'
  mix deps.get

  echo '--- Compiling (forced for compile_env changes) ---'
  mix compile --force
"

# Restart service
echo "--- Starting worker service ---"
sudo systemctl start galicia-worker

echo ""
echo "=== Deploy complete! ==="
echo "Check status: sudo systemctl status galicia-worker"
echo "Check health: curl http://localhost:4001/health"
echo "Check logs:   journalctl -u galicia-worker -f"
