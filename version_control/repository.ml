(*s: version_control/repository.ml *)
(*s: copyright ocamlgit *)
(* Copyright 2017 Yoann Padioleau, see copyright.txt *)
(*e: copyright ocamlgit *)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* API to access repository data (objects, index, refs, packs).
 *
 * less: use nested modules for objects, index, refs below?
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(*s: type Repository.t *)
type t = {
  (* less: on bare repo, this could be None *)
  worktree: Common.filename;
  (* less: on bare repo this could be the toplevel dir *)
  dotgit: Common.filename;

  (*s: [[Repository.t]] index field *)
  mutable index: Index.t;
  (*e: [[Repository.t]] index field *)
  (* less: compression level config field? *)
}
(*e: type Repository.t *)

(*s: constant Repository.TODOOPERATOR *)
let (/) = Filename.concat
(*e: constant Repository.TODOOPERATOR *)

(*s: constant Repository.dirperm *)
(* rwxr-x--- *)
let dirperm = 0o750
(*e: constant Repository.dirperm *)

(*s: type Repository.objectish *)
(* todo: handle ^ like HEAD^, so need more complex objectish parser *)
type objectish =
  | ObjByRef of Refs.t
  | ObjByHex of Hexsha.t
  (*s: [[Repository.objectish]] cases *)
  (* todo:
   *  ObjByBranch
   *  ObjByShortHex
   *)
  (*x: [[Repository.objectish]] cases *)
  (* ObjByTag *)
  (*e: [[Repository.objectish]] cases *)
(*e: type Repository.objectish *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*s: function Repository.hexsha_to_filename *)
(* for loose objects *)
let hexsha_to_filename r hexsha =
  let dir = String.sub hexsha 0 2 in
  let file = String.sub hexsha 2 (String.length hexsha - 2) in
  r.dotgit / "objects" / dir / file
(*e: function Repository.hexsha_to_filename *)

(*s: function Repository.hexsha_to_dirname *)
let hexsha_to_dirname r hexsha =
  let dir = String.sub hexsha 0 2 in
  r.dotgit / "objects" / dir
(*e: function Repository.hexsha_to_dirname *)

(*s: function Repository.ref_to_filename *)
let ref_to_filename r aref =
  match aref with
  | Refs.Head -> r.dotgit / "HEAD"
  (* less: win32: should actually replace '/' in name *)
  | Refs.Ref name -> r.dotgit / name
(*e: function Repository.ref_to_filename *)

(*s: function Repository.index_to_filename *)
let index_to_filename r =
  r.dotgit / "index"
(*e: function Repository.index_to_filename *)

(*s: function Repository.with_file_out_with_lock *)
(* todo: see code of _Gitfile.__init__ O_EXCL ... *)
let with_file_out_with_lock f file =
  (* todo: create .lock file and then rename *)
  Common.with_file_out f file
(*e: function Repository.with_file_out_with_lock *)


(* move in common.ml? *)
(*s: function Repository.with_opendir *)
(* less: use finalize *)
let with_opendir f dir =
  let handle = Unix.opendir dir in
  let res = f handle in
  Unix.closedir handle;
  res
(*e: function Repository.with_opendir *)
    
(* move in common.ml? (but remove .git specific stuff) *)
(*s: function Repository.walk_dir *)
(* inspired from os.path.walk in Python *)
let rec walk_dir f dir =
  dir |> with_opendir (fun handle ->
    let dirs = ref [] in
    let files = ref [] in
    try 
      while true do
        let s = Unix.readdir handle in
        (* git specific here *)
        if s <> "." && s <> ".." && s <> ".git" then begin
          let path = Filename.concat dir s in
          let st = Unix.lstat path in
          (match st.Unix.st_kind with
          | Unix.S_DIR -> Common.push s dirs
          | _ -> Common.push s files
          )
        end
      done
    with End_of_file ->
      let dirs = List.rev !dirs in
      let files = List.rev !files in
      f dir dirs files;
      dirs |> List.iter (fun s ->
        walk_dir f (Filename.concat dir s)
      )
  )
