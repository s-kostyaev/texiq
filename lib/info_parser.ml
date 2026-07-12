open! Core

type error =
  | No_nodes of { source_path : string }
  | Invalid_manual_id of Error.t
[@@deriving sexp_of]

type line =
  { text : string
  ; start : int
  ; end_ : int
  ; number : int
  ; raw_offsets : int array
  }

let remove_del string = String.filter string ~f:(fun char -> not (Char.equal char '\127'))

let trim_target string =
  let string = String.strip string in
  let characters, _ =
    String.fold string ~init:([], false) ~f:(fun (characters, quoted) char ->
      if Char.equal char '\127'
      then characters, not quoted
      else (char, quoted) :: characters, quoted)
  in
  let characters = List.rev characters in
  let characters =
    match List.last characters with
    | Some (char, false) when Char.equal char '.' || Char.equal char ',' ->
      List.drop_last_exn characters
    | _ -> characters
  in
  characters |> List.map ~f:fst |> String.of_char_list |> String.strip
;;

let target_of_string string =
  let value = trim_target string in
  if String.is_empty value then None else Info_id.Target.of_string value |> Result.ok
;;

let lines_of_string string =
  let length = String.length string in
  let rec loop start number lines =
    if start >= length
    then List.rev lines
    else (
      match String.index_from string start '\n' with
      | Some newline ->
        let text = String.sub string ~pos:start ~len:(newline - start) in
        loop
          (newline + 1)
          (number + 1)
          ({ text
           ; start
           ; end_ = newline + 1
           ; number
           ; raw_offsets = Array.init (String.length text + 1) ~f:Fn.id
           }
           :: lines)
      | None ->
        let text = String.drop_prefix string start in
        List.rev
          ({ text
           ; start
           ; end_ = length
           ; number
           ; raw_offsets = Array.init (String.length text + 1) ~f:Fn.id
           }
           :: lines))
  in
  loop 0 1 []
;;

let find_all string char =
  let rec loop position indexes =
    match String.index_from string position char with
    | None -> List.rev indexes
    | Some index -> loop (index + 1) (index :: indexes)
  in
  loop 0 []
;;

let split_header_fields header =
  let length = String.length header in
  let rec loop start index quoted reversed =
    if index >= length
    then List.rev (String.sub header ~pos:start ~len:(length - start) :: reversed)
    else (
      match header.[index] with
      | '\127' -> loop start (index + 1) (not quoted) reversed
      | ',' when not quoted ->
        let field = String.sub header ~pos:start ~len:(index - start) in
        loop (index + 1) (index + 1) quoted (field :: reversed)
      | _ -> loop start (index + 1) quoted reversed)
  in
  loop 0 0 false []
;;

let header_field header name =
  split_header_fields header
  |> List.find_map ~f:(fun field ->
    match String.lsplit2 field ~on:':' with
    | Some (label, value) when String.Caseless.equal (String.strip label) name ->
      Some (String.strip value)
    | _ -> None)
;;

let parse_header header =
  let open Option.Let_syntax in
  let%bind node = header_field header "Node" |> Option.map ~f:remove_del in
  let%bind node = Info_id.Node.of_string node |> Result.ok in
  let file = header_field header "File" |> Option.map ~f:remove_del in
  Some
    Manual.Header.
      { file
      ; node
      ; next = Option.bind (header_field header "Next") ~f:target_of_string
      ; prev = Option.bind (header_field header "Prev") ~f:target_of_string
      ; up = Option.bind (header_field header "Up") ~f:target_of_string
      }
;;

let line_range (lines : line list) =
  match List.hd lines, List.last lines with
  | Some first, Some last ->
    Manual.Line_range.{ start = first.number; end_ = last.number }
  | _ -> Manual.Line_range.{ start = 0; end_ = 0 }
;;

let indexes_outside_del string wanted =
  let rec loop index quoted reversed =
    if index >= String.length string
    then List.rev reversed
    else (
      match string.[index] with
      | '\127' -> loop (index + 1) (not quoted) reversed
      | char when (not quoted) && Char.equal char wanted ->
        loop (index + 1) quoted (index :: reversed)
      | _ -> loop (index + 1) quoted reversed)
  in
  loop 0 false []
