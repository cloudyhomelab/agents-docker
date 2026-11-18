#!/usr/bin/env bash
# Copyright (c) 2026 binarycodes
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs the newest Temurin JDK of every major in JAVA_VERSIONS from the
# Adoptium apt repo, exposed as /opt/java/<major>, and the newest stable Maven
# into /opt/maven. Nothing is pinned: each build takes whatever is current.

set -euo pipefail

MAVEN_REPO="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven"
CURL=(curl -fsSL --retry 5 --retry-all-errors --retry-delay 2)

fail() {
  echo "$*" >&2
  exit 1
}

# Read from the apt lists, so it can only name a major the repo actually ships.
newest_major() {
  apt-cache pkgnames temurin- | sed -n 's/^temurin-\([0-9]*\)-jdk$/\1/p' | sort -n | tail -n 1
}

# The checksum comes from the same host as the archive, so it guards against a
# truncated download, not against a compromised publisher.
fetch_verified() {
  local url="$1" algorithm="$2" sum="$3" out="$4"

  "${CURL[@]}" -o "${out}" "${url}"
  echo "${sum}  ${out}" | "${algorithm}sum" --check --quiet -
}

# /opt/java/<major> rather than the package's own directory: that one carries
# the Debian architecture, and the entrypoint, the smoke test and JAVA_HOME
# want one path per major on every platform.
install_jdks() {
  local arch entry major home tool
  local -a majors=() packages=()

  arch=$(dpkg --print-architecture)
  apt-get update

  for entry in ${JAVA_VERSIONS}; do
    major="${entry}"
    [[ ${entry} != latest ]] || major=$(newest_major)
    [[ ${major} =~ ^[0-9]+$ ]] || fail "JAVA_VERSIONS entry '${entry}' is neither a major nor latest"
    majors+=("${major}")
  done
  # latest may already be listed as a major of its own.
  mapfile -t majors < <(printf '%s\n' "${majors[@]}" | sort -un)

  for major in "${majors[@]}"; do
    packages+=("temurin-${major}-jdk")
  done
  apt-get install -y --no-install-recommends "${packages[@]}"

  mkdir -p /opt/java
  for major in "${majors[@]}"; do
    home="/usr/lib/jvm/temurin-${major}-jdk-${arch}"
    test -d "${home}" || fail "temurin-${major}-jdk did not install into ${home}"
    ln -s "${home}" "/opt/java/${major}"
  done

  test -d "/opt/java/${JAVA_LTS}" || fail "JAVA_LTS=${JAVA_LTS} not among JAVA_VERSIONS"
  ln -s "${JAVA_LTS}" /opt/java/lts
  ln -s "${majors[-1]}" /opt/java/latest

  # Otherwise /usr/bin/java is the highest major, by package priority. The exit
  # status is not trusted: the .jinfo lists tools such as jrunscript that newer
  # majors no longer ship, so the result is checked instead.
  home="/usr/lib/jvm/temurin-${JAVA_LTS}-jdk-${arch}"
  update-java-alternatives --set "temurin-${JAVA_LTS}-jdk-${arch}" || true
  for tool in java javac; do
    [[ $(readlink -f "/usr/bin/${tool}") == "${home}/bin/${tool}" ]] \
      || fail "/usr/bin/${tool} is not the JAVA_LTS=${JAVA_LTS} one after update-java-alternatives"
  done
}

# Only plain x.y.z counts as stable: the metadata also lists alphas, betas and
# release candidates, and 4.0.0-rc-* would otherwise sort above 3.x.
install_maven() {
  local metadata version sum

  metadata=$("${CURL[@]}" "${MAVEN_REPO}/maven-metadata.xml")
  version=$(sed -n 's|.*<version>\([0-9]*\.[0-9]*\.[0-9]*\)</version>.*|\1|p' <<<"${metadata}" | sort -V | tail -n 1)
  [[ -n ${version} ]] || fail "no stable Maven release in ${MAVEN_REPO}/maven-metadata.xml"
  sum=$("${CURL[@]}" "${MAVEN_REPO}/${version}/apache-maven-${version}-bin.tar.gz.sha512")

  fetch_verified "${MAVEN_REPO}/${version}/apache-maven-${version}-bin.tar.gz" sha512 "${sum%% *}" /tmp/maven.tar.gz
  mkdir -p /opt/maven
  tar -xzf /tmp/maven.tar.gz --no-same-owner --strip-components=1 -C /opt/maven
  rm /tmp/maven.tar.gz
  chmod -R a+rX /opt/maven
  echo "installed Maven ${version} into /opt/maven"
}

install_jdks
install_maven
