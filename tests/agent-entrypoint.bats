#!/usr/bin/env bats
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The JDK resolution order of scripts/agent-entrypoint: the environment, then
# .sdkmanrc, then .java-version, then LTS, against a fake /opt/java; and the
# git identity it passes on from GIT_USER_NAME and GIT_USER_EMAIL; and the
# AGENT_CONFIG_REPO links, against a local repo standing in for the remote.

source "${BATS_TEST_DIRNAME}/../scripts/agent-entrypoint"

setup() {
  TMP=$(mktemp -d)
  # The same layout the Dockerfile lays out: one directory per major plus the
  # two aliases. java_dir is the script's own global, pointed here.
  java_dir="${TMP}/java"
  mkdir -p "${java_dir}"/{8,11,17,21,25,26} "${TMP}/project"
  ln -s 25 "${java_dir}/lts"
  ln -s 26 "${java_dir}/latest"
  claude_dir="${TMP}/claude"
  cd "${TMP}/project"
  # Whatever the host has must not leak into the git identity tests.
  unset GIT_USER_NAME GIT_USER_EMAIL GIT_CONFIG_COUNT AGENT_CONFIG_REPO
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
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

# What git itself resolves in the command main execs; an unset key prints "-".
git_identity() {
  main sh -c 'printf "%s\n%s\n%s\n" \
    "$(git config user.name || echo -)" \
    "$(git config user.email || echo -)" \
    "$(git config core.editor || echo -)"'
}

@test "GIT_USER_NAME and GIT_USER_EMAIL become git's user.name and user.email" {
  export GIT_USER_NAME="Ada Lovelace" GIT_USER_EMAIL="ada@example.com"
  run git_identity
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Ada Lovelace" ]
  [ "${lines[1]}" = "ada@example.com" ]
}

@test "with neither set no git config is passed on" {
  run main sh -c 'echo "${GIT_CONFIG_COUNT:-unset}"'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "unset" ]
}

@test "each variable is applied on its own" {
  export GIT_USER_EMAIL="ada@example.com"
  run git_identity
  [ "${lines[0]}" = "-" ]
  [ "${lines[1]}" = "ada@example.com" ]
}

@test "GIT_CONFIG pairs already in the environment are kept" {
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.editor GIT_CONFIG_VALUE_0=vi
  export GIT_USER_NAME="Ada Lovelace" GIT_USER_EMAIL="ada@example.com"
  run git_identity
  [ "${lines[0]}" = "Ada Lovelace" ]
  [ "${lines[1]}" = "ada@example.com" ]
  [ "${lines[2]}" = "vi" ]
}

# A remote with CLAUDE.md and one skill, plus an empty ~/.claude.
make_config_remote() {
  mkdir -p "${claude_dir}" "${TMP}/remote/skills/alpha"
  echo "rules" > "${TMP}/remote/CLAUDE.md"
  echo "alpha" > "${TMP}/remote/skills/alpha/SKILL.md"
  commit_remote
  export AGENT_CONFIG_REPO="${TMP}/remote"
}

commit_remote() {
  git -C "${TMP}/remote" init --quiet
  git -C "${TMP}/remote" add --all
  git -C "${TMP}/remote" -c user.name=t -c user.email=t@t commit --quiet -m change
}

@test "AGENT_CONFIG_REPO links CLAUDE.md and each skill into ~/.claude" {
  make_config_remote
  run main true
  [ "$status" -eq 0 ]
  [ "$(cat "${claude_dir}/CLAUDE.md")" = "rules" ]
  [ -L "${claude_dir}/skills/alpha" ]
  [ "$(cat "${claude_dir}/skills/alpha/SKILL.md")" = "alpha" ]
}

