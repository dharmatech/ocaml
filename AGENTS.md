# OCaml Plan 9 port guidance

## Project

This branch carries the OCaml 4.14.3 bytecode port for Plan 9/9front. The
existing compiler, runtime, standard library, and REPL use APE for their
portable Unix-facing behavior. Preserve that compatibility.

The port also provides a first-class, Plan 9-only `Plan9` library. Its
`plan9.cma` is ML-only and uses defensively validated native primitives built
into the standard Plan 9 `ocamlrun`. Ordinary users do not need `-custom`,
`-use-runtime`, a C compiler, a linker, a wrapper compiler, or user-written C.
Keep the portable `Sys` and `Unix` APIs unchanged.

## Source and build boundary

- Treat `C:\Users\dharm\src\ocaml` as the authoritative editing repository.
- Before running or diagnosing any Plan 9 configure, build, test, or
  installation command, read `build-aux/plan9/README.md` completely from the
  current authoritative checkout and follow its shell setup exactly. Enter
  APE through `ape/psh`; do not approximate that environment with manual
  namespace binds or ad hoc command adapters. If a documented command cannot
  be used, stop and identify the exact discrepancy before substituting
  anything.
- Run configure, GNU Make, compiler, runtime, library, and installed-prefix
  tests on native Plan 9 storage, not Windows and not `/mnt/term`.
- Use `/mnt/term` for transfer, then copy build inputs to native Plan 9
  storage. Never copy `.git`.
- Retain useful native build trees when incremental rebuilding is valuable.
  Use a fresh clone when deliberately performing end-to-end validation.
- Agree on an install prefix with the user and do not accidentally overwrite a
  known-working compiler.
- Keep the APE/GNU Make build lane unless the user decides to change it.

## P9QEMU and VM safety

- Before a VM operation, confirm the target instance, loopback address, and
  intended action with the user.
- Do not access another project's VM, guest, address, disk, or checkpoint
  unless the user asks.
- Reserve `127.0.0.1` for the user's ordinary/default P9QEMU lane. Give each
  concurrently running lab a unique explicit IPv4 loopback address and its
  own writable instance.
- Prefer the host's explicit WHPX profile. Use TCG only when the user chooses
  it; never fall back silently.
- Never boot a protected checkpoint directly. If needed, derive a new writable
  instance from a halted, verified source.
- Never copy or hash a live writable QCOW2. Never run two QEMU processes
  against the same writable disk.
- Inspect the exact P9QEMU/Python/QEMU process chain, QEMU PID, selected
  address, and seven listeners when starting or stopping a VM.
- Halt through Drawterm `fshalt`, wait for the exact QEMU PID to exit, and
  verify the selected listeners closed. Never broad-kill by executable name.

## Git and collaboration

- Use mainstream Git in the Windows checkout. Do not depend on git9 for the
  inner loop and never copy one implementation's `.git` directory into the
  other environment.
- Keep work on `plan9-4.14.3-000` unless the user requests another branch.
- Keep commits coherent and reviewable. Do not publish known-broken or
  partially validated runtime changes.
- Coordinate work with the user step by step and inspect live state before VM
  operations.
- Commit and push only after the user asks.
