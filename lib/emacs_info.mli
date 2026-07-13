open! Core

type error =
  | Client_failed of
      { program : string
      ; status : string
      ; output : string
      }
  | Invalid_output of
      { output : string
      ; reason : string
      }
[@@deriving sexp_of]

(** Query a running Emacs through [emacsclient] and return its active
    [Info-directory-list] in Emacs precedence order. *)
val directories : ?program:string -> unit -> (string list, error) Result.t
