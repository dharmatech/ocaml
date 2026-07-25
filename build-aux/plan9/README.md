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

The qualified compiler lab did not provide the example `gmake` path. Its
accepted Phase 1 build exported this exact command before configure, build,
test, and install:

```sh
MAKE=/usr/glenda/lib/unix/make-4.4.1/bin/make
export MAKE
```

Resolve and record the actual GNU Make executable on each lab rather than
assuming that the wrapper's default path exists.

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

The Plan 9 target also selects the ML-only `plan9` otherlib and includes its
native process primitives in the standard Plan 9 runtime. Installation puts
`plan9.cma` and `plan9.cmi` beneath `$(ocamlc -where)/plan9`, for normal use as
`ocamlc -I +plan9 plan9.cma ...`; consumers do not use `-custom` or a
dedicated `-use-runtime`.

`MAKE`, `CC`, and `CPPFLAGS` can be overridden through the environment. Extra
arguments are passed to `./configure`, so a test prefix can be selected with:

```sh
build-aux/plan9/configure.sh --prefix=/usr/glenda/lib/unix/ocaml-4.14.3-test
```

## Build

```sh
build-aux/plan9/build-world.sh
```

The wrapper sets the repo-local shim `PATH`, honors `MAKE` if it is already
set, and otherwise uses `/usr/glenda/lib/unix/bin/gmake`.

The focused source-tree Plan 9 tests are:

```sh
"$MAKE" -C otherlibs/plan9 TEST_SUFFIX=phase1_manual_001 test
```

Supply a new suffix for each run. The environment suite accepts only 1-40
ASCII letters, digits, or underscores, mutates only the two resulting
dedicated names in the test process's `/env`, and removes both names on
success or failure. The same target also runs the deterministic pure-ML
process coordinator tests, malformed primitive-call validation, the shared
P9E1 frame codec suite, and bounded native process integration tests through
the freshly built runtime. The test-only native helpers are not linked into or
installed with `plan9.cma`; ordinary consumers still require no C tools.
Actual asynchronous note interruption remains part of the separately
authorized compiler-lab evidence rather than the ordinary deterministic
suite. The repository-owned bounded driver for that explicit observation is
`"$MAKE" -C otherlibs/plan9 test-native-interruption`; it adds no production
fault switch or independent waiter.

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

## Phase 1 validation reference

The accepted 2026-07-24 native build used exact staged index tree
`7dee13d2b8c9fd159cb90d9834ea7100e5592e3b`, installed only under
`/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001`, and left the production
prefix unchanged. The focused environment suite passed, and an installed
consumer built and ran with:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

Fail-closed command sentinels proved that this ordinary link did not invoke a
C compiler, linker, archiver, `ocamlmklib`, or `flexlink`. General `-custom`
linking remains a separate later phase.

## Shims

The scripts under `shims/bin` are compatibility shims for commands used by the
configure and build machinery. They should not contain machine-local paths.
These shims intentionally implement only the flags and behavior needed by this
build.
