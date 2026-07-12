open! Core

type scope =
  | Catalog
  | Manual
[@@deriving sexp_of, compare, equal]

type value_type =
  | Catalog_root
  | Manual_root
  | Node
  | Node_list
  | List_value
  | Object
  | Scalar
  | Unknown
[@@deriving sexp_of]

let value_type_name value_type =
  Sexp.to_string_hum ([%sexp_of: value_type] value_type) |> String.lowercase
;;

let error message = Error ("Error[E_QUERY_TYPECHECK]: " ^ message)

let stage_error ~stage ~current message hint =
  error
    (sprintf
       "stage %d has current type %s: %s\nHint: %s"
       stage
       (value_type_name current)
       message
       hint)
;;

let rec check_expr = function
  | Query_ast.Literal _ | Field _ -> Ok ()
  | Call (name, arguments) ->
    if not (List.mem [ "contains"; "startswith"; "endswith" ] name ~equal:String.equal)
    then error (sprintf "unknown expression function %S" name)
    else if not (Int.equal (List.length arguments) 2)
    then error (sprintf "%s expects exactly two arguments" name)
    else List.map arguments ~f:check_expr |> Result.all_unit
  | Compare (_, left, right) | And (left, right) | Or (left, right) ->
    Result.all_unit [ check_expr left; check_expr right ]
;;

let is_string_literal = function
  | Query_ast.Literal (String _) -> true
  | _ -> false
;;

let is_non_negative_int_literal = function
  | Query_ast.Literal (Int value) -> value >= 0
  | _ -> false
;;

let check_arguments ~scope ~name ~args =
  let catalog_selectors =
    [ "summary"; "tree"; "categories"; "entries"; "manuals"; "search" ]
  in
  let manual_selectors =
    [ "summary"
    ; "tree"
    ; "nodes"
    ; "node"
    ; "search"
    ; "menus"
    ; "xrefs"
    ; "indices"
    ; "anchors"
    ; "text"
    ]
  in
  let recognized =
    String.equal name "length"
    || List.mem
         (match scope with
          | Catalog -> catalog_selectors
          | Manual -> manual_selectors)
         name
         ~equal:String.equal
  in
  if not recognized
  then if List.is_empty args then Ok () else error (sprintf "unknown selector .%s" name)
  else (
    match name, args with
    | ("node" | "search"), [ argument ] when is_string_literal argument -> Ok ()
    | ("node" | "search"), _ -> error (sprintf ".%s expects one string literal" name)
    | "tree", [] -> Ok ()
    | "tree", [ argument ] when is_non_negative_int_literal argument -> Ok ()
    | "tree", _ -> error ".tree expects an optional non-negative integer"
    | _, [] -> Ok ()
    | _ -> error (sprintf ".%s does not accept arguments" name))
;;

let list_like = function
  | Node_list | List_value -> true
  | _ -> false
;;

let apply_postfix_type value_type = function
  | Query_ast.Index _ ->
    if list_like value_type then Ok Unknown else error "indexing requires a collection"
  | Slice _ ->
    if list_like value_type then Ok value_type else error "slicing requires a collection"
  | Field_access _ ->
    (match value_type with
     | Scalar -> error "field access requires an object"
     | _ -> Ok Unknown)
;;

let infer_selector ~scope ~stage ~current ~name =
  let root_required output =
    match scope, current with
    | Catalog, Catalog_root | Manual, Manual_root -> Ok output
    | _ ->
      stage_error
        ~stage
        ~current
        (sprintf ".%s is a root selector" name)
        "start a new query at this selector or access a field on the current value"
  in
  match name with
  | "length" ->
    (match current with
     | Catalog_root | Manual_root | Node | Node_list | List_value | Object | Scalar ->
       Ok Scalar
     | Unknown -> Ok Scalar)
  | "summary" -> root_required Object
  | "tree" -> root_required List_value
  | "categories" | "entries" | "manuals" -> root_required List_value
  | "nodes" -> root_required Node_list
  | "node" -> root_required Node
  | "search" -> root_required List_value
  | "menus" | "xrefs" | "indices" | "anchors" ->
    (match current with
     | Manual_root | Node | Node_list -> Ok List_value
     | _ ->
       stage_error
         ~stage
         ~current
         (sprintf ".%s requires a manual, node, or node collection" name)
         "use .node(\"Name\") or .nodes before this selector")
  | "text" ->
    (match current with
     | Node -> Ok Scalar
     | Node_list -> Ok List_value
     | _ ->
       stage_error
         ~stage
         ~current
         ".text requires a node or node collection"
         "use .node(\"Name\") | .text")
  | _ ->
    (match current with
     | Scalar ->
       stage_error
         ~stage
         ~current
         (sprintf ".%s requires an object" name)
         "remove the field stage"
     | _ -> Ok Unknown)
;;

let check ~scope query =
  let initial =
    match scope with
    | Catalog -> Catalog_root
    | Manual -> Manual_root
  in
  List.foldi query ~init:(Ok initial) ~f:(fun index current stage ->
    let stage_number = index + 1 in
    Result.bind current ~f:(fun current ->
      match stage with
      | Query_ast.Select { name; args; postfixes } ->
        Result.bind
          (List.map args ~f:check_expr |> Result.all_unit)
          ~f:(fun () ->
            Result.bind (check_arguments ~scope ~name ~args) ~f:(fun () ->
              Result.bind
                (infer_selector ~scope ~stage:stage_number ~current ~name)
                ~f:(fun output ->
                  List.fold_result postfixes ~init:output ~f:apply_postfix_type)))
      | Filter expression ->
        Result.bind (check_expr expression) ~f:(fun () ->
          if list_like current
          then Ok current
          else
            stage_error
              ~stage:stage_number
              ~current
              "filter requires a collection"
              "apply filter immediately after a collection selector such as .nodes")
      | Map expression ->
        Result.bind (check_expr expression) ~f:(fun () ->
          if list_like current
          then Ok List_value
          else
            stage_error
              ~stage:stage_number
              ~current
              "map requires a collection"
              "apply map immediately after a collection selector such as .entries")))
  |> Result.map ~f:(fun _ -> ())
;;

let%expect_test "stage types reject invalid pipelines before evaluation" =
  let check scope query =
    match Query_parser.parse query with
    | Error parse_error -> print_endline (Query_parser.render_error parse_error)
    | Ok query -> check ~scope query |> [%sexp_of: (unit, string) Result.t] |> print_s
  in
  check Catalog ".entries | filter(contains(.description, \"debugger\"))";
  check Manual ".node(\"Top\") | .text";
  check Manual ".nodes | map(.name) | .menus";
  check Manual ".nodes | .length | filter(true)";
  [%expect
    {|
    (Ok ())
    (Ok ())
    (Error
      "Error[E_QUERY_TYPECHECK]: stage 3 has current type list_value: .menus requires a manual, node, or node collection\
     \nHint: use .node(\"Name\") or .nodes before this selector")
    (Error
      "Error[E_QUERY_TYPECHECK]: stage 3 has current type scalar: filter requires a collection\
     \nHint: apply filter immediately after a collection selector such as .nodes")
    |}]
;;
