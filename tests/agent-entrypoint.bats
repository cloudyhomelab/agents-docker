#!/usr/bin/env bats
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The JDK resolution order of scripts/agent-entrypoint: the environment, then
# .sdkmanrc, then .java-version, then LTS, against a fake /opt/java.

source "${BATS_TEST_DIRNAME}/../scripts/agent-entrypoint"

setup() {
  TMP=$(mktemp -d)
  # The same layout the Dockerfile lays out: one directory per major plus the
  # two aliases. java_dir is the script's own global, pointed here.
  java_dir="${TMP}/java"
  mkdir -p "${java_dir}"/{8,11,17,21,25,26} "${TMP}/project"
  ln -s 25 "${java_dir}/lts"
  ln -s 26 "${java_dir}/latest"
  cd "${TMP}/project"
}

teardown() {
  rm -rf "${TMP}"
}

# main execs its arguments, so the command under test reports what it was
# handed. The first PATH entry is JAVA_HOME/bin when the selection worked.
selected() {
  main sh -c 'printf "%s\n%s\n" "${JAVA_HOME}" "${PATH%%:*}"'
}

@test "JAVA_VERSION in the environment wins over both project files" {
  echo "java=11.0.32.fx-zulu" > .sdkmanrc
  echo "17" > .java-version
  export JAVA_VERSION=21
  run selected
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "${java_dir}/21" ]
  [ "${lines[1]}" = "${java_dir}/21/bin" ]
}

@test ".sdkmanrc is read before .java-version" {
  echo "java=11.0.32.fx-zulu" > .sdkmanrc
  echo "17" > .java-version
  run selected
  [ "${lines[0]}" = "${java_dir}/11" ]
}

@test "a .sdkmanrc without a java entry does not shadow .java-version" {
  echo "maven=3.9.9" > .sdkmanrc
  echo "17" > .java-version
  run selected
  [ "${lines[0]}" = "${java_dir}/17" ]
}

@test ".java-version accepts a vendor string and keeps only the major" {
  echo "21.0.12.fx-zulu" > .java-version
  run selected
  [ "${lines[0]}" = "${java_dir}/21" ]
}

@test "leading whitespace and trailing text are tolerated in both files" {
  printf '  java=8.0.502.fx-zulu  # oldest\n' > .sdkmanrc
  run selected
  [ "${lines[0]}" = "${java_dir}/8" ]
  rm .sdkmanrc
  printf '  8  # oldest\n' > .java-version
  run selected
  [ "${lines[0]}" = "${java_dir}/8" ]
}

@test "with nothing declared the LTS alias is selected" {
  run selected
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "${java_dir}/lts" ]
}

@test "the aliases can be requested by name" {
  export JAVA_VERSION=latest
  run selected
  [ "${lines[0]}" = "${java_dir}/latest" ]
}

@test "an unknown version warns, falls back to LTS and still runs the command" {
  export JAVA_VERSION=99
  run selected
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "agent-entrypoint: no JDK '99' in this image; available: "* ]]
  [[ "${lines[0]}" == *" 8 "*"lts"* ]]
  [ "${lines[1]}" = "${java_dir}/lts" ]
  [ "${lines[2]}" = "${java_dir}/lts/bin" ]
}

@test "the command's own exit status is what comes back" {
  run main sh -c 'exit 7'
  [ "$status" -eq 7 ]
}
