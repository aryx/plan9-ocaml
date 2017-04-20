open Common

(* less: use Error of error? as in ocaml source? easier for pretty printing *)
exception Ebadarg
exception Enovmem
exception Esoverlap
exception Enochild
exception Ebadexec

let panic str =
  raise (Impossible ("panic: " ^ str))