;;

let target_and_description string =
  let rec loop index quoted =
    if index >= String.length string
    then String.strip string, ""
    else (
      match string.[index] with
      | '\127' -> loop (index + 1) (not quoted)
      | '.' when not quoted ->
        if index + 1 = String.length string || Char.is_whitespace string.[index + 1]
        then
          ( String.prefix string index |> String.strip
          , String.drop_prefix string (index + 1) |> String.strip )
        else loop (index + 1) quoted
      | _ -> loop (index + 1) quoted)
  in
  loop 0 false
;;

let menu_entry_of_lines ~(node_is_index : bool) (entry_lines : line list) =
  match entry_lines with
  | [] -> None, None
  | first :: _ ->
    let stripped = String.strip first.text in
    (match String.chop_prefix stripped ~prefix:"* " with
     | None -> None, None
     | Some rest ->
       let parsed =
         match
           indexes_outside_del rest ':'
           |> List.find ~f:(fun index ->
             index + 1 < String.length rest && Char.equal rest.[index + 1] ':')
         with
         | Some delimiter ->
           let label = String.sub rest ~pos:0 ~len:delimiter |> String.strip in
           let description =
             String.drop_prefix rest (delimiter + 2)
             :: List.map (List.tl_exn entry_lines) ~f:(fun line -> line.text)
             |> List.map ~f:String.strip
             |> String.concat ~sep:" "
             |> String.strip
           in
           let label = remove_del label in
           Option.map (target_of_string label) ~f:(fun target ->
             label, target, description)
         | None ->
           (match List.last (indexes_outside_del rest ':') with
            | None -> None
            | Some delimiter ->
              let label = String.prefix rest delimiter |> String.strip |> remove_del in
              let target_text, description =
                String.drop_prefix rest (delimiter + 1) |> target_and_description
              in
              let description =
                description
                :: List.map (List.tl_exn entry_lines) ~f:(fun line -> line.text)
                |> List.map ~f:String.strip
                |> String.concat ~sep:" "
                |> String.strip
              in
              Option.map (target_of_string target_text) ~f:(fun target ->
                label, target, description))
       in
       (match parsed with
        | None -> None, None
        | Some (label, target, description) ->
          let last = List.last_exn entry_lines in
          let bytes = Manual.Byte_range.{ start = first.start; end_ = last.end_ } in
          let lines = line_range entry_lines in
          if node_is_index
          then
            ( None
            , Some Manual.Index_entry.{ term = label; target; description; bytes; lines }
            )
          else Some Manual.Menu_entry.{ label; target; description; bytes; lines }, None))
;;

let parse_menus lines =
  let node_is_index =
    List.exists lines ~f:(fun line ->
      String.is_substring line.text ~substring:"\000\b[index\000\b]")
  in
  let flush current menus indices =
    match current with
    | [] -> menus, indices
    | _ ->
      let menu, index = menu_entry_of_lines ~node_is_index (List.rev current) in
      Option.to_list menu @ menus, Option.to_list index @ indices
  in
  let rec loop in_menu current menus indices = function
    | [] ->
      let menus, indices = flush current menus indices in
      List.rev menus, List.rev indices
    | line :: rest ->
      let stripped = String.strip line.text in
      if String.equal stripped "* Menu:"
      then loop true [] menus indices rest
      else if in_menu && String.is_prefix stripped ~prefix:"* "
      then (
        let menus, indices = flush current menus indices in
        loop true [ line ] menus indices rest)
      else if in_menu && String.is_empty stripped
      then (
        let menus, indices = flush current menus indices in
        loop true [] menus indices rest)
      else if in_menu && (not (List.is_empty current)) && Char.is_whitespace line.text.[0]
      then loop true (line :: current) menus indices rest
      else if in_menu
      then (
        let menus, indices = flush current menus indices in
        loop false [] menus indices rest)
      else loop false current menus indices rest
  in
  loop false [] [] [] lines
;;

