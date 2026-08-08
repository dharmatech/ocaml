# Phase 2.1 `Plan9.In_channel` ownership and buffered input handoff

Status: proposed focused handoff for review; implementation has not begun

Reviewed Phase 2 documentation checkpoint: pending final documentation-content
commit and follow-up checkpoint-recording commit.

## Authority and required reading

Read completely before implementation:

- `C:\Users\dharm\src\ocaml\AGENTS.md`;
- `C:\Users\dharm\src\ocaml\README.md`;
- `C:\Users\dharm\src\ocaml\build-aux\plan9\README.md`;
- `C:\Users\dharm\src\ocaml\docs\design\plan9-native-io-foundation.md`;
- `C:\Users\dharm\src\ocaml\docs\design\handoffs\plan9-native-in-channel-phase2.md`;
- the accepted Phase 1.2 ownership-lifecycle handoff, especially its private
  attachment protocol; and
- the accepted Phase 1.3 byte-I/O handoff, especially attachment-owner I/O,
  one-transfer policy, errors, and final qualification boundary.

This document delegates only Phase 2.1. Later Phase 2 handoffs are context,
not authority to implement their APIs. If an accepted source or document
conflicts with this handoff, stop and report the exact conflict.

## Start gate

The implementation task must begin only after the complete Phase 2 handoff set
is reviewed and its exact documentation checkpoint is recorded. Then verify:

- branch `codex/plan9-native-io-foundation` is checked out;
- `HEAD` contains accepted Phase 1 at
  `ee8f799bba40f2ed8caa57a4ef7e91726f2f4283` and the documentation/status
  base `50f022919198c24ca4e5697b79b1cd52411da83e`;
- the complete reviewed Phase 2 documentation is present;
- the worktree and index are clean; and
- no unrelated local or remote-tracking discrepancy is present.

Record `git status --short --branch`, `git rev-parse HEAD`, the local branch,
its upstream, and the relevant recent log. If anything differs, stop. Do not
clean, stash, reset, switch branches, or incorporate another task's changes.

## Accepted predecessor facts

The exact predecessor is the accepted Phase 1 implementation and its later
documentation clarifications. In particular:

- `Plan9_fd.t` contains one shared public/attached ownership state;
- `Plan9_fd.Private.prepare_attach` allocates a token and all commit state but
  does not reserve or mutate the cell;
- `Plan9_fd.Private.commit_attach` is allocation-free, rechecks open-detached
  state, commits at most one token, and returns an immediate `bool`;
- only the exact committed token may use `Private.read` or `Private.close`;
- `Private.read` validates its caller buffer, requests at most the private
  accepted count, preserves positive short reads, returns zero on the observed
  lower EOF, never retries interruption, and leaves its destination unchanged
  on error;
- `Private.close` terminalizes ownership after any normal primitive result,
  is idempotent after terminal close, and retains an inactive retry state only
  if the backend raised before its normal result; and
- public aliases never regain authority after attachment.

Do not change `Plan9_fd`, the native capability ABI, primitive staging,
blocking-section discipline, raw syscall objects, or runtime C code unless new
evidence first causes an explicit revision of the owning accepted design.

## Delegated outcome

Add one uninstalled ML module, `Plan9_in_channel`, with the internal Phase 2.1
surface:

```ocaml
module type Descriptor = sig
  type t
  type attachment

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val read :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

module type S = sig
  type fd
  type t

  val of_fd : fd -> (t, Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result
  val input :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
end

module Make (Fd : Descriptor) : S with type fd = Fd.t

include S with type fd = Plan9_fd.t
```

Equivalent destructive type-substitution syntax is allowed if required by
OCaml 4.14, but the source must preserve the same abstraction and fakeable
dependency boundary. The production inclusion instantiates exactly
`Plan9_fd`; the functor is private and exists for deterministic tests.

Every `Descriptor` instantiation inherits the accepted semantic attachment
contract, not merely the types above. In particular, `commit_attach` performs
one final state/token recheck, returns exactly one immediate `bool`, and does
not deliberately allocate, poll, process pending actions, invoke callbacks,
perform native work, or raise an OCaml exception. The Phase 2.1 caller supplies
the additional heap-age precondition below that makes the production
`Plan9_fd.commit_attach` field write avoid write-barrier allocation paths; the
prepared attached-state candidate is immutable after preparation. A direct
adversarial fixture may force the normal `false` result, but it must otherwise
honor this commit contract; a fixture that raises before or after a commit is
outside the controlled boundary because the channel cannot safely distinguish
those cases or recover authority after a hidden transition.

Do not add `Plan9.In_channel` to `plan9.mli` or `plan9.ml` in this subphase.
The new implementation enters the ML-only archive only so later checkpoints
can build and test it through its uninstalled interface.

## Authorized source boundary

This subphase may add or update only the Phase 2.1-relevant paths:

- new `otherlibs/plan9/plan9_in_channel.mli`;
- new `otherlibs/plan9/plan9_in_channel.ml`;
- `otherlibs/plan9/Makefile` for archive order and focused tests;
- generated `otherlibs/plan9/.depend`, only through the documented native
  dependency-generation gate and authoritative return;
- new `otherlibs/plan9/tests/in_channel_lifecycle_test.ml`; and
- new `otherlibs/plan9/tests/in_channel_io_test.ml`.

No public documentation, umbrella source, primitive source, runtime source,
or existing test source should require a semantic edit. A generated or build
file not named above requires source evidence and user review before inclusion.

## Allocation-safe ownership transfer

`Plan9_in_channel` defines one unit-scoped retained binding for `Ok 0` and one
for `Ok ()`, outside `Make`. Every `Make` application and the production
inclusion share those bindings. Both are immutable block-constructor
applications with constant arguments and must lower to structured block
literals in executable global data rather than functor allocations. OCaml
permits identical immutable constants to be shared, so no contract requires
the two typed bindings to be physically distinct from one another. Repeated
authorized zero-length inputs must nevertheless return the exact retained zero
binding by physical identity, and repeated terminal closes must return the
exact retained unit binding by physical identity. The retained value or values
are rooted by executable global data, are never mutated or stored by a
protected field mutation, and are available before descriptor or channel work
begins. Target qualification must prove the actual structured-literal/global
provenance instead of claiming allocation during functor application or unit
initialization.

`of_fd` uses operation name `Plan9.In_channel.of_fd` and follows this exact
sequence:

1. Call `Fd.Private.prepare_attach` for the supplied descriptor.
2. If preparation fails, return an `Invalid_argument` under the public
   `Plan9.In_channel.of_fd` operation, preserving the accepted message
   `descriptor is not open and detached` and exposing no private operation
   name.
3. After successful preparation, allocate and initialize the fixed private
   scratch buffer, complete channel record with immediate lifecycle and cursor
   fields, the channel's single reusable close-attempt record with immediate
   active and terminal fields, the inner commit-lost `Plan9_types.error`
   record and its complete enclosing `Error` result, and the enclosing
   `Ok channel` result. Initialize the lifecycle tag as stably open and the
   close attempt as inactive and nonterminal.
4. Initialize every scanned field to a GC-safe value before any later
   allocation.
5. After all success-side allocation and initialization, keep the token,
   channel, enclosing success, complete lost-commit result, and every reachable
   candidate rooted and call exactly one saturated `Gc.minor ()`. Because
   `stdlib/gc.mli` declares
   `minor` as an external primitive, the target caller must compile this
   directly to `C_CALL1 caml_gc_minor`, with no ML wrapper `APPLY`, caller-side
   stack check, or pending-action boundary before primitive entry. Every
   candidate remains rooted across the direct C call. Inside
   `caml_gc_minor`, the requested minor collection promotes every live young
   candidate before signal, memprof, or finalizer callbacks run. The primitive
   may then process pending actions, invoke callbacks, or raise; all of that
   occurs before the lower commit's final state/token recheck.
6. After successful stabilization, perform no further channel-owned
   allocation and never replace or mutate a promoted commit candidate. Call
   `commit_attach`; call setup may stack-check, reallocate the bytecode stack,
   process a pending action, invoke a callback, or raise before entering the
   lower function. A callback may allocate unrelated objects, but it cannot
   make a promoted candidate young. On normal entry, the lower internal final
   recheck must still immediately dominate its state write.
7. If commit returns `true`, return the preallocated success immediately with
   no allocation, callback, safe point, or other fallible work.
8. If commit returns `false`, immediately return the complete preallocated
   enclosing `Error` result whose `Plan9.In_channel.of_fd`
   `Invalid_argument` error has message
   `descriptor is not open and detached`. Perform no allocation, callback,
   safe point, pending-action processing, or other fallible work after the
   lower `false` result; the failed channel does not escape.

An exception escaping `Fd.Private.prepare_attach` is not a normal preparation
failure and is not converted to `Plan9.error`. Propagate the physically
identical exception unchanged. At that point `of_fd` owns no returned token:
it performs no commit or cleanup close and lets no channel escape. The shared
descriptor cell retains the exact state established by the lower preparation
path and any callback it ran, without a stale overwrite by the channel layer.

If any allocation, initialization, direct `Gc.minor ()` stabilization path,
or `commit_attach` application setup before lower-function
entry raises after successful preparation, `of_fd` performs no attachment
commit, calls neither public nor private close, and lets no channel escape.
The uncommitted token owns nothing and must not be used for cleanup. Propagate
the physically identical final exception value that escapes the runtime into
the channel code. For a C/runtime exception path, this identity is anchored to
the value ultimately selected after the pending-action passes actually
executed before transfer to the ML handler, not necessarily to the first
exception raised by an earlier callback. Pending work may remain armed; do not
claim that the runtime drained its pending-action queue. The channel must
neither wrap nor replace the selected value. Transparent propagation
without a handler is acceptable and is preferred when no local state requires
restoration; if a handler is present for a structural reason, it must use
ordinary `RERAISE`. If no competing callback acted, the original descriptor
remains open and detached; if a callback or finalizer did act, the shared cell
retains that exact competing state without stale overwrite, and any completed
underlying I/O effect is not rolled back.

Preparation does not reserve the descriptor. An allocation callback may use a
still-authorized public alias for a zero-length or positive read or write,
close the public alias, or commit a competing token before this channel
commits, including during explicit precommit stabilization or call setup. A
completed public read or write restores the accepted `Open_detached` state, so
this channel's later commit may still succeed even though the underlying input
or output changed. A failed `of_fd` therefore does not promise that the
caller's descriptor remains operational; the shared cell retains the exact
state established by the competing actor. A successful result linearizes
exclusive channel ownership only at the final successful commit: it means this
channel's exact token owns the cell and all retained public aliases are then
permanently revoked, but it does not claim that no public I/O completed between
preparation and commit.

The private scratch capacity is exactly 4096 bytes for this initial layer,
matching one accepted lower `Fd` request without exposing a new public numeric
contract. It is allocated once per channel and reused. Changing that capacity
later is an internal performance decision only if all semantic tests remain
valid.

## Channel state and operation serialization

The channel owns explicit ML state sufficient to distinguish:

- stable open;
- one active input-family operation;
- active close;
- exception-left inactive close, retryable only by this channel; and
- terminal closed.

The representation uses the channel record and single reusable channel-owned
close-attempt record preallocated by `of_fd` before attachment commit. The
channel lifecycle tag, channel close-attempt active and terminal fields, unread
cursors, and every other GC-scanned field mutated in a protected region must
contain only immediate values: integers, booleans, or nullary constructors.
Retain the attachment token and any other block-valued stable data in separate
scanned fields that are initialized before commit and never mutated in a
protected region. These representation constraints apply in addition to the
following rules:

- every public input-family operation validates its pure arguments first;
- immediately before changing open to active, it rechecks stable open state;
- when an operation will enter active input, a successful final open-state
  recheck is followed immediately by allocation-free active-state
  installation, with no callback, safe point, or pending-action processing
  between them;
- active state covers the entire high-level operation, including allocations,
  buffered copying, delimiter scans in later phases, and every lower read;
- a reentrant input-family operation whose pure arguments are valid while any
  input operation is active returns `Invalid_argument`, message
  `input channel operation is already in progress`, under the reentrant
  operation, without a lower read or buffer mutation;
- reentrant close during active input returns the same in-progress message
  under `Plan9.In_channel.close`, without lower close;
- an input-family operation whose pure arguments are valid during active or
  inactive close returns `Invalid_argument`, message
  `input channel close is already in progress`, without lower read;
- an input-family operation whose pure arguments are valid after terminal
  close returns `Invalid_argument`, message `input channel is closed`, without
  lower read;
- every normal result from an invocation that successfully installed active
  input restores stable open before publication; and
- every arbitrary exception escaping an invocation that successfully
  installed active input restores stable open before re-raising the exact
  caught exception through ordinary `RERAISE`, with no wrapping or stale-state
  overwrite.

An invocation that did not install active input owns no restoration and
performs no lifecycle, close-attempt, or cursor write. A range or lifecycle
error describes the condition observed at that invocation's decision point.
If constructing the error allocates and a pending callback changes the channel
state, the callback-selected state wins: neither normal publication of the
prepared rejection nor an exception escaping its construction may restore or
overwrite that state. In particular, a rejected reentrant operation must never
restore stable open and erase the outer operation's guard.

Pure-argument precedence is absolute. An invalid input range returns the exact
range error before consulting active, closing, or terminal channel state,
including during a reentrant call and after close. The lifecycle results above
apply only after the invoked operation's pure arguments are valid.

The active guard is necessary even without systhreads. The lower `Fd` path
processes pending actions before native work, and an OCaml callback may
re-enter this channel. The channel guard protects buffer cursors and aggregate
state across the entire logical operation; the accepted `Fd` owner-I/O state
continues to protect the descriptor during each individual lower call.

Unsafe `Obj` forging or representation mutation of a channel is outside the
abstract ML contract. Do not add a registry or native channel capability to
defend against it.

## Buffer invariants and refill

The reusable scratch buffer has two cursors satisfying:

```text
0 <= unread_start <= unread_end <= Bytes.length scratch
```

Bytes in `[unread_start, unread_end)` are unread channel data. When the range
is empty, normalize both cursors to zero before a refill. A refill:

- runs only while the channel's high-level operation is active;
- calls `Fd.Private.read token scratch ~pos:0 ~len:(Bytes.length scratch)` at
  most once for that refill;
- maps every lower error to the invoking `Plan9.In_channel` operation while
  preserving kind and exact message;
