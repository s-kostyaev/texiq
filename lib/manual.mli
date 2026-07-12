open! Core

module Byte_range : sig
  type t =
    { start : int
    ; end_ : int
    }
  [@@deriving compare, equal, sexp_of]

  val length : t -> int
end

module Line_range : sig
  type t =
    { start : int
    ; end_ : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Menu_entry : sig
  type t =
    { label : string
    ; target : Info_id.Target.t
    ; description : string
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Xref : sig
  type t =
    { label : string
    ; target : Info_id.Target.t
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Index_entry : sig
  type t =
    { term : string
    ; target : Info_id.Target.t
    ; description : string
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Anchor : sig
  type t =
    { name : string
    ; bytes : Byte_range.t
    ; line : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Header : sig
  type t =
    { file : string option
    ; node : Info_id.Node.t
    ; next : Info_id.Target.t option
    ; prev : Info_id.Target.t option
    ; up : Info_id.Target.t option
    }
  [@@deriving compare, equal, sexp_of]
end

module Node : sig
  type t =
    { header : Header.t
    ; source_path : string
    ; bytes : Byte_range.t
    ; body_bytes : Byte_range.t
    ; lines : Line_range.t
    ; body : string
    ; body_raw_offsets : int array
    ; menus : Menu_entry.t list
    ; xrefs : Xref.t list
    ; indices : Index_entry.t list
    ; anchors : Anchor.t list
    }
  [@@deriving compare, equal, sexp_of]

  val name : t -> Info_id.Node.t
end

module Diagnostic : sig
  type t =
    | Malformed_header of
        { source_path : string
        ; byte : int
        ; header : string
        }
    | Malformed_entity of
        { source_path : string
        ; byte : int
        ; entity : string
        }
    | Duplicate_node of { name : Info_id.Node.t }
    | Offset_mismatch of
        { source_path : string
        ; node : Info_id.Node.t
        ; expected : int
        ; actual : int
        }
    | Tagged_node_missing of
        { source_path : string
        ; node : Info_id.Node.t
        ; expected : int
        }
    | Tagged_ref_missing of
        { source_path : string
        ; name : string
        ; expected : int
        }
    | Ref_offset_mismatch of
        { source_path : string
        ; name : string
        ; expected : int
        ; actual : int
        }
    | Duplicate_tag_identifier of { name : string }
    | Unsupported_encoding of
        { source_path : string
        ; encoding : string
        }
  [@@deriving compare, equal, sexp_of]
end

type t [@@deriving sexp_of]

val create
  :  id:Info_id.Manual.t
  -> source:Source.t
  -> encoding:string option
  -> preamble:string option
  -> nodes:Node.t list
  -> diagnostics:Diagnostic.t list
  -> t

val id : t -> Info_id.Manual.t
val source : t -> Source.t
val encoding : t -> string option
val preamble : t -> string option
val nodes : t -> Node.t list
val diagnostics : t -> Diagnostic.t list
val node_by_name : t -> Info_id.Node.t -> Node.t Or_error.t
val top : t -> Node.t option
val anchors : t -> Anchor.t list
