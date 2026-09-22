#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# Bake the consumer's modules into GOMODCACHE and compile the stdlib into
# GOCACHE, so a consuming build with GOPROXY=off downloads nothing and
# compiles only its own code.
#
# GOCACHE entries are keyed on build configuration, so the flags below must
# match build-binaries.bash exactly or nothing here is ever read. -ldflags is
# omitted deliberately: it affects the final link, not package compilation.

set -euo pipefail

DEPS_ROOT="${DEPS_ROOT:-/opt/deps}"

# Fail loudly rather than shipping an image with an empty module cache: with
# GOPROXY=off downstream, that surfaces a repo away as every module missing.
[ -f "${DEPS_ROOT}/go.mod" ] || {
  echo "no ${DEPS_ROOT}/go.mod, nothing to bake in" >&2
  exit 1
}

# Subshell so the stdlib compile below does not inherit the module directory
echo "Downloading modules"
(cd "${DEPS_ROOT}" && go mod download)

echo "Compiling stdlib for linux/${DOCKER_PLATFORM_CPU_ARCHITECTURE}"
CGO_ENABLED=0 GOOS=linux GOARCH="${DOCKER_PLATFORM_CPU_ARCHITECTURE}" go build -trimpath std
