  $ texiq -version
  1.1.0

  $ texiq --help | sed -n '1p'
  Query GNU Info manuals without reading entire contents

  $ texiq --help | grep -- '--emacs'
    [--emacs]                  . Prepend the active Emacs Info-directory-list via

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

  $ mkdir emacs-info fake-bin
  $ printf 'File: dir, Node: Top\n\n* Menu:\n\nTests\n* Ellama: (ellama). Demo.\n' > emacs-info/dir
  $ printf '\037\nFile: ellama.info, Node: Top, Up: (dir)\nFrom active Emacs.\n' > emacs-info/ellama.info
  $ printf '%s\n' '#!/bin/sh' 'hex=$(printf "%s" "$FAKE_EMACS_INFO" | od -An -tx1 | tr -d "[:space:]")' 'printf "\"%s\"\n" "$hex"' > fake-bin/emacsclient
  $ chmod +x fake-bin/emacsclient

  $ FAKE_EMACS_INFO="$PWD/emacs-info" PATH="$PWD/fake-bin:$PATH" texiq --emacs ellama '.nodes | .length'
  1

  $ mkdir explicit-info
  $ printf '\037\nFile: ellama.info, Node: Top, Next: Child, Up: (dir)\nExplicit.\n\037\nFile: ellama.info, Node: Child, Prev: Top, Up: Top\nExplicit child.\n' > explicit-info/ellama.info
  $ FAKE_EMACS_INFO="$PWD/emacs-info" PATH="$PWD/fake-bin:$PATH" texiq -d explicit-info --emacs ellama '.nodes | .length'
  2

  $ printf '%s\n' '#!/bin/sh' 'echo "no Emacs server" >&2' 'exit 7' > fake-bin/emacsclient
  $ FAKE_EMACS_INFO="$PWD/emacs-info" PATH="$PWD/fake-bin:$PATH" texiq --emacs ellama > emacs-error.out 2>&1; test $? = 2
  $ grep -q '^Error\[E_EMACS_INFO\]:' emacs-error.out
  $ grep -q '^Hint: start an Emacs server' emacs-error.out
