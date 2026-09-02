#!/usr/bin/env bash

set -euo pipefail

CLAUDE_VERSION_VAR_NAME="CLAUDE_VERSION"
CLAUDE_VERSION_CHECK_URL="https://api.github.com/repos/anthropics/claude-code/releases/latest"

LATEST_JSON_FILE=$(mktemp)
trap 'rm -f "${LATEST_JSON_FILE}"' EXIT

# Authenticated whenever a token is around: the anonymous api.github.com limit
# is per IP and shared with every other Actions runner, so an unauthenticated
# check works most days and 403s the rest.
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -n ${GITHUB_TOKEN} ]]; then
  AUTH_CONFIG="header = \"Authorization: Bearer ${GITHUB_TOKEN}\""
else
  AUTH_CONFIG=""
  echo "no GITHUB_TOKEN or GH_TOKEN; falling back to the anonymous rate limit" >&2
fi

# The token goes in via --config on stdin, not as a -H flag, to keep it out of
# the process list; an empty config is fine and simply sends no header. -S as
# well as -f, because -f alone reports a 403 as a bare exit code with no hint
# of which limit was hit.
curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    --config - --output "${LATEST_JSON_FILE}" "${CLAUDE_VERSION_CHECK_URL}" \
    <<<"${AUTH_CONFIG}"

LATEST_VERSION=$(jq -r '.tag_name | ltrimstr("v")' "${LATEST_JSON_FILE}")
CURRENT_VERSION=$(
  awk -F'"' -v var="${CLAUDE_VERSION_VAR_NAME}" \
  '$0 ~ "variable \"" var "\"" {print $4}' docker-bake.hcl
)
echo "current version - $CURRENT_VERSION ... latest version - $LATEST_VERSION"

if [[ "${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
  echo "No update found"
else
  awk -v var="${CLAUDE_VERSION_VAR_NAME}" -v cur="${CURRENT_VERSION}" -v ver="${LATEST_VERSION}" '
    $0 ~ "^variable \"" var "\"" && $0 ~ "\"" cur "\"" {
      sub("default *= *\"" cur "\"", "default = \"" ver "\"")
    }
    { print }
  ' docker-bake.hcl > docker-bake.hcl.tmp
  mv docker-bake.hcl.tmp docker-bake.hcl

  # Recorded so the workflow can name what moved in the commit message and PR
  # body; discarded by default, because a local run has nothing to tell.
  printf '%s %s %s\n' "claude" "${CURRENT_VERSION}" "${LATEST_VERSION}" \
    >> "${BUMP_LOG:-/dev/null}"
fi
