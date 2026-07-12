open! Core

type error =
  { position : int
  ; message : string
  ; hint : string option
  }
[@@deriving sexp_of]

type token_kind =
  | Dot
  | Ident of string
  | String of string
  | Int of int
  | True
  | False
  | Null
  | Lparen
  | Rparen
  | Lbracket
  | Rbracket
  | Comma
  | Colon
  | Pipe
  | Equal
  | Not_equal
  | Less
  | Less_or_equal
  | Greater
  | Greater_or_equal
  | And
  | Or
  | Eof
[@@deriving sexp_of]

type token =
  { kind : token_kind
  ; position : int
  }
[@@deriving sexp_of]

let render_error { position; message; hint } =
  let base = sprintf "Error[E_QUERY_PARSE] at byte %d: %s" position message in
  Option.value_map hint ~default:base ~f:(fun hint -> base ^ "\nHint: " ^ hint)
;;

let lex input =
  let length = String.length input in
  let error ?hint position message = Error { position; message; hint } in
  let rec string_literal quote start index buffer =
    if index >= length
    then error start "unterminated string literal" ~hint:"close the quoted string"
    else (
      match input.[index] with
      | c when Char.equal c quote -> Ok (Buffer.contents buffer, index + 1)
      | '\\' when index + 1 >= length ->
        error index "unterminated escape sequence" ~hint:"add the escaped character"
      | '\\' ->
        let escaped =
          match input.[index + 1] with
          | 'n' -> '\n'
          | 'r' -> '\r'
          | 't' -> '\t'
          | '\\' -> '\\'
          | '\'' -> '\''
          | '"' -> '"'
          | other -> other
        in
        Buffer.add_char buffer escaped;
        string_literal quote start (index + 2) buffer
      | c ->
        Buffer.add_char buffer c;
        string_literal quote start (index + 1) buffer)
  in
  let is_ident_start = function
    | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
    | _ -> false
  in
  let is_ident_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  let rec scan index reversed =
    if index >= length
    then Ok (List.rev ({ kind = Eof; position = length } :: reversed) |> Array.of_list)
    else (
      match input.[index] with
      | ' ' | '\t' | '\r' | '\n' -> scan (index + 1) reversed
      | '.' -> scan (index + 1) ({ kind = Dot; position = index } :: reversed)
      | '(' -> scan (index + 1) ({ kind = Lparen; position = index } :: reversed)
      | ')' -> scan (index + 1) ({ kind = Rparen; position = index } :: reversed)
      | '[' -> scan (index + 1) ({ kind = Lbracket; position = index } :: reversed)
      | ']' -> scan (index + 1) ({ kind = Rbracket; position = index } :: reversed)
      | ',' -> scan (index + 1) ({ kind = Comma; position = index } :: reversed)
      | ':' -> scan (index + 1) ({ kind = Colon; position = index } :: reversed)
      | '|' -> scan (index + 1) ({ kind = Pipe; position = index } :: reversed)
      | '=' when index + 1 < length && Char.equal input.[index + 1] '=' ->
        scan (index + 2) ({ kind = Equal; position = index } :: reversed)
      | '!' when index + 1 < length && Char.equal input.[index + 1] '=' ->
        scan (index + 2) ({ kind = Not_equal; position = index } :: reversed)
      | '<' when index + 1 < length && Char.equal input.[index + 1] '=' ->
        scan (index + 2) ({ kind = Less_or_equal; position = index } :: reversed)
      | '>' when index + 1 < length && Char.equal input.[index + 1] '=' ->
        scan (index + 2) ({ kind = Greater_or_equal; position = index } :: reversed)
      | '<' -> scan (index + 1) ({ kind = Less; position = index } :: reversed)
      | '>' -> scan (index + 1) ({ kind = Greater; position = index } :: reversed)
      | ('\'' | '"') as quote ->
        (match string_literal quote index (index + 1) (Buffer.create 32) with
         | Error _ as error -> error
         | Ok (value, next) ->
           scan next ({ kind = String value; position = index } :: reversed))
      | '-' when index + 1 < length && Char.is_digit input.[index + 1] ->
        let stop = ref (index + 2) in
        while !stop < length && Char.is_digit input.[!stop] do
          Int.incr stop
        done;
        let raw = String.sub input ~pos:index ~len:(!stop - index) in
        (match Int.of_string_opt raw with
         | Some value -> scan !stop ({ kind = Int value; position = index } :: reversed)
         | None -> error index "integer literal is outside the supported range")
      | c when Char.is_digit c ->
        let stop = ref (index + 1) in
        while !stop < length && Char.is_digit input.[!stop] do
          Int.incr stop
        done;
        let raw = String.sub input ~pos:index ~len:(!stop - index) in
        (match Int.of_string_opt raw with
         | Some value -> scan !stop ({ kind = Int value; position = index } :: reversed)
         | None -> error index "integer literal is outside the supported range")
      | c when is_ident_start c ->
        let stop = ref (index + 1) in
        while !stop < length && is_ident_char input.[!stop] do
          Int.incr stop
        done;
        let raw = String.sub input ~pos:index ~len:(!stop - index) in
        let kind =
          match raw with
          | "and" -> And
          | "or" -> Or
          | "true" -> True
          | "false" -> False
          | "null" -> Null
          | _ -> Ident raw
        in
        scan !stop ({ kind; position = index } :: reversed)
      | c ->
        error
          index
          (sprintf "unexpected character %C" c)
          ~hint:"quote shell-sensitive query syntax and use a supported operator")
  in
  scan 0 []
