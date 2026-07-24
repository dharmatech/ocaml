# P2-004: Corrected native process-primitives design

Status: proposed

Origin: OCaml Plan 9 port task

Materialized by: OCaml Plan 9 port task

Responds to: [P2-003](P2-003-caml9-process-design-review.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, published HEAD
`351d53555cbb1268271665840e4b778734c6aa17`, tree
`5b608847e1f549ed441c76352a8b7abc11cff60e`, and synchronized origin,
with an unchanged index, a modified exchange README, and untracked P2-002 and
P2-003 at the accepted documentation handoff

Canonical impact: none yet; this corrected exploration design requires caml9
review before any conclusion is promoted to canonical design or implementation

Requested next action: caml9 review of P2-004 under the exclusive
documentation lease, with no canonical, implementation, publication, or
operational action

## Purpose and design layer

This document answers every required correction and checklist item in P2-003.
It supersedes the operative recommendations in the historical
[P2-002](P2-002-ocaml-initial-process-design.md) proposal where the two
documents disagree. It does not rewrite either historical document.

The layers remain distinct:

- P2-002 records the initial proposal.
- P2-003 records the caml9 review.
- P2-004 is the corrected exploration design.
- The canonical Plan 9 documents remain unchanged until a later accepted
  promotion gate.
- Runtime and ML source remain unchanged until a later implementation gate.
- Source contracts settle architectural facts.
- A harmless guest probe may settle only installed ABI behavior.
- Stateful service and caml9 behavior require later, separately authorized
  gates.

This documentation gate did not inspect or operate a VM, guest, endpoint,
compiler prefix, service, or caml9 repository.

## Overall disposition

The architectural foundation accepted by P2-003 remains:

- built-in primitives in the standard Plan 9 `ocamlrun`;
- an ML-only, Plan 9-only `plan9.cma`;
- ordinary linking without `-custom` or consumer C tools;
- one combined native rfork/exec spawn primitive;
- no return into OCaml in the child;
- unconditional defensive rejection of `RFMEM`;
- default child flags `RFPROC | RFFDG | RFREND`;
- faithful native wait data;
- focused inherited or truncate-file stdout; and
- independent Plan9.Process qualification before caml9 integration.

The required corrections are disposed as follows:

| P2-003 correction | Disposition | Reason |
| --- | --- | --- |
| CPU-017 environment-group ownership | Accepted | A one-time current-process `RFENVG` split preserves global values without polluting init with derived service values |
| One native wait-queue owner | Accepted with detection refinement | Plan9.Process owns native await; loss is terminal when observable, but arbitrary theft cannot be distinguished from a live child before native evidence exists |
| Exec-failure and interruption ownership | Accepted and made concrete | A preallocated native pending-child registry owns every post-rfork child before any interruptible handshake step |
| Native wait naming | Accepted with timing-name refinement | `message` replaces `status`; `elapsed_time_ms` continues to name the third native timing field pending ABI width and unit confirmation |
| Defer `RFNOMNT` | Accepted | It is unnecessary and does not compose with the preferred `#d/<fd>` handshake |
| Raw versus high-level argv | Accepted | Raw.exec preserves the exact nonempty vector; Process synthesizes argv0 from `program` |
| Split ABI and service probes | Accepted | Harmless ABI evidence and stateful service behavior have different mutation and containment risks |
| Cross-repository state reconciliation | Accepted as a prerequisite | The record-only reconciliation must occur before, not inside, the next stateful gate |

No P2-003 correction is rejected. The wait-loss refinement rejects only an
unimplementable stronger promise: no library can prove that an external waiter
stole one particular completion while another managed child may still be
alive and the kernel has supplied no distinguishing evidence.

## Corrected public boundary

The exact surface syntax remains reviewable, but the ownership distinctions
are now fixed.

```ocaml
type error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

exception Error of error

type pid = private int
type process_id = private int64

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

val wait_succeeded : wait_msg -> bool

module Raw : sig
  val copy_environment : unit -> (unit, error) result

  val exec :
    program:string ->
    argv:string array ->
    ('a, error) result
end

module Process : sig
  type t

  type stdout =
    | Inherit
    | Truncate of string

  type launch_incomplete =
    | Exec_failure_unreaped of error
    | Handshake_interrupted of error
    | Handshake_protocol_error of error

  type launch =
    | Started of t
    | Incomplete of {
        process : t;
        reason : launch_incomplete;
      }

  type wait_failure =
    | Wait_error of error
    | Wait_queue_lost of error
    | Wait_protocol_error of error

  type completion =
    | Managed of t * wait_msg
    | Foreign of wait_msg

  val spawn :
    ?stdout:stdout ->
    program:string ->
    args:string array ->
    (launch, error) result

  val id : t -> process_id
  val pid : t -> pid

  val wait : t -> (wait_msg, wait_failure) result
  val wait_any : unit -> (completion, wait_failure) result

  val unresolved : unit -> t list
  val take_foreign_completions : unit -> wait_msg list
end
```

An outer `Error` from `Process.spawn` means no outstanding child remains:

- validation, parent-side setup, or rfork failed before a child existed; or
- the child reported exec failure and the shared coordinator confirmed that
  it was reaped before `spawn` returned.

If a child may still be live or waitable, the result is handle-bearing
`Incomplete`, never a plain `Error`.

The first high-level API does not expose arbitrary descriptor actions,
pipelines, stderr routing, PATH search, shell syntax, or environment overlays.
Additional safe isolation options may be added only when independently
justified. The CPU-017 default remains fixed and does not require a raw mask.

## Correction 1: CPU-017 environment-group boundary

### Disposition: accepted

The public operation is:

```ocaml
Plan9.Raw.copy_environment : unit -> (unit, Plan9.error) result
```

Its only native effect is the current-process equivalent of
`rfork(RFENVG)`. It does not include `RFPROC`, does not create a child, and
returns once to the calling OCaml process. The C primitive accepts no integer
mask and independently enforces that exact operation.

The CPU-017 sequence is:

1. Finalize globally intended `NPROC`, `sysname`, and prompt values in the
   original current environment group.
2. Call `Plan9.Raw.copy_environment ()`.
3. The continuing boot process now belongs to a copied private environment
   group containing those finalized global values.
4. Write derived `auth` and `serviced` with `Plan9.Env` after the split.
5. Spawn service children with the default process flags, omitting both
   `RFENVG` and `RFCENVG`, so they share the deliberately selected private
   group.
6. The original group visible to init retains the global values but never
   receives the derived service-only writes.

No reviewed later boot step requires rejoining the original environment group.
Because the split is intentionally one-way, caml9 must place it only after all
global environment publication is complete. Contrary source evidence would
require another design review rather than an environment replay mechanism.

A separate copied environment for every child is rejected for the initial
implementation. It would complicate ordering, prevent a family of services
from naturally sharing one prepared live group, and encourage child-side
override serialization.

The source contract establishes the intended `RFENVG` meaning. The harmless
ABI probe must confirm installed behavior: pre-existing values are copied,
post-split mutations do not cross in either direction, and no child is
created.

## Correction 2: exclusive native wait ownership

### Disposition: accepted with a detection refinement

The Plan9.Process coordinator is the only component permitted to invoke native
await while any managed child or native pending-child record remains
unresolved.

Consequences:

- `Plan9.Raw.wait_any` is removed.
- `Process.wait`, `Process.wait_any`, known exec-failure reaping, and
  incomplete-handle resolution all route through the same coordinator.
- `Sys.command`, `Unix.wait`, APE wait functions, and unrelated native waiters
  are prohibited while a managed child is unresolved.
- The restriction starts when rfork creates the first managed child, before
  the exec handshake.
- It ends only when no native pending record and no managed unresolved handle
  remains.
- Sequential use of another child/wait facility is supported only outside
  that interval.

During incremental caml9 migration, every remaining `Sys.command` operation
that may create or wait for a child must finish before the first long-lived
Plan9.Process child is launched. After that point, later commands must also
use Plan9.Process or wait until all managed children have resolved.

### Observable wait loss

If native await reports the exact no-living-children error while the
coordinator still has unresolved waitable handles, the coordinator atomically
marks them `Wait_queue_lost`. Their future `Process.wait` calls return the
memoized terminal `Wait_queue_lost` result rather than calling await again.

An arbitrary external waiter may steal one child's completion while another
child remains alive. Before the kernel reports no children, that state is
indistinguishable from the first child still running. The library therefore
cannot promise finite-time automatic detection without a timeout, note, or
external lifecycle oracle. Phase 2 does not invent such an oracle.

This is why mixing is unsupported, not merely discouraged. Tests avoid hangs
by using bounded purpose-built children, ensuring every test child terminates,
and driving the coordinator to either a completion or exact `No_children`.
Interruption is returned and not automatically retried.

### Handle identity, PID reuse, and foreign completions

This part of correction 2 is accepted.

Every managed child receives a library-unique monotonic `process_id` in
addition to its native PID. The process ID is allocated before rfork and is
never reused during the runtime instance.

The coordinator maintains:

- an active map from PID to exactly one unresolved handle;
- terminal state stored on the handle, not in a permanent PID table; and
- a bounded FIFO of foreign completions observed for unknown PIDs.

On a known completion:

1. find the active handle by PID;
2. atomically remove the PID mapping;
3. store the completion on that exact handle; and
4. make every repeated wait return the handle's memoized terminal result.

On an unknown completion:

1. classify it as foreign at the moment it is reaped;
2. assign it no managed handle;
3. return it through `Process.wait_any` or retain it in the bounded foreign
   FIFO while a particular-handle wait continues; and
4. never attach it to a later handle whose PID happens to match.

If the foreign FIFO reaches its bound, the coordinator returns a protocol
error and stops consuming further wait records until the caller drains the
FIFO. It never silently drops or overwrites a wait record.

A PID collision with an already active handle is a fail-closed protocol error.
The design does not rely on the kernel never reusing a PID after the earlier
handle became terminal.

## Correction 3: durable ownership and exec failure

### Disposition: accepted and made concrete

Durable ownership begins inside the parent branch of the combined C primitive,
immediately after native rfork returns a positive PID and before:

- reading the handshake pipe;
- entering an interruptible blocking section;
- allocating an OCaml result;
- processing an asynchronous exception; or
- returning to ML.

Before rfork, the primitive allocates a C-owned pending-child record containing
the unique process ID, prepared policy, and all storage required to publish
the PID. After successful rfork, publishing that preallocated record into the
runtime-global pending-child registry requires no allocation.

The record remains in the native registry until the ML coordinator:

1. creates and stores the managed handle;
2. inserts the active PID mapping; and
3. acknowledges adoption by the unique process ID.

Only that acknowledgment removes the native pending record. If an asynchronous
exception occurs while leaving a blocking section or materializing the ML
result, `Process.unresolved ()` can adopt the still-registered child. There is
no interval in which the child exists without a recoverable owner.

The registry design is an implementation decision selected here. It is not
delegated to the guest probe. The probe may exercise interruption, but it
cannot choose the ownership architecture.

### Private primitive state

The private primitive result is conceptually:

```text
No_child(error)

Registered {
  process_id;
  pid;
  handshake =
    Exec_confirmed
  | Exec_failed(native_error)
  | Indeterminate(handshake_error)
}
```

`No_child` is the only result that can immediately become a plain outer Error.
Every `Registered` result names a native registry record and therefore a
recoverable managed handle.

The C primitive never calls await.

### Known exec failure

When the frame reports exec failure:

1. ML adopts the registered handle.
2. The shared coordinator waits for that PID.
3. Any other known completion is stored on its own handle.
4. Any unknown completion is classified as foreign immediately.
5. If the failed child is confirmed reaped, the handle becomes terminal and
   `spawn` may return the preserved exec error as an outer Error because no
   child remains outstanding for that launch.
6. If waiting is interrupted or loss is detected, `spawn` returns
   `Incomplete { process; reason = Exec_failure_unreaped error }`.

No exec-failure child is privately reaped by the primitive, and no unrelated
wait message is discarded.

### Interrupted or malformed handshake

Clean EOF before any frame byte means exec success.

A complete, valid error frame means known exec failure.

Interruption before the outcome is proved yields
`Handshake_interrupted`. A truncated header or payload, invalid tag, invalid
length, trailing data, or premature EOF yields `Handshake_protocol_error`.
Both are handle-bearing incomplete launches.

The caller may inspect `Process.unresolved`, call `Process.wait`, and retain
the launch diagnosis separately from the eventual native completion.

### Bounded frame

The proposed wire format is:

```text
4 bytes  ASCII tag and version: "P9E1"
4 bytes  unsigned big-endian payload length
N bytes  native error text, with N no greater than the measured fixed maximum
EOF      required immediately after the payload
```

The child writes from preallocated storage, handles short writes without
allocating, and calls `_exits`. The parent performs complete reads into bounded
C-owned storage. The ABI probe measures the installed native error bound; the
implementation rejects any length beyond the compiled bound and preserves the
payload bytes as the error message.

The handshake descriptor is allocated and made close-on-exec before rfork.
Child redirection is ordered through collision-safe descriptor moves so that
closed or reused descriptors 0, 1, and 2 cannot replace, leak, or close the
handshake endpoint.

## Correction 4: native wait naming

### Disposition: accepted with a timing-name refinement

The public field is `message`, matching the semantic role of native
`Waitmsg.msg`. The complete native text is retained, including any native
process-name or PID prefix. It is never normalized into only the argument
passed to `exits`, a Unix integer status, or a signal constructor.

`wait_succeeded m` is true exactly when `m.message = ""`.

The third timing field remains named `elapsed_time_ms`, because it describes
elapsed/real wall time without overloading the generic word `real`. The
harmless ABI probe must confirm the installed width and unit conversion for
all three fields before implementation acceptance.

## Correction 5: defer RFNOMNT

### Disposition: accepted

Phase 2 exposes no `Forbid_mounts`, `RFNOMNT`, generic safe-flag list, or raw
integer mask.

`RFNOMNT` is unnecessary for CPU-017 and may prevent the `#d/<fd>` open needed
by the preferred handshake. It belongs, if anywhere, in a later separately
designed sandboxing facility with its own composition and recovery tests.

Removing it does not weaken the permanent rejection of `RFMEM`, child-returning
rfork, `RFNOWAIT`, clean resource groups, or unknown flags.

## Correction 6: raw and high-level argv

### Disposition: accepted

`Plan9.Raw.exec` accepts the exact nonempty native vector and never rewrites
`argv[0]`. It rejects:

- an empty vector;
- embedded NUL in the program or any argument;
- lengths or aggregate allocation that overflow the native representation; and
- malformed OCaml values even when the primitive is invoked directly.

`Plan9.Process.spawn` accepts `program` and an `args` array. It constructs:

```text
argv = [| program; args.(0); ...; args.(n - 1) |]
```

An empty high-level `args` array is valid and produces a one-element vector.
There is still no PATH search, shell, quoting, globbing, redirection parsing,
or environment expansion.

The corrected design keeps arrays rather than requiring lists because the
native boundary is an indexed vector and the existing OCaml process APIs use
arrays for argv. This is a surface-syntax refinement, not a rejection of
P2-003's argv0 rule.

## Correction 7: separate probe classes

### Disposition: accepted

### Harmless ABI probe

The next possible guest gate remains separately authorized and is limited to
`plan9-phase-2-process-primitives-abi-probe-001`.

It may establish:

- installed header declarations and symbol linkability;
- native flag values and source-contract consistency;
- exact-vector exec behavior in purpose-built bounded programs;
- wait field widths, units, formatting, native messages, and exact errors;
- `#d/<fd>` reopening with `OCEXEC`;
- the fixed bounded error-frame feasibility and malformed cases;
- inherited stdout and parent-opened disposable-file redirection;
- descriptor collisions involving 0, 1, and 2;
- bounded interruption observations;
- current-process `RFENVG` copy and isolation; and
- completion ordering with short-lived purpose-built children.

It must not start or inspect `auth/keyfs`, `aux/listen`, real service
directories, authentication services, listeners, caml9 executables, or
long-lived processes. It does not modify an installed compiler prefix and does
not implement OCaml source.

### Stateful service-behavior probe

`plan9-phase-2-service-behavior-probe-001` is a later, separately authorized
gate only if installed service behavior still requires direct evidence.

Its authorization must name:

- a disposable scratch lab;
- a unique address and complete endpoint policy;
- private namespace and environment boundaries;
- synthetic rather than production key and service data;
- permitted guest mutations;
- service process and descendant inventory;
- cleanup and shutdown behavior;
- credential protections;
- retained evidence; and
- failure recovery.

Passing the harmless ABI probe is not CPU-017 service or boot acceptance.

## Correction 8: cross-repository operational state

### Disposition: accepted as a prerequisite, not performed here

Before the next stateful VM, endpoint, transfer, build, installation, or probe
gate, the sole stateful operator must perform a separately authorized
record-only reconciliation:

1. Revalidate the live OCaml repository, `.40` instance, disk relationship,
   process state, and all assigned listeners.
2. Preserve the OCaml current-state record's completed Phase 1 history and
   update it only if the live observation requires a new dated boundary.
3. Under an explicit cross-repository documentation handoff, update caml9's
   tracked record so it no longer describes `.40` as unbooted, caml9-owned, or
   independently available.
4. Record that the OCaml task is the sole operational owner of the halted
   `.40` compiler lab and that caml9's `.32` state remains separate.
5. Name the exact next stateful gate and exclusions identically at handoff.

This reconciliation must not inspect or mutate the caml9 VM lane. It changes
records only, after live state is revalidated by the sole operator. The
present P2-004 gate neither authorizes nor performs it.

## Corrected state machine

Each launch has one unique process ID and moves monotonically:

```text
Prepared, no child
  |
  | rfork fails
  +--> No_child_error
  |
  | rfork returns positive PID; native registry publication
  v
Native_pending
  |
  | ML handle plus active PID map created; native adoption acknowledged
  v
Active
  |-- Exec_confirmed
  |-- Exec_failed_pending_reap
  `-- Handshake_indeterminate
          |
          | shared coordinator consumes matching wait record
          v
      Completed(wait_msg)

Active -- exact No_children with unresolved handle --> Wait_queue_lost
Active -- internal invariant failure -------------> Protocol_failed
```

Only the coordinator moves an active handle to a wait-terminal state. The
active PID entry is removed during the same transition. A completed, lost, or
protocol-failed handle keeps its own memoized result independently of PID
reuse.

The same handle cannot be resolved twice because every terminal transition
atomically removes the sole active mapping and checks the unique process ID.

## CPU-017 compatibility matrix

| CPU-017 need | Corrected Phase 2 facility | Environment visibility |
| --- | --- | --- |
| Publish `NPROC` | `Plan9.Env.set` before the split | original and later copied group |
| Finalize `sysname` and prompt | existing native/environment facilities before the split | original and later copied group |
| Isolate service setup | `Plan9.Raw.copy_environment ()` | creates the child-delivery boundary |
| Publish derived `auth` and `serviced` | `Plan9.Env.set` after the split | copied service group only |
| Start selected service scripts | `Plan9.Process.spawn` with inherited stdout | copied service group |
| Start CPU listener branch | `Plan9.Process.spawn` with truncate-file stdout | copied service group |
| Preserve continuation | retain handles without forced immediate waits | boot continues in copied group |
| Avoid zombies | coordinator owns exec-failure and normal reaping | process-wide invariant |
| Avoid stolen completions | no other wait/child facility while handles are unresolved | process-wide invariant |
| Observe later failure | `Process.wait` returns exact `Waitmsg.message` and timings | no environment translation |

This matrix does not settle service-directory precedence, configured versus
ndb authentication, rc pattern behavior, auth-server choice, `keyfs`, machine
defaults, daemonization, or complete boot acceptance. Those are later caml9
questions.

## Evidence classification

### Source-contract evidence

Authoritative source and headers settle:

- the available rfork flags and structurally forbidden combinations;
- the process-wide wait-any nature of await;
- native `Waitmsg` field meanings;
- `OCEXEC`, `#d`, and `#|` intent;
- `_exits` behavior needed by the child path; and
- runtime and compiler primitive registration.

### Harmless guest evidence

The ABI probe may settle:

- installed declarations and link availability from the APE-linked runtime;
- actual field widths, timing units, formatting, and native errors;
- close-on-exec and descriptor-collision behavior;
- bounded frame feasibility and short I/O behavior;
- bounded interruption observations;
- current-process `RFENVG` copy behavior; and
- short-lived child ordering.

### Implementation proof

Source review and focused candidate tests must settle:

- native registry publication before any interruptible post-rfork action;
- recovery through `Process.unresolved`;
- no OCaml child return, allocation, callback, finalizer, or channel use;
- no `RFMEM` or integer-mask escape;
- no await inside the spawn primitive;
- no public Raw waiter;
- handle-local terminal state and PID-reuse-safe routing;
- foreign-completion bounds without silent loss;
- frame parsing and every cleanup path;
- no-C-tool ordinary consumer linking; and
- observable resolution or loss for every owned handle.

### Later stateful service and caml9 evidence

Only separately authorized later gates may test:

- service-directory precedence;
- configured, ndb-derived, and absent auth cases;
- auth-server and `keyfs` behavior;
- `aux/listen`, ports, namespace, and descendants;
- long-lived service cleanup;
- CPU and non-CPU branches;
- the environment split in the integrated boot program; and
- developmental or promotion-lane boot acceptance.

## Implementation decisions versus probe facts

The following are implementation decisions and must not be delegated to the
guest probe:

- the native pending-child registry;
- unique process IDs and adoption acknowledgment;
- the handle state machine;
- exclusive coordinator ownership;
- active PID map lifetime;
- handle-local terminal memoization;
- foreign-completion queue bounds and fail-closed behavior;
- the public ownership-bearing result types;
- no private await in spawn;
- the exact frame schema within measured native size bounds;
- C-owned input copying and cleanup;
- the absence of public `Raw.wait_any` and `RFNOMNT`; and
- the high-level argv0 synthesis policy.

The probe measures only facts the implementation must accommodate.

## Direct response to the P2-003 checklist

1. **Accepted.** CPU-017 uses one current-process `RFENVG` split through
   `Plan9.Raw.copy_environment ()` before writing derived `auth` and
   `serviced`.
2. **Accepted.** The Plan9.Process coordinator exclusively consumes native
   await while any managed or native-pending child is unresolved.
3. **Accepted.** Public `Raw.wait_any` is removed.
4. **Accepted.** A unique process ID identifies the handle; PID maps only to
   an active unresolved handle; unknown completions are classified
   immediately; terminal state remains on the handle; no unknown record is
   later attached after PID reuse.
5. **Refined.** Exact native `No_children` with unresolved handles produces
   terminal `Wait_queue_lost`. Before such evidence, external theft is
   indistinguishable from a live child and cannot be promised finite-time
   detection; mixing is therefore prohibited and bounded tests drive to
   completion or `No_children`.
6. **Accepted.** Durable ownership begins when the parent publishes its
   preallocated record in the native pending-child registry immediately after
   successful rfork, before handshake I/O or any interruptible transition.
7. **Accepted.** No spawn error path may lose a live or waitable child. Every
   post-rfork non-success is handle-bearing until the shared coordinator
   confirms reaping.
8. **Accepted.** The shared Process coordinator, never the spawn primitive,
   reaps a child that reports exec failure.
9. **Accepted.** Interruption and malformed frames produce distinct
   handle-bearing `Handshake_interrupted` and
   `Handshake_protocol_error` results.
10. **Accepted.** The field is `message`, and the complete native text is
    preserved. The third timing field is refined to `elapsed_time_ms`.
11. **Accepted.** `RFNOMNT` is deferred from Phase 2.
12. **Accepted.** Raw.exec takes the exact nonempty argv; Process.spawn
    synthesizes argv0 as `program` and accepts an empty high-level args array.
13. **Accepted.** Harmless ABI and stateful service behavior use separate
    named gates and evidence boundaries.
14. **Answered.** Registry ownership, state transitions, queue policy, result
    types, frame schema, cleanup, and public exclusions are implementation
    decisions. Installed declarations, widths, units, error strings,
    `OCEXEC`, descriptor collisions, interruption observations, and `RFENVG`
    behavior are probe facts.
15. **Answered.** After exploration acceptance, canonical promotion would
    update `01-native-api-requirements.md`,
    `03-verification-and-recovery.md`, and `04-implementation-plan.md`.
    Current-state reconciliation is a separate record-only gate, not canonical
    API promotion.

## Canonical implications after acceptance

A later canonicalization gate would update:

- `01-native-api-requirements.md` for environment splitting, the narrowed Raw
  layer, synthesized high-level argv0, `message`, ownership-bearing launch
  results, exclusive waiting, handle identity, PID reuse, and loss semantics;
- `03-verification-and-recovery.md` for evidence classification, the harmless
  ABI gate, the separate stateful service gate, bounded wait/interruption
  tests, and cross-repository reconciliation before stateful work; and
- `04-implementation-plan.md` for the corrected ordering of reconciliation,
  ABI evidence, runtime implementation, ML coordination, independent native
  qualification, optional service evidence, and caml9 integration.

That gate must remove or supersede canonical text retaining public raw wait,
PID-only completion storage, caller-supplied high-level argv0, `status`,
Phase 2 `RFNOMNT`, globally written derived CPU-017 variables, or service
startup inside an ABI probe.

No canonical file changes in P2-004.

## Requested next action

The caml9 review task should review P2-004 directly under the exclusive
documentation lease. It may create the next numbered review and update only
the corresponding README row. It must not modify P2-002, P2-003, P2-004, any
other path in either repository, canonical design, current-state,
implementation, or any operational resource without separate authorization.