- does not retry interruption or any other failure;
- accepts zero as the EOF observed by that call;
- accepts a valid positive short count and sets the unread range exactly to
  `[0, count)`; and
- defensively rejects a negative count or count larger than the scratch length
  as `Protocol_error`, message
  `invalid input buffer fill result: buffer length {buffer_length}, returned count {count}`,
  without using the count as an index or copy length, leaves the unread cursors
  normalized to the empty range `[0, 0)`, and treats every byte the adversarial
  backend may have placed in scratch as unreadable garbage.

The production `Plan9_fd` predecessor already validates its result. The extra
check protects the private functor boundary and keeps a malformed fake or
future dependency from corrupting channel memory.

Do not cache EOF permanently. A later call with an empty buffer may call the
lower descriptor again. This avoids prematurely freezing a future regular-file
channel if data is appended after an earlier zero read. Pipe capture still
observes stable EOF when its peer has closed.

## `input` contract

`input channel destination ~pos ~len` uses operation
`Plan9.In_channel.input`.

Range validity is exactly:

```text
pos >= 0
len >= 0
pos <= Bytes.length destination
len <= Bytes.length destination - pos
```

Use subtraction rather than `pos + len`. Invalid ranges return
`Invalid_argument` with exact message
`invalid byte range: buffer length {buffer_length}, position {pos}, length {len}`
before lifecycle state, buffer inspection, or lower work.

For a valid range:

- zero length still checks that the channel is stably open, then returns the
  unit-scoped retained `Ok 0` binding without buffer movement or lower read;
  the successful final stable-open check is followed immediately by that
  retained return with no allocation, callback, safe point, or pending-action
  processing;
- if unread bytes are buffered, copy `min len available` bytes, advance only
  the cursor by that count, and return without a lower read;
- if the buffer is empty and length is positive, perform exactly one refill;
- lower zero returns `Ok 0` and leaves the caller destination unchanged;
- lower positive progress copies at most the requested length, retains every
  surplus byte in the channel buffer, and modifies exactly the returned
  destination prefix; and
- lower error returns once, leaves the destination unchanged, and does not
  retry, although an interrupted native read may have consumed an unknown
  amount of underlying input as documented by Phase 1.

One `input` call never loops merely to fill the caller's entire range. This
avoids blocking or returning an error after it already has positive buffered
progress. Higher materializing functions added later own their explicit loops.

Construct every normal result that requires allocation while the channel is
still active and inside the input operation's exception handler. This includes
mapped lower errors and synthesized protocol errors, not only successful
counts. Allocate every nonzero successful `Ok count` before advancing the
unread cursor or copying into the caller buffer. Complete all lower work,
cursor description, result construction, and preparation of the final normal
outcome inside that handler while active state is visible. On the normal path,
leave the handler through its bytecode `POPTRAP` while the channel is still
active and before any caller-destination or unread-consumption mutation. Keep
the prepared outcome and every live channel/copy value rooted across the
handler-exit pending-action path.

If that `POPTRAP` processes a pending callback and the callback raises, the
handler restores stable open and uses ordinary `RERAISE`. A successful refill
must already be represented by the unread cursors at this boundary, so every
newly read byte remains buffered after that exceptional restoration. A
reentrant callback at the boundary observes active input and receives the
ordinary in-progress rejection.

Only after `POPTRAP` has completed normally may the code copy exactly the
returned prefix into the caller destination, advance the unread cursor by
exactly that count, restore stable open, and immediately return the already
constructed result, in that order. From the first caller-destination or
unread-consumption mutation through result publication, perform no allocation,
polling, handler exit, pending-action processing, callback-capable operation,
or other fallible work; the validated direct primitive byte copy is the only
operation in that interval besides the required cursor and state mutations.

After a successful refill, first describe the complete validated fill with
the channel cursors, then allocate that call's success while the channel
remains active; if allocation or the handler-exit pending-action pass raises,
stable state is restored with every newly read byte still buffered for a later
call. For every other normal active outcome, including lower EOF, a mapped
lower error, or a malformed-count protocol error, make the final retained or
newly constructed result available before the same active-state `POPTRAP`.
After normal handler exit, restore stable open and publish that result
immediately with no intervening allocation, callback, safe point, pending-
action processing, or fallible work. The retained zero success requires no
allocation. No acceptance claim is made that arbitrary `Out_of_memory` is
converted to `Plan9.error`.

Declare the existing built-in byte-copy primitive privately in
`plan9_in_channel.ml`, with this reviewed shape and no corresponding interface
declaration:

```ocaml
external blit_bytes_noalloc :
  bytes -> int -> bytes -> int -> int -> unit
  = "caml_blit_bytes" [@@noalloc]
```

This is a private ML reference to an existing runtime primitive, not a new
primitive definition, generated-table entry, runtime object, C object, or
installed interface. Use it only for a positive copy after the channel has
validated every source and destination bound. The source and target-artifact
audit must prove that the saturated local external call compiles directly to
`C_CALL5 caml_blit_bytes`, with no cross-unit wrapper `APPLY`, stack check, or
pending-action boundary, and reaches the linked implementation in
`runtime/str.c`, whose complete path performs only the bounded `memmove` and
returns `unit`. The channel's cursor and range invariants must dominate every
primitive argument, and the selected target objects and symbol must correspond
to the reviewed sources. A wrapper call, different opcode, intervening poll,
or different copy helper stops qualification unless separately reviewed
evidence proves the same direct-call, runtime-object, bounds-domination,
no-allocation, no-polling, no-pending-action, no-callback, and nonraising
successful-path properties.

## Deterministic close

`close channel` uses operation `Plan9.In_channel.close`.

From stable open:

- reuse the channel-owned close-attempt record preallocated by `of_fd` and its
  immediate active and terminal fields; the channel layer performs no close-
  state allocation;
- recheck stable open immediately before changing the retained attempt to
  active and changing the channel's immediate lifecycle tag to closing;
- follow that successful final recheck immediately with the attempt/state
  mutations, with no allocation, callback, safe point, or pending-action
  processing in between;
- if a defensive final recheck does not observe stable open, do not install
  the candidate state or overwrite the winner; redispatch the exact current
  state through the ordinary active, inactive, or terminal close behavior;
- call `Fd.Private.close` exactly once through the committed token inside the
  close exception handler;
- on any normal `Ok` or `Error`, retain that lower result and immediately,
  allocation-free, mark the close attempt terminal and inactive, transition
  the channel to terminal closed, and discard unread cursors before leaving
  the handler; keep the retained lower result and channel rooted through the
  handler-exit pending-action path;
- remap a lower error's operation to `Plan9.In_channel.close` while preserving
  kind and exact native message.

The channel-layer no-state-allocation rule does not prohibit the accepted
lower descriptor implementation from allocating its distinct descriptor-owner
close-attempt record and `Owner_closing` value on the first
`Fd.Private.close` call from `Attached`. Those lower allocations precede the
descriptor layer's own final state/token recheck. They are permitted only
after the channel's active-close state is visible and its exception handler is
installed, and they remain outside both the channel's final stable-open-
recheck-to-active-install region and the later normal-lower-return-to-channel-
terminalization suffix. Descriptor terminalization is not the start of that
second suffix: after setting its owner-close attempt terminal, the accepted
lower implementation may still allocate while constructing a mapped native-
error result, or raise from that construction, before it returns to the
channel. Those operations remain covered by the channel handler while the
channel-owned attempt's terminal flag is false. They do not relax either
allocation-free channel region and must not be identified as channel-owned
state.

The close exception handler syntactically covers the lower call, the immediate
channel terminalization writes, and the normal handler-exit `POPTRAP`. After a
normal lower `Ok` or `Error`, perform all channel terminalization writes while
the handler is still installed and before that `POPTRAP`. A pending callback
processed by the `POPTRAP` therefore observes the terminal channel. Keep lower-
error mapping and all other wrapper result work outside the handler and after
normal `POPTRAP`.

The handler distinguishes its two exception boundaries using the retained
attempt's immediate terminal flag. If the flag is false, the exception escaped
before normal lower return and therefore before channel terminalization: mark
the attempt inactive, leave the channel in exception-left inactive close, and
use ordinary `RERAISE`, even when the lower descriptor terminalized its own
state before raising, including during its later native-error construction. If
the flag is true, the lower call returned normally and the exception arose
while the handler-exit `POPTRAP` processed pending work:
preserve the attempt and channel terminal state exactly and use ordinary
`RERAISE`, without reactivation or deactivation. An exception from later
wrapper mapping likewise leaves the channel terminal and is re-raised
unchanged. No acceptance claim is made that either exception is converted to
`Plan9.error`.

During active close, reentrant close returns `Invalid_argument`, message
`input channel close is already in progress`, without nested lower work.
After terminal close, repeated close returns the unit-scoped retained
`Ok ()` immediately, without lower work, allocation, callback, safe point, or
pending-action processing.

If the lower close raises an arbitrary exception, mark the existing attempt
inactive and re-raise the physically identical exception through ordinary
`RERAISE`. Input remains rejected while close is inactive. A later `close`
through the same channel reactivates the attempt and invokes
`Fd.Private.close`; that lower call either retries an uncommitted capability
close or observes its already-terminal owner and returns idempotently. No
public `Fd.t` alias regains authority.

## Exact wrapper-error matrix

Braced fields are decimal substitutions.

| Condition | Operation | Kind | Message |
| --- | --- | --- | --- |
| failed preparation or lost commit | `Plan9.In_channel.of_fd` | `Invalid_argument` | `descriptor is not open and detached` |
| invalid input range | `Plan9.In_channel.input` | `Invalid_argument` | `invalid byte range: buffer length {buffer_length}, position {pos}, length {len}` |
| input-family operation with valid pure arguments during active input | invoked input operation | `Invalid_argument` | `input channel operation is already in progress` |
| close during active input | `Plan9.In_channel.close` | `Invalid_argument` | `input channel operation is already in progress` |
| input-family operation with valid pure arguments during active/inactive close | invoked input operation | `Invalid_argument` | `input channel close is already in progress` |
| input-family operation with valid pure arguments after terminal close | invoked input operation | `Invalid_argument` | `input channel is closed` |
| close during active close | `Plan9.In_channel.close` | `Invalid_argument` | `input channel close is already in progress` |
| malformed fill count | invoking input operation | `Protocol_error` | `invalid input buffer fill result: buffer length {buffer_length}, returned count {count}` |

Lower failures preserve kind and message but are always rebound to the
invoked channel operation. Do not leak `Plan9.Fd.Private.prepare_attach` or
`Plan9.Fd.read` as a public-facing operation.

The invalid-range row, and later invalid-bound rows, have precedence over every
input lifecycle row in this table. `close` has no pure byte-range or bound
argument and therefore enters lifecycle dispatch directly.

## Build and dependency integration

Add `plan9_in_channel.cmo` after `plan9_fd.cmo` and before
`plan9_process.cmo` in `CAMLOBJS`:

```make
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo \
  plan9_in_channel.cmo plan9_process.cmo plan9.cmo
```

`plan9_in_channel` depends on `Plan9_types` and `Plan9_fd`, never on the
`Plan9` umbrella or `Plan9_primitive`. No cycle is permitted.

The target-generated `.depend` prerequisite sets for the new unit are exactly:

```text
plan9_in_channel.cmi : plan9_types.cmi plan9_fd.cmi
plan9_in_channel.cmo : plan9_types.cmi plan9_fd.cmi plan9_in_channel.cmi
plan9_in_channel.cmx : plan9_types.cmx plan9_fd.cmx plan9_in_channel.cmi
```

The target generator remains authoritative for textual ordering and line
wrapping, but not for admitting another dependency. Every pre-existing
`.depend` stanza and prerequisite set must remain unchanged; this subphase
adds only the three source-derived stanzas above. An additional prerequisite,
missing expected prerequisite, or changed existing stanza stops review rather
than being accepted merely because it was generated.

Define these exact Makefile program variables:

```make
IN_CHANNEL_LIFECYCLE_TEST_PROGRAM=tests/in_channel_lifecycle_test$(EXE)
IN_CHANNEL_IO_TEST_PROGRAM=tests/in_channel_io_test$(EXE)
```

Include both in `ML_TEST_PROGRAMS` and let the existing
`TEST_PROGRAMS`-based cleanup inventory cover them. The ordinary `test` recipe
runs both with `$(NEW_OCAMLRUN)`. The existing pure `process_state_test`
remains the only ML test in this inventory that runs with bootstrap
`$(OCAMLRUN)`; do not change any predecessor runtime lane.

The lifecycle executable links these private objects in this exact order:

```text
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo plan9_in_channel.cmo
```

followed by `tests/in_channel_lifecycle_test.ml`. It exercises the private
functors and must use `$(NEW_OCAMLRUN)` because the production inclusions in
the linked units import the accepted descriptor primitives. The native I/O
test compiles with `-I .`, links the source-tree `plan9.cma`, and depends on the
private `plan9_in_channel.cmi` needed to compile its internal references; it
also runs with `$(NEW_OCAMLRUN)`. Neither test, private CMI, nor test object is
installed.

Make hand-written source and Makefile changes in the authoritative Windows
checkout, but never hand-edit `.depend`. Generate dependencies only on native
Plan 9 storage using the configured target compiler and documented APE/GNU
Make lane. Bring back and review only the generated `.depend` file, then prove
its source reasons. Accept it only from the exact successful dependency target
and complete validation gate below. If dependency generation changes anything
else, fails, or leaves incomplete output, stop and follow that gate's recovery
rule rather than returning or adopting the file.

The archive remains ML-only. This subphase adds no primitive definition,
generated runtime-table entry, runtime object, C object, C option, dynamic
library, or installed CMI. Its ML code deliberately reaches the existing
`caml_blit_bytes` primitive through the reviewed private direct external in
`plan9_in_channel.ml` and reaches `caml_gc_minor` through the reviewed
saturated `Gc.minor` external declared by `stdlib/gc.mli`, which the target
caller must lower directly to `C_CALL1 caml_gc_minor`.

## Required fake-backend tests

`in_channel_lifecycle_test.ml` uses two complementary private fixtures:

1. Compose `Plan9_fd.Make` with a counted fake primitive and instantiate
   `Plan9_in_channel.Make` over that accepted-shape `Fd` module. Use this path
   for real attachment, alias, owner-I/O, close, callback, and lower-error
   mapping semantics.
