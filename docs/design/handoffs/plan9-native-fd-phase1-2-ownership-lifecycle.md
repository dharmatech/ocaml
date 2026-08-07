# Phase 1.2 `Plan9.Fd` ownership lifecycle handoff

Status: accepted and completed; Phase 1.2 checkpoint
`ff4a65b9b0b99c10725957fe318cebce95f0e968`; final Phase 1 checkpoint
`ee8f799bba40f2ed8caa57a4ef7e91726f2f4283`

## Authority and required reading

This handoff delegates only the Phase 1.2 ownership lifecycle. Before editing,
read:

- `docs/design/handoffs/plan9-native-fd-phase1.md` completely;
- the accepted Phase 1.1 completion report and implementation diff;
- the foundation's APE-independence boundary, layered architecture, private
  capability design, error handling, heap/blocking rules, proposed source
  boundary, `Plan9.Fd` target contract, non-goals, and required reports;
- the accepted Phase 0.2 capability lifecycle and Phase 0.3 final-acceptance
  handoffs for native ownership and publication invariants;
- release-11554 `sys/man/2/pipe`, `sys/man/2/open`, and
  `sys/src/9/port/sysfile.c` facts recorded in the roadmap;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before those actions occur.

If Phase 1.1 differs from its accepted report, or this handoff conflicts with
the reviewed roadmap or foundation, stop and return the evidence.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. The accepted code predecessor is exactly
`fff8fc57552523e37a03dcf55a98466d471a9b8a`; its reviewed documentation
predecessor is exactly
`9369474ed38cf35bb0bf699e28d617a88c534e07`. The reviewed Phase 1.2
documentation-checkpoint `HEAD` is exactly
`fab00d79c52990c5203845e38dd62da24e531a18`. Verify a clean index and worktree,
expected branch and remote tracking state, and no unrelated history.

Do not begin from an uncommitted, dirty, unqualified, or rejected Phase 1.1.
Do not stash, reset, clean, or absorb unrelated work.

## Accepted predecessor facts

Phase 0 supplies validated opaque descriptor capabilities and the accepted
native `PIPE` and `CLOSE` path. Phase 1.1 supplies uninstalled
`Plan9_types` and `Plan9_primitive` modules, with existing behavior and public
API unchanged. Production `Plan9_primitive` still contains only the Raw and
process bindings moved from `plan9.ml`; the descriptor capability, pipe, and
close declarations remain test-local at that checkpoint.

The native pipe primitive preallocates, roots, and initializes its capability
and success blocks before acquisition. A successful native return therefore
already has deterministic capability ownership. The high-level `Fd.pipe`
wrapper must nevertheless preallocate its own ownership cells and complete
public result before calling that primitive: capabilities have no finalizer,
so allocating wrappers after successful acquisition could leak descriptors if
allocation raised.

Release 11554 returns two distinct, bidirectional, `ORDWR` pipe descriptors as
an all-or-nothing pair. A valid native close is guaranteed to close and return
success. The accepted runtime still terminalizes a capability before raw
close so an unexpected native or result-construction failure cannot make an
uncertain descriptor reusable.

## Delegated outcome

Add the private, uninstalled `Plan9_fd` module with:

- production `Plan9_primitive` bindings for the accepted opaque capability,
  pipe, and close operations;
- a shared abstract ownership cell;
- native pipe construction with allocation-safe wrapper publication;
- deterministic public close and alias semantics;
- explicit detached, public-closing, publicly closed, attached,
  owner-closing, and owner-closed states;
- a preallocated private attachment token with an allocation-free commit; and
- fake-backend and native lifecycle tests.

This subphase does not implement read or write, does not re-export `Plan9.Fd`
from `plan9.ml` or `plan9.mli`, and does not update installed public
documentation. The complete public module is published only in Phase 1.3.

## Internal module and test boundary

Add:

- the descriptor capability, pipe, and close declarations in
  `otherlibs/plan9/plan9_primitive.mli` and `.ml`;
- `otherlibs/plan9/plan9_fd.mli` and `.ml`;
- `otherlibs/plan9/tests/fd_lifecycle_test.ml`; and
- the minimal Makefile and dependency wiring needed to build the private
  module and focused test.

`Plan9_fd` depends only on `Plan9_types` and a narrow primitive backend. It
must not depend on `Plan9`, `Plan9_process`, `Stdlib` channels, `Sys`, or
`Unix`.

Structure the module around an internal backend signature, result signature,
and functor so the ownership state machine can be tested without native
syscalls. The uninstalled `plan9_fd.mli` has this complete shape; the final
`include S` is the private production instance:

```ocaml
module type Primitive = sig
  type capability

  val pipe :
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  val close :
    capability -> (unit, Plan9_types.native_failure) result
end

module type S = sig
  type t
  type attachment

  val pipe : unit -> ((t * t), Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

module Make (_ : Primitive) : S

include S
```

The private CMI deliberately spells out `S` without naming
`Plan9_primitive`. It therefore depends on `Plan9_types.cmi` only. The
implementation instantiates `Make` with the narrow descriptor subset of
`Plan9_primitive` and consequently has a direct implementation dependency on
both `Plan9_types` and `Plan9_primitive`.

The new production bindings retain the accepted logical shapes and exact C
symbols. `plan9_primitive.mli` adds the abstract type and corresponding
`val` declarations:

