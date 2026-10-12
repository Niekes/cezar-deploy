# cezar on Docker + Traefik

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Self-host the [cezar](https://cezar.run) cockpit for your AI coding agents
(Claude Code, Codex, OpenCode …) on any VPS with Docker and Traefik — including
[Dokploy](https://dokploy.com). Traefik terminates **HTTPS** and enforces
**HTTP Basic Auth**; cezar runs 24/7 and you drive it from the browser.

> 🔐 **No secrets in this repo.** Domain, credentials and paths are all
> environment variables — see [`.env.example`](.env.example).

## What this is

- cezar ships as an **npm package only** (no official image), so the
  [`Dockerfile`](Dockerfile) builds one: Node 22 + cezar + Claude Code + `gh`.
- cezar has **no authentication of its own**, so a reverse proxy **must** sit in
  front of it. This template uses Traefik for **TLS + Basic Auth**.
- Routing/TLS/auth are declared as Traefik **labels** in
  [`docker-compose.yml`](docker-compose.yml) instead of Dokploy's *Domains* tab.
  Dokploy rewrites the compose file when you add a domain there, and its
  generated labels clash with the auth middleware — with labels only, Dokploy
  leaves the file untouched. The same file also works with a standalone Traefik.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the image: Node 22 + cezar + Claude Code + `gh`. |
| `entrypoint.sh` | Fixes the repos mount, seeds a workspace, drops privileges. |
| `docker-compose.yml` | Service, volumes and Traefik routing/auth labels. |
| `.env.example` | All configuration knobs, with defaults. |

## Configuration

Everything instance-specific is an environment variable. Copy `.env.example` to
`.env` (or, in Dokploy, paste the values into the **Environment** tab).

### Required

| Variable | Meaning |
|----------|---------|
| `CEZAR_DOMAIN` | Hostname Traefik serves cezar on. DNS must already point here. |
| `CEZAR_AUTH_USER` | Basic-Auth login name (an email works fine). |
| `CEZAR_AUTH_HASH` | Basic-Auth password hash — see below. |

### Optional

`CEZAR_REPOS_PATH`, `CEZAR_VERSION`, `CLAUDE_CODE_VERSION`, `CEZAR_UID`,
`CEZAR_GID`, `CEZAR_IMAGE`, `CEZAR_CONTAINER_NAME`, `CEZAR_GIT_NAME`,
`CEZAR_GIT_EMAIL`, `TZ` and the `TRAEFIK_*` wiring — all with sensible defaults,
documented in `.env.example`.

### The Basic-Auth password

cezar has no login of its own, so Traefik enforces HTTP Basic Auth. Generate the
hash from your chosen password:

```bash
openssl passwd -apr1 'your-password'
```

Set it one of two ways — both are correct:

- **Plain `.env`**: keep the value in **single quotes** so its `$` stay literal:
  `CEZAR_AUTH_HASH='$apr1$…'`
- **Dokploy Environment tab**: paste it **exactly as printed** (single `$`).
  Dokploy escapes `$` itself when it writes its `.env`.

> ⚠️ Do **not** hand-double the `$` to `$$`. Dokploy already escapes it, so `$$`
> would survive literally and the login would never match.

> ⚠️ `CEZAR_AUTH_HASH` must be a **hash**, never the password itself. Traefik's
> Basic Auth only accepts `$apr1$…` (MD5), `{SHA}…` or `$2y$…` (bcrypt); a plain
> password or passphrase makes every login fail with `401`.

After changing any value, redeploy so the labels are re-rendered.

## Deploy

### 1. DNS first

Create an **A record** for `CEZAR_DOMAIN` pointing at the server's public IPv4
(and **AAAA** for IPv6 if you serve it). Traefik requests the certificate via
the HTTP challenge on port 80, so DNS must be live before the first deploy.

### Option A — Dokploy

1. *Create Service → Docker Compose*. Source = **Git**, point it at this repo,
   set **Compose Path** to `./docker-compose.yml`.
2. **Leave the *Domains* tab empty** — routing lives in the compose labels.
3. In the **Environment** tab set `CEZAR_DOMAIN`, `CEZAR_AUTH_USER`,
   `CEZAR_AUTH_HASH` (plus any optional overrides).
4. Click **Deploy**. Dokploy clones the repo, builds the image and starts the
   container on `dokploy-network`. The first build takes a few minutes.

### Option B — plain Docker + Traefik

```bash
cp .env.example .env      # then edit it
docker compose up -d --build
```

This expects an external Traefik network named by `TRAEFIK_NETWORK`
(`dokploy-network` by default), with `web`/`websecure` entrypoints and a
`letsencrypt` certresolver.

Then open `https://<CEZAR_DOMAIN>` and log in with `CEZAR_AUTH_USER` + password.

## First-run setup

cezar shells out to the agent CLIs; log them in **inside the container** so the
credentials land in the persistent `cezar_home` volume:

```bash
docker exec -it cezar claude          # one-time Claude Code login
docker exec -it cezar gh auth login   # optional: GitHub issues/PRs
```

(the container name is `CEZAR_CONTAINER_NAME`, default `cezar`)

Then in the cockpit, **Settings → Projects → Add project → Open local folder…**
and register repos under `/srv/cezar/repos` (or clone them there with *Clone
from GitHub…*). That path is the `CEZAR_REPOS_PATH` bind mount on the host.

## Updating

Bump `CEZAR_VERSION` / `CLAUDE_CODE_VERSION` (or edit the `Dockerfile`) and
redeploy — the image is the source of truth. Don't let cezar self-update inside
the container.

## Operating notes

- **Persistence**: workspace config, the Claude/`gh` logins and secrets live in
  the `cezar_home` volume; recreating the container keeps them.
- **Ownership**: the container starts as root *only* to `chown` the repos bind
  mount to its unprivileged `cezar` user, then drops privileges — your host
  files are never left owned by root.
- **Resources**: each agent run is a full checkout plus a CLI process. Give the
  box headroom, or lower cezar's parallel cap in *Settings → Resources*.
- **Troubleshooting**:
  - `docker logs -f cezar` — cockpit + agent output.
  - 502 from Traefik → the container isn't healthy yet; check the logs.
  - Change the Basic-Auth password: `openssl passwd -apr1 'newpass'`, update
    `CEZAR_AUTH_HASH` in the *Environment* tab, redeploy.

## License

[MIT](LICENSE)
