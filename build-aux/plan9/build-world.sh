#!/bin/sh

set -u

if test ! -f Makefile; then
  echo "build-aux/plan9/build-world.sh: run this script from a configured repository root" >&2
  exit 1
fi

GMAKE=${MAKE:-/usr/glenda/lib/unix/bin/gmake}

PATH=$PWD/build-aux/plan9/shims/bin:/usr/glenda/lib/unix/bin:/bin:.
export PATH

exec "$GMAKE" MAKE="$GMAKE" world ${1+"$@"}