```ocaml
type descriptor_capability

val descriptor_pipe :
  unit ->
  ((descriptor_capability * descriptor_capability),
   Plan9_types.native_failure) result

val descriptor_close :
  descriptor_capability ->
  (unit, Plan9_types.native_failure) result
```

`plan9_primitive.ml` adds these exact production declarations:

```ocaml
type descriptor_capability

external descriptor_pipe :
  unit ->
  ((descriptor_capability * descriptor_capability),
   Plan9_types.native_failure) result
  = "caml_plan9_syscall_pipe"

external descriptor_close :
  descriptor_capability ->
  (unit, Plan9_types.native_failure) result
  = "caml_plan9_syscall_close"
```

Neither external carries `[@@noalloc]` or any other calling-convention,
allocation, or code-generation attribute. The ML names, arities, result
layouts, native-failure identity, and C symbols are exact.

They accept or return capabilities only and never expose descriptor integers.
Do not add production read or write bindings yet. The production `Plan9_fd`
module instantiates the functor with these bindings and exposes `S` from its
uninstalled CMI. The private ML names in this handoff are now fixed. Any
proposed rename or signature change requires documentation review before
implementation; C symbols, arities, result shapes, public ownership, token
authorization, allocation, and native-call behavior must remain unchanged.

## Ownership cell contract

### Shared aliases

Copying a `t` aliases the same ML cell and capability. It does not allocate a
new owner and never invokes native `dup`. Every alias observes the same
lifecycle transition.

The cell distinguishes these exact semantic states:

1. unpublished, used only while a preallocated pipe result is private to
   `pipe`;
2. open and detached, permitting public ownership operations;
3. public close in progress or uncertain, retaining a preallocated public
   close attempt whose immediate `active` flag distinguishes an executing
   backend call from a retryable unwound attempt;
4. publicly closed, permitting idempotent public close only;
5. attached to one exact private token, rejecting every public operation;
6. owner close in progress or uncertain, retaining that exact committed token
   and a preallocated owner-close attempt with the same `active` distinction;
   and
7. owner-closed after attachment, retaining the exact committed token,
   rejecting public operations, and making private owner close idempotent.

The implementation may encode those states compactly, but must not collapse
publicly closed, owner-closed, or either close-attempt state. A closing cell
is not open and detached: it rejects attachment and, in Phase 1.3, will reject
I/O. Publicly closed and owner-closed must not be collapsed in a way that
allows a retained public alias to regain authority after attachment.

Every object needed to represent both the in-flight close and its terminal
state is allocated before the cell leaves its prior stable state. The
implementation may instead encode terminalization by mutating an immediate
field in a preallocated attempt, but after the backend returns it must not
allocate a public-closed or owner-closed marker. Allocation failure before
the state transition therefore leaves an open public cell open and detached,
or an attached cell attached to its exact owner, without backend work.

The attempt's mutable `active` flag and any mutable terminal-phase field
contain only immediate values. Deactivation on exception, reactivation for a
later retry, and terminalization after a normal backend result are
allocation-free and perform no callback, safe point, or pending-action
processing. Owner-closing and owner-closed representations both retain the
exact token in a GC-scanned field so token identity and authorization survive
every collection.

Any lifecycle path that allocates before a state-dependent transition or
successful return treats every earlier state or authorization observation as
provisional. It must either allocate all candidate values before its first
authoritative observation, or recheck the shared cell after all such
allocations. The authoritative state/token check is followed immediately by
the allocation-free transition or return, with no intervening allocation,
callback, safe point, or pending-action processing. If the state changed
during allocation, discard the unused candidates and dispatch exactly as a
new invocation observing that current state; never overwrite or undo the
competing close or attachment transition. This rule applies to public close,
private owner close, and attachment preparation. `commit_attach` already has
no allocation window and performs its authoritative recheck immediately
before commit.

The cell holds its capability in a GC-scanned, preallocated slot initialized
to a safe non-capability placeholder while unpublished. A capability may be
read from that slot only after the lifecycle proves it was published. If a
typed capability field cannot be safely initialized before acquisition, use a
narrow private `Obj.t` slot with explicit invariants rather than allocating an
option or variant after native success. No placeholder ever reaches a
primitive or escapes in a returned `Fd.t`.

There is no descriptor-closing finalizer. Dropping the last open `Fd.t`
without explicit close remains a caller ownership error; tests and higher
layers must close deterministically.

### Allocation-safe pipe publication

Before calling the accepted primitive `pipe`, allocate and retain as roots:

- both unpublished ownership cells and their GC-safe capability slots;
- the pair containing those exact cells; and
- the enclosing public `Ok` result.

On primitive failure, construct the high-level `Plan9.Fd.pipe` error only
after the primitive has established that it owns no descriptor. The
unpublished cells are discarded and never escape.

On primitive success, perform only straight-line, allocation-free publication:

1. copy each returned capability into its preallocated cell slot;
2. transition both cells to open and detached;
3. return the already allocated `Ok` pair.

There must be no fallible allocation, callback, safe point, or pending-action
processing between successful primitive return and publication of both
owners. If the ML compiler or runtime makes that claim uncertain, inspect the
generated bytecode/native instruction path used on Plan 9 or select a simpler
representation whose allocation-free property can be demonstrated.

