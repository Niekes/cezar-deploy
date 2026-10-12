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
    CEZ_NO_BANNER=1 \
    CEZ_SECRETS_KEYCHAIN=0

EXPOSE 4321

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:4321/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
