variable "REGISTRY" { default = "docker.io" }
variable "NAMESPACE"  { default = "binarycodes" }

variable "CLAUDE_VERSION" { default = "2.1.252" }
variable "CODEX_VERSION" { default = "0.152.0" }
variable "GEMINI_VERSION" { default = "0.57.0" }

variable "GO_VERSION" { default = "1.27.0" }

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

variable "LOCAL" { default = false }

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
    "ansible",
    "ansible-lint",
    "bash",
    "build-essential", # cgo, native pip wheels, node-gyp
    "ca-certificates",
    "curl",
    "git",
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

target "common" {
  args = {
    PACKAGES = join(" ", PACKAGES)
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

  labels = {
    "org.opencontainers.image.title"       = "${agent}"
    "org.opencontainers.image.description" = "Docker container to run ${agent} workloads"
    "org.opencontainers.image.version"     = agent_version(agent)
  }

  args = {
    CLAUDE_VERSION = CLAUDE_VERSION
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
    GO_VERSION = GO_VERSION
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
