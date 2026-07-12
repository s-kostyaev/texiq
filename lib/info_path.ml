open! Core

type entry =
  { directory : string
  ; precedence_rank : int
  }
[@@deriving compare, equal, sexp_of]

type t = entry list [@@deriving compare, equal, sexp_of]

let default_directories =
  [ "/usr/local/share/info"
  ; "/usr/local/info"
  ; "/opt/homebrew/share/info"
  ; "/opt/local/share/info"
  ; "/usr/share/info"
  ; "/usr/info"
  ]
  |> List.filter ~f:(fun path ->
    try Stdlib.Sys.file_exists path && Stdlib.Sys.is_directory path with
    | Sys_error _ -> false)
;;

let normalize_directory path =
  let path = String.strip path in
  if String.is_empty path
  then path
  else (
    let absolute = String.is_prefix path ~prefix:"/" in
    let parts =
      String.split path ~on:'/'
      |> List.fold ~init:[] ~f:(fun acc part ->
        match part with
        | "" | "." -> acc
        | ".." ->
          (match acc with
           | head :: tail when not (String.equal head "..") -> tail
           | _ when absolute -> acc
           | _ -> part :: acc)
        | part -> part :: acc)
      |> List.rev
    in
    let normalized = String.concat ~sep:"/" parts in
    let normalized =
      if absolute
      then "/" ^ normalized
      else if String.is_empty normalized
      then "."
      else normalized
    in
    try Filename_unix.realpath normalized with
    | _ -> normalized)
;;

let expand_environment ~environment ~defaults =
  match environment with
  | None -> defaults
  | Some value ->
    let components = String.split value ~on:':' in
    let final_index = List.length components - 1 in
    List.concat_mapi components ~f:(fun index component ->
      if not (String.is_empty component)
      then [ component ]
      else if Int.equal index final_index
      then defaults
      else [])
;;

let effective ~explicit ~environment ?(defaults = default_directories) () =
  explicit @ expand_environment ~environment ~defaults
  |> List.map ~f:normalize_directory
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.stable_dedup ~compare:String.compare
  |> List.mapi ~f:(fun precedence_rank directory -> { directory; precedence_rank })
;;

let directories t = List.map t ~f:(fun entry -> entry.directory)
let dir_file_basenames = [ "dir"; "DIR"; "dir.info"; "DIR.INFO"; "dir.gz" ]

type discovery =
  { files : (entry * string) list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

let is_directory path =
  try Stdlib.Sys.is_directory path with
  | Sys_error _ -> false
;;

let discover_dir_files t =
  let files_rev, diagnostics_rev =
    List.fold t ~init:([], []) ~f:(fun (files_rev, diagnostics_rev) entry ->
      if not (Stdlib.Sys.file_exists entry.directory && is_directory entry.directory)
      then
        ( files_rev
        , Diagnostic.create
            ~code:Directory_not_found
            ~severity:Warning
            ~exit_class:Resolution
            ~message:"Info search directory does not exist or is not readable"
            ~source:entry.directory
            ~hint:
              "Remove the directory from INFOPATH or pass an existing path with \
               --directory."
            ()
          :: diagnostics_rev )
      else (
        match
          List.find_map dir_file_basenames ~f:(fun basename ->
            let path = Filename.concat entry.directory basename in
            if Stdlib.Sys.file_exists path && not (is_directory path)
            then Some path
            else None)
        with
        | Some path -> (entry, path) :: files_rev, diagnostics_rev
        | None ->
          ( files_rev
          , Diagnostic.create
              ~code:Dir_file_not_found
              ~severity:Warning
              ~exit_class:Resolution
              ~message:"Info search directory contains no supported directory file"
              ~source:entry.directory
              ~hint:"Expected dir, DIR, dir.info, DIR.INFO, or dir.gz."
              ()
            :: diagnostics_rev )))
  in
  { files = List.rev files_rev; diagnostics = List.rev diagnostics_rev }
;;

let locate_dir_files t = (discover_dir_files t).files

let%expect_test "INFOPATH expansion, normalization, and precedence" =
  let path =
    effective
      ~explicit:[ "./local/info"; "/usr/share/info" ]
      ~environment:(Some ":/opt/info::/usr/share/info:/opt/../opt/info:")
      ~defaults:[ "/default/info" ]
      ()
  in
  print_s [%sexp (path : t)];
  [%expect
    {|
    (((directory local/info) (precedence_rank 0))
     ((directory /usr/share/info) (precedence_rank 1))
     ((directory /opt/info) (precedence_rank 2))
     ((directory /default/info) (precedence_rank 3)))
    |}]
;;
