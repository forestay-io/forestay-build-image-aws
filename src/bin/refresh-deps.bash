#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# refresh-deps.bash - pull the consumer's go.mod and go.sum in here
#
# Step 2 of three. Nothing is resolved here and nothing is pushed anywhere:
# the consumer owns its dependencies because that is where the source is, and
# this repo only mirrors the result so the modules can be baked in.
#
# Usage:
#   src/bin/refresh-deps.bash
#
# The full change:
#   1. consumer: src/bin/resolve-deps.bash
#   2. here: src/bin/refresh-deps.bash, then commit, PR, merge to release
#   3. consumer: bump BuildImageVersion, commit all three files together
#
# Must run on bash 3.2.57: no associative arrays, no mapfile, no ${var,,}.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

MARKER="-build-image"

die() { printf '[FAILED] %s\n' "$*" >&2; exit 1; }

# forestay-build-image-aws -> forestay-aws, so every variant reuses this
infer_consumer() {
  local self="${FORESTAY_CONSUMER:-}"
  if [ -n "${self}" ]; then
    printf '%s' "${self}"
    return 0
  fi

  self="$(basename "${REPO_ROOT}")"
  case "${self}" in
    *"${MARKER}-"*)
      printf '%s-%s' "${self%%"${MARKER}-"*}" "${self##*"${MARKER}-"}"
      ;;
    *"${MARKER}")
      printf '%s' "${self%"${MARKER}"}"
      ;;
    *)
      die "cannot infer the consumer: '${self}' does not contain ${MARKER}. Set FORESTAY_CONSUMER."
      ;;
  esac
}

main() {
  local consumer source_repo source_dir deps_dir file changed

  consumer="$(infer_consumer)"
  source_repo="${FORESTAY_CONSUMER_REPO:-$(dirname "${REPO_ROOT}")/${consumer}}"
  source_dir="${source_repo}/src/go"
  deps_dir="src/docker"

  [ -d "${source_repo}" ] \
    || die "no ${source_repo}. Clone it beside this repo, or set FORESTAY_CONSUMER_REPO."

  # Both or nothing. A go.mod with no go.sum means either resolve-deps has not
  # run, or the module has no dependencies and there is nothing to bake in.
  # Either way, pulling half a pair and releasing on it is worse than stopping.
  for file in go.mod go.sum; do
    [ -f "${source_dir}/${file}" ] \
      || die "no ${source_dir}/${file}. Run resolve-deps.bash in ${consumer} first."
  done

  echo "Consumer: ${consumer}"
  echo "Source:   ${source_dir}"
  echo "Target:   ${deps_dir}"
  echo

  [ -d "${deps_dir}" ] || die "no ${deps_dir}, this is not the build image repo"

  changed=0
  for file in go.mod go.sum; do
    if cmp -s "${source_dir}/${file}" "${deps_dir}/${file}"; then
      echo "  unchanged ${file}"
    else
      cp "${source_dir}/${file}" "${deps_dir}/${file}"
      echo "  pulled ${file}"
      changed=1
    fi
  done

  echo
  if [ "${changed}" -eq 0 ]; then
    echo "Already in step with ${consumer}, nothing to release."
    return 0
  fi

  echo "Review the diff, commit, PR and merge to release."
  echo "Then in ${consumer}, bump BuildImageVersion to the new release and"
  echo "commit go.mod, go.sum and BuildImageVersion together."
}

main "$@"