2. Instantiate `Plan9_in_channel.Make` over a direct or narrowly adapted
   adversarial `Descriptor` whose attachment contract remains controlled but
   whose `read` can deliberately return malformed successful counts, whose
   commit can deterministically return `false` without allocating, invoking a
   callback, or raising, and which records the physical caller scratch buffer.
   This fixture tests the channel functor boundary that `Plan9_fd.Make`
   intentionally sanitizes before returning.

Keep both fixtures in the one authorized lifecycle test source; add no
production hook or extra test file. At minimum, prove:

- successful `of_fd` commits exactly one token and revokes every public alias;
- preparation failure and an adversarially forced lost commit return the exact
  public error and do not let the failed channel escape; source review and
  target disassembly additionally prove that the lost-commit path rooted the
  complete enclosing `Error` result through stabilization and commit and
  publishes it immediately after `false` without allocation, polling,
  callback, pending-action processing, or other fallible work;
- a direct `Descriptor` `prepare_attach` implementation that raises a
  designated exception causes no commit or close, lets no channel escape,
  preserves the exact descriptor state, and is propagated with physical
  identity;
- source review and target-native disassembly prove that every channel-owned
  success-side allocation precedes the explicit `Gc.minor ()`, that all live
  commit candidates remain rooted through its direct `C_CALL1` primitive and
  pending-action path and are promoted by successful stabilization, and
  that no later channel-owned allocation or candidate replacement can make the
  production attached-state candidate young before the final commit; commit
  loss never overwrites a callback-established close or attachment state. The
  adversarial fixture must force that loss deterministically, while an actual
  callback during allocation, direct primitive stabilization, or commit
  application setup is runtime evidence only when the target provides a
  reviewed reliable mechanism;
- using the accepted-shape `Plan9_fd.Make` fixture, independently prove on
  separate descriptors that a prepared token can remain uncommitted while one
  successful positive-progress public read consumes the exact queued fake
  bytes and, separately, while one successful positive-count public write
  records the exact fake bytes; require each operation to restore
  `Open_detached` and permit the original token to commit. Map that accepted
  predecessor behavior to `of_fd`: a successful channel linearizes ownership
  at its final commit and does not roll back or deny an intervening public-I/O
  effect. Exercise each sequence through an actual precommit callback only
  when the target supplies a reviewed reliable mechanism; otherwise record
  those runtime callback schedules as unavailable and retain the mandatory
  predecessor tests plus source/static proof;
- source review proves that an exception during post-preparation channel
  allocation, direct `Gc.minor` stabilization, or pre-entry
  `commit_attach` application setup performs no commit or cleanup close and
  lets no channel escape. Where the target test runtime permits a deterministic
  allocation/finalizer callback, `Gc.minor` exception, or `commit_attach`
  application pending-action or stack-limit exception, exercise the same
  rule. Anchor physical identity to the final exception value selected by the
  runtime and caught by the ML caller, not necessarily the first callback
  exception;
- the adversarial fixture observes one physically identical scratch buffer
  reused across refills;
- invalid ranges `(-1,0)`, `(0,-1)`, `(buffer_length+1,0)`,
  `(buffer_length,1)`, `(max_int,1)`, and `(1,max_int)` return the exact error
  before that invocation consults lifecycle state or initiates lower work;
- representative invalid ranges during active input, active/inactive close,
  and terminal close return the same exact range error rather than a lifecycle
  error and initiate no lower work themselves;
- authorized `(buffer_length,0)` returns zero without buffer movement or lower
  read, returns the unit-scoped retained `Ok 0` binding by physical identity
  on repeated calls and across two `Make` instances, and contains no
  `MAKEBLOCK`, allocation, poll, or pending-action boundary, while closed and
  closing channels reject it;
- a valid zero-length reentrant `input` during active input returns the exact
  in-progress error without bypassing the guard, moving buffered data, or
  making a nested lower call;
- buffered input returns without a lower read and retains unused suffix bytes;
- an empty buffer causes exactly one lower read even when the logical request
  is larger than the scratch capacity;
- positive short reads, embedded NUL, zero EOF, and arbitrary caller offsets
  preserve exact bytes and untouched prefix/suffix regions;
- negative and oversized successful counts from the adversarial `Descriptor`
  produce the exact channel protocol error without an out-of-bounds access or
  caller mutation, leave the unread cursors empty, ignore scratch bytes written
  by the adversary, and permit the next valid refill to succeed exactly;
  separately require that malformed primitive results through `Plan9_fd.Make`
  retain the accepted lower `Plan9.Fd.read` error text when the channel rebinds
  their operation;
- lower errors retain kind/message, use `Plan9.In_channel.input`, and are not
  retried;
- repeated EOF calls may perform later lower reads and can observe later fake
  data;
- active-input callbacks attempting input, close, public `Fd` operations, or
  token operations receive their exact accepted rejection and make no nested
  lower call; every rejected invocation performs no channel lifecycle write or
  restoration through its normal error, and source/disassembly review proves
  that an exception while constructing a range or lifecycle rejection likewise
  cannot restore or overwrite the outer or any callback-selected state;
- a designated allocated exception raised by lower read restores stable
  channel and descriptor state and is re-raised with physical identity;
- source review and target-native disassembly prove that every allocated
  normal input result exists before caller-data or unread-consumption mutation;
  the input handler's normal `POPTRAP` occurs while active state is visible and
  before those mutations; a callback exception at that boundary restores
  stable state with newly read bytes retained; every prepared outcome and live
  copy value remains rooted through pending-action processing; the exact byte
  copy precedes cursor advancement; and the complete post-`POPTRAP` mutation,
  stable-restoration, and publication suffix contains no allocation, polling,
  handler exit, pending-action processing, callback-capable operation, or
  fallible work;
- the private direct copy declaration, channel call site, exact target
  bytecode, runtime object, and symbol prove a saturated local
  `C_CALL5 caml_blit_bytes` path with no wrapper `APPLY`, and channel-validated
  bounds dominate every primitive argument;
- source review and target disassembly prove that, if a designated pending-
  callback exception is processed at the input handler's `POPTRAP`, it occurs
  before caller-buffer and unread-consumption mutation, observes active input,
  restores stable state, preserves physical exception identity, and leaves
  every newly read byte represented by the cursors for the next input;
- the channel-owned close-attempt record was allocated before attachment
  commit, all of its mutable fields and every mutable lifecycle or cursor field
  contain only immediate values, every positive-input or close check that
  begins an active operation is followed immediately by allocation-free
  active-state installation, and a valid zero-length input returns its retained
  success immediately after its final stable-open check;
- production-close evidence distinguishes that retained channel attempt from
  the accepted descriptor-owner attempt and `Owner_closing` value allocated by
  the first lower close, and proves that those lower allocations occur only
  after channel active-close state and the channel exception handler are in
  place;
- close callbacks cover active close, input rejection, reentrant close,
  exception-left inactive retry using the same attempt, normal native error
  terminalization, and repeated terminal close;
- the adversarial `Descriptor` supplies two designated lower-close exception
  schedules: one raises before changing its own close state and one first
  terminalizes its own close state and then raises. In both cases the channel
  leaves its one retained attempt inactive, rejects input, re-raises the
  physically identical exception, and lets a later close reactivate that same
  attempt for exactly one additional lower call. The first retry completes the
  lower close; the second observes the lower descriptor's idempotent terminal
  result. Both retries terminalize the channel normally without restoring any
  public descriptor authority. These are lower-raise-before-return schedules,
  distinct from the normal-return/`POPTRAP` schedule below. Source and target-
  disassembly evidence must also map the production instance in which
  `Plan9_fd.Private.close` terminalizes its descriptor-owner attempt and then
  allocates while constructing a mapped native-error result: an exception from
  that construction follows the after-lower-terminal/pre-return schedule, and
  its retry observes the lower descriptor's idempotent terminal result;
- source review and target disassembly prove the third close schedule: if a
  designated pending-callback exception is processed at the close handler's
  `POPTRAP` after a normal lower result, the callback observes terminal close,
  the exact exception is re-raised, the channel and retained attempt remain
  terminal, and a repeated close returns the unit-scoped retained `Ok ()`
  binding by physical identity, including across two `Make` instances,
  without another lower call, `MAKEBLOCK`, allocation, poll, or pending-action
  boundary; and
- forced minor collection, full major collection, and compaction around live
  channels, immediate active lifecycle tags, buffered data, and close attempts
  do not lose or duplicate ownership.

For the two handler-exit `POPTRAP` schedules above, source review and exact
target disassembly are mandatory. Exercise the runtime schedule only if a
separately reviewed deterministic pure-ML target mechanism can arm pending
work after the lower path's final poll and before the particular `POPTRAP`.
If no such mechanism exists, record the runtime injection as unavailable and
the schedule as skipped with static-only evidence; that absence does not block
Phase 2.1. A fake callback invoked before lower return is useful for other
reentrancy tests but is not evidence for either `POPTRAP` schedule. Do not use
note injection, a new primitive, a test-only native hook, or a production hook
to manufacture this boundary.

Use fake callbacks for the other timing-sensitive or otherwise impossible
outcomes. Add no production fault switch.

## Required native tests

`in_channel_io_test.ml` uses production `Plan9_fd` and
`Plan9_in_channel` internally. At minimum, prove:

- a binary payload containing embedded NUL survives channel buffering exactly;
- data written in deliberately uneven chunks is returned across caller reads
  whose sizes straddle the private buffer boundary;
- a caller request larger than the scratch capacity returns valid progress
  without claiming exact fill;
- buffered surplus is returned without another native read;
- writer close yields all queued bytes before observed EOF;
- zero-length input neither consumes a queued byte nor performs native work;
- a retained public descriptor alias is revoked after `of_fd` and cannot read,
  close, or attach;
- channel close and repeated close behave deterministically;
- input after close is rejected without native work;
- forced GC with a live open channel preserves ownership; and
- 256 or another reviewed deterministic count of complete pipe/channel cycles
  leaves the sorted complete `/fd` inventory unchanged.

Rerun the complete existing Plan 9 environment, process, raw-syscall,
primitive, Phase 0 capability, and Phase 1 descriptor suites unchanged.
Actual timing-sensitive note interruption remains outside this checkpoint and
must not be used to force either handler-exit boundary.

## Authoritative transfer and source identity

Reuse the exact accepted Phase 1.3 source-manifest discipline and its reviewed
canonical-path, executable-mode, length, lowercase-digest, hash-tool, and
bytewise-sorting rules. Do not invent a shorter identity scheme for this
incremental checkpoint.

### Initial native source/build-tree selection

Before any Phase 2.1 write to native Plan 9 storage, stop and obtain user
confirmation of the expected exact canonical source/build root, whether the
selection reuses the accepted retained Phase 1.3 tree or creates a new
previously absent Phase 2.1 tree, and the intended reuse or population action.
Also record the exact configuration prefix that the selected tree uses or will
use as a read-only qualification dependency. Confirmation of a VM does not by
itself authorize a native path, and confirmation of a native path does not
authorize an alternate VM, tree, prefix, or action.

For reuse, re-resolve the selected root canonically on the confirmed guest
before the first write and require it to be exactly the retained Phase 1.3
source/build tree named by the accepted Phase 1.3 completion evidence and
`build-aux/plan9/README.md`. Prove its accepted provenance and final identity,
its unique availability, project ownership, and explicit authorization for
this task's reuse, and its disjointness from protected or foreign source/build
trees, install prefixes, consumer roots, and evidence roots. Inventory its
complete pre-transfer state with the Phase 1.3 common schema and require every
tuple to match the accepted final inventory. Confirm the recorded configuration
and prefix identities and the working bootstrap runtime, bootstrap compiler,
source-tree compiler, GNU Make, and other build prerequisites required below.
A changed, incomplete, live elsewhere, foreign, ambiguously owned, path-
mismatched, provenance-mismatched, or prerequisite-incomplete retained tree
stops before transfer.

For a new tree, select one exact canonical previously absent source/build root
and apply the accepted Phase 1.3 common creation-and-ownership gate before
population: prove disjointness from every protected or foreign prefix, source/
build tree, consumer root, and evidence root; prove absence; create only that
exact root; require exact status zero; canonically re-resolve it to the same
root; and record a complete initial common-schema inventory proving that it
contains exactly the root directory and no descendant. Claim task ownership
only after all of those checks succeed. Obtain user agreement on its exact
configuration prefix. Establish only its configured core bootstrap under the
producer-clean configure/core procedure in the execution sequence before
dependency generation; after the authoritative `.depend` returns and the final
source manifest matches, complete its separately gated world build before
qualification. A selected-but-not-created or foreign-or-ownership-unproven
path receives the accepted Phase 1.3 sentinel and no-action proof; never
populate, retain as task-owned, remove, or silently replace it in the same
attempt.

Keep selection, stat, manifest, and comparison evidence outside every source/
build tree. Failure or uncertainty in either branch stops the attempt; do not
infer permission to select another root or fall through from retained-tree
reuse to new-tree creation.

Derive the transfer set from every existing regular worktree file at a path
reported by `git ls-files` at the approved Phase 2 documentation checkpoint,
using the final reviewed Windows worktree bytes, adjusted by exactly these four
new regular source paths:

- `otherlibs/plan9/plan9_in_channel.mli`;
- `otherlibs/plan9/plan9_in_channel.ml`;
- `otherlibs/plan9/tests/in_channel_lifecycle_test.ml`; and
- `otherlibs/plan9/tests/in_channel_io_test.ml`.

At the approved documentation checkpoint these four planned additions have no
Git index entry from which a mode can be derived. Assign each one the explicit
reviewed regular, non-executable Git-mode equivalent `100644`. Include those
four explicit modes in both the pre-generation and final Windows/native mode
manifests, and prove that each native copy is a regular non-executable file. Do
not stage a new path merely to manufacture index-mode evidence. If the user
separately authorizes staging before transfer, require every resulting entry
for these four paths to be exactly `100644` and to agree with the explicit
manifest entry.

No source deletion or other new path is expected. The tracked
`otherlibs/plan9/Makefile` and natively generated
`otherlibs/plan9/.depend` remain ordinary members of that source set at their
final reviewed bytes. Stop for review if implementation proves another path
necessary.

Record complete untracked and ignored inventories separately. Recheck the
complete `git ls-files -s` inventory, exclude `.git` and the accepted non-file
`flexdll` gitlink from transfer, and derive and verify the executable-mode
manifest for baseline tracked regular files from the Git index rather than
Windows mode bits. Merge exactly the four explicit `100644` entries above for
the planned additions; distinguish them from baseline indexed entries in the
evidence. If separately authorized staging later places those additions in the
index, record those entries as corroboration rather than as new provenance or
duplicate transfer-set members. Transfer no unrelated path or build artifact.

