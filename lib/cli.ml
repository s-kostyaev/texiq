open! Core

let format_type =
  Command.Arg_type.of_alist_exn [ "text", Render.Text; "json", Json; "jsonl", Jsonl ]
;;

let print_outcome (outcome : Engine.outcome) =
  Option.iter outcome.stdout ~f:(fun output ->
    Out_channel.output_string Out_channel.stdout output;
    if not (String.is_suffix output ~suffix:"\n")
    then Out_channel.output_char Out_channel.stdout '\n');
  List.iter outcome.stderr ~f:(fun line -> eprintf "%s\n" line);
  if not (Int.equal outcome.exit_status 0) then Stdlib.exit outcome.exit_status
;;

let command =
  Command.basic
    ~summary:"Query GNU Info manuals without reading entire contents"
    ~readme:(fun () ->
      "With no SCOPE, texiq queries the merged (dir)Top catalog. Use a manual name or \
       explicit path to query one manual.")
    (let%map_open.Command positional = anon (sequence ("SCOPE [QUERY]" %: string))
     and directories =
       flag
         "--directory"
         (listed string)
         ~aliases:[ "-d" ]
         ~doc:"DIR Prepend an Info search directory (repeatable)."
     and strict = flag "--strict" no_arg ~doc:" Fail on incomplete parse coverage."
     and format =
       flag
         "--format"
         (optional_with_default Render.Text format_type)
         ~doc:"FORMAT Output format: text, json, or jsonl (default text)."
     and raw_output =
       flag "--raw-output" no_arg ~doc:" Emit scalar strings without framing."
     and max_results =
       flag
         "--max-results"
         (optional_with_default 50 int)
         ~doc:"N Maximum collection items rendered (default 50)."
     and all_results =
       flag "--all-results" no_arg ~doc:" Disable the result rendering cap."
     in
     fun () ->
       if (not all_results) && max_results < 0
       then (
         eprintf "Error[E_USAGE]: --max-results must be non-negative\n";
         Stdlib.exit 1);
       if raw_output && not (Render.equal_format format Render.Text)
       then (
         eprintf "Error[E_USAGE]: --raw-output requires --format text\n";
         Stdlib.exit 1);
       let scope, query =
         match positional with
         | [] -> None, None
         | [ scope ] -> Some scope, None
         | [ scope; query ] -> Some scope, Some query
         | _ ->
           eprintf "Error[E_USAGE]: expected at most SCOPE and QUERY\n";
           Stdlib.exit 1
       in
       let max_results = if all_results then None else Some max_results in
       Engine.execute
         { scope; query; directories; strict; format; raw_output; max_results }
       |> print_outcome)
;;
