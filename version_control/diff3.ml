open Common

module D = Diff

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Merge of files (aka diff3).
 *
 * alternatives:
 *  - diff3.c by Randy Smith (original author of diff3 algorithm)
 *  - diff3.py
 *  - https://blog.jcoglan.com/2017/05/08/merging-with-diff3/
 *  - Diff3 in Javascript
 *    http://homepages.kcbbs.gen.nz/tonyg/projects/synchrotron.html
 *    https://github.com/tonyg/synchrotron/blob/master/diff.js
 *
 * Pierce et al. formalized the diff3 algorithm in 
 * "A formal Investigation of Diff3" - FSTTCS 2007
 * Foundations of Software Technology and Theoretical Computer Science
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(* Final result (see Pierce et al. paper *)
type chunk =
  | Stable of Diff.item list
  | ChangedA of Diff.item list (* Orig *) * Diff.item list (* A *)
  | ChangedB of Diff.item list (* Orig *) * Diff.item list (* B *)
  | FalseConflict of Diff.item list
  | TrueConflict of 
      Diff.item list (* Orig *) * Diff.item list (*A*) * Diff.item list (*B*)

(* intermediate types *)
type matching_lines = 
    (int (* line# in original *) * int (* line# in modified file *)) 
    list

type identical_lines =
    (int (* line# in original *) * int (* line# in A *) * int (* line# in B *))
    list

type chunk_basic = 
  | Same of int
  | Changed of (int * int) * (int * int) * (int * int)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let matching_lines_of_diff diff =
  let rec aux old_line new_line xs =
    match xs with
    | [] -> []
    | x::xs -> 
      match x with
      | D.Equal _ -> 
        (old_line, new_line)::aux (old_line + 1) (new_line + 1) xs
      | D.Added _ ->
        aux old_line (new_line + 1) xs
      | D.Deleted _ ->
        aux (old_line + 1) new_line xs
  in
  aux 0 0 diff

let rec identical_lines xs ys =
  match xs, ys with
  | [], [] -> []
  | x::xs, [] -> []
  | [], y::ys -> []
  | (o1,a)::xs, (o2,b)::ys ->
    (match () with
    | _ when o1 = o2 -> (o1, a, b)::identical_lines xs ys
    | _ when o1 < o2 -> identical_lines xs ((o2,b)::ys)
    | _ (*   o1 > 02*) -> identical_lines ((o1,a)::xs) ys
    )

let basic_chunks (leno, lena, lenb) identical =
  let rec aux lo la lb xs =
  match xs with
  | [] -> 
    if lo < leno || la < lenb || lb < lenb
    then [Changed ((lo, leno),(la, lena), (lb, lenb))]
    else []
  | (o, a, b)::xs ->
    if a = la && b = lb
    then (Same o)::aux (o+1) (a+1) (b+1) xs
    else (Changed ((lo, o), (la, a), (lb, b)))::(Same o)::
      aux (o+1) (a+1) (b+1) xs
  in
  aux 0 0 0 identical

let rec span_range arr l1 l2=
  if l1 = l2
  then []
  else arr.(l1)::span_range arr (l1+1) l2

let final_chunks oxs axs bxs chunks =
  let rec aux xs =
  match xs with
  | [] -> []
  | x::xs ->
    let chunk = 
      (match x with
      | Same o -> Stable [oxs.(o)]
      | Changed ((o1, o2),(a1, a2), (b1, b2)) ->
        let oh = span_range oxs o1 o2 in
        let ah = span_range axs a1 a2 in
        let bh = span_range bxs b1 b2 in
        match oh = ah, oh = bh with
        | false, true ->
          ChangedA (oh, ah)
        | true, false ->
          ChangedB (oh, bh)
        | true, true -> raise (Impossible "should be Same then")
        | false, false ->
          if ah = bh
          then FalseConflict ah
          else TrueConflict (oh, ah, bh)
      )
    in
    chunk::aux xs
  in
  aux chunks

(*****************************************************************************)
(* Output *)
(*****************************************************************************)

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let diff3 str_origin str_a str_b =
  let oxs = Diffs.split_lines str_origin |> Array.of_list in
  let axs = Diffs.split_lines str_a |> Array.of_list in
  let bxs = Diffs.split_lines str_b |> Array.of_list in

  (* less: could go through Diffs.diff_array instead of hardcoded Diff_myers?*)
  let diff_oa = Diff_myers.diff oxs axs in
  let diff_ob = Diff_myers.diff oxs bxs in

  let match_oa = matching_lines_of_diff diff_oa in
  let match_ob = matching_lines_of_diff diff_ob in
  let same_all = identical_lines match_oa match_ob in
  let basic_chunks = 
    basic_chunks
      ((Array.length oxs),
       (Array.length axs),
       (Array.length bxs)
      )
      same_all in
  final_chunks oxs axs bxs basic_chunks
