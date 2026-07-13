open! Core

type error =
  | Client_failed of
      { program : string
      ; status : string
      ; output : string
      }
  | Invalid_output of
      { output : string
      ; reason : string
      }
[@@deriving sexp_of]

let expression =
  "(progn (require 'info) (mapconcat (lambda (directory) (mapconcat (lambda (byte) \
   (format \"%02x\" byte)) (string-to-list (encode-coding-string directory 'utf-8)) \
   \"\")) Info-directory-list \"\\n\"))"
;;

let bounded_output output =
  let max_length = 4096 in
  if String.length output <= max_length
  then output
  else String.prefix output max_length ^ "..."
;;

let decode_nibble = function
  | '0' .. '9' as character -> Ok (Char.to_int character - Char.to_int '0')
  | 'a' .. 'f' as character -> Ok (10 + Char.to_int character - Char.to_int 'a')
  | 'A' .. 'F' as character -> Ok (10 + Char.to_int character - Char.to_int 'A')
  | character -> Or_error.errorf "invalid hexadecimal character %C" character
;;

let decode_hex encoded =
  let open Or_error.Let_syntax in
  if Int.rem (String.length encoded) 2 <> 0
  then Or_error.error_string "hexadecimal path has odd length"
  else
    List.init
      (String.length encoded / 2)
      ~f:(fun index ->
        let%bind high = decode_nibble encoded.[index * 2] in
        let%map low = decode_nibble encoded.[(index * 2) + 1] in
        Char.of_int_exn ((high * 16) + low))
    |> Or_error.all
    |> Or_error.map ~f:String.of_char_list
;;

let parse_output output =
  let stripped = String.strip output in
  let invalid reason =
    Error (Invalid_output { output = bounded_output stripped; reason })
  in
  if
    String.length stripped < 2
    || (not (Char.equal stripped.[0] '"'))
    || not (Char.equal stripped.[String.length stripped - 1] '"')
  then invalid "emacsclient did not return a Lisp string"
  else (
    let encoded = String.sub stripped ~pos:1 ~len:(String.length stripped - 2) in
    if String.is_empty encoded
    then Ok []
    else
      String.substr_replace_all encoded ~pattern:"\\n" ~with_:"\n"
      |> String.split_lines
      |> List.map ~f:(fun path ->
        decode_hex path
        |> Result.map_error ~f:(fun error ->
          Invalid_output
            { output = bounded_output stripped; reason = Error.to_string_hum error }))
      |> Result.all)
;;

let run ~program =
  try
    let process =
      Core_unix.create_process
        ~prog:program
        ~args:[ "--quiet"; "--timeout=5"; "--eval"; expression ]
    in
    Core_unix.close process.stdin;
    let stdout_channel = Core_unix.in_channel_of_descr process.stdout in
    let stderr_channel = Core_unix.in_channel_of_descr process.stderr in
    let stdout = In_channel.input_all stdout_channel in
    let stderr = In_channel.input_all stderr_channel in
    In_channel.close stdout_channel;
    In_channel.close stderr_channel;
    let status = Core_unix.waitpid process.pid in
    status, stdout, stderr
  with
  | exn ->
    ( Error (`Exit_non_zero 127)
    , ""
    , sprintf "unable to start or read %s: %s" program (Exn.to_string exn) )
;;

let directories ?(program = "emacsclient") () =
  let status, stdout, stderr = run ~program in
  match status with
  | Ok () -> parse_output stdout
  | Error _ ->
    let output = if String.is_empty (String.strip stderr) then stdout else stderr in
    Error
      (Client_failed
         { program
         ; status = Core_unix.Exit_or_signal.to_string_hum status
         ; output = bounded_output (String.strip output)
         })
;;

let%expect_test "hex-encoded Emacs directories are decoded without path ambiguity" =
  let result =
    parse_output "\"2f746d702f696e666f\\n2f55736572732f656d61637320696e666f\""
  in
  print_s ([%sexp_of: (string list, error) Result.t] result);
  [%expect {| (Ok (/tmp/info "/Users/emacs info")) |}]
;;

let%expect_test "malformed emacsclient output remains a typed error" =
  let result = parse_output "not-a-lisp-string" in
  print_s ([%sexp_of: (string list, error) Result.t] result);
  [%expect
    {|
    (Error
     (Invalid_output (output not-a-lisp-string)
      (reason "emacsclient did not return a Lisp string")))
    |}]
;;
