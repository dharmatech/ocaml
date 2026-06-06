# OCaml 4.14.3 for Plan 9

This branch contains a Plan 9/9front APE port of OCaml 4.14.3.

Current support is focused on the bytecode compiler, bytecode runtime, standard
library, and REPL. The native compiler is not supported yet.

The Plan 9-specific OCaml build helpers live in `build-aux/plan9`.

## Prerequisite: GNU Make

This OCaml port depends on the Plan 9 port of GNU Make.

From a Plan 9 shell:

```sh
cd /usr/glenda/src
git/clone git@github.com:dharmatech/make.git
cd make
git/branch plan9-4.4.1-000
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
git/clone git@github.com:dharmatech/ocaml.git
cd ocaml
git/branch plan9-4.14.3-000
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
