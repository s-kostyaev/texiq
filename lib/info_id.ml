open! Core

let validate ~kind string =
  let string = String.strip string in
  if String.is_empty string
  then Or_error.error_string (kind ^ " identifier is empty")
  else if String.exists string ~f:(Char.equal '\000')
  then Or_error.error_string (kind ^ " identifier contains NUL")
  else Ok string
;;

module Manual = struct
  type t = string [@@deriving compare, equal, sexp_of]

  let of_string = validate ~kind:"manual"
  let of_string_exn string = Or_error.ok_exn (of_string string)
  let to_string t = t

  let normalized t =
    let base = Filename.basename t in
    let rec remove_suffixes value =
      List.find_map [ ".gz"; ".info"; ".inf" ] ~f:(fun suffix ->
        Option.map (String.chop_suffix value ~suffix) ~f:remove_suffixes)
      |> Option.value ~default:value
    in
    String.lowercase (remove_suffixes base)
  ;;
end

module Node = struct
  type t = string [@@deriving compare, equal, sexp_of]

  let of_string = validate ~kind:"node"
  let of_string_exn string = Or_error.ok_exn (of_string string)
  let to_string t = t
end

module Target = struct
  type t =
    { manual : Manual.t option
    ; node : Node.t
    }
  [@@deriving compare, equal, sexp_of]

  let of_string string =
    let string = String.strip string in
    match String.chop_prefix string ~prefix:"(" with
    | Some rest ->
      (match String.lsplit2 rest ~on:')' with
       | None ->
         Or_error.error_s [%message "unterminated manual target" (string : string)]
       | Some (manual, node) ->
         let node = if String.is_empty (String.strip node) then "Top" else node in
         let%map.Or_error manual = Manual.of_string manual
         and node = Node.of_string node in
         { manual = Some manual; node })
    | None ->
      let%map.Or_error node = Node.of_string string in
      { manual = None; node }
  ;;

  let to_string { manual; node } =
    match manual with
    | None -> Node.to_string node
    | Some manual -> sprintf "(%s)%s" (Manual.to_string manual) (Node.to_string node)
  ;;
end
