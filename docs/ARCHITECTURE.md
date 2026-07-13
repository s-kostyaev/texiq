# Architecture

## Design principles

1. The native Info graph is canonical; a tree is a deterministic projection.
2. Catalog discovery, manual loading, parsing, querying, and rendering are
   separate boundaries.
3. Full text is emitted only after a query has narrowed scope.
4. Byte positions are retained because tag and indirect tables are byte-based.
5. No external reference is followed automatically.
6. Parser recovery is observable; silent data loss is forbidden.

## Jane Street OCaml profile

The project follows Jane Street-style OCaml conventions:

- `Core` is the default standard library;
- Unix integration is isolated behind `Core_unix`;
- the CLI uses `Command` with `Command_unix.run`;
- preprocessing uses `ppx_jane`;
- user-visible behavior is covered by inline expect tests;
- domain types use explicit interfaces, labeled arguments, and useful derives;
- typed errors cross library boundaries and are rendered only at the CLI edge.

`Async` is not part of the initial stack. Parsing and search begin as a
deterministic synchronous pipeline. Parallel scanning may be added only after
the sequential contract and ordering are covered by tests.

Gzip input uses the pure OCaml `decompress` implementation with compressed and
expanded byte limits. Regex search uses Jane Street's RE2 binding.

## Data flow

```text
CLI request
   |
   v
Scope resolver -------- explicit path / Info name / merged directory
   |
   +--> Dir loader --> Catalog merge -------------------+
   |                                                    |
   +--> Manual loader --> decompression --> Info parser |
                                            |           |
                                            v           v
                                         Manual graph / Catalog
                                                    |
                                      query parse + typecheck
                                                    |
                                                evaluator
                                                    |
                                         text / JSON / JSONL
```

## Modules

```text
Diagnostic       stable codes, evidence, hints, and exit classification
Emacs_info       bounded emacsclient adapter for active Info-directory-list
Info_path        INFOPATH expansion, defaults, precedence, and explicit -d
Source           path/name resolution and source identity
Compression      transparent bounded decompression
Dir_parser       categories and entries from one directory file
Catalog          deterministic merge, deduplication, and registered manuals
Info_id          normalized manual/node/anchor identifiers
Info_parser      byte-oriented state machine for one logical manual
Manual           immutable parsed document and byte/line indexes
Graph            node/menu/navigation/xref edges and tree projection
Search           literal/regex matching, snippets, and global traversal
Query_ast        typed query representation
Query_parser     lexer and recursive-descent parser
Query_typecheck  selector and field compatibility before evaluation
Query_eval       pure transformations over typed values
Render_text      bounded agent-readable output
Render_json      versioned JSON and JSONL contracts
Engine           orchestration without terminal side effects
Cli              Command terms, stderr/stdout, and process exit status
```

Each public library module gets an `.mli`. Filesystem and process effects stay
in resolver/loader boundaries; parsing and evaluation accept immutable values
and remain straightforward to test.

## Core domain model

```text
Catalog
  sources       : Catalog_source.t list
  categories    : Category.t list
  entries       : Catalog_entry.t list
  manuals       : Manual_ref.t list
  diagnostics   : Diagnostic.t list

Manual
  id            : Manual_id.t
  source        : Source.t
  encoding      : string option
  preamble      : Byte_range.t option
  nodes         : Node.t array
  node_by_name  : Node_id.t -> Node.t Or_error.t
  anchors       : Anchor.t list
  diagnostics   : Diagnostic.t list

Node
  id/header     : node identity and Next/Prev/Up targets
  bytes/lines   : exact body ranges
  menus         : Menu_entry.t list
  xrefs         : Xref.t list
  indices       : Index_entry.t list
```

Persisted JSON schemas and future cache formats must live under explicit
`Stable.V1` modules. Internal parser types should not acquire stable-wire
guarantees by accident.

## Catalog search

Catalog search resolves only manuals registered by merged directory entries.
Each manual is parsed at most once per invocation. Search produces lightweight
references and snippets, never entire node bodies.

The internal sequence is complete and deterministically sorted. Renderers cap
visible items without changing `filter`, `map`, `.length`, or slicing
semantics. A future content-addressed cache may store pure parse results under
`XDG_CACHE_HOME/texiq`; cache keys include parser schema version and source
fingerprint.

## Parser recovery

The parser scans logical uncompressed bytes. Tag and indirect offsets are used
for fast location, then verified against node identity. Recovery proceeds:

1. exact offset;
2. bounded nearby scan;
3. full scan by Info separators;
4. typed diagnostic if identity or coverage remains inconsistent.

Directory and global-search modes continue past individual failures unless
`--strict` is active. Counts must always satisfy the documented coverage
invariants.

## Safety boundaries

- Read-only in v1.
- No network access.
- No automatic traversal of external-manual xrefs.
- Emacs integration is explicit, read-only, bounded by the client timeout, and
  never evaluates project- or user-provided Lisp.
- Decompression and snippet sizes are bounded.
- Symlinks and duplicate source directories are normalized explicitly.
- Errors include source identity without dumping arbitrary manual content.
