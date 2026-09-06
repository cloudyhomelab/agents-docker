# Agent CLI Docker Images

Docker images for three AI agent CLIs, published on Docker Hub:

- `docker.io/binarycodes/claude`
- `docker.io/binarycodes/codex`
- `docker.io/binarycodes/gemini`

## Available Images

One image per agent, tagged `latest` and with the agent CLI's own version, as
in `claude:<version>`. Each image carries every supported toolchain, so the
image does not have to be matched to the project:

- Several JDK majors (Zulu, with JavaFX) plus Maven; `JAVA_VERSIONS` in
  `docker-bake.hcl` is the list
- Python 3 with `pip` and `venv`, plus a venv on `PATH` carrying the Ansible
  toolchain; `PIP_PACKAGES` in `docker-bake.hcl` is the list
- Go
- Node.js and npm
- The Debian packages in `PACKAGES` in `docker-bake.hcl`

### Selecting a JDK

The LTS JDK is active by default. Override it per run with `JAVA_VERSION`,
using either a major version or the `lts` / `latest` aliases (`JAVA_LTS` and
`JAVA_LATEST` in `docker-bake.hcl`):

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

Run the CLI directly, substituting `codex` or `gemini` for `claude`:

```bash
docker run --rm -it docker.io/binarycodes/claude:latest
```

With your current project mounted:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  docker.io/binarycodes/claude:latest
```

### Shell helper function

Add to `~/.bashrc` or `~/.zshrc`:

```bash
agent() {
  [[ $# -lt 2 ]] && { echo "usage: agent <tool> <project_path> [agent args...]"; return 1; }
  local tool="$1"
  local project_path="$2"
  shift 2
  docker run --pull always --rm -it \
    --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit 4096 --memory 8g \
    -v "${tool}_home:/home/agent" \
    -v "${project_path}:/workspace" \
    -w /workspace \
    -e JAVA_VERSION \
    "docker.io/binarycodes/${tool}:latest" "$@"
}
```

```bash
agent codex /path/to/workspace
JAVA_VERSION=17 agent codex /path/to/workspace
```

`-e JAVA_VERSION` with no value forwards the variable only when it is set in
your shell, so a project's own `.sdkmanrc` still decides when you do not.

The `${tool}_home` volume persists agent configuration and credentials between
runs. Toolchains and the agent CLIs live outside `/home/agent`, so they always
come from the image and are refreshed by `--pull always`.

The agent inside runs whatever the workspace and the model decide, so the
container gets no capabilities and no privilege gain, and a pid and memory cap
sized for a Maven build; raise them if yours needs more. Network egress is not
restricted, since which APIs and registries to allow is your call: attach the
container to a user-defined network (`docker network create`, then `--network`)
and filter it with the host firewall.

[`shell-helper/agents.sh`](shell-helper/agents.sh) has fuller `claude`, `codex`
and `gemini` wrappers to source from the same rc file: a config volume per CLI,
separate volumes per cache, the host Maven repository shared when it exists, and
`<AGENT>_IMAGE_TAG` to pin a published version.

## Verifying the Images

Every published image is signed with [cosign](https://github.com/sigstore/cosign)
in keyless mode, so there is no public key to distribute: the signature is tied
to the workflow run that produced it, and verifying asserts that the image was
built by `.github/workflows/publish.yml` in this repository:

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github\.com/cloudyhomelab/agents-docker/\.github/workflows/publish\.yml@refs/' \
  docker.io/binarycodes/claude:latest
```

Substitute `codex` or `gemini` for `claude`, and a version tag for `latest`.
Tags published before the workflow was renamed carry its old name, `build.yml`.

The identity stops at `@refs/` because the ref depends on how the run was
triggered, a merged pull request or a manual `workflow_dispatch`. The repository
and workflow file are anchored exactly; `cosign verify` prints the identity it
matched, so pin it further once you have seen what your tag carries.

The signature is on the image index, which also carries the SLSA provenance and
SBOM attestations the build attached. The provenance says what was built rather
than who built it: the source repository and commit, the `Dockerfile` and the
build arguments, so a pulled image can be matched to a commit here and to the
versions `docker-bake.hcl` pinned at it.

```bash
docker buildx imagetools inspect docker.io/binarycodes/claude:latest \
  --format '{{ json .Provenance }}'
```

`{{ json .SBOM }}` prints the SBOM the same way.

## Build Locally

Build all default targets, or a single agent:

```bash
docker buildx bake
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
which needs a `docker-container` builder and `LOCAL=false` in the environment.

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
pull request workflow does, and `commit-msg` requires a single-line
[Conventional Commits](https://www.conventionalcommits.org) message. None of the three is
required locally: one that is not installed is reported and skipped, and CI
remains the enforcement point.

## License

Copyright (c) 2026 binarycodes. Licensed under the GNU General Public License
v3.0 or later; see [LICENSE](LICENSE) or <https://www.gnu.org/licenses/gpl-3.0.txt>.

SPDX-License-Identifier: `GPL-3.0-or-later`
