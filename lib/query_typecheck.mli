open! Core

type scope =
  | Catalog
  | Manual
[@@deriving sexp_of, compare, equal]

val check : scope:scope -> Query_ast.t -> (unit, string) Result.t
