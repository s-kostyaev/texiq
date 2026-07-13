# AGENTS.md

`texiq` is an agent-first, read-only query CLI for GNU Info manuals.

## Context map

- Product behavior and scope: `docs/PRD.md`
- Module boundaries and invariants: `docs/ARCHITECTURE.md`
- Ordered implementation stages: `docs/implementation_plan.md`
- Validation strategy: `docs/TESTING.md`
- Performance baseline and cache decision: `docs/PERFORMANCE.md`
- Agent usage and recovery: `docs/agent-playbook.md`
- Installable agent workflow: `skills/texiq/SKILL.md`

Read the relevant document before changing its corresponding contract. Do not
mirror these documents into this file.

## Project conventions

- Use OCaml >= 5.1 and Dune >= 3.17.
- Prefer `Core`/`Core_unix` APIs and Jane Street naming conventions.
- Build the CLI with `Command` and `Command_unix`, not an additional CLI stack.
- Give public modules explicit `.mli` interfaces.
- Prefer labeled arguments when two values of the same type could be confused.
- Name partial functions with an `_exn` suffix; keep failures typed at module
  boundaries.
- Derive `sexp_of`, `compare`, and `equal` where they improve diagnostics and
  tests; do not expose unstable serialization accidentally.
- Use `ppx_jane` and expect tests for user-visible output.
- Format OCaml with the repository's Jane Street `ocamlformat` profile.
- Keep parsing, resolution, evaluation, and rendering separate.
- Preserve deterministic ordering and stable diagnostics in every stage.

## Required checks

Run before treating a change as complete:

```sh
dune build
dune runtest
dune fmt
git diff --check
```

## Release discipline

Read the Distribution checks in `docs/TESTING.md` before changing the project
version or publishing a release.

- Do not change the version in `dune-project` during ordinary implementation.
  Bump it only when the user has asked to prepare or publish a release.
- Preparing and publishing are different authorization scopes. If the user
  asked only to prepare a release, stop before creating or pushing a tag and
  report that the version is unreleased.
- Once an authorized release version is committed to `main`, do not report the
  release complete until an annotated `v<VERSION>` tag points at the exact
  release commit, the tag is pushed, the Release workflow succeeds, and the
  GitHub Release contains both Linux x86-64 and macOS arm64 artifacts.
- Release tags are immutable. Never move or overwrite an existing tag; fix a
  published release forward with a new version.
- A successful branch CI run is not evidence that a GitHub Release exists.

Use this post-release audit before handoff:

```bash
set -euo pipefail
VERSION=$(sed -n 's/^(version \(.*\))$/\1/p' dune-project)
TAG="v$VERSION"
test "$(git rev-list -n 1 "$TAG")" = "$(git rev-parse HEAD)"
test "$(gh run list --workflow release.yml --branch "$TAG" --limit 1 --json conclusion --jq '.[0].conclusion')" = success
gh release view "$TAG" --json assets --jq '.assets[].name' | grep -Fxq texiq-linux-x86_64.tar.gz
gh release view "$TAG" --json assets --jq '.assets[].name' | grep -Fxq texiq-macos-arm64.tar.gz
gh release view "$TAG" --json tagName,url,assets
git status --short --branch
```
