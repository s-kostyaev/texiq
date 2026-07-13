open! Core

let us = Char.of_int_exn 31 |> String.of_char

let with_manual f =
  let path = Stdlib.Filename.temp_file "texiq-integration" ".info" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        path
        ~data:
          ("fixture preamble\n"
           ^ us
           ^ "\nFile: fixture.info,  Node: Top,  Next: Child,  Up: (dir)\n"
           ^ "Fixture top.\n\n* Menu:\n* Child:: Details.\n"
           ^ us
           ^ "\nFile: fixture.info,  Node: Child,  Prev: Top,  Up: Top\n"
           ^ "A deterministic integration needle.\n");
      f path)
    ~finally:(fun () -> if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path)
;;

let request path query =
  Texiq.Engine.
    { scope = Some path
    ; query = Some query
    ; directories = []
    ; emacs = false
    ; strict = false
    ; format = Texiq.Render.Text
    ; raw_output = false
    ; max_results = Some 50
    }
;;

let%expect_test "manual discover narrow extract workflow" =
  with_manual (fun path ->
    let nodes = Texiq.Engine.execute (request path ".nodes | map(.name)") in
    printf "exit=%d\n%s\n" nodes.exit_status (Option.value_exn nodes.stdout);
    let text = Texiq.Engine.execute (request path ".node(\"Child\") | .text") in
    printf "exit=%d\n%s\n" text.exit_status (Option.value_exn text.stdout));
  [%expect
    {|
    exit=0
    - Top
    - Child
    exit=0
    A deterministic integration needle.
    |}]
;;

let%expect_test "query failure is classified and actionable" =
  with_manual (fun path ->
    let outcome = Texiq.Engine.execute (request path ".node(\"Missing\") | .text") in
    printf "exit=%d\n" outcome.exit_status;
    printf
      "has-code=%b\nhas-hint=%b\n"
      (List.exists outcome.stderr ~f:(String.is_substring ~substring:"E_NODE_NOT_FOUND"))
      (List.exists
         outcome.stderr
         ~f:(String.is_substring ~substring:".nodes | map(.name)")));
  [%expect
    {|
    exit=1
    has-code=true
    has-hint=true
    |}]
;;

let%expect_test "malformed input corpus never escapes the typed parser boundary" =
  let random = Random.State.make [| 0x746578; 0x6971 |] in
  for case = 0 to 199 do
    let length = Random.State.int random 512 in
    let contents =
      String.init length ~f:(fun _ -> Char.of_int_exn (Random.State.int random 128))
    in
    let source =
      Texiq.Source.
        { manual = Texiq.Info_id.Manual.of_string_exn "fuzz"
        ; main_path = sprintf "fuzz-%d.info" case
        ; parts = [ Part.{ path = "fuzz.info"; contents; logical_offset = 0 } ]
        }
    in
    ignore
      (Texiq.Info_parser.parse source
       : (Texiq.Manual.t, Texiq.Info_parser.error) Result.t)
  done;
  print_endline "cases=200 escaped_exceptions=0";
  [%expect {| cases=200 escaped_exceptions=0 |}]
;;

let%expect_test "strict mode turns recovered tag mismatch into exit 3" =
  let path = Stdlib.Filename.temp_file "texiq-strict" ".info" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        path
        ~data:
          (us
           ^ "\nFile: strict.info, Node: Top, Up: (dir)\nBody.\n"
           ^ us
           ^ "\nTag Table:\nNode: Top\127999\n"
           ^ us
           ^ "\nEnd Tag Table\n");
      let outcome =
        Texiq.Engine.execute { (request path ".summary") with strict = true }
      in
      printf
        "exit=%d warning=%b\n"
        outcome.exit_status
        (List.exists outcome.stderr ~f:(String.is_substring ~substring:"Offset_mismatch")))
    ~finally:(fun () -> if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path);
  [%expect {| exit=3 warning=true |}]
;;

