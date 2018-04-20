<mkconfig

DIRS1=\
  lib_core/collections lib_core/commons\
  mk shell\
  lib_parsing lex yacc\
  macroprocessor\
  formats/objects assembler\
  formats/executables linker\
  compiler \
  version_control

# works only under plan9 for now: 
DIRS2=lib_core/commons2 lib_system/plan9 lib_graphics windows

# works only from scratch:
DIRS3=kernel

DIRS=$DIRS1 #$DIRS2 #DIRS3

all:V: all.directories
opt:V: opt.directories

%.directories:V:
	for(i in $DIRS) @{
		echo $i/
		cd $i
		mk $MKFLAGS $stem
	}

# alternate style to the %.directories trick; even simpler
clean nuke depend:V:
	for(i in $DIRS) @{
		cd $i
		mk $MKFLAGS $target
	}