(*e: function Repository.walk_dir *)

(*****************************************************************************)
(* Refs *)
(*****************************************************************************)

(*s: function Repository.read_ref *)
let read_ref r aref =
  (* less: packed refs *)
  let file = ref_to_filename r aref in
  file |> Common.with_file_in (fun ch ->
    ch |> IO.input_channel |> Refs.read
  )
(*e: function Repository.read_ref *)

(*s: function Repository.follow_ref *)
let rec follow_ref r aref =
  (* less: check if depth > 5? *)
  try (
  let content = read_ref r aref in
  match content with
  | Refs.Hash sha -> [aref], Some sha
  | Refs.OtherRef refname ->
    let (xs, shaopt) = follow_ref r (Refs.Ref refname) in
    aref::xs, shaopt
  ) 
  (* inexistent ref file, can happen at the beginning when have .git/HEAD
   * pointing to an inexistent .git/refs/heads/master
   *)
  with Sys_error _ (* no such file or directory *) -> [aref], None
(*e: function Repository.follow_ref *)

(*s: function Repository.follow_ref_some *)
let follow_ref_some r aref =
  match follow_ref r aref |> snd with
  | Some sha -> sha
  | None -> failwith (spf "could not follow %s" (Refs.string_of_ref aref))
(*e: function Repository.follow_ref_some *)

(*s: function Repository.add_ref_if_new *)
let add_ref_if_new r aref refval =
  let (refs, shaopt) = follow_ref r aref in
  if shaopt <> None
  then false
  else begin
    let lastref = List.hd (List.rev refs) in
    let file = ref_to_filename r lastref in
    (* todo: ensure dirname exists *)
    file |> with_file_out_with_lock (fun ch ->
      (* todo: check file does not exist aleady *)
      ch |> IO.output_channel |> IO_.with_close_out (Refs.write refval)
    );
    true
  end
(*e: function Repository.add_ref_if_new *)

(*s: function Repository.del_ref *)
let del_ref r aref =
  let file = ref_to_filename r aref in
  Unix.unlink file
(*e: function Repository.del_ref *)

(*s: function Repository.set_ref_if_same_old *)
let set_ref_if_same_old r aref oldh newh =
  let (refs, _) = follow_ref r aref in
  let lastref = List.hd (List.rev refs) in
  let file = ref_to_filename r lastref in
  try 
    file |> with_file_out_with_lock (fun ch ->
      (* TODO generate some IO.No_more_input 
      let prev = read_ref r lastref in
      if prev <> (Refs.Hash oldh)
      then raise Not_found
      else 
      *)
        ch |> IO.output_channel |> IO_.with_close_out 
            (Refs.write (Refs.Hash newh))
    );
    true
  with Not_found -> false
(*e: function Repository.set_ref_if_same_old *)

(*s: function Repository.set_ref *)
let set_ref r aref newh =
  let (refs, _) = follow_ref r aref in
  let lastref = List.hd (List.rev refs) in
  let file = ref_to_filename r lastref in
  file |> with_file_out_with_lock (fun ch ->
    ch |> IO.output_channel |> IO_.with_close_out 
        (Refs.write (Refs.Hash newh))
  )
(*e: function Repository.set_ref *)
  

(*s: function Repository.write_ref *)
(* low-level *)
let write_ref r aref content =
  let file = ref_to_filename r aref in
  file |> with_file_out_with_lock (fun ch ->
    ch |> IO.output_channel |> IO_.with_close_out (Refs.write content))
(*e: function Repository.write_ref *)

(*s: function Repository.all_refs *)
let all_refs r =
  let root = r.dotgit ^ "/" in
  let rootlen = String.length root in
  let res = ref [] in
  (root / "refs") |> walk_dir (fun path dirs files ->
    files |> List.iter (fun file ->
      (* less: replace os.path.sep *)
      let dir = String.sub path rootlen (String.length path - rootlen) in
      let refname = dir / file in
      Common.push refname res
    );
   );
  List.rev !res
