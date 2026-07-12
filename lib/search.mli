open! Core

module Pattern : sig
  type t =
    | Literal of string
    | Regex of
        { source : string
        ; case_sensitive : bool
        }
  [@@deriving compare, equal, sexp_of]

  val of_query_string : string -> (t, string) Result.t
end

module Match : sig
  type t =
    { manual : Info_id.Manual.t
    ; node : Info_id.Node.t
    ; source_path : string
    ; byte : int
    ; line : int
    ; column : int
    ; matched : string
    ; snippet : string
    }
  [@@deriving compare, equal, sexp_of]
end

type error = Invalid_regex of string [@@deriving sexp_of]

val validate : Pattern.t -> (unit, error) Result.t

val manual
  :  ?snippet_radius:int
  -> Manual.t
  -> Pattern.t
  -> (Match.t list, error) Result.t
