# Product requirements: texiq v1

Status: planned
License: MIT

## Summary

`texiq` is a local, read-only CLI for structure-first querying of GNU Info
manuals. It is designed primarily for tool-using LLM agents, while remaining
predictable and useful for humans and shell automation.

The canonical entry point is the merged Info directory `(dir)Top`. From there
an agent can discover manuals, search by text containment across registered
manuals, narrow to a manual and node, then extract only the required text.

## Goals

1. Compose the top-level catalog from all `dir` files in `INFOPATH`.
2. Resolve manuals by Info name or explicit filesystem path.
3. Parse nonsplit, split, and gzip-compressed Info manuals locally.
4. Preserve the native graph of nodes, menus, navigation pointers, indices,
   anchors, and cross-references.
5. Provide a small jq-inspired pipeline language with typed results.
6. Make output, ordering, diagnostics, and retries deterministic.
7. Bound default output so a global search cannot flood agent context.

## Non-goals for v1

1. Editing generated `.info` files or Texinfo source.
2. Parsing `.texi` source.
3. Network lookup of missing manuals or external references.
4. Semantic, embedding, or LLM-based search.
5. A mandatory persistent index.
6. Complete jq language compatibility.

## CLI contract

```text
texiq [OPTIONS] [SCOPE] [QUERY]
```

Scopes:

- no scope, `dir`, or `(dir)Top`: merged top-level catalog;
- an Info manual name such as `texinfo`;
- an explicit path to an Info main file.

Examples:

```sh
texiq
texiq dir '.tree'
texiq dir '.entries | filter(contains(.description, "debugger"))'
texiq dir '.search("remote debugging")'
texiq texinfo '.nodes | map(.name)'
texiq texinfo '.node("Info Format Specification") | .text'
```

Common options:

```text
-d, --directory DIR       prepend an Info search directory
--strict                  fail on incomplete parse coverage
--format text|json|jsonl  select renderer; default is text
--raw-output              emit scalar strings without framing
--max-results N           cap rendered collection items
--all-results             disable the rendering cap
```

No query renders a compact summary and the first discovery surface: catalog
categories and entries for `(dir)Top`, or the top-level menu for a manual.

## Query language

```text
QUERY     := STAGE ("|" STAGE)*
FUNCTION  := filter(PREDICATE) | map(EXPR)
POSTFIX   := [index] | [start:end] | .field
```

Catalog selectors:

```text
.summary .tree([max_depth]) .categories .entries .manuals .search(pattern)
```

Manual selectors:

```text
.summary .tree([max_depth]) .nodes .node(name) .search(pattern)
.menus .xrefs .indices .text .length
```

The initial v1 expression language supports field access, strings, integers,
booleans, comparisons, `and`, `or`, `contains`, `startswith`, and `endswith`.

`.node(name)` is exact and case-sensitive. Literal `.search(pattern)` is
case-insensitive. Slash-delimited regular expressions support explicit flags,
for example `.search("/garbage collect(or|ion)/i")`.

## Top directory semantics

The catalog is a virtual structure composed from `dir`, `DIR`, `dir.info`,
`DIR.INFO`, or compressed equivalents found along the effective Info path.

1. Search-directory precedence is preserved.
2. Categories with case-insensitively equal names are merged using the first
   spelling in precedence order.
3. Entries with the same `(label, manual, node)` are deduplicated.
4. Every category and entry retains its source path and precedence rank.
5. `.manuals` contains manuals registered by catalog entries; unregistered
   files are not silently added.

On a catalog, `.search(pattern)` performs full-text containment search across
registered manuals. Metadata-only discovery remains cheap and explicit through
`.entries | filter(...)`.

Global search results contain manual, node, line, column, match, bounded
snippet, and source path. Results sort by Info-path precedence, normalized
manual name, node byte position, line, and match offset.

The evaluator operates on the complete result stream. The renderer applies the
default output cap and reports `matched_total`, `returned`, and `truncated`.

## Info compatibility

The parser must support:

- Info node separators and headers;
- DEL-quoted node identifiers;
- menus, multiline descriptions, indices, anchors, and cross-references;
- tag tables and indirect tables;
- nonsplit and split manuals;
- encoding declared in local variables;
- gzip-compressed input.

Tag and indirect byte offsets are hints, not unquestioned truth. A mismatch
triggers a bounded nearby search followed by separator scanning and a stable
warning.

## Exit status

- `0`: success, including an empty result;
- `1`: query or usage error;
- `2`: resolution, I/O, permission, or decompression error;
- `3`: parse or integrity coverage error.

Diagnostics have a stable code, concise evidence, and a concrete repair hint.
