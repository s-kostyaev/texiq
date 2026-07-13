# Agent playbook

Use a stable discover, narrow, extract loop. Do not begin by dumping a whole
manual.

## Discover from `(dir)Top`

If a manual is registered only in the active Emacs session, include its Info
directories explicitly:

```sh
texiq --emacs dir '.entries | filter(.manual == "ellama")'
texiq --emacs ellama '.nodes | map(.name)'
```

`--emacs` requires a reachable Emacs server. For reproducible automation that
does not depend on an editor session, continue to prefer explicit `-d` paths.

```sh
texiq
texiq dir '.categories | map(.name)'
texiq dir '.entries | filter(contains(.description, "debugger"))'
texiq dir '.search("remote debugging")[:10]'
```

`.entries` searches catalog metadata cheaply. `.search` from `dir` scans node
bodies in each resolvable registered manual and returns bounded snippets.

## Narrow to a manual

```sh
texiq texinfo '.tree(2)'
texiq texinfo '.search("indirect table")[:10]'
texiq texinfo '.nodes | filter(contains(.name, "Format")) | map(.name)'
```

## Extract exact text

```sh
texiq texinfo '.node("Info Format Indirect Table") | .text'
texiq --raw-output texinfo '.node("Info Format Indirect Table") | .text'
```

Use `--format json` for typed automation and `--format jsonl` for result
streams. The default renderer caps visible collections at 50 items and reports
when it truncates. Use slicing before `--all-results` whenever possible.

## Recovery

| Signal | Meaning | Next action |
| --- | --- | --- |
| `E_QUERY_PARSE` | malformed query | use the byte position and supplied grammar hint |
| `E_QUERY_TYPE` | selector/expression received the wrong value kind | inspect the previous stage or remove it |
| `E_NODE_NOT_FOUND` | exact node lookup missed | run `.search("term")` or `.nodes | map(.name)` |
| `E_MANUAL_RESOLVE` | manual/path was not found | inspect `texiq dir '.manuals'`, pass `-d DIR`, or use `--emacs` for an Emacs-only manual |
| `E_EMACS_INFO` | `emacsclient` could not provide active directories | start the server or use explicit `-d DIR` paths |
| exit `3` | strict parse coverage failure | narrow scope or repair the named manual |

For reproducible automation, pass explicit `-d` directories and reuse the same
query string. Results are sorted by source precedence and byte position.
