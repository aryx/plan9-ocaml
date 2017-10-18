(setq p "/home/pad/github/plan9-ml")

(setq 
 pad-ocaml-project-path p
 pad-ocaml-project-subdirs 
 (split-string 
  "lib_core/commons
   formats/objects formats/executables
   assembler linker mk shell compiler macroprocessor
   version_control
   "
  ))


(setq
 pad-ocaml-project-prog     "linker/5l"
 pad-ocaml-project-args 
 (join-string 
  (list 
   ""
   (case 3
     (1 (concat p "/linker/test.5"))
     (2 (concat p "/linker/helloworld.5"))
     (3 (concat (concat p "/linker/hello.5") " " (concat p "/linker/world.5")))
     )
   )))


(setq
 pad-ocaml-project-prog     "mk/mk"
 pad-ocaml-project-args 
 (join-string 
  (list 
   ""
   (case 2
     (1 (concat "-debugger -f " (concat p "/mk/mkfile")))
     (2 (concat "-debugger -f " (concat p "/mk/tests/mk-empty-var")))
     (3 "-debugger -f /home/pad/plan9/windows/rio/mkfile")
     )
   )))

(setq
 pad-ocaml-project-prog     "shell/rc"
 pad-ocaml-project-args 
 (join-string 
  (list 
   ""
   (case 3
     (1 (concat "-debugger -test_parser " (concat p "/shell/tests/hello.rc")))
     (2 (concat "-debugger -dump_opcodes"))
     (3 (concat "-m " (concat p "/shell/rcmain-unix") " -i -r -dump_ast"))
     )
   )))

(setq
 pad-ocaml-project-prog     "compiler/5c"
 pad-ocaml-project-args 
 (join-string 
  (list 
   ""
   (case 4
     (1 (concat "-debugger -test_parser " (concat p "/compiler/tests/hello.rc")))
     (2 (concat "-debugger " (concat p "/compiler/tests/helloworld.c")))
     (3 (concat "-debugger -dump_asm " (concat p "/compiler/tests/pointer.c")))
     (4 (concat "-debugger -dump_asm /home/pad/plan9/builders/mk/dumpers.c"))
     )
   )))


(setq
 pad-ocaml-project-prog     "version_control/ogit"
 pad-ocaml-project-args 
 (join-string 
  (list 
   ""
   (case 4
     (1 (concat "clone /home/pad/tmp/t1 /home/pad/tmp/t2"))
     (3 "-debugger -f /home/pad/plan9/windows/rio/mkfile")
     (4 (concat "test diff3 " 
                p "/version_control/tests/file_origin  " 
                p "/version_control/tests/file_a  " 
                p "/version_control/tests/file_b "
                ))
     )
   )))

