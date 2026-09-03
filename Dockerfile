ARG CLAUDE_VERSION
ARG CODEX_VERSION
ARG GEMINI_VERSION
ARG GO_VERSION
ARG JAVA_VERSIONS
ARG JAVA_LTS
ARG JAVA_LATEST
ARG PACKAGES
ARG PIP_PACKAGES


#====================
# base layer
#====================
FROM debian:13-slim AS base
ARG PACKAGES

ENV DEBIAN_FRONTEND=noninteractive
# -f so an apt pattern such as linux-headers-* is not filesystem-matched before
# apt sees it; +f again for the cleanup glob.
RUN set -f \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${PACKAGES} \
    && set +f \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agent

# Created here, owned by agent, because a run mounts a named volume onto it:
# Docker seeds a new volume from the image's directory, ownership included, but
# only when that directory exists -- otherwise it creates the mount point itself
# as root and the agent cannot write to its own cache. The same applies to the
# toolchain and CLI config directories, each created in the stage that owns it.
# This one stays here: go, npm and pip all share it.
RUN install -d -o agent -g agent /home/agent/.cache


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
# set -f, because the list is deliberately unquoted to word-split and an extra
# such as molecule-plugins[podman] is also a valid glob pattern.
RUN set -f \
    && python3 -m venv "${VIRTUAL_ENV}" \
    && "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir --upgrade pip \
    && "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir ${PIP_PACKAGES} \
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

# set -e only after sourcing, since sdkman-init.sh is not written to run under
# it; and the steps are ';'-separated rather than '&&'-chained, because errexit
# is suppressed inside a compound command that is part of an AND list -- there a
# failed `sdk install` is swallowed and the image ships a JDK short.
RUN bash -c 'source "${SDKMAN_DIR}/bin/sdkman-init.sh"; \
    set -ef; \
    for version in ${JAVA_VERSIONS}; do sdk install java "${version}"; done; \
    sdk install maven'

# Stable per-major paths, so selecting a JDK at run time needs only "21" and
# not the full "21.0.10.fx-zulu" vendor string.
# Every target is checked, because ln -s happily creates a dangling link and the
# breakage would only surface at run time, inside someone's session.
RUN set -f \
    && mkdir -p /opt/java \
    && for version in ${JAVA_VERSIONS}; do \
         candidate="${SDKMAN_DIR}/candidates/java/${version}"; \
         test -d "${candidate}" || { echo "missing JDK: ${candidate}" >&2; exit 1; }; \
         ln -s "${candidate}" "/opt/java/${version%%.*}"; \
       done \
    && test -d "/opt/java/${JAVA_LTS}" || { echo "JAVA_LTS=${JAVA_LTS} not among JAVA_VERSIONS" >&2; exit 1; } \
    && test -d "/opt/java/${JAVA_LATEST}" || { echo "JAVA_LATEST=${JAVA_LATEST} not among JAVA_VERSIONS" >&2; exit 1; } \
    && ln -s "${JAVA_LTS}" /opt/java/lts \
    && ln -s "${JAVA_LATEST}" /opt/java/latest \
    && test -d "${SDKMAN_DIR}/candidates/maven/current" \
    && chmod -R a+rX /opt

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
    && chmod -R a+rX /opt/claude

RUN install -d -o agent -g agent /home/agent/.claude

USER agent
WORKDIR /home/agent
CMD ["claude"]


#====================
# codex
#====================
FROM jdk AS codex
ARG CODEX_VERSION

RUN npm install -g --prefix /usr/local @openai/codex@"${CODEX_VERSION}"

RUN install -d -o agent -g agent /home/agent/.codex

USER agent
WORKDIR /home/agent
CMD ["codex"]


#====================
# gemini
#====================
FROM jdk AS gemini
ARG GEMINI_VERSION

RUN npm install -g --prefix /usr/local @google/gemini-cli@"${GEMINI_VERSION}"

RUN install -d -o agent -g agent /home/agent/.gemini

USER agent
WORKDIR /home/agent
CMD ["gemini"]
