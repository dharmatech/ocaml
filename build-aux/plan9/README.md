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

Use the Plan 9 configure wrapper from the repository root:

```sh
build-aux/plan9/configure.sh
```

The wrapper sets the repo-local shim `PATH` and configures the current
bytecode-focused Plan 9 port. It defaults to:

- `MAKE=/usr/glenda/lib/unix/bin/gmake`
- `CC=c89`
- Plan 9 runtime `CPPFLAGS`
- `--prefix=/usr/glenda/lib/unix/ocaml-4.14.3`
- disabled native compiler, shared libraries, systhreads, debug runtime,
  debugger, ocamldoc, ocamltest, and dependency generation
- `--enable-imprecise-c99-float-ops`

`MAKE`, `CC`, and `CPPFLAGS` can be overridden through the environment. Extra
arguments are passed to `./configure`, so a test prefix can be selected with:

```sh
build-aux/plan9/configure.sh --prefix=/usr/glenda/lib/unix/ocaml-4.14.3-test
```

## Build

```sh
gmake world
```

## Install

Use the Plan 9 install wrapper from the repository root:

```sh
build-aux/plan9/install.sh
```

The wrapper sets the repo-local shim `PATH` and passes the Plan 9-specific GNU
Make overrides needed by the current port:

- an absolute path to `build-aux/install-sh`, because some subdirectory install
  rules run with a different working directory
- `INSTALL_SOURCE_ARTIFACTS=false`, because source artifacts are not needed for
  the current bytecode-focused Plan 9 build
- `LN="ln -s -f"`, matching the link behavior expected by the OCaml install
  rules

The wrapper honors `MAKE` if it is already set; otherwise it uses
`/usr/glenda/lib/unix/bin/gmake`.

## Shims

The scripts under `shims/bin` are compatibility shims for commands used by the
configure and build machinery. They should not contain machine-local paths.
