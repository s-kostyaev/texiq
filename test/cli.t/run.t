  $ texiq -version
  1.0.0

  $ texiq --help | sed -n '1p'
  Query GNU Info manuals without reading entire contents

  $ printf '\037\nFile: cli.info, Node: Top, Next: Child, Up: (dir)\nTop body.\n\037\nFile: cli.info, Node: Child, Prev: Top, Up: Top\nDeterministic child.\n' > cli.info

  $ texiq cli.info '.nodes | map(.name)'
  - Top
  - Child

  $ texiq cli.info '.nodes | map(.name)' > first
  $ texiq cli.info '.nodes | map(.name)' > second
  $ diff -u first second

  $ texiq --raw-output cli.info '.node("Child") | .text'
  Deterministic child.

  $ texiq --format json cli.info '.nodes | map(.name)'
  { "schema_version": 1, "data": [ "Top", "Child" ] }

  $ texiq --format jsonl cli.info '.nodes | map(.name)'
  {"schema_version":1,"data":"Top"}
  {"schema_version":1,"data":"Child"}

  $ texiq cli.info '.node("Missing") | .text' > missing.out 2>&1; test $? = 1
  $ grep -q '^Error\[E_NODE_NOT_FOUND\]:' missing.out
  $ grep -q '^Hint: run .search("Missing") or .nodes | map(.name)$' missing.out
