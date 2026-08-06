# Phase 0 native syscall veneer roadmap

Status: completed umbrella roadmap; Phase 0 accepted at
`aa627e94e9db4a680a30c8e3671a00e709a97320`

## Authority and required reading

The authoritative foundation is:

`C:\Users\dharm\src\ocaml\docs\design\plan9-native-io-foundation.md`

This roadmap divides its private Phase 0 proof into three sequential,
independently reviewed and natively validated subphases. It is not itself a
request to implement all of Phase 0 in one task.

The focused execution handoffs are:

1. `plan9-native-syscall-veneer-phase0-1-raw-build.md`;
2. `plan9-native-syscall-veneer-phase0-2-capability-lifecycle.md`; and
3. `plan9-native-syscall-veneer-phase0-3-byte-io-acceptance.md`.

For a subphase, read this roadmap, that subphase's handoff, the foundation
sections it names, the repository `AGENTS.md`, and every applicable local
skill. Later-subphase handoffs are not implementation authority for an earlier
subphase. The complete foundation remains authoritative if a cross-reference
is unclear. If two documents genuinely conflict, stop and ask the user.

## Repository and branch identity

- Authoritative editing repository: `C:\Users\dharm\src\ocaml`.
- Published Plan 9 baseline branch: `plan9-4.14.3-000`.
- Published baseline commit:
  `a98e773a80311653d7a78763bd017328b5c26b52`.
- Local source-and-workflow base:
  `835bc29b0c276a83211a517b950a55f0fb9c2bfe`.
- Sequential implementation branch: `codex/plan9-native-io-foundation`.
- Reviewed documentation checkpoint:
  `4209e21088f8ba0f5c5985fcec79e41d4cffcb77`.
- Accepted Phase 0.1 checkpoint:
  `0d3ac056a37e597e9673607de591cb8a0b5247bb`.
- Reviewed Phase 0.2 documentation checkpoint:
  `3c2fe24efb50aff2b7b00795868228712e01848a`.
- Accepted Phase 0.2 checkpoint:
  `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`.
- Reviewed Phase 0.3 documentation checkpoint:
  `dcbb9f2d2b31a31a7ccf6d946957fa5e132df3d1`.
- Accepted Phase 0 and Phase 0.3 checkpoint:
  `aa627e94e9db4a680a30c8e3671a00e709a97320`.
- Preserved rejected prototype:
  `codex/archive/plan9-process-capture-prototype` at
  `1eb780b1b8467d1b80b35102e40371b87dde5604`.

The foundation, this roadmap, and all three initial subphase handoffs were
committed together at the first documentation-only checkpoint above. A later
subphase review is committed as its own documentation-only checkpoint before
execution. Each executing request names its exact starting `HEAD`; a document
cannot record the identity of the commit that first contains that revision of
itself.

Before any subphase edits code, verify that:

- the branch is exactly `codex/plan9-native-io-foundation`;
- `HEAD` contains the complete reviewed documentation set and every accepted
  predecessor subphase;
- the index and worktree are clean; and
- no unexpected commit, merge, rebase, or unrelated local change is present.

If any condition differs, report the exact state and stop. Do not clean,
stash, reset, or absorb another task's work.

## Phase 0 outcome

Phase 0 proves the smallest private, OCaml-owned Plan 9 syscall path for:

1. native error capture;
2. pipe creation;
3. logical read;
4. logical write; and
5. close.

The final proof establishes that the standard amd64 Plan 9 `ocamlrun`, while
still linked with APE for portable OCaml behavior, performs these operations
without APE I/O or descriptor machinery, APE-private syscall entries, or
native-error translation through `errno` or APE-private error helpers.

Phase 0 adds no installed public `Plan9` API. It produces private runtime
infrastructure, private tests, build integration, evidence, and documentation
needed for the later `Plan9.Fd` design review.

## Sequential execution plan

