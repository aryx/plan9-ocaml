(*
 * Copyright (c) 2013-2017 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* 
 * 
 * Most of the code below derives from: https://github.com/mirage/ocaml-git
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type perm = 
  | Normal
  | Exec
  | Link
  | Dir
  | Commit (* ?? submodule? *)

type entry = {
  perm: perm;
  (* relative to tree, so does not contain any '/', or '.' or '..' *)
  name: string;
  (* blob or tree *)
  node: Sha1.t;
}

(* todo: entries must be sorted! and each name must be unique *)
type t = entry list

type hash = Sha1.t

(*****************************************************************************)
(* Walk *)
(*****************************************************************************)
(* we must visit in sorted order, so caller can rely on f being
 * called in order (so can for instance create sorted index entries for free)
 *)
let rec walk_tree read_tree dirpath f xs =
  xs |> List.iter (fun entry ->
    raise Todo
  )
  

(*****************************************************************************)
(* IO *)
(*****************************************************************************)

let perm_of_string = function
  | "44"
  | "100644" -> Normal
  | "100755" -> Exec
  | "120000" -> Link
  | "40000"  -> Dir
  | "160000" -> Commit
  | x        -> failwith (spf "Tree.perm_of_string: %s is not a valid perm." x)

let string_of_perm = function
  | Normal -> "100644"
  | Exec   -> "100755"
  | Link   -> "120000"
  | Dir    -> "40000"
  | Commit -> "160000"

(* todo: should transform some No_more_input exn in something bad,
 * on first one it's ok, but after it means incomplete entry.
 *)
let read_entry ch =
  let perm = IO_.read_string_and_stop_char ch ' ' in
  (* todo: handle escape char in filenames? encode/decode *)
  let name = IO_.read_string_and_stop_char ch '\000' in
  let hash = Sha1.read ch in
  { perm = perm_of_string perm; name = name; node = hash }

let write_entry ch e =
  IO.nwrite ch (string_of_perm e.perm);
  IO.write ch ' ';
  (* todo: handle escape char in filenames? encode/decode *)
  IO.nwrite ch e.name;
  IO.write ch '\000';
  Sha1.write ch e.node
  

let read ch =
  let rec aux acc =
    try 
      (* todo: how diffentiate no more input from wrong input ?
       * pass size ch and use IO.pos_in ?
       *)
      let e = read_entry ch in
      aux (e::acc)
    with IO.No_more_input ->
      List.rev acc
  in
  aux []


let write t ch =
  t |> List.iter (write_entry ch)

(*****************************************************************************)
(* Show *)
(*****************************************************************************)

let show xs =
  xs |> List.iter (fun entry ->
    pr (spf "%s%s" entry.name
          (match entry.perm with
          | Dir -> "/"
          | _ -> ""
          ))
  )
