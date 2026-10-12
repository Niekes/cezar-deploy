# syntax=docker/dockerfile:1
#
# cezar cockpit image.
#
# cezar (https://cezar.run) is distributed as an npm package only, so this image
# bakes it plus its most-tested agent backend (Claude Code) and the GitHub CLI
# into a small, reproducible container. It serves the cockpit on :4321 and is
# meant to sit behind a reverse proxy (e.g. Traefik, Dokploy) that terminates
# TLS and enforces authentication — cezar itself has no auth.

FROM node:22-bookworm

# Pin these for reproducible deploys.
ARG CEZAR_VERSION=latest
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=0.162.1
ARG OPENCODE_VERSION=1.19.0
ARG PI_VERSION=1.1.0
ARG COPILOT_VERSION=1.0.95

# Match the owner of the host's repos bind mount (see docker-compose.yml).
ARG UID=1001
ARG GID=1001

# git + ssh for the repos and agents; curl/gnupg for the GitHub CLI repo.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      openssh-client \
      curl \
      ca-certificates \
      gnupg \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI (used by cezar for GitHub issues and PRs).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# cezar + the default agent backend.
RUN npm install --global \
      "@open-mercato/cezar@${CEZAR_VERSION}" \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

# Optional agent CLIs so the cockpit can offer every runner. They install as
# PATH binaries that cezar's startup detection probes (`bin --version`), so no
# extra config is needed — only a one-time `… login` per CLI (see README).
RUN npm install --global --no-fund --no-audit \
      "@openai/codex@${CODEX_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
      "@earendil-works/pi-coding-agent@${PI_VERSION}" \
      "@github/copilot@${COPILOT_VERSION}" \
 && npm cache clean --force

# Cursor CLI installs into $HOME/.local (root during the build). /root is not
# traversable by the unprivileged cezar user, so move the whole versioned
# package to /opt (world-readable) and symlink its launcher onto PATH as
# `agent`, which is what cezar runs.
RUN curl -fsSL https://cursor.com/install -o /tmp/cursor-install.sh \
 && bash /tmp/cursor-install.sh >/dev/null \
 && mv /root/.local/share/cursor-agent/versions/* /opt/cursor-agent \
 && ln -sfn /opt/cursor-agent/cursor-agent /usr/local/bin/agent \
 && rm -rf /root/.local \
 && rm -f /tmp/cursor-install.sh

# Junie CLI (JetBrains) — its shim resolves the install tree through
# $JUNIE_DATA, so move the tree to /opt and default that env var there.
RUN curl -fsSL https://junie.jetbrains.com/install.sh -o /tmp/junie-install.sh \
 && bash /tmp/junie-install.sh >/dev/null \
 && mv /root/.local/share/junie /opt/junie-data \
 && ln -sfn "$(ls -d /opt/junie-data/versions/*/ | head -1)" /opt/junie-data/current \
 && mv /root/.local/bin/junie /usr/local/bin/junie \
 && rm -rf /root/.local \
 && rm -f /tmp/junie-install.sh

# Unprivileged user matching the host UID/GID of the repos bind mount.
RUN groupadd -g "${GID}" cezar \
 && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash cezar

# Entrypoint fixes the repos bind mount and drops privileges when started as
# root (the compose file runs it as root); otherwise it runs in place.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER cezar
WORKDIR /srv/cezar/repos

# No OS keychain in a container -> store the secrets data key as a 0600 file.
ENV HOME=/home/cezar \
    JUNIE_DATA=/opt/junie-data \
    CEZ_NO_BANNER=1 \
    CEZ_SECRETS_KEYCHAIN=0

EXPOSE 4321

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:4321/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