let%expect_test "global catalog search scans registered manuals in stable order" =
  let directory = Core_unix.mkdtemp "/tmp/texiq-catalog-XXXXXX" in
  let paths = List.map [ "dir"; "one.info"; "two.info" ] ~f:(Filename.concat directory) in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        (List.nth_exn paths 0)
        ~data:
          "File: dir, Node: Top\n\n\
           * Menu:\n\n\
           Tests\n\
           * Two: (two). Second.\n\
           * One: (one). First.\n";
      List.iteri [ "one"; "two" ] ~f:(fun index name ->
        Out_channel.write_all
          (List.nth_exn paths (index + 1))
          ~data:
            (us
             ^ sprintf "\nFile: %s.info, Node: Top, Up: (dir)\n" name
             ^ sprintf "unique-global-needle in %s\n" name));
      let outcome =
        Texiq.Engine.execute
          { scope = Some "dir"
          ; query = Some ".search(\"unique-global-needle\") | map(.manual)"
          ; directories = [ directory ]
          ; emacs = false
          ; strict = false
          ; format = Texiq.Render.Text
          ; raw_output = false
          ; max_results = Some 50
          }
      in
      printf "exit=%d\n%s\n" outcome.exit_status (Option.value_exn outcome.stdout))
    ~finally:(fun () ->
      List.iter paths ~f:(fun path ->
        if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path);
      Core_unix.rmdir directory);
  [%expect
    {|
    exit=0
    - one
    - two
    |}]
;;

let%expect_test "default surfaces expose catalog entries and a manual Top menu" =
  let directory = Core_unix.mkdtemp "/tmp/texiq-default-XXXXXX" in
  let dir_path = Filename.concat directory "dir" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        dir_path
        ~data:"File: dir, Node: Top\n\n* Menu:\n\nTests\n* Fixture: (fixture). Demo.\n";
      let catalog =
        Texiq.Engine.execute
          { scope = Some "dir"
          ; query = None
          ; directories = [ directory ]
          ; emacs = false
          ; strict = false
          ; format = Texiq.Render.Text
          ; raw_output = false
          ; max_results = Some 50
          }
      in
      printf
        "catalog-entry=%b\n"
        (Option.value_exn catalog.stdout
         |> String.is_substring ~substring:"manual=fixture");
      with_manual (fun path ->
        let manual =
          Texiq.Engine.execute { (request path ".summary") with query = None }
        in
        printf
          "manual-menu=%b\n"
          (Option.value_exn manual.stdout |> String.is_substring ~substring:"label=Child")))
    ~finally:(fun () ->
      if Stdlib.Sys.file_exists dir_path then Stdlib.Sys.remove dir_path;
      Core_unix.rmdir directory);
  [%expect
    {|
    catalog-entry=true
    manual-menu=true
    |}]
;;

let%expect_test "strict catalog resolution failures keep exit class 2" =
  let directory = Core_unix.mkdtemp "/tmp/texiq-strict-catalog-XXXXXX" in
  let dir_path = Filename.concat directory "dir" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        dir_path
        ~data:"File: dir, Node: Top\n\n* Menu:\n\nTests\n* Fixture: (fixture). Demo.\n";
      let outcome =
        Texiq.Engine.execute
          { scope = Some "dir"
          ; query = Some ".summary"
          ; directories = [ "/definitely/not/a/texiq/info/path"; directory ]
          ; emacs = false
          ; strict = true
          ; format = Texiq.Render.Text
          ; raw_output = false
          ; max_results = Some 50
          }
      in
      printf
        "exit=%d has-hint=%b\n"
        outcome.exit_status
        (List.exists outcome.stderr ~f:(String.is_substring ~substring:"Hint:")))
    ~finally:(fun () ->
      if Stdlib.Sys.file_exists dir_path then Stdlib.Sys.remove dir_path;
      Core_unix.rmdir directory);
  [%expect {| exit=2 has-hint=true |}]
;;
