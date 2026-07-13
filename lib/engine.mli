open! Core

type request =
  { scope : string option
  ; query : string option
  ; directories : string list
  ; emacs : bool
  ; strict : bool
  ; format : Render.format
  ; raw_output : bool
  ; max_results : int option
  }
[@@deriving sexp_of]

type outcome =
  { stdout : string option
  ; stderr : string list
  ; exit_status : int
  }
[@@deriving sexp_of]

val execute : request -> outcome
