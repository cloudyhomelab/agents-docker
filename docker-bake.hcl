variable "REGISTRY" { default = "docker.io" }
variable "NAMESPACE"  { default = "binarycodes" }

variable "CLAUDE_VERSION" { default = "2.1.84" }
variable "CODEX_VERSION" { default = "0.116.0" }
variable "GEMINI_VERSION" { default = "0.35.1" }

variable "LOCAL" { default = false }

variable "BUILD_AGENTS" {
  type    = list(string)
  default = ["claude", "codex", "gemini"]
}

target "common" {
  labels = {
    "org.opencontainers.image.title"       = "claude-local"
    "org.opencontainers.image.description" = "Docker container to run claude workloads"
  }

  args = {
    COMMON_PACKAGES="bash ca-certificates curl git make ncurses-term python3 ripgrep shellcheck terminfo unzip zip"
  }

  platforms = LOCAL ? [] : ["linux/amd64", "linux/arm64"]
}

group "default" {
  targets = ["python", "all-java-versions"]
}

target "python" {
  inherits = ["common"]
  context = "."
  dockerfile = "Dockerfile.python"

  args = {
    CLAUDE_VERSION = CLAUDE_VERSION
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
    EXTRA_PACKAGES = "python3 python3-pip python3-venv"
  }

  matrix = {
    agent = BUILD_AGENTS
  }

  name="${agent}-python"

  target = agent
  tags = ["${REGISTRY}/${NAMESPACE}/${agent}-local:python"]
}

target "java-base" {
  inherits = ["common"]
  context = "."
  dockerfile = "Dockerfile.java"
  target = "base"
}

target "all-java-versions" {
  inherits = ["java-base"]

  labels = {
    "org.opencontainers.image.version" = "jdk-${item.major}"
  }

  matrix = {
    agent = BUILD_AGENTS
    item = [
      { major = "25", version = "25.0.2.fx-zulu", extra_tags = ["jdk-latest"] },
      { major = "21", version = "21.0.10.fx-zulu", extra_tags = ["jdk-lts"] },
      { major = "17", version = "17.0.18.fx-zulu", extra_tags = [] },
      { major = "11", version = "11.0.30.fx-zulu", extra_tags = [] },
      { major = "8",  version = "8.0.482.fx-zulu", extra_tags = [] },
    ]
  }

  name="${agent}-jdk-${item.major}"

  args = {
    CLAUDE_VERSION = CLAUDE_VERSION
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
    JAVA_VERSION = item.version
  }

  target = agent
  tags = concat(
    ["${REGISTRY}/${NAMESPACE}/${agent}-local:jdk-${item.major}"],
    [for t in item.extra_tags : "${REGISTRY}/${NAMESPACE}/${agent}-local:${t}"]
    )
}
