# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# Declarations only -- no FROM interpolates these and every stage redeclares
# what it uses. They are here because one bake target passes all three agent
# versions to every agent build, which reaches just one of the CLI stages, and
# an arg no reached stage declares is one BuildKit warns about.
ARG CLAUDE_VERSION
ARG CODEX_VERSION
ARG GEMINI_VERSION
ARG GO_VERSION
ARG HADOLINT_VERSION
ARG JAVA_VERSIONS
ARG JAVA_LTS
ARG JAVA_LATEST
ARG PACKAGES
ARG PIP_PACKAGES


#====================
# base layer
#====================
# A floating tag on purpose: a digest pin would hold the base, and its security
# updates, at whatever was current the day someone last bumped it.
FROM debian:13-slim AS base
ARG PACKAGES

ENV DEBIAN_FRONTEND=noninteractive
# The cache mounts keep the package lists and the downloaded .debs out of the
# layer, as the usual rm -rf of the lists did, but carry them into the next
# build. Debian's image ships a docker-clean hook that deletes every .deb as
# soon as it is installed, which would empty the cache each time; it goes, and
# the setting that keeps the downloads replaces it.
# -f so an apt pattern such as linux-headers-* is not filesystem-matched before
# apt sees it.
# Nothing in the image switches user, so the setuid and setgid bits on su,
# mount, passwd and the rest are only a way up for a session talked into them.
# Stripped rather than the packages removed, which the base cannot lose; in
# this layer so the copy-up costs no extra one.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && set -f \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${PACKAGES} \
    && find / -xdev -perm /6000 -type f -exec chmod a-s '{}' +

# 1000:1000 explicitly, because a bind-mounted workspace carries the host's
# ownership: the files an agent writes come back out belonging to the person
# who started it.
#
# .cache is created here, owned by agent, because a run mounts a named volume
# onto it: Docker seeds a new volume from the image's directory, ownership
# included, but only when that directory exists -- otherwise it creates the
# mount point itself as root and the agent cannot write to its own cache. The
# same applies to the toolchain and CLI config directories, each created in the
# stage that owns it. This one stays here: go, npm and pip all share it.
#
# safe.directory, because that same host ownership is what git reads: on a host
# where the user is not 1000, every git command in the session would refuse the
# workspace as dubiously owned. --system, so the exemption also covers whichever
# uid a --user override runs as.
RUN groupadd -g 1000 agent \
    && useradd -m -u 1000 -g 1000 -s /bin/bash agent \
    && install -d -o agent -g agent /home/agent/.cache \
    && git config --system --add safe.directory /workspace

# Not in the Debian archive, so the static release binary is fetched instead.
# The release names its assets x86_64 and arm64 where TARGETARCH says amd64 and
# arm64, hence the map; any other arch fails here rather than 404ing on an asset
# that does not exist.
ARG HADOLINT_VERSION
ARG TARGETARCH
RUN case "${TARGETARCH}" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) echo "no hadolint build for ${TARGETARCH}" >&2; exit 1 ;; esac \
    && curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${arch}" \
    && chmod 0755 /usr/local/bin/hadolint


#====================
# install python tools
#====================
FROM base AS python
ARG PIP_PACKAGES

# A venv rather than a system-wide pip install: Debian marks its interpreter
# externally managed, so pip refuses to touch it. One venv for the whole list,
# so molecule and its driver share an interpreter with the ansible-core they
# drive rather than resolving a second copy of it.
ENV VIRTUAL_ENV="/opt/venv"
# A cache mount rather than --no-cache-dir: either keeps the wheel cache out of
# the layer, but this one survives into the next build.
# set -f, because the list is deliberately unquoted to word-split and an extra
# such as molecule-plugins[podman] is also a valid glob pattern.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    set -f \
    && python3 -m venv "${VIRTUAL_ENV}" \
    && "${VIRTUAL_ENV}/bin/pip" install --upgrade pip \
    && "${VIRTUAL_ENV}/bin/pip" install ${PIP_PACKAGES} \
    && chmod -R a+rX "${VIRTUAL_ENV}"

# Ahead of /usr/bin, so `python3` in a session is the interpreter that can
# actually import these tools.
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"


#====================
# install go
#====================
FROM python AS go
ARG GO_VERSION
ARG TARGETARCH

# Downloaded to a file first: piping straight into tar turns a bad response into
# a misleading "unexpected end of file" from gzip instead of the HTTP error, and
# dl.google.com is the redirect target of go.dev/dl anyway, one less hop to fail.
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/go.tar.gz "https://dl.google.com/go/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/go.tar.gz -C /usr/local \
    && rm /tmp/go.tar.gz

ENV GOROOT="/usr/local/go"
# GOPATH keeps its default of ${HOME}/go, so a mounted home volume also caches
# modules and `go install` binaries between runs.
ENV PATH="${GOROOT}/bin:/home/agent/go/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/go


