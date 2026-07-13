# texiq

`texiq` is an agent-first CLI for deterministic, structure-first querying of
GNU Info manuals.

The intended workflow is:

1. inspect the merged `(dir)Top` catalog;
2. search across registered manuals or narrow to one manual;
3. inspect its node graph;
4. extract only the relevant node text.

```sh
texiq
texiq dir '.search("indirect table")'
texiq texinfo '.tree'
texiq texinfo '.node("Info Format Indirect Table") | .text'
texiq --emacs ellama '.nodes | map(.name)'
```

Use `--emacs` when the desired manual is visible in Emacs Info but its
directory is not present in the shell's `INFOPATH`. `texiq` asks the active
Emacs server for `Info-directory-list` through `emacsclient`, preserving Emacs
precedence. Explicit `-d` directories still take precedence over that list.

The project implements the planned catalog, parser, graph, query, search, and
rendering pipeline. The product contract is in [docs/PRD.md](docs/PRD.md), the design is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and staged delivery is tracked in
[docs/implementation_plan.md](docs/implementation_plan.md).

## Stack

`texiq` uses the Jane Street OCaml stack and its conventions:

- OCaml 5.1 or newer;
- Dune 3.17 or newer;
- `Core` and `Core_unix`;
- `Command` and `Command_unix` for the CLI;
- `ppx_jane` and expect tests;
- `ocamlformat` with the `janestreet` profile;
- explicit module interfaces and typed boundary errors.

## Development

```sh
dune build
dune runtest
dune fmt
dune exec bench/benchmark_check.exe -- -nodes 5000 -iterations 5
```

Install from a checkout with:

```sh
opam install . --deps-only
dune build -p texiq
dune install
```

## Agent skill

The installable agent workflow lives in [`skills/texiq`](skills/texiq). It
teaches agents to discover manuals from `(dir)Top`, narrow with bounded search,
and extract only the selected node text. Link that canonical directory into a
supported skill scope rather than copying it, so repository updates remain
visible:

```sh
ln -s "$PWD/skills/texiq" "${CODEX_HOME:-$HOME/.codex}/skills/texiq"
ln -s "$PWD/skills/texiq" "$HOME/.emacs.d/ellama/skills/texiq"
```

## License

MIT

## Distribution

Git tags matching the version in `dune-project`, with a `v` prefix, trigger
verified Linux x86-64 and macOS arm64 binary artifacts. Before publication the
workflow runs the source tests, package build, version check, and a packaged-CLI
smoke test on both artifact platforms. The opam manifest is `texiq.opam`; a
release-substitution Homebrew formula is provided in
`packaging/homebrew/texiq.rb.in`.
