#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
tmp_bin="$(mktemp "${TMPDIR:-/tmp}/divide-engine.XXXXXX")"
trap 'rm -f "$tmp_bin"' EXIT
swiftc Sources/DivideEngine.swift Tests/EngineSmoke.swift -o "$tmp_bin"
"$tmp_bin"