@test "a second run pulls, links new skills and drops removed ones" {
  make_config_remote
  (main true)
  mkdir "${TMP}/remote/skills/beta"
  echo "beta" > "${TMP}/remote/skills/beta/SKILL.md"
  git -C "${TMP}/remote" rm --quiet -r skills/alpha
  commit_remote
  run main true
  [ "$status" -eq 0 ]
  [ ! -e "${claude_dir}/skills/alpha" ] && [ ! -L "${claude_dir}/skills/alpha" ]
  [ "$(cat "${claude_dir}/skills/beta/SKILL.md")" = "beta" ]
}

@test "skills and files the repo does not own are left alone" {
  make_config_remote
  mkdir -p "${claude_dir}/skills/synced"
  echo "mine" > "${claude_dir}/CLAUDE.md"
  ln -s "${TMP}/nowhere" "${claude_dir}/skills/other"
  run main true
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE.md is not a link"* ]]
  [ "$(cat "${claude_dir}/CLAUDE.md")" = "mine" ]
  [ -d "${claude_dir}/skills/synced" ]
  [ -L "${claude_dir}/skills/other" ]
}

@test "statusline.sh is linked and enabled in an existing settings.json" {
  make_config_remote
  echo "echo line" > "${TMP}/remote/statusline.sh"
  commit_remote
  echo '{"theme": "dark"}' > "${claude_dir}/settings.json"
  run main true
  [ "$status" -eq 0 ]
  [ "$(cat "${claude_dir}/statusline.sh")" = "echo line" ]
  [ "$(jq -r .theme "${claude_dir}/settings.json")" = "dark" ]
  [ "$(jq -r .statusLine.command "${claude_dir}/settings.json")" = "${claude_dir}/statusline.sh" ]
}

@test "a statusLine already in settings.json is kept" {
  make_config_remote
  echo "echo line" > "${TMP}/remote/statusline.sh"
  commit_remote
  echo '{"statusLine": {"type": "command", "command": "mine"}}' > "${claude_dir}/settings.json"
  run main true
  [ "$status" -eq 0 ]
  [ "$(jq -r .statusLine.command "${claude_dir}/settings.json")" = "mine" ]
}

@test "without settings.json one is created with only the statusLine" {
  make_config_remote
  echo "echo line" > "${TMP}/remote/statusline.sh"
  commit_remote
  run main true
  [ "$status" -eq 0 ]
  [ "$(jq -c 'keys' "${claude_dir}/settings.json")" = '["statusLine"]' ]
}

@test "an unparsable settings.json warns and is left as it was" {
  make_config_remote
  echo "echo line" > "${TMP}/remote/statusline.sh"
  commit_remote
  echo "{broken" > "${claude_dir}/settings.json"
  run main true
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not add statusLine"* ]]
  [ "$(cat "${claude_dir}/settings.json")" = "{broken" ]
  [ ! -e "${claude_dir}/settings.json.new" ]
}

@test "a repo without statusline.sh leaves settings.json alone" {
  make_config_remote
  run main true
  [ "$status" -eq 0 ]
  [ ! -e "${claude_dir}/settings.json" ]
  [ ! -e "${claude_dir}/statusline.sh" ]
}

@test "an unreachable repo warns and the command still runs" {
  mkdir -p "${claude_dir}"
  export AGENT_CONFIG_REPO="${TMP}/missing"
  run main sh -c 'echo ran'
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-entrypoint: could not clone ${TMP}/missing"* ]]
  [ "${lines[-1]}" = "ran" ]
}

@test "an unreachable repo after the first clone keeps the last copy" {
  make_config_remote
  (main true)
  mv "${TMP}/remote" "${TMP}/gone"
  run main true
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not update"* ]]
  [ "$(cat "${claude_dir}/skills/alpha/SKILL.md")" = "alpha" ]
}

@test "without ~/.claude, as in the codex and gemini images, nothing is cloned" {
  make_config_remote
  rm -rf "${claude_dir}"
  run main true
  [ "$status" -eq 0 ]
  [ ! -e "${claude_dir}" ]
}
