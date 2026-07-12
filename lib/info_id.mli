open! Core

module Manual : sig
  type t = private string [@@deriving compare, equal, sexp_of]

  val of_string : string -> t Or_error.t
  val of_string_exn : string -> t
  val to_string : t -> string
  val normalized : t -> string
end

module Node : sig
  type t = private string [@@deriving compare, equal, sexp_of]

  val of_string : string -> t Or_error.t
  val of_string_exn : string -> t
  val to_string : t -> string
end

module Target : sig
  type t =
    { manual : Manual.t option
    ; node : Node.t
    }
  [@@deriving compare, equal, sexp_of]

  val of_string : string -> t Or_error.t
  val to_string : t -> string
end
