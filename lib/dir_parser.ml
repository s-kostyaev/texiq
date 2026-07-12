open! Core

module Provenance = struct
  type t =
    { source_path : string
    ; precedence_rank : int
    ; line : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Entry = struct
  type t =
    { label : string
    ; manual : string
    ; node : string
    ; description : string
    ; category : string
    ; provenance : Provenance.t
    }
  [@@deriving compare, equal, sexp_of]
end

module Category = struct
  type t =
    { name : string
    ; provenance : Provenance.t
    }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { source_path : string
  ; precedence_rank : int
  ; categories : Category.t list
  ; entries : Entry.t list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

type pending_entry =
  { label : string
  ; manual : string
  ; node : string
  ; description_parts_rev : string list
  ; category : string
  ; provenance : Provenance.t
  }

let split_once value ~on =
  match String.lsplit2 value ~on with
  | None -> None
  | Some (left, right) -> Some (String.strip left, String.strip right)
;;

let parse_target target =
  if not (String.is_prefix target ~prefix:"(")
  then None
  else (
    match String.index target ')' with
    | None -> None
    | Some close_index ->
      let manual = String.sub target ~pos:1 ~len:(close_index - 1) |> String.strip in
      let remainder = String.drop_prefix target (close_index + 1) |> String.strip in
      let rec find_terminator index =
        if index >= String.length remainder
        then None
        else if
          Char.equal remainder.[index] '.'
          && (index + 1 = String.length remainder
              || Char.is_whitespace remainder.[index + 1])
        then Some index
        else find_terminator (index + 1)
      in
      let node, description =
        match find_terminator 0 with
        | None -> remainder, ""
        | Some terminator ->
          ( String.prefix remainder terminator |> String.strip
          , String.drop_prefix remainder (terminator + 1) |> String.strip )
      in
      let node = if String.is_empty node then "Top" else node in
      if String.is_empty manual then None else Some (manual, node, description))
;;

let parse_menu_entry ~category ~provenance line =
  let payload = String.drop_prefix line 1 |> String.strip in
  match split_once payload ~on:':' with
  | None -> None
  | Some (label, target) ->
    Option.map (parse_target target) ~f:(fun (manual, node, description) ->
      { label
      ; manual
      ; node
      ; description_parts_rev =
          (if String.is_empty description then [] else [ description ])
      ; category
      ; provenance
      })
;;

let finish_entry pending entries_rev =
  match pending with
  | None -> entries_rev
  | Some pending ->
    let description =
      pending.description_parts_rev
      |> List.rev
      |> List.filter ~f:(Fn.non String.is_empty)
      |> String.concat ~sep:" "
    in
    { Entry.label = pending.label
    ; manual = pending.manual
    ; node = pending.node
    ; description
    ; category = pending.category
    ; provenance = pending.provenance
    }
    :: entries_rev
;;

let parse_string ~source_path ~precedence_rank contents =
  let lines = String.split_lines contents in
  let in_menu = ref false in
  let current_category = ref "Miscellaneous" in
  let categories_rev = ref [] in
  let entries_rev = ref [] in
  let diagnostics_rev = ref [] in
  let pending = ref None in
  let add_category ~line name =
    let name = String.strip name in
    if not (String.is_empty name)
    then (
      current_category := name;
      categories_rev
      := { Category.name; provenance = { source_path; precedence_rank; line } }
         :: !categories_rev)
  in
  let flush_pending () =
    entries_rev := finish_entry !pending !entries_rev;
    pending := None
  in
  List.iteri lines ~f:(fun index raw_line ->
    let line_number = index + 1 in
    let line = String.rstrip raw_line in
    if not !in_menu
    then (if String.equal (String.strip line) "* Menu:" then in_menu := true)
    else if String.is_prefix (String.lstrip line) ~prefix:"* "
    then (
      flush_pending ();
      let provenance = { Provenance.source_path; precedence_rank; line = line_number } in
      match
        parse_menu_entry ~category:!current_category ~provenance (String.lstrip line)
      with
      | Some value -> pending := Some value
      | None ->
        diagnostics_rev
        := Diagnostic.create
             ~code:Dir_entry_malformed
             ~severity:Warning
             ~exit_class:Parse
             ~message:"could not parse Info directory menu entry"
             ~source:source_path
             ~line:line_number
             ~hint:"Expected `* Label: (manual)Node. Description`."
             ()
           :: !diagnostics_rev)
    else if String.is_empty (String.strip line)
    then flush_pending ()
    else if Char.is_whitespace line.[0]
    then (
      match !pending with
      | None -> ()
      | Some value ->
        let part = String.strip line in
        pending
        := Some { value with description_parts_rev = part :: value.description_parts_rev })
    else (
      flush_pending ();
      add_category ~line:line_number line));
  flush_pending ();
  let categories = List.rev !categories_rev in
  let entries = List.rev !entries_rev in
  let categories =
    if
      (not
         (List.exists entries ~f:(fun entry ->
            String.Caseless.equal entry.category "Miscellaneous")))
      || List.exists categories ~f:(fun category ->
        String.Caseless.equal category.name "Miscellaneous")
    then categories
    else
      { Category.name = "Miscellaneous"
      ; provenance = { source_path; precedence_rank; line = 1 }
      }
      :: categories
  in
  { source_path
  ; precedence_rank
  ; categories
  ; entries
  ; diagnostics = List.rev !diagnostics_rev
  }
;;

let%expect_test "categories, entries, descriptions, and recovery" =
  let parsed =
    parse_string
      ~source_path:"/one/dir"
      ~precedence_rank:0
      "File: dir, Node: Top\n\n\
       * Menu:\n\n\
       Development\n\
       * Compiler: (compiler)Top. Compile things.\n\
      \  Continued description.\n\
       * Broken entry\n\n\
       Utilities\n\
       * Shell: (shell)Commands.Shell. A shell.\n"
  in
  print_s [%sexp (parsed.categories : Category.t list)];
  print_s [%sexp (parsed.entries : Entry.t list)];
  List.iter parsed.diagnostics ~f:(fun diagnostic ->
    print_endline (Diagnostic.render diagnostic));
  [%expect
    {|
    (((name Development)
      (provenance ((source_path /one/dir) (precedence_rank 0) (line 5))))
     ((name Utilities)
      (provenance ((source_path /one/dir) (precedence_rank 0) (line 10)))))
    (((label Compiler) (manual compiler) (node Top)
      (description "Compile things. Continued description.")
      (category Development)
      (provenance ((source_path /one/dir) (precedence_rank 0) (line 6))))
     ((label Shell) (manual shell) (node Commands.Shell) (description "A shell.")
      (category Utilities)
      (provenance ((source_path /one/dir) (precedence_rank 0) (line 11)))))
    Warning[W_DIR_ENTRY_MALFORMED] (/one/dir:8): could not parse Info directory menu entry
    Hint: Expected `* Label: (manual)Node. Description`.
    |}]
;;