Do not clean up one endpoint through high-level allocation after a successful
primitive pipe call. Either both preallocated owners are published, or a
discovered invariant violation is handled by an explicitly reviewed
allocation-free cleanup path that closes both still-owned capabilities.

### Public close

`close` uses operation name `Plan9.Fd.close`.

- For an open, detached cell, allocate the public close attempt, enclosing
  public-closing state, and any terminal candidate before changing the cell.
  Apply the authoritative post-allocation state rule above. Only if the cell
  is still open and detached may the wrapper set the attempt active, install
  that preallocated state, and invoke the accepted capability close exactly
  once for that active attempt; otherwise it discards the candidates and
  handles the current state without stale-state overwrite.
- While the attempt is active, a callback observes a public-closing cell.
  `prepare_attach` returns its exact validation error, every already prepared
  token fails `commit_attach`, and a reentrant public close returns its exact
  in-progress validation error. None of those paths invokes the backend.
- After any normal primitive return, whether `Ok` or `Error`, perform the
  allocation-free transition to publicly closed before the wrapper returns
  or maps that result.
- A capability close failure preserves its exact native message and mapped
  kind. The cell remains terminal because the descriptor is uncertain.
- Repeated close through any public alias of a publicly closed cell returns
  `Ok ()` without another primitive call.
- An attached, owner-closing, or owner-closed cell returns structured
  `Invalid_argument` without a primitive call; attachment permanently
  revoked public close authority.
- If the backend raises, catch only to set the existing attempt's immediate
  `active` flag to `false`, then re-raise the physically identical exception
  value with ordinary OCaml reraise semantics. Do not restore
  open-and-detached state and do not force a second close while unwinding. The
  cell remains public-closing and therefore cannot be attached or used for
  another operation.
- A later public close through any alias may retry an inactive public-closing
  attempt by setting its flag active and invoking the same capability close
  once. If the earlier exception occurred before the native commit, that call
  performs the close; if it occurred after native terminalization, the
  accepted capability close is idempotent and performs no second syscall.
  A normal retry result transitions to publicly closed before publication.

The exception handler encloses exactly the backend `close` invocation. It is
no longer active once the backend has produced a normal result; the wrapper
then terminalizes allocation-free and only afterward performs native-error
mapping. An exception from result mapping therefore cannot deactivate,
restore, or otherwise change the already publicly closed cell.

“Unchanged exception” throughout this handoff means that the exact caught
exception value is re-raised by ordinary OCaml reraise compilation. Do not
wrap, translate, replace, or explicitly capture a backtrace through
`Printexc`; raw-backtrace byte identity is not a separate acceptance
requirement. The generated bytecode must use `RERAISE` after the allocation-
free deactivation, preserving the runtime's normal reraise behavior without
adding another module dependency or fallible cleanup step.

This transient state reconciles callback reentrancy with the native
primitive's exception boundary. Do not catch arbitrary exceptions merely to
claim success or force the cell terminal: before the primitive commit point an
exception can mean the descriptor was never closed. The ML attempt state
serializes authority, while the accepted capability remains the final
authority over whether native close has committed.

## Private attachment protocol

Attachment is internal ownership transfer for a future native channel, not a
public API. It performs no native syscall and never changes the descriptor.

`prepare_attach`:

- accepts only an open, detached cell;
- allocates an opaque token referring to that exact cell;
- preallocates any owner marker/state needed by commit and the enclosing
  successful `Ok` result;
- applies the authoritative post-allocation state rule immediately before
  returning that success, so a token whose cell changed during allocation
  does not escape;
- returns the preallocated token without changing the cell only while that
  final check still observes open and detached; and
- returns structured `Invalid_argument` for publicly closing, publicly
  closed, already attached, owner-closing, or owner-closed cells without
  native work.

Preparation does not reserve the cell. Retained public aliases remain
operational until commit and may close it. Multiple preparations may exist,
but at most one token can commit.

`commit_attach`:

- is a straight-line allocation-free function returning an immediate `bool`;
- rechecks that the cell is still open and detached immediately before the
  transition;
- installs the exact prepared token as owner and changes the state to attached
  without allocation, callback, safe point, or native work;
- returns `true` only for the one token that performed that transition; and
- returns `false` without changing state for a stale, competing, publicly
  closing, publicly closed, already committed, owner-closing, or owner-closed
  token.

The token, any attached-state marker, and any owner slot must therefore be
allocated and GC-safe before commit. Owner operations authorize by exact token
identity, not merely by observing a generic attached state. A losing prepared
token can never operate on or close the descriptor.

`Private.close` uses lower-level operation name `Plan9.Fd.close` and invokes
the native close only for the exact committed token:

- from attached state, allocate the owner-close attempt, enclosing
  owner-closing state, and any terminal candidate before changing the cell;
  retain the exact committed token in those representations and apply the
  authoritative post-allocation state/token rule above; only if the cell is
  still stably attached to that token may the wrapper mark the attempt active,
  install the preallocated state, and invoke the backend once, otherwise it
  discards the candidates and handles the current state without stale-state
  overwrite;
- while the attempt is active, a reentrant close through the same token
  returns the exact in-progress validation error without backend work;
- after any normal primitive result, perform the allocation-free transition
  to owner-closed before returning or mapping that result;
- if the backend raises, deactivate the existing attempt and re-raise the
  physically identical exception value under the shared unchanged-exception
  rule without changing its owner-closing state;
