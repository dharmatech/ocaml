#**************************************************************************
#*                                                                        *
#*                                 OCaml                                  *
#*                                                                        *
#*                             Dharmatech                                 *
#*                                                                        *
#*   Copyright 2026 Dharmatech                                            *
#*                                                                        *
#*   All rights reserved.  This file is distributed under the terms of    *
#*   the GNU Lesser General Public License version 2.1, with the           *
#*   special exception on linking described in the file LICENSE.          *
#*                                                                        *
#**************************************************************************

LIBNAME=plan9
CAMLOBJS=plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo plan9_process.cmo plan9.cmo
CMIFILES=plan9.cmi
INSTALL_LIBDIR_SUFFIX=/plan9

ENV_TEST_PROGRAM=tests/env_test$(EXE)
FD_LIFECYCLE_TEST_PROGRAM=tests/fd_lifecycle_test$(EXE)
PROCESS_STATE_TEST_PROGRAM=tests/process_state_test$(EXE)
PROCESS_STATE_PRIMITIVES=tests/process_state_primitives
PROCESS_PRIMITIVE_TEST_PROGRAM=tests/process_primitive_validation_test$(EXE)
PROCESS_NATIVE_TEST_PROGRAM=tests/process_native_integration_test$(EXE)
PROCESS_NATIVE_HELPER=tests/process_native_helper$(EXE)
PROCESS_NATIVE_HELPER_OBJECT=tests/process_native_helper.$(O)
PROCESS_FRAME_TEST_PROGRAM=tests/process_frame_parser_test$(EXE)
PROCESS_FRAME_TEST_OBJECT=tests/process_frame_parser_test.$(O)

include ../Makefile.otherlibs.common

RAW_SYSCALL_TEST_PROGRAM=
RAW_SYSCALL_TEST_OBJECT=
RAW_SYSCALL_OBJECT=
SYSCALL_CAPABILITY_TEST_PROGRAM=
ifneq "$(filter x86_64-%-plan9,$(HOST))" ""
RAW_SYSCALL_TEST_PROGRAM=tests/raw_syscall_test$(EXE)
RAW_SYSCALL_TEST_OBJECT=tests/raw_syscall_test.$(O)
RAW_SYSCALL_OBJECT=$(ROOTDIR)/runtime/plan9_syscall_amd64.$(O)
SYSCALL_CAPABILITY_TEST_PROGRAM=tests/syscall_capability_test$(EXE)
endif
ML_TEST_PROGRAMS=$(ENV_TEST_PROGRAM) $(FD_LIFECYCLE_TEST_PROGRAM) \
  $(PROCESS_STATE_TEST_PROGRAM) \
  $(PROCESS_PRIMITIVE_TEST_PROGRAM) $(PROCESS_NATIVE_TEST_PROGRAM) \
  $(SYSCALL_CAPABILITY_TEST_PROGRAM)
NATIVE_TEST_PROGRAMS=$(PROCESS_NATIVE_HELPER) $(PROCESS_FRAME_TEST_PROGRAM) \
  $(RAW_SYSCALL_TEST_PROGRAM)
