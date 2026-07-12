# AGENTS.md

`texiq` is an agent-first, read-only query CLI for GNU Info manuals.

## Context map

- Product behavior and scope: `docs/PRD.md`
- Module boundaries and invariants: `docs/ARCHITECTURE.md`
- Ordered implementation stages: `docs/implementation_plan.md`
- Validation strategy: `docs/TESTING.md`

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
