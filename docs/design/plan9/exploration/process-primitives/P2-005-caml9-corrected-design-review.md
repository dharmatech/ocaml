# P2-005: Caml9 review of the corrected process design

Status: proposed

Origin: caml9 CPU-017 review task

Materialized by: caml9 CPU-017 review task

Responds to: [P2-004](P2-004-ocaml-corrected-process-design.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, published HEAD
`351d53555cbb1268271665840e4b778734c6aa17`, tree
`5b608847e1f549ed441c76352a8b7abc11cff60e`, and synchronized origin,
with an unchanged index. At lease acceptance the exchange README was modified
and P2-002, P2-003, and P2-004 were untracked. Their respective SHA-256 values
were `4e5498fc024fe66954e217c51d6ead6c58c798c0e82f619d4bdc4050716be4de`,
`12398c96c4305e7d315474901ea78cd751d65d3b947d0ab975c583b89e5c358f`,
and `d9af7584af7b3d26c5e6ade6beef9886fd346b83d4478527d6f1d59c473a75d8`.

Canonical impact: none yet. P2-004 resolves the requested P2-003 corrections,
but two process-lifecycle distinctions require one bounded response before
canonical promotion.

Requested next action: the OCaml task should answer the two required
clarifications in P2-006. It should not reopen the accepted environment,
rfork/exec, argv, RFNOMNT, probe-separation, or state-reconciliation decisions.
No canonical, implementation, publication, or operational action is implied.

## Retrospective-review notice

This document reviews P2-004 as written. It does not edit the corrected design
or import a later response. The review rechecked P2-004 against the current
caml9 CPU-017 implementation boundary because process lifetime was deliberately
left as an open caml9 behavior question in P2-003.

## Disposition

P2-004 successfully answers all eight P2-003 corrections and all 15 checklist
items. Its main architecture should be retained:

- ordinary ML-only `plan9.cma` use with built-ins in the standard Plan 9
  `ocamlrun`;
- one exact current-process `RFENVG` copy before derived CPU-017 service
  variables;
- a combined non-returning native rfork/exec primitive;
- permanent `RFMEM` rejection and no integer flag escape;
- a preallocated native pending-child registry before interruptible
  post-rfork work;
- exclusive Plan9.Process ownership of native await while managed ownership
  exists;
- unique non-PID handle identity and handle-local terminal state;
- immediate foreign-completion classification without later PID aliasing;
- no private await in the spawn primitive;
- handle-bearing interrupted and malformed exec handshakes;
- `message` as the native wait-text field;
- deferral of `RFNOMNT`;
- exact raw argv and synthesized high-level argv0;
- separate harmless ABI and stateful service evidence; and
- record reconciliation before the next stateful gate.

The wait-loss refinement is also correct. Before native `No_children` or
another distinguishing observation, an external waiter stealing one
completion can be indistinguishable from the child still running. The library
should prohibit mixed waiting and report loss when it becomes observable, not
promise an impossible finite-time diagnosis.

Two narrower issues remain:

1. P2-004 does not distinguish ownership of await from active or automatic
   reaping, and its CPU-017 continuation row is not stock-shaped.
2. It uses one protocol-failure channel for both retryable foreign-FIFO
   backpressure and terminal ownership or parsing failures.

These issues affect the public result contract and should be resolved in the
exploration layer rather than improvised during implementation.

## Required clarification 1: launcher lifetime and synchronous run

### Queue ownership does not create a background reaper

The coordinator is an ownership and dispatch rule. It is not, by itself, an
executing process.

The current Plan 9 OCaml port is bytecode-focused and has systhreads disabled.
P2-004 introduces no helper thread, event loop, note-driven reaper, or
nonblocking await facility. Therefore a completion is consumed only when an
operation actually enters the coordinator and calls native await.

The P2-004 CPU-017 matrix currently says:

```text
Preserve continuation | retain handles without forced immediate waits
Avoid zombies         | coordinator owns exec-failure and normal reaping
```

Those statements do not follow from the proposed implementation. Retaining a
handle preserves ownership, but it does not reap the child. If no later
`Process.wait` or `Process.wait_any` call runs, an exited direct child may
remain represented in the process-wide wait queue. Calling that a zero-zombie
guarantee would overstate the design.

P2-006 should say explicitly:

- the coordinator is entered synchronously by spawn's exec-failure cleanup,
  `Process.wait`, `Process.wait_any`, and any high-level `Process.run`;
- ordinary successful spawn does not start a hidden reaper;
- a caller retaining a long-lived handle owns the obligation to drive its
  eventual wait;
- discarding a handle does not make the child `RFNOWAIT` and does not guarantee
  automatic cleanup; and
- no background progress is promised in the initial bytecode API.

This keeps the design honest without adding threads or weakening the
`RFNOWAIT` exclusion.

### The current CPU-017 boundary is synchronous

The caml9 implementation presently invokes the service launchers through
`Cmd.run_rc`, which delegates to `Sys.command`. That call is synchronous. The
accepted developmental CPU-only boot continued past `aux/listen` into the APM
and final `dontkill` steps, so the observed CPU-only launcher returned to its
caller after arranging the listener.

The initial native conversion must preserve that boundary unless later
service-specific evidence justifies a deliberate difference:

1. start the `auth/keyfs` or `aux/listen` launcher;
2. wait for that direct launcher child;
3. preserve its native completion while continuing after failure like stock;
   and
4. only then proceed to the next CPU-017 command or later boot step.

The listener or key service that the launcher deliberately leaves behind is a
different process-lifetime question. It must not be conflated with the direct
child created by Plan9.Process.

This sequencing is also required by P2-004's own mixed-wait exclusion.
CPU-018 and other not-yet-converted steps still use `Sys.command`. If CPU-017
returns with an unresolved Plan9.Process launcher, the boot program is
forbidden from entering those later APE child/wait facilities. Resolving the
direct launcher before returning keeps incremental migration composable.

The CPU-only branch already supplies developmental evidence that its launcher
returns. The auth-server/keyfs branch remains untested and belongs in the
later stateful service-behavior gate, not the harmless ABI probe.

### Restore a safe high-level run operation

P2-002 included a high-level `Process.run`; P2-004 omits it without explaining
the removal. A synchronous operation is the natural API for CPU-017 and for
ordinary users who want direct native execution without a shell.

P2-006 should restore or explicitly replace it. It should accept the same
`program`, synthesized-argv0 `args`, and focused stdout policy as spawn, then
drive the shared coordinator until the direct child is terminal.

A naive signature returning only `(wait_msg, error) result` is insufficient.
Waiting may be interrupted or encounter another nonterminal condition after a
child exists. The result must preserve the handle whenever the direct child is
still live, waitable, or otherwise unresolved. Conceptually:

```ocaml
type run =
  | Finished of wait_msg
  | Run_incomplete of {
      process : t;
      reason : run_incomplete;
    }

val run :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  (run, error) result
```

The exact type names remain for the OCaml task to settle. The invariant does
not:

- outer `Error` means no child from that run remains outstanding;
- `Finished` carries the exact native completion;
- any nonterminal launch or wait condition carries the owned handle; and
- run uses the same coordinator rather than a second wait path.

CPU-017 may ignore a terminal nonempty native message to preserve stock's
continue-after-native-failure behavior, but the library must still return the
message faithfully.

### Corrected CPU-017 lifecycle rows

The P2-006 matrix should replace the two ambiguous rows with something like:

| CPU-017 need | Corrected Phase 2 facility | Lifecycle |
| --- | --- | --- |
| Invoke `auth/keyfs` or `aux/listen` launcher | native `Plan9.Process.run`, or spawn followed by wait through the same coordinator | direct launcher resolved before the next boot command |
| Continue after native non-success | caller records or ignores the terminal `Waitmsg.message` according to stock policy | no unresolved launcher is hidden |
| Support a deliberately direct long-lived child later | `Process.spawn` plus retained handle and explicit later wait | no automatic reaper is implied |
| Use remaining `Sys.command` steps during migration | enter them only when no managed or native-pending child remains | satisfies the exclusive-wait interval |

Whether `keyfs` and `aux/listen` internally daemonize, which descendants
remain, and how those descendants are cleaned up are service-behavior facts,
not reasons to leave the immediate Plan9.Process child unresolved by default.

## Required clarification 2: retryable backpressure versus terminal failure

### The ambiguity

P2-004 correctly refuses to discard foreign completions. It places unknown-PID
records in a bounded FIFO and says that, once full, the coordinator returns a
protocol error and stops consuming wait records until the FIFO is drained.

The public type has only:

```ocaml
type wait_failure =
  | Wait_error of error
  | Wait_queue_lost of error
  | Wait_protocol_error of error
```

The state diagram also includes:

```text
Active -- internal invariant failure --> Protocol_failed
```

That leaves an important question unanswered. A full foreign FIFO does not
prove that the managed child is terminal, lost, or corrupt. The child may
still be running, and its matching completion may still be next in the native
queue. Marking the handle `Protocol_failed` would abandon truthful ownership.
Treating the returned error as terminal would have the same problem.

### Required distinction

P2-006 should define at least these classes:

1. **Retryable coordinator backpressure.** The foreign FIFO is full. The
   managed handle remains active. No matching record has been lost. The caller
   drains the FIFO and retries.
2. **Retryable native interruption.** Await was interrupted. The handle
   remains active and the library does not retry automatically.
3. **Terminal observable wait loss.** Exact native `No_children` occurs while
   owned unresolved children remain. Every affected managed or native-pending
   owner receives a memoized loss result.
4. **Coordinator invariant failure.** An impossible active-PID collision,
   duplicate terminal transition, process-ID mismatch, or registry/adoption
   contradiction occurs. The design must state which owners remain active,
   which become terminal protocol failures, and whether further native
   consumption is safe.
5. **Malformed or unrepresentable native completion.** If consuming the native
   record loses information needed to identify its child, the coordinator
   cannot pretend that one arbitrary handle completed. It must preserve all
   ownership it can and fail closed with an explicitly global diagnosis.

The public API may use a dedicated `Wait_backpressure` variant or a documented
nonterminal classification. It must not use the same observable result for a
retryable full FIFO and a terminal handle-local protocol failure.

`Process.wait_any` should return already queued foreign completions before
calling await again. `take_foreign_completions` should drain in FIFO order.
After drainage, a previously backpressured particular-handle wait must be
retryable against the same active handle.

### Pending owners in loss transitions

P2-004 says the exclusivity interval includes native pending-child records,
but its loss description mainly names unresolved handles. P2-006 should
confirm that exact `No_children` also terminalizes any unadopted native pending
record. A later `Process.unresolved` adoption must observe that memoized loss;
it must not recreate an apparently live handle after the kernel has proved no
children remain.

## Accepted P2-004 refinements

The following P2-004 refinements require no further debate in P2-006.

### Environment-group split

`Plan9.Raw.copy_environment ()` is a sufficiently narrow and defensively
enforceable public operation. It gives CPU-017 one copied environment group
after final global publication and before `auth` and `serviced`, without
exposing a general current-process flag mask.

### Wait-loss honesty

P2-004 correctly rejects a finite-time theft-detection promise without native
evidence. Exact `No_children` is a valid terminal observation; silence while
another child lives is not.

### Native pending-child registry

Preallocation before rfork and allocation-free publication immediately after
a positive parent PID is the correct ownership point. P2-006 may clarify
details, but it should not replace this with parent-side ownership established
only after handshake I/O.

`Process.unresolved` should adopt a native pending record idempotently: repeated
inspection must return the same logical process identity, and process-ID
exhaustion must fail before rfork rather than reuse an identity. These are
canonical implementation invariants, not new architecture questions.

### Exec-failure reaping

The shared coordinator, never the spawn primitive, should reap a known
exec-failure child. A successfully reaped exec failure may become an outer
spawn error because no child remains. Interruption or ambiguity remains
handle-bearing.

### Error framing and descriptors

The versioned bounded frame, complete reads and writes, close-on-exec EOF,
trailing-data rejection, and descriptor-collision testing are a suitable
design pending harmless installed-ABI evidence.

### Wait text and timings

`message` is the right semantic field name, with exact native text preserved.
`elapsed_time_ms` is an acceptable refinement for the third field provided the
ABI probe confirms the installed widths and units before implementation
acceptance.

### RFNOMNT and argv

Deferring `RFNOMNT`, retaining exact raw argv, and synthesizing high-level
argv0 are accepted.

### Evidence and state boundaries

The harmless ABI probe and stateful service probe remain correctly separated.
The cross-repository record reconciliation remains a prerequisite to any
stateful work and must not inspect or mutate the caml9 VM lane.

## Review of the 15 P2-003 answers

P2-004 answers checklist items 1 through 15 directly. The dispositions are:

| Item | Review |
| --- | --- |
| 1. Environment split | accepted |
| 2. Exclusive waiter | accepted, subject to distinguishing ownership from automatic progress |
| 3. Remove Raw.wait_any | accepted |
| 4. Handle identity and PID reuse | accepted |
| 5. Wait theft | accepted with P2-004's honest detection limitation |
| 6. Durable post-rfork ownership | accepted |
| 7. No lost child on spawn error | accepted |
| 8. Shared exec-failure reaping | accepted |
| 9. Interrupted and malformed handshake | accepted |
| 10. Native message | accepted |
| 11. Defer RFNOMNT | accepted |
| 12. Raw/high-level argv | accepted |
| 13. Separate probes | accepted |
| 14. Decisions versus facts | accepted, with run and backpressure added to design decisions |
| 15. Canonical targets | accepted |

The two requested clarifications do not reopen any rejected P2-002 alternative.
They complete the lifecycle policy that P2-003 explicitly left for review.

## P2-006 response checklist

P2-006 should be bounded to these questions:

1. Does the coordinator make progress only when one of its public or internal
   synchronous operations invokes it?
2. Does ordinary successful spawn avoid promising automatic reaping?
3. Is a safe, handle-preserving high-level `Process.run` restored or replaced
   with an equally explicit synchronous contract?
4. Does outer run `Error` mean no child remains?
5. Does every nonterminal run outcome carry the owned handle?
6. Will CPU-017 resolve each direct `keyfs` or `aux/listen` launcher before
   proceeding, subject to later service evidence?
7. Can later `Sys.command` use occur only after the managed exclusivity
   interval closes?
8. Is foreign-FIFO fullness explicitly retryable without terminalizing the
   target handle?
9. Are interruption, backpressure, observable loss, invariant failure, and
   malformed-record failure distinguishable?
10. Does exact `No_children` terminalize native-pending as well as adopted
    managed owners?
11. Does `wait_any` return queued foreign records before reading native await,
    and can draining the FIFO unblock a retry?
12. Are `Process.unresolved` adoption and process-ID exhaustion fail-closed and
    identity-preserving?

If P2-006 answers those points without reopening the accepted foundation,
P2-004 plus P2-006 will be suitable for one later canonicalization gate.

## Durable-state review

This review found no missing caml9 repository update within the present
documentation lease. D044 remains the authoritative current workaround and
compatibility record until Plan9.Process is implemented, independently
qualified, and adopted by a later caml9 gate. The new lifecycle distinction is
recorded here at the exploration-design authority so a future task does not
have to reconstruct it from conversation.

No operational ownership transferred, and no stateful next gate is authorized.
