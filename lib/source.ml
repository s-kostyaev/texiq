open! Core

module Part = struct
  type t =
    { path : string
    ; contents : string
    ; logical_offset : int
    }
  [@@deriving sexp_of]
end

type t =
  { manual : Info_id.Manual.t
  ; main_path : string
  ; parts : Part.t list
  }
[@@deriving sexp_of]

type error =
  | Not_found of
      { requested : string
      ; searched : string list
      }
  | Compression_error of Compression.error
  | Invalid_indirect_entry of
      { path : string
      ; line : string
      }
  | Too_many_indirect_parts of
      { path : string
      ; count : int
      ; max_parts : int
      }
[@@deriving sexp_of]

let file_exists path = Stdlib.Sys.file_exists path && not (Stdlib.Sys.is_directory path)
let max_indirect_parts = 4096

let candidate_names requested =
  if String.is_suffix requested ~suffix:".gz"
  then [ requested ]
  else if
    String.is_suffix requested ~suffix:".info"
    || String.is_suffix requested ~suffix:"-info"
    || String.is_suffix requested ~suffix:".inf"
  then [ requested; requested ^ ".gz" ]
  else
    List.concat_map
      [ requested; requested ^ ".info"; requested ^ "-info"; requested ^ ".inf" ]
      ~f:(fun path -> [ path; path ^ ".gz" ])
;;

let resolve_path ~directories requested =
  let has_directory = not (String.equal (Filename.basename requested) requested) in
  let candidates =
    if Filename.is_absolute requested || has_directory || file_exists requested
    then candidate_names requested
    else
      List.concat_map directories ~f:(fun directory ->
        List.map (candidate_names requested) ~f:(Filename.concat directory))
  in
  match List.find candidates ~f:file_exists with
  | Some path -> Ok path
  | None -> Error (Not_found { requested; searched = candidates })
;;

let indirect_entries ~path contents =
  let lines = String.split_lines contents in
  let rec seek = function
    | [] -> Ok []
    | line :: rest ->
      if String.equal (String.strip line) "Indirect:" then parse [] rest else seek rest
  and parse entries = function
    | [] -> Ok (List.rev entries)
    | line :: rest ->
      let stripped = String.strip line in
      if
        String.is_empty stripped
        || String.is_prefix stripped ~prefix:"Tag Table:"
        || String.is_prefix stripped ~prefix:"End Tag Table"
        || String.is_prefix stripped ~prefix:"\031"
      then Ok (List.rev entries)
      else (
        match String.rsplit2 stripped ~on:':' with
        | Some (filename, offset) ->
          (match Int.of_string_opt (String.strip offset) with
           | Some offset -> parse ((String.strip filename, offset) :: entries) rest
           | None -> Error (Invalid_indirect_entry { path; line }))
        | None -> Error (Invalid_indirect_entry { path; line }))
  in
  seek lines
;;

let load_part ?max_bytes ~logical_offset path =
  Result.map_error (Compression.read_file ?max_bytes path) ~f:(fun error ->
    Compression_error error)
  |> Result.map ~f:(fun contents -> Part.{ path; contents; logical_offset })
;;

let load ?max_bytes ~directories requested =
  let open Result.Let_syntax in
  let max_bytes = Option.value max_bytes ~default:Compression.default_max_bytes in
  let%bind main_path = resolve_path ~directories requested in
  let%bind main = load_part ~max_bytes ~logical_offset:0 main_path in
  let%bind indirect = indirect_entries ~path:main_path main.contents in
  let%bind () =
    if List.length indirect <= max_indirect_parts
    then Ok ()
    else
      Error
        (Too_many_indirect_parts
           { path = main_path
           ; count = List.length indirect
           ; max_parts = max_indirect_parts
           })
  in
  let directory = Filename.dirname main_path in
  let%bind _, fragments_rev =
    List.fold_result
      indirect
      ~init:(max_bytes - String.length main.contents, [])
      ~f:(fun (remaining, fragments) (filename, logical_offset) ->
        let path = Filename.concat directory filename in
        let path =
          if file_exists path || String.is_suffix path ~suffix:".gz"
          then path
          else if file_exists (path ^ ".gz")
          then path ^ ".gz"
          else path
        in
        let%map part = load_part ~max_bytes:remaining ~logical_offset:0 path in
        let first_node_local =
          String.index part.contents '\031' |> Option.value ~default:0
        in
        ( remaining - String.length part.contents
        , { part with logical_offset = logical_offset - first_node_local } :: fragments ))
  in
  let fragments = List.rev fragments_rev in
  let manual_name =
    let basename = Filename.basename main_path in
    let basename =
      Option.value (String.chop_suffix basename ~suffix:".gz") ~default:basename
    in
    List.find_map [ ".info"; "-info"; ".inf" ] ~f:(fun suffix ->
      String.chop_suffix basename ~suffix)
    |> Option.value ~default:basename
  in
  let%map manual =
    Info_id.Manual.of_string manual_name
    |> Result.map_error ~f:(fun error ->
      Invalid_indirect_entry { path = main_path; line = Error.to_string_hum error })
  in
  { manual; main_path; parts = main :: fragments }
