#!/usr/bin/env bash
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Bumps the pinned agent CLI versions in docker-bake.hcl to whatever upstream
# currently publishes, and records what moved so the calling workflow can name
# it in the commit message and PR body.
#
# Run from the repository root. Set BUMP_LOG to collect the bumps; a local run
# can leave it unset and the log is discarded.

# shellcheck source=.github/scripts/check-updates-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/check-updates-lib.sh"

# One row per pinned version: the docker-bake.hcl variable, where to look up
# the current release, and which project to look up. The label used in output
# and in the bump log is the variable name lowercased without its _VERSION
# suffix, so there is no second place to keep the agent's name.
#
#      <bake variable>  <source>        <project>
CHECKS=(
  "CLAUDE_VERSION      github-release   anthropics/claude-code"
  "CODEX_VERSION       npm-dist-tag     @openai/codex"
  "GEMINI_VERSION      npm-dist-tag     @google/gemini-cli"
)

# These are called as $(...), and a function body running inside a command
# substitution does not honour errexit -- a failed fetch would otherwise fall
# through to the parse and yield an empty version. Hence the explicit
# `|| return` here and the checked call site below.
github_release_version() {
  local repo="$1"
  local response="${SCRATCH}/${repo//\//_}.json"
  local auth_config=""

  # Authenticated whenever a token is around: the anonymous api.github.com
  # limit is per IP and shared with every other Actions runner, so an
  # unauthenticated check works most days and 403s the rest.
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [[ -n ${token} ]]; then
    auth_config="header = \"Authorization: Bearer ${token}\""
  else
    echo "no GITHUB_TOKEN or GH_TOKEN; falling back to the anonymous rate limit" >&2
  fi

  # The token goes in via --config on stdin, not as a -H flag, to keep it out
  # of the process list; an empty config is fine and simply sends no header.
  # -S as well as -f, because -f alone reports a 403 as a bare exit code with
  # no hint of which limit was hit.
  curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      --config - --output "${response}" \
      "https://api.github.com/repos/${repo}/releases/latest" \
      <<<"${auth_config}" || return 1

  jq -r '.tag_name | ltrimstr("v")' "${response}"
}

npm_dist_tag_version() {
  npm show "$1" version --json | jq -r .
}

latest_version() {
  case "$1" in
    github-release) github_release_version "$2" ;;
    npm-dist-tag)   npm_dist_tag_version "$2" ;;
    *)              echo "unknown source '$1'" >&2; return 1 ;;
  esac
}

main() {
  set -euo pipefail
  local check variable source project label latest current written

  [[ -f ${BAKE_FILE} ]] || fail "no ${BAKE_FILE} here; run this from the repository root"

  SCRATCH=$(mktemp -d)
  trap 'rm -rf "${SCRATCH}"' EXIT

  for check in "${CHECKS[@]}"; do
    # The columns are space-separated, so word splitting is the whole parse.
    read -r variable source project <<<"${check}"

    label="${variable%_VERSION}"
    label="${label,,}"

    if ! latest=$(latest_version "${source}" "${project}"); then
      fail "${label} - could not determine the latest version"
    fi
    is_version "${latest}" \
      || fail "${label} - upstream gave '${latest}', which is not a version"

    current=$(current_version "${label}" "${variable}")
    is_version "${current}" \
      || fail "${label} - read '${current}' as the current ${variable} from ${BAKE_FILE}"

    echo "${label} - current version - ${current} ... latest version - ${latest}"

    if [[ "${current}" == "${latest}" ]]; then
      echo "${label} - No update found"
      continue
    fi

    bump_version "${variable}" "${current}" "${latest}"

    # The rewrite is a regex over one line: a miss would leave the pin untouched
    # while the run still reported success, which is how the pins would quietly
    # freeze.
    written=$(current_version "${label}" "${variable}")
    [[ ${written} == "${latest}" ]] \
      || fail "${label} - ${variable} still reads '${written}' after the rewrite"

    # Recorded so the workflow can name what moved in the commit message and PR
    # body; discarded by default, because a local run has nothing to tell.
    printf '%s %s %s\n' "${label}" "${current}" "${latest}" \
      >> "${BUMP_LOG:-/dev/null}"
  done
}

main "$@"
