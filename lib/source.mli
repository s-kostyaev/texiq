open! Core

module Part : sig
  type t =
    { path : string
    ; contents : string
    ; logical_offset : int
    }
  [@@deriving sexp_of]
end

type t =
  { manual : Info_id.Manual.t
  ; main_path : string
  ; parts : Part.t list
  }
[@@deriving sexp_of]

type error =
  | Not_found of
      { requested : string
      ; searched : string list
      }
  | Compression_error of Compression.error
  | Invalid_indirect_entry of
      { path : string
      ; line : string
      }
  | Too_many_indirect_parts of
      { path : string
      ; count : int
      ; max_parts : int
      }
[@@deriving sexp_of]

val resolve_path : directories:string list -> string -> (string, error) Result.t
val load : ?max_bytes:int -> directories:string list -> string -> (t, error) Result.t
val manual : t -> Info_id.Manual.t
val main_path : t -> string
val parts : t -> Part.t list