(*e: function Repository.all_refs *)

(*****************************************************************************)
(* Objects *)
(*****************************************************************************)

(*s: function Repository.read_obj *)
let read_obj r h =
  (* todo: look for packed obj *)
  let path = h |> Hexsha.of_sha |> hexsha_to_filename r in
  path |> Common.with_file_in (fun ch ->
    (* less: check read everything from channel? *)
    (* todo: check if sha consistent? *)
    ch |> IO.input_channel |> Compression.decompress |> Objects.read
  )
(*e: function Repository.read_obj *)

(*s: function Repository.read_commit *)
let read_commit r h =
  match read_obj r h with
  | Objects.Commit x -> x
  | _ -> failwith "read_commit: was expecting a commit"
(*e: function Repository.read_commit *)
(*s: function Repository.read_tree *)
let read_tree r h =
  match read_obj r h with
  | Objects.Tree x -> x
  | _ -> failwith "read_commit: was expecting a tree"
(*e: function Repository.read_tree *)
(*s: function Repository.read_blob *)
let read_blob r h =
  match read_obj r h with
  | Objects.Blob x -> x
  | _ -> failwith "read_commit: was expecting a blob"
(*e: function Repository.read_blob *)

(*s: function Repository.read_objectish *)
let read_objectish r objectish =
  match objectish with
  | ObjByRef aref -> 
    (match follow_ref r aref |> snd with
    | None -> failwith (spf "could not resolve %s" (Refs.string_of_ref aref))
    | Some sha -> 
      sha, read_obj r sha
    )
  | ObjByHex hexsha ->
    let sha = Hexsha.to_sha hexsha in
    sha, read_obj r sha
(*e: function Repository.read_objectish *)

(*s: function Repository.add_obj *)
let add_obj r obj =
  let bytes = 
    IO.output_bytes () |> IO_.with_close_out (Objects.write obj) in
  let sha = Sha1.sha1 bytes in
  let hexsha = Hexsha.of_sha sha in
  let dir = hexsha_to_dirname r hexsha in
  if not (Sys.file_exists dir)
  then Unix.mkdir dir dirperm;
  let file = hexsha_to_filename r hexsha in
  if (Sys.file_exists file)
  then sha (* deduplication! nothing to write, can share objects *)
  else begin
    file |> with_file_out_with_lock (fun ch ->
      let ic = IO.input_bytes bytes in
      let oc = IO.output_channel ch in
      Compression.compress ic oc;
      IO.close_out oc;
    );
    sha
  end
(*e: function Repository.add_obj *)

(*s: function Repository.has_obj *)
let has_obj r h =
  let path = h |> Hexsha.of_sha |> hexsha_to_filename r in
  Sys.file_exists path
(*e: function Repository.has_obj *)

(*****************************************************************************)
(* Index *)
(*****************************************************************************)

(*s: function Repository.read_index *)
let read_index r =
  r.index
(*e: function Repository.read_index *)

(*s: function Repository.write_index *)
let write_index r =
  let path = index_to_filename r in
  path |> with_file_out_with_lock (fun ch ->
    ch |> IO.output_channel |> IO_.with_close_out (Index.write r.index)
  )
(*e: function Repository.write_index *)

    
(*s: function Repository.content_from_path_and_unix_stat *)
let content_from_path_and_unix_stat full_path stat =
  match stat.Unix.st_kind with
  | Unix.S_LNK ->
    Unix.readlink full_path
  | Unix.S_REG -> 
    full_path |> Common.with_file_in (fun ch ->
      ch |> IO.input_channel |> IO.read_all
    )
  | _ -> failwith (spf "Repository.add_in_index: %s kind not handled" 
                     full_path)
(*e: function Repository.content_from_path_and_unix_stat *)

