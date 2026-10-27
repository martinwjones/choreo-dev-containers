#!/bin/bash
# Builds the React web app and serves it on http://localhost:5173 in a Node container.
# Reads web/.env, which deploy.sh writes. Safe to re-run (re-run after editing web/);
# stop with: docker rm -f recipe-chat-web
#
# Serves the production build with `vite preview` rather than the dev server: the dev server
# watches files, and the VM's inotify instances are used up by the k3d cluster (EMFILE).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"

NODE_IMAGE=node:22.21.1-alpine
[[ -f "$HERE/web/.env" ]] || die "web/.env is missing. Run deploy.sh first."

docker rm -f recipe-chat-web >/dev/null 2>&1 || true
# Host network: the browser reaches it on localhost:5173, the same origin ThunderID redirects to.
# unless-stopped: Docker starts it again after a VM or dev container restart.
docker run -d --name recipe-chat-web --network=host --restart unless-stopped \
  -v "$HERE/web:/app" -w /app "$NODE_IMAGE" \
  sh -c 'npm ci --no-audit --no-fund && npm run build && npx vite preview --port 5173 --strictPort' >/dev/null

log "Installing packages, building and starting the web server"
wait_for_url http://localhost:5173 300
cat <<EOF

  Web app:  http://localhost:5173   (sign in as chef / chef)
  Logs:     docker logs -f recipe-chat-web
EOF
