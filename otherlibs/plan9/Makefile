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
CAMLOBJS=plan9.cmo
INSTALL_LIBDIR_SUFFIX=/plan9

TEST_PROGRAM=tests/env_test$(EXE)
TEST_SUFFIX?=manual
CLEANFILES=$(TEST_PROGRAM) tests/*.cmi tests/*.cmo

include ../Makefile.otherlibs.common

plan9.cmo: plan9.cmi
plan9.cmx: plan9.cmi

.PHONY: depend test

depend:
	$(OCAMLRUN) $(ROOTDIR)/boot/ocamlc -depend -slash *.mli *.ml > .depend

test: all $(TEST_PROGRAM)
	$(OCAMLRUN) ./$(TEST_PROGRAM) '$(TEST_SUFFIX)'

$(TEST_PROGRAM): tests/env_test.ml plan9.cma plan9.cmi
	$(CAMLC) -I . plan9.cma tests/env_test.ml -o $@

include .depend