```text
Phase 0.1: raw ABI and build proof
                  |
                  v
Phase 0.2: capability lifecycle, pipe, close, and error proof
                  |
                  v
Phase 0.3: staged byte I/O and complete Phase 0 acceptance
```

### Phase 0.1: raw ABI and build proof

Accepted at `0d3ac056a37e597e9673607de591cb8a0b5247bb`. It implements the five
checked-in amd64 raw syscall entries, private native
declarations, architecture/build/archive wiring, and a private native harness
that calls only those raw entries for the operations under test. Prove the
assembler and archive facts, raw behavior, raw-object isolation, and cleanup
rules on native Plan 9; those proofs completed during native qualification.

This subphase adds no `CAMLprim`, opaque ML capability, ML test, installed
library content, or public API. Its checkpoint proves only the raw tier and its
build integration.

### Phase 0.2: capability lifecycle

Accepted at `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`. Starting from accepted
Phase 0.1 and the reviewed documentation checkpoint, it implements the private
opaque runtime capability, guarded pipe publication, deterministic close,
native failure construction, and dedicated negative-path error probe, with
the focused private ML tests needed for those operations.

This subphase does not implement general byte read or write primitives. Its
negative probe may use the already accepted raw read entry internally, but no
raw descriptor crosses an ML boundary.

### Phase 0.3: byte I/O and final acceptance

Accepted at `aa627e94e9db4a680a30c8e3671a00e709a97320`. Starting from accepted
Phase 0.2 checkpoint
`f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b` and the exact user-approved Phase
0.3 documentation checkpoint, add the private validated read and write
primitives, bounded staging, pending-action ordering, allocation and rooting
discipline, short/zero-length semantics, and the complete private ML test.
Then perform the full regression, symbol, packaging, clean-build, and
installed-prefix qualification required for final Phase 0 acceptance.

Phase 0.3 concluded that Phase 0 is accepted and stopped for an architectural
regroup before `Plan9.Fd`.

## Shared invariants

Every subphase preserves these rules:

- the project keeps one standard APE-linked `ocamlrun` and the existing
  APE/GNU Make build lane;
- portable `Stdlib`, `Sys`, and `Unix` behavior remains unchanged;
- repository-prefixed raw entries issue the selected native syscalls directly
  and call no C, OCaml runtime, native libc, or APE function;
- the raw tier accepts only native C values and caller-owned buffers;
- runtime integration may use OCaml allocation, rooting, blocking-section, and
  byte-copy facilities, but never APE operating-system I/O for the new path;
- no ML-facing primitive accepts or returns a raw descriptor integer;
- built-in primitive names are treated as callable by hostile correct-arity
  `external` declarations, not as an access-control boundary;
- descriptor release is explicit and deterministic, with no descriptor-closing
  GC finalizer;
- interruption is not retried implicitly;
- native errors are captured immediately before cleanup can replace them and
  are not derived from `errno`; and
- no public name is added to `plan9.mli` or the installed reference.

The initial and only qualified architecture is amd64 9front, using the clean
read-only source reference:

- `/home/dharmatech/src/9front-11554`;
- commit `2191d72205863d2c53ea6ac36991cb4c13204c7c`; and
- the release-qualified mappings recorded in the foundation.

Other Plan 9 architectures receive neither copied amd64 entries nor a silent
APE fallback.

## Review, VM, and checkpoint protocol

Each subphase is a vertical slice owned by one executing task through source
implementation, host-side review, and native validation. Do not split routine
implementation and VM correction between concurrent tasks editing the same
branch. A separate read-only review may be requested after a subphase reports.

For every subphase:

1. Record the starting Git and source state.
2. Implement only that subphase.
3. Run all safe host-side static checks and review the complete diff.
4. Report the proposed code and any design deviation to the user, then pause.
5. Before any VM operation, obtain explicit user confirmation of the exact
   writable instance, loopback address, action, and acceleration profile.
6. Transfer without `.git` through `/mnt/term`, copy onto native Plan 9
   storage, and run the subphase's native qualification there.
