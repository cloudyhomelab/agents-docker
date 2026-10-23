# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later


#====================
# base layer
#====================
FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f AS base
ARG PACKAGES

ENV DEBIAN_FRONTEND=noninteractive
# docker-clean deletes each .deb after install, which would empty the apt cache mount.
# set -f so a pattern such as linux-headers-* reaches apt unglobbed.
# Nothing switches user, so setuid/setgid bits are only an escalation path.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && set -f \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends ${PACKAGES} \
    && find / -xdev -perm /6000 -type f -exec chmod a-s '{}' +

# Volume mount points are created owned by agent: otherwise Docker creates them as root.
# safe.directory: the bind-mounted workspace keeps the host's owner, which may not be 1000.
RUN groupadd -g 1000 agent \
    && useradd -m -u 1000 -g 1000 -s /bin/bash agent \
    && install -d -o agent -g agent /home/agent/.cache \
    && git config --system --add safe.directory '/workspace/*'

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

ENV VIRTUAL_ENV="/opt/venv"
# set -f: an extra such as molecule-plugins[podman] is also a glob pattern.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    set -f \
    && python3 -m venv "${VIRTUAL_ENV}" \
    && "${VIRTUAL_ENV}/bin/pip" install --upgrade pip \
    && "${VIRTUAL_ENV}/bin/pip" install ${PIP_PACKAGES} \
    && chmod -R a+rX "${VIRTUAL_ENV}"

ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"


#====================
# install go
#====================
FROM python AS go
ARG GO_VERSION
ARG TARGETARCH

# Not piped into tar, which would hide an HTTP error behind a gzip one.
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/go.tar.gz "https://dl.google.com/go/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/go.tar.gz -C /usr/local \
    && rm /tmp/go.tar.gz

ENV GOROOT="/usr/local/go"
ENV PATH="${GOROOT}/bin:/home/agent/go/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/go


#====================
# install jdks
#====================
FROM go AS jdk
ARG JAVA_VERSIONS
ARG JAVA_LTS
ARG JAVA_LATEST

# Outside /home/agent: the home volume is seeded only once and would freeze the toolchains.
ENV SDKMAN_DIR="/opt/sdkman"
# Not piped into bash: /bin/sh has no pipefail, so a failed download would exit 0.
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/sdkman.sh "https://get.sdkman.io?ci=true&rcupdate=false" \
    && bash /tmp/sdkman.sh \
    && rm /tmp/sdkman.sh

RUN --mount=type=bind,source=install-jdks.sh,target=/tmp/install-jdks.sh \
    bash /tmp/install-jdks.sh

ENV JAVA_HOME="/opt/java/lts"
ENV PATH="${JAVA_HOME}/bin:${PATH}"

ENV M2_HOME="${SDKMAN_DIR}/candidates/maven/current"
ENV PATH="${M2_HOME}/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/.m2

ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global
ENV PATH="/home/agent/.npm-global/bin:${PATH}"

RUN install -d -o agent -g agent /home/agent/.npm-global


#====================
# install release binaries
#====================
FROM jdk AS tools
ARG TARGETARCH
ARG OPENTOFU_VERSION
ARG TFLINT_VERSION
ARG TRIVY_VERSION
ARG SOPS_VERSION

RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/tofu.tar.gz "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/tofu.tar.gz --no-same-owner -C /usr/local/bin tofu \
    && rm /tmp/tofu.tar.gz

RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TARGETARCH}.zip" \
    && unzip -q /tmp/tflint.zip tflint -d /usr/local/bin \
    && rm /tmp/tflint.zip

RUN case "${TARGETARCH}" in amd64) arch=64bit ;; arm64) arch=ARM64 ;; *) echo "no trivy build for ${TARGETARCH}" >&2; exit 1 ;; esac \
    && curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /tmp/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${arch}.tar.gz" \
    && tar -xzf /tmp/trivy.tar.gz --no-same-owner -C /usr/local/bin trivy \
    && rm /tmp/trivy.tar.gz

RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
        -o /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH}" \
    && chmod 0755 /usr/local/bin/sops