Before dependency generation, compare parsed Windows and native content
manifests for the reviewed pre-generation source set. After the generated
`.depend` is returned to the authoritative Windows checkout and final host
review passes, regenerate the complete final Windows manifest, transfer those
exact bytes, and require a matching final native source manifest before any
forced rebuild, disassembly, or test. In a retained configured native tree,
inventory pre-existing build products separately. In a new tree, inventory
every configuration, core-bootstrap, and later world-build product separately
at the boundary that created it. None of those products adds a source path or
permits any transferred source path to differ. Record the canonical native root
and all manifest, hash-tool, mode-restoration, build-product, extra-artifact,
and comparison evidence.

Any authoritative source change after either comparison invalidates the
corresponding native source identity and all later evidence. Repeat the
applicable manifest, transfer, dependency-return, and final-host-review gates
instead of patching guest source.

## Source and packaging review

Before VM work, inspect and record evidence that:

- every `of_fd` success-side allocation, including both complete enclosing
  result candidates, precedes its single explicit `Gc.minor ()`; every live
  commit candidate and result remains rooted through stabilization and the
  later commit application, and no channel-owned allocation or candidate
  replacement follows successful stabilization before commit;
- an exception after successful preparation but before lower commit entry,
  including one propagated by direct `Gc.minor` stabilization or by bytecode
  stack growth or pending-action processing during `commit_attach` application
  setup, neither commits nor closes through the uncommitted token, lets no
  channel escape, and preserves the exact competing descriptor state;
- production commit sees an immediate overwritten state and a promoted
  block-valued replacement, so its `SETFIELD`/`caml_modify` path cannot darken
  an old block, add a young block to the remembered set, request collection,
  or resize C bookkeeping;
- no callback, allocation, or safe point occurs between successful commit and
  return of the preallocated success;
- no callback, allocation, safe point, pending-action processing, or other
  fallible work occurs between a normal `false` commit result and return of the
  complete preallocated enclosing `Error` result;
- the prepare-to-commit window leaves public aliases operational: a completed
  public read or write restores `Open_detached`, can change the underlying
  stream without blocking this channel's later successful commit, and is not
  rolled back; successful `of_fd` linearizes exclusive ownership only at that
  commit;
- commit loss cannot leak a channel or overwrite competing descriptor state;
- all buffer cursor arithmetic is ordered and bounded before indexing;
- input range validation precedes lifecycle and lower work;
- every lifecycle row for an input-family operation is reached only after its
  pure arguments are valid;
- every successful final stable-open recheck is followed immediately by the
  required retained zero return or allocation-free active-state installation;
- the compilation unit defines the typed retained `Ok 0` and `Ok ()` bindings
  outside `Make`; every functor application shares them, never mutates or
  protected-field-stores them, and uses the appropriate exact binding for
  valid zero-length input and repeated terminal close respectively; source,
  CMO, and executable evidence separates their unit-initialization literal
  materialization from the later compiler-selected identity-preserving,
  nonallocating binding access, without assuming closure capture, a fast-path
  `GETGLOBAL`, or cross-type physical distinction;
- one public `input` performs at most one refill and never retries failure;
- every allocated normal input result is complete while active; the input
  handler's normal `POPTRAP` occurs with active state still visible and before
  caller-data or unread-consumption mutation; every positive result precedes
  those mutations; the private direct `C_CALL5 caml_blit_bytes` copy precedes
  cursor advancement; and every post-`POPTRAP` restoration-to-publication
  suffix is handler-exit-, allocation-, callback-, polling-, pending-action-,
  and fallibility-free;
- active state encloses every mutation-sensitive operation; only the
  invocation that installed that active state may restore stable open on its
  normal or exceptional exit, while range and lifecycle rejection paths
  perform no lifecycle, close-attempt, or cursor write and preserve any
  callback-selected state even if result construction raises;
- every GC-scanned lifecycle, close-attempt, or unread-cursor field mutated in
  a protected region is initialized and maintained with immediate values only,
  while attachment tokens and other block-valued stable data occupy separate
  fields that those regions never mutate;
- the channel's sole reusable close attempt is allocated before attachment
  commit, stable-open recheck is followed immediately by allocation-free
  channel active-state install, and close follows the accepted owner-close
  terminal/inactive-retry boundary;
- the accepted `Plan9_fd.Private.close` first-call path separately allocates
  its descriptor-owner close attempt and `Owner_closing` value before its own
  final state/token recheck; those allocations occur only after channel active-
  close state and the channel handler are installed, and occur outside the
  protected channel recheck-to-install and normal-lower-return-to-channel-
  terminalization regions;
- after a normal primitive result, the accepted lower close terminalizes its
  descriptor-owner attempt before mapping that result; its native-error
  construction may allocate or raise before normal lower return, remains
  covered by the channel handler with the channel attempt nonterminal, and
  does not begin the allocation-free channel terminalization suffix;
- the close handler covers the lower call, immediate channel terminalization
  after normal lower return, and handler-exit `POPTRAP`; its terminal flag
  distinguishes a pre-return lower exception, which deactivates the attempt,
  from a post-channel-terminalization pending-callback exception at `POPTRAP`,
  which preserves terminal state;
  the retained lower result, attempt, and channel remain rooted across that
  pending-action path;
  wrapper mapping occurs only after normal handler exit and cannot restore an
  inactive state;
- an exception escaping `Fd.Private.prepare_attach` propagates unchanged and
  cannot cause channel-owned commit or cleanup work;
- every malformed successful fill leaves normalized empty cursors, ignores
  adversarial scratch contents, and permits a later valid refill;
- no public alias is restored after attachment;
- the new module has exactly the three generated prerequisite sets above,
  depends only on accepted private predecessors, and changes no pre-existing
  `.depend` stanza;
- the lifecycle test uses the exact private-object link order above, both new
  tests use `$(NEW_OCAMLRUN)`, and the pure process-state lane remains on
  bootstrap `$(OCAMLRUN)`;
- the generated primitive table and runtime object set are byte-for-byte
  unchanged, while the focused executable's used-primitive section contains
  the expected existing `caml_blit_bytes` and `caml_gc_minor` references;
- `plan9.cma` contains ML only;
- because `plan9.cma` is built with `-linkall`, production
  `Plan9_in_channel` unit initialization constructs only its reviewed ML
  closures and module values and references the already materialized unit-
  scoped retained normal results; it does not allocate those result blocks
  and performs no descriptor acquisition, attachment, read, close, or native
  call;
- `CMIFILES` remains exactly `plan9.cmi`; and
- `plan9.mli` and `plan9.ml` remain byte-for-byte unchanged, with the accepted
  Phase 1.3 public `plan9.cmi` identity recorded for the native comparison
  below.

No claim should exceed the accepted APE-independent descriptor path. Existing
`Plan9.Env`, `Sys`, `Unix`, and unrelated runtime operations retain their
documented APE behavior.

This host source review is necessary but is not final proof of the
allocation-, callback-, polling-, or safe-point-free bytecode regions below.
The target-native disassembly audit in qualification is authoritative for
those claims.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state and the exact accepted Phase 1.3 target-built public
`plan9.cmi` path, decimal size, and content hash from its completion evidence.
Implement only the authorized source boundary, run safe host-side text/diff
checks, and leave generated `.depend` untouched.

### 2. Complete host review

Inspect every changed line, authorized path, module dependency, error template,
buffer invariant, callback boundary, and test expectation. Report the proposed
source and any discrepancy to the user.

### 3. Explicit VM and native-tree confirmation

Stop and obtain user confirmation of the exact writable instance, unique
loopback address, intended start/use action, WHPX profile, expected canonical
native source/build root, retained-versus-new selection, intended tree action,
and configuration prefix described above. Inspect the P9QEMU/Python/QEMU
chain, exact QEMU PID, address, disk, and seven listeners as required by
repository policy. Do not start or reuse another project's VM. After
connection and before the first native write, perform the corresponding
retained-tree proof or new-tree creation-and-ownership gate in full. A failed
gate stops; it does not authorize an implicit alternate tree.

### 4. Native dependency generation and authoritative return

Only into the confirmed and proved native root, transfer the reviewed source
set without `.git` through `/mnt/term`, copy it to native Plan 9 storage, enter
APE through `ape/psh`, use the exact shell setup from
`build-aux/plan9/README.md`, resolve the actual GNU Make executable, and require
the pre-generation Windows/native source manifests above to match.

Before the dependency producer, establish and record one producer-clean
environment. Require `OCAMLPARAM`, `OCAMLLIB`, legacy `CAMLLIB`,
`CAML_LD_LIBRARY_PATH`, `BUILD_PATH_PREFIX_MAP`,
`OCAML_BINANNOT_WITHENV`, `OCAMLRUNPARAM`, legacy `CAMLRUNPARAM`,
`CAML_DEBUG_FILE`, and `CAML_DEBUG_SOCKET` to be unset. This exact explicit-
unset set also governs every directly invoked compiler, linker, runtime, and
evidence-tool command below; the GNU Make no-injection proof does not
substitute for it. Before every top-level GNU Make command, additionally
require inherited `MAKEFLAGS`, `GNUMAKEFLAGS`, `MFLAGS`, `MAKEFILES`, and
`MAKEOVERRIDES` to be unset, and reject any other inherited GNU Make option or
variable assignment that redirects, suppresses, ignores failures from,
overrides tools or recipes in, or rewrites outputs of the reviewed command.
Literal command-line assignments expressly required by this handoff are not
inherited injection. A recursive GNU Make may synthesize only the internal
flags and exact assignments derived from that reviewed top-level command;
record the expanded recursive commands and prove that no other value entered
them. This cleanliness gate is additional to, and does not replace, the exact
documented `ape/psh` setup.

Before every `build-aux/plan9/configure.sh` invocation in this handoff,
additionally establish and record one configure-clean environment. Retain the
exact resolved `MAKE` export required by the documented Plan 9 shell setup,
and set and export `CONFIG_SITE=/dev/null` so neither an environment-selected
nor an agreed-prefix `config.site` script is loaded. Require `CONFIG_SHELL`,
`build_alias`, `host_alias`, `target_alias`, `AS`, `ASPP`, `PARTIALLD`,
`DLLIBS`, `WINDOWS_UNICODE_MODE`, `DEFAULT_STRING`, `CC`, `CFLAGS`, `LDFLAGS`,
`LIBS`, `CPPFLAGS`, `LT_SYS_LIBRARY_PATH`, `CPP`, `AR`, `RANLIB`, `LD`,
`DEP_CC`, `DIRECT_LD`, `STRIP`, and `AWK` to be unset before invoking the
wrapper, and reject every other inherited configure option, cache value,
feature-test override, or tool selection, including any `ac_cv_*`, `ax_cv_*`,
or `lt_cv_*` variable. The wrapper must therefore select `CC=c89` and its exact
literal Plan 9 `CPPFLAGS`; a different compiler, preprocessor flag set, site
policy, cache value, or tool override requires a new reviewed handoff revision
rather than an implicit environment exception. Preserve the complete
pre-invocation environment and configure output, then prove from `config.log`,
`Makefile.config`, and the configured command variables that no site script or
cache was loaded and that the exact prefix, `MAKE`, `CC`, `CPPFLAGS`, and
derived tool selections match this gate.

If the selected root is new, establish only the configured core bootstrap
needed by the dependency producer. After the source manifest and modes match,
and after immediately re-recording the producer-clean environment before each
command, run these exact command shapes from the repository root with the user-
agreed prefix substituted literally:

```text
build-aux/plan9/configure.sh --prefix=<agreed configuration prefix>
"$MAKE" MAKE="$MAKE" core
```

Preserve both exact commands, producer-clean and configure-clean environments,
complete outputs, statuses, configured paths, and resulting bootstrap-runtime,
compiler, standard-library, and GNU Make identities. Prove that every GNU Make
process reached by `core` satisfies the top-level and recursive no-injection
rule above, that this target
builds the repository's documented minimum system needed to run dependency
generation, and that it neither enters `otherlibs/plan9` nor changes the
authoritative pre-generation `.depend`. Require exact status zero for both
commands and prove the agreed read-only dependency prefix and every protected
prefix unchanged before dependency generation. After `core`, regenerate and
compare the complete parsed pre-generation source and mode manifests and
require them still to match the authoritative Windows manifests exactly;
inventory every configure/core artifact separately. Do not run `world`,
`build-world.sh`, `all`, `otherlibraries`, or `alldepend` in this pre-generation
lane. A source-set delta or a nonzero, interrupted, unknown, incomplete, path-
incomplete, or contradictory configure or core result rejects that initial
dependency tree; record its complete failed-tree inventory and retained or
separately authorized removed postcondition. Do not run the dependency producer
there or resume establishment in place. Any later fresh dependency-tree attempt
starts from another new absent root and repeats the complete creation, transfer,
configure, and core gate. A retained tree does not rerun these establishment
commands, but its accepted configuration and working prerequisites must already
have passed the initial retained-tree proof.

Immediately before dependency generation, re-record that environment and
re-prove all of those unset and no-injection conditions. Only then run this
exact command from the repository root with the resolved GNU Make executable:

```text
"$MAKE" -C otherlibs/plan9 depend
```

Record the exact command, producer-clean environment, complete output, exit
status, GNU Make identity, expanded dependency recipe, configured
`$(OCAMLRUN)` and target `boot/ocamlc` paths and identities, and pre/post
`.depend` paths, decimal sizes, and content hashes. Accept the output only
after exact status zero and
prove that it is nonempty and complete, contains `.cmi`, `.cmo`, and `.cmx`
rules for every Plan 9 ML unit, has exactly the three new prerequisite sets
specified above, changes no predecessor stanza, and causes a guest source-
manifest delta containing only `otherlibs/plan9/.depend`.

Only after those checks may the exact generated file return through
`/mnt/term`. Compare the returned bytes with the accepted guest artifact before
replacing only the authoritative Windows `.depend`, inspect its diff, repeat
host review, produce the final authoritative manifest, and re-establish exact
native source identity before qualification. A nonzero, interrupted, unknown,
empty, truncated, incomplete, or contradictory result is rejected evidence:
preserve its command, diagnostics, and artifact outside the source tree, do not
return or adopt it, and either repopulate a new reviewed dependency tree or
restore the exact authoritative pre-generation `.depend` into the same
confirmed tree. Repeat the complete pre-generation source and mode manifest
checks and the producer-clean environment gate before any retry. Do not
approximate the APE namespace manually.

