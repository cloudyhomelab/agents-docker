#!/usr/bin/env bash
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the image each named agent target built and checks that every toolchain
# in it starts. A build proves the layers assemble; this proves the result
# works, so a JDK that cannot run or an agent CLI that will not start is caught
# before it is published.
#
# Every check runs even after one has failed, so the table written per agent --
# to the job summary under Actions, to stdout elsewhere -- is complete, and the
# exit status says whether anything in it failed. The rows are sorted by label
# rather than left in the order the checks ran. Progress goes to stderr, so the
# table is all that stdout carries.
#
# Run from the repository root after a bake that left the images in the local
# docker daemon: a plain `docker buildx bake`, or one with --load.
#
#   smoke-test.sh <agent>...

set -euo pipefail

BAKE_FILE="docker-bake.hcl"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

fail() {
  echo "smoke-test: $*" >&2
  exit 1
}

[[ $# -gt 0 ]] || fail "usage: smoke-test.sh <agent>..."
[[ -f ${BAKE_FILE} ]] || fail "no ${BAKE_FILE} here; run this from the repository root"

# One row per check: the label the table shows, then the command run in the
# container. The per-major JDKs and the agent CLI are added per image below,
# since they differ between images. Importing ansible from python3 is what
# proves the python3 on PATH is the venv's and not /usr/bin's. The setuid row
# passes on empty output: the base stage strips those bits, and a file that
# still carries one is listed.
#
#      <label>   <command>
CHECKS=(
  "java      java -version"
  "maven     mvn -v"
  "go        go version"
  "python    python3 -c 'import ansible, sys; print(sys.version)'"
  "ansible   ansible --version"
  "node      node -v"
  "ripgrep   rg --version"
  "jq        jq --version"
  "hadolint  hadolint --version"
  "setuid    ! find / -xdev -perm /6000 -type f 2>/dev/null | grep ."
)

# Looked up through bake rather than assembled from REGISTRY and NAMESPACE here,
# so what runs is exactly what the build tagged. -e makes a missing target jq's
# failure instead of the string "null" reaching docker run.
image_for() {
  docker buildx bake --file "${BAKE_FILE}" --progress=quiet --print \
    | jq -er --arg target "$1" '.target[$target].tags[0]'
}

# --pull never, because the tag is the one the published image carries too:
# were the build not loaded, docker run would fetch that from the registry and
# pass the test against the wrong image. A fresh container per command rather
# than docker exec into one, because only a container start goes through the
# entrypoint, and PATH and JAVA_HOME as a session gets them are part of what is
# under test. The capability and privilege restrictions are the wrappers', so
# a CLI that stops starting under them fails here rather than in a session.
in_image() {
  local image="$1"
  shift
  docker run --rm --pull never \
    --cap-drop ALL --security-opt no-new-privileges \
    "${image}" "$@"
}

failures=0
rows=()

# Collects one table row and logs the outcome. The cell carries the first line
# of output, which for every tool here is the version; the full output of a
# failure goes to the log, where there is room for it.
run_check() {
  local image="$1" label="$2" command="$3"
  local output status=0 result line

  output=$(in_image "${image}" bash -c "${command}" 2>&1) || status=$?

  if [[ ${status} -eq 0 ]]; then
    result=":white_check_mark:"
    echo "${label} - ok" >&2
  else
    result=":x:"
    failures=$((failures + 1))
    echo "${label} - FAILED (exit ${status})" >&2
    echo "${output}" >&2
  fi

  # First line only, with the one character that would break the table escaped.
  line="${output%%$'\n'*}"
  rows+=("| ${label} | ${result} | ${line//|/\\|} |")
}

for agent in "$@"; do
  if ! image=$(image_for "${agent}"); then
    fail "no target '${agent}' in ${BAKE_FILE}"
  fi

  echo "smoke-test: ${agent} - ${image}" >&2
  rows=()

  for check in "${CHECKS[@]}"; do
    # The columns are space-separated, so word splitting is the whole parse;
    # the command keeps its own internal spaces.
    read -r label command <<<"${check}"
    run_check "${image}" "${label}" "${command}"
  done

  # Every entry under /opt/java, aliases included, listed from the image rather
  # than from JAVA_VERSIONS so it is the shipped symlinks that get started; the
  # build only checked that their targets exist.
  for jdk in $(in_image "${image}" ls /opt/java); do
    run_check "${image}" "jdk ${jdk}" "/opt/java/${jdk}/bin/java -version"
  done

  run_check "${image}" "${agent}" "${agent} --version"

  # -V so the jdk rows go 8, 11, 17 rather than 11, 17, 8, with the two aliases
  # after the numbers; C locale so the order does not depend on the runner.
  {
    echo "### ${agent}"
    echo
    echo "\`${image}\`"
    echo
    echo "| Check | Result | Output |"
    echo "| --- | --- | --- |"
    printf '%s\n' "${rows[@]}" | LC_ALL=C sort -V
    echo
  } >> "${SUMMARY}"
done

[[ ${failures} -eq 0 ]] || fail "${failures} check(s) failed"