let parse_xrefs lines =
  let position_in_lines lines position =
    let rec loop position = function
      | [] -> None
      | line :: rest ->
        let length = String.length line.text in
        if position <= length
        then Some (line, position)
        else loop (position - length - 1) rest
    in
    loop position lines
  in
  List.concat_mapi lines ~f:(fun line_index line ->
    let paragraph_lines =
      List.drop lines line_index
      |> List.take_while ~f:(fun line -> not (String.is_empty (String.strip line.text)))
    in
    let paragraph =
      List.map paragraph_lines ~f:(fun line -> line.text) |> String.concat ~sep:"\n"
    in
    let folded = String.lowercase line.text in
    let rec loop position xrefs =
      match String.substr_index folded ~pos:position ~pattern:"*note " with
      | None -> List.rev xrefs
      | Some start ->
        let rest_start = start + 6 in
        let rest = String.drop_prefix paragraph rest_start in
        let parsed =
          match
            indexes_outside_del rest ':'
            |> List.find ~f:(fun index ->
              index + 1 < String.length rest && Char.equal rest.[index + 1] ':')
          with
          | Some delimiter ->
            let label =
              String.sub rest ~pos:0 ~len:delimiter |> String.strip |> remove_del
            in
            Option.map (target_of_string label) ~f:(fun target ->
              label, target, delimiter + 2)
          | None ->
            Option.bind
              (List.hd (indexes_outside_del rest ':'))
              ~f:(fun delimiter ->
                let label =
                  String.sub rest ~pos:0 ~len:delimiter |> String.strip |> remove_del
                in
                let target_payload = String.drop_prefix rest (delimiter + 1) in
                let target_text, _description = target_and_description target_payload in
                let consumed =
                  let rec find index quoted =
                    if index >= String.length target_payload
                    then String.length target_payload
                    else (
                      match target_payload.[index] with
                      | '\127' -> find (index + 1) (not quoted)
                      | '.' when not quoted -> index + 1
                      | _ -> find (index + 1) quoted)
                  in
                  find 0 false
                in
                Option.map (target_of_string target_text) ~f:(fun target ->
                  label, target, delimiter + 1 + consumed))
        in
        let xrefs =
          Option.value_map parsed ~default:xrefs ~f:(fun (label, target, length) ->
            let end_position = Int.min (String.length paragraph) (rest_start + length) in
            match position_in_lines paragraph_lines end_position with
            | None -> xrefs
            | Some (end_line, end_column) ->
              Manual.Xref.
                { label
                ; target
                ; bytes =
                    { start = line.start + line.raw_offsets.(start)
                    ; end_ = end_line.start + end_line.raw_offsets.(end_column)
                    }
                ; lines = { start = line.number; end_ = end_line.number }
                }
              :: xrefs)
        in
        loop rest_start xrefs
    in
    loop 0 [])
;;

let first_body_position contents separator =
  let rec skip index =
    if
      index < String.length contents
      && (Char.equal contents.[index] '\n' || Char.equal contents.[index] '\012')
    then skip (index + 1)
    else index
  in
  skip (separator + 1)
;;

let line_number_lookup contents =
  let newlines = find_all contents '\n' |> Array.of_list in
  fun position ->
    let rec count_before low high =
      if low >= high
      then low
      else (
        let middle = low + ((high - low) / 2) in
        if newlines.(middle) < position
        then count_before (middle + 1) high
        else count_before low middle)
    in
    1 + count_before 0 (Array.length newlines)
;;

type text_decoder = string -> string * int array

let identity_decoder string = string, Array.init (String.length string + 1) ~f:Fn.id

