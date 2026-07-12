open! Core

module Source = struct
  type t =
    { path : string
    ; precedence_rank : int
    }
  [@@deriving compare, equal, sexp_of]
end

module Entry = struct
  type t = Dir_parser.Entry.t [@@deriving compare, equal, sexp_of]
end

module Category = struct
  type t =
    { name : string
    ; provenance : Dir_parser.Provenance.t
    ; entries : Entry.t list
    }
  [@@deriving compare, equal, sexp_of]
end

module Manual_ref = struct
  type t =
    { name : string
    ; source_path : string
    ; precedence_rank : int
    }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { sources : Source.t list
  ; categories : Category.t list
  ; entries : Entry.t list
  ; manuals : Manual_ref.t list
  ; diagnostics : Diagnostic.t list
  }
[@@deriving compare, equal, sexp_of]

let empty =
  { sources = []; categories = []; entries = []; manuals = []; diagnostics = [] }
;;

let entry_key (entry : Entry.t) = entry.category, entry.label, entry.manual, entry.node

let compare_parsed (left : Dir_parser.t) (right : Dir_parser.t) =
  match Int.compare left.precedence_rank right.precedence_rank with
  | 0 -> String.compare left.source_path right.source_path
  | value -> value
;;

let merge parsed_files =
  let parsed_files = List.sort parsed_files ~compare:compare_parsed in
  let seen_entries = Hash_set.Poly.create () in
  let category_order_rev = ref [] in
  let category_data = String.Table.create () in
  let entries_rev = ref [] in
  let diagnostics_rev = ref [] in
  let ensure_category (category : Dir_parser.Category.t) =
    let key = String.strip category.name in
    if not (Hashtbl.mem category_data key)
    then (
      category_order_rev := key :: !category_order_rev;
      Hashtbl.set category_data ~key ~data:(category.name, category.provenance, ref []))
  in
  List.iter parsed_files ~f:(fun parsed ->
    List.iter parsed.categories ~f:ensure_category;
    diagnostics_rev := List.rev_append parsed.diagnostics !diagnostics_rev;
    List.iter parsed.entries ~f:(fun entry ->
      let category_key = String.strip entry.category in
      if not (Hashtbl.mem category_data category_key)
      then
        ensure_category
          { Dir_parser.Category.name = entry.category; provenance = entry.provenance };
      let canonical_category_name, _, _ = Hashtbl.find_exn category_data category_key in
      let entry = { entry with category = canonical_category_name } in
      if Hash_set.mem seen_entries (entry_key entry)
      then ()
      else (
        Hash_set.add seen_entries (entry_key entry);
        entries_rev := entry :: !entries_rev;
        let _, _, category_entries_rev = Hashtbl.find_exn category_data category_key in
        category_entries_rev := entry :: !category_entries_rev)));
  let entries = List.rev !entries_rev in
  let categories =
    List.rev !category_order_rev
    |> List.map ~f:(fun key ->
      let name, provenance, category_entries_rev = Hashtbl.find_exn category_data key in
      { Category.name; provenance; entries = List.rev !category_entries_rev })
  in
  let seen_manuals = String.Hash_set.create () in
  let manuals =
    List.filter_map entries ~f:(fun entry ->
      let key = entry.manual in
      if Hash_set.mem seen_manuals key
      then None
      else (
        Hash_set.add seen_manuals key;
        Some
          { Manual_ref.name = entry.manual
          ; source_path = entry.provenance.source_path
          ; precedence_rank = entry.provenance.precedence_rank
          }))
  in
  let sources =
    List.map parsed_files ~f:(fun parsed ->
      { Source.path = parsed.source_path; precedence_rank = parsed.precedence_rank })
    |> List.stable_dedup ~compare:Source.compare
  in
  { sources; categories; entries; manuals; diagnostics = List.rev !diagnostics_rev }
;;

let%expect_test "merge preserves case-distinct categories and cross-category entries" =
  let first =
    Dir_parser.parse_string
      ~source_path:"/first/dir"
      ~precedence_rank:0
      "* Menu:\n\nDevelopment\n* Compiler: (compiler)Top. First.\n"
  in
  let second =
    Dir_parser.parse_string
      ~source_path:"/second/dir"
      ~precedence_rank:1
      "* Menu:\n\n\
       development\n\
       * Compiler: (compiler)Top. Duplicate.\n\
       * Debugger: (debugger)Top. Debug.\n\n\
       Utilities\n\
       * Shell: (shell). Shell.\n"
  in
  let catalog = merge [ second; first ] in
  print_s
    [%sexp
      (List.map catalog.categories ~f:(fun category ->
         category.name, List.map category.entries ~f:(fun entry -> entry.label))
       : (string * string list) list)];
  print_s [%sexp (List.map catalog.manuals ~f:(fun manual -> manual.name) : string list)];
  [%expect
    {|
    ((Development (Compiler)) (development (Compiler Debugger))
     (Utilities (Shell)))
    (compiler debugger shell)
    |}]
;;

let%expect_test "entry deduplication is exact" =
  let parsed =
    Dir_parser.parse_string
      ~source_path:"/dir"
      ~precedence_rank:0
      "* Menu:\n\nTools\n* Tool: (Manual)Top. Upper.\n* tool: (manual)top. Lower.\n"
  in
  let catalog = merge [ parsed ] in
  print_s
    [%sexp
      (List.map catalog.entries ~f:(fun entry -> entry.label, entry.manual, entry.node)
       : (string * string * string) list)];
  [%expect {| ((Tool Manual Top) (tool manual top)) |}]
;;
