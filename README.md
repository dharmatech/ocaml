# OCaml 4.14.3 for Plan 9

This branch contains a Plan 9/9front APE port of OCaml 4.14.3.

Current support is focused on the bytecode compiler, bytecode runtime, standard
library, and REPL. The native compiler is not supported yet.

The Plan 9-specific OCaml build helpers live in `build-aux/plan9`.

## Prerequisite: GNU Make

This OCaml port depends on the Plan 9 port of GNU Make.

HTTPS cloning uses `webfs`. If it is not already running, start it with:

```sh
webfs
```

From a Plan 9 shell:

```sh
cd /usr/glenda/src
git/clone https://github.com/dharmatech/make.git
cd make
```

Then enter APE and install GNU Make:

```sh
ape/psh
build-aux/plan9/configure.sh --prefix=/usr/glenda/lib/unix/make-4.4.1
build-aux/plan9/build.sh
build-aux/plan9/install.sh
exit
```

## Build and Install OCaml

From a Plan 9 shell:

```sh
cd /usr/glenda/src
git/clone https://github.com/dharmatech/ocaml.git
cd ocaml
```

Then enter APE and install OCaml:

```sh
ape/psh
MAKE=/usr/glenda/lib/unix/make-4.4.1/bin/make
export MAKE
build-aux/plan9/configure.sh --prefix=/usr/glenda/lib/unix/ocaml-4.14.3
build-aux/plan9/build-world.sh
build-aux/plan9/install.sh
```

The install prefix can be changed. The path above keeps this build separate
from the rest of the system until you choose how to bind or expose it.

## Smoke Test

```sh
/usr/glenda/lib/unix/ocaml-4.14.3/bin/ocamlc -version
/usr/glenda/lib/unix/ocaml-4.14.3/bin/ocaml
```

## Native Plan 9 API

Plan 9 builds include an ML-only `Plan9` library for programs that deliberately
want native Plan 9 semantics. `Plan9.Env` reads and mutates the process's live
`/env` namespace without changing the portable APE-backed `Sys` or `Unix`
interfaces. `Plan9.Fd` provides explicitly owned native pipes and typed
descriptor byte I/O with deterministic close. `Plan9.Raw` provides the narrow
exact environment-copy and exec operations, while `Plan9.Process` provides
direct managed process execution and synchronous native wait ownership. The
standard Plan 9 `ocamlrun` contains the required primitives.

An installed client uses the library normally:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

This does not require `-custom`, `-use-runtime`, C stubs, a C compiler, or a
linker. See the [Plan 9 library reference](otherlibs/plan9/REFERENCE.md) for
user-facing examples and the complete public API. The
[library README](otherlibs/plan9/README.md) records implementation semantics,
validation, and the qualification boundary.
