#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# One envtest control plane per supported Kubernetes minor, so the test matrix
# downloads nothing.
#
# Reads ENVTEST_VERSIONS, ENVTEST_ROOT and DOCKER_PLATFORM_CPU_ARCHITECTURE
# from the image environment.

set -euo pipefail

mkdir -p "${ENVTEST_ROOT}"

for version in ${ENVTEST_VERSIONS}; do
  name="envtest-v${version}-linux-${DOCKER_PLATFORM_CPU_ARCHITECTURE}.tar.gz"
  url="https://github.com/kubernetes-sigs/controller-tools/releases/download/envtest-v${version}/${name}"

  echo "Fetching ${name}"
  curl -fsSL -o "/tmp/${name}" "${url}"
  curl -fsSL -o "/tmp/${name}.sha512" "${url}.sha512"

  # The published .sha512 holds an absolute path, so sha512sum -c cannot use it
  expected="$(awk '{print $1}' "/tmp/${name}.sha512")"
  actual="$(sha512sum "/tmp/${name}" | awk '{print $1}')"
  if [ "${expected}" != "${actual}" ]; then
    echo "checksum mismatch for ${name}" >&2
    echo "  expected ${expected}" >&2
    echo "  actual   ${actual}" >&2
    exit 1
  fi

  mkdir -p "${ENVTEST_ROOT}/${version}"
  tar xzf "/tmp/${name}" -C "${ENVTEST_ROOT}/${version}" --strip-components=2
  rm -f "/tmp/${name}" "/tmp/${name}.sha512"

  test -x "${ENVTEST_ROOT}/${version}/kube-apiserver"
  test -x "${ENVTEST_ROOT}/${version}/etcd"
done
