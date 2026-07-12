open! Core

let summary = "Query GNU Info manuals without reading entire contents"

module Cli = Cli
module Catalog = Catalog
module Compression = Compression
module Diagnostic = Diagnostic
module Dir_parser = Dir_parser
module Engine = Engine
module Graph = Graph
module Info_id = Info_id
module Info_parser = Info_parser
module Info_path = Info_path
module Manual = Manual
module Query_ast = Query_ast
module Query_eval = Query_eval
module Query_parser = Query_parser
module Query_typecheck = Query_typecheck
module Render = Render
module Search = Search
module Source = Source

let%expect_test "summary is stable" =
  print_endline summary;
  [%expect {| Query GNU Info manuals without reading entire contents |}]
;;
