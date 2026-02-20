#!/bin/bash

# Deploy GaliciaLocal using Depot + Fly.io
# Usage: ./scripts/deploy.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_NAME="galicia-local"
TAG="deploy-$(date +%Y%m%d-%H%M%S)"

echo -e "${GREEN}🐚 Deploying GaliciaLocal using Depot${NC}"

# Check prerequisites
if ! command -v depot &> /dev/null; then
    echo -e "${RED}❌ Depot CLI not found${NC}"
    echo "Install: https://depot.dev/docs/installation"
    exit 1
fi

if ! command -v fly &> /dev/null; then
    echo -e "${RED}❌ Fly CLI not found${NC}"
    exit 1
fi

if ! depot whoami &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Depot${NC}"
    depot login
fi

echo "App: $APP_NAME"
echo "Tag: $TAG"

# Authenticate with Fly registry
echo -e "${GREEN}🔐 Authenticating with Fly registry...${NC}"
fly auth docker

# Build and push with Depot
echo -e "${GREEN}📦 Building with Depot...${NC}"
depot build \
    --push \
    --platform linux/amd64 \
    --tag registry.fly.io/$APP_NAME:$TAG \
    --tag registry.fly.io/$APP_NAME:latest \
    --build-arg MIX_ENV=prod \
    .

echo -e "${GREEN}✅ Build complete!${NC}"

# Deploy to Fly
echo -e "${GREEN}🚁 Deploying to Fly.io...${NC}"
fly deploy \
    --image registry.fly.io/$APP_NAME:$TAG \
    --strategy immediate

echo -e "${GREEN}🔍 Waiting for deploy...${NC}"
sleep 15

URL="https://galicia-local.fly.dev"
if curl -sf "$URL" > /dev/null; then
    echo -e "${GREEN}✅ App is live at $URL${NC}"
else
    echo -e "${YELLOW}⚠️  App may still be starting - check: $URL${NC}"
    echo "Logs: fly logs -a $APP_NAME"
fi

# Worker VPS deployment DISABLED (2026-02-20) — paused to reduce costs.
# The worker VPS (89.167.60.204) should be fully stopped.
# To re-enable, uncomment the block below and restore worker.exs Oban config.
#
# WORKER_HOST="deploy@89.167.60.204"
# echo ""
# echo -e "${GREEN}🔧 Deploying Content Worker...${NC}"
#
# if ssh -o ConnectTimeout=5 "$WORKER_HOST" "true" 2>/dev/null; then
#     ssh "$WORKER_HOST" 'export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH" && cd /opt/galicia-local && git pull origin master && MIX_ENV=worker mix deps.get && MIX_ENV=worker mix compile --force'
#     ssh "$WORKER_HOST" 'sudo systemctl restart galicia-worker'
#     sleep 5
#     if ssh "$WORKER_HOST" 'curl -sf http://localhost:4001/health' > /dev/null; then
#         echo -e "${GREEN}✅ Worker is healthy${NC}"
#     else
#         echo -e "${YELLOW}⚠️  Worker health check failed - check: ssh $WORKER_HOST journalctl -u galicia-worker -f${NC}"
#     fi
# else
#     echo -e "${YELLOW}⚠️  Cannot reach worker VPS ($WORKER_HOST), skipping worker deploy${NC}"
# fi

echo -e "${GREEN}🎉 Deployment complete!${NC}"
