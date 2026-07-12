open! Core

module Code = struct
  type t =
    | Invalid_info_path
    | Directory_not_found
    | Dir_file_not_found
    | Dir_parse_error
    | Dir_entry_malformed
    | Duplicate_dir_entry
  [@@deriving compare, equal, sexp_of]

  let to_string = function
    | Invalid_info_path -> "E_INVALID_INFO_PATH"
    | Directory_not_found -> "E_DIRECTORY_NOT_FOUND"
    | Dir_file_not_found -> "E_DIR_FILE_NOT_FOUND"
    | Dir_parse_error -> "E_DIR_PARSE_ERROR"
    | Dir_entry_malformed -> "W_DIR_ENTRY_MALFORMED"
    | Duplicate_dir_entry -> "W_DUPLICATE_DIR_ENTRY"
  ;;
end

module Severity = struct
  type t =
    | Warning
    | Error
  [@@deriving compare, equal, sexp_of]
end

module Exit_class = struct
  type t =
    | Usage
    | Resolution
    | Parse
  [@@deriving compare, equal, sexp_of]

  let status = function
    | Usage -> 1
    | Resolution -> 2
    | Parse -> 3
  ;;
end

type t =
  { code : Code.t
  ; severity : Severity.t
  ; exit_class : Exit_class.t
  ; message : string
  ; source : string option
  ; line : int option
  ; hint : string
  }
[@@deriving compare, equal, fields ~getters, sexp_of]

let create ~code ~severity ~exit_class ~message ?source ?line ~hint () =
  { code; severity; exit_class; message; source; line; hint }
;;

let render t =
  let level =
    match t.severity with
    | Warning -> "Warning"
    | Error -> "Error"
  in
  let location =
    match t.source, t.line with
    | None, None -> ""
    | Some source, None -> " (" ^ source ^ ")"
    | None, Some line -> sprintf " (line %d)" line
    | Some source, Some line -> sprintf " (%s:%d)" source line
  in
  sprintf "%s[%s]%s: %s\nHint: %s" level (Code.to_string t.code) location t.message t.hint
;;
