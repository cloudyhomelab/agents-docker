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

# One row per pinned version: the docker-bake.hcl variable and the npm package
# whose latest dist-tag it follows. The label used in output and in the bump
# log is the variable name lowercased without its _VERSION suffix, so there is
# no second place to keep the agent's name.
#
#      <bake variable>  <package>
CHECKS=(
  "CLAUDE_VERSION      @anthropic-ai/claude-code"
  "CODEX_VERSION       @openai/codex"
  "GEMINI_VERSION      @google/gemini-cli"
)

latest_version() {
  npm show "$1" version --json | jq -r .
}

main() {
  set -euo pipefail
  local check variable package label latest current written

  [[ -f ${BAKE_FILE} ]] || fail "no ${BAKE_FILE} here; run this from the repository root"

  for check in "${CHECKS[@]}"; do
    # The columns are space-separated, so word splitting is the whole parse.
    read -r variable package <<<"${check}"

    label="${variable%_VERSION}"
    label="${label,,}"

    # Called as $(...), where a failed fetch would not trip errexit and would
    # fall through to the parse as an empty version; hence the checked call.
    if ! latest=$(latest_version "${package}"); then
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
