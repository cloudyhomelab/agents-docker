# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared by the check-*-updates.sh scripts: how a pin in docker-bake.hcl is read
# back and how one is rewritten. Sourced, never run; the pure functions are
# covered by tests/check-updates-lib.bats.
# shellcheck shell=bash

BAKE_FILE="docker-bake.hcl"

fail() {
  echo "${0##*/}: $*" >&2
  exit 1
}

# Read back through bake rather than by parsing the HCL, so the pin reported
# here is exactly what a build would see.
current_version() {
  local target="$1" variable="$2"

  docker buildx bake --file "${BAKE_FILE}" --progress=quiet --print \
    | jq -r --arg variable "${variable}" ".target.${target}.args[\$variable]"
}

# A bare dotted version and nothing else. Everything this rejects -- an empty
# parse, jq's "null" for a missing key, an error page, "npm ERR!" -- used to be
# written into the pin or silently rewrite nothing at all.
is_version() {
  [[ $1 =~ ^[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.-]+)?$ ]]
}

# Rewrites the default of one variable, matched by name and current value, and
# leaves every other byte of the file as it was.
bump_version() {
  local var="$1" cur="$2" new="$3"

  awk -v var="${var}" -v cur="${cur}" -v ver="${new}" '
    $0 ~ "^variable \"" var "\"" && $0 ~ "\"" cur "\"" {
      sub("default *= *\"" cur "\"", "default = \"" ver "\"")
    }
    { print }
  ' "${BAKE_FILE}" > "${BAKE_FILE}.tmp"
  mv "${BAKE_FILE}.tmp" "${BAKE_FILE}"
}
