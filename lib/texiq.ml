open! Core

let summary = "Query GNU Info manuals without reading entire contents"

let%expect_test "summary is stable" =
  print_endline summary;
  [%expect {| Query GNU Info manuals without reading entire contents |}]
;;
