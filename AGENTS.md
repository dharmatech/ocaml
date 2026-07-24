# OCaml Plan 9 port guidance

## Mission and current phase

This branch carries the OCaml 4.14.3 bytecode port for Plan 9/9front. The
existing compiler, runtime, standard library, and REPL use APE for their
portable Unix-facing behavior. Preserve that compatibility while adding a
first-class, explicitly Plan 9-native `Plan9` library.

The immediate direction is an ML-only, Plan 9-only `plan9.cma` backed by
defensively validated native primitives compiled into the standard Plan 9
`ocamlrun`. Ordinary users must not need `-custom`, `-use-runtime`, a C
compiler, a linker, a wrapper compiler, or user-written C.

## Start every task

1. Run `git --no-optional-locks status -sb` and
   `git --no-optional-locks log -1` before editing. Preserve unrelated changes
   and use live Git, not a handoff note, as the repository identity.
2. Read `README.md` and `build-aux/plan9/README.md` for the current port and
   build lane.
3. Read `docs/design/plan9/00-intro.md` and route additional reading by task:
   - API or runtime work: `01-native-api-requirements.md`
   - source transfer or native builds: `02-development-workflow.md`
   - VM, installation, recovery, or evidence work:
     `03-verification-and-recovery.md`
   - milestone selection: `04-implementation-plan.md`
4. Before any local VM, Drawterm, guest-transfer, guest-build, installation,
   prefix, or checkpoint operation, use `$ocaml-plan9-local` and read its
   tracked `references/current-state.md` and
   `references/compiler-lab-runbook.md`.

Treat current-state as a dated observation. Revalidate live Git, tool, process,
listener, instance, guest, and hash state before relying on it.

## Architectural boundary

- Keep `Sys` and `Unix` behavior unchanged. Their APE-backed semantics remain
  the portable Unix compatibility surface.
- Keep `Plan9` out of `Stdlib`. Build and install it only for Plan 9.
- Keep `plan9.cma` ML-only: no C objects, static archive, DLL metadata, or
  custom-link request.
- Compile `caml_plan9_*` implementations conditionally into the standard
  Plan 9 `ocamlrun` and its built-in primitive table. Non-Plan-9 builds must
  neither compile nor advertise those primitives.
- Require normal use to work as
  `ocamlc plan9.cma program.ml -o program`.
- Operate `Plan9.Env` directly on the live native `/env` representation. Do not
  add an OCaml mutation overlay, replay map, APE `environ` synchronization, or
  command-specific environment wrapper.
- Execute native processes directly. Do not route `Plan9.Process` through
  `Sys.command`, APE `system`, a shell, PATH search, quoting, or argument
  rewriting.
- Implement production spawn as one C primitive that copies inputs to C-owned
  memory, performs native rfork-and-exec, and never returns to OCaml in the
  child.
- Permanently reject `RFMEM`. Do not expose a generic integer-mask rfork
  primitive. A child-returning rfork is outside the initial stable API.
- Preserve native error strings, wait status text, PID, and all three timing
  fields. Do not collapse native wait results into Unix signal/exit variants.
- Treat the general custom-runtime repair as a separate compiler-port
  capability, not as a prerequisite for `Plan9`.

## Source and build boundary

- Treat `C:\Users\dharm\src\ocaml` as the authoritative editing repository.
- Run configure, GNU Make, compiler, runtime, library, and installed-prefix
  tests on native Plan 9 storage, not Windows and not `/mnt/term`.
- Preserve `/usr/glenda/src/ocaml` as a reported known-built reference until a
  stateful task revalidates it. Do not overwrite it for uncommitted work.
- Use a distinct disposable native development tree for active work.
- For inner-loop work, transfer only a reviewed manifest of intended
  additions, changes, and deletions through `/mnt/term`. Never copy `.git`.
- Before a milestone, export the exact reviewed Windows Git index, record its
  tree identity and archive hashes, and build that exact source in a fresh
  native tree. Account explicitly for any required gitlink/submodule content.
- Install experimental compilers only under a new versioned prefix. Never
  replace the known-working prefix.
- Keep the APE/GNU Make build lane unless a separate milestone explicitly
  changes it. Native Plan 9 runtime semantics do not require replacing the
  portable upstream build system.

## Validation and safety

- Source inspection and host-only tests do not authorize guest access.
- A compiler-lab phase must name its VM, loopback address, allowed mutations,
  native tree, install prefix, checks, recovery source, and exclusions before
  it begins.
- Keep the compiler lab separate from every caml9 boot lab. Never access a
  caml9 guest, address, port, disk, or checkpoint without an explicit ownership
  transfer.
- Reserve `127.0.0.1` for the user's ordinary/default P9QEMU lane. Give each
  agent-managed lab a unique explicit IPv4 loopback address and its own
  writable instance.
- Prefer the pinned host's explicit WHPX profile. Use TCG only as an explicit
  fallback or diagnostic comparison; never silently fall back during a gate.
- Never boot a protected checkpoint directly. Derive a new writable sibling
  only from a halted, verified source and only within an authorized phase.
- Never copy or hash a live writable QCOW2. Never run two QEMU processes
  against the same writable disk.
- Record the exact P9QEMU/Python/QEMU process chain, QEMU PID, selected address,
  seven listeners, serial log, source tree, build commands, install prefix,
  and results in the tracked current-state record.
- Halt through Drawterm `fshalt`, wait for the exact QEMU PID to exit, and
  verify the selected listeners closed. Never broad-kill by executable name.

## Git and completion

- Use mainstream Git in the Windows checkout. Do not depend on git9 for the
  inner loop and never copy one implementation's `.git` directory into the
  other environment.
- Keep work on `plan9-4.14.3-000` unless the user requests another branch.
- Keep commits coherent and reviewable. Do not publish a known-broken or
  partially validated runtime milestone.
- A milestone is complete only when its exact source boundary, native build,
  installed-prefix checks, documentation, evidence, current-state, and
  working-tree state are understood.
- Commit and push only after the user authorizes publication of the validated
  milestone.

## Conversations, subagents, and handoff

- Keep exactly one stateful operator for the authoritative OCaml worktree,
  native development tree, compiler VM, ports, prefixes, current-state,
  commits, and pushes.
- Default to one agent. Recommend a subagent only for a bounded independent
  read-only task, and spawn one only after explicit user approval.
- Before handing off, review the conversation for durable decisions,
  operational discoveries, rejected alternatives, failure modes, and
  unresolved risks. Record only missing durable knowledge in the appropriate
  tracked file.
- Update current-state with the exact next separately authorized phase and
  recovery boundary, validate the documentation and worktree, then transfer
  ownership explicitly.
