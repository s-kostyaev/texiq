open! Core

module Source : sig
  type t =
    { path : string
    ; precedence_rank : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Entry : sig
  type t = Dir_parser.Entry.t [@@deriving compare, equal, sexp_of]
end

module Category : sig
  type t =
    { name : string
    ; provenance : Dir_parser.Provenance.t
    ; entries : Entry.t list
    }
  [@@deriving compare, equal, sexp_of]
end

module Manual_ref : sig
  type t =
    { name : string
    ; source_path : string
    ; precedence_rank : int
    }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { sources : Source.t list
  ; categories : Category.t list
  ; entries : Entry.t list
  ; manuals : Manual_ref.t list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

val empty : t
val merge : Dir_parser.t list -> t