(*s: function Repository.add_in_index *)
(* old: was called stage() in dulwich *)
let add_in_index r relpaths =
  assert (relpaths |> List.for_all Filename.is_relative);
  relpaths |> List.iter (fun relpath ->
    let full_path = r.worktree / relpath in
    let stat = 
      try Unix.lstat full_path 
      with Unix.Unix_error _ ->
        failwith (spf "Repository.add_in_index: %s does not exist anymore"
                    relpath)
    in
    let blob = Objects.Blob (content_from_path_and_unix_stat full_path stat) in
    let sha = add_obj r blob in
    let entry = Index.mk_entry relpath sha stat in
    r.index <- Index.add_entry r.index entry;
  );
  write_index r
(*e: function Repository.add_in_index *)

(*****************************************************************************)
(* Commit *)
(*****************************************************************************)

(* less: move to cmd_commit.ml? *)
(*s: function Repository.commit_index *)
let commit_index r author committer message =
  let aref = Refs.Head in
  let tree = Index.tree_of_index r.index 
    (fun t -> add_obj r (Objects.Tree t)) 
  in
  (* todo: execute pre-commit hook *)

  (* less: Try to read commit message from .git/MERGE_MSG *)
  let message = message in
  (* todo: execute commit-msg hook *)

  let commit = { Commit. parents = []; tree; author; committer; message } in

  let ok =
    match follow_ref r aref |> snd with
    | Some old_head ->
      (* less: merge_heads from .git/MERGE_HEADS *)
      let merge_heads = [] in
      let commit = { commit with Commit.parents = old_head :: merge_heads } in
      let sha = add_obj r (Objects.Commit commit) in
      set_ref_if_same_old r aref old_head sha
    | None ->
      (* maybe first commit so refs/heads/master may not even exist yet *)
      let commit = { commit with Commit.parents = [] } in
      let sha = add_obj r (Objects.Commit commit) in
      add_ref_if_new r aref (Refs.Hash sha)
  in
  if not ok
  then failwith (spf "%s changed during commit" (Refs.string_of_ref aref));
  (* todo: execute post-commit hook *)
  ()
(*e: function Repository.commit_index *)
  
(*****************************************************************************)
(* Checkout and reset *)
(*****************************************************************************)

(*s: function Repository.build_file_from_blob *)
let build_file_from_blob fullpath blob perm =
  let oldstat =
    try 
      Some (Unix.lstat fullpath)
    with Unix.Unix_error _ -> None
  in
  (match perm with 
  | Tree.Link -> 
    if oldstat <> None
    then Unix.unlink fullpath;
    Unix.symlink blob fullpath;
  | Tree.Normal | Tree.Exec ->
    (match oldstat with
    (* opti: if same content, no need to write anything *)
    | Some { Unix.st_size = x } when x = Bytes.length blob && 
      (fullpath |> Common.with_file_in (fun ch -> 
        (ch |> IO.input_channel |> IO.read_all ) = blob
       )) ->
      ()
    | _ ->
      fullpath |> Common.with_file_out (fun ch ->
        output_bytes ch blob
      );
      (* less: honor filemode? *)
      Unix.chmod fullpath 
        (match perm with 
        | Tree.Normal -> 0o644
        | Tree.Exec -> 0o755
        | _ -> raise (Impossible "matched before")
        )
    )
  | Tree.Dir -> raise (Impossible "dirs filtered in walk_tree iteration")
  (*s: [[Repository.build_file_from_blob()]] match perm cases *)
  | Tree.Commit -> failwith "submodule not yet supported"
  (*e: [[Repository.build_file_from_blob()]] match perm cases *)
  );
  Unix.lstat fullpath
(*e: function Repository.build_file_from_blob *)


