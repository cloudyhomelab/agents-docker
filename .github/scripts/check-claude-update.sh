#!/usr/bin/env bash

set -euo pipefail

CLAUDE_VERSION_VAR_NAME="CLAUDE_VERSION"
CLAUDE_VERSION_CHECK_URL="https://api.github.com/repos/anthropics/claude-code/releases/latest"
LATEST_JSON_FILE=$(mktemp)
curl -fssL "${CLAUDE_VERSION_CHECK_URL}" --output "${LATEST_JSON_FILE}"

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
