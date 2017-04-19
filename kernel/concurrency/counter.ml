open Common
open Types

type t = Ref.t

(* will start at 1 *)
let gen x =
  Ref.inc x

(* less: delete once have { Xxx.xxx= yyy= ... } feature *)
open Ref_

let alloc () =
  { Ref_.
    cnt = 0;
    l = Spinlock.alloc ();
  }
