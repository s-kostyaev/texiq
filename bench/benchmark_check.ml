open! Core

let separator = Char.of_int_exn 31 |> String.of_char

let synthetic_manual node_count =
  let buffer = Buffer.create (node_count * 100) in
  Buffer.add_string buffer "texiq synthetic benchmark\n";
  for index = 0 to node_count - 1 do
    let name = if Int.equal index 0 then "Top" else sprintf "Node %d" index in
    let up = if Int.equal index 0 then "(dir)" else "Top" in
    Buffer.add_string buffer separator;
    Buffer.add_string
      buffer
      (sprintf "\nFile: benchmark.info, Node: %s, Up: %s\n" name up);
    Buffer.add_string buffer (sprintf "Deterministic benchmark body %d.\n" index)
  done;
  Buffer.contents buffer
;;

let parse_once contents =
  let source =
    Texiq.Source.
      { manual = Texiq.Info_id.Manual.of_string_exn "benchmark"
      ; main_path = "benchmark.info"
      ; parts = [ Part.{ path = "benchmark.info"; contents; logical_offset = 0 } ]
      }
  in
  match Texiq.Info_parser.parse source with
  | Ok manual -> List.length (Texiq.Manual.nodes manual)
  | Error error ->
    raise_s [%message "benchmark parse failed" (error : Texiq.Info_parser.error)]
;;

let command =
  Command.basic
    ~summary:"Run a deterministic texiq parser benchmark"
    (let%map_open.Command nodes =
       flag "-nodes" (optional_with_default 5_000 int) ~doc:"N Synthetic node count"
     and iterations =
       flag "-iterations" (optional_with_default 5 int) ~doc:"N Parse iterations"
     in
     fun () ->
       let contents = synthetic_manual nodes in
       let start = Time_ns.now () in
       let parsed = ref 0 in
       for _ = 1 to iterations do
         parsed := parse_once contents
       done;
       let elapsed = Time_ns.diff (Time_ns.now ()) start in
       printf
         "nodes=%d iterations=%d input_bytes=%d elapsed_ms=%.3f\n"
         !parsed
         iterations
         (String.length contents)
         (Time_ns.Span.to_ms elapsed))
;;

let () = Command_unix.run command
