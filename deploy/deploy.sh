#!/usr/bin/env bash
#
# Builds the client and ships everything to the server.
#
#   ./deploy.sh user@203.0.113.45
#   ./deploy.sh user@203.0.113.45 --backend-only     # skip the Flutter build
#
# The Flutter build runs here rather than on the server: compiling it needs
# ~2GB of RAM and a Flutter SDK, neither of which belongs on a €4 box whose job
# is to serve a game. The backend jar is built on the server, in Docker, where
# Maven and a JDK are already part of the image.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${1:-}"
shift || true
BACKEND_ONLY=false
for arg in "$@"; do
  [ "$arg" = "--backend-only" ] && BACKEND_ONLY=true
done

if [ -z "$REMOTE" ]; then
  echo "usage: $0 user@host [--backend-only]" >&2
  exit 2
fi

REMOTE_DIR=/srv/jeopard

say() { printf '\n\033[1;33m==>\033[0m %s\n' "$1"; }

if [ "$BACKEND_ONLY" = false ]; then
  say "building the client"
  # No --dart-define: the web build defaults to the origin it is served from, so
  # one bundle works on this host, on a LAN and on localhost.
  (cd "$REPO/app" && flutter build web --release)
fi

say "creating $REMOTE_DIR on $REMOTE"
ssh "$REMOTE" "sudo mkdir -p $REMOTE_DIR && sudo chown -R \$(id -u):\$(id -g) $REMOTE_DIR"

say "copying the stack"
# --delete on the web directory only: a stale main.dart.js served next to a new
# index.html is a broken app that looks like a cache problem.
rsync -az --delete "$REPO/app/build/web/" "$REMOTE:$REMOTE_DIR/web/"
rsync -az "$REPO/deploy/Caddyfile" "$REPO/deploy/docker-compose.yml" "$REMOTE:$REMOTE_DIR/"
rsync -az --exclude target "$REPO/backend/" "$REMOTE:$REMOTE_DIR/backend/"

say "checking the server has an .env"
if ! ssh "$REMOTE" "test -f $REMOTE_DIR/.env"; then
  rsync -az "$REPO/deploy/.env.example" "$REMOTE:$REMOTE_DIR/.env.example"
  cat >&2 <<EOF

  No .env on the server yet. On $REMOTE:

      cd $REMOTE_DIR
      cp .env.example .env
      openssl rand -base64 24        # paste as POSTGRES_PASSWORD
      \$EDITOR .env                  # set JEOPARD_HOST too

  Then run this script again.
EOF
  exit 1
fi

say "building and starting"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d --build"

say "waiting for health"
ssh "$REMOTE" "cd $REMOTE_DIR && for i in \$(seq 1 40); do
  if docker compose ps backend | grep -q healthy; then echo 'backend healthy'; exit 0; fi
  sleep 5
done; echo 'backend did not become healthy in 200s'; docker compose logs --tail 40 backend; exit 1"

HOST=$(ssh "$REMOTE" "grep '^JEOPARD_HOST=' $REMOTE_DIR/.env | cut -d= -f2")
say "deployed"
case "$HOST" in
  :*) echo "  http://$(echo "$REMOTE" | cut -d@ -f2)" ;;
  *)  echo "  https://$HOST" ;;
esac