7. Report results and stop; do not begin the next subphase.

An install prefix is requested only in Phase 0.3. It must be isolated and
nonexistent unless the user explicitly approves replacement, and the user must
also choose whether it is retained or removed afterward. Never overwrite the
known-working compiler prefix `/usr/glenda/lib/unix/ocaml-4.14.3`; Phase 0.3
records before/after manifests proving it remained unchanged. No VM snapshot
or checkpoint replacement is authorized by these handoffs.

Do not commit or push implementation changes unless the user explicitly asks
in the executing task. A later subphase must not begin from an unreviewed,
known-broken, dirty, or only partially qualified predecessor.

## Final Phase 0 acceptance summary

The detailed criteria live in the foundation and Phase 0.3 handoff. At a
minimum, final acceptance requires:

- a fresh artifact-free native build of the exact approved source set from the
  reviewed worktree;
- correct checked-in raw entries and archive/build integration;
- defensively validated opaque capabilities and deterministic ownership;
- binary pipe round-trip, EOF, short-read, short-write-policy, zero-length,
  forged-value, close, error-preservation, and descriptor-cleanup evidence;
- correct pending-action, staging, rooting, preallocation, and publication
  ordering established by test and source review;
- isolated object/source evidence that the five-operation path avoids APE I/O,
  descriptor machinery, private entries, and `errno` translation;
- existing Plan 9 regression suites passing;
- executed `clean` and `distclean` preservation checks; and
- an approved installed-prefix smoke test proving ordinary bytecode linkage
  with installed `ocamlc`, `ocamlrun`, and ML-only `plan9.cma`.

If installation is not authorized, the installed-prefix criterion remains
open and Phase 0 must not be reported as fully accepted.

## Strictly excluded work

No Phase 0 subphase includes:

- any public addition to `Plan9` or `plan9.mli`;
- `Plan9.Fd`, `Plan9.In_channel`, `Plan9.Out_channel`, `Plan9.File`,
  `Plan9.Stat`, `Plan9.Directory`, or `Plan9.Command`;
- modification or migration of `Plan9.Env`, `Plan9.Raw`, or `Plan9.Process`;
- process creation, capture, line splitting, `dup`, `rfork`, `exec`, `exits`,
  or `await`;
- standard-descriptor adoption or raw descriptors at any ML boundary;
- changes to portable `Stdlib`, `Sys`, or `Unix`;
- a second runtime, removal of APE, custom-runtime repair, native-code support,
  shared libraries, or systhreads;
- temporary-file I/O, shell commands, or external service behavior; or
- VM snapshots, checkpoint replacement, release publication, or Caml9 changes.

If excluded work appears necessary, stop and return the evidence rather than
expanding the subphase.

## Shared completion report

Every subphase reports:

- adopted foundation, roadmap, and focused-handoff paths;
- exact starting branch, `HEAD`, predecessor checkpoint, tested tree, and final
  committed or uncommitted identities;
- selected 9front source and guest release/architecture provenance;
- files changed and why;
- implemented raw symbols, primitive shapes, staging choices, or build wiring
  relevant to that subphase;
- every host and native command with pass/fail result;
- symbol/source audit and APE-independence evidence relevant to that subphase;
- descriptor, temporary-file, source-tree, VM, listener, and writable-disk
  postconditions;
- every deviation, uncertainty, open criterion, or skipped gate; and
- final worktree, index, branch, and remote-tracking status.

Phase 0.3 additionally reports installed-prefix and `plan9.cma` packaging
evidence and ends with exactly one recommendation:

- **Phase 0 accepted; ready for architectural regroup before `Plan9.Fd`**;
- **implementation ready but native qualification still required**; or
- **Phase 0 blocked or rejected**, with the exact reason.

No report may claim that the entire runtime is APE-free. The final claim is
only that the reviewed five-operation path is independent of APE's
operating-system I/O and descriptor machinery inside the existing APE-linked
runtime.
