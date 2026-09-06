# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# The toolchains are the published base, built from base/; docker-bake.hcl
# assembles the reference from its pinned tag and digest. Declared here because
# a FROM can only read an arg from above the first stage.
ARG BASE_IMAGE

# Declarations only -- every stage redeclares what it uses. They are here
# because one bake target passes all three agent versions to every agent build,
# which reaches just one of the CLI stages, and an arg no reached stage declares
# is one BuildKit warns about.
ARG CLAUDE_VERSION
ARG CODEX_VERSION
ARG GEMINI_VERSION


#====================
# runtime
#====================
FROM ${BASE_IMAGE} AS runtime

COPY --chmod=0755 scripts/agent-entrypoint /usr/local/bin/agent-entrypoint
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]


#====================
# claude
#====================
FROM runtime AS claude
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
FROM runtime AS codex
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
FROM runtime AS gemini
ARG GEMINI_VERSION

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g --prefix /usr/local @google/gemini-cli@"${GEMINI_VERSION}" \
    && install -d -o agent -g agent /home/agent/.gemini

USER 1000
WORKDIR /home/agent
CMD ["gemini"]
