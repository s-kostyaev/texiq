open! Core

type error =
  | Io_error of
      { path : string
      ; message : string
      }
  | Malformed_compression of
      { path : string
      ; message : string
      }
  | Limit_exceeded of
      { path : string
      ; max_bytes : int
      }
[@@deriving sexp_of]

val default_max_bytes : int
val read_file : ?max_bytes:int -> string -> (string, error) Result.t
