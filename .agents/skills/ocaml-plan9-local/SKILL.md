---
name: ocaml-plan9-local
description: Use when starting, resuming, testing, or handing off the OCaml 4.14.3 Plan 9 port on Dharmatech's Windows host; operating an isolated P9QEMU compiler lab; using Drawterm; transferring Windows source through /mnt/term; building or installing OCaml on native Plan 9; selecting a versioned compiler prefix; recording VM, process, listener, build, checkpoint, or recovery state; or coordinating the OCaml lab with caml9's separate VM lane.
---

# OCaml Plan 9 local workflow

Use this tracked host profile for the OCaml compiler port. Read the repository
root `AGENTS.md` and the relevant `docs/design/plan9` files for portable policy.
Use this skill for Dharmatech-host paths, P9QEMU and Drawterm mechanics, mutable
lab state, and safe transfer/build procedures.

## Begin from recorded state

Read:

- [`references/current-state.md`](references/current-state.md) before relying
  on any repository, tool, native tree, prefix, VM, address, PID, or listener;
- [`references/compiler-lab-runbook.md`](references/compiler-lab-runbook.md)
  before source transfer, a guest build, installation, VM lifecycle, or
  checkpoint decision.

Treat current-state as a dated observation. Revalidate the live boundary before
acting. Stop for an unexpected dirty worktree, active writable disk, listener
conflict, changed recovery source, or unowned shared lab.

## Keep one stateful operator

One task owns the authoritative OCaml worktree and index, native development
tree, compiler VM, selected loopback address, source transfer, build, installed
prefixes, current-state, commits, and pushes.

An ownership transfer limited to the Windows worktree does not convey authority
over a VM, guest, port, instance, checkpoint, native tree, or installed prefix.
Require those resources to be named explicitly in a separate stateful gate.

Do not access caml9's worktree, running guest, ports, instances, or checkpoints
without an explicit ownership transfer. A separate loopback address does not
permit two conversations to mutate shared host state independently.

## Use the established host tools

- Windows source: `C:\Users\dharm\src\ocaml`
- P9QEMU source/docs: `C:\Users\dharm\src\p9qemu`
- Installed P9QEMU: `C:\Users\dharm\.local\bin\p9qemu.exe`
- QEMU: `C:\Program Files\qemu\qemu-system-x86_64.exe`
- Drawterm: `C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe`
- Proposed OCaml VM root: `C:\Users\dharm\vm\ocaml` after explicit creation
- Drawterm host bridge:
  `/mnt/term/C:/Users/dharm/src/ocaml`

Verify each path and tool identity before the first stateful phase.

## Select a lab deliberately

Reserve `127.0.0.1` for the user's default P9QEMU lane. Assign an OCaml lab a
unique canonical `127.0.0.0/8` address only after checking tracked allocations,
live QEMU processes, all seven address-specific endpoints, and ownership of
other project labs.

Use a distinct writable instance. Never point two QEMU processes at the same
disk. Never boot a frozen checkpoint directly.

On the pinned Windows host, use installed P9QEMU with explicit `--accel whpx`.
Use `--accel tcg` only for a declared fallback or diagnostic comparison. Run a
dry run with the exact instance, address, accelerator, and log policy before a
real start.

Record the P9QEMU shim, Python launcher, and exact QEMU PID and command lines,
plus QEMU's ownership of all seven selected listeners.

## Connect and transfer through Drawterm

Use explicit CPU and auth endpoints on the selected address:

```powershell
$env:PASS = '<credential>'
& 'C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe' `
    -h "tcp!$labAddress!17019" `
    -a "tcp!$labAddress!17567" `
    -u glenda -G -c '<short rc command>'
```

The published ready image's `p9qemu-demo` credential is a public localhost
fixture. Never store a real replacement credential in tracked files, logs, or
tool arguments.

Inside Drawterm, Windows `C:` is available under `/mnt/term/C:`. Copy reviewed
files into a disposable native tree and build there. Never build through the
bridge and never transfer `.git`.

Keep independently authenticated `-c` commands short. Use a copied guest-side
driver script for long build sequences. Run namespace-changing probes beneath
`rfork n` unless the experiment intentionally targets the persistent guest
namespace.

## Build and install natively

Preserve `/usr/glenda/src/ocaml` as the reported known-built reference until
revalidated. Use a separate native development tree and a fresh versioned
install prefix for every experimental milestone.

Use the repository's APE/GNU Make helpers. Run consumer-facing Plan 9 API tests
from native `rc` using only the selected installed prefix. Do not overwrite the
known compiler.

For inner-loop work, transfer an explicit changed-file/deletion manifest. For
a milestone, build a fresh exact-index archive and record its Git tree and
transfer hashes.

## Preserve lifecycle evidence

Use a unique serial-log path that does not exist. After launch, report the
instance, address, process chain, QEMU PID, forwarded endpoints, Drawterm
command, and whether the lab remains running.

Halt with address-specific Drawterm `fshalt`, wait for the exact QEMU PID to
exit, verify the seven endpoints closed, then validate the halted instance.
Never broad-kill. If graceful shutdown fails, preserve evidence and request
approval before terminating only the recorded PID.

Update current-state after every accepted or rejected stateful gate and before
handoff. Record failures as distinct attempts rather than replacing them with
corrected output.

## Protect checkpoints and prefixes

Create a checkpoint only from a completely halted, verified instance and only
under separate authorization. Copy through a uniquely named staging directory,
verify source and destination identities, then rename atomically. Do not build
a backing chain through a mutable instance.

Never boot a protected checkpoint for ordinary work. Copy it to a new writable
instance when resuming from it. Never install over a known-working compiler
prefix.

## Hand off cleanly

Before transferring ownership:

1. review the conversation for missing durable decisions or failure modes;
2. update tracked design, runbook, evidence, and current-state as needed;
3. state which VMs are running or halted and which must not be touched;
4. record the exact next separately authorized phase and recovery boundary;
5. validate Git and the local skill; and
6. state explicitly that stateful ownership has moved.

Do not spawn a subagent without explicit user approval.
