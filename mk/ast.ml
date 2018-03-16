(* Copyright 2016 Yoann Padioleau, see copyright.txt *)

type loc = {
  file: Common.filename;
  line: int;
}

(* No separator, direct concatenation (hence the need for ${name} below).
 * The list must contain at least one element.
 *)
type word = W of word_element list

  and word_element =
    | String of string (* except the empty string *)
    | Percent
  
    (* evaluated in eval.ml just after parsing *)
    | Var of var
     (* `...` or `{...} (the string does not include the backquote or braces) *)
    | Backquoted of string

     and var = 
      (* $name or ${name} (the string does not contain the $ or {}) *)
      | SimpleVar of string
      (* ${name:a%b=c%d} *)
      | SubstVar of (string * word * word list)

(* separated by spaces *)
type words = word list


(* (the strings do not contain the leading space nor trailing newline) *)
type recipe = R of string list


type rule = {
  targets: words;
  prereqs: words;
  attrs: rule_attribute list;
  recipe: recipe option;
}
  and rule_attribute = 
    | Virtual
    | Quiet
    | Delete
    | Interactive (* pad: I added this one *)
    | NotHandled of char


type instr = {
  instr: instr_kind;
  loc: loc;
}

  and instr_kind =
    (* should resolve to a single filename, less: could enforce of word? *)
    | Include of words
    | Rule of rule
    (* stricter: no dynamic def like X=AVAR  $X=42 ... $AVAR *)
    | Definition of string * words
