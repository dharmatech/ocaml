#!/bin/sh

# Plan 9's native loaders do not provide the Unix ld -r / -L semantics
# used by PACKLD for -output-complete-obj object output.

if grep '^TARGET=.*-plan9$' "${ocamlsrcdir}/Makefile.config" >/dev/null 2>&1; then
  echo "-output-complete-obj object output requires Unix-style relocatable partial linking, which is not available on Plan 9" > "${ocamltest_response}"
  exit "${TEST_SKIP}"
fi

exit "${TEST_PASS}"