A newly selected dependency tree in that recovery branch must first repeat the
exact VM/native-path confirmation, creation-and-ownership, source-transfer,
mode, manifest, configure, and core-bootstrap gates above. It does not use the
later replacement-qualification world-build rule. Reuse of the same confirmed
tree is allowed only after its failed artifact has been preserved externally,
the authoritative pre-generation `.depend` has been restored byte-for-byte,
its source/mode manifests and core-bootstrap artifact identities still match,
and every failure postcondition is closed.

### 5. Native qualification

Throughout this qualification, an input-artifact, output-artifact, executable,
or evidence-tool “identity” includes its canonical absolute path and complete
accepted Phase 1.3 common-schema tuple: entry type, native mode, server type
and device, Qid type/version/path, ownership fields, decimal byte length, and
content hash. If it belongs to an inventoried tree, also record that canonical
root and its raw root-relative path. A local request for size and hash is a
reporting emphasis, not permission to omit the rest of this identity.

Before the first evidence-producing qualification command, re-establish and
record the producer-clean environment defined in step 4 as the
qualification-clean environment inside the exact documented `ape/psh` shell
setup. It governs every subsequent evidence-producing compiler, linker,
runtime, GNU Make, tool-build, tool-execution, disassembly, symbol-inspection,
and test command, beginning with the conditional initial-tree world build when
applicable and otherwise with the `stdlib__Gc.cmi` reproduction below.
Immediately before each top-level evidence command named by this handoff,
re-record the environment and re-prove every required unset and no-injection
condition. For compiler, linker, runtime, or tool producers spawned by a
reviewed GNU Make command, the immediate parent proof is sufficient only when
the complete expanded recipe and Makefile path prove that each child inherits
the relevant unset OCaml/runtime/debugger controls and receives no Make option
or assignment except GNU Make's internally synthesized values from the exact
reviewed top-level command. A set or injected control variable, a change in
the required unset state, an unreviewed child override, or an unrecorded
producer environment stops qualification. This remains an additional
cleanliness gate within the documented Plan 9 shell procedure, not permission
to approximate or replace that procedure.

Return the final reviewed source set to native storage and build in the
accepted APE/GNU Make lane. After the final source manifests match, a new
initial tree that ran only the core-bootstrap lane above must first run this
exact full-world command from the repository root:

```text
build-aux/plan9/build-world.sh
```

Immediately before it, re-record the qualification-clean environment and
re-prove every unset and GNU Make no-injection condition. Preserve the exact
command, complete output, status, expanded recursive commands, and all newly
built runtime, compiler, standard-library, tool, and otherlib identities.
Require exact status zero, prove that every GNU Make process satisfies the
top-level and recursive no-injection rule, prove that the final authoritative
`.depend` supplied the `plan9_in_channel.cmi` prerequisite edge before the
new implementation was compiled, and recheck that the final source/mode
manifests and every agreed or protected prefix remain unchanged. A nonzero,
interrupted, unknown, incomplete, path-incomplete, up-to-date-only,
pre-generation-dependency, or contradictory result rejects that new tree; do
not begin qualification there or repair it in place. A retained Phase 1.3 tree
does not rerun this conditional initial-world step.

Only after that conditional step succeeds or is inapplicable, first reproduce
the exact target standard-library `Gc` interface artifact selected by the Plan
9 otherlib compiler. The reviewed repository graph derives
`stdlib/stdlib__Gc.cmi` from `stdlib/gc.mli`; if the target graph resolves a
different interface artifact or source, stop rather than substituting it. Run
this exact target-scoped shape from the repository root with the recorded GNU
Make executable:

```text
"$MAKE" -C stdlib -W gc.mli stdlib__Gc.cmi
```

Preserve the complete command, output, and status and require exact status
zero. The log must visibly recompile the current `stdlib/gc.mli` into that CMI
without rebuilding or changing a source file. Record the source and interface
paths and complete identities, expanded rule, and complete compiler command.
Record the canonical paths and complete identities of every `$(OCAMLRUN)`
launcher and compiler-bytecode artifact named by that command. Prove that the
Plan 9 otherlib `$(CAMLC)` expansion retains its reviewed fully expanded
`$(BEST_OCAMLC) -nostdlib -I $(ROOTDIR)/stdlib` selection and selects this
exact CMI for the saturated external declaration. Record the launcher and
bytecode compiler identities selected there as well. Separately record the
complete identity of the source-tree `stdlib.cma` selected by each focused
link below as an ordinary link input; do not claim that a `Gc` wrapper object
supplies the direct primitive call. An up-to-date shortcut, stale or different
`Gc` CMI, different launcher, compiler, or archive, nonzero, interrupted, or
unknown status stops qualification.

Then run this exact target-scoped forced-rebuild shape from the repository
root with the recorded GNU Make executable:

```text
"$MAKE" -C otherlibs/plan9 -B \
  plan9.cma \
  tests/in_channel_lifecycle_test \
  tests/in_channel_io_test
```

On the Plan 9 target `$(EXE)` is empty, so these are the resolved program
targets. The complete log must visibly recompile the current
`plan9_in_channel.mli` and `plan9_in_channel.ml`, relink the current
`plan9.cma`, reproduce the current public `plan9.cmi`, and rebuild both focused
channel tests through their reviewed rules and object order. Preserve the
command and log; an up-to-date shortcut, different target set, stale object,
or incomplete compilation trace is not qualification.

Immediately after that rebuild, record the new public `plan9.cmi` path,
decimal size, and content hash and require byte-for-byte identity with the
exact accepted Phase 1.3 target-built artifact recorded during preflight. A
mismatch means this private subphase changed or failed to reproduce its public
compilation interface and stops qualification even if `plan9.mli` source bytes
are unchanged.

Before selecting or creating the consumer directory, resolve and record the
fully expanded source-tree bytecode compiler command and its exact argument
order. In this bytecode-only lane the expected command is the configured
`$(OCAMLRUN)` launcher followed by the source-tree `ocamlc` bytecode artifact;
if the expanded target graph selects a different shape, stop rather than
silently treating one path as the compiler. Record the canonical path and
complete identity of every executable or bytecode artifact in the command,
including both `boot/ocamlrun` and `ocamlc` for the expected shape. Also record
the exact configured `$(NEW_OCAMLRUN)` canonical path and complete identity.
Do not call any artifact freshly built unless the preserved build log proves
that fact. Use the exact recorded compiler command for its identity probe and
consumer compilation, and the recorded `$(NEW_OCAMLRUN)` for consumer
execution and every repository bytecode evidence-tool invocation explicitly
shown below. Run the resolved native symbol-inspection tool directly under the
same qualification-clean environment. A later path, argument order, identity,
or configuration change invalidates the affected evidence.

Select and record an exact canonical fresh consumer-directory path on native
storage outside the source and build trees. Prove it is disjoint from every
source, build, dependency-generation, transfer, evidence, install, protected,
and retained tree relevant to the attempt, and prove it is absent. Invoke
creation only for that exact path and preserve the command, output, and status.
Claim task ownership only after exact status zero followed immediately by
canonical re-resolution to the same root, a complete initial identity
inventory using the accepted Phase 1.3 common schema, and proof that the
directory contains exactly its root and no descendant.

If creation is nonzero, interrupted, or unknown, or canonical identity,
disjointness, ownership, or emptiness cannot be proved, stop before copying or
compiling and perform one read-only re-resolution. If the path is absent,
record the exact selected-but-not-created sentinel and failure reason. If it
exists without proved task ownership, record the exact
foreign-or-ownership-unproven collision sentinel, canonical path, and root
stat identity obtainable without walking or modifying it. Never populate,
retain as task-owned, or remove an unowned path, and do not select another
consumer path within the same qualification attempt.

Only a successfully created, identity-proved, empty task-owned directory may
receive byte-identical copies of the freshly built `plan9.cma`, the verified
public `plan9.cmi`, and this exact accepted minimal public consumer source:

```ocaml
let () =
  ignore Plan9.wait_succeeded;
  print_endline "plan9 staging consumer: passed"
```

Record the source and staged paths, decimal sizes, and content hashes, require
each staged archive/CMI copy to match its freshly built source artifact, and
record the consumer-source hash. Before compilation, record a complete
identity inventory using the accepted Phase 1.3 common schema and require the
directory to contain exactly its root plus these three regular files and no
other entry: `plan9.cma`, `plan9.cmi`, and `consumer.ml`. This exact allowlist
also proves that `plan9_types.cmi`, `plan9_primitive.cmi`, `plan9_fd.cmi`,
`plan9_in_channel.cmi`, `plan9_process.cmi`, every private `.cmo`, every C
payload, competing archive, directory, and unrelated file are absent.

For the compiler identity probe, consumer compilation and execution, and the
recorded `$(NEW_OCAMLRUN) -p`, `dumpobj`, and `ocamlobjinfo` invocations, use
and immediately re-record the qualification-clean environment established
above. Under that environment, invoke the exact recorded launcher-plus-
compiler command with `-where`, preserve its result, and resolve and record the
canonical standard-library root plus the path, decimal size, and content hash
of the effective `stdlib.cma`, `std_exit.cmo`, `stdlib.cmi`, and `camlheader`
that ordinary compilation and linking will select. Resolve `ld.conf` under
that root and
record either its regular-file path, decimal size, and content hash or its
proved absence; a non-regular entry is invalid. An injected compiler or
runtime option, alternate launcher or standard-library root, competing
archive or interface, unresolved implicit input, or change between the
identity probe and compilation stops qualification.

Compile in the isolated directory with the resolved source-tree bytecode
compiler in the exact shape
`<recorded source-tree compiler command> -I . plan9.cma consumer.ml -o consumer`,
where the placeholder expands literally to the recorded launcher and compiler
artifacts in their recorded order. Use no include path back to
`otherlibs/plan9`, `-linkall`, `-custom`, `-use-runtime`, C compiler, linker,
wrapper compiler, or additional archive. Run the result under the same
recorded environment with exactly
`<recorded NEW_OCAMLRUN> ./consumer`. Re-hash the staged `plan9.cma`,
`plan9.cmi`, effective `stdlib.cma`, `std_exit.cmo`, `stdlib.cmi`, and
`camlheader` afterward and require all six to retain their recorded
identities. Recheck the recorded `ld.conf` identity or absence and require it
to remain unchanged.

Whenever a task-owned consumer directory's probe terminates, successfully or
otherwise, stop all writes within that exact consumer directory and record its
exact successful, failed, interrupted, unknown, or incomplete status and
reason, followed by a complete final identity inventory including every
partial output. Later qualification may build or test elsewhere and may read
the retained consumer directory only through the exact evidence commands
authorized below; it must not modify any consumer entry. Retain that exact
directory and inventory by default. Removal is a separate destructive action
requiring explicit user authorization: re-resolve the exact canonical path,
reprove disjointness, require its complete current inventory to match the
preserved final inventory, remove only that exact task-owned directory, and
prove it is absent. An inventory mismatch blocks removal. A selected-but-not-
created or foreign-or-ownership-unproven path follows the no-action branch
above. Keep the consumer, inventories, and logs outside the source-set
manifest. This is a source-tree packaging probe, not an installed-prefix or
installed-consumer test.

Build the repository target-native `tools/dumpobj` and `tools/ocamlobjinfo`
through the accepted tool lane, using the recorded GNU Make executable:

```text
"$MAKE" -C tools -W make_opcodes.mll -W dumpobj.ml dumpobj
"$MAKE" -C tools -W objinfo.ml ocamlobjinfo
```

Preserve both commands, complete outputs, and statuses, and require exact zero
for each. The first log must visibly regenerate `tools/make_opcodes.ml` from
the authoritative `tools/make_opcodes.mll`, rebuild `tools/make_opcodes`,
regenerate `tools/opnames.ml` from the exact `runtime/caml/instruct.h`, compile
`tools/opnames.cmo` and `tools/dumpobj.cmo`, and relink `tools/dumpobj`; an
unchanged or skipped link in that chain stops qualification. Record the
canonical source and target paths, decimal sizes, and content hashes for
`tools/make_opcodes.mll`, generated `tools/make_opcodes.ml`,
`tools/make_opcodes`, `runtime/caml/instruct.h`, `tools/opnames.ml`,
`tools/opnames.cmo`, `tools/dumpobj.ml`, `tools/dumpobj.cmo`,
`tools/objinfo.ml`, `tools/objinfo.cmo`, `tools/dumpobj`, and
`tools/ocamlobjinfo`, plus their expanded lexer, generator, compiler, and link
rules and the canonical path and complete identity of each executable or
bytecode tool those rules invoke. An up-to-date, stale, differently sourced,
nonzero, interrupted, or unknown tool result stops qualification.

Under the same recorded qualification-clean environment, run that exact
target-native `tools/ocamlobjinfo` with the recorded `$(NEW_OCAMLRUN)` against the retained
isolated consumer's `consumer.cmi`. Preserve the exact command, complete
output, status, consumer-CMI identity, and every imported interface name and
CRC. Require the staged `Plan9` import to match the recorded staged
`plan9.cmi`; require every other imported CMI used by compilation to resolve
canonically beneath the recorded standard-library root and record its path,
decimal size, and content hash. An unresolved import, CRC mismatch, import
resolved outside those two approved locations, or change in any recorded
interface identity stops qualification. Re-hash these imported CMIs after the
remaining evidence commands and require their identities to remain unchanged.

Under that same recorded qualification-clean environment, also run the exact
target-native `tools/ocamlobjinfo` with the recorded `$(NEW_OCAMLRUN)` against the freshly
forced-built `otherlibs/plan9/plan9_in_channel.cmo` with this command shape:

```text
<recorded NEW_OCAMLRUN> tools/ocamlobjinfo \
  otherlibs/plan9/plan9_in_channel.cmo
```

Preserve the exact command, complete output, status, CMO identity, and every
imported interface name and CRC. Require the imports for `Stdlib__Gc`,
`Plan9_types`, `Plan9_fd`, and the unit's own `Plan9_in_channel` interface to
match the exact recorded CMIs selected by the forced build. Resolve and record
the canonical path and complete identity of each of those four CMIs. Require
every other imported CMI to resolve canonically beneath the recorded standard-
library root, and require that no `Plan9_primitive` import appears. An
unresolved import, CRC mismatch, import resolved outside those approved local
or standard-library locations, unexpected private Plan 9 import, or later
change in any recorded interface identity stops qualification. Re-hash these
CMIs after the remaining evidence commands and require their identities to
remain unchanged.