- the same exact committed token may later reactivate and retry an inactive
  owner-closing attempt, relying on capability-close idempotence exactly as
  the public retry does;
- owner close is idempotent for that same token after owner-closed; and
- an uncommitted, stale, losing, or merely competing token returns structured
  `Invalid_argument` without native work in attached, owner-closing, and
  owner-closed states.

Retained public aliases remain revoked throughout attached, owner-closing, and
owner-closed states. No public alias can perform or retry an owner close.
As on the public path, the private deactivation handler encloses exactly the
backend `close` invocation. Native-error mapping occurs only after the
allocation-free owner-closed transition and is outside that handler, so a
mapping exception cannot reactivate or roll back owner state.

Phase 2 will allocate its channel and enclosing success result after
preparation but before commit, then return the preallocated success only if
commit succeeds. Allocation failure before any competing alias acts leaves the
original descriptor open and detached. If commit returns `false`, no
ownership transfers to that channel: the shared cell instead retains the exact
state established by the competing alias, which may be open, public-closing,
publicly closed, attached to another token, owner-closing, or owner-closed.
The failed channel and enclosing success never escape, and the caller must not
assume the descriptor remained operational merely because its own commit
lost. Phase 1.2 proves the token protocol but does not allocate or expose a
channel.

## Error and threat boundaries

Native failures map directly through `Plan9_types.error_of_native`, retain
the captured message, and use `Plan9.Fd.pipe` for descriptor-pipe failure or
`Plan9.Fd.close` for both public and exact-owner close failure.
`commit_attach` returns only its immediate `bool` and constructs no error.
Every ML lifecycle rejection uses `Invalid_argument` and this exact matrix:

| Path | Rejected condition | Operation | Message |
| --- | --- | --- | --- |
| public `close` | attached, owner-closing, or owner-closed | `Plan9.Fd.close` | `descriptor ownership has been transferred` |
| public `close` | active public-close attempt | `Plan9.Fd.close` | `descriptor close is already in progress` |
| `Private.prepare_attach` | any state other than open and detached | `Plan9.Fd.Private.prepare_attach` | `descriptor is not open and detached` |
| `Private.close` | active owner-close attempt through the exact owner | `Plan9.Fd.close` | `descriptor close is already in progress` |
| `Private.close` | uncommitted, stale, losing, competing, or otherwise unauthorized token | `Plan9.Fd.close` | `attachment token is not the committed owner` |

An inactive public-close attempt is a retry path, not a rejection. An inactive
owner-close attempt is retryable only through its retained exact committed
token. Publicly closed public close and owner-closed exact-owner close return
`Ok ()` idempotently. Do not broaden these messages with state dumps,
capability data, token identities, or descriptor integers.

The public `t` and private token are ordinary abstract ML types. Unsafe
`Obj.magic` forging or representation mutation of those ML values is outside
their contract. The accepted native capability primitives remain defensively
validated against correct-arity hostile `external` declarations, including
forged well-formed OCaml values; rerun those tests unchanged.

No capability or owner token is exposed by the installed umbrella in this
subphase. No raw descriptor crosses any ML boundary.

## Required focused tests

### Fake counted backend

The functor test uses a fake capability and records every pipe and close call.
At minimum, prove:

- a successful pipe returns two distinct cells backed by the exact two fake
  capabilities;
- a one-shot normal-return pipe callback performs `Gc.minor ()`,
  `Gc.full_major ()`, and `Gc.compact ()` before returning the exact two fake
  capabilities; the wrapper still publishes two distinct owners backed by
  those respective capabilities, and closing them produces exactly one close
  call for each capability. Together with the source and generated-instruction
  audit, this proves that the unpublished cells and enclosing success remained
  rooted and that those preallocated owners, rather than post-return
  replacements, were published;
- primitive pipe failure returns the mapped `Plan9.Fd.pipe` error and no owner;
- aliases share close state and exactly one primitive close occurs;
- repeated public close is idempotent without a backend call;
- a backend close error preserves the exact mapped operation, kind, and
  message, terminalizes the public cell, and is not retried;
- prepare does not revoke public ownership before commit;
- close between prepare and commit makes commit fail;
- a previously prepared token attempting to commit from inside an active
  public-close callback returns `false`, and the outer close retains sole
  authority;
- reentrant public close from that callback returns the exact in-progress
  error without a second backend call;
- a callback exception from public close leaves an inactive, non-attachable
  public-close attempt; the physically identical designated exception value
  is reraised, and a later public close retry makes exactly one additional
  backend call and terminalizes normally;
- of two competing tokens, exactly one commits and only it is authorized;
- after commit, public close and further attachment fail without backend work;
- private close through the committed token calls the backend once and is
  idempotent thereafter;
- a backend close error through the exact committed token preserves the exact
  mapped operation, kind, and message, terminalizes the owner-closed state,
  leaves public aliases and nonowner tokens revoked, and is not retried;
- reentrant private close through the committed token returns the exact
  in-progress error without a second backend call;
- a callback exception from owner close leaves an inactive owner-close
  attempt, reraises the physically identical designated exception value, and
  remains authorized only to the exact committed token, whose later retry
  makes exactly one additional backend call and terminalizes normally;
- throughout active and inactive owner-close attempts, every public alias and
  every nonowner token remains rejected without backend work;
