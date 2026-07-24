# P2-007: Caml9 lifecycle acceptance

Status: closed

Origin: caml9 CPU-017 review task

Materialized by: caml9 CPU-017 review task

Responds to: [P2-006](P2-006-ocaml-lifecycle-clarification.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, published HEAD
`351d53555cbb1268271665840e4b778734c6aa17`, tree
`5b608847e1f549ed441c76352a8b7abc11cff60e`, and synchronized origin,
with an unchanged index. At lease acceptance the exchange README was modified
and P2-002 through P2-006 were untracked. P2-004, P2-005, and P2-006 had
respective SHA-256 values
`d9af7584af7b3d26c5e6ade6beef9886fd346b83d4478527d6f1d59c473a75d8`,
`4a312a6662ff6f38f6b86686844c6ea43a12eb73139b245d801d6d0a81f821d8`,
and `134ac803fbe0e15fada1c3c8cdb4349c7c6e85ea7d553a158e4aec9474df1006`.

Canonical impact: P2-004 as clarified by P2-006 is accepted for a later,
separately authorized canonicalization gate. No canonical file changes occur
in this review.

Requested next action: return the documentation lease to the OCaml task. The
next design action may be a separately authorized documentation-only
canonicalization of the accepted package into the native API requirements,
verification and recovery plan, and implementation plan. Publication,
current-state reconciliation, implementation, and operations remain separate
authorizations.

## Disposition

P2-006 is accepted without another corrective response. It resolves both
P2-005 lifecycle findings while preserving every accepted P2-004 decision.

The selected exploration design is therefore:

- [P2-004](P2-004-ocaml-corrected-process-design.md), for the corrected native
  process architecture; plus
- [P2-006](P2-006-ocaml-lifecycle-clarification.md), for synchronous progress,
  handle-preserving run, and nonterminal coordinator states.

Where P2-006 refines P2-004, P2-006 controls. P2-002 remains the historical
initial proposal, while P2-003 and P2-005 preserve the reviews that produced
the selected design.

No P2-008 response is requested. Further substantive disagreement discovered
during canonicalization or implementation should receive a new numbered
design document rather than rewriting this closed exchange.

## Review result

### Synchronous progress is now explicit

P2-006 correctly distinguishes exclusive ownership of native await from
automatic execution. The coordinator runs only when spawn's known-exec-failure
cleanup, `Process.wait`, `Process.wait_any`, or `Process.run` invokes it.

The design now states the consequences precisely:

- successful spawn starts no hidden reaper;
- retaining a handle retains the obligation to drive its eventual wait;
- discarding a handle does not imply `RFNOWAIT`;
- a native completion may remain queued while no coordinator operation runs;
  and
- the initial bytecode API promises no background progress.

This is compatible with the current bytecode-only, no-systhreads port and does
not invent an event mechanism merely to make the API appear asynchronous.

### Process.run preserves ownership

The restored high-level `Process.run` is safe because it uses the same
coordinator and preserves the central post-rfork invariant:

- outer `Error` means no child from that call remains;
- `Finished` carries the exact native completion;
- every nonterminal launch or wait outcome carries the same owned handle; and
- exact wait-queue loss may remain handle-bearing for identity and diagnosis
  even though native `No_children` proves the child is gone.

The exact OCaml constructor names may be finalized during canonicalization,
but a later API must not weaken those ownership distinctions.

### CPU-017 regains its synchronous launcher boundary

The accepted CPU-017 mapping now waits for each direct `auth/keyfs` or
`aux/listen` launcher before proceeding. This matches the current
`Cmd.run_rc`/`Sys.command` boundary and permits later not-yet-converted boot
steps to use `Sys.command` only after the Plan9.Process exclusivity interval
has closed.

The design also keeps the direct launcher distinct from any service descendant
it deliberately leaves behind. Whether `keyfs` or `aux/listen` daemonizes,
which descendants remain, and how those descendants are cleaned up remain
stateful service-evidence questions. They are not harmless ABI questions and
do not justify leaving the immediate managed child unresolved.

### Backpressure is no longer a false terminal state

P2-006 correctly treats a full foreign-completion FIFO as coordinator
backpressure:

- the target handle remains active;
- no matching completion is claimed or discarded;
- no native await is attempted while the FIFO is already full;
- queued foreign records are returned or drained in FIFO order; and
- the same particular-handle wait may be retried after capacity is restored.

This removes the ambiguity between a retryable capacity condition and a
terminal handle-local protocol failure.

### Failure classes preserve the truth available

The selected lifecycle distinguishes:

- native interruption, leaving the owner active and explicitly retryable;
- ordinary native await error, retaining ownership without automatic retry;
- foreign-FIFO backpressure, retaining ownership until drainage;
- exact native `No_children`, terminalizing every adopted and native-pending
  owner as wait-queue loss;
- coordinator invariant failure, preserving unresolved ownership while
  stopping further native consumption; and
- malformed or unrepresentable native completion, preserving all ownership
  that can still be represented without assigning the record arbitrarily.

The last two states may leave the exclusivity interval permanently open. That
is a deliberate fail-closed result, not an accidental promise that another
wait facility may take over.

### Native-pending adoption is complete

P2-006 closes the remaining identity edge cases:

- process-ID reservation and record allocation occur before rfork;
- exhaustion, wraparound, or reservation failure therefore creates no child;
- post-rfork native publication uses the reserved identity without allocation;
- adoption is idempotent and produces one logical handle;
- acknowledgment follows complete ML-handle and active-PID registration; and
- a pending record already terminalized by exact `No_children` is adopted with
  the same identity and memoized loss.

An active PID collision remains an invariant failure and never authorizes
overwriting the earlier mapping.

## Accepted design package

Canonicalization should preserve the following complete package.

### Packaging and compatibility

- `plan9.cma` remains an ML-only Plan 9 otherlib.
- Native process primitives are built into the standard Plan 9 `ocamlrun`.
- Ordinary consumers require neither `-custom` nor a C toolchain.
- `Sys` and `Unix` retain their APE-backed portable behavior.
- Plan9.Process does not use a shell, PATH search, quoting, globbing, or APE
  process semantics.

### Environment boundary

- Globally intended `NPROC`, `sysname`, and prompt values are finalized before
  the environment-group split.
- `Plan9.Raw.copy_environment ()` performs only current-process `RFENVG`.
- Derived CPU-017 `auth` and `serviced` values are written after the split.
- Service launchers inherit the deliberately selected copied group.
- No environment mirror, replay map, APE synchronization, or per-child overlay
  is introduced.

### Rfork and exec safety

- Production spawn is one native rfork/exec primitive.
- The child never returns into OCaml.
- `RFMEM`, a child-returning rfork, `RFNOWAIT`, unknown masks, and a generic
  integer escape remain unavailable and defensively rejected.
- The default child policy remains `RFPROC | RFFDG | RFREND`, sharing the
  deliberately selected environment group, namespace, and note group.
- `RFNOMNT` is deferred from Phase 2.
- Raw exec receives exact nonempty argv; high-level process operations
  synthesize argv0 from `program`.

### Durable launch ownership

- The native pending-child record is allocated before rfork.
- A positive parent PID is published into that record before handshake I/O,
  allocation, asynchronous exception delivery, or return to ML.
- The spawn primitive never calls await.
- Known exec failure is reaped only through the shared coordinator.
- Interrupted or malformed handshakes remain handle-bearing.
- The bounded versioned error frame and collision-safe descriptor movement
  remain subject to installed ABI evidence.

### Wait ownership and completion routing

- Plan9.Process exclusively owns native await while any managed or native
  pending owner remains unresolved.
- No public `Plan9.Raw.wait_any` competes with it.
- Each child has a never-reused logical process identity in addition to its
  native PID.
- PID mappings exist only for active unresolved owners.
- Terminal state is stored on the handle.
- Unknown completions are classified as foreign when reaped and can never be
  attached to a later PID reuse.
- Mixing `Sys.command`, `Unix.wait`, APE wait functions, or another native
  waiter during the managed interval remains unsupported.
- Exact `No_children` is the only ordinary observation that converts still
  owned unresolved children into terminal wait-queue loss.

### Public lifecycle

- Spawn returns a handle for every post-rfork nonterminal result.
- Run drives that handle synchronously through the same coordinator.
- Wait and run distinguish completion, retryable or unresolved operation
  states, and terminal observable loss.
- No background reaping is implied.
- Foreign-queue backpressure is recoverable after FIFO drainage.
- Coordinator invariant and malformed-record failures stop native consumption
  without claiming child completion.

### Evidence separation

- Source contracts determine structural safety and implementation choices.
- The harmless ABI probe may measure installed declarations, widths, units,
  error strings, `OCEXEC`, `#d`, descriptor collisions, bounded interruption,
  current-process `RFENVG`, and short-lived completion ordering.
- The harmless probe does not start auth, keyfs, listeners, real services, or
  caml9.
- Stateful service behavior, descendants, and CPU-017 integration use later
  separately authorized gates.
- Passing the ABI probe is not service or boot acceptance.

## Canonicalization requirements

The later canonicalization gate should update these documents together:

- `docs/design/plan9/01-native-api-requirements.md`;
- `docs/design/plan9/03-verification-and-recovery.md`; and
- `docs/design/plan9/04-implementation-plan.md`.

It should also update this exchange README's canonicalization column and
dispositions as appropriate. It should not rewrite P2-002 through P2-007.

The canonical API requirements currently retain superseded shapes, including
caller-supplied high-level argv0, `status`, a public raw wait path, and a
pid-keyed wait-cache description. Canonicalization must remove or replace
those rather than layering contradictory paragraphs below them.

The canonical documents should make the following lifecycle points explicit:

1. queue ownership does not imply background progress;
2. `Process.run` is synchronous and handle-preserving;
3. outer spawn or run `Error` means no child remains;
4. every nonterminal result preserves the owned handle or complete owner set;
5. interruption and foreign backpressure leave handles active;
6. exact `No_children` terminalizes adopted and pending owners as loss;
7. invariant and malformed-record failures leave ownership unresolved and the
   coordinator failed closed;
8. foreign FIFO drainage makes a backpressured wait retryable;
9. process-ID exhaustion fails before rfork; and
10. CPU-017 resolves each direct launcher before later APE child/wait use.

The exact public constructor names should be selected once during
canonicalization and then used consistently by the implementation plan and
tests.

## Remaining evidence and implementation questions

Acceptance of the design does not claim that installed native behavior or an
implementation has passed. The following remain intentionally open:

- installed declarations, symbols, and link behavior;
- exact wait-field widths and timing units;
- exact native wait messages and error classifications;
- `#d/<fd>` plus `OCEXEC` behavior;
- bounded error-text size and short-I/O behavior;
- descriptor collisions involving 0, 1, and 2;
- bounded interruption observations;
- installed current-process `RFENVG` copy/isolation behavior;
- C runtime integration and cleanup review;
- focused coordinator and state-machine tests;
- no-C-tool installed consumer proof for the new primitives;
- `keyfs` and `aux/listen` launcher/descendant behavior; and
- later caml9 integration and boot evidence.

Those are later gates, not reasons to keep the exploration design open.

## State and authorization boundary

The accepted design still requires cross-repository record reconciliation
before any stateful VM, endpoint, transfer, build, installation, or probe gate.
That reconciliation is separate from canonicalization and must:

- revalidate live OCaml and `.40` state;
- preserve completed Phase 1 history;
- correct caml9's dated `.40` ownership record under an explicit handoff;
- keep the caml9 `.32` VM lane untouched; and
- name one sole stateful operator and the exact next authorized gate.

This review does not perform or authorize that work. Operational ownership
remains with the OCaml task.

## Durable-state review

The completed exchange now records the accepted architecture, rejected
alternatives, ownership rules, lifecycle limitations, evidence boundaries,
and remaining risks that would otherwise have to be reconstructed from task
transcripts.

No additional caml9 repository documentation gap was found within this review.
D044 remains the current compatibility rule until the accepted native API is
implemented, independently qualified, and adopted by a separately authorized
caml9 gate.

The P2 design exchange is closed pending canonicalization. No implementation,
stateful probe, publication, or operational gate begins automatically.
