#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# run-tests.bash - postDockerTests hook for forestay-build-image-aws
#
# Asserts every tool runs and reports the version it was pinned to, that every
# listed envtest control plane exists, and that the network lockdown is on.
#
# Versions are compared against the pin, not merely run: a tool that silently
# drifts from its pin is worse than one that is missing.
#
# Must run on bash 3.2.57: no associative arrays, no mapfile, no ${var,,}.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILURES=0

log() {
  echo "$@"
}

fail() {
  echo "[FAILED] $*" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "[ok] $*"
}

find_container_cli() {
  if [[ -n "${CONTAINER_CLI:-}" ]]; then
    echo "${CONTAINER_CLI}"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker"
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi
  return 1
}

in_image() {
  local cli="$1"
  local image="$2"
  shift 2
  "${cli}" run --rm --entrypoint /bin/sh "${image}" -c "$*" 2>/dev/null
}

assert_tool_version() {
  local cli="$1"
  local image="$2"
  local label="$3"
  local pin_var="$4"
  local command="$5"
  local pin reported

  pin=$(in_image "${cli}" "${image}" "printf '%s' \"\${${pin_var}}\"")
  if [[ -z "${pin}" ]]; then
    fail "${label}: pin ${pin_var} is not set in the image"
    return
  fi

  reported=$(in_image "${cli}" "${image}" "${command}" || true)
  if [[ -z "${reported}" ]]; then
    fail "${label}: did not run or produced no output (${command})"
    return
  fi

  # Pins carry a leading v for some tools and not others
  local bare_pin="${pin#v}"
  if echo "${reported}" | grep -q -F "${bare_pin}"; then
    pass "${label} ${pin}"
  else
    fail "${label}: pinned ${pin} but reports '${reported}'"
  fi
}

assert_envtest_assets() {
  local cli="$1"
  local image="$2"
  local versions root missing version

  # Expand inside the image, not here
  # shellcheck disable=SC2016
  root=$(in_image "${cli}" "${image}" 'printf "%s" "${ENVTEST_ROOT}"')
  # shellcheck disable=SC2016
  versions=$(in_image "${cli}" "${image}" 'printf "%s" "${ENVTEST_VERSIONS}"')

  if [[ -z "${versions}" ]]; then
    fail "ENVTEST_VERSIONS is not set in the image"
    return
  fi

  missing=0
  for version in ${versions}; do
    if in_image "${cli}" "${image}" \
        "test -x '${root}/${version}/kube-apiserver' && test -x '${root}/${version}/etcd'"; then
      pass "envtest ${version} control plane present"
    else
      fail "envtest ${version} control plane missing under ${root}/${version}"
      missing=$((missing + 1))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    pass "envtest assets complete for: ${versions}"
  fi
}

# The image bakes the consumer's modules, so it can answer for their age and
# pinning without a network. The script is mounted from this repo rather than
# baked in, because an image that supplied the script judging it could ship
# one that passes.
assert_dep_age() {
  local cli="$1"
  local image="$2"

  if "${cli}" run --rm --network none \
      --volume "${REPO_ROOT}/src/bin:/check:ro,z" \
      --entrypoint /bin/sh "${image}" \
      -c 'cd /opt/deps && /check/check-dep-age.bash' >/dev/null 2>&1; then
    pass "dependencies pinned and old enough"
  else
    fail "dependency age or pinning check failed inside the image"
  fi
}

assert_lockdown() {
  local cli="$1"
  local image="$2"
  local value

  value=$(in_image "${cli}" "${image}" 'go env GOPROXY')
  if [[ "${value}" == "off" ]]; then
    pass "GOPROXY=off"
  else
    fail "GOPROXY is '${value}', expected off"
  fi

  value=$(in_image "${cli}" "${image}" 'go env GOTOOLCHAIN')
  if [[ "${value}" == "local" ]]; then
    pass "GOTOOLCHAIN=local"
  else
    fail "GOTOOLCHAIN is '${value}', expected local"
  fi

  value=$(in_image "${cli}" "${image}" 'go env GOFLAGS')
  if echo "${value}" | grep -q -F -- "-mod=readonly"; then
    pass "GOFLAGS carries -mod=readonly"
  else
    fail "GOFLAGS is '${value}', expected to contain -mod=readonly"
  fi
}

test_image() {
  local cli="$1"
  local image="$2"

  log ""
  log "--- ${image} ---"

  if ! "${cli}" image inspect "${image}" >/dev/null 2>&1; then
    fail "image not present locally: ${image}"
    return
  fi

  # GOLANG_VERSION is set by the upstream golang image, not by us.
  assert_tool_version "${cli}" "${image}" "go" \
    "GOLANG_VERSION" 'go version'
  assert_tool_version "${cli}" "${image}" "controller-gen" \
    "CONTROLLER_GEN_VERSION" 'controller-gen --version'
  assert_tool_version "${cli}" "${image}" "staticcheck" \
    "STATICCHECK_VERSION" 'staticcheck --version'
  assert_tool_version "${cli}" "${image}" "golangci-lint" \
    "GOLANGCI_LINT_VERSION" 'golangci-lint --version'
  assert_tool_version "${cli}" "${image}" "aws" \
    "AWS_CLI_VERSION" 'aws --version'

  # "setup-envtest version" rather than --version, which exits 2
  assert_tool_version "${cli}" "${image}" "setup-envtest" \
    "SETUP_ENVTEST_VERSION" 'setup-envtest version'

  assert_envtest_assets "${cli}" "${image}"
  assert_dep_age "${cli}" "${image}"
  assert_lockdown "${cli}" "${image}"
}

main() {
  local cli platform suffix image tested

  if ! cli=$(find_container_cli); then
    echo "[FAILED] no container CLI found, set CONTAINER_CLI or install docker or podman" >&2
    exit 1
  fi
  log "Using container CLI: ${cli}"

  if [[ -z "${DOCKER_TARGET_IMAGE_FULL_URI:-}" ]]; then
    echo "[FAILED] DOCKER_TARGET_IMAGE_FULL_URI is not set" >&2
    exit 1
  fi

  tested=0

  # Same derivation the build uses: slashes to hyphens, appended to the URI
  if [[ "${DOCKER_PLATFORM:-}" == *,* ]]; then
    local platforms
    IFS=',' read -r -a platforms <<< "${DOCKER_PLATFORM}"
    for platform in "${platforms[@]}"; do
      suffix=$(echo "${platform}" | tr '/' '-')
      image="${DOCKER_TARGET_IMAGE_FULL_URI}-${suffix}"
      test_image "${cli}" "${image}"
      tested=$((tested + 1))
    done
  else
    test_image "${cli}" "${DOCKER_TARGET_IMAGE_FULL_URI}"
    tested=$((tested + 1))
  fi

  log ""
  if [[ ${FAILURES} -gt 0 ]]; then
    echo "[FAILED] ${FAILURES} check(s) failed across ${tested} image(s)" >&2
    exit 1
  fi
  log "All checks passed across ${tested} image(s)"
}

main "$@"
