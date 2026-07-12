#!/bin/sh
set -eu

version=${1:?usage: scripts/package_release.sh VERSION}
case "$version" in
  v*) ;;
  *) echo "VERSION must start with v" >&2; exit 2 ;;
esac
expected_version=${version#v}

opam exec -- dune build bin/main.exe
scripts/smoke_test.sh _build/default/bin/main.exe "$expected_version"
mkdir -p dist/package
if [ -f dist/package/texiq ]; then
  chmod u+w dist/package/texiq
fi
cp _build/default/bin/main.exe dist/package/texiq
chmod +x dist/package/texiq
tar -C dist/package -czf "dist/texiq-${version}.tar.gz" texiq
smoke_dir=$(mktemp -d "${TMPDIR:-/tmp}/texiq-package-smoke.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT HUP INT TERM
tar -C "$smoke_dir" -xzf "dist/texiq-${version}.tar.gz"
scripts/smoke_test.sh "$smoke_dir/texiq" "$expected_version"
shasum -a 256 "dist/texiq-${version}.tar.gz"
