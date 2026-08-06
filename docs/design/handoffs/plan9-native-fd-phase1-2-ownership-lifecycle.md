# Phase 1.2 `Plan9.Fd` ownership lifecycle handoff

Status: draft execution handoff for review; starts only after accepted Phase
1.1

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
`codex/plan9-native-io-foundation`. The executing request must name the exact
accepted Phase 1.1 implementation checkpoint and its reviewed documentation
predecessor. Verify a clean index and worktree, expected branch and remote
tracking state, and no unrelated history.

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
- explicit detached, publicly closed, attached, and owner-closed states;
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

Structure the module around an internal backend signature and functor so the
ownership state machine can be tested without native syscalls:

```ocaml
module type Primitive = sig
  type capability

  val pipe :
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  val close :
    capability -> (unit, Plan9_types.native_failure) result
end

module Make (_ : Primitive) : sig
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
```

The new production bindings retain the accepted logical shapes and exact C
symbols:

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

They accept or return capabilities only and never expose descriptor integers.
Do not add production read or write bindings yet. The production `Plan9_fd`
module instantiates the functor with these bindings and exposes the same
private interface from its uninstalled CMI. Exact private ML naming may be
improved during review, but C symbols, arities, result shapes, public
ownership, token authorization, allocation, and native-call behavior must
remain unchanged.

## Ownership cell contract

### Shared aliases

Copying a `t` aliases the same ML cell and capability. It does not allocate a
new owner and never invokes native `dup`. Every alias observes the same
lifecycle transition.

The cell distinguishes at least these semantic states:

1. unpublished, used only while a preallocated pipe result is private to
   `pipe`;
2. open and detached, permitting public ownership operations;
3. publicly closed, permitting idempotent public close only;
4. attached to one exact private token, rejecting every public operation;
5. owner-closed after attachment, rejecting public operations while making
   private owner close idempotent.

The implementation may encode those states compactly, but must not collapse
publicly closed and owner-closed if doing so would allow a retained public
alias to regain close authority after attachment.

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

- An open, detached cell invokes the accepted capability close exactly once.
- After any normal primitive return, whether `Ok` or `Error`, the public cell
  is terminally publicly closed before the wrapper returns that result.
- A capability close failure preserves its exact native message and mapped
  kind. The cell remains terminal because the descriptor is uncertain.
- Repeated close through any public alias of a publicly closed cell returns
  `Ok ()` without another primitive call.
- An attached or owner-closed cell returns structured `Invalid_argument`
  without a primitive call; attachment permanently revoked public close
  authority.
- A callback exception raised by pending-action processing before the
  primitive reaches its close commit point may propagate with the cell still
  open so the caller can retry. The accepted capability remains the final
  authority against unsafe reuse if failure-result allocation raises after
  native terminalization.

Do not catch arbitrary exceptions merely to force the ML cell closed: before
the primitive commit point an exception can mean the descriptor was never
closed. Preserve the accepted primitive distinction.

## Private attachment protocol

Attachment is internal ownership transfer for a future native channel, not a
public API. It performs no native syscall and never changes the descriptor.

`prepare_attach`:

- accepts only an open, detached cell;
- allocates an opaque token referring to that exact cell;
- preallocates any owner marker/state needed by commit;
- returns the token without changing the cell; and
- returns structured `Invalid_argument` for closed or already attached cells
  without native work.

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
- returns `false` without changing state for a stale, competing, closed, or
  already committed token.

The token, any attached-state marker, and any owner slot must therefore be
allocated and GC-safe before commit. Owner operations authorize by exact token
identity, not merely by observing a generic attached state. A losing prepared
token can never operate on or close the descriptor.

`Private.close` invokes the native close only for the exact committed token.
It transitions to owner-closed after any normal primitive result and is
idempotent for that same token. An uncommitted, stale, or losing token returns
structured `Invalid_argument` without native work. Retained public aliases
remain revoked before and after owner close.

Phase 2 will allocate its channel and enclosing success result after
preparation but before commit, then return the preallocated success only if
commit succeeds. If any allocation fails before commit or commit returns
false, the original detached descriptor remains operational unless another
alias independently closed it. Phase 1.2 proves the token protocol but does
not allocate or expose a channel.

