# Agent CLI Docker Images

This repository builds and publishes Docker images for three AI agent CLIs:

- `claude`
- `codex`
- `gemini`

Images are published on Docker Hub under:

- `docker.io/binarycodes/claude`
- `docker.io/binarycodes/codex`
- `docker.io/binarycodes/gemini`

## Available Images

One image per agent, tagged `latest` and with the agent CLI's own version
(for example `claude:2.1.252`). Each image carries every supported toolchain,
so the image does not have to be matched to the project:

- JDK 8, 11, 17, 21, 25 and 26 (Zulu, with JavaFX) plus Maven
- Python 3 with `pip` and `venv`, plus a venv on `PATH` carrying `ansible`,
  `ansible-lint`, `antsibull-changelog` and `molecule` (with the podman driver;
  `molecule test` needs a `podman` binary, which the image does not carry)
- Go
- Node.js and npm

### Selecting a JDK

The LTS JDK is active by default. Override it per run with `JAVA_VERSION`,
using either a major version or the `lts` / `latest` aliases (currently 25 and
26):

```bash
docker run --rm -it -e JAVA_VERSION=17 docker.io/binarycodes/claude:latest
```

A project can also declare its own JDK, which applies whenever `JAVA_VERSION`
is not set. Either form works, read from the working directory:

```bash
# .sdkmanrc
java=17
```

```bash
# .java-version
17
```

## Quick Start

### Run the CLI directly:

#### Claude
```bash
docker run --rm -it docker.io/binarycodes/claude:latest
```

#### Codex
```bash
docker run --rm -it docker.io/binarycodes/codex:latest
```

#### Gemini
```bash
docker run --rm -it docker.io/binarycodes/gemini:latest
```

### Run with your current project mounted:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  docker.io/binarycodes/codex:latest
```

### Shell helper function
Add to your shell rc file such as `~/.bashrc` or `~/.zshrc`

```bash
agent() {
	[[ $# -lt 2 ]] && { echo "usage: agent <tool> <project_path> [agent args...]"; return 1; }
	local tool="$1"
	local project_path="$2"
	shift 2
	docker run --pull always --rm -it \
	-v "${tool}_home:/home/agent" \
	-v "${project_path}:/workspace" \
	-w /workspace \
	-e JAVA_VERSION \
	"docker.io/binarycodes/${tool}:latest" "$@"
}
```

Examples:

```bash
agent codex "/path/to/workspace"
JAVA_VERSION=17 agent codex "/path/to/workspace"
```

`-e JAVA_VERSION` with no value forwards the variable only when it is set in
your shell, so a project's own `.sdkmanrc` still decides when you do not.

The `${tool}_home` volume persists agent configuration and credentials between
runs. Toolchains and the agent CLIs themselves live outside `/home/agent`, so
they always come from the image and are refreshed by `--pull always`.

[`shell-helper/zshrc`](shell-helper/zshrc) has fuller `claude` and `codex`
wrappers: a config volume per CLI, separate volumes per cache, the host Maven
repository shared, and `<AGENT>_IMAGE_TAG` to pin a published version.

## Build Locally

Build all default targets:

```bash
docker buildx bake
```

Build a single agent:

```bash
docker buildx bake claude
```

Print the resolved build plan:

```bash
docker buildx bake --print
```
