#!/usr/bin/env bash
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# sdkman-init.sh does not survive set -e.
# shellcheck source=/dev/null
source "${SDKMAN_DIR}/bin/sdkman-init.sh"
set -eo pipefail

fail() {
  echo "$*" >&2
  exit 1
}

# No set -f: sdkman relies on globbing and silently installs nothing without it.
for version in ${JAVA_VERSIONS}; do
  sdk install java "${version}"
done
sdk install maven
rm -rf "${SDKMAN_DIR}/tmp"/*

# ln -s happily creates dangling links, so every target is checked.
mkdir -p /opt/java
for version in ${JAVA_VERSIONS}; do
  candidate="${SDKMAN_DIR}/candidates/java/${version}"
  test -d "${candidate}" || fail "missing JDK: ${candidate}"
  ln -s "${candidate}" "/opt/java/${version%%.*}"
done
test -d "/opt/java/${JAVA_LTS}" || fail "JAVA_LTS=${JAVA_LTS} not among JAVA_VERSIONS"
test -d "/opt/java/${JAVA_LATEST}" || fail "JAVA_LATEST=${JAVA_LATEST} not among JAVA_VERSIONS"
ln -s "${JAVA_LTS}" /opt/java/lts
ln -s "${JAVA_LATEST}" /opt/java/latest
test -d "${SDKMAN_DIR}/candidates/maven/current" || fail "missing maven: ${SDKMAN_DIR}/candidates/maven/current"

chmod -R a+rX /opt