- stale, losing, and uncommitted tokens cannot close;
- retained public aliases remain rejected after owner close; and
- forced minor and major GC between preparation, commit, close, callback
  exception, and retry preserves cell/attempt/token identity and capability
  reachability.

The fake backend must provide one-shot injected callbacks and callback
exceptions for the close cases above, recording the complete ordered call
trace. Use allocated designated exception values rather than nullary
constructors and assert physical identity with the value caught from public
close and owner close. It must provide two separate one-shot pipe callback
cases: the normal-return forced-GC callback above, and a callback that raises
an allocated designated exception before returning. The raising case proves
physical identity of the propagated value and proves that no ownership cell
or enclosing success escapes. The preallocated cells remain private until the
normal backend success returns and then only the exact reviewed owners escape;
in the raising case the cells and enclosing success never escape. These are
deterministic fake-backend behaviors, not timing injection; do not add a
production fault switch.

Exercise every row of the exact lifecycle-error matrix in every reachable
stable, active-attempt, and inactive-attempt state to which that row applies.
For each rejection, assert the complete operation, `Invalid_argument` kind,
and exact message, plus an unchanged backend-call count. This includes
`prepare_attach` during active and inactive public close, public close across
all transferred-owner states, and unauthorized private close across all
token-bearing states. The normal native-failure cases for public and exact-
owner close must likewise assert the complete mapped error before proving
their respective terminal idempotence.

Exercise the complete immediate-boolean matrix separately for
`commit_attach`: the first still-current prepared token commits exactly once
and returns `true`; a repeated commit through that winning token, every losing
or competing token, and every token attempted in public-closing, publicly
closed, attached, owner-closing, or owner-closed state returns `false`, leaves
the exact state unchanged, and performs no backend work. Source and generated-
instruction review must additionally prove that this check and transition
allocate nothing and contain no callback or safe point.

The mandatory generated-instruction audit in native qualification applies to
all allocation-sensitive spans, not only `commit_attach`. Source review alone
does not satisfy that acceptance item.

### Native lifecycle test

The native focused path uses the production `Plan9_fd` instance and verifies:

- two native pipe peer owners can be created and both explicitly closed;
- aliases observe deterministic and idempotent close;
- attachment revokes public close and only the committed owner token closes;
- repeated create/close and create/attach/owner-close cycles leave the sorted
  complete `/fd` inventory unchanged; and
- the existing Phase 0 hostile primitive, native error, and descriptor-leak
  suites still pass.

Phase 1.2 has no public read/write API, so it does not perform byte transfer
through `Plan9_fd`. The accepted Phase 0 round-trip suite remains the native
I/O regression for this checkpoint.

## Source and packaging review

Before VM work, review:

- every allocation relative to primitive pipe acquisition and owner
  publication;
- GC-safe placeholder and capability-slot invariants;
- exact cell transitions, authoritative post-allocation state/token checks,
  and absence of stale-state overwrite;
- public and owner close behavior on success, native failure, callback
  exception, and repeated calls;
- absence of native calls on invalid lifecycle/token paths;
- absence of finalizers, raw integers, ordinary channels, APE descriptor
  registration, `dup`, or foreign adoption;
- the functor boundary and production instantiation;
- exact addition of only capability pipe/close primitive imports to the
  production archive;
- the complete generated ML dependency graph, exact archive order, and
  uninstalled `plan9_fd.cmi`;
- byte identity of the rebuilt public `plan9.cmi` with the exact artifact
  accepted in Phase 1.1, plus an isolated staged-consumer rerun proving that
  the changed archive still needs no private CMI at consumer compile or link
  time;
- every executable linked with force-linked `plan9.cma` now runs with
  `$(NEW_OCAMLRUN)`, including the environment test, because the archive now
  imports Phase 0 descriptor primitives absent from the bootstrap runtime;
- the additive lifecycle test links the private objects in the reviewed order
  and runs with `$(NEW_OCAMLRUN)`;
- the pure process-state executable still links only `plan9_types.cmo` and
  `plan9_process.cmo` and continues to run with bootstrap `$(OCAMLRUN)`; and
- unchanged `plan9.mli`, README, installed reference, runtime C, raw assembly,
  primitive inventory, and every predecessor source below
  `otherlibs/plan9/tests`.

The new generated dependency edges are exact:

| Artifact | Private compilation prerequisites | Runtime implementation globals |
| --- | --- | --- |
| `plan9_fd.cmi` | `plan9_types.cmi` | not applicable |
| `plan9_fd.cmo` | `plan9_fd.cmi`, `plan9_types.cmi`, `plan9_primitive.cmi` | `Plan9_types`, `Plan9_primitive` |
| `plan9_fd.cmx` | `plan9_fd.cmi`, `plan9_types.cmx`, `plan9_primitive.cmx` | `Plan9_types`, `Plan9_primitive` |

`plan9.cmo` and `plan9.cmx` gain no `Plan9_fd` source edge in this
subphase because the umbrella does not re-export the incomplete module. The
generated `.cmx` rule is dependency metadata for non-Plan-9 builds, not
native-code qualification.

`CAMLOBJS` is exactly:

```make
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo plan9_process.cmo plan9.cmo
```

