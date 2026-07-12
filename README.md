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
```

The project is currently at the architecture bootstrap stage. The product
contract is in [docs/PRD.md](docs/PRD.md), the design is in
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
```

## License

MIT
