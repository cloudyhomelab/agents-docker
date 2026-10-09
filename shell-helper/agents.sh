# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash

# Containerised agent CLIs. Source from ~/.bashrc or ~/.zshrc. The first
# argument is always the workspace: `claude . --version`, not `claude --version`.
#
#     JAVA_VERSION=17 claude . --resume
#     CODEX_IMAGE_TAG=0.152.0 codex ~/some/project
#     AGENT_MEMORY=16g gemini .
#     AGENT_RUNTIME=docker claude .
#     AGENT_CONFIG_REPO=https://github.com/you/agent-config.git claude .

function _agent_run() {
    local tool="$1"
    local tag="$2"
    local workspace="$3"

    if [[ ! -d "$workspace" ]]; then
        printf 'usage: %s <workspace> [%s args...]\n' "$tool" "$tool" >&2
        return 1
    fi
    shift 3

    local runtime="${AGENT_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        if command -v podman >/dev/null 2>&1; then
            runtime=podman
        elif command -v docker >/dev/null 2>&1; then
            runtime=docker
        else
            printf '%s: neither podman nor docker found\n' "$tool" >&2
            return 1
        fi
    fi

    local workspace_abs name tmp_path
    local -a config cmd userns

    workspace_abs="$(cd "$workspace" && pwd -P)" || return 1
    # $RANDOM: two instances can start in the same second
    name="${tool}-$(basename "$workspace_abs")-$(date +%s)-${RANDOM}"
    name="${name//[^a-zA-Z0-9_.-]/-}"

    case "$tool" in
        claude)
            # a bind mount whose source is missing becomes a directory
            tmp_path="/tmp/agent-helper-${UID}"
            if [[ ! -f "${tmp_path}/claude.json" ]]; then
                mkdir -p "${tmp_path}"
                printf '{}\n' > "${tmp_path}/claude.json"
            fi
            config=(
                -v claude_config:/home/agent/.claude
                -v "${tmp_path}/claude.json:/home/agent/.claude.json"
                -e AGENT_CONFIG_REPO
            )
            ;;
        codex)
            config=(-v codex_config:/home/agent/.codex)
            ;;
        gemini)
            config=(-v gemini_config:/home/agent/.gemini)
            ;;
    esac

    # a missing bind source would be created root-owned
    local -a maven
    if [[ -d "$HOME/.m2" ]]; then
        maven=(-v "$HOME/.m2:/home/agent/.m2")
    fi

    # an unset identity stays unset rather than empty
    local git_name git_email
    local -a identity
    git_name="$(git -C "$workspace_abs" config user.name 2>/dev/null)"
    git_email="$(git -C "$workspace_abs" config user.email 2>/dev/null)"
    [[ -n "$git_name" ]] && identity+=(-e "GIT_USER_NAME=${git_name}")
    [[ -n "$git_email" ]] && identity+=(-e "GIT_USER_EMAIL=${git_email}")

    # rootless podman maps the host user to container root, so map it to agent;
    # --version also catches podman behind a docker shim
    if "$runtime" --version 2>/dev/null | grep -qi podman; then
        userns=(--userns "keep-id:uid=1000,gid=1000")
    fi

    cmd=(
        "$runtime" run
        --rm
        -it
        --pull always
        "${userns[@]}"
        --cap-drop ALL
        --security-opt no-new-privileges
        --pids-limit 4096
        --memory "${AGENT_MEMORY:-8g}"
        "${config[@]}"
        -v "${workspace_abs}:/workspace"
        "${maven[@]}"
        -v "${tool}_go:/home/agent/go"
        -v "${tool}_cache:/home/agent/.cache"
        -w /workspace
        -e JAVA_VERSION
        "${identity[@]}"
        --name "$name"
        "docker.io/binarycodes/${tool}:${tag}"
        "$@"
    )

    "${cmd[@]}"
}

function claude() {
    _agent_run claude "${CLAUDE_IMAGE_TAG:-latest}" "$@"
}

function codex() {
    _agent_run codex "${CODEX_IMAGE_TAG:-latest}" "$@"
}

function gemini() {
    _agent_run gemini "${GEMINI_IMAGE_TAG:-latest}" "$@"
}
