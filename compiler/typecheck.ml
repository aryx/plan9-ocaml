(* Copyright 2016 Yoann Padioleau, see copyright.txt *)
open Common

open Ast
module T = Type
module S = Storage
module E = Check

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* This module assigns a final (resolved) type to every identifiers.
 * Typedefs are expanded, struct definitions are computed.
 * It also assigns the final storage to every identifiers.
 * 
 * Thanks to the naming done in parser.mly and the unambiguous Ast.fullname,
 * we do not have to handle scope here. 
 * Thanks to check.ml we do not have to check for inconcistencies or
 * redefinition of tags. We can assume everything is fine.
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(* less: vlong? *)
type integer = int

(* Environment for typechecking *)
type env = {
  ids:  (Ast.fullname, idinfo) Hashtbl.t;
  structs: (Ast.fullname, Type.struct_kind * Type.structdef) Hashtbl.t;
  typedefs: (Ast.fullname, Type.t) Hashtbl.t;
  constants: (Ast.fullname, integer) Hashtbl.t;
  (* less: enum? fullname -> Type.t but only basic? *)
}
  and idinfo = {
    typ: Type.t;
    sto: Storage.t;
    loc: Location_cpp.loc;
    (* typed initialisers *)
    ini: Ast.initialiser option;
  }

(* less: could factorize things in error.ml? *)
type error = Check.error

let string_of_error err =
  Check.string_of_error err

exception Error of error

(*****************************************************************************)
(* Constant expression evaluator *)
(*****************************************************************************)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(* will expand typedefs, resolve constant expressions *)
let rec asttype_to_type env typ0 =
  match typ0.t with
  | TBase t -> t
  | TPointer typ -> Type.TPointer (asttype_to_type env typ)
  | TArray (eopt, typ) ->
      raise Todo
  | TStructName (su, fullname) -> Type.TStructName (su, fullname)
  | TEnumName fullname ->
      raise Todo
  | TTypeName fullname -> Hashtbl.find env.typedefs fullname
  | TFunction (tret, (tparams, tdots)) ->
    Type.TFunc (asttype_to_type env tret,
                tparams |> List.map (fun p -> asttype_to_type env p.p_type),
                tdots)


(* if you declare multiple times the same global, we need to make sure
 * the types are the same. ex: 'extern int foo; ... int foo = 1;'
 * This is where we detect inconsistencies like 'int foo; void foo();'.
 * 
 * todo: allow struct with different names if have same fields!
 * So need to pass env. Or be stricter and forbid it? useful feature?
 *)
let same_types t1 t2 =
  t1 = t2

    


(* if you declare multiple times the same global, we may need to merge
 * types. Really???
*)
let merge_types t1 t2 =
  raise Todo

(* when processing enumeration constants *)
let max_types t1 t2 =
  raise Todo

let compatible_types t1 t2 =
  raise Todo


(* If you declare multiple times the same global, we need to make sure
 * the storage declaration are compatible and we need to compute the
 * final (resolved) storage.
 * This function works for global entities (variables but also functions).
 *)
let merge_storage_global name loc stoopt ini old =
  match stoopt, old.sto with
    (* this is ok, a header file can declare many externs and a C file
     * can then selectively "implements" some of those declarations.
     *)
    | None, S.Extern -> S.Global
    | None, S.Global ->
        if ini = None
        then raise (Error (E.Inconsistent (
          spf "useless redeclaration of '%s'" name, loc,
          "previous definition is here", old.loc)))
        else S.Global

    (* stricter: useless extern *)
    | Some S.Extern, (S.Global | S.Extern) ->
      raise (Error (E.Inconsistent (
        spf "useless extern declaration of '%s'" name, loc,
        "previous definition is here", old.loc)))

    (* stricter: forbid auto for globals *)
    | Some S.Auto, _ ->
      raise  (Error(E.ErrorMisc ("illegal storage class for file-scoped entity",
                                 loc)))
    | Some (S.Param | S.Global), _ -> 
      raise (Impossible "param or global are not keywords")
    | _, (S.Auto | S.Param) -> 
      raise (Impossible "globals can't be auto or param")

    | Some S.Static, (S.Extern | S.Global) ->
      raise (Error (E.Inconsistent (
       spf "static declaration of '%s' follows non-static declaration" name,loc,
       "previous definition is here", old.loc)))
    (* stricter: 5c just warns for this *)
    | (None | Some S.Extern), S.Static ->
      raise (Error (E.Inconsistent (
       spf "non-static declaration of '%s' follows static declaration" name,loc,
       "previous definition is here", old.loc)))

    | Some S.Static, S.Static ->
        if ini = None
        then raise (Error (E.Inconsistent (
          spf "useless redeclaration of '%s'" name, loc,
          "previous definition is here", old.loc)))
        else S.Static


