#!/usr/bin/env bash
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Bumps the pinned agent-base tag and digest in docker-bake.hcl to the newest
# tag the base publish has landed on Docker Hub, and records the bump so the
# calling workflow can name it in the commit message and PR body.
#
# Run from the repository root. Set BUMP_LOG to collect the bump; a local run
# can leave it unset and the log is discarded.

# shellcheck source=.github/scripts/check-updates-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/check-updates-lib.sh"

# The base publish tags yyyy.mm.dd.hhmm in UTC, so the newest tag is the
# greatest one under a plain string sort; latest and anything else on the
# repository are left out.
BASE_TAG_SHAPE='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$'

# Reads Docker Hub's tag listing on stdin and prints "<tag> <digest>" for the
# newest base tag in it. -e makes a listing without one jq's failure.
newest_base_tag() {
  jq -er --arg shape "${BASE_TAG_SHAPE}" '
    [.results[] | select(.name | test($shape))]
    | sort_by(.name)
    | last
    | select(. != null)
    | "\(.name) \(.digest)"
  '
}

is_digest() {
  [[ $1 =~ ^sha256:[0-9a-f]{64}$ ]]
}

# The pin as a build sees it, read back through bake rather than by parsing the
# HCL: "<registry>/<namespace>/agent-base:<tag>[@<digest>]".
current_base_image() {
  docker buildx bake --file "${BAKE_FILE}" --progress=quiet --print \
    | jq -er '.target.claude.args.BASE_IMAGE'
}

main() {
  set -euo pipefail
  local image ref repo current_tag current_digest latest_tag latest_digest

  [[ -f ${BAKE_FILE} ]] || fail "no ${BAKE_FILE} here; run this from the repository root"

  SCRATCH=$(mktemp -d)
  trap 'rm -rf "${SCRATCH}"' EXIT

  image=$(current_base_image) || fail "could not read BASE_IMAGE from ${BAKE_FILE}"
  ref="${image%%@*}"
  current_tag="${ref##*:}"
  current_digest=""
  [[ ${image} != *@* ]] || current_digest="${image##*@}"
  # Docker Hub's API names repositories without the registry host.
  repo="${ref%:*}"
  repo="${repo#docker.io/}"

  curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
      --output "${SCRATCH}/tags.json" \
      "https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100" \
    || fail "base - could not list the tags of ${repo}"

  read -r latest_tag latest_digest < <(newest_base_tag < "${SCRATCH}/tags.json") \
    || fail "base - ${repo} has no tag shaped like a base publish"
  [[ ${latest_tag} =~ ${BASE_TAG_SHAPE} ]] \
    || fail "base - upstream gave '${latest_tag}', which is not a base tag"
  is_digest "${latest_digest}" \
    || fail "base - upstream gave '${latest_digest}' as the digest of ${latest_tag}"

  echo "base - current version - ${current_tag} ... latest version - ${latest_tag}"

  if [[ ${current_tag} == "${latest_tag}" && ${current_digest} == "${latest_digest}" ]]; then
    echo "base - No update found"
    return
  fi

  bump_version BASE_TAG "${current_tag}" "${latest_tag}"
  bump_version BASE_DIGEST "${current_digest}" "${latest_digest}"

  # The rewrite is a regex over one line each: a miss would leave the pin
  # untouched while the run still reported success.
  image=$(current_base_image)
  [[ ${image} == *":${latest_tag}@${latest_digest}" ]] \
    || fail "base - BASE_IMAGE still reads '${image}' after the rewrite"

  printf '%s %s %s\n' base "${current_tag}" "${latest_tag}" >> "${BUMP_LOG:-/dev/null}"
}

# tests/check-base-updates.bats sources this file for the functions above; only
# a direct run checks and bumps.
[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