Use the exact `$(NEW_OCAMLRUN)` path and identity already recorded before the
consumer probe. Run the exact target-native `tools/dumpobj` under that recorded
runtime against the freshly forced-built
`otherlibs/plan9/plan9_in_channel.cmo`. Record the tool, runtime, object,
command, status, sizes, content hashes, relocation table, and complete
disassembly; invoke `tools/dumpobj` with `-reloc` so the CMO's symbolic literal
relocations are visible. The ordinary debug build must retain source events
sufficient to map the reviewed functions; if it does not, stop.

Record the canonical paths and complete identities of `stdlib/gc.mli`, the
freshly reproduced `stdlib/stdlib__Gc.cmi`, `lambda/translcore.ml`,
`lambda/translprim.ml`, `lambda/matching.ml`, `lambda/simplif.ml`,
`lambda/translmod.ml`, `bytecomp/bytegen.ml`, `bytecomp/emitcode.ml`,
`bytecomp/symtable.ml`, and `bytecomp/bytelink.ml`, plus the exact compiler
launcher and bytecode artifact selected by the Plan 9 otherlib build above.
Record the build provenance tying that artifact to every reviewed compiler
source. Review the external declaration and the compiler's saturated-
primitive lowering from `Val_prim`, through `Translcore`'s call into
`Translprim`, `Translprim`'s `External`-to-`Pccall` translation, bytecode
generation, and emission. Also review `Translprim`'s caught-exception
`Raise_reraise` translation used by the required ordinary `RERAISE` paths.
In the already required `plan9_in_channel.cmo` disassembly,
`Gc.minor ()` must appear as direct `C_CALL1 caml_gc_minor`, with no
`GETGLOBAL`/wrapper `APPLY`, caller-side stack check, or `CHECK_SIGNALS`
between argument preparation and primitive entry. There is no `Gc` CMO
wrapper-dispatch evidence requirement because the call must not dispatch
through one. The byte-copy evidence likewise begins at the private external
declaration and saturated call in `plan9_in_channel.ml` and must appear as the
direct `C_CALL5` in that same disassembly.

Separately, divide each retained-result proof into materialization and access.
For materialization, trace `Translcore` from each `Texp_construct` through its
`Cstr_block` branch and constant-argument extraction to
`Lconst (Const_block ...)`, then trace `Matching`'s strict top-level binding,
`Simplif` and `Translmod` structure and functor treatment, bytecode `Kconst`
emission as a literal `GETGLOBAL`, `Reloc_literal` assignment in `Symtable`, and
`Bytelink` serialization of the initial global table into executable `DATA`.
Record the CMO `-reloc` evidence and the final focused executable's resolved-
constant disassembly. Standard `dumpobj` consumes but does not print a final
executable's numeric global-slot operand, so no hidden numeric slot is required
for this materialization proof and no cross-type physical-sharing conclusion
may be inferred from its output.

For access, trace `Translmod` and `Bytegen` from each strict unit binding to the
exact target opcodes used by the resulting `Make` and fast paths. A compiler
substitution to a compilation-unit global field, closure capture, or another
fully mapped route is acceptable only when it preserves access to the declared
stored binding; the evidence must describe the route actually selected.
`ENVACC`, `ACC`, `GETGLOBALFIELD`, or another proved identity-preserving,
nonallocating load is acceptable. A literal `GETGLOBAL` is acceptable only if
compiler and artifact evidence proves that it resolves to that same stored unit
binding, rather than to an independently materialized structurally equal
literal. Because standard `dumpobj` hides the final numeric global-slot operand,
stop if that same-binding fact cannot otherwise be proved. Do not require
closure capture or a fast-path `GETGLOBAL` merely because materialization used
one. The per-type repeated-call and cross-`Make` physical-identity tests
corroborate reuse but do not by themselves establish this binding provenance.
Map executable startup through `runtime/startup_byt.c` and `runtime/intern.c`
into `caml_global_data`, including startup oldification, and map its global-root
scan through `runtime/roots_byt.c`. Prove that every authorized zero-length
and terminal-close fast path reaches its retained binding without `MAKEBLOCK`,
result-block allocation during functor application or unit initialization,
polling, or a pending-action boundary.

Resolve the configured object and archive suffixes and record the exact target
paths and identities for the bytecode runtime's `runtime/str.b.<O>`,
`runtime/interp.b.<O>`, `runtime/startup_byt.b.<O>`,
`runtime/intern.b.<O>`,
`runtime/dynlink.b.<O>`, `runtime/memory.b.<O>`,
`runtime/minor_gc.b.<O>`, `runtime/gc_ctrl.b.<O>`,
`runtime/signals.b.<O>`, `runtime/memprof.b.<O>`,
`runtime/finalise.b.<O>`, `runtime/roots_byt.b.<O>`,
`runtime/globroots.b.<O>`, `runtime/freelist.b.<O>`,
`runtime/major_gc.b.<O>`, `runtime/callback.b.<O>`,
`runtime/stacks.b.<O>`, `runtime/fail_byt.b.<O>`, `runtime/misc.b.<O>`, and
`runtime/custom.b.<O>` objects,
`runtime/libcamlrun.<A>` archive, generated `runtime/primitives`,
`runtime/prims.c`, separately linked `runtime/prims.<O>`, and recorded
`$(NEW_OCAMLRUN)`. This is the minimum evidence set established by repository
source review, not permission to truncate the target's actual transitive path.
If the exact configured runtime reaches another object while scanning or
promoting roots, performing an application stack check or reachable major
slice, dispatching a callback, raising or propagating an exception, or
evaluating a hook or custom-finalizer site, add that object and its source to
the recorded set before qualification. Preserve the expanded runtime object
list and link rules proving that every recorded object enters that exact
archive, that `prims.<O>` remains a separate direct input, and that the
recorded runtime links both the direct object and archive.

Record the canonical native source paths, decimal sizes, and content hashes of
`runtime/interp.c` used for the `PUSHTRAP`, `POPTRAP`, `C_CALL1`, `C_CALL5`,
`RERAISE`, and field-write opcode audits; `runtime/memory.c`,
`runtime/caml/minor_gc.h`, and `runtime/minor_gc.c` used for the field-write
and minor-collection audits;
`runtime/gc_ctrl.c` used for explicit precommit stabilization;
`runtime/startup_byt.c` and `runtime/intern.c` used for executable `DATA`
loading, unmarshalling, `caml_global_data` installation, and startup
oldification;
`runtime/roots_byt.c` and `runtime/globroots.c` used to establish the exact
bytecode-stack, local-C-root, and global-root promotion path;
`runtime/freelist.c` and `runtime/major_gc.c` used by promotion allocation and
the reachable major-slice path; `runtime/signals.c`, `runtime/memprof.c`,
`runtime/finalise.c`, and `runtime/callback.c` used by pending-action,
callback, and exception dispatch; `runtime/stacks.c` used by bytecode
application stack checks and growth; `runtime/fail_byt.c` used by stack-limit,
`caml_raise_if_exception`, final exception selection, repeated pending-action,
and bytecode-runtime raise paths; and `runtime/misc.c` and `runtime/custom.c`
used to establish hook initialization and custom-table provenance. Include any
additional source required by the target-derived expansion above.

Record the generator rule and source inventory for `runtime/primitives`, and
prove that the generated primitive-name file and both arrays in `prims.c`
contain `caml_blit_bytes` and `caml_gc_minor` exactly once each at their
corresponding indices. Run the recorded runtime's builtin-primitive listing
under the documented exact environment with this command shape, replacing the
angle-bracketed runtime with its recorded canonical path literally:

```text
<recorded NEW_OCAMLRUN> -p
```

Preserve its complete output and status and require each of those two names to
appear exactly once at the same position it occupies in the generated table.
Use the resolved target symbol-inspection tool to prove that
`prims.<O>` references both entries, `caml_blit_bytes` is supplied by the
recorded `str` object, `caml_gc_minor` is supplied by the recorded `gc_ctrl`
object, and the final runtime resolves each without a duplicate or alternate
definition.

Run the recorded `ocamlobjinfo` and `dumpobj` tools under the recorded runtime
against the freshly rebuilt native-I/O executable with these command shapes
from the repository root, again substituting the recorded runtime path
literally:

```text
<recorded NEW_OCAMLRUN> tools/ocamlobjinfo \
  otherlibs/plan9/tests/in_channel_io_test
<recorded NEW_OCAMLRUN> tools/dumpobj \
  otherlibs/plan9/tests/in_channel_io_test
```

Preserve the executable identity, both exact commands and statuses, the
complete `ocamlobjinfo` output, and the complete disassembly. Require
`ocamlobjinfo`'s ordered `Primitives used` section to contain
`caml_blit_bytes` and `caml_gc_minor` exactly once each. Review
`tools/objinfo.ml`, its recorded build provenance, and the exact built tool to
prove that its forward string scan prepends each primitive and its printer
emits that accumulated list without reversing it, so the displayed section is
the reverse of executable `PRIM` serialization order. Count the displayed
entries as `N`, number displayed positions from zero, and record each unique
displayed position `d_blit` and `d_gc` with its actual executable primitive
index `N - 1 - d_blit` and `N - 1 - d_gc`; never use a displayed position
directly as a primitive index.

Review `tools/dumpobj.ml`, its recorded build provenance, and its exact built
artifact to prove that it preserves serialized `PRIM` order and that
executable `C_CALL1` and `C_CALL5` printing reads each actual numeric operand
and indexes that preserved vector. Correlate the final linked
`C_CALL1 caml_gc_minor` and `C_CALL5 caml_blit_bytes` outputs with their
computed indices, thereby proving the actual operands and indices rather than
claiming that `dumpobj` printed a table it does not emit. Using the reviewed
`runtime/startup_byt.c`, `runtime/dynlink.c`, and `runtime/caml/prims.h` plus
their recorded target objects, map executable startup reading the `PRIM`
section, name lookup through the generated builtin arrays, construction of
`caml_prim_table`, `Primitive1(index)` dispatch to the `gc_ctrl`
implementation, and `Primitive5(index)` dispatch to the `str` implementation.
A CMO relocation name, symbolic `dumpobj` call, or final C symbol without this
ordered executable table, numeric correlation, and generated-table chain is
not proof. Any duplicate, missing, reordered, unresolved, differently
supplied, or unlinked entry stops qualification.

Using the disassembly and reviewed source, map the complete reachable control
flow for:

- completion of all success-side allocations through the rooted direct
  `C_CALL1 caml_gc_minor` path and its normal promotion or final-runtime-
  exception path; the later `commit_attach` application stack check and
  pending-action boundary, lower entry and internal final recheck, its
  block-valued state write, and
  successful publication of the preallocated `Ok channel` or failed commit
  through the complete preallocated enclosing `Error` result; both result
  candidates remain rooted through stabilization and commit, the post-`false`
  suffix performs no allocation, polling, callback, pending-action processing,
  or other fallible work, and every pre-entry exception branch performs no
  commit, cleanup close, or channel publication;
- every input-family final stable-open check that begins an active operation
  through allocation-free active installation, plus valid zero-length `input`
  through the exact unit-scoped retained `Ok 0` binding, with no `MAKEBLOCK`,
  allocation, poll, or pending-action boundary;
- every positive `input` path from availability of its already constructed
  success through the input handler's active-state `POPTRAP`, exact direct
  destination copy, unread-cursor advancement, stable-state restoration, and
  publication, proving that handler exit precedes mutation and copy precedes
  cursor advancement;
- every other normal active input outcome from availability of its retained or
  fully constructed result through active-state `POPTRAP`, stable-state
  restoration, and publication;
- every normal and exceptional path owned by an invocation that installed
  active input through exact stable-state restoration before result
  publication or physical-identity reraise, plus every range/lifecycle
  rejection path through normal error publication or an exception without any
  state restoration or overwrite;
- final stable-open close recheck through activation of the preallocated
  attempt and change of the immediate lifecycle tag to closing;
- normal lower-close return through immediate terminalization, terminal-state
  handler-exit `POPTRAP`, and only then wrapper error mapping or result
  publication;
- an exception escaping before normal lower-close return through attempt
  deactivation and ordinary `RERAISE`;
- a pending-callback exception at the close handler's `POPTRAP` through the
  terminal-flag branch and ordinary `RERAISE` without terminal-state change;
- any exception-capable wrapper mapping after terminalization, proving that it
  cannot reach the inactive-close transition; and
- repeated terminal close through the exact unit-scoped retained `Ok ()` binding,
  with no lower call, `MAKEBLOCK`, allocation, poll, or pending-action
  boundary.

Treat each item as a complete control-flow region, including every branch,
switch target, and fallthrough, rather than as a visually contiguous source
span. No protected check-to-install or commit-to-publication region may
allocate, poll, process pending actions, invoke a callback-capable operation,
or leave through an unreviewed target. The expected private read or close call
may occur only after the corresponding channel active state is visible.
The explicit direct `Gc.minor ()` primitive, its collection and pending-action
or finalizer processing, and the later `commit_attach` application setup all
precede the lower commit's internal final state/token recheck and therefore lie
outside the final protected commit-to-publication suffix. The direct primitive
call has no ML wrapper application, caller-side stack-growth check, or pending-
action boundary before primitive entry; the later `commit_attach` application
still has its own reviewed setup and pre-entry exception branches. Map both
paths completely, including any repeated pending-action processing during
runtime raise, and prove that no allocation or callback after successful
stabilization can replace the immutable rooted attached-state candidate or
make it young before that recheck.

For input, map `PUSHTRAP`, every active operation path, normal `POPTRAP`, and
the exception handler completely. Prove that normal `POPTRAP` pending-action
processing occurs while active state remains visible and before any caller-
destination or unread-consumption mutation; a pending callback exception takes
the handler's stable-restoration and `RERAISE` path; and a successful refill's
complete bytes are already described by the cursors on that path. Prove from
the interpreter's event-frame setup and root scan that the prepared outcome,
channel, destination, and every other live value remain rooted if `POPTRAP`
processes pending work. No positive-input post-`POPTRAP` mutation-to-
publication region or other normal input restoration-to-publication region
may allocate, poll, process pending actions, exit a handler, invoke a callback-
capable operation, perform fallible work, or leave through an unreviewed
target. The reviewed validated direct byte copy is the only operation
permitted in the positive interval besides the required cursor and state
mutations.

