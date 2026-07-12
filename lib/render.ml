open! Core

type format =
  | Text
  | Json
  | Jsonl
[@@deriving sexp_of, compare, equal]

let limit_value value max_results =
  match value, max_results with
  | Query_eval.Value.List values, Some limit when List.length values > limit ->
    Query_eval.Value.List (List.take values limit), Some (List.length values, limit)
  | _ -> value, None
;;

let rec text_lines ?(indent = 0) = function
  | Query_eval.Value.Null -> [ "null" ]
  | Bool value -> [ Bool.to_string value ]
  | Int value -> [ Int.to_string value ]
  | String value -> String.split_lines value
  | List values ->
    List.concat_map values ~f:(fun value ->
      match value with
      | Query_eval.Value.Object _ ->
        (match text_lines ~indent:(indent + 2) value with
         | [] -> [ String.make indent ' ' ^ "-" ]
         | first :: rest -> (String.make indent ' ' ^ "- " ^ String.strip first) :: rest)
      | _ ->
        let lines = text_lines ~indent:(indent + 2) value in
        (match lines with
         | [] -> [ sprintf "%s-" (String.make indent ' ') ]
         | first :: rest ->
           (String.make indent ' ' ^ "- " ^ first)
           :: List.map rest ~f:(fun line -> String.make (indent + 2) ' ' ^ line)))
  | Object fields ->
    List.concat_map fields ~f:(fun (key, value) ->
      match value with
      | Query_eval.Value.String value when not (String.mem value '\n') ->
        [ sprintf "%s%s=%s" (String.make indent ' ') key value ]
      | Int value -> [ sprintf "%s%s=%d" (String.make indent ' ') key value ]
      | Bool value -> [ sprintf "%s%s=%b" (String.make indent ' ') key value ]
      | Null -> [ sprintf "%s%s=null" (String.make indent ' ') key ]
      | _ ->
        sprintf "%s%s:" (String.make indent ' ') key
        :: text_lines ~indent:(indent + 2) value)
;;

let json_envelope value truncation =
  let metadata =
    match truncation with
    | None -> []
    | Some (total, returned) ->
      [ "matched_total", `Int total; "returned", `Int returned; "truncated", `Bool true ]
  in
  `Assoc
    ([ "schema_version", `Int 1; "data", Query_eval.Value.to_yojson value ] @ metadata)
;;

let render ~format ~raw_output ~max_results value =
  let visible, truncation = limit_value value max_results in
  match format, raw_output, visible with
  | Text, true, Query_eval.Value.String value -> value
  | Text, _, _ ->
    let body = text_lines visible |> String.concat ~sep:"\n" in
    (match truncation with
     | None -> body
     | Some (total, returned) ->
       body ^ sprintf "\n\nmatched_total=%d\nreturned=%d\ntruncated=true" total returned)
  | Json, _, _ -> Yojson.Safe.pretty_to_string (json_envelope visible truncation)
  | Jsonl, _, Query_eval.Value.List values ->
    let lines =
      List.map values ~f:(fun value ->
        `Assoc [ "schema_version", `Int 1; "data", Query_eval.Value.to_yojson value ])
    in
    let lines =
      match truncation with
      | None -> lines
      | Some (total, returned) ->
        lines
        @ [ `Assoc
              [ "schema_version", `Int 1
              ; ( "metadata"
                , `Assoc
                    [ "matched_total", `Int total
                    ; "returned", `Int returned
                    ; "truncated", `Bool true
                    ] )
              ]
          ]
    in
    List.map lines ~f:Yojson.Safe.to_string |> String.concat ~sep:"\n"
  | Jsonl, _, _ ->
    Yojson.Safe.to_string
      (`Assoc [ "schema_version", `Int 1; "data", Query_eval.Value.to_yojson visible ])
;;

let%expect_test "only root collections are bounded" =
  let value =
    Query_eval.Value.Object
      [ "items", List [ String "one"; String "two"; String "three" ] ]
  in
  render ~format:Text ~raw_output:false ~max_results:(Some 2) value |> print_endline;
  [%expect
    {|
    items:
      - one
      - two
      - three
    |}]
;;

let%expect_test "jsonl reports root truncation" =
  let value = Query_eval.Value.List [ String "one"; String "two" ] in
  render ~format:Jsonl ~raw_output:false ~max_results:(Some 1) value |> print_endline;
  [%expect
    {|
    {"schema_version":1,"data":"one"}
    {"schema_version":1,"metadata":{"matched_total":2,"returned":1,"truncated":true}}
    |}]
;;
