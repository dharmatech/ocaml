# Plan 9 APE build helpers

This directory contains helper scripts for building this OCaml fork on
9front/Plan 9 through APE.

The helpers are intentionally small. They smooth over command-line differences
between Autoconf/GNU Make expectations and the Plan 9 userland while keeping the
build tied to the normal OCaml source tree.

## Requirements

- 9front/Plan 9 with APE
- GNU Make available on the Plan 9 system
- A C compiler available as `c89`

## Shell setup

From the root of a checkout, enter APE and put the repo-local shims before the
system tools:

```sh
ape/psh
PATH=$PWD/build-aux/plan9/shims/bin:/usr/glenda/lib/unix/bin:/bin:.
export PATH
MAKE=/usr/glenda/lib/unix/bin/gmake
export MAKE
```

The path to GNU Make may differ on another system.

## Configure

The current Plan 9 build uses the bytecode runtime and disables features that
are not currently supported by this port:

```sh
./configure \
  --prefix=/usr/glenda/lib/unix/ocaml-4.14.3 \
  CC=c89 \
  CPPFLAGS="-D_RESEARCH_SOURCE -D_BSD_EXTENSION -DCAML_PLAN9_NO_ALIGN -DCAML_PLAN9_NO_STRINGS_H -DCAML_PLAN9_MATH_FALLBACKS -DCAML_PLAN9_NO_GETPROTOBYNUMBER -DCAML_PLAN9_OCAMLTEST_FALLBACKS" \
  --disable-native-compiler \
  --disable-shared \
  --disable-systhreads \
  --disable-debug-runtime \
  --disable-debugger \
  --disable-ocamldoc \
  --disable-ocamltest \
  --disable-dependency-generation \
  --enable-imprecise-c99-float-ops
```

## Build

```sh
gmake world
```

## Install

Use an absolute path to `install-sh` when installing. Some subdirectory install
rules run with a different working directory, so a relative `build-aux/install-sh`
does not resolve correctly on Plan 9.

```sh
INSTALL_SH=$PWD/build-aux/install-sh
gmake \
  INSTALL="$INSTALL_SH -c" \
  INSTALL_PROG="$INSTALL_SH -c" \
  INSTALL_DATA="$INSTALL_SH -c -m 644" \
  INSTALL_SOURCE_ARTIFACTS=false \
  LN="ln -s -f" \
  install
```

`INSTALL_SOURCE_ARTIFACTS=false` avoids installing source artifacts that are not
needed for the current bytecode-focused Plan 9 build. `LN="ln -s -f"` matches the
link behavior expected by the OCaml install rules.

## Shims

The scripts under `shims/bin` are compatibility shims for commands used by the
configure and build machinery. They should not contain machine-local paths.