let single_byte_decoder ~codepoint string =
  let output = Buffer.create (String.length string) in
  let offsets_rev = ref [] in
  String.iteri string ~f:(fun raw_offset char ->
    let code = codepoint (Char.to_int char) in
    if code < 0x80
    then (
      offsets_rev := raw_offset :: !offsets_rev;
      Buffer.add_char output (Char.of_int_exn code))
    else if code < 0x800
    then (
      offsets_rev := raw_offset :: raw_offset :: !offsets_rev;
      Buffer.add_char output (Char.of_int_exn (0xc0 lor (code lsr 6)));
      Buffer.add_char output (Char.of_int_exn (0x80 lor (code land 0x3f))))
    else (
      offsets_rev := raw_offset :: raw_offset :: raw_offset :: !offsets_rev;
      Buffer.add_char output (Char.of_int_exn (0xe0 lor (code lsr 12)));
      Buffer.add_char output (Char.of_int_exn (0x80 lor ((code lsr 6) land 0x3f)));
      Buffer.add_char output (Char.of_int_exn (0x80 lor (code land 0x3f)))));
  let offsets = Array.of_list (List.rev (String.length string :: !offsets_rev)) in
  Buffer.contents output, offsets
;;

let latin1_decoder = single_byte_decoder ~codepoint:Fn.id

let latin9_decoder =
  single_byte_decoder ~codepoint:(function
    | 0xa4 -> 0x20ac
    | 0xa6 -> 0x0160
    | 0xa8 -> 0x0161
    | 0xb4 -> 0x017d
    | 0xb8 -> 0x017e
    | 0xbc -> 0x0152
    | 0xbd -> 0x0153
    | 0xbe -> 0x0178
    | code -> code)
;;

let decoder_of_encoding = function
  | None -> identity_decoder, None
  | Some encoding ->
    (match String.lowercase (String.strip encoding) with
     | "utf-8" | "utf8" | "us-ascii" | "ascii" -> identity_decoder, None
     | "iso-8859-1" | "iso8859-1" | "latin-1" | "latin1" -> latin1_decoder, None
     | "iso-8859-15" | "iso8859-15" | "latin-9" | "latin9" -> latin9_decoder, None
     | _ -> latin1_decoder, Some encoding)
;;

let parse_part ~(decode_text : text_decoder) (part : Source.Part.t) =
  let line_number_at = line_number_lookup part.contents in
  let separators = find_all part.contents '\031' in
  let following_separators = Option.value (List.tl separators) ~default:[] in
  let boundaries =
    match separators with
    | [] -> []
    | _ ->
      List.map2_exn
        separators
        (following_separators @ [ String.length part.contents ])
        ~f:(fun start end_ -> start, end_)
  in
  let nodes, diagnostics =
    List.fold
      boundaries
      ~init:([], [])
      ~f:(fun (nodes, diagnostics) (separator, segment_end) ->
        let header_start = first_body_position part.contents separator in
        match String.index_from part.contents header_start '\n' with
        | None -> nodes, diagnostics
        | Some header_end ->
          let header =
            String.sub part.contents ~pos:header_start ~len:(header_end - header_start)
            |> decode_text
            |> fst
          in
          (match parse_header header with
           | None ->
             let normalized_header = String.strip header |> String.lowercase in
             if
               List.exists
                 [ "indirect:"; "tag table:"; "end tag table"; "local variables:" ]
                 ~f:(fun prefix -> String.is_prefix normalized_header ~prefix)
             then nodes, diagnostics
             else
               ( nodes
               , Manual.Diagnostic.Malformed_header
                   { source_path = part.path
                   ; byte = part.logical_offset + header_start
                   ; header
                   }
                 :: diagnostics )
           | Some parsed_header ->
             let body_start = header_end + 1 in
             let body_end = segment_end in
             let body =
               String.sub part.contents ~pos:body_start ~len:(body_end - body_start)
             in
             let raw_body = body in
             let body, body_raw_offsets = decode_text raw_body in
             let local_lines =
               lines_of_string raw_body
               |> List.map ~f:(fun line ->
                 let text, raw_offsets = decode_text line.text in
                 { line with text; raw_offsets })
             in
             let starting_line = line_number_at body_start - 1 in
             let lines =
               List.map local_lines ~f:(fun line ->
                 { line with
                   start = line.start + part.logical_offset + body_start
                 ; end_ = line.end_ + part.logical_offset + body_start
                 ; number = line.number + starting_line
                 })
             in
             let menus, indices = parse_menus lines in
             let node =
               Manual.Node.
                 { header = parsed_header
                 ; source_path = part.path
                 ; bytes =
                     { start = part.logical_offset + separator
                     ; end_ = part.logical_offset + segment_end
                     }
                 ; body_bytes =
                     { start = part.logical_offset + body_start
                     ; end_ = part.logical_offset + body_end
                     }
                 ; lines = line_range lines
                 ; body
                 ; body_raw_offsets
                 ; menus
                 ; xrefs = parse_xrefs lines
                 ; indices
                 ; anchors = []
                 }
             in
             node :: nodes, diagnostics))
  in
  List.rev nodes, List.rev diagnostics
