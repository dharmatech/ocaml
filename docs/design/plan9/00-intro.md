# Plan 9 port direction

## Purpose

This directory records the durable design and operating contract for the
OCaml 4.14.3 Plan 9 port. The repository currently provides the bytecode
compiler/runtime, standard library, and REPL through APE. That remains the
portable Unix compatibility lane.

The next objective is a first-class `Plan9` library for programs that
deliberately want native Plan 9 semantics. Caml9's CPU boot conversion is the
initial demanding consumer, but the API and implementation must be suitable
for any OCaml program targeting Plan 9.

## Settled direction

The release packaging is:

```text
standard Plan 9 ocamlrun
  contains conditionally built caml_plan9_* primitives

ML-only, Plan 9-only plan9.cma
  declares and wraps those primitives

ordinary consumer
  ocamlc -I +plan9 plan9.cma program.ml -o program
```

Consumers do not use `-custom`, select a special runtime, invoke a C compiler
or linker, or write C. `Plan9` is not part of `Stdlib`, and non-Plan-9 builds do
not compile or advertise its primitives.

`Sys` and `Unix` remain unchanged. Code seeking their portable Unix behavior
continues to use APE. Code seeking native Plan 9 behavior uses `Plan9.Env`,
`Plan9.Process`, and the deliberately constrained low-level facilities.

## Scope

The near-term scope is:

- lossless native `/env` access;
- literal native process creation without a shell or PATH search;
- faithful native wait results and error strings;
- safe OCaml runtime boundaries around rfork, exec, and blocking wait; and
- ordinary installed-library packaging.

The following are separate projects:

- removing every APE dependency from `ocamlrun`;
- reimplementing Unix/POSIX compatibility without APE;
- replacing Autoconf, GNU Make, or APE shell build machinery with mk/rc;
- adding the native-code compiler, shared libraries, or systhreads; and
- changing the established semantics of `Sys` or `Unix`.

## Documents

- `01-native-api-requirements.md`: packaging, environment, process, wait, and
  safety invariants.
- `02-development-workflow.md`: authoritative-source and Plan 9 build flow.
- `03-verification-and-recovery.md`: validation lanes, VM safety, and evidence.
- `04-implementation-plan.md`: ordered milestones and exclusions.

Machine-local paths, tool identities, VM inventory, addresses, and live state
belong in `.agents/skills/ocaml-plan9-local`, not in these portable design
documents.
