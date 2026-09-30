#!/usr/bin/env bash
# One-time preparation of the VM that already runs linkup. From your machine:
#
#   scp deploy/oracle/bootstrap.sh ubuntu@158.180.18.180:
#   ssh ubuntu@158.180.18.180 'bash bootstrap.sh'
#
# Docker and the firewall are already set up by linkup's bootstrap. This only adds
# what jeopard needs, and it MUST run before linkup's Caddy is redeployed with the
# `edge` network and the jeopard bind mounts: docker refuses to start a container
# that references a missing external network, and would create a missing bind
# source owned by root, which deploy.sh could then not write to.
#
# Safe to re-run.
set -euo pipefail

docker network inspect edge >/dev/null 2>&1 || docker network create edge

# /opt/jeopard/web  the Flutter build, served by linkup's Caddy
# /opt/edge/conf.d  site files that linkup's Caddyfile imports
#
# /opt belongs to root, so create them with sudo and hand them to the deploy user.
# An empty conf.d is a valid import; Caddy just loads nothing from it.
me=$(id -un)
sudo install -d -o "$me" -g "$me" -m 755 /opt/jeopard /opt/jeopard/web /opt/edge /opt/edge/conf.d

echo "Done. Next:"
echo "  1. create /opt/jeopard/.env from deploy/oracle/env.example (chmod 600)"
echo "  2. deploy linkup's updated Caddy config (edge network + mounts)"
echo "  3. run deploy/oracle/deploy.sh from your machine"
