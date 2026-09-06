# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

variable "REGISTRY" { default = "docker.io" }
variable "NAMESPACE"  { default = "binarycodes" }

# The commit the image was built from, for the OCI revision label. HCL cannot
# read git, so the publish workflow passes the sha it checked out; a local build
# leaves it empty, which is the honest answer for a working tree.
variable "REVISION" { default = "" }

# The base the agents are built on: the tag for the reader, the digest for the
# build. check-base-updates.sh moves both to the newest tag the base publish
# has landed; the publish workflow passes them on as the OCI base labels.
variable "BASE_TAG" { default = "latest" }
variable "BASE_DIGEST" { default = "" }

variable "CLAUDE_VERSION" { default = "2.1.263" }
variable "CODEX_VERSION" { default = "0.153.4" }
variable "GEMINI_VERSION" { default = "0.58.0" }

variable "LOCAL" { default = true }

variable "BUILD_AGENTS" {
  type    = list(string)
  default = ["claude", "codex", "gemini"]
}

# The versions stay in one variable each so the update workflow can sed them
# individually; this maps an agent name onto its own.
function "agent_version" {
  params = [name]
  result = {
    claude = CLAUDE_VERSION
    codex  = CODEX_VERSION
    gemini = GEMINI_VERSION
  }[name]
}

group "default" {
  targets = ["agent"]
}

target "agent" {
  context = "."
  dockerfile = "Dockerfile"

  platforms = LOCAL ? [] : ["linux/amd64", "linux/arm64"]

  matrix = {
    agent = BUILD_AGENTS
  }

  name = "${agent}"

  # The provenance attestation carries the source and revision too, but a label
  # is what `docker inspect` and Docker Hub read.
  labels = {
    "org.opencontainers.image.title"       = "${agent}"
    "org.opencontainers.image.description" = "Docker container to run ${agent} workloads"
    "org.opencontainers.image.version"     = agent_version(agent)
    "org.opencontainers.image.source"      = "https://github.com/cloudyhomelab/agents-docker"
    "org.opencontainers.image.revision"    = REVISION
    "org.opencontainers.image.licenses"    = "GPL-3.0-or-later"
    "org.opencontainers.image.base.name"   = "${REGISTRY}/${NAMESPACE}/agent-base:${BASE_TAG}"
    "org.opencontainers.image.base.digest" = BASE_DIGEST
  }

  args = {
    BASE_IMAGE = "${REGISTRY}/${NAMESPACE}/agent-base:${BASE_TAG}${BASE_DIGEST == "" ? "" : "@${BASE_DIGEST}"}"
    CLAUDE_VERSION = CLAUDE_VERSION
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
  }

  target = agent
  tags = [
    "${REGISTRY}/${NAMESPACE}/${agent}:latest",
    "${REGISTRY}/${NAMESPACE}/${agent}:${agent_version(agent)}",
  ]
}
