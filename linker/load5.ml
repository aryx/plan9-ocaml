open Common

open Ast_asm5
module T = Types
module T5 = Types5

(* Naming, modifies ent, modifies h *)
let process_ent ent h idfile =
  (match ent.priv with
  | Some _ -> ent.priv <- Some idfile
  | None -> ()
  );
  T5.lookup_ent ent h |> ignore

(* Visit entities to populate symbol table with wanted symbols.
 * This is more complicated than in 5l because we can not rely
 * on an ANAME or Operand.sym.
 * This is boilerplate which could be auto generated.
 *)
let visit_entities f xs =
  let rec ximm x =
    match x with
    | Address ent -> f ent
    | String _ -> ()
  in
  let rec imm_or_ximm x =
    match x with
    | Left _ -> ()
    | Right x -> ximm x
  in
  let rec mov_operand x =
    match x with
    | Entity (ent, _) -> f ent
    | Ximm x -> ximm x
    | Imsr _ | Indirect _ | Param _ | Local _ -> ()
  in
  let rec branch_operand x =
    match !x with
    | SymbolJump ent -> f ent
    | IndirectJump _ | Relative _ | LabelUse _ | Absolute _ -> ()
  in
  xs |> List.iter (fun (x, _line) ->
    match x with
    | Pseudo y ->
      (match y with
      | TEXT (ent, _, _) -> f ent
      | GLOBL (ent, _, _) -> f ent
      | DATA (ent, _, _, ix) -> f ent; imm_or_ximm ix
      | WORD (ix) -> imm_or_ximm ix
      )
    | Instr (i, _cond) ->
      (match i with
      | MOV (_, _, m1, m2) -> mov_operand m1; mov_operand m2
      | B b | BL b | Bxx (_, b) -> branch_operand b
      | Arith _ | SWAP _ | RET | Cmp _ | SWI _ | RFE | NOP -> () 
      )
    | LabelDef _ | LineDirective _ -> ()
  )



(* load() performs a few things:
 * - load objects (of course),
 * - split and concatenate in code vs data all objects,
 * - relocate absolute jumps,
 * - "name" entities by assigning a unique name to every entities
 *   (handling private symbols),
 * - visit all entities (defs and uses) and add them in symbol table
 *)
let load xs =

  (* values to return *)
  let code = ref [] in
  let data = ref [] in
  let h = Hashtbl.create 101 in

  let pc = ref 0 in
  let idfile = ref 0 in

  xs |> List.iter (fun file ->
    let ipc = !pc in
    incr idfile;
    (* less: assert it is a .5 file *)
    (* todo: if lib file! *)

    (* object loading is so much easier in ocaml *)
    let (prog, _srcfile) = Object_code5.load file in

    (* naming and populating symbol table h *)
    prog |> visit_entities (fun ent -> process_ent ent h !idfile);

    (* split and concatenate in code vs data, relocate branches, 
     * and add definitions in symbol table h.
     *)
    prog |> List.iter (fun (p, line) ->
      match p with
      | Pseudo pseudo ->
          (match pseudo with
          | TEXT (ent, attrs, size) ->
              (* less: set curtext *)
              let v = T5.lookup_ent ent h in
              (match v.T.section with
              | T.SXref -> v.T.section <- T.SText !pc;
              | _ -> failwith (spf "redefinition of %s" ent.name)
              );
              (* less: adjust autosize? *)
              code |> Common.push (T5.TEXT (ent, attrs, size), (file, line));
              incr pc;
          | WORD v ->
              code |> Common.push (T5.WORD v, (file, line));
              incr pc;
            
          | GLOBL (ent, attrs, size) -> 
              let v = T5.lookup_ent ent h in
              (match v.T.section with
              | T.SXref -> v.T.section <- T.SData size;
              | _ -> failwith (spf "redefinition of %s" ent.name)
              );
          | DATA (ent, offset, size, v) -> 
              data |> Common.push (T5.DATA (ent, offset, size, v))
          )

      | Instr (inst, cond) ->
          let relocate_branch opd =
            match !opd with
            | SymbolJump _ | IndirectJump _ -> ()
            | Relative _ | LabelUse _ ->
                raise (Impossible "Relative or LabelUse resolved by assembler")
            | Absolute i -> opd := Absolute (i + ipc)
          in
          (match inst with
          | B opd | BL opd | Bxx (_, opd) -> relocate_branch opd
          | _ -> ()
          );
          code |> Common.push (T5.I (inst, cond), (file, line));
          incr pc;

      | LabelDef _ -> failwith (spf "label definition in object")
      (* todo: return also, but for now stripped info *)
      | LineDirective _ -> ()
    );
  );
  Array.of_list (List.rev !code), List.rev !data, h
