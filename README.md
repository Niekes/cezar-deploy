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
  [`Dockerfile`](Dockerfile) builds one: Node 22 + cezar + Claude Code + `gh`
  plus the optional agent CLIs (Codex, OpenCode, Cursor, pi, Junie, Copilot).
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
| `Dockerfile` | Builds the image: Node 22 + cezar + Claude Code + `gh` + optional agent CLIs. |
| `entrypoint.sh` | Fixes the repos mount, seeds a workspace, drops privileges. |
| `docker-compose.yml` | Service, volumes and Traefik routing/auth labels. |
| `.env.example` | All configuration knobs, with defaults. |
| `meta.json` | Dokploy template index (this file *is* the template list). |
| `blueprints/cezar/` | Dokploy blueprint: `docker-compose.yml`, `template.toml`, `meta.json`, `logo.svg` (image-based, see Option C). |
| `.github/workflows/docker-publish.yml` | CI: builds + publishes `ghcr.io/niekes/cezar` on every push to `main`. |

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

### Option C — Dokploy template (one-click blueprint)

The repo doubles as a Dokploy **template source**: the image is published to
`ghcr.io/niekes/cezar` by GitHub Actions, and `blueprints/cezar/` defines the
blueprint — so cezar installs from the Templates dialog exactly like the
official templates.

1. **Publish & expose the image** (once — the workflow runs automatically on
   push to `main`). After the first successful run make the package **public**
   so your server can pull it without credentials:
   GitHub → repo → *Packages* → `cezar` → *Package settings* →
   *Change visibility* → **Public**.
2. In **Dokploy**: *Create Service → Docker Compose → Templates*. In the
   template dialog set **Base URL (optional)** to
   `https://raw.githubusercontent.com/Niekes/cezar-deploy/main`.
3. Pick the **cezar** template and fill the three required fields
   (`cezar_domain`, `cezar_auth_user`, `cezar_auth_hash` — an `apr1` hash, see
   *The Basic-Auth password*). Everything else already has a default.
4. **Deploy**, then do the first-run logins below. The container name is the
   app name you gave it — find it with `docker ps | grep cezar`.

This is **the fastest way back** after a full server wipe (see below): no build
on the server, no `.env` to reconstruct — the template dialog *is* the config.

The blueprint sets `pull_policy: always`, so **every redeploy re-pulls the
image** and a freshly published `:latest` lands automatically (Dokploy itself
runs `docker compose up` without `--pull` and would otherwise keep the cached
image). To pin a specific build instead, change the blueprint's `image:` tag to
`ghcr.io/niekes/cezar:sha-<commit>`.

Then open `https://<CEZAR_DOMAIN>` and log in with `CEZAR_AUTH_USER` + password.

## First-run setup

cezar shells out to the agent CLIs; log them in **inside the container** so the
credentials land in the persistent `cezar_home` volume. The compose file starts
the container as root, so pass `-u 1001` (the `cezar` user) — otherwise the CLI
login runs as root, writes root-owned `0600` credential files that the cezar
process can't read, and the cockpit keeps showing them as unavailable:

```bash
docker exec -u 1001 -it cezar claude            # one-time Claude Code login
docker exec -u 1001 -it cezar gh auth login     # optional: GitHub issues/PRs
```

Restart the container afterwards so cezar re-runs its startup detection:
`docker restart cezar` (the log should then show `✓ claude` / `✓ gh
authenticated`).

(the container name is `CEZAR_CONTAINER_NAME`, default `cezar`; for a
template-created app it is the app name you typed in Dokploy —
`docker ps | grep cezar` finds it)

### Optional runners (codex, opencode, cursor, pi, junie, copilot)

The image bakes in all six CLIs, so the banner lists them as installed. Each still
needs a one-time login before you can actually use it — always as the `cezar`
user, then restart:

| Runner | Login (inside the container) |
| --- | --- |
| codex | `docker exec -u 1001 -it cezar codex login` — ChatGPT OAuth, a URL is printed |
| opencode | `docker exec -u 1001 -it cezar opencode auth login` — choose a provider (Anthropic/OpenAI…): OAuth or API key |
| cursor | `docker exec -u 1001 -it cezar agent login` — Cursor OAuth in your browser |
| pi | `docker exec -u 1001 -it cezar pi` — first-run interactive sign-in |
| junie | `docker exec -u 1001 -it cezar junie` — welcome screen: JetBrains account OAuth, or a Junie API key from <https://junie.jetbrains.com/cli> |
| copilot | `docker exec -u 1001 -it cezar copilot login` — GitHub OAuth (reuses your `gh` account) |

Note that the banner's `✓` only means "CLI installed" (cezar probes `--version`);
it does **not** mean "authenticated" — an unauthenticated runner fails when you
start a task on it, so do the logins above once per container lifetime (they
persist in the `cezar_home` volume).

Then in the cockpit, **Settings → Projects → Add project → Open local folder…**
and register repos under `/srv/cezar/repos` (or clone them there with *Clone
from GitHub…*). That path is the `CEZAR_REPOS_PATH` bind mount on the host.

## Recreate from scratch (server wipe)

Nothing on the server is part of the setup — the repo is the only input. Wiping
Dokploy and the host is fine; the following brings cezar back:

1. **Install Dokploy** fresh (it creates the `dokploy-network` Traefik attaches to).
2. **Project → New service → type `Compose`**.
3. **Source**: your GitHub account, repo `Niekes/cezar-deploy`, branch `main`
   (or any commit/tag you pinned).
4. Leave the **Domains tab empty** — routing, TLS and Basic Auth come from the
   Traefik labels in the compose file, so a Dokploy-injected domain would clash.
5. **Environment tab**: paste the *required* variables (`CEZAR_DOMAIN`,
   `CEZAR_AUTH_USER`, `CEZAR_AUTH_HASH` — an `apr1` hash, keep single quotes so
   the `$` stay literal). Optional knobs as you like; everything has a default.
6. **Deploy** and wait for `healthy`.
7. Do the first-run logins (previous section).

Automatically recreated: the `cezar_home` volume, the repos bind mount
(`CEZAR_REPOS_PATH`, seeded + chowned by the entrypoint), the image build and
the Let's Encrypt certificate. The password hash and any secrets are **never**
in the repo — you re-enter them in the Environment tab. What you lose on a wipe
(by design): provider logins, workspaces and the Basic-Auth password hash.

The same file works without Dokploy, against a standalone Traefik:
`cp .env.example .env && ${EDITOR:-vi} .env && docker compose up -d --build`.

Fastest path on a fresh Dokploy: **Option C** — Templates dialog, Base URL
`https://raw.githubusercontent.com/Niekes/cezar-deploy/main`, pick *cezar*, fill
the three required fields, deploy.

## Updating

Bump `CEZAR_VERSION` / `CLAUDE_CODE_VERSION` (or the optional `CODEX_VERSION`,
`OPENCODE_VERSION`, `PI_VERSION`, `COPILOT_VERSION` ARGs in the `Dockerfile`) and
redeploy — the image is the source of truth. Don't let cezar self-update inside
the container.

With **Option C** (published image) an update is: merge to `main` → CI pushes a
new `ghcr.io/niekes/cezar:latest` → *Redeploy* in Dokploy (pulls the new image).
To pin a specific build, bump the blueprint's `image:` tag to
`ghcr.io/niekes/cezar:sha-<commit>`.

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
