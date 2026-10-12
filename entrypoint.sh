#!/usr/bin/env bash
# Container entrypoint.
#
# Runs `cezar serve` on :4321. If the container is started as root (the compose
# file does this so it can fix bind-mount ownership), it prepares the repos
# directory, then drops to the unprivileged `cezar` user. Started as any other
# user, it just runs in place.
set -euo pipefail

REPOS_DIR="${CEZAR_REPOS_DIR:-/srv/cezar/repos}"
PORT=4321

if [ "$(id -u)" = "0" ]; then
  uid="$(id -u cezar)"
  gid="$(id -g cezar)"
  mkdir -p "${REPOS_DIR}"
  chown "${uid}:${gid}" "${REPOS_DIR}"
  RUN=(setpriv --reuid="${uid}" --regid="${gid}" --init-groups)
else
  mkdir -p "${REPOS_DIR}"
  RUN=()
fi

# Seed an empty git repo so "Open local folder…" / "Clone from GitHub…" have a
# ready workspace. Only done once; your own repos are never touched.
if [ ! -d "${REPOS_DIR}/.git" ]; then
  "${RUN[@]}" git -C "${REPOS_DIR}" init -q -b main
  "${RUN[@]}" git -C "${REPOS_DIR}" \
    -c user.email="${CEZAR_GIT_EMAIL:-cezar@local}" \
    -c user.name="${CEZAR_GIT_NAME:-cezar}" \
    commit -q --allow-empty -m "cezar workspace"
fi

exec "${RUN[@]}" cezar serve \
  --bind-host 0.0.0.0 --port "${PORT}" --no-open --repo "${REPOS_DIR}"
