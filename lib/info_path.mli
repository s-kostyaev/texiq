open! Core

type entry =
  { directory : string
  ; precedence_rank : int
  }
[@@deriving compare, equal, sexp_of]

type t = entry list [@@deriving compare, equal, sexp_of]

val default_directories : string list

(** [effective] prepends command-line directories to [INFOPATH]. A trailing
    separator in [environment] appends [defaults]; other empty components are
    ignored. Duplicate normalized directories retain their first occurrence. *)
val effective
  :  explicit:string list
  -> environment:string option
  -> ?defaults:string list
  -> unit
  -> t

val directories : t -> string list
val dir_file_basenames : string list

type discovery =
  { files : (entry * string) list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

(** Discover directory files and report missing/unreadable search roots without
    aborting discovery of lower-precedence roots. *)
val discover_dir_files : t -> discovery

(** Return at most one directory file per search directory. Filename variant
    precedence follows [dir_file_basenames]. *)
val locate_dir_files : t -> (entry * string) list