(*s: function Repository.set_worktree_and_index_to_tree *)
let set_worktree_and_index_to_tree r tree =
  (* todo: need lock on index? on worktree? *)
  let hcurrent = 
    r.index |> List.map (fun e -> e.Index.name, false) |> Hashtbl_.of_list in
  let new_index = ref [] in
  (* less: honor file mode from config file? *)
  tree |> Tree.walk_tree (read_tree r) "" (fun relpath entry ->
    let perm = entry.Tree.perm in
    match perm with
    | Tree.Dir -> 
      (* bugfix: need also here to mkdir; doing it below is not enough
       * when a dir has no file but only subdirs
       *)
      let fullpath = r.worktree / relpath in
      if not (Sys.file_exists fullpath)
      then Unix.mkdir fullpath dirperm;
    | Tree.Normal | Tree.Exec | Tree.Link ->
      (* less: validate_path? *)
      let fullpath = r.worktree / relpath in
      if not (Sys.file_exists (Filename.dirname fullpath))
      then Unix.mkdir (Filename.dirname fullpath) dirperm;
      let sha = entry.Tree.id in
      let blob = read_blob r sha in
      let stat = build_file_from_blob fullpath blob perm in
      Hashtbl.replace hcurrent relpath true;
      Common.push (Index.mk_entry relpath sha stat) new_index;
    (*s: [[Repository.set_worktree_and_index_to_tree()]] walk tree cases *)
    | Tree.Commit -> failwith "submodule not yet supported"
    (*e: [[Repository.set_worktree_and_index_to_tree()]] walk tree cases *)
  );
  let index = List.rev !new_index in
  r.index <- index;
  write_index r;
  hcurrent |> Hashtbl.iter (fun file used ->
    if not used
    then 
      (* todo: should check if modified? otherwise lose modif! *)
      let fullpath = r.worktree / file in
      Unix.unlink fullpath
  )
  (* less: delete if a dir became empty, just walk_dir? *)
(*e: function Repository.set_worktree_and_index_to_tree *)

(*****************************************************************************)
(* Packs *)
(*****************************************************************************)

(*****************************************************************************)
(* Repo init/open *)
(*****************************************************************************)

(*s: function Repository.init *)
let init root =
  if not (Sys.file_exists root)
  then Unix.mkdir root dirperm;

  (* less: bare argument? so no .git/ prefix? *)
  let dirs = [
    ".git";
    ".git/objects";
    ".git/refs";
    ".git/refs/heads";
    ".git/refs/tags";
    ".git/refs/remote";
    ".git/refs/remote/origin";
    ".git/hooks";
    ".git/info";
  ] in
  dirs |> List.iter (fun dir ->
    (* less: exn if already there? *)
    Unix.mkdir (root / dir) dirperm;
  );
  let r = {
    worktree = root;
    dotgit = root / ".git";
    index = Index.empty;
  } in
  add_ref_if_new r Refs.Head Refs.default_head_content |> ignore;

  (* less: config file, description, hooks, etc *)
  Sys.chdir root;
  let absolute = Sys.getcwd () in
  pr (spf "Initialized empty Git repository in %s" (absolute / ".git/"))
(*e: function Repository.init *)

(*s: function Repository.open_ *)
let open_ root = 
  let path = root / ".git" in
  if Sys.file_exists path &&
     (Unix.stat path).Unix.st_kind = Unix.S_DIR
  then 
    { worktree = root;
      dotgit = path;
      (* less: grafts, hooks *)
      index = 
        if Sys.file_exists (path / "index")
        then 
          (path / "index") |> Common.with_file_in (fun ch ->
            ch |> IO.input_channel |> Index.read)
        else Index.empty
    }
  else failwith (spf "Not a git repository at %s" root)
(*e: function Repository.open_ *)

(*s: function Repository.find_dotgit_root_and_open *)
let find_root_open_and_adjust_paths paths = 
  (* todo: allow git from different location *)
  let r = open_ "." in
  (* todo: support also absolute paths and transform in relpaths *)
  let relpaths = paths |> List.map (fun path ->
    if Filename.is_relative path
    then 
      (* todo: may have to adjust if root was not pwd *)
      path
    else failwith (spf "TODO: Not a relative path: %s" path)
    )
  in
  r, relpaths
(*e: function Repository.find_dotgit_root_and_open *)
(*e: version_control/repository.ml *)