Map the private external declaration and saturated copy call in
`plan9_in_channel.ml` through the exact target `plan9_in_channel.cmo`
`C_CALL5 caml_blit_bytes` opcode and runtime symbol. Record the channel source
and object plus runtime source and object identities, the bounds facts that
dominate all five arguments, the `[@@noalloc]` declaration, and the runtime
`memmove`-only complete path. Include the recorded target interpreter object
and reviewed `runtime/interp.c` `C_CALL5` path in this proof, including its
`Setup_for_c_call`, primitive dispatch, restore, and return. Prove that there
is no cross-unit wrapper `APPLY`, stack check, signal/pending-action poll,
callback, allocation, or fallible operation from the direct call through
unread-cursor advancement, stable-state restoration, and result publication.
If the target bytecode uses a wrapper, different opcode, or different
placement, stop because the required handler-exit and mutation-to-publication
boundaries have not been proved. A declaration, named call, source annotation,
CMO relocation, or final symbol without matching target artifacts, opcode
semantics, bounds proof, and complete reachable-path analysis is not proof.

For close, map the channel's final stable-open recheck and active-state install,
its `PUSHTRAP`, the lower call, normal channel terminalization writes, handler-
exit `POPTRAP`, terminal-flag handler branch, and later wrapper mapping. On the
first production lower-close path from `Attached`, also map allocation of the
distinct descriptor-owner close attempt and `Owner_closing` value followed by
the descriptor's own final state/token recheck. Continue the production lower-
error path from normal primitive return through descriptor-owner
terminalization, `native_error` construction, and either normal lower return or
an exception. Prove that the first two lower attempt/state allocations occur
after channel active-close state and the channel `PUSHTRAP` are in place and
before lower terminalization begins. Prove separately that native-error
construction after descriptor terminalization may allocate, remains inside
the channel handler while the channel-owned terminal flag is false, and lies
before the second allocation-free channel region. The two protected channel
regions are the final stable-open-recheck-to-active-install region and the
normal-lower-return-to-channel-terminalization region. An exception during
lower native-error construction must reach the channel's inactive-retry
transition without rolling back the terminal descriptor, and the retry must
observe the lower descriptor's idempotent terminal result. Prove that
`POPTRAP` can process pending actions before removing the handler; that it does
so only after the channel-owned attempt and channel are terminal and cursors
are discarded; that a callback exception reaches the terminal-preserving
`RERAISE`; and that any other pre-return lower exception reaches the inactive-
retry transition instead. Prove that the retained lower result, channel-owned
attempt, and channel remain rooted through the pending-action event frame.
Mapping after normal handler exit must be unable to reach either exception
branch.

For every channel lifecycle, close-attempt, or unread-cursor mutation in a
protected region, map the target bytecode field-write opcode through the exact
recorded interpreter object and its reviewed `runtime/interp.c` `SETFIELD`
path into `caml_modify`. Review `runtime/memory.c`,
`runtime/caml/minor_gc.h`, and `runtime/minor_gc.c` plus the exact recorded
`memory` and `minor_gc` objects. Prove at each write that both the overwritten
value and replacement value are immediate and that every separate stable
block-valued field is untouched. Consequently no major-heap darkening,
remembered-set insertion, minor-collection request, remembered-set resize, C
allocation, callback, poll, or fallible path is reachable from those writes.
A block-valued old or new lifecycle/cursor value, an untraced field write, or
an object/source mismatch stops qualification.

Separately map the production `Plan9_fd.commit_attach` state write through the
same `SETFIELD`/`caml_modify` implementation. Its overwritten
`Open_detached` value must be immediate and the block-valued prepared
replacement must be proved non-young as a consequence of the explicit rooted
minor collection and absence of later candidate replacement. Prove that this
exact heap-age pair bypasses both darkening and remembered-set insertion, so
no collection request, table resize, C allocation, callback, poll, or fallible
work remains between the lower final recheck and publication. A missing root,
later candidate replacement, young replacement, callback after the lower
final recheck, or unproved commit opcode path stops qualification.

Map the two unit-scoped retained-result bindings through two distinct regions.
First map unit-initialization materialization from each `Texp_construct`
through `Translcore`'s `Cstr_block` constant-argument path to
`Lconst (Const_block ...)`, then through the CMO's symbolic `Reloc_literal`,
final executable resolved constant, `DATA` loading, startup oldification, and
bytecode global-root scan; for this materialization region, do not require a
numeric final global slot that standard `dumpobj` does not print. Then map the
actual compiler-selected binding route, including any compilation-unit global-
field substitution, closure capture, or other proved identity-preserving
lowering, and every zero-input and terminal-close fast path
from its lifecycle decision through the resulting `ENVACC`, `ACC`, global-
field, or other proved identity-preserving nonallocating access and publication
of the appropriate exact binding. Accept a literal-global access only when
compiler and artifact evidence proves that it resolves to that same stored unit
binding; structural equality or per-type runtime identity alone is
insufficient, and inability to recover the hidden final slot is not a waiver.
Per-type runtime identity corroborates reuse across calls and `Make` instances;
no cross-type identity result is required. No fast path may contain
`MAKEBLOCK`, another allocation, a functor or unit initializer call, a poll,
pending-action processing, or an unreviewed branch.

Map `Gc.minor` from its `stdlib/gc.mli` external declaration and the exact
selected `stdlib__Gc.cmi` through the reviewed saturated-primitive compiler
lowering into the `plan9_in_channel.cmo` and executable direct
`C_CALL1 caml_gc_minor`. Map that opcode through the recorded `interp` object
to the recorded `gc_ctrl` object, requested minor collection, `minor_gc`
dispatch, and exact bytecode-root scan in `roots_byt` through stack, local C,
and global roots. Prove that this caller path contains no `APPLY`, stack check,
or `CHECK_SIGNALS` before primitive entry. Follow promotion through
`globroots`, `memory`, and `freelist` as reached by the target, and map the
reachable `major_gc` slice plus the `signals`, `memprof`, `finalise`, and
`callback` pending-action and OCaml-callback path. Establish from `gc_ctrl`
and `signals` that the requested urgent minor collection runs before signal,
memprof, or finalizer callbacks. Prove that every candidate remains rooted
through the direct C call, that normal stabilization promotes it before any
later pending OCaml callback, and that it remains non-young through the later
commit application boundary.

On the stabilization primitive's exception-result path, continue from
`gc_ctrl`'s `caml_raise_if_exception` through the recorded `fail_byt` object
and `caml_raise`. Map `caml_raise`'s additional
`caml_process_pending_actions_with_root_exn` pass, including every callback it
can invoke and the possibility that a later pending callback replaces an
earlier callback's exception, through the interpreter's external-raise/trap
path. The channel's physical-identity promise is to propagate without wrapping
or substitution the final exception value selected by the pending-action
passes actually executed on this runtime path and presented to the ML caller;
it does not promise that the first callback exception wins, that all pending
callbacks ran, or that the pending-action queue was drained. Review the
exception branch in `runtime/signals.c` that re-arms pending work when a
callback raises. For an exception arising at the post-stabilization
`commit_attach` application boundary, map its actual `interp`/`stacks` or
`signals` origin through `fail_byt` without inventing a `gc_ctrl` edge. A
stack-limit or pending-action exception there, before lower entry, performs no
commit or cleanup close and lets no channel escape.

Separately enumerate every reachable function-pointer site on this path,
including minor-collection begin/end hooks, the root-scan hook, major-GC and
major-slice hooks, finalization begin/end hooks, and minor custom-block
finalizers. For the exact linked executable, either prove a site remains null
or unreachable, or record the installed target implementation and map its
complete behavior. Do not treat the pending-action dispatcher as the only
callback-capable part of `Gc.minor`: custom finalizers and runtime hooks can
run during collection or a major slice. Prove that every such reachable point
precedes `commit_attach`'s internal final recheck and that a stabilization
exception reaches no commit or cleanup close. An unenumerated hook, custom
finalizer, root scanner, promotion allocator, major-slice edge, or callback
dispatcher stops qualification.

Exception restoration must use ordinary `RERAISE` when a handler is required;
transparent uncaught precommit propagation is accepted and must not be
misclassified as a missing reraise. An incomplete, unmappable, allocating,
polling, callback-capable, or contradictory audit stops qualification.

Use `phase2_1_001` for the first qualification attempt's new `TEST_SUFFIX`.
For every later complete-suite rerun, increment the three-digit suffix and
record the new previously unused value. Each value satisfies the required
1-40 ASCII letters, digits, or underscores. After the immediately preceding
qualification-clean environment record and unset plus GNU Make no-injection
proof, run the first attempt with:

```text
"$MAKE" -C otherlibs/plan9 TEST_SUFFIX=phase2_1_001 test
```

The completion evidence records the actual literal suffix, command, complete
output, and status. Require the new focused tests and all regressions to pass,
then inspect the archive, installed-file selection logic, primitive inventory,
symbols, runtime lanes, and descriptor cleanup relevant to this checkpoint.
No installation is needed in Phase 2.1.

#### Authoritative retry rule for Phase 2.1 qualification

The standard-library CMI reproduction and Plan 9 forced rebuild, consumer
probe, `dumpobj` and symbol production and capture, primitive-table audit,
tests, and remaining qualification audits are evidence-producing lanes, not
guest source-editing
lanes. Preserve the exact command, environment, complete output, status,
canonical guest path, relevant input/output artifact identities, and
postconditions for every attempt. A nonzero, interrupted, unknown, incomplete,
path-incomplete, unmappable, or contradictory result stops the current
qualification attempt and cannot be hidden by a later successful subset.

Do not edit implementation, interface, Makefile, test, generated dependency,
standard-library, or runtime source bytes in the guest and do not repair an
object, executable, primitive table, or log in place. If a failure exposes a
source defect, make the correction only in the authoritative Windows checkout,
invalidate the prior final host review, manifests, native source identity, and
all later qualification evidence, and repeat the applicable dependency-
generation/return gate, complete host review, exact transfer, and final native
source-manifest comparison before beginning a new qualification attempt.

If no source correction is required and the cause is confined to an approved
environment, tool, capture, or build artifact, preserve the failure, restore
and prove every guest-global postcondition, recheck the unchanged final Windows
source and executable-mode manifests, exact native source identity, and tool
identities, and decide whether the same confirmed retained native tree remains
safe to reuse. A safely reusable tree must repeat the complete Phase 2.1
qualification from the target-scoped
`stdlib__Gc.cmi` reproduction onward; do not resume
only at the failed producer. If safe reuse cannot be proved, return to explicit
VM and native-path confirmation before selecting a new absent source/build
destination and applying the accepted Phase 1.3 common creation-and-ownership,
source-transfer, executable-mode, and manifest gates. Population alone does
not make that new tree a qualification input.

Before configuring a replacement tree, obtain user agreement on its exact
configuration prefix even though Phase 2.1 performs no installation. Record
whether that prefix is the accepted Phase 1 development prefix or another
explicitly approved read-only dependency, preserve complete before/after
inventories, and prove that the known-working protected prefix remains
unchanged. The prefix must already provide the effective ordinary-link
`stdlib.cma` and `std_exit.cmo`, compilation-time `stdlib.cmi` and other
imported standard-library CMIs, and link-time `camlheader` selected by the new
source-tree compiler, together with a record of `ld.conf` as the exact regular
file selected there or as proved absent. Phase 2.1 must not install or overlay
a prefix merely to make its consumer probe work. If no suitable unchanged
prefix is approved and present, stop for a separately reviewed qualification
plan rather than expanding this subphase.

In the exact documented `ape/psh` environment with the recorded GNU Make
executable, re-establish and immediately record the producer-clean environment
before each command that configures or establishes the replacement tree, and
apply the configure-clean gate above immediately before `configure.sh`. The
agreed prefix below is the only additional literal command argument authorized
by this paragraph. Configure and establish the tree with these command shapes
from its repository root, substituting that prefix literally:

```text
build-aux/plan9/configure.sh --prefix=<agreed configuration prefix>
build-aux/plan9/build-world.sh
```

This replacement-tree world build begins only after dependency generation and
authoritative return have produced the final reviewed `.depend` and the final
source manifest has been selected. It is not the pre-dependency core-bootstrap
lane for an initially new tree, and it must prove that the final dependency
edges are present before compiling `plan9_in_channel.ml`.

Preserve both exact commands, producer-clean and configure-clean environments,
complete outputs, statuses, configured paths, source manifests, and resulting
bootstrap/runtime/compiler/standard-library identities. For `build-world.sh`,
prove that every GNU Make process satisfies the top-level and recursive no-
injection rule above.
Require exact zero for both commands and prove the agreed and protected
prefixes unchanged before beginning the new Phase 2.1
qualification at the target-scoped standard-library CMI reproduction. A
nonzero,
interrupted, unknown, incomplete, path-incomplete, or contradictory configure
or world-build result rejects that replacement tree; retain it under the
recorded failed-tree postcondition and begin any later attempt with another
new absent destination. Do not treat replacement-tree establishment as a
same-artifact recapture or resume at a later producer.

Every new qualification attempt uses a new absent consumer-directory path and
the complete creation-and-ownership gate above; never reuse a failed consumer
workspace as an input. If a complete-suite command was invoked in the prior
attempt, its suffix is consumed regardless of result and the next full-suite
run uses the next previously unused three-digit suffix. A failure before any
complete-suite invocation does not consume that unused suffix.

Only a failed capture of otherwise successful, strictly read-only evidence may
be repeated against the same artifacts. Before recapture, prove that the
producer's status was exactly zero and that the capture cannot modify source,
build products, consumer workspaces, configured or protected prefixes, or
guest-global state. Require every input artifact and capture tool to retain its
recorded canonical absolute path and complete Phase 1.3 common-schema identity
tuple: entry type, mode, server type and device, Qid type/version/path,
ownership fields, decimal byte length, and content hash. When an input belongs
to an inventoried tree, also require its canonical root and raw root-relative
path to match that inventory. Preserve both captures and every comparison.
Otherwise begin a complete new qualification attempt under the rules above.
Record every failed attempt and consumer workspace's retained or explicitly
authorized removed postcondition in the completion evidence.

If final host review changes a transferred source byte, invalidate the native
result and repeat from an exact reviewed source set. Do not silently patch the
guest tree.

