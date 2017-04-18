open Common
open Types
open Spinlock_

(* less:
 * - nlocks
 * - use monitor approach instead of fine-grained locks? anyway, monitor
 *   need to rely on spinlock internally?
 *)

type t = Spinlock_.t

let lock x =
  let when_hold () =
    let up = !Globals.up in
    (* less: increment up.nlocks (but using low level atomic_inc) *)
    if up.Proc_.pid <> 0 
    then x.p <- Some up.Proc_.pid;
    (* less: add more debugging info in lock once you grab it *)
    ()
  in
  if Tas.tas x.hold = false
  then when_hold () (* good to go! *)
  else begin
    (* we have to spin *)
    let finish = ref false in
    while not !finish do
      let i = ref 0 in
      (* less: coherence issue? *)
      while not !(x.hold) do
        incr i;
        if !i > 10000000
        then failwith "lock loop";
      done;
      (* let's try again *)
      if Tas.tas x.hold = false
      then begin 
        when_hold ();
        finish := true;
      end
    done
  end

let unlock x =
  if not !(x.hold)
  then failwith "Spinlock.unlock: not locked";
  (* less: other sanity checks on x.pid <> up.pid *)
  (* less: coherence issue? *)
  x.hold := false

let canlock x =
  if Tas.tas x.hold = false
  then (* less: update debugging fields *) true
  else false


(* so nice compared to C *)
let with_lock f x =
  lock x;
  Common.finalize f (fun () ->
    unlock x
  )


let alloc () = 
  { hold = ref false;
    p = None;
  }