;;

let encoding_of_contents contents =
  let rec loop in_local_variables = function
    | [] -> None
    | line :: rest ->
      let line = String.strip line in
      if String.Caseless.equal line "Local Variables:"
      then loop true rest
      else if in_local_variables && String.Caseless.equal line "End:"
      then loop false rest
      else if in_local_variables
      then (
        match String.lsplit2 line ~on:':' with
        | Some (name, value) when String.Caseless.equal (String.strip name) "coding" ->
          (match
             String.strip value
             |> String.take_while ~f:(fun char ->
               (not (Char.is_whitespace char)) && not (Char.equal char ';'))
           with
           | "" -> loop true rest
           | encoding -> Some encoding)
        | _ -> loop true rest)
      else loop false rest
  in
  loop false (String.split_lines contents)
;;

type tag_entry =
  | Node_tag of Info_id.Node.t * int
  | Ref_tag of string * int

let tag_entries contents =
  let rec loop in_table entries = function
    | [] -> List.rev entries
    | line :: rest ->
      let line = String.strip line in
      if String.Caseless.equal line "Tag Table:"
      then loop true entries rest
      else if in_table && String.is_prefix (String.lowercase line) ~prefix:"end tag table"
      then loop false entries rest
      else if in_table
      then (
        match String.lsplit2 line ~on:':' with
        | Some (kind, entry)
          when String.Caseless.equal (String.strip kind) "Node"
               || String.Caseless.equal (String.strip kind) "Ref" ->
          (match String.rsplit2 entry ~on:'\127' with
           | Some (name, offset) ->
             let name = String.strip name in
             (match Int.of_string_opt (String.strip offset) with
              | None -> loop true entries rest
              | Some offset when String.Caseless.equal (String.strip kind) "Ref" ->
                loop true (Ref_tag (name, offset) :: entries) rest
              | Some offset ->
                (match Info_id.Node.of_string name with
                 | Ok name -> loop true (Node_tag (name, offset) :: entries) rest
                 | Error _ -> loop true entries rest))
           | None -> loop true entries rest)
        | _ -> loop true entries rest)
      else loop false entries rest
  in
  loop false [] (String.split_lines contents)
;;

let offset_diagnostics source nodes =
  let node_offsets =
    List.fold nodes ~init:String.Map.empty ~f:(fun offsets node ->
      Map.set
        offsets
        ~key:(Info_id.Node.to_string (Manual.Node.name node))
        ~data:node.bytes.start)
  in
  List.concat_map source.Source.parts ~f:(fun part ->
    List.filter_map (tag_entries part.contents) ~f:(function
      | Ref_tag _ -> None
      | Node_tag (node, expected) ->
        (match Map.find node_offsets (Info_id.Node.to_string node) with
         | None ->
           Some
             (Manual.Diagnostic.Tagged_node_missing
                { source_path = part.path; node; expected })
         | Some actual when Int.equal expected actual -> None
         | Some actual ->
           Some
             (Manual.Diagnostic.Offset_mismatch
                { source_path = part.path; node; expected; actual }))))
;;

let recovered_ref_offset source ~name ~expected ~is_valid =
  let candidates =
    List.concat_map source.Source.parts ~f:(fun part ->
      let rec loop position offsets =
        match String.substr_index part.contents ~pos:position ~pattern:name with
        | None -> List.rev offsets
        | Some local ->
          loop
            (local + Int.max 1 (String.length name))
            ((part.logical_offset + local) :: offsets)
      in
      loop 0 [])
  in
  let compare_distance left right =
    Int.compare (Int.abs (left - expected)) (Int.abs (right - expected))
  in
  let candidates = List.filter candidates ~f:is_valid in
  let nearby =
    List.filter candidates ~f:(fun offset -> Int.abs (offset - expected) <= 4096)
  in
  List.min_elt
    (if List.is_empty nearby then candidates else nearby)
    ~compare:compare_distance
