open! Core

module Value = struct
  type t =
    | Null
    | Bool of bool
    | Int of int
    | String of string
    | Object of (string * t) list
    | List of t list
  [@@deriving sexp_of, compare, equal]

  let field value name =
    match value with
    | Object fields ->
      (match List.Assoc.find fields ~equal:String.equal name with
       | Some value -> Ok value
       | None ->
         Error
           (sprintf
              "Error[E_QUERY_FIELD]: unknown field %S; available fields: %s"
              name
              (fields |> List.map ~f:fst |> String.concat ~sep:", ")))
    | _ -> Error (sprintf "Error[E_QUERY_TYPE]: field .%s requires an object" name)
  ;;

  let rec to_yojson = function
    | Null -> `Null
    | Bool value -> `Bool value
    | Int value -> `Int value
    | String value -> `String value
    | Object fields ->
      `Assoc (List.map fields ~f:(fun (key, value) -> key, to_yojson value))
    | List values -> `List (List.map values ~f:to_yojson)
  ;;
end

type selector =
  current:Value.t -> name:string -> args:Value.t list -> (Value.t, string) Result.t

let literal = function
  | Query_ast.String value -> Value.String value
  | Int value -> Int value
  | Bool value -> Bool value
  | Null -> Null
;;

let rec eval_expr ~current = function
  | Query_ast.Literal value -> Ok (literal value)
  | Field path ->
    List.fold_result path ~init:current ~f:(fun value field -> Value.field value field)
  | Call (name, expressions) ->
    let open Result.Let_syntax in
    let%bind arguments = List.map expressions ~f:(eval_expr ~current) |> Result.all in
    eval_call name arguments
  | Compare (operator, left, right) ->
    let open Result.Let_syntax in
    let%bind left = eval_expr ~current left in
    let%bind right = eval_expr ~current right in
    let%map result = compare_values operator left right in
    Value.Bool result
  | And (left, right) -> eval_boolean_pair ~current ~operator:( && ) left right
  | Or (left, right) -> eval_boolean_pair ~current ~operator:( || ) left right

and eval_call name arguments =
  let string_pair function_name f =
    match arguments with
    | [ Value.String left; String right ] -> Ok (Value.Bool (f left right))
    | _ ->
      Error (sprintf "Error[E_QUERY_TYPE]: %s expects two string arguments" function_name)
  in
  match name with
  | "contains" ->
    string_pair name (fun value substring -> String.is_substring value ~substring)
  | "startswith" -> string_pair name (fun value prefix -> String.is_prefix value ~prefix)
  | "endswith" -> string_pair name (fun value suffix -> String.is_suffix value ~suffix)
  | _ -> Error (sprintf "Error[E_QUERY_FUNCTION]: unknown function %S" name)

and compare_values operator left right =
  match operator with
  | Query_ast.Equal -> Ok (Value.equal left right)
  | Not_equal -> Ok (not (Value.equal left right))
  | (Less | Less_or_equal | Greater | Greater_or_equal) as operator ->
    let comparison =
      match left, right with
      | Value.Int left, Int right -> Some (Int.compare left right)
      | String left, String right -> Some (String.compare left right)
      | Bool left, Bool right -> Some (Bool.compare left right)
      | _ -> None
    in
    (match comparison with
     | None ->
       Error
         "Error[E_QUERY_TYPE]: ordered comparison requires operands of the same scalar \
          type"
     | Some comparison ->
       Ok
         (match operator with
          | Less -> comparison < 0
          | Less_or_equal -> comparison <= 0
          | Greater -> comparison > 0
          | Greater_or_equal -> comparison >= 0
          | Equal | Not_equal -> assert false))

and eval_boolean_pair ~current ~operator left right =
  let open Result.Let_syntax in
  let%bind left = eval_expr ~current left in
  let%bind right = eval_expr ~current right in
  match left, right with
  | Value.Bool left, Bool right -> Ok (Value.Bool (operator left right))
  | _ -> Error "Error[E_QUERY_TYPE]: 'and' and 'or' require boolean operands"
