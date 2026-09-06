#!/usr/bin/env bats
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The two pure functions of .github/scripts/check-updates-lib.sh: is_version,
# which decides what may be written into a pin, and bump_version, which
# rewrites one line of docker-bake.hcl and must touch nothing else.

source "${BATS_TEST_DIRNAME}/../.github/scripts/check-updates-lib.sh"

setup() {
  TMP=$(mktemp -d)
  cd "${TMP}"
  # Every line here is a trap for a careless rewrite: a second variable pinned
  # to the same version, a variable whose name merely starts the same way, and
  # the version quoted in a comment.
  cat > "${BAKE_FILE}" <<'HCL'
# Bumped by check-agent-updates.sh; CLAUDE_VERSION was "2.1.259" before "2.1.260".
variable "CLAUDE_VERSION" { default = "2.1.260" }
variable "CLAUDE_VERSION_PREVIOUS" { default = "2.1.260" }
variable "CODEX_VERSION" { default = "0.153.2" }
variable "GEMINI_VERSION" { default = "2.1.260" }
variable "GO_VERSION"  {  default  =  "1.27.0"  }
HCL
  cp "${BAKE_FILE}" original.hcl
}

teardown() {
  rm -rf "${TMP}"
}

@test "is_version accepts the shapes upstream actually publishes" {
  for v in 2.1.260 0.153.2 1.27.0 26.0.2 1.2 1.2.3.4 1.2.3-rc.1 1.2.3+build.7; do
    is_version "${v}" || { echo "rejected ${v}"; return 1; }
  done
}

@test "is_version rejects everything that once reached a pin" {
  for v in "" null v1.2.3 1 1.2.3.4.5 "npm ERR! code E404" "1.2.3 " "<html>" 1..2 .1.2; do
    ! is_version "${v}" || { echo "accepted '${v}'"; return 1; }
  done
}

@test "bump_version rewrites the one line and leaves the rest byte for byte" {
  bump_version CLAUDE_VERSION 2.1.260 2.1.261
  run diff original.hcl "${BAKE_FILE}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "2c2" ]
  [ "${lines[1]}" = '< variable "CLAUDE_VERSION" { default = "2.1.260" }' ]
  [ "${lines[3]}" = '> variable "CLAUDE_VERSION" { default = "2.1.261" }' ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "bump_version normalises the spacing around default" {
  bump_version GO_VERSION 1.27.0 1.28.0
  grep -qxF 'variable "GO_VERSION"  {  default = "1.28.0"  }' "${BAKE_FILE}"
}

@test "bump_version changes nothing when the current version does not match" {
  bump_version CODEX_VERSION 0.153.1 0.154.0
  cmp -s original.hcl "${BAKE_FILE}"
}

@test "bump_version changes nothing for a variable that is not there" {
  bump_version NODE_VERSION 22.0.0 24.0.0
  cmp -s original.hcl "${BAKE_FILE}"
}
