open! Core

type literal =
  | String of string
  | Int of int
  | Bool of bool
  | Null
[@@deriving sexp_of, compare, equal]

type comparison =
  | Equal
  | Not_equal
  | Less
  | Less_or_equal
  | Greater
  | Greater_or_equal
[@@deriving sexp_of, compare, equal]

type expr =
  | Literal of literal
  | Field of string list
  | Call of string * expr list
  | Compare of comparison * expr * expr
  | And of expr * expr
  | Or of expr * expr
[@@deriving sexp_of, compare, equal]

type postfix =
  | Index of int
  | Slice of int option * int option
  | Field_access of string
[@@deriving sexp_of, compare, equal]

type stage =
  | Select of
      { name : string
      ; args : expr list
      ; postfixes : postfix list
      }
  | Filter of expr
  | Map of expr
[@@deriving sexp_of, compare, equal]

type t = stage list [@@deriving sexp_of, compare, equal]
