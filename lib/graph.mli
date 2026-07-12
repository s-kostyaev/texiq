open! Core

module Tree : sig
  type t =
    { node : Manual.Node.t
    ; children : t list
    ; cycle : bool
    }
  [@@deriving sexp_of]
end

type t [@@deriving sexp_of]

val create : Manual.t -> t
val manual : t -> Manual.t
val children : t -> Manual.Node.t -> Manual.Node.t list
val tree : ?max_depth:int -> t -> Tree.t list
val unreachable : t -> Manual.Node.t list