This is also the exact `plan9.cma` unit order. `CMIFILES` remains exactly
`plan9.cmi`. The additive `fd_lifecycle_test` executable links, in order,
`plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo` and its test source; it
does not link `plan9.cma`, `Plan9_process`, or the umbrella. Because the
production `Plan9_fd` instance imports `Plan9_primitive`, both its fake and
native cases run with `$(NEW_OCAMLRUN)`; keeping this test on the bootstrap
runtime would require another source-module split and is not authorized here.

Every existing executable linked with `plan9.cma`, including
`tests/env_test`, runs with `$(NEW_OCAMLRUN)`. Process primitive validation,
syscall capability, and process native integration retain their accepted new
runtime lane; frame parser and raw syscall remain direct native executables;
and the native helper remains a direct child. The filtered pure process-state
test alone retains bootstrap `$(OCAMLRUN)`. No predecessor test source is
edited to obtain these linkage changes; `tests/fd_lifecycle_test.ml` is the
only additive test source.

`plan9.cma` may now contain the private `plan9_fd.cmo`, but remains ML-only.
Only `plan9.cmi` remains selected for installation. The incomplete internal
module must not be re-exported as public `Plan9.Fd` yet.

The archive's primitive-name set may differ from accepted Phase 1.1 only by
the exact existing `caml_plan9_syscall_pipe` and
`caml_plan9_syscall_close` names. This is an ML binding change, not a new
runtime primitive or native ABI change. The hostile Phase 0 test keeps its
direct bindings for independent defensive validation.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state, the accepted Phase 1.1 checkpoint, the exact approved Phase
1.2 documentation checkpoint, and the accepted Phase 1.1 just-built public
`plan9.cmi` path, decimal size, and content hash from its completion evidence.
Also record exact private module interfaces, primitive shapes, allocation
conventions, runtime pending-action behavior, Makefile/dependency state, and
complete untracked and ignored path inventories. Confirm that `.depend` has
identical bytes at the accepted Phase 1.1 and Phase 1.2 documentation
checkpoints. Implement only the production
capability pipe/close bindings, ownership, pipe, close, attachment, and
focused lifecycle tests. Make the hand-written Makefile changes, but leave the
tracked `.depend` byte-for-byte at accepted Phase 1.1 and mark native
regeneration as the single pending generated artifact. Do not hand-edit or
predict its new rules.

### 2. Source review before VM work

Run safe host-side checks and inspect the authoritative implementation diff
from the exact approved Phase 1.2 documentation checkpoint. Separately inspect
the cumulative diff from accepted Phase 1.1. The first diff must contain only
the delegated Phase 1.2 implementation, test, and hand-written build changes,
with `.depend` still unchanged. The cumulative diff must consist only of the
reviewed Phase 1.2 documentation-checkpoint delta plus that authoritative
implementation diff; any other change stops the subphase.

Report both baseline identities and diff inventories, the cell
representation, publication proof, state machine, close exception boundary,
token protocol, backend call counts, exact expected dependency DAG, test
linkage, and packaging state. Confirm that every predecessor test source and
public/runtime file is unchanged. Stop before VM access with only `.depend`
pending.

### 3. Explicit VM confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, WHPX profile, and retained configured native source
tree. Confirm that the selected tree has the working bootstrap runtime,
bootstrap compiler, configuration, and GNU Make required by the dependency
target. Use the repository VM and native-build skills. Transfer without
`.git` through `/mnt/term`, copy onto native storage, and verify and retain an
exact pre-generation source manifest using canonical repository-relative
paths, decimal byte lengths, and the reviewed content-hash algorithm.

The compared and transferred source set is every existing path reported by
`git ls-files` at the approved Phase 1.2 documentation checkpoint, using the
current authoritative worktree bytes, plus exactly these three reviewed new
paths:

- `otherlibs/plan9/plan9_fd.ml`;
- `otherlibs/plan9/plan9_fd.mli`; and
- `otherlibs/plan9/tests/fd_lifecycle_test.ml`.

No source deletion or other new path is expected. Record complete untracked
and ignored inventories separately; transfer no other untracked or ignored
path and never transfer `.git`. Keep manifest files and comparison evidence
outside both source trees. Because this is a retained configured tree, its
pre-existing generated objects and other build artifacts are inventoried
separately and are outside the compared source-set manifest; their presence
does not add a source path or permit a differing byte at any manifested path.
Never build on `/mnt/term`.

### 4. Native dependency generation and authoritative return

Record guest, source-tree, bootstrap compiler, configured host, GNU Make, and
release identity. Before any compilation, archive relink, runtime relink, or
test, run only the existing `otherlibs/plan9` dependency target through the
accepted APE/GNU Make lane. The target redirects directly to `.depend`, so
accept its output only after a successful command exit.

Require a nonempty generated file containing `.cmi`, `.cmo`, and `.cmx`
rules for `plan9_types`, `plan9_primitive`, `plan9_fd`,
`plan9_process`, and `plan9`. Compare the generated `plan9_fd` edges with
the exact table above and confirm that `plan9` gained no source dependency on
the unpublished module.

Record the guest file's exact path, contents, size, and content hash. Return
only that validated text artifact through a validated `/mnt/term` exchange
path, update only authoritative Windows
`otherlibs/plan9/.depend`, and require byte-for-byte identity between the
guest, returned, and authoritative files. Do not return build artifacts,
generated binaries, `.git`, or another guest path. A failed, empty,
truncated, partial, or incomplete output is rejected and must not update the
Windows file.

