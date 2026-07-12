# Implementation plan

Stages are ordered vertical slices. A stage is complete only when its checks,
fixtures, documentation updates, and acceptance scenario pass.

## M0: contract and project harness

- Establish the Jane Street OCaml/Dune project skeleton.
- Lock the PRD, architecture, exit status, result ordering, and diagnostics
  shape.
- Add fixture directories and golden/expect-test conventions.
- Add CI for `dune build`, `dune runtest`, formatting, and opam package build.

Acceptance: a clean clone builds and tests; `texiq --help` describes the
planned top-directory default without exposing unimplemented selectors.

## M1: top directory catalog

- Implement effective `INFOPATH` and `-d/--directory` precedence.
- Parse supported `dir` filename variants and compressed directory files.
- Merge categories and entries with stable provenance and deduplication.
- Implement catalog summary, `.tree`, `.categories`, `.entries`, and
  `.manuals` through a minimal selector parser.

Acceptance: `texiq` produces a stable merged view for multiple fixture `dir`
files and matches the relevant entries in GNU Info/Emacs directory output.

## M2: manual loading and node graph

- Resolve an Info name or explicit main-file path.
- Add gzip and split-manual loading.
- Parse preamble, indirect table, tag table, local variables, nodes, and
  Next/Prev/Up headers.
- Verify offsets and implement bounded recovery.
- Implement manual summary, `.nodes`, `.node(name)`, `.tree`, and `.text`.

Acceptance: nonsplit and split fixtures plus installed `info-stnd` and
`texinfo` manuals return the same selected-node text as GNU `info`.

## M3: typed query core

- Complete lexer, parser, AST, and type checker.
- Add pipes, field access, `filter`, `map`, comparisons, boolean operations,
  indexing, slicing, and `.length`.
- Add type-specific repair hints and stable exit classification.
- Add text, JSON, JSONL, and raw renderers with schema versioning.

Acceptance: golden query results are byte-stable across repeated runs and bad
queries identify the invalid stage, current type, and a valid next action.

## M4: Info entities and scoped search

- Parse menus, multiline descriptions, xrefs, anchors, and index entries.
- Add `.menus`, `.xrefs`, `.indices`, and literal/regex `.search` for a manual.
- Produce bounded snippets with exact node and line locations.

Acceptance: agent scenarios discover, narrow, and extract answers without
reading a whole manual.

## M5: global catalog search

- Traverse manuals registered by the merged catalog.
- Parse each source once per invocation and continue with coverage diagnostics.
- Sort complete results deterministically.
- Apply renderer-only result caps with total/returned/truncated metadata.
- Add `--strict`, `--max-results`, and `--all-results` behavior.

Acceptance: `texiq dir '.search("term")'` finds fixture matches across split,
compressed, duplicate, and partially broken manual sets with stable ordering.

## M6: hardening and distribution

- Add fuzz/property tests for parser boundaries and malformed offsets.
- Benchmark startup, global scan, allocation, output size, and context savings.
- Add an optional versioned parse cache only if benchmarks justify it.
- Produce GitHub release binaries, then prepare opam and Homebrew delivery.
- Publish an agent playbook with discover/narrow/extract/recover examples.

Acceptance: release artifacts pass fixture, differential, package, and agent
workflow suites on supported platforms.