## Error and threat boundaries

High-level lifecycle validation errors use exact operation names
`Plan9.Fd.pipe`, `Plan9.Fd.close`, and private test-only attachment operation
names, `Invalid_argument`, and stable explanatory messages. Native failures
map through `Plan9_types.error_of_native` and retain the captured message.

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
- primitive pipe failure returns the mapped `Plan9.Fd.pipe` error and no owner;
- aliases share close state and exactly one primitive close occurs;
- repeated public close is idempotent without a backend call;
- a backend close error terminalizes the public cell and is not retried;
- prepare does not revoke public ownership before commit;
- close between prepare and commit makes commit fail;
- of two competing tokens, exactly one commits and only it is authorized;
- after commit, public close and further attachment fail without backend work;
- private close through the committed token calls the backend once and is
  idempotent thereafter;
- stale, losing, and uncommitted tokens cannot close;
- retained public aliases remain rejected after owner close; and
- forced minor and major GC between preparation, commit, and close preserves
  cell/token identity and capability reachability.

Where practical, the fake backend should execute an injected callback during
pipe or close to model the state observations possible around primitive
pending-action processing. Do not add a production fault switch.

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
- exact cell transitions and authorization checks;
- public and owner close behavior on success, native failure, callback
  exception, and repeated calls;
- absence of native calls on invalid lifecycle/token paths;
- absence of finalizers, raw integers, ordinary channels, APE descriptor
  registration, `dup`, or foreign adoption;
- the functor boundary and production instantiation;
- exact addition of only capability pipe/close primitive imports to the
  production archive;
- archive order and uninstalled `plan9_fd.cmi`;
- every executable linked with force-linked `plan9.cma` now runs with
  `$(NEW_OCAMLRUN)`, including the environment test, because the archive now
  imports Phase 0 descriptor primitives absent from the bootstrap runtime;
- the pure process-state executable still links only `plan9_types.cmo` and
  `plan9_process.cmo` and continues to run with bootstrap `$(OCAMLRUN)`; and
- unchanged `plan9.mli`, README, installed reference, runtime C, raw assembly,
  and primitive inventory.

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

Record Git state, the accepted Phase 1.1 checkpoint, exact private module
interfaces, primitive shapes, allocation conventions, runtime pending-action
behavior, and Makefile/dependency state. Implement only the production
capability pipe/close bindings, ownership, pipe, close, attachment, and
focused lifecycle tests.

### 2. Source review before VM work

Run safe host-side checks and inspect the complete diff from accepted Phase
1.1. Report the cell representation, publication proof, state machine, close
exception boundary, token protocol, backend call counts, and packaging state.
Stop before VM access.

### 3. Explicit VM confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, and WHPX profile. Use the repository VM and
native-build skills. Transfer without `.git` through `/mnt/term`, copy onto
native storage, and never build on `/mnt/term`.

### 4. Native qualification

Record guest, source-tree, compiler, GNU Make, and release identity. Build the
standard runtime and Plan 9 library, run the fake-backend lifecycle test, the
production native lifecycle test, all Phase 0 focused tests, and all existing
Plan 9 regressions. Audit private CMI installation selection, ML-only archive
content, exact primitive-import delta, test runtime lanes, primitive
uniqueness, descriptor inventories, and cleanup. Do not run the separately
authorized timing-sensitive interruption target.

### 5. Report and stop

Do not add public byte I/O, publish `Plan9.Fd`, begin `Plan9.In_channel`,
change accepted runtime primitives, migrate process code, or begin capture.
Commit and push only if the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact cell, capability-slot, lifecycle, and token representations;
- allocation-safe pipe publication proof;
- public close and owner close result/exception matrices;
- attachment preparation, competing-token, and commit proof;
- fake-backend call traces and native descriptor-inventory results;
- proof that invalid public/token paths perform no native work;
- exact production pipe/close binding shapes, primitive-import delta, and test
  runtime lanes;
- archive and private-CMI packaging evidence;
- confirmation that public files and runtime sources are unchanged; and
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
