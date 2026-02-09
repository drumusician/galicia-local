#!/bin/bash
# Setup script for the Content Worker VPS (Hetzner CX22 / Ubuntu 24.04)
# Run as root on a fresh VPS.
#
# Usage: curl -sSL <raw-url> | bash
#   or:  bash scripts/setup_worker.sh

set -euo pipefail

echo "=== GaliciaLocal Content Worker Setup ==="

# --- System updates ---
apt-get update && apt-get upgrade -y
apt-get install -y git curl build-essential autoconf m4 libncurses5-dev \
  libwxgtk3.2-dev libwxgtk-webview3.2-dev libgl1-mesa-dev libglu1-mesa-dev \
  libpng-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils \
  libssl-dev inotify-tools postgresql-client

# --- Create deploy user ---
if ! id deploy &>/dev/null; then
  useradd -m -s /bin/bash deploy
  echo "Created deploy user"
fi

# --- Install asdf for deploy user ---
su - deploy -c '
  if [ ! -d "$HOME/.asdf" ]; then
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.1
    echo ". \$HOME/.asdf/asdf.sh" >> ~/.bashrc
    echo ". \$HOME/.asdf/completions/asdf.bash" >> ~/.bashrc
  fi

  export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"

  # Install Erlang
  asdf plugin add erlang || true
  asdf install erlang 27.2.1
  asdf global erlang 27.2.1

  # Install Elixir
  asdf plugin add elixir || true
  asdf install elixir 1.18.3-otp-27
  asdf global elixir 1.18.3-otp-27

  # Install hex and rebar
  mix local.hex --force
  mix local.rebar --force
'

# --- Create data directories ---
mkdir -p /data/research /data/discovery
chown -R deploy:deploy /data

# --- Create app directory ---
mkdir -p /opt/galicia-local
chown -R deploy:deploy /opt/galicia-local

# --- Clone repo (deploy user) ---
su - deploy -c '
  if [ ! -d /opt/galicia-local/.git ]; then
    git clone https://github.com/your-org/galicia_local.git /opt/galicia-local
  fi
'

# --- Install Claude CLI ---
echo "Installing Claude CLI..."
npm install -g @anthropic-ai/claude-code 2>/dev/null || {
  # Install Node.js first if npm not available
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  npm install -g @anthropic-ai/claude-code
}

# --- Create systemd service ---
cat > /etc/systemd/system/galicia-worker.service << 'SYSTEMD'
[Unit]
Description=GaliciaLocal Content Worker
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/galicia-local
EnvironmentFile=/opt/galicia-local/.env
Environment=MIX_ENV=worker
Environment=LANG=en_US.UTF-8
ExecStart=/home/deploy/.asdf/shims/elixir --sname worker -S mix run --no-halt
Restart=always
RestartSec=10
SyslogIdentifier=galicia-worker

# Resource limits
LimitNOFILE=65536
MemoryMax=3G

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable galicia-worker

# --- Create env file template ---
if [ ! -f /opt/galicia-local/.env ]; then
  cat > /opt/galicia-local/.env << 'ENV'
DATABASE_URL=postgresql://user:pass@host:5432/dbname
SECRET_KEY_BASE=generate-with-mix-phx-gen-secret
TOKEN_SIGNING_SECRET=generate-a-secret
ENABLE_CLI_ENRICHMENT=true
APPSIGNAL_PUSH_API_KEY=your-appsignal-key
POSTMARK_API_KEY=your-postmark-key
PHX_HOST=startlocal.app
ENV
  chown deploy:deploy /opt/galicia-local/.env
  chmod 600 /opt/galicia-local/.env
  echo ""
  echo "IMPORTANT: Edit /opt/galicia-local/.env with your actual secrets!"
fi

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "1. Edit /opt/galicia-local/.env with actual secrets"
echo "2. Run: sudo -u deploy bash /opt/galicia-local/scripts/deploy_worker.sh"
echo "3. Start: sudo systemctl start galicia-worker"
echo "4. Check logs: journalctl -u galicia-worker -f"
