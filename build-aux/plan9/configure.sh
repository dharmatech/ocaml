#!/bin/sh

set -u

if test ! -x ./configure; then
  echo "build-aux/plan9/configure.sh: run this script from the repository root" >&2
  exit 1
fi

PATH=$PWD/build-aux/plan9/shims/bin:/usr/glenda/lib/unix/bin:/bin:.
export PATH

MAKE=${MAKE:-/usr/glenda/lib/unix/bin/gmake}
CC=${CC:-c89}
CPPFLAGS=${CPPFLAGS:-"-D_RESEARCH_SOURCE -D_BSD_EXTENSION -DCAML_PLAN9_NO_ALIGN -DCAML_PLAN9_NO_STRINGS_H -DCAML_PLAN9_MATH_FALLBACKS -DCAML_PLAN9_NO_GETPROTOBYNUMBER -DCAML_PLAN9_OCAMLTEST_FALLBACKS"}

export MAKE CC CPPFLAGS

exec ./configure \
  --prefix=/usr/glenda/lib/unix/ocaml-4.14.3 \
  --disable-native-compiler \
  --disable-shared \
  --disable-systhreads \
  --disable-debug-runtime \
  --disable-debugger \
  --disable-ocamldoc \
  --disable-ocamltest \
  --disable-dependency-generation \
  --enable-imprecise-c99-float-ops \
  "$@"
