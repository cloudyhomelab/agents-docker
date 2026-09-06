# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

variable "REGISTRY" { default = "docker.io" }
variable "NAMESPACE"  { default = "binarycodes" }

# The commit the image was built from, for the OCI revision label. HCL cannot
# read git, so the publish workflow passes the sha it checked out; a local build
# leaves it empty, which is the honest answer for a working tree.
variable "REVISION" { default = "" }

variable "CLAUDE_VERSION" { default = "2.1.263" }
variable "CODEX_VERSION" { default = "0.153.4" }
variable "GEMINI_VERSION" { default = "0.58.0" }

variable "GO_VERSION" { default = "1.27.0" }

variable "HADOLINT_VERSION" { default = "2.15.1" }

# Every major listed here is installed; the entrypoint activates one per run.
variable "JAVA_VERSIONS" {
  type = list(string)
  default = [
    "8.0.502.fx-zulu",
    "11.0.32.fx-zulu",
    "17.0.20.fx-zulu",
    "21.0.12.fx-zulu",
    "25.0.4.fx-zulu",
    "26.0.2.fx-zulu",
  ]
}

# Majors from the list above, exposed as the /opt/java/lts and /opt/java/latest aliases.
variable "JAVA_LTS" { default = "25" }
variable "JAVA_LATEST" { default = "26" }

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

# Debian packages installed in every image. Kept sorted; the Dockerfile expects
# a single space-separated string, so the list is joined where it is passed in.
variable "PACKAGES" {
  type = list(string)
  default = [
    "bash",
    "bats",
    "build-essential", # cgo, native pip wheels, node-gyp
    "ca-certificates",
    "curl",
    "git",
    "jq",
    "make",
    "ncurses-term",
    "nodejs",
    "npm",
    "python3",
    "python3-dev", # building C extensions from source
    "python3-pip",
    "python3-venv",
    "ripgrep",
    "shellcheck",
    "terminfo",
    "unzip",
    "zip",
  ]
}

# Python tooling, installed into one shared venv. Ansible is here rather than in
# PACKAGES so its version is ours to choose instead of being whatever Debian
# ships, and so molecule resolves against the same ansible-core it will run.
# Every entry is pinned, so rebuilding an old tag gets the same pip versions
# rather than whatever pip resolves that day. The apt packages in PACKAGES are
# deliberately not pinned, so the image as a whole is not reproducible.
# Kept sorted; joined into one space-separated string where it is passed in,
# like PACKAGES.
variable "PIP_PACKAGES" {
  type = list(string)
  default = [
    "ansible==14.3.1", # the community bundle, not just ansible-core
    "ansible-lint==26.8.0",
    "antsibull-changelog==0.35.1",
    "molecule==26.8.0",
    # The driver only; `molecule test` additionally needs a podman binary,
    # which the image deliberately does not carry.
    "molecule-plugins[podman]==26.7.15",
  ]
}

target "common" {
  args = {
    PACKAGES = join(" ", PACKAGES)
    PIP_PACKAGES = join(" ", PIP_PACKAGES)
  }

  platforms = LOCAL ? [] : ["linux/amd64", "linux/arm64"]
}

group "default" {
  targets = ["agent"]
}

target "agent" {
  inherits = ["common"]
  context = "."
  dockerfile = "Dockerfile"

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
  }

  args = {
    CLAUDE_VERSION = CLAUDE_VERSION
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
    GO_VERSION = GO_VERSION
    HADOLINT_VERSION = HADOLINT_VERSION
    JAVA_VERSIONS = join(" ", JAVA_VERSIONS)
    JAVA_LTS = JAVA_LTS
    JAVA_LATEST = JAVA_LATEST
  }

  target = agent
  tags = [
    "${REGISTRY}/${NAMESPACE}/${agent}:latest",
    "${REGISTRY}/${NAMESPACE}/${agent}:${agent_version(agent)}",
  ]
}
