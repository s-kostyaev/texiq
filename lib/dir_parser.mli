open! Core

module Provenance : sig
  type t =
    { source_path : string
    ; precedence_rank : int
    ; line : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Entry : sig
  type t =
    { label : string
    ; manual : string
    ; node : string
    ; description : string
    ; category : string
    ; provenance : Provenance.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Category : sig
  type t =
    { name : string
    ; provenance : Provenance.t
    }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { source_path : string
  ; precedence_rank : int
  ; categories : Category.t list
  ; entries : Entry.t list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

(** Parse the uncompressed contents of one Info directory file. Malformed menu
    entries are retained as diagnostics while later entries remain parseable. *)
val parse_string : source_path:string -> precedence_rank:int -> string -> t