Record the guest manifest delta caused by successful dependency generation.
Relative to the retained pre-generation manifest, exactly
`otherlibs/plan9/.depend` may have a different content and size tuple; no
other source-manifest entry may be added, removed, or changed.

### 5. Final host source review

Inspect the authoritative implementation diff from the exact approved Phase
1.2 documentation checkpoint, now including the natively generated
`.depend`. Separately inspect the cumulative diff from accepted Phase 1.1 and
again require it to contain only the reviewed documentation-checkpoint delta
plus that implementation diff. Re-run all safe source, ABI, allocation,
state-machine, immutable-test, dependency, primitive, packaging, and diff
checks. Produce fresh complete post-generation manifests for the authoritative
Windows checkout and guest using the same canonical paths, lengths, hash
algorithm, sorting, and source-set boundary as the retained pre-generation
manifest. Require those two final manifests to match exactly, require the
generated dependency bytes to match separately, and confirm that the guest
pre/post delta contains only the expected `.depend` tuple change. Stop if any
file, diff inventory, manifest entry, generated byte, or dependency edge
differs; no native build starts before this review passes.

### 6. Native qualification

Build the standard runtime. After the final manifest gate and before any test,
perform a target-scoped forced rebuild in the retained tree of
`otherlibs/plan9/plan9.cma` and `otherlibs/plan9/tests/fd_lifecycle_test`
through the recorded GNU Make `-B` lane. Preserve the complete command and
build log. That log must show compilation of the current
`plan9_fd.mli` and `plan9_fd.ml`, production of `plan9_fd.cmi` and
`plan9_fd.cmo`, production of the current `plan9.cmi`, relinking of
`plan9.cma`, and compilation/linking of the lifecycle executable after final
manifest approval. An absent command, up-to-date shortcut, stale artifact, or
incomplete log is not qualification; stop rather than infer provenance from
timestamps or hashes. This scoped rebuild does not authorize cleaning or
rebuilding unrelated retained artifacts.

Immediately after that rebuild, record the new public `plan9.cmi` path,
decimal size, and content hash and require byte-for-byte identity with the
exact accepted Phase 1.1 artifact recorded during preflight. An identity
mismatch means that this private subphase changed or failed to reproduce its
public compilation interface and stops qualification even if `plan9.mli`
source bytes are unchanged.

Also perform a target-scoped forced build from the repository root using the
recorded GNU Make command shape
`<GNU Make> -C tools -W make_opcodes.mll -W dumpobj.ml dumpobj`. The two `-W`
operands force regeneration of the opcode input and recompilation of the
disassembler without recursively forcing the retained compiler-interface
graph. Do not use global `-B` for this target: `tools/.depend` names compiler
CMIs reached through `VPATH`, so `-B` would rebuild those unrelated sibling
interfaces in dependency-list order and can transiently mix incompatible CMI
assumptions. This is the Plan 9 `dumpobj$(EXE)` target actually defined in
`tools/Makefile`; there is no root-level `tools/dumpobj` target to infer. Do
not substitute a host-built tool or object. Preserve its complete build
command and log, then invoke the newly built `tools/dumpobj` under the
recorded new runtime against that freshly built
`otherlibs/plan9/plan9_fd.cmo`.

Record the disassembly command, runtime, tool path/size/content hash, object
path/size/content hash, exit status, and complete output. Keep the logs,
output, and all analysis evidence outside the source tree. The ordinary
other-library `-g` build must provide source-location events sufficient to map
the reviewed functions; stop if it does not.

Using that exact disassembly and the reviewed source, identify and record the
instruction spans for:

- capability publication from normal primitive-pipe return through both cell
  publications and return of the preallocated success;
- every authoritative post-allocation state/token check through its state
  installation or return of the preallocated attachment success;
- public-close and owner-close attempt activation and state installation
  before the backend call;
- normal backend-close return through allocation-free public or owner
  terminalization before error mapping;
- exception-path attempt deactivation followed by `RERAISE`; and
- the complete `commit_attach` check and transition.

Treat each item as a control-flow region containing every reachable path
between its named entry and exit boundaries, not merely as visually
contiguous lines in the disassembly. Record the boundary PCs, every reachable
instruction and fallthrough, and every branch or switch target. Follow each
target through the required publication, state installation, terminalization,
authorized no-change return, or exception rethrow. No edge may leave the
reviewed region early, bypass the required state effect, or reach an
unrecorded target.

Prove across that complete control flow that each protected region contains
no allocation, polling, callback-capable instruction, or unreviewed call. The
expected backend invocation may occur only after the active close state is
installed; error mapping may occur only after terminalization. Both close
handlers must use `RERAISE` for the same caught exception value after
deactivation. A failed, incomplete, unmappable, path-incomplete, or
contradictory instruction audit stops qualification and follows the
authoritative retry rule.

Create a fresh isolated directory on native storage outside the source and
build trees. Before compilation it contains only byte-identical copies of the
freshly built `plan9.cma`, the verified public `plan9.cmi`, and this exact
accepted Phase 1.1 minimal public consumer source:

```ocaml
let () =
  ignore Plan9.wait_succeeded;
  print_endline "plan9 staging consumer: passed"
```

