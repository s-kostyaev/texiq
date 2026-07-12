---
name: texiq
description: Query installed GNU Info manuals with the texiq CLI using deterministic, structure-first, bounded-output workflows. Use when an agent needs to discover relevant manuals from the merged Info top directory, search manual contents, inspect nodes, menus, indices, anchors, or cross-references, and extract only the smallest relevant node text instead of loading an entire Info manual.
---

# Query GNU Info Manuals with `texiq`

Use `texiq` as a local read-only retrieval layer. Keep Info structure outside the
agent context until it is needed.

```text
(dir)Top -> manual -> node/search match -> minimal text -> answer
```

## Follow the Retrieval Loop

1. Discover the catalog or a known manual's structure.
2. Narrow with metadata, node names, or bounded search results.
3. Extract `.text` only from the smallest relevant node.
4. Preserve the manual and node name when reporting evidence.

Start from the cheapest useful surface:

```bash
# Unknown manual: inspect catalog metadata first
texiq dir '.entries | filter(contains(.description, "debugger"))'

# Cross-manual content search only when metadata is insufficient
texiq dir '.search("remote debugging")[0:10]'

# Known manual: inspect structure or search inside it
texiq texinfo '.tree(2)'
texiq texinfo '.search("indirect table")[0:10]'
texiq texinfo '.nodes | filter(contains(.name, "Format")) | map(.name)'

# Extract only after choosing a node
texiq --raw-output texinfo '.node("Info Format Indirect Table") | .text'
```

## Control Context Growth

1. Run `.length` before consuming a potentially large root collection.
2. Slice selectors before mapping or rendering: `.search("term")[0:10]`.
3. Project fields with `map(...)` instead of returning full objects.
4. Keep the default `--max-results 50`; lower it for exploratory calls.
5. Use `--all-results` only when the complete collection is required by the
   task, never merely for convenience.
6. Prefer catalog `.entries` for cheap metadata discovery. Catalog `.search`
   scans every resolvable registered manual and is intentionally more costly.

Useful bounded probes:

```bash
texiq dir '.manuals | .length'
texiq dir '.manuals[0:20] | map(.name)'
texiq bash '.search("parameter expansion") | .length'
texiq bash '.search("parameter expansion")[0:5]'
```

## Choose Output for the Consumer

- Use default text for human-readable inspection.
- Use `--format json` for one typed, versioned response envelope.
- Use `--format jsonl` for a versioned result stream.
- Use `--raw-output` only with text format and a scalar string such as `.text`.
- Use explicit repeated `-d DIR` flags when reproducible Info-path precedence
  matters.

For automation, parse structured fields rather than scraping text rendering:

```bash
texiq --format json texinfo '.search("tag table")[0:5]'
```

## Apply Search Semantics Deliberately

- Treat `.node("Name")` as exact and case-sensitive.
- Treat literal `.search("term")` as case-insensitive containment.
- Use RE2 syntax for regex queries: `.search("/garbage collect(or|ion)/i")`.
- Quote the whole query at the shell boundary.
- Keep identical queries unchanged across verification retries.

## Recover from Errors

1. On `E_NODE_NOT_FOUND`, list node names or search the manual, then retry with
   the exact returned name.
2. On `E_QUERY_PARSE` or `E_QUERY_TYPECHECK`, follow the reported stage and
   hint; change only the invalid expression.
3. On `E_MANUAL_RESOLVE`, inspect `texiq dir '.manuals | map(.name)'`, verify
   `INFOPATH`, or pass `-d DIR`.
4. On exit `2`, fix the path, permissions, compression, or resolution problem.
5. On exit `3`, treat the manual as structurally incomplete. Use best-effort
   mode only when partial coverage is acceptable; use `--strict` when complete
   parsing is required.

Do not silently replace a failed exact node lookup with a whole-manual dump.

## Read the Reference When Needed

Read [references/query-reference.md](references/query-reference.md) before
composing advanced pipelines, selecting entity fields, interpreting structured
output, or handling nontrivial diagnostics. Do not load it for the basic
discover-narrow-extract loop above.
