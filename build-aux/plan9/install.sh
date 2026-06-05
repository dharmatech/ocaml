#!/bin/sh

set -u

if test ! -f build-aux/install-sh; then
  echo "build-aux/plan9/install.sh: run this script from the repository root" >&2
  exit 1
fi

GMAKE=${MAKE:-/usr/glenda/lib/unix/bin/gmake}
INSTALL_SH=$PWD/build-aux/install-sh

PATH=$PWD/build-aux/plan9/shims/bin:/usr/glenda/lib/unix/bin:/bin:.
export PATH

exec "$GMAKE" \
  MAKE="$GMAKE" \
  INSTALL="$INSTALL_SH -c" \
  INSTALL_PROG="$INSTALL_SH -c" \
  INSTALL_DATA="$INSTALL_SH -c -m 644" \
  INSTALL_SOURCE_ARTIFACTS=false \
  LN="ln -s -f" \
  install
