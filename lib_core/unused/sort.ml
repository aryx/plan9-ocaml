(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* $Id: sort.ml,v 1.3 1996/04/30 14:50:35 xleroy Exp $ *)

(* Merging and sorting *)

let rec merge order l1 l2 =
  match l1 with
    [] -> l2
  | h1 :: t1 ->
      match l2 with
        [] -> l1
      | h2 :: t2 ->
          if order h1 h2
          then h1 :: merge order t1 l2
          else h2 :: merge order l1 t2

let list order l =
  let rec initlist = function
      [] -> []
    | [e] -> [[e]]
    | e1::e2::rest ->
        (if order e1 e2 then [e1;e2] else [e2;e1]) :: initlist rest in
  let rec merge2 = function
      l1::l2::rest -> merge order l1 l2 :: merge2 rest
    | x -> x in
  let rec mergeall = function
      [] -> []
    | [l] -> l
    | llist -> mergeall (merge2 llist) in
  mergeall(initlist l)

