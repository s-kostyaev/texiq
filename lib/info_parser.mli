open! Core

type error =
  | No_nodes of { source_path : string }
  | Invalid_manual_id of Error.t
[@@deriving sexp_of]

val parse : Source.t -> (Manual.t, error) Result.t