;;

let line_at_offset source ~source_path offset =
  List.find source.Source.parts ~f:(fun part -> String.equal part.path source_path)
  |> Option.map ~f:(fun part ->
    let local =
      Int.max 0 (Int.min (String.length part.contents) (offset - part.logical_offset))
    in
    1
    + String.fold (String.prefix part.contents local) ~init:0 ~f:(fun count char ->
      if Char.equal char '\n' then count + 1 else count))
;;

let attach_tag_anchors source nodes =
  let refs =
    List.concat_map source.Source.parts ~f:(fun part ->
      List.filter_map (tag_entries part.contents) ~f:(function
        | Node_tag _ -> None
        | Ref_tag (name, offset) -> Some (part.path, name, offset)))
  in
  let seen = String.Hash_set.create () in
  let duplicates, refs =
    List.fold refs ~init:([], []) ~f:(fun (duplicates, refs) ((_, name, _) as ref_) ->
      if Hash_set.mem seen name
      then Manual.Diagnostic.Duplicate_tag_identifier { name } :: duplicates, refs
      else (
        Hash_set.add seen name;
        duplicates, ref_ :: refs))
  in
  let anchors_by_node, missing =
    List.fold
      (List.rev refs)
      ~init:(String.Map.empty, [])
      ~f:(fun (by_node, missing) (source_path, name, expected) ->
        let find_node offset =
          List.find nodes ~f:(fun (node : Manual.Node.t) ->
            offset >= node.bytes.start && offset < node.bytes.end_)
        in
        let expected_node = find_node expected in
        let expected_verified = Option.is_some expected_node in
        let actual =
          if expected_verified
          then Some expected
          else
            recovered_ref_offset source ~name ~expected ~is_valid:(fun offset ->
              Option.is_some (find_node offset))
        in
        let actual, node = actual, Option.bind actual ~f:find_node in
        match actual, node with
        | _, None | None, _ ->
          ( by_node
          , Manual.Diagnostic.Tagged_ref_missing { source_path; name; expected }
            :: missing )
        | Some actual, Some node ->
          let node_name = Info_id.Node.to_string (Manual.Node.name node) in
          let anchor =
            Manual.Anchor.
              { name
              ; bytes = { start = actual; end_ = actual + 1 }
              ; line =
                  Option.value
                    (line_at_offset source ~source_path:node.source_path actual)
                    ~default:node.lines.start
              }
          in
          let missing =
            if Int.equal actual expected
            then missing
            else
              Manual.Diagnostic.Ref_offset_mismatch
                { source_path; name; expected; actual }
              :: missing
          in
          ( Map.update by_node node_name ~f:(function
              | None -> [ anchor ]
              | Some anchors -> anchor :: anchors)
          , missing ))
  in
  let nodes =
    List.map nodes ~f:(fun node ->
      let name = Info_id.Node.to_string (Manual.Node.name node) in
      let anchors =
        Map.find anchors_by_node name |> Option.value ~default:[] |> List.rev
      in
      { node with anchors })
  in
  nodes, List.rev_append duplicates (List.rev missing)
;;

