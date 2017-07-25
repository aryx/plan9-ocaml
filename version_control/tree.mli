
type perm = 
  | Normal
  | Exec
  | Link
  | Dir
  | Commit (* submodule? *)

type entry = {
  perm: perm;
  name: string;
  (* blob or tree *)
  node: Sha1.t;
}

type t = entry list

type hash = Sha1.t


(* assumes have already read the 'tree <size>\000' header from unzipped input *)
val read: IO.input -> t
(* does not write the header, does not compress *)
val write: t -> bytes IO.output -> unit

val show: t -> unit

val walk_tree: 
  (hash -> t) -> Common.filename (* dir *) -> 
  (Common.filename -> entry -> unit) -> t -> unit