(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

(* todo:
 *  - tmerge to compare decl to def.
 *  - evaluate const_expr  "enum not a constant: %s"
 *  - stuff done by 5c at parsing time:
 *    * type of Cast
 *    * type of lexpr
 *    * type of Return
 *    * type of identifier
 *    * type of constants (integers, floats, strings)
 *  - adjust storage when have more information
 *     (also if initializer => extern to global)
 * 
 *  - check if redeclare things (which is different from refining things)
 *    for instance two parameters with same name, if two locals with same name.
 *    or if redefine same structure in same scope, or conflicting sukind
 *    for the same tag.
 *    (or do that in check.ml??)
 *  - can define enum with same name than global entity? there would
 *    have the same blockid but will get ambiguity then.
 *    (or do that in check.ml??)
 *)

let check_and_annotate_program ast =

  let funcs = ref [] in

  let rec toplevel env = function
    | StructDef { s_kind = su; s_name = fullname; s_loc = loc; s_flds = flds }->
      Hashtbl.add env.structs fullname 
        (su, flds |> List.map 
            (fun {fld_name = name; fld_loc=_; fld_type = typ } ->
              (name, asttype_to_type env typ)))

    | TypeDef { typedef_name = fullname; typedef_loc = loc; typedef_type =typ}->
      Hashtbl.add env.typedefs fullname (asttype_to_type env typ)

    | EnumDef { enum_name = fullname; enum_loc = loc; enum_constants = csts }->
      raise Todo

    (* remember that VarDecl covers also prototypes *)
    | VarDecl { v_name = fullname; v_loc = loc; v_type = typ;
                v_storage = stoopt; v_init = eopt} ->
      let t = asttype_to_type env typ in
      let ini = expropt env eopt in

      (* step1: check for weird declarations *)
      (match t, ini, stoopt with
      | T.TFunc _, Some _, _ -> 
        raise (Error(E.ErrorMisc 
                     ("illegal initializer (only var can be initialized)",loc)))
      (* stricter: 5c says nothing, clang just warns *)
      | _, Some _, Some S.Extern ->
        raise (Error(E.ErrorMisc("'extern' variable has an initializer", loc)))
      | _ -> ()
      );

      (try 
         (* step2: check for weird redeclarations *)
         let old = Hashtbl.find env.ids fullname in

         (* check type compatibility *)
         if not (same_types t old.typ)
         then raise (Error (E.Inconsistent (
              (* less: could dump both type using vof_type *)
               spf "redefinition of '%s' with a different type" 
                 (unwrap fullname), loc,
               "previous definition is here", old.loc)))
         else
           (* TODO: need merge?? *)
           let finalt = t in

           let finalini = 
             match ini, old.ini with
             | Some x, None | None, Some x -> Some x
             | None, None -> None
             | Some x, Some y ->
               raise (Error (E.Inconsistent (
               spf "redefinition of '%s'" (unwrap fullname), loc,
               "previous definition is here", old.loc)))
           in

           (* check storage compatibility and compute final storage *)
           let finalsto = 
             merge_storage_global (unwrap fullname) loc stoopt ini old in

           Hashtbl.replace env.ids fullname 
             {typ = finalt; sto = finalsto; loc = loc; ini = finalini }
       with Not_found ->
         let finalsto =
           match stoopt with
           | None -> S.Global
           | Some S.Extern -> S.Extern
           | Some S.Static -> S.Static
           | Some S.Auto -> 
             raise (Error(E.ErrorMisc ("illegal storage class for global",loc)))
           | Some (S.Global | S.Param) -> 
             raise (Impossible "global or param are not keywords")
         in
         Hashtbl.add env.ids fullname 
           {typ = t; sto = finalsto; loc = loc; ini = ini }
      )

    | FuncDef { f_name = name; f_loc = loc; f_type = ftyp; f_body = st } ->
      (* todo: call toplevel with Var_decl adapted from FuncDef with ini *)
      raise Todo



  and stmt env st0 = function
    | _ -> raise Todo

  and expr env e0 =
    (* TODO *)
    e0
  and expropt env eopt = 
    match eopt with
    | None -> None
    | Some e -> Some (expr env e)
  in

  let env = {
    ids = Hashtbl.create 101;
    structs = Hashtbl.create 101;
    typedefs = Hashtbl.create 101;
    constants = Hashtbl.create 101;
  }
  in
  ast |> List.iter (toplevel env);
  env, List.rev !funcs
