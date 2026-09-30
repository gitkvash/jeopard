# Jeopard on the Oracle VM it shares with linkup

Linkup's Caddy owns ports 80/443 on the VM (`158.180.18.180`, Always Free, arm64, Frankfurt), so
jeopard does not run a proxy of its own. It runs the backend and Postgres, and linkup's Caddy serves
it as a second site:

```
https://<jeopard host> ─► linkup's Caddy ─┬─ /            → /opt/jeopard/web  (Flutter build, bind mount)
                                           └─ /api /ws     → jeopard-backend:8080  (`edge` network)
                                                              └── Postgres (private, not published)
```

This is the same single-origin layout as the standalone stack in [`../`](../docker-compose.yml), for
the same reason: a page served over https cannot open a plain `ws://` socket.

Linkup needs three small changes to take part (already made in its `deploy/oracle/`): the `edge`
network, two bind mounts, and `import /etc/caddy/conf.d/*` in its Caddyfile. Jeopard's site block is
installed into `/opt/edge/conf.d/jeopard.caddy` by `deploy.sh`, so linkup never needs to know its
hostname.

## First time

Order matters; step 3 breaks linkup's Caddy if 1 has not happened.

1. **Prepare the VM** (creates the `edge` network and the two directories):
   ```bash
   scp deploy/oracle/bootstrap.sh ubuntu@158.180.18.180:
   ssh ubuntu@158.180.18.180 'bash bootstrap.sh'
   ```
2. **Write `/opt/jeopard/.env`** from [`env.example`](env.example), `chmod 600`. `JEOPARD_HOST` is
   `jeopard-kvasho.duckdns.org`, which must point at the VM before the first deploy (DuckDNS names
   are added on duckdns.org while signed in). An sslip.io name needs no registration but shares a
   Let's Encrypt quota with everyone who uses it.
3. **Redeploy linkup** so its Caddy joins `edge` and mounts the two directories (push its `main`, or
   run its "Deploy (Oracle)" workflow). This restarts linkup's Caddy: a few seconds of downtime.
4. **Deploy jeopard** from this machine (Flutter and ssh needed, no rsync):
   ```bash
   ./deploy/oracle/deploy.sh                      # add --backend-only to skip the Flutter build
   ```

## Operating it

```bash
ssh ubuntu@158.180.18.180
cd /opt/jeopard
docker compose ps
docker compose logs -f backend
```

Redeploying is step 4 again. The database lives in the `jeopard_pgdata` volume and survives it.
`deploy.sh` runs `caddy validate` before reloading, and removes its site file if Caddy rejects it, so
a mistake here cannot take linkup's proxy down.

## Switching over from Render

Native builds bake in their server: rebuild them with `--dart-define=API_BASE=https://<jeopard host>`.
The web build follows whatever origin serves it. Suspend the Render service once the new host works.
Games in progress on Render are not carried over; the seeder fills the content of a fresh database.
