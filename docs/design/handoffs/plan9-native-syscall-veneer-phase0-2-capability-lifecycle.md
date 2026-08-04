# Phase 0.2 capability lifecycle handoff

Status: execute only after an accepted Phase 0.1 checkpoint

## Authority and required reading

This handoff delegates only Phase 0.2. Before editing, read:

- `docs/design/handoffs/plan9-native-syscall-veneer-phase0.md` completely;
- the accepted Phase 0.1 completion report and implementation diff;
- the foundation's repository identities, APE-independence boundary, qualified
  source facts, private syscall veneer sections on internal tiers, capability
  defense, error handling, OCaml heap/blocking sections, proposed source
  boundary, and Phase 0 acceptance criteria;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before their actions occur.

Do not implement Phase 0.3 or `Plan9.Fd`. If the accepted Phase 0.1 result does
not match the assumptions below, stop and return the mismatch for design
review.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. Record the exact starting `HEAD` and verify
that it is the user-approved Phase 0.1 checkpoint, with a clean index and
worktree and no unexpected history.

Do not begin from an uncommitted, dirty, unqualified, or rejected Phase 0.1
tree. Do not stash, reset, clean, or absorb unrelated work.

## Delegated outcome

Add the minimum OCaml runtime integration needed to prove:

- opaque runtime-owned descriptor capabilities;
- preallocated, all-or-nothing pipe ownership publication;
- deterministic terminal close with idempotent repetition;
- immediate native error capture and private native-failure construction; and
- a dedicated negative-path probe that exercises raw error capture without
  exposing an integer descriptor to ML.

This subphase uses the accepted raw `ERRSTR`, `PIPE`, `PREAD`, and `CLOSE`
entries. The raw `PWRITE` entry remains present but is not exposed through an
ML primitive yet.

Phase 0.2 adds no general ML-facing read or write primitive, byte staging,
public API, installed interface, or `plan9.cma` C payload.

## Threat model and capability boundary

A built-in primitive remains callable through a user-declared `external` even
when no interface installs it. Treat every correct-arity primitive call as
receiving arbitrary well-formed OCaml values, including false types introduced
through `Obj.magic`.

Deliberately wrong `external` arities and mutation, truncation, retagging, or
duplication of a valid capability through unsafe `Obj` representation
operations remain outside the supported contract. Do not add a global
ownership registry merely to defend against those operations. The capability
must have no descriptor-closing GC finalizer; release remains explicit.

No primitive may accept or return a raw descriptor integer. A capability must
be accepted only when it was created by this runtime path and is in the state
required by the operation.

Before reading representation-specific payload, validate in this order:

1. immediate versus block;
2. expected tag;
3. sufficient or exact block size, as appropriate; and
4. runtime-owned capability identity.

Only then may code inspect capability state or its native descriptor. A forged
look-alike must never trigger an out-of-bounds access or dereference
attacker-controlled metadata.

The Phase 0.2 capability is guarded private runtime state, not the future
public `Plan9.Fd` shared ownership cell or attachment protocol.

## Required runtime integration

### Source boundary

Add `runtime/plan9_syscall.c` for validated OCaml runtime integration. Extend
`runtime/plan9_syscall.h` only with private native declarations genuinely
shared with it. Make the minimum Plan 9-only runtime build and primitive-table
changes.

Private ML tests belong under `otherlibs/plan9/tests`. They may declare exact
private `external` bindings and the existing private native-failure shape, but
no new name may appear in `plan9.mli`, installed documentation, or another
public interface.

No primitive may allocate or construct an OCaml value while inside a blocking
section.

### Pipe publication

Before calling raw `PIPE`, allocate, initialize to safe closed/unpublished
states, and root:

- both opaque capabilities;
- their pair container; and
- every structural success block needed to return the owning result.

Every scanned block must contain GC-safe values before any later allocation.
After successful native acquisition, publish both descriptors into the rooted
capabilities and return without another fallible allocation, callback, or safe
point. If an allocation could still fail, close both descriptors before taking
that path. Source review must account for the exact blocking-section exit and
prove that the post-acquisition path cannot raise before publication.

The qualified kernel `syspipe`/`newfd2` implementation publishes its pair
atomically and cleans both channels on native failure. Capture `ERRSTR`
immediately after a negative raw result, before leaving the blocking section
or performing cleanup. Only after the native text is safe may ML failure
allocation occur.

### Deterministic close

Before native close, check for and process pending OCaml actions while every
live value and preallocated success result is rooted. Pending processing may
allocate, invoke a callback, close the same capability, or raise. Revalidate
the capability afterward.

On the successful native-work path, perform no allocation, safe point, or
pending-action processing after that revalidation. Save the descriptor and
terminalize the capability at a nonraising commit point immediately before
`caml_enter_blocking_section_no_pending`, which must lead directly to raw
close.

Repeated close is idempotent and performs no second syscall. If raw close or
later failure-result construction fails, the capability remains terminal so an
uncertain descriptor cannot be reused. Preallocate a success container unless
the chosen successful representation is immediate and allocation-free. After
a successful raw close, publish that preallocated or immediate success without
a fallible allocation.

Source review must confirm that the selected standard runtime hooks are
nonraising under the Phase 0 no-systhreads configuration and that the ordering
matches the established check-pending, re-read-state, non-pending-entry pattern
in `runtime/io.c`.

