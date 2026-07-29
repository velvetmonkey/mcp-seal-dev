#!/usr/bin/env bash
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! leanbuild build m7_version_gate; then
  echo "M7 LEAN RUNNER REFUSED build-failed; stale binary was not executed" >&2
  exit 1
fi

exec .lake/build/bin/m7_version_gate
