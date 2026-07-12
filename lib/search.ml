open! Core

module Pattern = struct
  type t =
    | Literal of string
    | Regex of
        { source : string
        ; case_sensitive : bool
        }
  [@@deriving compare, equal, sexp_of]

  let of_query_string string =
    match String.chop_prefix string ~prefix:"/" with
    | None -> Ok (Literal string)
    | Some rest ->
      (match String.rsplit2 rest ~on:'/' with
       | None -> Error "regex patterns must end with / or /i"
       | Some (source, flags) ->
         if String.for_all flags ~f:(fun flag -> Char.equal flag 'i')
         then Ok (Regex { source; case_sensitive = not (String.mem flags 'i') })
         else Error (sprintf "unsupported regex flags: %s" flags))
  ;;
end

module Match = struct
  type t =
    { manual : Info_id.Manual.t
    ; node : Info_id.Node.t
    ; source_path : string
    ; byte : int
    ; line : int
    ; column : int
    ; matched : string
    ; snippet : string
    }
  [@@deriving compare, equal, sexp_of]
end

type error = Invalid_regex of string [@@deriving sexp_of]

let validate = function
  | Pattern.Literal _ -> Ok ()
  | Regex { source; case_sensitive } ->
    let options = { Re2.Options.default with case_sensitive } in
    Result.map_error (Re2.create ~options source) ~f:(fun _ -> Invalid_regex source)
    |> Result.map ~f:(fun _ -> ())
;;

let literal_matches ~needle haystack =
  let needle = String.lowercase needle in
  let haystack_folded = String.lowercase haystack in
  if String.is_empty needle
  then []
  else (
    let rec loop position matches =
      match String.substr_index haystack_folded ~pos:position ~pattern:needle with
      | None -> List.rev matches
      | Some start -> loop (start + 1) ((start, String.length needle) :: matches)
    in
    loop 0 [])
;;

let regex_matches ~source ~case_sensitive haystack =
  let options = { Re2.Options.default with case_sensitive } in
  match Re2.create ~options source with
  | Error _ -> Error (Invalid_regex source)
  | Ok expression ->
    (match Re2.get_matches expression haystack with
     | Error _ -> Error (Invalid_regex source)
     | Ok matches ->
       Ok
         (List.map matches ~f:(fun match_ -> Re2.Match.get_pos_exn ~sub:(`Index 0) match_)))
;;

let line_and_column body position =
  String.prefix body position
  |> String.fold ~init:(1, 1) ~f:(fun (line, column) char ->
    if Char.equal char '\n' then line + 1, 1 else line, column + 1)
;;

let snippet ~radius body ~start ~length =
  let snippet_start = Int.max 0 (start - radius) in
  let snippet_end = Int.min (String.length body) (start + length + radius) in
  String.sub body ~pos:snippet_start ~len:(snippet_end - snippet_start)
  |> String.tr ~target:'\n' ~replacement:' '
  |> String.strip
;;

let manual ?(snippet_radius = 80) manual pattern =
  let open Result.Let_syntax in
  let%bind () = validate pattern in
  let%map by_node =
    Manual.nodes manual
    |> List.map ~f:(fun node ->
      let%map matches =
        match pattern with
        | Pattern.Literal needle -> Ok (literal_matches ~needle node.body)
        | Regex { source; case_sensitive } ->
          regex_matches ~source ~case_sensitive node.body
      in
      List.map matches ~f:(fun (start, length) ->
        let relative_line, column = line_and_column node.body start in
        Match.
          { manual = Manual.id manual
          ; node = Manual.Node.name node
          ; source_path = node.source_path
          ; byte =
              (node.body_bytes.start
               +
               if start < Array.length node.body_raw_offsets
               then node.body_raw_offsets.(start)
               else start)
          ; line = node.lines.start + relative_line - 1
          ; column
          ; matched = String.sub node.body ~pos:start ~len:length
          ; snippet = snippet ~radius:snippet_radius node.body ~start ~length
          }))
    |> Result.all
  in
  List.concat by_node
  |> List.sort ~compare:(fun left right ->
    [%compare: int * int] (left.byte, left.column) (right.byte, right.column))
;;

let%expect_test "literal and regex search retain stable byte and line locations" =
  let manual_id = Info_id.Manual.of_string_exn "sample" in
  let node_id = Info_id.Node.of_string_exn "Top" in
  let source =
    Source.
      { manual = manual_id
      ; main_path = "sample.info"
      ; parts = [ Part.{ path = "sample.info"; contents = ""; logical_offset = 0 } ]
      }
  in
  let body = "Alpha needle.\nAnother NEEDLE here." in
  let node =
    Manual.Node.
      { header =
          { file = Some "sample.info"
          ; node = node_id
          ; next = None
          ; prev = None
          ; up = None
          }
      ; source_path = "sample.info"
      ; bytes = { start = 0; end_ = 100 }
      ; body_bytes = { start = 20; end_ = 20 + String.length body }
      ; lines = { start = 4; end_ = 5 }
      ; body
      ; body_raw_offsets = Array.init (String.length body + 1) ~f:Fn.id
      ; menus = []
      ; xrefs = []
      ; indices = []
      ; anchors = []
      }
  in
  let document =
    Manual.create
      ~id:manual_id
      ~source
      ~encoding:None
      ~preamble:None
      ~nodes:[ node ]
      ~diagnostics:[]
  in
  let print_matches pattern =
    match manual ~snippet_radius:8 document pattern with
    | Error error -> print_s [%sexp (error : error)]
    | Ok matches ->
      List.iter matches ~f:(fun match_ ->
        printf
          "%d:%d byte=%d match=%s snippet=%S\n"
          match_.line
          match_.column
          match_.byte
          match_.matched
          match_.snippet)
  in
  print_matches (Pattern.Literal "needle");
  print_matches (Pattern.Regex { source = "n(e+)dle"; case_sensitive = false });
  [%expect
    {|
    4:7 byte=26 match=needle snippet="Alpha needle. Anothe"
    5:9 byte=42 match=NEEDLE snippet="Another NEEDLE here."
    4:7 byte=26 match=needle snippet="Alpha needle. Anothe"
    5:9 byte=42 match=NEEDLE snippet="Another NEEDLE here."
    |}]
;;

let%expect_test "slash patterns reject malformed delimiters and flags" =
  List.iter [ "/unterminated"; "/needle/m" ] ~f:(fun query ->
    match Pattern.of_query_string query with
    | Ok _ -> print_endline "unexpected success"
    | Error message -> print_endline message);
  [%expect
    {|
    regex patterns must end with / or /i
    unsupported regex flags: m
    |}]
;;

let%expect_test "literal matching retains overlapping occurrences" =
  print_s [%sexp (literal_matches ~needle:"ana" "banana" : (int * int) list)];
  [%expect {| ((1 3) (3 3)) |}]
;;
