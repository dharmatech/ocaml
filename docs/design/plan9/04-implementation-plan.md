# Plan 9 implementation plan

The Phase 2 ordering and contracts in this document promote the accepted
[P2 process-primitives design package](exploration/process-primitives/README.md).
Each operational, implementation, validation, publication, and integration
step still requires its own authorization.

## Phase 0: onboarding

Create and review the repository guidance, native API requirements,
Windows-to-Plan-9 workflow, local compiler-lab skill, current-state record, and
runbook. No compiler source, guest, VM, or installed prefix changes occur.

## Phase 1: built-in packaging and `Plan9.Env`

Add the Plan 9-only otherlib, keep `plan9.cma` ML-only, and implement the
lossless native environment API directly against `/env` using the existing
runtime's file-I/O machinery. This phase adds no C stubs or external
primitives. The library and installation layout must remain compatible with
later built-in process primitives in the standard Plan 9 runtime.

Prove ordinary linking without `-custom`, `-use-runtime`, or consumer C tools.
Cross-check native `/env` values with `rc` and confirm intentional divergence
from APE's cached environment.

Explicit exclusions:

- no process creation or wait API;
- no `Sys` or `Unix` changes;
- no generic rfork;
- no C stubs or runtime primitive changes;
- no custom-runtime repair;
- no caml9 integration; and
- no replacement of the known compiler prefix.

Phase 1 was accepted on 2026-07-24 from exact tested index tree
`7dee13d2b8c9fd159cb90d9834ea7100e5592e3b`, whose
`otherlibs/plan9` subtree is
`c7c4d0b98ee94c7ca0fe601244af917dc02ee33f`. A fresh native build and
isolated-prefix install passed the complete environment suite, rc and APE
launch cross-checks, installed `ocamlobjinfo` inspection, and an ordinary
installed consumer link with fail-closed C-tool sentinels. The production
compiler prefix remained byte-for-byte unchanged.

The acceptance documentation was added after that exact tested index. It
records the result but is not part of the source archive that produced the
tested binaries.

## Phase 2: safe native process primitives

Phase 2 adds the canonical API from
[01-native-api-requirements.md](01-native-api-requirements.md):

- built-in Plan 9 runtime primitives with an ML-only `plan9.cma`;
- `Plan9.Raw.copy_environment` and exact-vector `Plan9.Raw.exec`;
- one combined child-nonreturning rfork/exec spawn primitive;
- native pending-child ownership before interruptible post-rfork work;
- handle-preserving `Process.spawn`, `Process.run`, and wait results;
- a synchronous exclusive wait coordinator with no background reaper;
- unique process identities and PID-reuse-safe routing;
- bounded foreign-completion retention with retryable backpressure; and
- faithful native wait messages, timings, and failure distinctions.

The following order is required.

### Gate 2.1: cross-repository record reconciliation

Before any new stateful Phase 2 work:

1. revalidate the live OCaml repository and halted compiler-lab boundary;
2. preserve the completed Phase 1 record;
3. use an explicit documentation handoff to correct dated caml9 ownership
   descriptions without inspecting or changing caml9 operational state;
4. record one sole stateful operator; and
5. name the exact next stateful gate identically in both handoffs.

This is record-only work. It does not boot, probe, transfer, build, install,
or implement.

### Gate 2.2: harmless installed-ABI evidence

Run a separately authorized
`plan9-phase-2-process-primitives-abi-probe-001` before implementation. It may
measure declarations, symbols, flag values, exact exec vectors, wait layout
and units, native messages and errors, `OCEXEC` and `#d/<fd>`, bounded
error-frame feasibility, descriptor collisions, interruption observations,
current-process `RFENVG`, and short-lived child ordering.

It must use bounded purpose-built probes and must not start or inspect auth,
keyfs, listeners, real services, caml9, or long-lived children. It changes no
compiler prefix and contains no candidate OCaml implementation.

### Gate 2.3: Windows-source implementation

Implement against the measured ABI in the authoritative Windows checkout.
This gate changes source and focused host-checkable tests only; it does not
boot or build unless separately combined with an explicitly authorized native
gate.

#### Runtime and primitive mutations

- Conditionally compile the `caml_plan9_*` implementations only for Plan 9.
- Register every primitive exactly once in the standard `ocamlrun` and the
  bytecode compiler's generated known-primitive table.
- Add the exact current-process environment-copy primitive.
- Add exact current-process exec.
- Add the combined fixed-policy `RFPROC | RFFDG | RFREND` spawn primitive.
- Preallocate and publish the native pending-child record before interruptible
  post-rfork work.
- Implement the bounded versioned exec-error frame and collision-safe
  descriptor moves.
