#!/bin/sh
set -eu

binary=${1:-_build/default/bin/main.exe}
if ! command -v info >/dev/null 2>&1; then
  echo "texiq differential: GNU info is required" >&2
  exit 77
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/texiq-differential.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
manual="$work/differential.info"
gnu="$work/gnu.txt"
texiq="$work/texiq.txt"

printf '\037\nFile: differential.info, Node: Top, Next: Child, Up: (dir)\nTop.\n\037\nFile: differential.info, Node: Child, Prev: Top, Up: Top\nExact child body.\n' > "$manual"
info --file "$manual" --node Child --output "$gnu"
tail -n +2 "$gnu" > "$work/gnu-body.txt"
"$binary" --raw-output "$manual" '.node("Child") | .text' > "$texiq"
cmp "$work/gnu-body.txt" "$texiq"

echo "texiq differential: GNU Info node text matches"