let parse (source : Source.t) =
  let main = List.hd_exn source.parts in
  let encoding = encoding_of_contents main.contents in
  let decode_text, unsupported_encoding = decoder_of_encoding encoding in
  let nodes, diagnostics =
    List.fold source.Source.parts ~init:([], []) ~f:(fun (nodes, diagnostics) part ->
      let part_nodes, part_diagnostics = parse_part ~decode_text part in
      nodes @ part_nodes, diagnostics @ part_diagnostics)
  in
  match nodes with
  | [] -> Error (No_nodes { source_path = source.main_path })
  | _ ->
    let nodes, anchor_diagnostics = attach_tag_anchors source nodes in
    let diagnostics =
      diagnostics @ offset_diagnostics source nodes @ anchor_diagnostics
    in
    let diagnostics =
      match unsupported_encoding with
      | None -> diagnostics
      | Some encoding ->
        diagnostics
        @ [ Manual.Diagnostic.Unsupported_encoding
              { source_path = source.main_path; encoding }
          ]
    in
    let first_separator = String.index main.contents '\031' |> Option.value ~default:0 in
    let preamble =
      if first_separator = 0
      then None
      else Some (String.prefix main.contents first_separator)
    in
    Ok (Manual.create ~id:source.manual ~source ~encoding ~preamble ~nodes ~diagnostics)
;;

let%expect_test "nodes, menus, xrefs, and locations are parsed deterministically" =
  let separator = Char.to_string '\031' in
  let node_contents =
    String.concat
      [ "fixture preamble\nLocal Variables:\ncoding: utf-8\nEnd:\n"
      ; separator
      ; "\nFile: sample.info, Node: Top, Next: First, Up: (dir)\n"
      ; "Sample manual.\n\n* Menu:\n* First:: The first chapter.\n"
      ; separator
      ; "\nFile: sample.info, Node: First, Prev: Top, Up: Top\n"
      ; "A deterministic needle with fixture-anchor.  See *Note Top::.\n"
      ]
  in
  let anchor_offset = String.substr_index_exn node_contents ~pattern:"fixture-anchor" in
  let contents =
    String.concat
      [ node_contents
      ; separator
      ; sprintf "\nTag Table:\nRef: fixture-anchor\127%d\n" anchor_offset
      ; separator
      ; "\nEnd Tag Table\n"
      ]
  in
  let manual_id = Info_id.Manual.of_string_exn "sample" in
  let source =
    Source.
      { manual = manual_id
      ; main_path = "sample.info"
      ; parts = [ Part.{ path = "sample.info"; contents; logical_offset = 0 } ]
      }
  in
  let manual =
    match parse source with
    | Ok manual -> manual
    | Error error -> raise_s [%message "fixture parse failed" (error : error)]
  in
  printf
    "encoding=%s nodes=%d anchors=%d diagnostics=%d\n"
    (Option.value (Manual.encoding manual) ~default:"none")
    (List.length (Manual.nodes manual))
    (List.length (Manual.anchors manual))
    (List.length (Manual.diagnostics manual));
  List.iter (Manual.nodes manual) ~f:(fun node ->
    printf
      "%s menus=%d xrefs=%d bytes=%d:%d\n"
      (Info_id.Node.to_string (Manual.Node.name node))
      (List.length node.menus)
      (List.length node.xrefs)
      node.bytes.start
      node.bytes.end_);
  [%expect
    {|
    encoding=utf-8 nodes=2 anchors=1 diagnostics=0
    Top menus=1 xrefs=0 bytes=53:161
    First menus=0 xrefs=1 bytes=161:276
    |}]
;;

let parse_fixture_exn contents =
  let source =
    Source.
      { manual = Info_id.Manual.of_string_exn "fixture"
      ; main_path = "fixture.info"
      ; parts = [ Part.{ path = "fixture.info"; contents; logical_offset = 0 } ]
      }
  in
  match parse source with
  | Ok manual -> manual
  | Error error -> raise_s [%message "fixture parse failed" (error : error)]
;;

let%expect_test "DEL quoting preserves trailing target punctuation" =
  let manual =
    parse_fixture_exn
      ("\031\nFile: fixture.info, Node: Top, Next: \127Ends.\127, Up: (dir)\nBody\n"
       ^ "\031\nFile: fixture.info, Node: \127Ends.\127, Prev: Top, Up: Top\nDone\n")
  in
  let top = Manual.top manual |> Option.value_exn in
  print_s [%sexp (top.header.next : Info_id.Target.t option)];
  [%expect {| (((manual ()) (node Ends.))) |}]
;;

