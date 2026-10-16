# Agent CLI Docker Images

Docker images for three AI agent CLIs, published on Docker Hub:

- `docker.io/binarycodes/claude`
- `docker.io/binarycodes/codex`
- `docker.io/binarycodes/gemini`

## Available Images

- Tags: `latest` and the agent CLI's own version, e.g. `claude:<version>`.
- Every image carries every toolchain, so no need to match image to project:
  - Several JDK majors (Zulu, with JavaFX) plus Maven (`JAVA_VERSIONS` in `docker-bake.hcl`)
  - Python 3 with `pip` and `venv`, plus a venv on `PATH` with the Ansible toolchain (`PIP_PACKAGES`)
  - Go
  - Node.js and npm
  - Debian packages (`PACKAGES`)

### Selecting a JDK

Resolution order:

1. `JAVA_VERSION` env var: a major version, or `lts` / `latest` (`JAVA_LTS` / `JAVA_LATEST` in `docker-bake.hcl`)
2. The project's `.sdkmanrc` (`java=17`) or `.java-version` (`17`) in the working directory
3. The LTS JDK

```bash
docker run --rm -it -e JAVA_VERSION=17 docker.io/binarycodes/claude:latest
```

### Setting the git identity

- `GIT_USER_NAME` / `GIT_USER_EMAIL` set git's `user.name` / `user.email` for the run.
- Not written to any config file; lasts only for that run.
- Only needed with bare `docker run`; the [shell helper](#shell-helper) passes it automatically.

```bash
docker run --rm -it \
  -e GIT_USER_NAME="Ada Lovelace" -e GIT_USER_EMAIL="ada@example.com" \
  docker.io/binarycodes/claude:latest
```

## Quick Start

Substitute `codex` or `gemini` for `claude`:

```bash
docker run --rm -it docker.io/binarycodes/claude:latest
```

With the current project mounted:

```bash
docker run --rm -it \
  -v "$PWD:/workspace/${PWD##*/}" \
  -w "/workspace/${PWD##*/}" \
  docker.io/binarycodes/claude:latest
```

### Shell helper

[`shell-helper/agents.sh`](shell-helper/agents.sh) defines `claude`, `codex` and `gemini` wrappers.
Source it from `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/shell-helper/agents.sh
```

First argument is the workspace; the rest go to the CLI:

```bash
claude .
codex /path/to/workspace --version
JAVA_VERSION=17 claude . --resume
CODEX_IMAGE_TAG=0.152.0 codex .
AGENT_MEMORY=16g gemini .
AGENT_RUNTIME=docker claude .
AGENT_CONFIG_REPO=https://github.com/you/agent-config.git claude .
```

| Variable | Effect |
|---|---|
| `AGENT_RUNTIME` | `podman` or `docker`; default is podman when installed |
| `<AGENT>_IMAGE_TAG` | Pin a published version |
| `AGENT_MEMORY` | Raise the container memory cap |
| `JAVA_VERSION` | Forwarded only when set, so `.sdkmanrc` decides otherwise |
| `AGENT_CONFIG_REPO` | Personal Claude config repo, see below |

Behaviour:

- **Workspace path**: Mounted at `/workspace/<folder name>`, because the CLIs key memory, sessions and trust on the working directory. Two folders with the same name share that state.
- **File ownership**: Under podman the host user maps to the container's `agent` user, so written files stay yours.
- **Git identity**: Taken from git config for the project, so per-repo and `includeIf` identities apply.
- **Volumes**
  - One config volume per CLI (settings, credentials), plus separate Go and cache volumes.
  - Host `~/.m2` is shared when it exists.
  - Toolchains and CLIs are outside the volumes, so `--pull always` refreshes them.
- **Security**
  - No capabilities, no privilege gain, pid and memory caps sized for a Maven build.
  - Network egress is not restricted. To filter it, attach a user-defined network (`docker network create`, then `--network`) and use the host firewall.

#### Personal config repo (`AGENT_CONFIG_REPO`)

Carries your Claude instructions and skills to every machine. Export it in your shell rc.

- Public HTTPS git repo (cloned without credentials) containing:
  - `CLAUDE.md`
  - `skills/<name>/SKILL.md`
  - optional `statusline.sh` at the root
- On each start the claude image clones or fast-forwards it into `~/.claude/agent-config` and links into `~/.claude`:
  - `CLAUDE.md` and each skill
  - `statusline.sh`, set as the status line in `~/.claude/settings.json` unless one is already set
- A skill deleted from the repo loses its link; a non-link file is never replaced.
- If the repo is unreachable, the last copy is used.

## Verifying the Images

- Signed with [cosign](https://github.com/sigstore/cosign) in keyless mode, so there is no public key to distribute.
- Verification asserts the image was built by `.github/workflows/publish.yml` in this repository.

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github\.com/cloudyhomelab/agents-docker/\.github/workflows/publish\.yml@refs/' \
  docker.io/binarycodes/claude:latest
```

- Substitute `codex` / `gemini` for `claude`, and a version tag for `latest`.
- Older tags were signed by `build.yml`; use that file name for them.
- `docker.io/binarycodes/agent-base` (the toolchain base image) is signed by `publish-base.yml`.
- The identity stops at `@refs/` because the ref depends on the trigger (merged PR or `workflow_dispatch`). `cosign verify` prints the matched identity; pin it further once you've seen it.

### Provenance and SBOM

- Attached to the image index alongside the signature.
- Provenance records source repo and commit, `Dockerfile` and build args, enough to match an image to a commit and its `docker-bake.hcl` pins.

```bash
docker buildx imagetools inspect docker.io/binarycodes/claude:latest \
  --format '{{ json .Provenance }}'   # or '{{ json .SBOM }}'
```

## Build Locally

```bash
docker buildx bake                          # all default targets
docker buildx bake claude                   # one agent
docker buildx bake --print                  # resolved build plan
.github/scripts/smoke-test.sh claude        # check the image runs (as in PR CI)
```

Base toolchain image (`agent-base`, from `base/`), run from the repo root:

```bash
docker buildx bake -f base/docker-bake.hcl
BAKE_FILE=base/docker-bake.hcl .github/scripts/smoke-test.sh base
```

Tests for the entrypoint and update script (no image needed):

```bash
bats tests
```

- Local builds target the host platform only.
- Multi-platform builds need a `docker-container` builder and `LOCAL=false`.

## Contributing

Enable the hooks once per clone:

```bash
git config core.hooksPath .githooks
```

- `pre-commit`: Runs `shellcheck`, `hadolint` and `bats`, same as PR CI.
- `commit-msg`: Requires a single-line [Conventional Commits](https://www.conventionalcommits.org) message.
- Missing tools are reported and skipped; CI is the enforcement point.

## License

Copyright (c) 2026 binarycodes. Licensed under the GNU General Public License
v3.0 or later; see [LICENSE](LICENSE) or <https://www.gnu.org/licenses/gpl-3.0.txt>.

SPDX-License-Identifier: `GPL-3.0-or-later`