- Add the single native await boundary needed by the ML coordinator.
- Reject `RFMEM`, `RFNOWAIT`, `RFNOMNT`, unknown masks, generic masks, and
  child-returning rfork at the C entry points.
- Keep await out of the spawn primitive and all OCaml execution out of the
  child.

#### ML library mutations

- Keep `plan9.cma` ML-only and keep `Sys` and `Unix` unchanged.
- Add the canonical types and constructor names once, without a transitional
  public API.
- Synthesize high-level argv0 while keeping `Raw.exec` exact.
- Adopt native pending records idempotently by never-reused process ID.
- Implement handle-local terminal memoization and the active PID map.
- Implement one synchronous coordinator for wait, wait-any, run, and known
  exec-failure cleanup.
- Implement the bounded foreign FIFO, queued-foreign-first `wait_any`, FIFO
  drainage, and retryable particular-handle backpressure.
- Implement exact `No_children` loss for both adopted and native-pending
  owners.
- Implement distinct failed-closed invariant and malformed-record states that
  preserve unresolved ownership and stop further native await.

#### Focused source tests

Add direct primitive validation tests, ownership and adoption state-machine
tests, frame and descriptor-collision tests, literal argv tests, out-of-order
completion tests, FIFO backpressure and retry tests, exact loss tests,
coordinator-failure tests, process-ID exhaustion tests, blocking-runtime
tests, and ordinary packaging checks.

Do not introduce a temporary APE process backend, private wait path,
environment replay map, shell wrapper, PID-only completion cache, public raw
waiter, generic rfork, or custom-runtime requirement.

### Gate 2.4: exact-source native qualification

Stage only the reviewed candidate, record the exact index and relevant
subtrees, export a deterministic archive, transfer only that archive, and
build it on fresh native Plan 9 storage.

Use a new versioned experimental prefix. Prove:

- full bytecode-world build and install;
- built-in primitive-table agreement;
- ML-only `plan9.cma`;
- ordinary `ocamlc -I +plan9 plan9.cma ...` use without consumer C tools;
- complete primitive, launch, wait, lifecycle, and cleanup suites from
  [03-verification-and-recovery.md](03-verification-and-recovery.md);
- no changes to the known-working compiler prefix; and
- clean VM, endpoint, QCOW2, evidence, and source-identity postflight.

Independent OCaml qualification must pass before caml9 integration.

### Gate 2.5: optional stateful service evidence

If `keyfs`, `aux/listen`, daemonization, descendant, or listener behavior
remains unresolved after the harmless ABI and implementation gates, authorize
a separate disposable service-behavior probe. It must use synthetic data,
private containment, an explicit process and endpoint inventory, credential
protections, cleanup, and recovery.

Do not fold service startup into the harmless ABI probe. Passing service
evidence is not itself caml9 boot acceptance.

## Phase 3: caml9 integration

Only after independent OCaml qualification and any required service evidence:

1. finalize globally intended `NPROC`, `sysname`, and prompt values;
2. call `Plan9.Raw.copy_environment ()` once;
3. write derived `auth` and `serviced` through `Plan9.Env` in the copied
   group;
4. use `Plan9.Process.run`, or spawn followed by wait through the same
   coordinator, for each direct `auth/keyfs` or `aux/listen` launcher;
5. resolve each direct launcher before continuing;
6. preserve the exact native completion and apply stock continuation policy
   only after terminal resolution; and
7. use any remaining `Sys.command` or APE child/wait path only after the
   managed exclusivity interval has closed.

The direct launcher and any service descendant it leaves behind are distinct
lifecycles. Caml9 developmental acceptance and formal boot promotion remain
governed by the caml9 repository, its stateful operator, and separately
authorized VM lanes.

Do not remove the current caml9 compatibility rule until the independently
qualified native facility passes its own integration gate.

## Phase 4: custom-runtime repair

Separately repair installed `-custom`, `-make-runtime`, `ocamlmktop -custom`,
`unix.cma`, and third-party C-stub linking on Plan 9. This is useful port
functionality but is not a prerequisite for ordinary `Plan9` use and must not
become the process-primitives packaging path.

## Deferred work

The following remain outside Phase 2:

- `RFNOMNT` or a broader sandboxing policy;
- arbitrary descriptor action lists, pipelines, or stderr routing;
- a public raw native waiter;
- generic or child-returning rfork;
- `Raw.Unsafe` runtime experiments;
- a fully non-APE runtime;
- replacement of GNU Make or the POSIX build shell;
- native-code compilation, shared libraries, or systhreads; and
- changes to portable `Sys` or `Unix` semantics.
