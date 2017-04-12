
type pid = int

type state = 
  | Running

  | Dead
  | Broken
  | Moribund
  | Stopped

  | Ready
  | Scheding

  | Queueing of rw option
(*
  | Rendezvous
  | Waitrelease
  | Wakeme
*)

and rw = Read | Write


type t = {
  pid: pid;
  mutable state: state;

  mutable slash: Chan.t;
  mutable dot: Chan.t;
}