open! Core

module Value : sig
  type t =
    | Null
    | Bool of bool
    | Int of int
    | String of string
    | Object of (string * t) list
    | List of t list
  [@@deriving sexp_of, compare, equal]

  val field : t -> string -> (t, string) Result.t
  val to_yojson : t -> Yojson.Safe.t
end

type selector =
  current:Value.t -> name:string -> args:Value.t list -> (Value.t, string) Result.t

val run
  :  selector:selector
  -> initial:Value.t
  -> Query_ast.t
  -> (Value.t, string) Result.t