#====================
# install jdks
#====================
FROM go AS jdk
ARG JAVA_VERSIONS
ARG JAVA_LTS
ARG JAVA_LATEST

# Toolchains live outside /home/agent: that path is normally a named volume,
# which is seeded only on first use and would otherwise pin every toolchain to
# whatever the image held on the day the volume was created.
ENV SDKMAN_DIR="/opt/sdkman"
# Fetched to a file rather than piped into bash: /bin/sh has no pipefail, so a
# failed download would feed bash an empty script and still exit 0.
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/sdkman.sh "https://get.sdkman.io?ci=true&rcupdate=false" \
    && bash /tmp/sdkman.sh \
    && rm /tmp/sdkman.sh

# A quoted delimiter, so the variables reach bash unexpanded instead of being
# substituted by BuildKit first. hadolint does not read the shebang and would
# otherwise lint this as /bin/sh.
# hadolint shell=/bin/bash
RUN <<'EOF'
#!/bin/bash
# set -e only after sourcing, since sdkman-init.sh is not written to run under
# it.
# shellcheck source=/dev/null
source "${SDKMAN_DIR}/bin/sdkman-init.sh"
set -e

fail() {
  echo "$*" >&2
  exit 1
}

# No -f, despite the unquoted list: sdkman moves the unzipped JDK into place
# with an unquoted glob and returns 0 regardless, so noglob installs nothing
# and says it succeeded.
for version in ${JAVA_VERSIONS}; do
  sdk install java "${version}"
done
sdk install maven
# The zip of every candidate stays under tmp/ and nothing reads it again.
rm -rf "${SDKMAN_DIR}/tmp"/*

# Stable per-major paths, so selecting a JDK at run time needs only "21" and
# not the full "21.0.10.fx-zulu" vendor string. Every target is checked,
# because ln -s happily creates a dangling link and the breakage would only
# surface at run time, inside someone's session.
mkdir -p /opt/java
for version in ${JAVA_VERSIONS}; do
  candidate="${SDKMAN_DIR}/candidates/java/${version}"
  test -d "${candidate}" || fail "missing JDK: ${candidate}"
  ln -s "${candidate}" "/opt/java/${version%%.*}"
done
test -d "/opt/java/${JAVA_LTS}" || fail "JAVA_LTS=${JAVA_LTS} not among JAVA_VERSIONS"
test -d "/opt/java/${JAVA_LATEST}" || fail "JAVA_LATEST=${JAVA_LATEST} not among JAVA_VERSIONS"
ln -s "${JAVA_LTS}" /opt/java/lts
ln -s "${JAVA_LATEST}" /opt/java/latest
test -d "${SDKMAN_DIR}/candidates/maven/current" || fail "missing maven: ${SDKMAN_DIR}/candidates/maven/current"

chmod -R a+rX /opt
EOF

ENV M2_HOME="${SDKMAN_DIR}/candidates/maven/current"
ENV PATH="${M2_HOME}/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/.m2

# Global npm installs the agent does at run time land in its home, where it has
# write access; the CLIs below are installed to /usr/local with an explicit
# --prefix so they stay out of the home volume.
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global
ENV PATH="/home/agent/.npm-global/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/.npm-global

COPY --chmod=0755 scripts/agent-entrypoint /usr/local/bin/agent-entrypoint
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]


#====================
# claude
#====================
FROM jdk AS claude
ARG CLAUDE_VERSION

# The installer is ${HOME}-relative and its launcher is an absolute symlink, so
# a throwaway HOME relocates the whole install out of the agent's home volume.
RUN HOME=/opt/claude bash -o pipefail -c 'curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "https://claude.ai/install.sh" | bash -s "${CLAUDE_VERSION}"' \
    && ln -s /opt/claude/.local/bin/claude /usr/local/bin/claude \
    && chmod -R a+rX /opt/claude \
    && install -d -o agent -g agent /home/agent/.claude

USER 1000
WORKDIR /home/agent
CMD ["claude"]


#====================
# codex
#====================
FROM jdk AS codex
ARG CODEX_VERSION

# A cache mount rather than a post-install `npm cache clean`: either keeps the
# cache out of the layer, but this one survives into the next build. Locked,
# because the codex and gemini stages install in parallel and share it.
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g --prefix /usr/local @openai/codex@"${CODEX_VERSION}" \
    && install -d -o agent -g agent /home/agent/.codex

USER 1000
WORKDIR /home/agent
CMD ["codex"]


#====================
# gemini
#====================
FROM jdk AS gemini
ARG GEMINI_VERSION

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g --prefix /usr/local @google/gemini-cli@"${GEMINI_VERSION}" \
    && install -d -o agent -g agent /home/agent/.gemini

USER 1000
WORKDIR /home/agent
CMD ["gemini"]