Record the source and staged paths, decimal sizes, and content hashes for the
archive and CMI, require each staged copy to match its source artifact, and
record the consumer-source hash. Inventory the isolated directory before
compilation and prove that `plan9_types.cmi`, `plan9_primitive.cmi`,
`plan9_process.cmi`, `plan9_fd.cmi`, every private `.cmo`, and every C payload
are absent. Compile there with the ordinary source-tree bytecode compiler in
the shape `ocamlc -I . plan9.cma consumer.ml -o consumer`, with no include path
back to `otherlibs/plan9`, `-custom`, `-use-runtime`, C compiler, linker,
wrapper compiler, or additional archive. Run the result under
`$(NEW_OCAMLRUN)`, which is required because the force-linked archive now
imports the accepted descriptor pipe and close primitives. Re-hash the staged
`plan9.cma` and `plan9.cmi` afterward and require that both remain
byte-for-byte identical to their freshly built source artifacts. Keep the
consumer and all inventories and logs outside the source-set manifest, and
record the isolated directory's retained or removed postcondition.

Then run the complete additive fake/native lifecycle executable, all Phase 0
focused tests, and all existing Plan 9 regressions with the exact lanes above.
Audit private CMI installation selection, ML-only archive content and unit
order, exact primitive-import delta, test runtime lanes, primitive uniqueness,
descriptor inventories, process and temporary-file postconditions, and
cleanup. Do not run the separately authorized timing-sensitive interruption
target.

### Authoritative retry rule for steps 4-6

Native dependency generation, compilation, tests, and audits are evidence
producers, not source-editing lanes. Apart from generated build products and
the dependency target's `.depend`, do not edit implementation, Makefile, or
test source in the guest.

If a native step exposes a defect:

1. preserve the exact command, output, guest path, and relevant artifact or
   postcondition;
2. make every corrective source edit only in the authoritative Windows
   checkout without changing predecessor test sources;
3. invalidate the prior pre-generation and post-generation manifests, guest
   source copy, returned dependency evidence, and final host review;
4. repeat the complete host review and transfer the corrected exact source to
   the same confirmed native destination; and
5. after any `.ml`, `.mli`, source-list, or dependency-relevant Makefile
   change, repeat native dependency generation, authoritative return,
   byte-for-byte comparison, and final host review before resuming
   qualification.

Even when a permitted correction cannot affect ML dependencies, repeat the
host diff, source manifest, exact transfer, and final host review before
resuming. Never patch guest source to make a failure disappear, hand-edit
generated dependency output, or continue from stale review evidence. If the
confirmed destination cannot be reused safely, return to explicit VM
confirmation before selecting another tree.

### 7. Report and stop

Do not add public byte I/O, publish `Plan9.Fd`, begin `Plan9.In_channel`,
change accepted runtime primitives, migrate process code, or begin capture.
Commit and push only if the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact cell, capability-slot, lifecycle, and token representations;
- allocation-safe pipe publication proof;
- public close and owner close result/exception matrices;
- attachment preparation, competing-token, close-in-flight rejection, and
  complete `commit_attach` boolean matrix and commit proof;
- public-close, owner-close, and preparation post-allocation linearization
  proof;
- exact active/inactive public-close and owner-close attempt traces, including
  callback exception, physical exception identity, ordinary `RERAISE`,
  authorization during uncertainty, and later retry;
- both review-baseline identities and the authoritative and cumulative diff
  inventories at the pre-VM and final-host gates;
- scoped fresh-build commands, complete logs, and provenance for
  `plan9_fd.cmi`, `plan9_fd.cmo`, the public `plan9.cmi`, `plan9.cma`, the
  lifecycle executable, and the repository-built `dumpobj`;
- byte identity of the rebuilt public `plan9.cmi` with the accepted Phase 1.1
  artifact, plus the isolated staged-consumer inventory, commands, runtime,
  artifact identities, result, and postcondition;
- native `dumpobj` tool/object identities, complete output location, mapped
  critical control-flow regions and boundary PCs, complete branch/switch
  coverage, and allocation/callback/safe-point audit;
- fake-backend call traces, including the successful forced-GC pipe
  publication and raising pipe callback, and native descriptor-inventory
  results;
- proof that invalid public/token paths perform no native work;
- exact production pipe/close binding shapes, primitive-import delta, and test
  runtime lanes;
- native `.depend` generation provenance, returned-file identity, final host
  review, pre/post-generation manifest delta and final host/guest identity,
  and every authoritative retry cycle;
- transfer-set basis, the exact three additions and no deletion, complete
  untracked/ignored inventories, exclusions, and retained-artifact inventory;
- exact dependency graph, archive order, and private-CMI packaging evidence;
- confirmation that predecessor tests, public files, and runtime sources are
  unchanged; and
- exactly one final recommendation:
  - **Phase 1.2 accepted; ready to checkpoint and review Phase 1.3**;
  - **implementation ready but native qualification still required**; or
  - **Phase 1.2 blocked or rejected**, with the exact reason.

## Strict exclusions

This handoff does not authorize public `Plan9.Fd`, production descriptor read
or write bindings, read or write wrappers, `Plan9.In_channel`, installed
documentation changes, new runtime primitives or native ABI changes, process
migration, capture, timing-sensitive interruption injection, installation, VM
snapshots, merge, release publication, or Caml9 changes.