TEST_PROGRAMS=$(ML_TEST_PROGRAMS) $(NATIVE_TEST_PROGRAMS)
TEST_SUFFIX?=manual
CLEANFILES=$(TEST_PROGRAMS) $(PROCESS_NATIVE_HELPER_OBJECT) \
  $(PROCESS_FRAME_TEST_OBJECT) $(RAW_SYSCALL_TEST_OBJECT) \
  $(PROCESS_STATE_PRIMITIVES) $(PROCESS_STATE_PRIMITIVES).tmp \
  tests/*.cmi tests/*.cmo

.PHONY: depend test test-native-interruption

depend:
	$(OCAMLRUN) $(ROOTDIR)/boot/ocamlc -depend -slash *.mli *.ml > .depend

test: all $(TEST_PROGRAMS)
	$(NEW_OCAMLRUN) ./$(ENV_TEST_PROGRAM) '$(TEST_SUFFIX)'
	$(NEW_OCAMLRUN) ./$(FD_LIFECYCLE_TEST_PROGRAM)
	$(OCAMLRUN) ./$(PROCESS_STATE_TEST_PROGRAM)
	$(NEW_OCAMLRUN) ./$(PROCESS_PRIMITIVE_TEST_PROGRAM)
	./$(PROCESS_FRAME_TEST_PROGRAM)
ifneq "$(RAW_SYSCALL_TEST_PROGRAM)" ""
	./$(RAW_SYSCALL_TEST_PROGRAM)
endif
ifneq "$(SYSCALL_CAPABILITY_TEST_PROGRAM)" ""
	$(NEW_OCAMLRUN) ./$(SYSCALL_CAPABILITY_TEST_PROGRAM)
endif
	$(NEW_OCAMLRUN) ./$(PROCESS_NATIVE_TEST_PROGRAM) \
	  '$(NEW_OCAMLRUN)' './$(PROCESS_NATIVE_TEST_PROGRAM)' \
	  './$(PROCESS_NATIVE_HELPER)' '$(TEST_SUFFIX)'

test-native-interruption: all $(PROCESS_NATIVE_TEST_PROGRAM) \
    $(PROCESS_NATIVE_HELPER)
	$(NEW_OCAMLRUN) ./$(PROCESS_NATIVE_TEST_PROGRAM) \
	  --qualification-wait-interruption './$(PROCESS_NATIVE_HELPER)'

$(ENV_TEST_PROGRAM): tests/env_test.ml plan9.cma plan9.cmi
	$(CAMLC) -I . plan9.cma tests/env_test.ml -o $@

$(FD_LIFECYCLE_TEST_PROGRAM): tests/fd_lifecycle_test.ml \
    plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo
	$(CAMLC) -I . \
	  plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo \
	  tests/fd_lifecycle_test.ml -o $@

$(PROCESS_STATE_PRIMITIVES): $(ROOTDIR)/runtime/primitives
	grep -v '^caml_plan9_' $< > $@.tmp
	mv $@.tmp $@

$(PROCESS_STATE_TEST_PROGRAM): tests/process_state_test.ml \
    $(PROCESS_STATE_PRIMITIVES) \
    plan9_types.cmo plan9_process.cmo
	$(BOOT_OCAMLC) -nostdlib -I $(ROOTDIR)/stdlib -I . \
	  -use-prims $(PROCESS_STATE_PRIMITIVES) \
	  plan9_types.cmo plan9_process.cmo \
	  tests/process_state_test.ml -o $@

$(PROCESS_PRIMITIVE_TEST_PROGRAM): \
    tests/process_primitive_validation_test.ml plan9.cma plan9.cmi
	$(CAMLC) -I . plan9.cma \
	  tests/process_primitive_validation_test.ml -o $@

$(PROCESS_NATIVE_TEST_PROGRAM): \
    tests/process_native_integration_test.ml plan9.cma plan9.cmi
	$(CAMLC) -I . plan9.cma \
	  tests/process_native_integration_test.ml -o $@

ifneq "$(SYSCALL_CAPABILITY_TEST_PROGRAM)" ""
$(SYSCALL_CAPABILITY_TEST_PROGRAM): tests/syscall_capability_test.ml
	$(CAMLC) tests/syscall_capability_test.ml -o $@
endif

$(PROCESS_NATIVE_HELPER): $(PROCESS_NATIVE_HELPER_OBJECT)
	$(call MKEXE_USING_COMPILER,$@,$^)

$(PROCESS_FRAME_TEST_PROGRAM): $(PROCESS_FRAME_TEST_OBJECT)
	$(call MKEXE_USING_COMPILER,$@,$^)

ifneq "$(RAW_SYSCALL_TEST_PROGRAM)" ""
$(RAW_SYSCALL_TEST_PROGRAM): $(RAW_SYSCALL_TEST_OBJECT) \
    $(RAW_SYSCALL_OBJECT)
	$(call MKEXE_USING_COMPILER,$@,$^)

$(RAW_SYSCALL_TEST_OBJECT): tests/raw_syscall_test.c \
    $(ROOTDIR)/runtime/plan9_syscall.h

$(RAW_SYSCALL_OBJECT):
	$(MAKE) -C $(ROOTDIR)/runtime $(notdir $@)
endif

$(PROCESS_FRAME_TEST_OBJECT): \
    tests/process_frame_parser_test.c \
    $(ROOTDIR)/runtime/plan9_process_frame.h

include .depend
