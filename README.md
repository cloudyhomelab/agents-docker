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

One image per agent, tagged `latest` and with the agent CLI's own version, as
in `claude:<version>`. Each image carries every supported toolchain, so the
image does not have to be matched to the project:

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

[`shell-helper/agents.sh`](shell-helper/agents.sh) has fuller `claude`, `codex`
and `gemini` wrappers to source from the same rc file: a config volume per CLI,
separate volumes per cache, the host Maven repository shared when it exists, and
`<AGENT>_IMAGE_TAG` to pin a published version.

## Verifying the Images

Every published image is signed with [cosign](https://github.com/sigstore/cosign)
in keyless mode, so there is no public key to distribute -- the signature is tied
to the workflow run that produced it. Verifying asserts that the image really was
built by `.github/workflows/publish.yml` in this repository:

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github\.com/cloudyhomelab/agents-docker/\.github/workflows/publish\.yml@refs/' \
  docker.io/binarycodes/claude:latest
```

Substitute `codex` or `gemini` for `claude`, and a version tag for `latest`.
Tags published before the workflow was renamed carry its old name,
`build.yml`, in the identity instead.

The identity is a regular expression that stops at `@refs/` rather than pinning
one ref, because the ref a run signs under depends on how it was triggered: the
usual path is a merged pull request, a manual `workflow_dispatch` is not the
same ref. The repository and the workflow file -- the parts that carry the trust
-- are still anchored exactly, and `cosign verify` prints the full identity it
matched, so pin it further once you have seen what your tag actually carries.

The build also attaches SBOM and provenance attestations, which say what went
into the image rather than who built it:

```bash
docker buildx imagetools inspect docker.io/binarycodes/claude:latest
```

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

Check that a built image actually runs, as the pull request workflow does:

```bash
.github/scripts/smoke-test.sh claude
```

These build for the host platform only. The published images are multi-platform,
that needs a `docker-container` builder and `LOCAL=false` in the environment.

Run the tests for the entrypoint and the update script, which need no image:

```bash
bats tests
```

## Contributing

Enable the repository's hooks once per clone:

```bash
git config core.hooksPath .githooks
```

`pre-commit` then runs the same `shellcheck`, `hadolint` and `bats` checks the
pull request workflow does, and `commit-msg` checks the message against the
conventions above. None of the three is required locally -- one that is not
installed is reported and skipped, and CI remains the enforcement point.

## License

Copyright (c) 2026 binarycodes

This project is licensed under the GNU General Public License v3.0 or later.
See [LICENSE](LICENSE), or <https://www.gnu.org/licenses/gpl-3.0.txt>.

Every file that supports comments carries the copyright and
`SPDX-License-Identifier` header; `LICENSE` and this README state it in prose
instead.

SPDX-License-Identifier: `GPL-3.0-or-later`
