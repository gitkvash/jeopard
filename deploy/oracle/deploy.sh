#!/usr/bin/env bash
#
# Builds the client here and ships jeopard to the Oracle VM it shares with linkup.
#
#   ./deploy/oracle/deploy.sh                       # ubuntu@158.180.18.180
#   ./deploy/oracle/deploy.sh ubuntu@1.2.3.4
#   ./deploy/oracle/deploy.sh ubuntu@1.2.3.4 --backend-only    # skip the Flutter build
#
# The Flutter build runs on this machine: it needs a Flutter SDK and ~2GB of RAM,
# which the VM has better uses for. The backend jar is built on the VM, in Docker.
# Files travel as tar over ssh, so nothing but ssh is needed locally (Windows has
# no rsync).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE="${1:-ubuntu@158.180.18.180}"
BACKEND_ONLY=false
for arg in "${@:2}"; do
  [ "$arg" = "--backend-only" ] && BACKEND_ONLY=true
done

APP=/opt/jeopard
EDGE=/opt/edge/conf.d
say() { printf '\n\033[1;33m==>\033[0m %s\n' "$1"; }

if ! ssh "$REMOTE" "test -f $APP/.env && docker network inspect edge >/dev/null 2>&1"; then
  cat >&2 <<EOF
$REMOTE is not ready: it needs $APP/.env and the 'edge' docker network.
Run deploy/oracle/bootstrap.sh there first, then fill in .env from deploy/oracle/env.example.
EOF
  exit 1
fi
HOST=$(ssh "$REMOTE" "grep '^JEOPARD_HOST=' $APP/.env | cut -d= -f2")
[ -n "$HOST" ] || { echo "JEOPARD_HOST is empty in $APP/.env" >&2; exit 1; }

if [ "$BACKEND_ONLY" = false ]; then
  say "building the client"
  # No --dart-define: the web build uses the origin it is served from.
  (cd "$REPO/app" && flutter build web --release)
fi

say "shipping the backend source and compose file"
# Replace, don't merge: a deleted source file must not survive in the build context.
tar -C "$REPO" --exclude=backend/target -czf - backend \
  | ssh "$REMOTE" "rm -rf $APP/backend && tar -xzf - -C $APP"
scp -q "$REPO/deploy/oracle/docker-compose.yml" "$REMOTE:$APP/docker-compose.yml"

if [ "$BACKEND_ONLY" = false ]; then
  say "shipping the client"
  # Wiped first: a stale main.dart.js beside a new index.html is a broken app that
  # looks like a cache problem. The directory itself stays, since it is bind-mounted.
  tar -C "$REPO/app/build/web" -czf - . \
    | ssh "$REMOTE" "find $APP/web -mindepth 1 -delete && tar -xzf - -C $APP/web"
fi

say "installing the Caddy site for $HOST"
sed "s/__HOST__/$HOST/" "$REPO/deploy/oracle/caddy-site.tmpl" \
  | ssh "$REMOTE" "cat > $EDGE/jeopard.caddy"

say "building and starting"
ssh "$REMOTE" "cd $APP && docker compose up -d --build --wait --wait-timeout 300" || {
  ssh "$REMOTE" "cd $APP && docker compose logs --tail 60 backend" >&2
  exit 1
}

say "reloading Caddy"
# `caddy validate` first: a bad site file must not take linkup's proxy down with it.
ssh "$REMOTE" "docker exec linkup-caddy-1 caddy validate --config /etc/caddy/Caddyfile >/dev/null \
  && docker exec linkup-caddy-1 caddy reload --config /etc/caddy/Caddyfile" || {
  echo "Caddy rejected the config; removing the jeopard site so linkup is unaffected." >&2
  ssh "$REMOTE" "rm -f $EDGE/jeopard.caddy"
  exit 1
}

say "deployed"
echo "  https://$HOST"
