#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Forestay contributors (Fred Cooke)
#
# check-dep-age.bash - refuse dependencies published too recently
#
# A freshly published version is where a compromised maintainer account or a
# typosquat lands. Waiting gives the ecosystem time to notice. This enforces
# that floor over the whole build list, indirect dependencies included,
# because that is where such a version usually arrives.
#
# Deliberately duplicated per repo and mounted in, never baked into the image.
# An image that supplies the script judging it could ship one that passes.
# Runs INSIDE a container, working directory set to a directory holding go.mod.
# Reads publish times from the .info files go mod download already writes into
# GOMODCACHE, so it needs no network and works inside the locked down build
# image as well as during resolution.
#
# Also refuses anything unpinned in go.mod: latest is not a version.
#
# MIN_DEP_AGE_DAYS overrides the floor. ALLOW_YOUNG_DEPS is a space separated
# list of module@version escapes, for a security patch you need immediately.

set -euo pipefail

MIN_DEP_AGE_DAYS="${MIN_DEP_AGE_DAYS:-14}"
ALLOW_YOUNG_DEPS="${ALLOW_YOUNG_DEPS:-}"

fail=0

# Uppercase is !-escaped in both proxy URLs and the on-disk cache, so
# github.com/Masterminds/... lives under github.com/!masterminds/...
escape_path() {
  printf '%s' "$1" | sed 's/\([A-Z]\)/!\1/g' | tr '[:upper:]' '[:lower:]'
}

allowed() {
  local want="$1" entry
  for entry in ${ALLOW_YOUNG_DEPS}; do
    [ "${entry}" = "${want}" ] && return 0
  done
  return 1
}

echo "== go.mod is fully pinned =="
if grep -n "latest" go.mod; then
  echo "[FAILED] go.mod names 'latest'. Pin an explicit version." >&2
  fail=1
else
  echo "[ok] no unpinned versions"
fi

echo
echo "== every dependency is at least ${MIN_DEP_AGE_DAYS} days old =="

cache="$(go env GOMODCACHE)/cache/download"
now="$(date -u +%s)"
checked=0

# go.mod's require list, read straight off disk. go list -m all needs to
# resolve the graph and so fails under GOPROXY=off, which is exactly the
# environment this has to work in. The require list is also the honest set:
# go.sum holds versions that were considered and rejected and never compiled.
modules="$(go mod edit -json | python3 -c '
import json, sys
for r in json.load(sys.stdin).get("Require") or []:
    print(r["Path"], r["Version"])
')"

[ -n "${modules}" ] || {
  echo "[FAILED] no requirements read from go.mod, refusing to pass vacuously" >&2
  exit 1
}

while read -r path version; do
  [ -n "${version}" ] || continue

  info="${cache}/$(escape_path "${path}")/@v/${version}.info"
  if [ ! -f "${info}" ]; then
    echo "[FAILED] no cached .info for ${path}@${version}, cannot age check" >&2
    fail=1
    continue
  fi

  published="$(sed -n 's/.*"Time":"\([^"]*\)".*/\1/p' "${info}")"
  if [ -z "${published}" ]; then
    echo "[FAILED] no Time in ${info}" >&2
    fail=1
    continue
  fi

  # GNU date, present in both images, which are bookworm based
  epoch="$(date -u -d "${published}" +%s 2>/dev/null || true)"
  if [ -z "${epoch}" ]; then
    echo "[FAILED] could not parse ${published} for ${path}@${version}" >&2
    fail=1
    continue
  fi

  age=$(( (now - epoch) / 86400 ))
  checked=$(( checked + 1 ))

  if [ "${age}" -lt "${MIN_DEP_AGE_DAYS}" ]; then
    if allowed "${path}@${version}"; then
      echo "[allowed] ${path}@${version} is ${age}d old, explicitly permitted"
    else
      echo "[FAILED] ${path}@${version} is ${age}d old, minimum is ${MIN_DEP_AGE_DAYS}d" >&2
      fail=1
    fi
  fi
done <<EOF
${modules}
EOF

# A check that examined nothing must never report success.
if [ "${checked}" -eq 0 ]; then
  echo "[FAILED] checked 0 modules, something is wrong with this check" >&2
  fail=1
else
  echo "[ok] checked ${checked} module(s)"
fi

echo
if [ "${fail}" -ne 0 ]; then
  echo "[FAILED] dependency age or pinning check failed" >&2
  exit 1
fi
echo "All dependencies pinned and at least ${MIN_DEP_AGE_DAYS} days old"
