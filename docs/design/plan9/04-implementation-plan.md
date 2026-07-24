# Plan 9 implementation plan

## Phase 0: onboarding

Create and review the repository guidance, native API requirements,
Windows-to-Plan-9 workflow, local compiler-lab skill, current-state record, and
runbook. No compiler source, guest, VM, or installed prefix changes occur.

## Phase 1: built-in packaging and `Plan9.Env`

Conditionally compile the first `caml_plan9_*` primitives into the standard
Plan 9 runtime, keep `plan9.cma` ML-only, and implement the lossless native
environment API.

Prove ordinary linking without `-custom`, `-use-runtime`, or consumer C tools.
Cross-check native `/env` values with `rc` and confirm intentional divergence
from APE's cached environment.

Explicit exclusions:

- no process creation or wait API;
- no `Sys` or `Unix` changes;
- no generic rfork;
- no custom-runtime repair;
- no caml9 integration; and
- no replacement of the known compiler prefix.

## Phase 2: safe native process and wait

Add the combined native rfork-exec primitive, exact exec-error handshake,
managed process handle, faithful wait record, error classification, and
out-of-order wait cache.

The child never returns to OCaml. `RFMEM` remains impossible. Literal argument,
environment-group, namespace, descriptor, note, interruption, error, GC
stress, and cleanup tests must pass independently of caml9.

## Phase 3: constrained low-level API

Expose only the audited current-process and combined rfork-exec operations
whose C entry points make forbidden states impossible. Do not expose a generic
integer mask or stable child-returning rfork.

## Phase 4: custom-runtime repair

Separately repair installed `-custom`, `-make-runtime`, `ocamlmktop -custom`,
`unix.cma`, and third-party C-stub linking on Plan 9. This is useful port
functionality but is not the ordinary `Plan9` packaging path.

## Phase 5: caml9 integration

Only after the independent OCaml tests pass, update caml9 to set native
environment values once and spawn native children that inherit the selected
environment group. Remove command-specific environment forwarding only after
focused CPU-017 branches and the relevant boot behavior pass.

Caml9 developmental acceptance and formal boot promotion remain governed by
the caml9 repository, its stateful operator, and its separately authorized VM
lanes.
