(lang dune 3.17)
(name texiq)
(version 1.0.0)

(package
 (name texiq)
 (synopsis "Agent-first query CLI for GNU Info manuals")
 (description
  "A deterministic, structure-first CLI for querying Info catalogs, manuals, nodes, menus, indices, and cross-references.")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.17))
  core
  core_unix
  (decompress (>= 1.5.3))
  ppx_jane
  ppx_expect
  re2
  yojson))

(formatting
 (enabled_for ocaml dune))

(cram enable)
