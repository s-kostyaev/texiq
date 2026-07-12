open! Core
module Value = Query_eval.Value
open Value

type request =
  { scope : string option
  ; query : string option
  ; directories : string list
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

let success ?stdout ?(stderr = []) () = { stdout; stderr; exit_status = 0 }
let failure ?(stderr = []) exit_status = { stdout = None; stderr; exit_status }
let target_value target = Value.String (Info_id.Target.to_string target)

let target_option = function
  | None -> Value.Null
  | Some target -> target_value target
;;

let provenance_fields (provenance : Dir_parser.Provenance.t) =
  [ "source_path", Value.String provenance.source_path
  ; "precedence_rank", Int provenance.precedence_rank
  ; "line", Int provenance.line
  ]
;;

let catalog_entry_value (entry : Catalog.Entry.t) =
  Value.Object
    ([ "kind", String "catalog_entry"
     ; "label", String entry.label
     ; "manual", String entry.manual
     ; "node", String entry.node
     ; "description", String entry.description
     ; "category", String entry.category
     ]
     @ provenance_fields entry.provenance)
;;

let catalog_category_value ?(include_entries = true) (category : Catalog.Category.t) =
  Value.Object
    ([ "kind", String "category"
     ; "name", String category.name
     ; ( "entries"
       , List
           (if include_entries
            then List.map category.entries ~f:catalog_entry_value
            else []) )
     ]
     @ provenance_fields category.provenance)
;;

let manual_ref_value (manual : Catalog.Manual_ref.t) =
  Value.Object
    [ "kind", String "manual_ref"
    ; "name", String manual.name
    ; "source_path", String manual.source_path
    ; "precedence_rank", Int manual.precedence_rank
    ]
;;

let node_value manual (node : Manual.Node.t) =
  Value.Object
    [ "kind", String "node"
    ; "manual", String (Info_id.Manual.to_string (Manual.id manual))
    ; "name", String (Info_id.Node.to_string (Manual.Node.name node))
    ; "next", target_option node.header.next
    ; "prev", target_option node.header.prev
    ; "up", target_option node.header.up
    ; "start_byte", Int node.bytes.start
    ; "end_byte", Int node.bytes.end_
    ; "start_line", Int node.lines.start
    ; "end_line", Int node.lines.end_
    ; "source_path", String node.source_path
    ]
;;

let menu_value (entry : Manual.Menu_entry.t) =
  Value.Object
    [ "kind", String "menu_entry"
    ; "label", String entry.label
    ; "target", target_value entry.target
    ; "description", String entry.description
    ; "start_line", Int entry.lines.start
    ; "end_line", Int entry.lines.end_
    ]
;;

let xref_value (xref : Manual.Xref.t) =
  Value.Object
    [ "kind", String "xref"
    ; "label", String xref.label
    ; "target", target_value xref.target
    ; "start_line", Int xref.lines.start
    ; "end_line", Int xref.lines.end_
    ]
;;

let index_value (entry : Manual.Index_entry.t) =
  Value.Object
    [ "kind", String "index_entry"
    ; "term", String entry.term
    ; "target", target_value entry.target
    ; "description", String entry.description
    ; "start_line", Int entry.lines.start
    ; "end_line", Int entry.lines.end_
    ]
;;

let anchor_value (anchor : Manual.Anchor.t) =
  Value.Object
    [ "kind", String "anchor"
    ; "name", String anchor.name
    ; "byte", Int anchor.bytes.start
    ; "line", Int anchor.line
    ]
;;

let search_value (match_ : Search.Match.t) =
  Value.Object
    [ "kind", String "search_match"
    ; "manual", String (Info_id.Manual.to_string match_.manual)
    ; "node", String (Info_id.Node.to_string match_.node)
    ; "source_path", String match_.source_path
    ; "byte", Int match_.byte
    ; "line", Int match_.line
    ; "column", Int match_.column
    ; "match", String match_.matched
    ; "snippet", String match_.snippet
    ]
;;

let tree_value manual trees =
  let rec value (tree : Graph.Tree.t) =
    match node_value manual tree.node with
    | Value.Object fields ->
      Value.Object
        (fields
         @ [ "cycle", Bool tree.cycle
           ; "children", List (List.map tree.children ~f:value)
           ])
    | _ -> assert false
  in
  Value.List (List.map trees ~f:value)
;;

let parse_single_string_argument name = function
  | [ Value.String value ] -> Ok value
  | _ -> Error (sprintf "Error[E_QUERY_ARGUMENT]: .%s expects one string argument" name)
;;

let parse_optional_depth name = function
  | [] -> Ok None
  | [ Value.Int value ] when value >= 0 -> Ok (Some value)
  | _ ->
    Error
      (sprintf
         "Error[E_QUERY_ARGUMENT]: .%s expects an optional non-negative integer"
         name)
;;

let current_kind = function
  | Value.Object fields ->
    (match List.Assoc.find fields ~equal:String.equal "kind" with
     | Some (Value.String kind) -> Some kind
     | _ -> None)
  | _ -> None
;;

let current_node_name = function
  | Value.Object fields ->
    (match List.Assoc.find fields ~equal:String.equal "name" with
     | Some (Value.String name) -> Some name
     | _ -> None)
  | _ -> None
;;

let nodes_for_current manual current =
  match current with
  | Value.List values ->
    List.map values ~f:current_node_name
    |> Option.all
    |> Option.bind ~f:(fun names ->
      List.map names ~f:(fun name ->
        Info_id.Node.of_string name |> Or_error.bind ~f:(Manual.node_by_name manual))
      |> Or_error.all
      |> Or_error.ok)
  | _ ->
    (match current_kind current, current_node_name current with
     | Some "node", Some name ->
       Info_id.Node.of_string name
       |> Or_error.bind ~f:(Manual.node_by_name manual)
       |> Or_error.ok
       |> Option.map ~f:List.return
     | _ -> None)
;;

let selected_nodes manual current =
  match nodes_for_current manual current with
  | Some nodes -> Ok nodes
  | None
    when Option.value_map (current_kind current) ~default:false ~f:(String.equal "manual")
    -> Ok (Manual.nodes manual)
  | None ->
    Error
      "Error[E_QUERY_SCOPE]: selector requires a manual, node, or node collection\n\
       Hint: start from .nodes or select one node with .node(\"Name\")"
;;

let manual_selector manual ~current ~name ~args =
  let all_nodes () = Manual.nodes manual in
  match name with
  | "summary" ->
    Ok
      (Value.Object
         [ "kind", String "manual_summary"
         ; "manual", String (Info_id.Manual.to_string (Manual.id manual))
         ; "source_path", String (Manual.source manual).main_path
         ; "nodes", Int (List.length (Manual.nodes manual))
         ; "diagnostics", Int (List.length (Manual.diagnostics manual))
         ])
  | "nodes" -> Ok (List (List.map (all_nodes ()) ~f:(node_value manual)))
  | "node" ->
    Result.bind (parse_single_string_argument name args) ~f:(fun node_name ->
      Info_id.Node.of_string node_name
      |> Or_error.bind ~f:(Manual.node_by_name manual)
      |> Result.map_error ~f:(fun error ->
        sprintf
          "Error[E_NODE_NOT_FOUND]: %s\nHint: run .search(%S) or .nodes | map(.name)"
          (Error.to_string_hum error)
          node_name)
      |> Result.map ~f:(node_value manual))
  | "tree" ->
    Result.map (parse_optional_depth name args) ~f:(fun max_depth ->
      Graph.create manual |> Graph.tree ?max_depth |> tree_value manual)
  | "menus" ->
    Result.map (selected_nodes manual current) ~f:(fun nodes ->
      Value.List
        (nodes |> List.concat_map ~f:(fun node -> node.menus) |> List.map ~f:menu_value))
  | "xrefs" ->
    Result.map (selected_nodes manual current) ~f:(fun nodes ->
      Value.List
        (nodes |> List.concat_map ~f:(fun node -> node.xrefs) |> List.map ~f:xref_value))
  | "indices" ->
    Result.map (selected_nodes manual current) ~f:(fun nodes ->
      Value.List
        (nodes |> List.concat_map ~f:(fun node -> node.indices) |> List.map ~f:index_value))
  | "anchors" ->
    Result.map (selected_nodes manual current) ~f:(fun nodes ->
      Value.List
        (nodes
         |> List.concat_map ~f:(fun node -> node.anchors)
         |> List.map ~f:anchor_value))
  | "text" ->
    (match nodes_for_current manual current with
     | Some [ node ] -> Ok (Value.String node.body)
     | Some nodes ->
       Ok (Value.List (List.map nodes ~f:(fun node -> Value.String node.body)))
     | None ->
       Error
         "Error[E_QUERY_SCOPE]: .text requires a node or node collection\n\
          Hint: use .node(\"Name\") | .text")
  | "search" ->
    Result.bind (parse_single_string_argument name args) ~f:(fun pattern ->
      Result.bind
        (Search.Pattern.of_query_string pattern
         |> Result.map_error ~f:(sprintf "Error[E_SEARCH_PATTERN]: %s"))
        ~f:(fun pattern ->
          Search.manual manual pattern
          |> Result.map_error ~f:(fun error ->
            sprintf
              "Error[E_SEARCH_PATTERN]: %s"
              (Sexp.to_string_hum ([%sexp_of: Search.error] error)))
          |> Result.map ~f:(fun matches -> Value.List (List.map matches ~f:search_value))))
  | _ -> Error (sprintf "Error[E_QUERY_SELECTOR]: unknown manual selector .%s" name)
;;

let load_catalog info_path =
  let discovery = Info_path.discover_dir_files info_path in
  let parsed, load_errors =
    List.fold discovery.files ~init:([], []) ~f:(fun (parsed, errors) (entry, path) ->
      match Compression.read_file path with
      | Ok contents ->
        ( Dir_parser.parse_string
            ~source_path:path
            ~precedence_rank:entry.precedence_rank
            contents
          :: parsed
        , errors )
      | Error error ->
        ( parsed
        , (Sexp.to_string_hum ([%sexp_of: Compression.error] error)
           ^ "\n\
              Hint: verify the directory file is readable, valid gzip, and within the \
              size limit.")
          :: errors ))
  in
  let catalog = Catalog.merge (List.rev parsed) in
  let catalog =
    { catalog with diagnostics = discovery.diagnostics @ catalog.diagnostics }
  in
  catalog, List.rev load_errors
;;

let global_search ~directories catalog pattern =
  let seen = String.Hash_set.create () in
  List.fold catalog.Catalog.manuals ~init:([], []) ~f:(fun (matches, errors) manual_ref ->
    let identity = manual_ref.name in
    if Hash_set.mem seen identity
    then matches, errors
    else (
      Hash_set.add seen identity;
      match Source.load ~directories manual_ref.name with
      | Error error ->
        matches, Sexp.to_string_hum ([%sexp_of: Source.error] error) :: errors
      | Ok source ->
        (match Info_parser.parse source with
         | Error error ->
           matches, Sexp.to_string_hum ([%sexp_of: Info_parser.error] error) :: errors
         | Ok manual ->
           let errors =
             List.rev_append
               (List.map (Manual.diagnostics manual) ~f:(fun diagnostic ->
                  Sexp.to_string_hum ([%sexp_of: Manual.Diagnostic.t] diagnostic)))
               errors
           in
           (match Search.manual manual pattern with
            | Error error ->
              matches, Sexp.to_string_hum ([%sexp_of: Search.error] error) :: errors
            | Ok found -> List.rev_append found matches, errors))))
  |> Tuple2.map_fst ~f:(fun matches ->
    let rank_by_manual =
      List.fold catalog.Catalog.manuals ~init:String.Map.empty ~f:(fun ranks manual ->
        Map.update ranks manual.name ~f:(function
          | None -> manual.precedence_rank
          | Some rank -> Int.min rank manual.precedence_rank))
    in
    List.rev matches
    |> List.sort ~compare:(fun (left : Search.Match.t) right ->
      let key (match_ : Search.Match.t) =
        let exact_manual = Info_id.Manual.to_string match_.manual in
        let normalized_manual = String.lowercase exact_manual in
        ( Map.find rank_by_manual exact_manual |> Option.value ~default:Int.max_value
        , normalized_manual
        , exact_manual
        , match_.byte
        , match_.line
        , match_.column )
      in
      [%compare: int * string * string * int * int * int] (key left) (key right)))
  |> Tuple2.map_snd ~f:List.rev
;;

let catalog_selector ~directories ~search_errors catalog ~current:_ ~name ~args =
  match name with
  | "summary" ->
    Ok
      (Value.Object
         [ "kind", String "catalog_summary"
         ; "sources", Int (List.length catalog.Catalog.sources)
         ; "categories", Int (List.length catalog.categories)
         ; "entries", Int (List.length catalog.entries)
         ; "manuals", Int (List.length catalog.manuals)
         ; "diagnostics", Int (List.length catalog.diagnostics)
         ])
  | "categories" -> Ok (List (List.map catalog.categories ~f:catalog_category_value))
  | "entries" -> Ok (List (List.map catalog.entries ~f:catalog_entry_value))
  | "manuals" -> Ok (List (List.map catalog.manuals ~f:manual_ref_value))
  | "tree" ->
    Result.map (parse_optional_depth name args) ~f:(fun depth ->
      let include_entries =
        Option.value_map depth ~default:true ~f:(fun depth -> depth > 0)
      in
      Value.List
        (List.map catalog.categories ~f:(catalog_category_value ~include_entries)))
  | "search" ->
    Result.bind (parse_single_string_argument name args) ~f:(fun query ->
      Result.bind
        (Search.Pattern.of_query_string query
         |> Result.map_error ~f:(sprintf "Error[E_SEARCH_PATTERN]: %s"))
        ~f:(fun pattern ->
          Result.bind
            (Search.validate pattern
             |> Result.map_error ~f:(fun error ->
               sprintf
                 "Error[E_SEARCH_PATTERN]: %s"
                 (Sexp.to_string_hum ([%sexp_of: Search.error] error))))
            ~f:(fun () ->
              let matches, errors = global_search ~directories catalog pattern in
              search_errors := errors;
              Ok (Value.List (List.map matches ~f:search_value)))))
  | _ -> Error (sprintf "Error[E_QUERY_SELECTOR]: unknown catalog selector .%s" name)
;;

let parse_query ~scope query =
  Query_parser.parse query
  |> Result.map_error ~f:Query_parser.render_error
  |> Result.bind ~f:(fun query ->
    Result.map (Query_typecheck.check ~scope query) ~f:(fun () -> query))
;;

let evaluate ~scope ~selector ~initial query =
  match query with
  | None -> Ok initial
  | Some query ->
    Result.bind (parse_query ~scope query) ~f:(Query_eval.run ~selector ~initial)
;;

let catalog_initial catalog =
  let category_summaries =
    List.map catalog.Catalog.categories ~f:(fun category ->
      Value.Object
        [ "kind", String "category_summary"
        ; "name", String category.name
        ; "entries", Int (List.length category.entries)
        ])
  in
  Value.Object
    [ "kind", String "catalog"
    ; ( "summary"
      , Object
          [ "sources", Int (List.length catalog.Catalog.sources)
          ; "categories", Int (List.length catalog.categories)
          ; "entries", Int (List.length catalog.entries)
          ; "manuals", Int (List.length catalog.manuals)
          ] )
    ; "categories", List category_summaries
    ; "entries", List (List.take catalog.entries 20 |> List.map ~f:catalog_entry_value)
    ; "entries_returned", Int (Int.min 20 (List.length catalog.entries))
    ; "entries_truncated", Bool (List.length catalog.entries > 20)
    ]
;;

let manual_initial manual =
  let graph = Graph.create manual in
  Value.Object
    [ "kind", String "manual"
    ; ( "summary"
      , Object
          [ "manual", String (Info_id.Manual.to_string (Manual.id manual))
          ; "source_path", String (Manual.source manual).main_path
          ; "nodes", Int (List.length (Manual.nodes manual))
          ] )
    ; "tree", Graph.tree ~max_depth:1 graph |> tree_value manual
    ; ( "menu"
      , List
          (Manual.top manual
           |> Option.value_map ~default:[] ~f:(fun node ->
             List.map node.menus ~f:menu_value)) )
    ]
;;

let diagnostic_lines catalog load_errors =
  List.map catalog.Catalog.diagnostics ~f:Diagnostic.render @ load_errors
;;

let strict_catalog_status catalog ~has_load_errors =
  let statuses =
    List.map catalog.Catalog.diagnostics ~f:(fun diagnostic ->
      Diagnostic.Exit_class.status (Diagnostic.exit_class diagnostic))
  in
  let statuses = if has_load_errors then 2 :: statuses else statuses in
  List.max_elt statuses ~compare:Int.compare
;;

let source_error_status = function
  | Source.Invalid_indirect_entry _ -> 3
  | Not_found _ | Compression_error _ | Too_many_indirect_parts _ -> 2
;;

let source_error_hint = function
  | Source.Not_found _ ->
    "Check INFOPATH or pass the containing directory with --directory."
  | Compression_error _ ->
    "Verify the file is readable, valid gzip, and within the size limit."
  | Too_many_indirect_parts _ ->
    "Regenerate the manual with fewer split parts or raise the bounded loader policy in \
     code."
  | Invalid_indirect_entry _ -> "Regenerate the Info manual or repair its Indirect table."
;;

let manual_diagnostic_lines manual =
  List.map (Manual.diagnostics manual) ~f:(fun diagnostic ->
    sprintf
      "Warning[W_INFO_PARSE]: %s\n\
       Hint: regenerate the manual with makeinfo; use --strict to reject recovered input."
      (Sexp.to_string_hum ([%sexp_of: Manual.Diagnostic.t] diagnostic)))
;;

let execute request =
  let environment = Stdlib.Sys.getenv_opt "INFOPATH" in
  let info_path = Info_path.effective ~explicit:request.directories ~environment () in
  let directories = Info_path.directories info_path in
  let render value =
    Render.render
      ~format:request.format
      ~raw_output:request.raw_output
      ~max_results:request.max_results
      value
  in
  match request.scope with
  | None | Some "dir" | Some "(dir)Top" | Some "(dir)top" ->
    let catalog, load_errors = load_catalog info_path in
    let stderr = diagnostic_lines catalog load_errors in
    let strict_status =
      strict_catalog_status catalog ~has_load_errors:(not (List.is_empty load_errors))
    in
    if List.is_empty catalog.sources && List.is_empty catalog.entries
    then
      failure
        ~stderr:
          (stderr
           @ [ "Error[E_CATALOG_EMPTY]: no readable Info directory files\n\
                Hint: set INFOPATH or pass an Info directory with --directory."
             ])
        2
    else if request.strict && Option.is_some strict_status
    then failure ~stderr (Option.value_exn strict_status)
    else (
      let initial = catalog_initial catalog in
      let search_errors = ref [] in
      match
        evaluate
          ~scope:Query_typecheck.Catalog
          ~selector:(catalog_selector ~directories ~search_errors catalog)
          ~initial
          request.query
      with
      | Ok value ->
        let search_warnings =
          List.map !search_errors ~f:(fun error ->
            "Warning[W_SEARCH_COVERAGE]: "
            ^ error
            ^ "\n\
               Hint: inspect the named manual or rerun with --strict to require full \
               coverage.")
        in
        let stderr = stderr @ search_warnings in
        if request.strict && not (List.is_empty search_warnings)
        then failure ~stderr 3
        else success ~stdout:(render value) ~stderr ()
      | Error error -> failure ~stderr:(stderr @ [ error ]) 1)
  | Some scope ->
    (match Source.load ~directories scope with
     | Error error ->
       failure
         ~stderr:
           [ sprintf
               "Error[E_MANUAL_RESOLVE]: %s\nHint: %s"
               (Sexp.to_string_hum ([%sexp_of: Source.error] error))
               (source_error_hint error)
           ]
         (source_error_status error)
     | Ok source ->
       (match Info_parser.parse source with
        | Error error ->
          failure
            ~stderr:
              [ sprintf
                  "Error[E_INFO_PARSE]: %s\n\
                   Hint: regenerate the Info manual and inspect its node separators."
                  (Sexp.to_string_hum ([%sexp_of: Info_parser.error] error))
              ]
            3
        | Ok manual ->
          let stderr = manual_diagnostic_lines manual in
          if request.strict && not (List.is_empty stderr)
          then failure ~stderr 3
          else (
            let initial = manual_initial manual in
            match
              evaluate
                ~scope:Query_typecheck.Manual
                ~selector:(manual_selector manual)
                ~initial
                request.query
            with
            | Ok value -> success ~stdout:(render value) ~stderr ()
            | Error error -> failure ~stderr:(stderr @ [ error ]) 1)))
;;
