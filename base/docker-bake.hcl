# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

variable "REGISTRY" { default = "docker.io" }
variable "NAMESPACE"  { default = "binarycodes" }

# The commit the image was built from, for the OCI revision label. HCL cannot
# read git, so the publish workflow passes the sha it checked out; a local build
# leaves it empty, which is the honest answer for a working tree.
variable "REVISION" { default = "" }

variable "GO_VERSION" { default = "1.27.3" }

variable "HADOLINT_VERSION" { default = "2.15.1" }
variable "TFLINT_VERSION" { default = "0.65.0" }
variable "TRIVY_VERSION" { default = "0.76.1" }
variable "SOPS_VERSION" { default = "3.13.3" }

# Temurin majors, each installed at its newest release when the image is built;
# latest is the newest feature release, whatever its number. The entrypoint
# activates one per run, and /opt/java/latest points at the highest installed.
variable "JAVA_VERSIONS" {
  type = list(string)
  default = ["8", "11", "17", "21", "25", "latest"]
}

# The default JDK and the /opt/java/lts alias; must be a major listed above.
variable "JAVA_LTS" { default = "25" }

variable "LOCAL" { default = true }

# The timestamp tag a publish adds beside latest, yyyy.mm.dd.hhmm in UTC. Passed
# in by the publish workflow; a local build leaves it empty and tags only
# latest. Year-first so the tags sort chronologically, which is the order
# Dependabot ranks candidates in when it moves the agents' pin.
variable "BASE_TAG" { default = "" }

# Debian packages installed in every image. Kept sorted; the Dockerfile expects
# a single space-separated string, so the list is joined where it is passed in.
variable "PACKAGES" {
  type = list(string)
  default = [
    "age",
    "bash",
    "bats",
    "build-essential", # cgo, native pip wheels, node-gyp
    "ca-certificates",
    "curl",
    "direnv",
    "gh",
    "glab",
    "git",
    "jq",
    "just",
    "make",
    "ncurses-term",
    "nodejs",
    "npm",
    "packer",
    "procps", # required by codex
    "python3",
    "python3-dev", # building C extensions from source
    "python3-pip",
    "python3-pytest",
    "python3-venv",
    "ripgrep",
    "shellcheck",
    "terminfo",
    "terramate",
    "tofu",
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
    "pre-commit==4.7.0",
  ]
}

group "default" {
  targets = ["base"]
}

# Paths are relative to where bake runs, so this file is used from the
# repository root like the agents' one: docker buildx bake -f base/docker-bake.hcl
target "base" {
  context = "base"
  dockerfile = "Dockerfile"

  platforms = LOCAL ? [] : ["linux/amd64", "linux/arm64"]

  # The provenance attestation carries the source and revision too, but a label
  # is what `docker inspect` and Docker Hub read.
  labels = {
    "org.opencontainers.image.title"       = "agent-base"
    "org.opencontainers.image.description" = "Toolchains shared by the agent images"
    "org.opencontainers.image.source"      = "https://github.com/cloudyhomelab/agents-docker"
    "org.opencontainers.image.revision"    = REVISION
    "org.opencontainers.image.licenses"    = "GPL-3.0-or-later"
  }

  args = {
    PACKAGES = join(" ", PACKAGES)
    PIP_PACKAGES = join(" ", PIP_PACKAGES)
    GO_VERSION = GO_VERSION
    HADOLINT_VERSION = HADOLINT_VERSION
    TFLINT_VERSION = TFLINT_VERSION
    TRIVY_VERSION = TRIVY_VERSION
    SOPS_VERSION = SOPS_VERSION
    JAVA_VERSIONS = join(" ", JAVA_VERSIONS)
    JAVA_LTS = JAVA_LTS
  }

  target = "tools"

  tags = concat(
    ["${REGISTRY}/${NAMESPACE}/agent-base:latest"],
    BASE_TAG == "" ? [] : ["${REGISTRY}/${NAMESPACE}/agent-base:${BASE_TAG}"],
  )
}
