ARG CLAUDE_VERSION
ARG CODEX_VERSION
ARG GEMINI_VERSION
ARG GO_VERSION
ARG JAVA_VERSIONS
ARG JAVA_LTS
ARG JAVA_LATEST
ARG PACKAGES


#====================
# base layer
#====================
FROM debian:13-slim AS base
ARG PACKAGES

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ${PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agent


#====================
# install go
#====================
FROM base AS go
ARG GO_VERSION
ARG TARGETARCH

RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local

ENV GOROOT="/usr/local/go"
# GOPATH keeps its default of ${HOME}/go, so a mounted home volume also caches
# modules and `go install` binaries between runs.
ENV PATH="${GOROOT}/bin:/home/agent/go/bin:${PATH}"


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
RUN curl -fsSL "https://get.sdkman.io?ci=true&rcupdate=false" | bash

RUN bash -c 'source "${SDKMAN_DIR}/bin/sdkman-init.sh" \
    && for version in ${JAVA_VERSIONS}; do sdk install java "${version}"; done \
    && sdk install maven'

# Stable per-major paths, so selecting a JDK at run time needs only "21" and
# not the full "21.0.10.fx-zulu" vendor string.
RUN mkdir -p /opt/java \
    && for version in ${JAVA_VERSIONS}; do \
         ln -s "${SDKMAN_DIR}/candidates/java/${version}" "/opt/java/${version%%.*}"; \
       done \
    && ln -s "${JAVA_LTS}" /opt/java/lts \
    && ln -s "${JAVA_LATEST}" /opt/java/latest \
    && chmod -R a+rX /opt

ENV M2_HOME="${SDKMAN_DIR}/candidates/maven/current"
ENV PATH="${M2_HOME}/bin:${PATH}"

# Global npm installs the agent does at run time land in its home, where it has
# write access; the CLIs below are installed to /usr/local with an explicit
# --prefix so they stay out of the home volume.
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global
ENV PATH="/home/agent/.npm-global/bin:${PATH}"

COPY --chmod=0755 scripts/agent-entrypoint /usr/local/bin/agent-entrypoint
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]


#====================
# claude
#====================
FROM jdk AS claude
ARG CLAUDE_VERSION

# The installer is ${HOME}-relative and its launcher is an absolute symlink, so
# a throwaway HOME relocates the whole install out of the agent's home volume.
RUN HOME=/opt/claude bash -c 'curl -fsSL "https://claude.ai/install.sh" | bash -s "${CLAUDE_VERSION}"' \
    && ln -s /opt/claude/.local/bin/claude /usr/local/bin/claude \
    && chmod -R a+rX /opt/claude

USER agent
WORKDIR /home/agent
CMD ["claude"]


#====================
# codex
#====================
FROM jdk AS codex
ARG CODEX_VERSION

RUN npm install -g --prefix /usr/local @openai/codex@"${CODEX_VERSION}"

USER agent
WORKDIR /home/agent
CMD ["codex"]


#====================
# gemini
#====================
FROM jdk AS gemini
ARG GEMINI_VERSION

RUN npm install -g --prefix /usr/local @google/gemini-cli@"${GEMINI_VERSION}"

USER agent
WORKDIR /home/agent
CMD ["gemini"]
