(* Copyright 2016 Yoann Padioleau, see copyright.txt *)
open Common

module T = Types

let check h =
  h |> Hashtbl.iter (fun (s, _) v ->
    match v.T.section with
    | T.SXref -> failwith (spf "%s: not defined" s)
    | _ -> ()
  )

(* less: could also check validity of object file, 
 *  - registers are in range, 
 *  - integers are in range
 *    ex with immediate in shifting operation:
 *    if i >= 0 && i <= 31
 *    then ...
 *    else failwith "shift value out of range"
 *  - that cond is AL for B and Bxx
 *)