### Native failure shape

Use the existing private shape containing `native_kind` and `native_message`.
The runtime integration returns that private value; later ML layers assign the
high-level operation and convert it into `Plan9.error`. Do not construct the
public error record in C or add a second public error hierarchy.

A negative raw result is followed immediately by raw `ERRSTR` into an initially
empty, bounded 128-byte buffer before leaving the blocking section or making a
cleanup syscall. Do not use native `rerrstr`, `errno`, or an APE-private error
helper.

### Dedicated negative-path probe

Add a private probe taking no ML descriptor. It must:

1. obtain a locally owned raw pipe pair;
2. close the selected target using the accepted raw close entry;
3. only if close succeeds, invoke raw read on the saved integer and capture
   `ERRSTR` immediately after its negative result;
4. close every other definitely owned local resource; and
5. return only the structured failure to ML.

Every operation while the probe owns a raw descriptor uses the non-pending
discipline and crosses no ordinary pending-processing entry. If the deliberate
close unexpectedly fails, capture that close error immediately, never retry
the now-uncertain target, close only other definitely owned resources, and
return without reading. Cleanup must preserve the original failing-operation
error.

## Required tests and review evidence

At minimum, the private ML test and source review must establish that:

- the pipe primitive rejects malformed unit arguments before native work;
- raw integers, immediate values, forged blocks, forged look-alike blocks, and
  capabilities in the wrong state are rejected before native work;
- validation checks shape, tag, size, and runtime identity before payload;
- successful pipe acquisition publishes two opaque capabilities without a
  post-acquisition fallible allocation;
- neither capability exposes its integer descriptor to ML;
- closing each capability succeeds and leaves no owned endpoint;
- closing through an ML alias terminalizes that same capability;
- repeated close succeeds idempotently without a second syscall;
- an unexpected close failure cannot make the capability usable again;
- pending actions occur before final close validation, followed immediately by
  terminalization and the non-pending entry with no intervening safe point;
- successful raw close reaches publication without a fallible allocation;
- the negative probe returns a nonempty immediate native read error without
  `errno` translation or descriptor exposure;
- the probe does not read after an unexpected close failure, does not retry the
  uncertain close, cleans only definitely owned resources, and preserves the
  original error; and
- repeated pipe/close/probe runs have clean descriptor postconditions.

The Phase 0.1 native raw harness must retain its accepted behavior. Existing
`otherlibs/plan9` tests must also remain unchanged in behavior.

## Symbol, source, and packaging audit

Record evidence that:

- each new `CAMLprim` appears exactly once in the generated primitive table and
  has one linked definition in the standard Plan 9 `ocamlrun`;
- the runtime integration object references repository-prefixed raw entries,
  not `_PIPE`, `_PREAD`, `_READ`, `_CLOSE`, `_ERRSTR`, or ordinary OS I/O;
- source contains no `_fdinfo`, raw ML descriptor conversion, `errno`
  translation, APE registration, or private `sys9.h` inclusion in the new path;
- the accepted raw object remains free of undefined library calls and forbidden
  references; and
- `plan9.cma` remains ML-only and no public interface or installed reference
  changes.

The primitive generator ends with `sort | uniq`; inventory membership alone
does not prove unique discovery. Inspect the generated table and linked
definitions separately.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state, the accepted Phase 0.1 identity and report, current runtime
hooks, allocation helpers, custom-block conventions, build rules, and
primitive-generation inputs. Implement only Phase 0.2.

### 2. Source review before VM work

Run safe host-side checks, inspect the full diff from the Phase 0.1 checkpoint,
and review validation ordering, allocation/rooting, pending actions,
terminalization, error capture, and cleanup. Report to the user and stop before
VM access.

### 3. Explicit VM confirmation

Obtain user confirmation of the exact writable instance, loopback address,
action, and acceleration profile. Use the repository VM and native-build
skills. Transfer without `.git`, copy onto native storage, and never build on
`/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record guest and toolchain identity and verify the accepted amd64 release.
2. Create a fresh artifact-free native copy of the exact reviewed tree.
3. Configure and build through the existing APE/GNU Make lane.
4. Run the Phase 0.1 raw harness, the focused Phase 0.2 ML test, and existing
   Plan 9 regression suites.
5. Perform primitive uniqueness, linked-definition, raw-object, integration
   object, and public-interface audits.
6. Record descriptor, temporary-file, tree, VM, listener, and disk
   postconditions.

No installation or installed-prefix change is authorized in Phase 0.2.

### 5. Report and stop

Do not implement general byte reads or writes, begin Phase 0.3 or `Plan9.Fd`,
install, merge, tag, or publish. Commit and push only if the user explicitly
asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact capability representation and validation sequence;
- exact private primitive names and ML result shapes;
- allocation/rooting and pipe-publication proof;
- pending-action and close-commit proof;
- native-failure and negative-probe cleanup proof;
- primitive uniqueness, linked raw symbol, APE-isolation, ML-only packaging,
  and public-interface evidence; and
- one recommendation:
  - **Phase 0.2 accepted; ready to checkpoint and regroup before Phase 0.3**;
  - **implementation ready but native qualification still required**; or
  - **Phase 0.2 blocked or rejected**, with the exact reason.
