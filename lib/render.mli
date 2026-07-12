open! Core

type format =
  | Text
  | Json
  | Jsonl
[@@deriving sexp_of, compare, equal]

val render
  :  format:format
  -> raw_output:bool
  -> max_results:int option
  -> Query_eval.Value.t
  -> string
