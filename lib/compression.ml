open! Core

type error =
  | Io_error of
      { path : string
      ; message : string
      }
  | Malformed_compression of
      { path : string
      ; message : string
      }
  | Limit_exceeded of
      { path : string
      ; max_bytes : int
      }
[@@deriving sexp_of]

let default_max_bytes = 256 * 1024 * 1024
let is_gzip path = String.is_suffix (String.lowercase path) ~suffix:".gz"

let uncompress_gzip ~path ~max_bytes input =
  let output = Bigarray.Array1.create Bigarray.char Bigarray.c_layout Gz.io_buffer_size in
  let result = Buffer.create (Int.min max_bytes 4096) in
  let append decoder =
    let length = Gz.io_buffer_size - Gz.Inf.dst_rem decoder in
    if length > max_bytes - Buffer.length result
    then Error (Limit_exceeded { path; max_bytes })
    else (
      for index = 0 to length - 1 do
        Buffer.add_char result output.{index}
      done;
      Ok ())
  in
  let rec loop decoder =
    match Gz.Inf.decode decoder with
    | `Await _ ->
      Error
        (Malformed_compression
           { path; message = "gzip decoder unexpectedly requested more string input" })
    | `Malformed message -> Error (Malformed_compression { path; message })
    | `Flush decoder ->
      Result.bind (append decoder) ~f:(fun () -> loop (Gz.Inf.flush decoder))
    | `End decoder -> Result.map (append decoder) ~f:(fun () -> Buffer.contents result)
  in
  loop (Gz.Inf.decoder (`String input) ~o:output)
;;

let read_file ?(max_bytes = default_max_bytes) path =
  try
    In_channel.with_file path ~f:(fun channel ->
      let length = In_channel.length channel in
      if Int64.(length > of_int max_bytes)
      then Error (Limit_exceeded { path; max_bytes })
      else (
        let input = In_channel.input_all channel in
        if is_gzip path then uncompress_gzip ~path ~max_bytes input else Ok input))
  with
  | exn -> Error (Io_error { path; message = Exn.to_string exn })
;;

let%expect_test "bounded gzip decompression" =
  let path = Stdlib.Filename.temp_file "texiq-gzip" ".info.gz" in
  Exn.protect
    ~f:(fun () ->
      Out_channel.write_all
        path
        ~data:
          "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\xcb\x48\xcd\xc9\xc9\x57\x48\xaf\xca\x2c\xe0\x02\x00\x39\x7c\x63\x56\x0b\x00\x00\x00";
      (match read_file path with
       | Ok value -> printf "ok=%S\n" value
       | Error error -> print_s [%sexp (error : error)]);
      match read_file ~max_bytes:5 path with
      | Error (Limit_exceeded _) -> print_endline "limit-exceeded"
      | result -> print_s [%sexp (result : (string, error) Result.t)])
    ~finally:(fun () -> if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path);
  [%expect
    {|
    ok="hello gzip\n"
    limit-exceeded
    |}]
;;
