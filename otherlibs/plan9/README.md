# Plan 9 native library

This directory builds the Plan 9-only `Plan9` module. The installed bytecode
archive is ML-only and lives in the `plan9` standard-library subdirectory:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

That normal link does not require `-custom`, `-use-runtime`, C stubs, a C
compiler, or a linker.

## `Plan9.Env`

`Plan9.Env` reads and mutates the calling process's live `/env` namespace.
Each lookup enumerates `/env` and, when present, opens the corresponding file.
Each set creates or truncates that file, and each removal calls `Sys.remove`
on that file. There is no environment mirror, mutation registry, APE
`getenv`/`putenv` call, command wrapper, or child-specific inference.

The representation is lossless:

| Native meaning | OCaml value | `/env` bytes |
| --- | --- | --- |
| absent | `Ok None` | no file |
| empty list | `Ok (Some [])` | zero bytes |
| empty scalar | `Ok (Some [""])` | one NUL |
| scalar | `Ok (Some ["x"])` | `x\000` |
| list | `Ok (Some ["x"; "y"])` | `x\000y\000` |

The decoder also accepts an unterminated final element. The encoder always
emits a trailing NUL for every element. It preserves arbitrary non-NUL bytes,
whitespace, newlines, empty elements, and element boundaries.

Lookups do not retry namespace races. A name absent from the fresh directory
enumeration returns `Ok None`; a file removed after that enumeration but before
the read produces its I/O error.

Names must not be empty, `.`, `..`, contain `/`, or contain NUL. Other Plan 9
names, including `fn#...`, are allowed. Invalid names and values return an
error with kind `Invalid_argument`.

`Plan9.Env.get_exn` returns the value, raises `Not_found` for absence, and
raises `Plan9.Error` for validation or I/O failure. The result-returning
operations preserve the `Sys_error` message produced by the existing runtime
file-I/O machinery. Removing an absent file is an error. A failed direct write
may leave the live file truncated or partially written; the module provides no
rollback overlay.

This phase deliberately relies on the existing runtime's file-I/O path. It
does not claim that the runtime or executable is APE-free. `Sys`, `Unix`,
`Sys.command`, and `Unix.putenv` retain their existing portable behavior.

## Focused test

On a configured Plan 9 source tree:

```sh
"$MAKE" -C otherlibs/plan9 TEST_SUFFIX=phase1_manual_001 test
```

The test covers absent, empty, scalar, list, unterminated, live reread, set,
remove, invalid-name, invalid-element, arbitrary-byte, and `fn#...` behavior.
Use a new 1-40 character ASCII letter, digit, or underscore suffix for each
run. The test cleans up its two resulting `/env` names on both success and
failure.

## Accepted Phase 1 validation

The exact Plan 9 library subtree
`c7c4d0b98ee94c7ca0fe601244af917dc02ee33f` was built, tested, installed
under an isolated prefix, and exercised through the installed interface on
2026-07-24. Installed `ocamlobjinfo` reported `Force custom: no` and no extra
C objects, C options, or dynamically loaded libraries. An ordinary installed
consumer compiled and ran while fail-closed C-tool sentinels remained
uninvoked.

The cross-environment checks also read an rc-created list and an APE-created
scalar from live `/env`, then proved that a direct `Plan9.Env` mutation was
visible through `/env` while APE's cached environment remained unchanged.
Child inheritance and native process creation are intentionally not claimed
by this phase.
