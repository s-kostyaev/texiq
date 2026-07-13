# `texiq` Query Reference

## Contents

- [Invocation and scopes](#invocation-and-scopes)
- [Selectors](#selectors)
- [Pipeline expressions](#pipeline-expressions)
- [Common fields](#common-fields)
- [Search and output](#search-and-output)
- [Diagnostics and exit status](#diagnostics-and-exit-status)
- [Recipes](#recipes)

## Invocation and Scopes

```text
texiq [OPTIONS] [SCOPE] [QUERY]
```

- Omit `SCOPE`, or use `dir` or `(dir)Top`, for the merged Info catalog.
- Use an Info manual id such as `bash` or `texinfo` for a manual.
- Use an explicit main-file path for a manual outside the effective Info path.

Options:

```text
-d, --directory DIR       prepend an Info search directory; repeatable
--strict                  fail when parse coverage is incomplete
--format text|json|jsonl  choose the renderer
--raw-output              emit a scalar text string without framing
--max-results N           cap a rendered root collection; default 50
--all-results             disable the root collection cap
--emacs                   prepend active Emacs Info-directory-list
```

Precedence is repeated `-d` directories, then active Emacs directories when
`--emacs` is present, then `INFOPATH`. A trailing separator in `INFOPATH`
appends platform defaults.

## Selectors

Catalog root:

```text
.summary
.tree([max_depth])
.categories
.entries
.manuals
.search(pattern)
```

Manual root:

```text
.summary
.tree([max_depth])
.nodes
.node(name)
.search(pattern)
.menus
.xrefs
.indices
.anchors
```

Node or node collection:

```text
.menus
.xrefs
.indices
.anchors
.text
```

Generic values:

```text
.field
.length
[index]
[start:end]
```

Root selectors such as `.nodes`, `.node`, and `.search` cannot be applied after
an unrelated pipeline value. Select the root collection first, then use
`filter`, `map`, fields, or postfix operations.

## Pipeline Expressions

```text
QUERY := STAGE ("|" STAGE)*
```

Supported collection stages:

```text
filter(PREDICATE)
map(EXPR)
```

Supported expression values and operators:

```text
strings, integers, booleans, null
== != < <= > >=
and or
contains(string, substring)
startswith(string, prefix)
endswith(string, suffix)
```

Examples:

```bash
texiq dir '.entries | filter(.category == "Programming") | map(.manual)'
texiq dir '.entries | filter(contains(.description, "compiler")) | map(.manual)'
texiq texinfo '.nodes | filter(startswith(.name, "Info")) | map(.name)'
texiq texinfo '.nodes[0:10] | map(.name)'
```

Postfix slicing belongs to a selector stage. Prefer
`.search("term")[0:10] | map(.node)` over attempting to slice after `map(...)`.

## Common Fields

Catalog entry:

```text
label manual node description category source_path precedence_rank line
```

Manual reference:

```text
name source_path precedence_rank
```

Node:

```text
manual name next prev up start_byte end_byte start_line end_line source_path
```

Search match:

```text
manual node source_path byte line column match snippet
```

Menu entry:

```text
label target description start_line end_line
```

Cross-reference:

```text
label target start_line end_line
```

Index entry:

```text
term target description start_line end_line
```

Anchor:

```text
name byte line
```

## Search and Output

Literal search is case-insensitive. Regex search uses slash delimiters and the
optional `i` flag:

```bash
texiq bash '.search("parameter expansion")[0:5]'
texiq bash '.search("/parameter[ -]expansion/i")[0:5]'
```

Catalog search scans the full text of registered, resolvable manuals. Results
are deterministic and include provenance and coordinates. Prefer `.entries`
when names and descriptions are enough.

JSON uses an envelope:

```json
{"schema_version":1,"data":[]}
```

When a root collection is capped, JSON adds `matched_total`, `returned`, and
`truncated`. JSONL emits versioned data lines and a final metadata line when
truncated. Nested typed collections are not mutated with sentinel objects.

## Diagnostics and Exit Status

```text
0  success, including an empty result
1  query or usage error
2  resolution, I/O, permission, compression, or loader limit error
3  parse or integrity coverage error
```

Diagnostics include a stable code and repair hint. Warnings in best-effort mode
mean the result may have incomplete coverage; `--strict` promotes incomplete
coverage to failure.

## Recipes

Discover candidate manuals without scanning their contents:

```bash
texiq dir '.entries | filter(contains(.description, "regular expression"))'
```

Search all registered manuals and retain evidence coordinates:

```bash
texiq --format json dir '.search("remote debugging")[0:10]'
```

Inspect a manual graph before extracting text:

```bash
texiq bash '.tree(2)'
texiq bash '.nodes | filter(contains(.name, "Expansion")) | map(.name)'
```

Inspect structural entities for one node:

```bash
texiq texinfo '.node("Info Format Specification") | .menus'
texiq texinfo '.node("Info Format Specification") | .xrefs'
```

Extract exact text for downstream reasoning:

```bash
texiq --raw-output texinfo '.node("Info Format Specification") | .text'
```
