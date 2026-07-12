open! Core

let command =
  Command.basic ~summary:Texiq.summary
    (let%map_open.Command () = return () in
     fun () -> print_endline "texiq: architecture bootstrap")
;;

let () = Command_unix.run command
