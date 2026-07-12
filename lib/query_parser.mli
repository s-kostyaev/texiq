open! Core

type error =
  { position : int
  ; message : string
  ; hint : string option
  }
[@@deriving sexp_of]

val parse : string -> (Query_ast.t, error) Result.t
val render_error : error -> string