;;

type state =
  { tokens : token array
  ; mutable index : int
  }

let current state = state.tokens.(state.index)
let advance state = state.index <- state.index + 1

let parse_error ?hint state message =
  Error { position = (current state).position; message; hint }
;;

let consume state expected =
  if Poly.equal (current state).kind expected
  then (
    advance state;
    Ok ())
  else
    parse_error
      state
      (sprintf "expected %s" (Sexp.to_string_hum ([%sexp_of: token_kind] expected)))
;;

let rec parse_expr state = parse_or state

and parse_or state =
  let open Result.Let_syntax in
  let%bind first = parse_and state in
  let rec loop left =
    match (current state).kind with
    | Or ->
      advance state;
      let%bind right = parse_and state in
      loop (Query_ast.Or (left, right))
    | _ -> Ok left
  in
  loop first

and parse_and state =
  let open Result.Let_syntax in
  let%bind first = parse_comparison state in
  let rec loop left =
    match (current state).kind with
    | And ->
      advance state;
      let%bind right = parse_comparison state in
      loop (Query_ast.And (left, right))
    | _ -> Ok left
  in
  loop first

and parse_comparison state =
  let open Result.Let_syntax in
  let%bind left = parse_primary state in
  let operator =
    match (current state).kind with
    | Equal -> Some Query_ast.Equal
    | Not_equal -> Some Not_equal
    | Less -> Some Less
    | Less_or_equal -> Some Less_or_equal
    | Greater -> Some Greater
    | Greater_or_equal -> Some Greater_or_equal
    | _ -> None
  in
  match operator with
  | None -> Ok left
  | Some operator ->
    advance state;
    let%map right = parse_primary state in
    Query_ast.Compare (operator, left, right)

and parse_primary state =
  let open Result.Let_syntax in
  match (current state).kind with
  | String value ->
    advance state;
    Ok (Query_ast.Literal (String value))
  | Int value ->
    advance state;
    Ok (Query_ast.Literal (Int value))
  | True ->
    advance state;
    Ok (Query_ast.Literal (Bool true))
  | False ->
    advance state;
    Ok (Query_ast.Literal (Bool false))
  | Null ->
    advance state;
    Ok (Query_ast.Literal Null)
  | Dot ->
    advance state;
    let rec fields reversed =
      match (current state).kind with
      | Ident name ->
        advance state;
        let reversed = name :: reversed in
        if Poly.equal (current state).kind Dot
        then (
          advance state;
          fields reversed)
        else Ok (Query_ast.Field (List.rev reversed))
      | _ -> parse_error state "expected a field name after '.'"
    in
    fields []
  | Ident name ->
    advance state;
    if Poly.equal (current state).kind Lparen
    then (
      let%map args = parse_arguments state in
      Query_ast.Call (name, args))
    else parse_error state (sprintf "bare identifier %S is not an expression" name)
  | Lparen ->
    advance state;
    let%bind expression = parse_expr state in
    let%map () = consume state Rparen in
    expression
  | _ -> parse_error state "expected a literal, field, or function call"

