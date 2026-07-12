open! Core

module Byte_range = struct
  type t =
    { start : int
    ; end_ : int
    }
  [@@deriving compare, equal, sexp_of]

  let length t = t.end_ - t.start
end

module Line_range = struct
  type t =
    { start : int
    ; end_ : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Menu_entry = struct
  type t =
    { label : string
    ; target : Info_id.Target.t
    ; description : string
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Xref = struct
  type t =
    { label : string
    ; target : Info_id.Target.t
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Index_entry = struct
  type t =
    { term : string
    ; target : Info_id.Target.t
    ; description : string
    ; bytes : Byte_range.t
    ; lines : Line_range.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Anchor = struct
  type t =
    { name : string
    ; bytes : Byte_range.t
    ; line : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Header = struct
  type t =
    { file : string option
    ; node : Info_id.Node.t
    ; next : Info_id.Target.t option
    ; prev : Info_id.Target.t option
    ; up : Info_id.Target.t option
    }
  [@@deriving compare, equal, sexp_of]
end

module Node = struct
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

  let name t = t.header.node
end

module Diagnostic = struct
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

type t =
  { id : Info_id.Manual.t
  ; source : Source.t
  ; encoding : string option
  ; preamble : string option
  ; nodes : Node.t list
  ; diagnostics : Diagnostic.t list
  ; node_index : Node.t String.Map.t
  }
[@@deriving sexp_of]

let create ~id ~source ~encoding ~preamble ~nodes ~diagnostics =
  let node_index, duplicate_diagnostics =
    List.fold nodes ~init:(String.Map.empty, []) ~f:(fun (index, diagnostics) node ->
      let name = Info_id.Node.to_string (Node.name node) in
      if Map.mem index name
      then index, Diagnostic.Duplicate_node { name = Node.name node } :: diagnostics
      else Map.set index ~key:name ~data:node, diagnostics)
  in
  { id
  ; source
  ; encoding
  ; preamble
  ; nodes
  ; diagnostics = diagnostics @ List.rev duplicate_diagnostics
  ; node_index
  }
;;

let id t = t.id
let source t = t.source
let encoding t = t.encoding
let preamble t = t.preamble
let nodes t = t.nodes
let diagnostics t = t.diagnostics

let node_by_name t name =
  match Map.find t.node_index (Info_id.Node.to_string name) with
  | Some node -> Ok node
  | None ->
    Or_error.error_s
      [%message
        "Info node not found" (name : Info_id.Node.t) ~manual:(t.id : Info_id.Manual.t)]
;;

let top t = Option.first_some (Map.find t.node_index "Top") (List.hd t.nodes)
let anchors t = List.concat_map t.nodes ~f:(fun node -> node.anchors)
