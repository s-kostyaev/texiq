#!/bin/sh
set -eu

binary=${1:?usage: scripts/smoke_test.sh BINARY [EXPECTED_VERSION]}
expected_version=${2:-}

if [ ! -x "$binary" ]; then
  echo "texiq smoke: binary is not executable: $binary" >&2
  exit 1
fi

version=$("$binary" -version)
if [ -z "$version" ] || [ "$version" = "NO_VERSION_UTIL" ]; then
  echo "texiq smoke: binary has no usable version" >&2
  exit 1
fi
if [ -n "$expected_version" ] && [ "$version" != "$expected_version" ]; then
  echo "texiq smoke: expected version $expected_version, got $version" >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/texiq-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf '\037\nFile: smoke.info, Node: Top, Up: (dir)\nSmoke body.\n' > "$work/smoke.info"

output=$("$binary" --raw-output "$work/smoke.info" '.node("Top") | .text')
if [ "$output" != "Smoke body." ]; then
  echo "texiq smoke: unexpected node text: $output" >&2
  exit 1
fi

json=$("$binary" --format json "$work/smoke.info" '.nodes | map(.name)')
printf '%s\n' "$json" | grep '"schema_version"' >/dev/null
printf '%s\n' "$json" | grep '"Top"' >/dev/null

jsonl=$("$binary" --format jsonl "$work/smoke.info" '.nodes | map(.name)')
printf '%s\n' "$jsonl" | grep '"schema_version":1' >/dev/null
printf '%s\n' "$jsonl" | grep '"data":"Top"' >/dev/null

first=$("$binary" "$work/smoke.info" '.nodes | map(.name)')
second=$("$binary" "$work/smoke.info" '.nodes | map(.name)')
if [ "$first" != "$second" ]; then
  echo "texiq smoke: repeated query output differs" >&2
  exit 1
fi

printf 'texiq smoke: version=%s ok\n' "$version"
