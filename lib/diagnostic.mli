open! Core

module Code : sig
  type t =
    | Invalid_info_path
    | Directory_not_found
    | Dir_file_not_found
    | Dir_parse_error
    | Dir_entry_malformed
    | Duplicate_dir_entry
  [@@deriving compare, equal, sexp_of]

  val to_string : t -> string
end

module Severity : sig
  type t =
    | Warning
    | Error
  [@@deriving compare, equal, sexp_of]
end

module Exit_class : sig
  type t =
    | Usage
    | Resolution
    | Parse
  [@@deriving compare, equal, sexp_of]

  val status : t -> int
end

type t [@@deriving compare, equal, sexp_of]

val create
  :  code:Code.t
  -> severity:Severity.t
  -> exit_class:Exit_class.t
  -> message:string
  -> ?source:string
  -> ?line:int
  -> hint:string
  -> unit
  -> t

val code : t -> Code.t
val severity : t -> Severity.t
val exit_class : t -> Exit_class.t
val message : t -> string
val source : t -> string option
val line : t -> int option
val hint : t -> string
val render : t -> string
