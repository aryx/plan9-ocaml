open Types

(* Rfork *)

(* Rfork has a complex interface
 * less: opti: could use a bitset for the whole type
 *)
type rfork_flags = 
  | Fork of fork_flags * common_rfork_flags
  | NoFork of common_rfork_flags
  and fork_flags = {
    share_mem: bool;
    wait_child: bool;
  }
 and common_rfork_flags = {
    fork_fds: fork_kind;
    fork_namespace: fork_kind;
    fork_env: fork_kind;
    (* less: 
     * share_rendezvous_group: bool;
     * share_note_group: bool;
     *)
  }
  and fork_kind = Clean | Copy | Share (* Share mean Nothing for NoFork *)

(* Await *)

(* await result *)
type wait_msg = {
  wait_pid: pid;
  wait_msg: string;
  (* less: time information *)
}

(* Open *)

(* less: opti: a bitset *)
type open_flags = {
  open_read: bool;
  open_write: bool;
  (* less: 
   *  - open_exec: bool; (* imply open_read *) 
   *  - open_truncate: ...
   *  - open_close_on_exec:
   *  - open_remove_on_close
   *)
}

(* Stat *)

(* stat result *)
type dir_entry = unit (* todo: *)

(* todo: a request type and an answer type? like plan9p?
 * generalized interface for syscall is then
 * syscall(char* bufin, int lenin, char* bufout, int lenout)
 * where use marshall in and out for Syscall.req_t and Syscall.ans_t
*)
type t = 
  | Nop

  (* process *)
  | Rfork of rfork_flags
  | Exec of filename (* cmd *) * string list (* args *)
  | Await
  | Exits of string

  (* memory *)
  | Brk of user_addr

  (* file *)
  | Open of filename * open_flags
  | Close of fd
  | Pread of fd
  | Pwrite of fd
  | Seek of fd

  (* directory *)
  | Create of filename
  | Remove of filename
  | Chdir of filename
  | Fd2path of fd
  | Fstat of fd
  | Fwstat of fd
  (* less: Stat and Wstat are unecessary *)

  (* namespace *)
  | Bind
  | Mount
  | Umount

  (* time *)
  | Sleep of sec
  | Alarm of time
  (* less: Nsec *)

  (* IPC *)
  | Pipe

  | Notify
  | Noted
  (* less: Segattach ... *)

  (* concurrency *)
  (*
  | RendezVous
  | SemAcquire
  | SemRelease
  *)
  (* less: TSemAcquire *)
  
  (* misc *)
  | Dup

  (* security *)
  (* less: Fversion | Fauth *) 

  (* todo? replace with a better error management comm between user/kernel?*)
  | Errstr