and parse_arguments state =
  let open Result.Let_syntax in
  let%bind () = consume state Lparen in
  if Poly.equal (current state).kind Rparen
  then (
    advance state;
    Ok [])
  else (
    let rec loop reversed =
      let%bind argument = parse_expr state in
      match (current state).kind with
      | Comma ->
        advance state;
        loop (argument :: reversed)
      | Rparen ->
        advance state;
        Ok (List.rev (argument :: reversed))
      | _ -> parse_error state "expected ',' or ')' after argument"
    in
    loop [])
;;

let parse_postfixes state =
  let open Result.Let_syntax in
  let rec loop reversed =
    match (current state).kind with
    | Lbracket ->
      advance state;
      let start =
        match (current state).kind with
        | Int value ->
          advance state;
          Some value
        | _ -> None
      in
      (match (current state).kind with
       | Rbracket ->
         advance state;
         (match start with
          | Some value -> loop (Query_ast.Index value :: reversed)
          | None -> parse_error state "an index cannot be empty")
       | Colon ->
         advance state;
         let finish =
           match (current state).kind with
           | Int value ->
             advance state;
             Some value
           | _ -> None
         in
         let%bind () = consume state Rbracket in
         loop (Query_ast.Slice (start, finish) :: reversed)
       | _ -> parse_error state "expected ':' or ']' in postfix")
    | Dot ->
      advance state;
      (match (current state).kind with
       | Ident field ->
         advance state;
         loop (Query_ast.Field_access field :: reversed)
       | _ -> parse_error state "expected a field name after postfix '.'")
    | _ -> Ok (List.rev reversed)
  in
  loop []
;;

let parse_stage state =
  let open Result.Let_syntax in
  match (current state).kind with
  | Dot ->
    advance state;
    (match (current state).kind with
     | Ident name ->
       advance state;
       let%bind args =
         if Poly.equal (current state).kind Lparen then parse_arguments state else Ok []
       in
       let%map postfixes = parse_postfixes state in
       Query_ast.Select { name; args; postfixes }
     | _ -> parse_error state "expected a selector name after '.'")
  | Ident (("filter" | "map") as name) ->
    advance state;
    let%bind args = parse_arguments state in
    (match args with
     | [ expression ] ->
       Ok
         (if String.equal name "filter"
          then Query_ast.Filter expression
          else Map expression)
     | _ -> parse_error state (sprintf "%s expects exactly one expression" name))
  | _ ->
    parse_error
      state
      "expected a selector, filter(...), or map(...)"
      ~hint:"start a selector with '.', for example .nodes"
;;

let parse_tokens tokens =
  let open Result.Let_syntax in
  let state = { tokens; index = 0 } in
  if Poly.equal (current state).kind Eof
  then parse_error state "query is empty" ~hint:"omit QUERY for the default summary"
  else (
    let rec stages reversed =
      let%bind stage = parse_stage state in
      match (current state).kind with
      | Pipe ->
        advance state;
        stages (stage :: reversed)
      | Eof -> Ok (List.rev (stage :: reversed))
      | _ -> parse_error state "expected '|' or end of query"
    in
    stages [])
;;

let parse input = Result.bind (lex input) ~f:parse_tokens

let%expect_test "pipeline with filter and postfix" =
  parse ".nodes | filter(.name == 'Top') | map(.name)"
  |> [%sexp_of: (Query_ast.t, error) Result.t]
  |> print_s;
  [%expect
    {|
    (Ok
     ((Select (name nodes) (args ()) (postfixes ()))
      (Filter (Compare Equal (Field (name)) (Literal (String Top))))
      (Map (Field (name))))) |}]
;;