let%expect_test "multiline xrefs and menu termination retain structure" =
  let manual =
    parse_fixture_exn
      ("\031\nFile: fixture.info, Node: Indexing, Up: (dir)\n"
       ^ "* Menu:\n* Child:: A child.\n\nNarrative follows.\n"
       ^ "See *Note Conditional Subdirectories:\n"
       ^ " (automake)Conditional Subdirectories. for details.\n")
  in
  let node = Manual.top manual |> Option.value_exn in
  printf
    "menus=%d indices=%d xrefs=%d\n"
    (List.length node.menus)
    (List.length node.indices)
    (List.length node.xrefs);
  List.iter node.xrefs ~f:(fun xref ->
    printf
      "%s -> %s lines=%d:%d\n"
      xref.label
      (Info_id.Target.to_string xref.target)
      xref.lines.start
      xref.lines.end_);
  [%expect
    {|
    menus=1 indices=0 xrefs=1
    Conditional Subdirectories -> (automake)Conditional Subdirectories lines=7:8
    |}]
;;

let%expect_test "Latin-1 bodies decode to UTF-8 with raw byte mapping" =
  let manual =
    parse_fixture_exn
      ("Local Variables:\ncoding: latin-1\nEnd:\n\031\n"
       ^ "File: fixture.info, Node: Top, Up: (dir)\n"
       ^ "* Menu:\n* Caf\233:: d\233sc.\n\ncaf\233 marker\n")
  in
  let node = Manual.top manual |> Option.value_exn in
  printf
    "encoding=%s body=%S utf8-offset=%d raw-offset=%d diagnostics=%d\n"
    (Manual.encoding manual |> Option.value_exn)
    node.body
    (String.substr_index_exn node.body ~pattern:"marker")
    node.body_raw_offsets.(String.substr_index_exn node.body ~pattern:"marker")
    (List.length (Manual.diagnostics manual));
  let menu = List.hd_exn node.menus in
  printf "menu=%s description=%s\n" menu.label menu.description;
  [%expect
    {|
    encoding=latin-1 body="* Menu:\n* Caf\195\169:: d\195\169sc.\n\ncaf\195\169 marker\n" utf8-offset=32 raw-offset=29 diagnostics=0
    menu=Café description=désc.
    |}]
;;

let%expect_test "unsupported encoding is an observable coverage diagnostic" =
  let manual =
    parse_fixture_exn
      ("Local Variables:\ncoding: koi8-r\nEnd:\n\031\n"
       ^ "File: fixture.info, Node: Top, Up: (dir)\nBody\n")
  in
  print_s [%sexp (Manual.diagnostics manual : Manual.Diagnostic.t list)];
  [%expect {| ((Unsupported_encoding (source_path fixture.info) (encoding koi8-r))) |}]
;;

let%expect_test "ordinary prose containing coding colon is not an encoding declaration" =
  let manual =
    parse_fixture_exn
      "\031\n\
       File: fixture.info, Node: Top, Up: (dir)\n\
       Working on coding: Download files.\n"
  in
  printf
    "encoding=%s diagnostics=%d\n"
    (Option.value (Manual.encoding manual) ~default:"none")
    (List.length (Manual.diagnostics manual));
  [%expect {| encoding=none diagnostics=0 |}]
;;

let%expect_test "bad ref offsets recover to an exact node and line" =
  let contents =
    "\031\nFile: fixture.info, Node: Top, Up: (dir)\nfirst\nfixture-anchor here\n"
    ^ "\031\nTag Table:\nRef: fixture-anchor\1279999\n"
    ^ "\031\nEnd Tag Table\n"
  in
  let manual = parse_fixture_exn contents in
  let anchor = Manual.anchors manual |> List.hd_exn in
  printf "anchor=%s line=%d byte=%d\n" anchor.name anchor.line anchor.bytes.start;
  print_s [%sexp (Manual.diagnostics manual : Manual.Diagnostic.t list)];
  [%expect
    {|
    anchor=fixture-anchor line=4 byte=49
    ((Ref_offset_mismatch (source_path fixture.info) (name fixture-anchor)
      (expected 9999) (actual 49)))
    |}]
;;
