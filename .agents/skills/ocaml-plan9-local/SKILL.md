---
name: ocaml-plan9-local
description: Use when transferring OCaml source to an already prepared Plan 9 guest, selecting native source/build/install paths, or running the OCaml Plan 9 configure, GNU Make, test, and installation workflow. Do not use for creating, cloning, starting, stopping, checkpointing, or removing VMs; use ocaml-plan9-vm-workflow instead.
---

# OCaml Plan 9 Local Development

Keep the Windows checkout authoritative while doing compiler, runtime, library,
and installed-prefix work on native Plan 9 storage.

## Required preflight

Before any native toolchain setup or build action, read the top-level
`README.md` completely from the current authoritative checkout. Treat it as the
canonical end-to-end entry point. When configuring, building, testing,
installing, or diagnosing OCaml itself, also read
`build-aux/plan9/README.md` completely for the helper-specific procedure.
Follow the documented shell setup exactly. Enter APE through `ape/psh`; do not
substitute manual namespace binds or ad hoc command adapters. If a documented
command cannot be used, stop and report the exact discrepancy before choosing
an alternative.

## Boundaries

- Authoritative editing repository: `C:\Users\dharm\src\ocaml`.
- Drawterm view of that checkout:
  `/mnt/term/C:/Users/dharm/src/ocaml`
- Use `/mnt/term` only for exchange. Copy build inputs to native Plan 9
  storage before configuring, building, or testing.
- Never copy `.git` between Windows and Plan 9 and never build directly through
  `/mnt/term`.
- Retain useful native build trees for incremental development. Use a fresh
  clone only for deliberate end-to-end qualification.
- Agree on an isolated installation prefix with the user. Do not overwrite a
  known-working compiler.
- Keep the APE/GNU Make build lane unless the user chooses to change it.

## Workflow

1. Complete the required README preflight, then confirm the already prepared
   guest target and native destination paths.
2. Use `$plan9-drawterm-windows` for transport and `/mnt/term` exchange.
3. Transfer only the intended source inputs and verify them after copying to
   native storage.
4. Configure for the Plan 9 target with the agreed compiler, GNU Make command,
   and isolated prefix.
5. Build and test from native storage. Preserve logs and durations useful to
   the current development loop.
6. Install only when authorized, then validate the installed compiler and
   ordinary `ocamlc -I +plan9 plan9.cma ...` consumer shape independently of
   the source-tree executables.
7. Keep successful native trees when incremental rebuilding is valuable.

Use `$plan9-file-search` for guest file discovery, `$plan9-source` for Plan 9
implementation source, `$plan9-docs` for manuals and papers, and `$plan9-git`
when deliberately using git9 in a fresh-clone qualification.

Use `$ocaml-plan9-vm-workflow` when the task crosses into VM lifecycle,
checkpoint, loopback-address, serial-log, or instance management.
