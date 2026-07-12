open! Core

module Tree = struct
  type t =
    { node : Manual.Node.t
    ; children : t list
    ; cycle : bool
    }
  [@@deriving sexp_of]
end

type t =
  { manual : Manual.t
  ; by_name : Manual.Node.t String.Map.t
  ; children_by_name : Manual.Node.t list String.Map.t
  }
[@@deriving sexp_of]

let create manual =
  let nodes = Manual.nodes manual in
  let by_name =
    List.fold nodes ~init:String.Map.empty ~f:(fun map node ->
      Map.set map ~key:(Info_id.Node.to_string (Manual.Node.name node)) ~data:node)
  in
  let stable_dedup nodes =
    List.fold nodes ~init:(String.Set.empty, []) ~f:(fun (seen, nodes) node ->
      let name = Info_id.Node.to_string (Manual.Node.name node) in
      if Set.mem seen name then seen, nodes else Set.add seen name, node :: nodes)
    |> snd
    |> List.rev
  in
  let menu_children =
    List.fold nodes ~init:String.Map.empty ~f:(fun map node ->
      let children =
        List.filter_map node.menus ~f:(fun entry ->
          match entry.target.manual with
          | Some target_manual
            when not (Info_id.Manual.equal target_manual (Manual.id manual)) -> None
          | _ ->
            Map.find by_name (Info_id.Node.to_string entry.target.node)
            |> Option.bind ~f:(fun child ->
              match child.header.up with
              | None -> Some child
              | Some up ->
                let same_manual =
                  match up.manual with
                  | None -> true
                  | Some up_manual -> Info_id.Manual.equal up_manual (Manual.id manual)
                in
                if same_manual && Info_id.Node.equal up.node (Manual.Node.name node)
                then Some child
                else None))
        |> stable_dedup
      in
      Map.set map ~key:(Info_id.Node.to_string (Manual.Node.name node)) ~data:children)
  in
  let children_by_name =
    List.fold nodes ~init:menu_children ~f:(fun map node ->
      match node.header.up with
      | None -> map
      | Some target ->
        (match target.manual with
         | Some target_manual
           when not (Info_id.Manual.equal target_manual (Manual.id manual)) -> map
         | _ ->
           let parent_name = Info_id.Node.to_string target.node in
           if not (Map.mem by_name parent_name)
           then map
           else
             Map.update map parent_name ~f:(function
               | None -> [ node ]
               | Some children -> stable_dedup (children @ [ node ]))))
  in
  { manual; by_name; children_by_name }
;;

let manual t = t.manual

let children t node =
  Map.find t.children_by_name (Info_id.Node.to_string (Manual.Node.name node))
  |> Option.value ~default:[]
;;

let roots t =
  match Manual.top t.manual with
  | Some top -> [ top ]
  | None -> []
;;

let reachable_names t =
  let rec visit seen node =
    let name = Info_id.Node.to_string (Manual.Node.name node) in
    if Set.mem seen name
    then seen
    else List.fold (children t node) ~init:(Set.add seen name) ~f:visit
  in
  List.fold (roots t) ~init:String.Set.empty ~f:visit
;;

let unreachable t =
  let reachable = reachable_names t in
  Manual.nodes t.manual
  |> List.filter ~f:(fun node ->
    not (Set.mem reachable (Info_id.Node.to_string (Manual.Node.name node))))
;;

let tree ?max_depth t =
  let rec build ancestors depth node =
    let name = Info_id.Node.to_string (Manual.Node.name node) in
    let cycle = Set.mem ancestors name in
    let depth_reached =
      Option.exists max_depth ~f:(fun max_depth -> depth >= max_depth)
    in
    let children =
      if cycle || depth_reached
      then []
      else (
        let ancestors = Set.add ancestors name in
        List.map (children t node) ~f:(build ancestors (depth + 1)))
    in
    Tree.{ node; children; cycle }
  in
  let primary = List.map (roots t) ~f:(build String.Set.empty 0) in
  let rec mark_reachable seen node =
    let name = Info_id.Node.to_string (Manual.Node.name node) in
    if Set.mem seen name
    then seen
    else List.fold (children t node) ~init:(Set.add seen name) ~f:mark_reachable
  in
  let _, detached =
    List.fold (unreachable t) ~init:(String.Set.empty, []) ~f:(fun (seen, trees) node ->
      let name = Info_id.Node.to_string (Manual.Node.name node) in
      if Set.mem seen name
      then seen, trees
      else mark_reachable seen node, build String.Set.empty 0 node :: trees)
  in
  let detached = List.rev detached in
  primary @ detached
;;
