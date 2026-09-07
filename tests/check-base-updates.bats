#!/usr/bin/env bats
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The tag selection of .github/scripts/check-base-updates.sh: from Docker Hub's
# listing, the newest tag shaped like a base publish and its digest, with
# latest and anything else ignored.

source "${BATS_TEST_DIRNAME}/../.github/scripts/check-base-updates.sh"

listing() {
  jq -n --args '{results: [$ARGS.positional[] | split("=") | {name: .[0], digest: .[1]}]}' "$@"
}

@test "newest_base_tag picks the greatest base tag and its digest" {
  run newest_base_tag < <(listing \
    "latest=sha256:aaaa" \
    "2026.09.06.1222=sha256:bbbb" \
    "2026.09.13.0300=sha256:cccc" \
    "2026.09.07.0300=sha256:dddd")
  [ "$status" -eq 0 ]
  [ "$output" = "2026.09.13.0300 sha256:cccc" ]
}

@test "newest_base_tag fails on a listing without a base tag" {
  run newest_base_tag < <(listing "latest=sha256:aaaa" "build-123=sha256:bbbb")
  [ "$status" -ne 0 ]
}

@test "is_digest accepts a sha256 digest and nothing else" {
  is_digest "sha256:$(printf '%064d' 0)"
  ! is_digest "sha256:abc"
  ! is_digest "$(printf '%064d' 0)"
  ! is_digest ""
}