;;

let manual t = t.manual
let main_path t = t.main_path
let parts t = t.parts

let%expect_test "manual candidate order follows Info conventions" =
  candidate_names "sample" |> List.iter ~f:print_endline;
  [%expect
    {|
    sample
    sample.gz
    sample.info
    sample.info.gz
    sample-info
    sample-info.gz
    sample.inf
    sample.inf.gz
    |}]
;;

let%expect_test "split parts retain declared logical offsets" =
  let main_path = Stdlib.Filename.temp_file "texiq-info-split" ".info" in
  let part_path = main_path ^ "-1" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all part_path ~data:"fragment";
      Out_channel.write_all
        main_path
        ~data:(sprintf "Indirect:\n%s: 1024\nTag Table:\n" (Filename.basename part_path));
      match load ~directories:[] main_path with
      | Error error -> print_s [%sexp (error : error)]
      | Ok source ->
        List.iter source.parts ~f:(fun part ->
          printf
            "%s offset=%d\n"
            (if String.equal part.path main_path then "main" else "part")
            part.logical_offset))
    ~finally:(fun () ->
      List.iter [ main_path; part_path ] ~f:(fun path ->
        if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path));
  [%expect
    {|
    main offset=0
    part offset=1024
    |}]
;;

let%expect_test "split manual expansion limit is aggregate" =
  let main_path = Stdlib.Filename.temp_file "texiq-info-budget" ".info" in
  let part_paths = List.map [ "-1"; "-2" ] ~f:(( ^ ) main_path) in
  Exn.protect
    ~f:(fun () ->
      List.iter part_paths ~f:(fun path -> Out_channel.write_all path ~data:"12345678");
      let main_contents =
        sprintf
          "Indirect:\n%s: 100\n%s: 200\nTag Table:\n"
          (Filename.basename (List.nth_exn part_paths 0))
          (Filename.basename (List.nth_exn part_paths 1))
      in
      Out_channel.write_all main_path ~data:main_contents;
      match
        load ~max_bytes:(String.length main_contents + 8) ~directories:[] main_path
      with
      | Error (Compression_error (Compression.Limit_exceeded _)) ->
        print_endline "aggregate-limit-exceeded"
      | result -> print_s [%sexp (result : (t, error) Result.t)])
    ~finally:(fun () ->
      List.iter (main_path :: part_paths) ~f:(fun path ->
        if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path));
  [%expect {| aggregate-limit-exceeded |}]
;;

let%expect_test "indirect part count is bounded before fragment I/O" =
  let main_path = Stdlib.Filename.temp_file "texiq-info-parts" ".info" in
  Exn.protect
    ~f:(fun () ->
      let entries =
        List.init (max_indirect_parts + 1) ~f:(fun index ->
          sprintf "part-%d: %d" index index)
        |> String.concat ~sep:"\n"
      in
      Out_channel.write_all main_path ~data:("Indirect:\n" ^ entries ^ "\nTag Table:\n");
      match load ~directories:[] main_path with
      | Error (Too_many_indirect_parts { count; max_parts; _ }) ->
        printf "count=%d max=%d\n" count max_parts
      | result -> print_s [%sexp (result : (t, error) Result.t)])
    ~finally:(fun () ->
      if Stdlib.Sys.file_exists main_path then Stdlib.Sys.remove main_path);
  [%expect {| count=4097 max=4096 |}]
;;
