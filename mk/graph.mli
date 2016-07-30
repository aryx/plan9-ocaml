
type node = {
  (* usually a filename *)
  name: string;
  (* None for virtual targets and inexistent files *)
  time: float option;
  
  (* todo: flags *)
  is_virtual: bool;

  prereqs: arc list ref;
}
and arc = {
  (* Can point to an existing node since the graph of dependencies is a DAG.
   * None for virtual targets (still need a recipe hence an arc).
  *)
  dest: node option;

  (* what we need from the rule *)
  rule_exec: Rules.rule_exec;
}


val graph: 
  string (* target *) -> Rules.t -> node (* the root *)