After the final successful qualification producer, audit, and test has stopped
all writes, canonically re-resolve the successful source/build root and record
its complete final Phase 1.3 common-schema identity inventory, final source and
mode manifests, build-artifact inventory, configuration and tool identities,
and read-only dependency-prefix identity. Only a tree whose selection,
ownership or authorized reuse, source identity, establishment when applicable,
and complete Phase 2.1 qualification all succeeded is eligible for the
accepted Phase 2.1 tree label. Do not assign that label until the exact-tree
disposition and final VM shutdown gate below have also completed successfully.

Obtain an explicit disposition for that exact tree. If retained for Phase 2.2,
record its canonical path, final identity, project ownership, and pending
designation as the uniquely selected retained Phase 2.1 tree. Phase 2.2 may
reuse it only after the shutdown gate assigns the accepted label and only when
its start gate matches the resulting evidence.
If the user instead separately authorizes exact-path removal, apply the
accepted common-schema identity and removal proof and record final absence;
source/build-tree creation, reuse, or qualification authority does not imply
removal authority. Without explicit removal authority, retain the tree. A
failed, rejected, incomplete, or identity-uncertain tree must not receive the
accepted label or be represented as the Phase 2.2 predecessor.

#### Final VM shutdown and handoff gate

After every guest write, evidence producer, test, and any separately authorized
tree removal has stopped, obtain fresh user confirmation of the exact writable
P9QEMU instance, leased loopback address, and intended shutdown action. The
earlier confirmation to start or use the VM does not authorize this shutdown.
Before acting, reidentify the P9QEMU/Python/QEMU process chain, exact QEMU PID,
writable disk, selected address, accelerator, and all seven listeners.

Halt that selected guest through an address-specific Drawterm `fshalt`. Record
the exact CPU and authentication endpoints, command, complete output, and exit
status. Wait for that exact QEMU PID to exit; then verify that its complete
P9QEMU/Python/QEMU process chain has ended, all seven listeners on the selected
address have closed, and no live QEMU process owns the writable disk. Never
broad-kill by executable name. Never copy, move, hash, inspect, or checkpoint a
live writable disk. A post-halt checkpoint requires separate authorization and
may begin only after the shutdown evidence is complete.

This shutdown gate applies whether the source/build tree was retained or
removed. If `fshalt` fails, returns nonzero, is interrupted, or leaves any PID,
listener, disk ownership, or shutdown result uncertain, withhold the accepted
Phase 2.1 label and do not begin Phase 2.2. Preserve and report a shutdown-
failure handoff containing the exact instance, leased address, accelerator,
process identities, QEMU PID, listener state, writable-disk state, serial-log
path when present, failure evidence, and next required action. If the exact
QEMU process remains live, classify it as a live-VM handoff and do not describe
it as halted. If the exact PID has exited, the process chain has ended, all
seven listeners have closed, and no live QEMU owns the disk, record that actual
host-terminated state while marking clean guest shutdown unconfirmed; do not
call it an accepted clean halt. If any host state remains uncertain, record the
uncertainty and perform no disk copy, move, hash, inspection, or checkpoint.

Only after exact-tree disposition, all descriptor/process/temporary-resource
and guest postconditions, and every shutdown check have succeeded may the tree
receive the accepted Phase 2.1 label. A retained tree then receives its final
designation as the unique Phase 2.1 predecessor eligible for Phase 2.2. An
authorized removed-tree disposition records final absence and the accepted
Phase 2.1 result, but supplies no retained predecessor to Phase 2.2.

### 6. Report and stop

Report the complete evidence and stop. Do not begin Phase 2.2, commit, push,
install, merge, or publish unless the user explicitly asks.

## Completion report

Report:

- exact foundation, roadmap, and handoff paths;
- exact branch, starting `HEAD`, reviewed documentation checkpoint, tested
  source identity, and final Git state;
- files added/changed and why;
- exact initial VM/native-tree confirmation; selected canonical source/build
  root and retained-versus-new branch; intended action; configuration prefix;
  retained Phase 1.3 provenance, accepted-identity reconciliation, ownership,
  disjointness, prerequisite, and complete pre-transfer inventory evidence, or
  new-tree absence, creation, canonical re-resolution, ownership, emptiness,
  disjointness, pre-dependency configure/core bootstrap, post-return final-
  source world build, post-core and post-world source/mode rechecks, producer-
  clean, configure-clean, no-site/no-cache, effective configure-variable,
  no-injection, dependency-edge, prefix-unchanged, and rejected-path sentinel
  evidence as applicable;
- internal `Descriptor`, `S`, channel, attachment, state, and buffer shapes,
  including immediate-only mutable lifecycle, close-attempt, and cursor fields
  separated from stable block-valued fields;
- preparation, post-preparation allocation, rooted direct
  `C_CALL1 caml_gc_minor` stabilization, promotion, callback/finalizer,
  repeated pending-action/raise, executed-pass final-runtime-exception
  identity without a queue-drain claim, intervening public-I/O predecessor and
  conditional callback evidence with commit-time ownership linearization,
  later `commit_attach` application and stack-growth boundaries, complete
  preallocated and rooted enclosing success and lost-commit results, the
  allocation-/poll-/callback-/pending-action-/fallibility-free post-`false`
  publication suffix, preallocated channel close-attempt evidence, and distinct
  accepted lower descriptor-owner close-attempt allocation, terminalization,
  and post-terminal native-error-construction evidence;
- every error operation/kind/message and lower-error mapping result;
- accepted-shape and adversarial-`Descriptor` callback, exception, malformed-
  result, cursor-recovery, zero-fast-path, physical-buffer, GC, and call-count
  results, including physical identity and allocation-free target bytecode for
  the unit-scoped retained zero-input and terminal-close successes, their CMO
  `-reloc` and executable resolved-constant/global-data provenance, compiler-
  selected identity-preserving binding routes and actual nonallocating access
  opcodes, conditional literal-global same-binding proof, and per-type cross-
  `Make` identity without treating the absence of a printed hidden slot,
  structural equality, or runtime identity alone as binding-provenance
  evidence and without a cross-type identity claim; mandatory source/
  disassembly proof for both handler-`POPTRAP` pending-callback schedules;
  either each conditional runtime schedule's recovery,
  terminal-preservation, identity, and retry result or its exact unavailable/
  skipped static-only record; and the before-lower-terminal and after-lower-
  terminal close-exception schedules, including the production post-terminal
  native-error-construction path, and exact retry traces;
- transfer-set basis, exact four additions and no deletion, baseline tracked
  index/mode inventory, the four explicit `100644` new-path entries, complete
  untracked/ignored inventories, `.git`/gitlink/build-artifact exclusions,
  selected manifest/hash algorithm and tool identities, matching pre-
  generation and final Windows/native source and mode manifests, retained-
  artifact inventory, and every invalidation/retransfer cycle;
- target-native `stdlib__Gc.cmi` reproduction command, complete log, status,
  expanded rule/compiler selection, launcher and compiler-bytecode paths and
  identities, `Gc` source/interface identities, compiler selection and
  `Translcore` `Texp_construct`/`Cstr_block`/`Const_block` retained-result path,
  `Translcore`/`Translprim` primitive- and reraise-lowering source/artifact
  provenance, `Matching`/`Simplif`/`Translmod` retained-result materialization
  and binding-access source/artifact provenance, plus the source-tree
  `stdlib.cma` identity and exact proof that each focused Plan
  9 link selected that archive without claiming a `Gc` wrapper dispatch;
- target-native Plan 9 forced-rebuild provenance plus `dumpobj` and
  `ocamlobjinfo` source/tool/runtime identities, complete tool-build logs and
  `make_opcodes.mll`/generated `make_opcodes.ml`/generator/`instruct.h`/
  `opnames.ml`/`opnames.cmo` provenance, `plan9_in_channel.cmo` and native-I/O-
  executable identities, the CMO's complete imported-interface names, CRCs,
  resolved CMI identities, required local and `Stdlib__Gc` matches, and
  `Plan9_primitive` absence, complete disassembly and ordered
  `Primitives used` evidence locations, proof that the displayed order
  reverses serialization, displayed count `N`, positions `d_blit` and `d_gc`,
  computed executable indices, and linked `C_CALL5`/`C_CALL1` numeric
  correlations,
  generated `runtime/primitives`, `prims.c`, `prims.<O>`, runtime
  `str`/interpreter/startup/intern/dynlink/memory/minor-GC/GC-control/signals/
  memprof/finalizer/bytecode-roots/global-roots/freelist/major-GC/callback/stacks/
  bytecode-failure/misc/custom objects plus every target-derived transitive
  addition, archive, and executable identities and linkage, builtin-primitive
  listing, complete generated-table uniqueness/order and startup name-
  resolution chain, mapped
  critical control-flow regions and boundary PCs, complete branch/switch
  coverage, allocation/callback/safe-point audit, exact input result/copy/
  cursor/restore/publication ordering including active input `POPTRAP` before
  mutation, rejection-path no-restoration proof, exact private direct
  `caml_blit_bytes` declaration/`C_CALL5` path and exact `Gc.minor` external,
  selected-CMI, compiler-lowering, direct-`C_CALL1`, and `caml_gc_minor`
  source/object/symbol proofs, direct-opcode and later-application stack-
  growth/pending-action/finalizer/repeated-raise-dispatch placement, final-
  runtime-exception
  executed-pass identity anchor and remaining-pending-work caveat,
  precommit promotion and production-commit heap-age/write-barrier proof,
  successful mutation-to-publication path, channel `SETFIELD`/`caml_modify`
  immediate-value proof with no darkening or remembered-set path, close
  terminalization/`POPTRAP`/mapping boundaries, terminal-flag exception split,
  retained-result constant/literal-relocation/`DATA`/global-root provenance
  with per-type repeated-call and cross-`Make` identity only, and `RERAISE`
  evidence;
- exact lifecycle and native-I/O link orders and runtime lanes, resolved
  `$(OCAMLRUN)`, source-tree `ocamlc`, and `$(NEW_OCAMLRUN)` paths, identities,
  expanded command order, forced-rebuild command/log, actual new `TEST_SUFFIX`,
  qualification-clean environment including explicit `BUILD_PATH_PREFIX_MAP`
  and `OCAML_BINANNOT_WITHENV` unset evidence, plus the immediate unset and GNU
  Make no-injection proof for every evidence producer, complete-suite command/
  output/status, and unchanged bootstrap process-state lane;
- native binary, buffer-split, EOF, alias, close, and `/fd` cleanup results;
- complete regression results;
- exact dependency-generation command, producer-clean environment and GNU Make
  no-injection proof, tools, expanded recipe, output, status, pre/post/returned
  artifact identities, failure/recovery history, and exact three-stanza
  `.depend` delta with every predecessor stanza unchanged;
- archive order, primitive, ML-only, installed-CMI selection, force-linked
  initialization source audit including the unit-scoped retained normal-result
  bindings, executable-global materialization, and absence of descriptor/native
  work, and isolated staged-consumer
  canonical path,
  disjointness/absence/exact-zero creation/task-ownership gate, collision or
  selected-but-not-created sentinel and no-action proof when applicable,
  initial/exact-three-file-precompile/final inventories, qualification-wide
  clean environment and per-producer unset proofs, exact launcher-plus-compiler
  and execution-runtime commands,
  paths, identities, and argument order, compiler `-where` result and canonical
  standard-library root, effective `stdlib.cma`, `std_exit.cmo`, `stdlib.cmi`,
  `camlheader`, and `ld.conf` identity-or-absence evidence, consumer-CMI
  `ocamlobjinfo` output with imported names/CRCs and approved-root resolution,
  staged and imported artifact identities and post-evidence re-hashes, unset
  compiler/runtime/debugger control variables, result/status, read-only post-
  probe consumer evidence, and retained or explicitly authorized exact-path
  removal postcondition;
- every qualification attempt's command/environment/output/status, canonical
  paths, artifact identities, failure classification, invalidation and
  retransfer history, safe retained-tree reuse or replacement decision,
  replacement-tree creation/configuration-prefix/configure/world-build
  producer-clean, configure-clean, no-site/no-cache, effective configure-
  variable, and GNU Make no-injection evidence and rejected-tree
  postconditions, complete-rerun boundary, consumed test suffixes, full common-
  schema same-artifact recapture comparisons, and rejected consumer-workspace
  postconditions;
- successful source/build root canonical re-resolution, complete final common-
  schema identity and build-artifact inventories, final source/mode manifests,
  configuration/tool/read-only-prefix identities, accepted Phase 2.1 tree-
  label decision, exact retain-or-separately-authorized-remove disposition,
  and, when retained, project ownership and explicit Phase 2.2 handoff
  identity;
- accepted Phase 1.3 and rebuilt public `plan9.cmi` paths, sizes, hashes, and
  byte-for-byte identity result;
- guest release/architecture; fresh shutdown confirmation; exact P9QEMU
  instance, leased address, accelerator, P9QEMU/Python/QEMU process identities,
  QEMU PID, writable disk, and seven-listener state; address-specific Drawterm
  CPU/authentication endpoints and exact `fshalt` command, output, and status;
  exact-PID exit, process-chain disappearance, listener-closure, and no-live-
  disk-owner proofs; any separately authorized post-halt checkpoint evidence;
  and any shutdown failure, actual live/host-terminated-with-clean-shutdown-
  unconfirmed/uncertain classification, required shutdown-failure or live-VM
  handoff, and withheld-label result;
- every skipped gate, deviation, uncertainty, and open criterion; and
- one conclusion: accepted Phase 2.1 checkpoint, implementation awaiting
  native qualification, or blocked/rejected with exact reason.

## Strict exclusions

This subphase does not include:

- `input_line`, `input_all`, `input_lines`, limit policy, or line parsing;
- public `Plan9.In_channel` re-export or public documentation;
- installation, prefix mutation, or installed-consumer tests; read-only
  identity and unchanged-state evidence for an approved configuration prefix
  is a qualification dependency only;
- changes to `Plan9.Fd`, `Plan9.Process`, `Plan9.Raw`, or `Plan9.Env` semantics;
- new primitives, raw syscalls, runtime C, process migration, capture, or
  command convenience;
- ordinary channels, raw descriptors, standard input, file opening, seeking,
  positions, length, text translation, channel finalizer registration, or
  automatic GC-driven channel cleanup; runtime hook, custom-finalizer, and
  pending-finalizer behavior reached by the explicit stabilization remains in
  scope for the qualification above;
- note injection, a new primitive, a test-only native hook, or a production
  hook used to force either handler-exit `POPTRAP` schedule; or
- snapshots, checkpoint replacement, branch merge, release publication, or
  Caml9 changes.

If excluded work appears necessary, stop and report the evidence.