;;

let normalize_index length index = if index < 0 then length + index else index

let apply_postfix value = function
  | Query_ast.Field_access field -> Value.field value field
  | Index index ->
    (match value with
     | Value.List values ->
       let index = normalize_index (List.length values) index in
       (match List.nth values index with
        | Some value -> Ok value
        | None -> Error (sprintf "Error[E_QUERY_INDEX]: index %d is out of bounds" index))
     | _ -> Error "Error[E_QUERY_TYPE]: indexing requires a collection")
  | Slice (start, finish) ->
    (match value with
     | Value.List values ->
       let length = List.length values in
       let boundary default = function
         | None -> default
         | Some value -> normalize_index length value |> Int.max 0 |> Int.min length
       in
       let start = boundary 0 start in
       let finish = boundary length finish in
       let slice_length = Int.max 0 (finish - start) in
       Ok (Value.List (List.slice values start (start + slice_length)))
     | _ -> Error "Error[E_QUERY_TYPE]: slicing requires a collection")
;;

let builtin_selector ~current ~name =
  match name, current with
  | "length", Value.List values -> Some (Ok (Value.Int (List.length values)))
  | "length", String value -> Some (Ok (Value.Int (String.length value)))
  | "length", Object fields -> Some (Ok (Value.Int (List.length fields)))
  | _ -> None
;;

let apply_select ~selector current ~name ~args ~postfixes =
  let open Result.Let_syntax in
  let%bind args = List.map args ~f:(eval_expr ~current) |> Result.all in
  let%bind selected =
    match builtin_selector ~current ~name with
    | Some result -> result
    | None ->
      (match selector ~current ~name ~args with
       | Ok value -> Ok value
       | Error selector_error ->
         (match args with
          | [] ->
            (match Value.field current name with
             | Ok value -> Ok value
             | Error _ -> Error selector_error)
          | _ -> Error selector_error))
  in
  List.fold_result postfixes ~init:selected ~f:apply_postfix
;;

let apply_stage ~selector current = function
  | Query_ast.Select { name; args; postfixes } ->
    apply_select ~selector current ~name ~args ~postfixes
  | Filter expression ->
    (match current with
     | Value.List values ->
       let open Result.Let_syntax in
       let%map kept =
         List.filter_map values ~f:(fun value ->
           match eval_expr ~current:value expression with
           | Ok (Value.Bool true) -> Some (Ok value)
           | Ok (Bool false) -> None
           | Ok _ -> Some (Error "Error[E_QUERY_TYPE]: filter expression must be boolean")
           | Error error -> Some (Error error))
         |> Result.all
       in
       Value.List kept
     | _ -> Error "Error[E_QUERY_TYPE]: filter requires a collection")
  | Map expression ->
    (match current with
     | Value.List values ->
       Result.map
         (List.map values ~f:(fun value -> eval_expr ~current:value expression)
          |> Result.all)
         ~f:(fun values -> Value.List values)
     | _ -> Error "Error[E_QUERY_TYPE]: map requires a collection")
;;

let run ~selector ~initial query =
  List.fold_result query ~init:initial ~f:(apply_stage ~selector)
;;

let%expect_test "filter and map generic objects" =
  let initial =
    Value.List
      [ Object [ "name", String "Top"; "level", Int 0 ]
      ; Object [ "name", String "Child"; "level", Int 1 ]
      ]
  in
  let query =
    match Query_parser.parse ".items | filter(.level > 0) | map(.name)" with
    | Ok query -> query
    | Error error -> failwith (Query_parser.render_error error)
  in
  let selector ~current ~name ~args:_ =
    match name with
    | "items" -> Ok current
    | _ -> Error "unknown selector"
  in
  run ~selector ~initial query |> [%sexp_of: (Value.t, string) Result.t] |> print_s;
  [%expect {| (Ok (List ((String Child)))) |}]
;;
