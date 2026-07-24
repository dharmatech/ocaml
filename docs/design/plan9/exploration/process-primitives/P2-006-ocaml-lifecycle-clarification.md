# P2-006: OCaml process-lifecycle clarification

Status: proposed

Origin: OCaml Plan 9 port task

Materialized by: OCaml Plan 9 port task

Responds to: [P2-005](P2-005-caml9-corrected-design-review.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, published HEAD
`351d53555cbb1268271665840e4b778734c6aa17`, tree
`5b608847e1f549ed441c76352a8b7abc11cff60e`, and synchronized origin,
with an unchanged index, a modified exchange README, and untracked P2-002
through P2-005 at the accepted documentation handoff

Canonical impact: none yet; this document clarifies only the two lifecycle
issues raised by P2-005 and awaits caml9 confirmation before P2-004 and P2-006
are eligible for a separately authorized canonicalization gate

Requested next action: caml9 review of P2-006 under the exclusive
documentation lease, with no canonical, implementation, publication, or
operational action

## Purpose and bounded disposition

P2-006 accepts both P2-005 clarifications:

1. coordinator ownership does not imply automatic or background reaping; and
2. a full foreign-completion FIFO is retryable backpressure, not a terminal
   protocol failure for a managed child.

This document refines only the process-lifecycle and public-result portions of
[P2-004](P2-004-ocaml-corrected-process-design.md). It replaces P2-004's
ambiguous CPU-017 continuation and zombie rows, its treatment of a full
foreign FIFO as a protocol error, and its underspecified
`Active -> Protocol_failed` transition.

All other P2-004 decisions remain accepted and closed in this response. In
particular, P2-006 does not reopen:

- the one-time current-process environment-group copy;
- the combined, child-nonreturning native rfork/exec primitive;
- permanent `RFMEM` rejection;
- the native pending-child registry;
- exact raw argv and synthesized high-level argv0;
- `message` and the three native timing fields;
- deferral of `RFNOMNT`;
- the split between harmless ABI and stateful service evidence; or
- cross-repository state reconciliation before stateful work.

This is still an exploration document. Canonical design, implementation
source, current-state, and operational state remain unchanged.

## Synchronous coordinator progress

### Disposition: accepted

The Plan9.Process coordinator is a process-wide ownership and dispatch
facility, not an independently executing reaper.

The initial bytecode port has no systhreads-based helper, background event
loop, note-driven reaper, or nonblocking native await operation. The
coordinator calls native await only when one of these synchronous paths
invokes it:

- known exec-failure cleanup performed on behalf of `Process.spawn`;
- `Process.wait`;
- `Process.wait_any`; or
- the high-level `Process.run` defined below.

`Process.unresolved` may adopt native pending-child records, but adoption by
itself does not call await. An ordinary successful `Process.spawn` returns its
handle without starting any hidden activity.

Consequently:

- retaining a long-lived handle retains the obligation to drive its eventual
  wait;
- discarding a handle neither applies `RFNOWAIT` nor guarantees cleanup;
- a child that exits while no coordinator operation runs may remain in the
  process-wide native wait queue; and
- the initial API promises no background progress.

The exclusive-wait interval from P2-004 is unchanged. It begins with the first
successful managed rfork and ends only when no adopted managed owner and no
native pending-child owner remains unresolved. Coordinator ownership prevents
competing waiters during that interval; it does not cause time to advance or
invoke await on its own.

## Handle-preserving wait results

### Disposition: accepted and made explicit

P2-004's single `Wait_protocol_error` category is too broad. The corrected
contract distinguishes a terminal child state from a coordinator operation
that cannot presently resolve the child.

The exact constructor names remain reviewable, but the required shape is:

```ocaml
type wait_unresolved =
  | Await_interrupted of error
  | Await_error of error
  | Foreign_backpressure of {
      queued : int;
      capacity : int;
    }
  | Coordinator_invariant_failure of error
  | Malformed_native_record of error

type wait_terminal_failure =
  | Wait_queue_lost of error

type wait_result =
  | Wait_finished of wait_msg
  | Wait_unresolved of {
      process : t;
      reason : wait_unresolved;
    }
  | Wait_terminal_failure of {
      process : t;
      reason : wait_terminal_failure;
    }

val wait : t -> wait_result
```

Every nonterminal result from `Process.wait` carries the exact owned handle.
The handle remains active unless and until a matching native completion or an
exact terminal observation changes its state. A caller is never required to
reconstruct ownership from a PID or error string.

The categories have deliberately different meanings:

| Observation | Handle state | Further coordinator action |
| --- | --- | --- |
| native await interruption | active and owned | caller may retry explicitly |
| ordinary native await error other than exact `No_children` | active and owned | no automatic retry; caller retains the handle |
| full foreign FIFO | active and owned | drain queued foreign records, then retry |
| exact native `No_children` | terminal `Wait_queue_lost` | memoized; do not await for that owner again |
| internal ownership invariant failure | owned but unresolved | coordinator fails closed; no further native await |
| malformed or unrepresentable native record | owned but unresolved | coordinator fails closed; no arbitrary completion assignment |

Interruption is not automatically retried. Backpressure is retryable only
after capacity is made available. An invariant or malformed-record failure is
not retryable inside the failed coordinator, but it also does not falsely
claim that the child completed or disappeared. The owned handle in that result
preserves the unresolved lifecycle fact.

On an invariant failure, already terminal handles remain terminal. Every
nonterminal adopted or native-pending owner remains registered, the
coordinator enters a distinct failed-closed state, and no later operation
calls native await or permits another child/wait facility to take over.

If a consumed native record cannot be represented without losing the identity
or native information needed for safe dispatch, the coordinator records a
distinct global malformed-record diagnosis. It does not attach that record to
an arbitrary handle. All ownership that can still be represented remains
registered, and the exclusive-wait interval remains open. This is different
from exact `No_children`, which proves that no native child remains.

## Safe high-level `Process.run`

### Disposition: accepted and restored

The high-level library includes a synchronous `Process.run` using the same
program, synthesized-argv0 arguments, and focused stdout policy as
`Process.spawn`.

Its required ownership-bearing result shape is:

```ocaml
type run_incomplete =
  | Run_launch_incomplete of launch_incomplete
  | Run_wait_unresolved of wait_unresolved

type run_terminal_failure =
  | Run_wait_queue_lost of error

type run =
  | Finished of wait_msg
  | Run_incomplete of {
      process : t;
      reason : run_incomplete;
    }
  | Run_terminal_failure of {
      process : t;
      reason : run_terminal_failure;
    }

val run :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  (run, error) result
```

The exact type names may be refined during canonicalization, but these
invariants are fixed:

- outer `Error` means that no child created by this call remains;
- `Finished` carries the exact native wait message and timings;
- every nonterminal launch or wait outcome carries the owned handle;
- a terminal loss result may retain the handle for identity and diagnosis even
  though exact `No_children` proves the native child no longer exists; and
- `run` never introduces a second private wait path.

Normally `run` invokes `spawn`, adopts the resulting handle, and drives the
shared coordinator until the direct child is terminal. It returns early only
when a specifically reported nonterminal condition prevents that progress.

Before a child exists, validation, setup, process-ID reservation, or rfork
failure may produce outer `Error`. After rfork, outer `Error` is permitted only
when the coordinator has confirmed that a known exec-failure child was reaped.
An interrupted or indeterminate launch, a wait interruption, foreign
backpressure, an ordinary nonterminal wait error, an invariant failure, or a
malformed native record returns `Run_incomplete` with the handle.

If `run` returns `Run_incomplete`, its caller owns the same handle accepted by
the coordinator. The caller may drain foreign completions and retry
`Process.wait`, explicitly retry after an interruption where appropriate, or
fail closed while preserving an invariant or malformed-record diagnosis.

## Foreign FIFO backpressure

### Disposition: accepted and corrected

The bounded foreign-completion FIFO remains necessary because a
particular-handle wait may consume an unknown child's native completion before
reaching its target. No completion may be dropped, overwritten, or later
reattached by PID.

FIFO capacity is enforced as follows:

1. A particular-handle wait first returns any memoized result for that target.
2. If the target is active and the foreign FIFO is already full, it returns
   `Foreign_backpressure` without invoking native await.
3. If native await yields an unknown completion while capacity remains, the
   coordinator stores that record at the FIFO tail.
4. If storing it fills the last slot and the target is still active, the wait
   returns `Foreign_backpressure` before another native await.
5. The target remains active throughout; fullness never changes it to
   `Protocol_failed`, `Wait_queue_lost`, or any other terminal state.

`Process.wait_any` returns the oldest already queued foreign completion before
it invokes native await. `Process.take_foreign_completions` drains retained
foreign records in FIFO order. Either operation makes capacity available.
After drainage, the caller retries `Process.wait` on the same active handle.

Backpressure therefore reports a recoverable coordinator-capacity condition,
not a lifecycle conclusion about the target child.

A nonterminal `Process.wait_any` result likewise carries the complete current
set of adopted owned handles. Before native await, `wait_any` adopts any
recoverable native pending-child records so it cannot hide ownership behind a
handle-free interruption or coordinator failure.

## Exact `No_children` and native-pending owners

### Disposition: accepted and clarified

Exact native `No_children` is the distinguishing terminal observation. When
the coordinator receives it while any managed or native-pending owner remains,
it atomically:

1. marks every adopted unresolved handle `Wait_queue_lost`;
2. marks every unadopted native pending-child record with the same memoized
   terminal loss;
3. removes active PID mappings that can no longer lead to a completion; and
4. stops awaiting on behalf of those terminal owners.

A later `Process.unresolved` call adopts a terminal native record with its
original process ID and memoized loss. It must not manufacture a fresh active
handle after the kernel has proved that no children remain.

This treatment is intentionally different from coordinator invariant or
malformed-record failure. Those failures do not prove child absence and
therefore leave ownership unresolved and the exclusivity interval open.

## Identity-preserving pending-child adoption

### Disposition: accepted and clarified

The process ID is reserved, and all native pending-record storage is
preallocated, before rfork. Exhaustion, wraparound, collision in the
never-reused process-ID space, or inability to reserve the record fails before
rfork and therefore creates no child.

After a positive parent-side rfork result, the preallocated record is
published allocation-free under that reserved process ID. Adoption is
idempotent:

- exactly one logical `Process.t` corresponds to that process ID;
- repeated `Process.unresolved` inspection returns the same logical handle and
  memoized state;
- adoption never assigns a new process ID;
- acknowledgment removes the native pending entry only after the handle and
  active PID mapping are established; and
- an already terminal native-pending record is adopted as that same terminal
  handle.

An active native PID collision detected after rfork is an invariant failure,
not permission to overwrite the earlier PID mapping. Both ownership records
remain preserved by process ID and the coordinator fails closed.

## CPU-017 direct-launcher lifecycle

### Disposition: accepted, subject to later service evidence

CPU-017 should use `Process.run` for each direct `auth/keyfs` or `aux/listen`
launcher. Spawn followed by `Process.wait` through the same coordinator is
equivalent, but `run` makes the synchronous ownership boundary explicit.

The sequence is:

1. launch one direct child;
2. drive that exact handle to a terminal result;
3. preserve its complete native wait data;
4. record or ignore a nonempty `Waitmsg.message` according to stock's
   continue-after-native-failure policy; and
5. proceed to the next CPU-017 command only after no direct-launcher handle is
   unresolved.

The service or listener process that a launcher may deliberately leave behind
is a different lifecycle. Whether `keyfs` or `aux/listen` daemonizes, which
descendants remain, and how they are cleaned up require the later stateful
service-evidence gate. That uncertainty does not justify leaving the direct
Plan9.Process child unresolved.

If `run` returns backpressure, CPU-017 drains the foreign FIFO and retries the
same handle before continuing. If it returns an interruption, CPU-017 retains
the handle and applies an explicit retry or stop policy. An invariant or
malformed-record failure is fail-closed. Exact wait-queue loss proves that no
direct child remains but does not synthesize the missing native completion;
the integration must report that distinct failure rather than treat it as an
ordinary nonempty native message.

The corrected lifecycle matrix is:

| CPU-017 need | Corrected Phase 2 facility | Lifecycle |
| --- | --- | --- |
| Invoke `auth/keyfs` or `aux/listen` launcher | native `Plan9.Process.run`, or spawn plus wait through the same coordinator | direct launcher resolved before the next boot command |
| Continue after native non-success | caller records or ignores terminal `Waitmsg.message` according to stock policy | no unresolved launcher is hidden |
| Resolve retryable coordinator pressure | drain foreign FIFO and retry the same handle | ownership and identity are unchanged |
| Support a deliberately direct long-lived child later | `Process.spawn` plus retained handle and explicit later wait | no automatic reaper is implied |
| Use remaining `Sys.command` steps during migration | enter them only after no managed or native-pending owner remains unresolved | exclusive-wait interval is closed |

Later `Sys.command` use is therefore permitted only after the managed
exclusivity interval closes. CPU-017 must not return to CPU-018 or another APE
child/wait facility with an unresolved direct launcher. This preserves the
current synchronous integration boundary while allowing later service
evidence to refine descendant behavior.

## Corrected lifecycle state model

P2-004's ownership states remain, with coordinator failure separated from
child terminal state:

```text
Prepared, no child
  |
  | process-ID reservation or rfork fails
  +--> No_child_error
  |
  | rfork returns positive PID; native registry publication
  v
Native_pending
  |
  | identity-preserving ML adoption
  v
Active
  |-- matching native record ----------> Completed(wait_msg)
  |-- exact native No_children --------> Wait_queue_lost
  |-- interruption --------------------> Active, caller may retry
  `-- foreign FIFO full ---------------> Active, drain then retry

Coordinator_ready
  |-- ownership invariant failure -----> Coordinator_failed_invariant
  `-- malformed native record ---------> Coordinator_failed_malformed
```

A coordinator-failed state does not falsely terminalize an active or
native-pending owner. It preserves handle-bearing unresolved diagnoses,
performs no further native await, and keeps the exclusive-wait interval open.
Already completed or queue-lost handles retain their memoized terminal state.

## Direct response to the P2-005 checklist

1. **Yes.** The coordinator progresses only when a named synchronous internal
   or public operation invokes it.
2. **Yes.** Ordinary successful spawn starts no background reaper and promises
   no automatic cleanup.
3. **Yes.** `Process.run` is restored as a synchronous, handle-preserving
   high-level operation using the same coordinator.
4. **Yes.** Outer run `Error` guarantees that no child from that call remains.
5. **Yes.** Every nonterminal launch, particular wait, run, or wait-any result
   carries the applicable owned handle or complete owned-handle set.
6. **Yes.** CPU-017 resolves each direct `keyfs` or `aux/listen` launcher
   before proceeding, subject to later service and descendant evidence.
7. **Yes.** Later `Sys.command` use occurs only after no managed or
   native-pending owner remains unresolved.
8. **Yes.** Foreign-FIFO fullness is retryable backpressure and leaves the
   target handle active.
9. **Yes.** Interruption, backpressure, exact observable loss, invariant
   failure, and malformed-record failure have distinct results and state
   effects.
10. **Yes.** Exact `No_children` terminalizes both adopted managed handles and
    unadopted native pending-child records with memoized queue loss.
11. **Yes.** `wait_any` returns queued foreign records before native await;
    FIFO drainage permits the original particular-handle wait to be retried.
12. **Yes.** Pending-child adoption preserves one never-reused process
    identity, and process-ID exhaustion fails before rfork.

No answer above changes the accepted environment, rfork/exec, argv,
`RFNOMNT`, evidence-classification, or reconciliation decisions.

## Requested next action

The caml9 review task should review P2-006 directly under the exclusive
documentation lease. It may create the next numbered review and update only
the corresponding README dispositions. It must not modify P2-002 through
P2-006, canonical design, current-state, implementation source, either
repository outside the declared review files, or any operational resource
without separate authorization.
