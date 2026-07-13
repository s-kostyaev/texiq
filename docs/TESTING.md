# Testing and evaluation

## Fast checks

```sh
dune build
dune runtest
dune fmt
git diff --check
```

## Test layers

1. Pure unit tests for identifiers, byte ranges, catalog merge, query parsing,
   type checking, and result ordering.
2. Inline expect tests for CLI output, diagnostics, and repair hints.
3. Golden fixtures for nonsplit, split, gzip, malformed offsets, DEL-quoted
   names, encodings, multiline menus, indices, cycles, and external xrefs.
4. Differential tests against GNU `info` for selected nodes in installed
   manuals. GNU `info` is a test oracle, not a runtime dependency.
5. Agent workflow scenarios: directory discovery, global search, manual
   narrowing, exact node extraction, and recovery from a misspelled node.

## Determinism checks

Every end-to-end scenario runs twice and compares stdout, stderr, exit status,
and JSON values. Fixture traversal and results use explicit stable ordering.

## Eval metrics

- task pass rate;
- output bytes and estimated tokens;
- number of agent/tool turns;
- recovery count;
- parse coverage and validation failures;
- wall-clock time and peak memory;
- cache hit rate, if a cache is later introduced.

Compare baseline whole-manual reads, GNU `info --subnodes`, scoped manual
queries, and full catalog search followed by targeted extraction.

Run the deterministic parser benchmark with:

```sh
dune exec bench/benchmark_check.exe -- -nodes 5000 -iterations 5
```

The automated differential check uses installed GNU Info as an oracle:

```sh
scripts/differential_test.sh _build/default/bin/main.exe
```

## Distribution checks

`dune runtest` includes black-box CLI checks for help/version output, text,
raw text, JSON, JSONL, failure status, and byte-identical repeated queries.
The reusable package smoke test verifies a built or installed executable:

```sh
scripts/smoke_test.sh _build/default/bin/main.exe 1.1.0
```

CI additionally installs `texiq.opam` into an opam switch, runs the smoke test
against the installed executable, and compares exact node output with GNU
Info. A release tag must be `v` followed by
the version in `dune-project`; release verification and both packaged-binary
smoke tests must succeed before the publish job can run.

The CLI cram layer uses a fake `emacsclient` to verify `--emacs` directory
resolution and stable connection-failure diagnostics without depending on a
developer's running Emacs server.
