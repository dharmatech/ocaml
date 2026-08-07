# Phase 2.1 `Plan9.In_channel` ownership and buffered input handoff

Status: proposed focused handoff for review; implementation has not begun

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

`of_fd` uses operation name `Plan9.In_channel.of_fd` and follows this exact
sequence:

1. Call `Fd.Private.prepare_attach` for the supplied descriptor.
2. If preparation fails, return an `Invalid_argument` under the public
   `Plan9.In_channel.of_fd` operation, preserving the accepted message
   `descriptor is not open and detached` and exposing no private operation
   name.
3. After successful preparation, allocate and initialize the fixed private
   scratch buffer, complete channel state, stable and active state markers,
   commit-lost error, and enclosing `Ok channel` result.
4. Initialize every scanned field to a GC-safe value before any later
   allocation.
5. Call `commit_attach` only after all success-side allocation has completed.
6. If commit returns `true`, return the preallocated success immediately with
   no allocation, callback, safe point, or other fallible work.
7. If commit returns `false`, return the preallocated
   `Plan9.In_channel.of_fd` `Invalid_argument` error with message
   `descriptor is not open and detached`; the failed channel does not escape.

Preparation does not reserve the descriptor. An allocation callback may close
the public alias or commit a competing token before this channel commits. A
failed `of_fd` therefore does not promise that the caller's descriptor remains
operational; the shared cell retains the exact state established by the
competing actor. A successful result means this channel's exact token owns the
cell and all retained public aliases are permanently revoked.

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

The representation may use preallocated state values and a close-attempt
record, but it must satisfy these rules:

- every public input-family operation validates its pure arguments first;
- immediately before changing open to active, it rechecks stable open state;
- active state covers the entire high-level operation, including allocations,
  buffered copying, delimiter scans in later phases, and every lower read;
- reentrant input while any input operation is active returns
  `Invalid_argument`, message `input channel operation is already in progress`,
  under the reentrant operation, without a lower read or buffer mutation;
- reentrant close during active input returns the same in-progress message
  under `Plan9.In_channel.close`, without lower close;
- input during active or inactive close returns `Invalid_argument`, message
  `input channel close is already in progress`, without lower read;
- input after terminal close returns `Invalid_argument`, message
  `input channel is closed`, without lower read;
- every normal input result restores stable open before publication; and
- every arbitrary exception restores stable open before re-raising the exact
  caught exception through ordinary `RERAISE`, with no wrapping or stale-state
  overwrite.

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
  without using the count as an index or copy length.

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

- zero length still checks that the channel is stably open, then returns a
  retained `Ok 0` without buffer movement or lower read;
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

Allocate every nonzero successful `Ok count` before advancing the unread cursor
or copying into the caller buffer. After a successful refill, first describe
the complete validated fill with the channel cursors, then allocate that
call's success while the channel remains active; if allocation raises, stable
state is restored with every newly read byte still buffered for a later call.
The retained zero success requires no allocation. No acceptance claim is made
that arbitrary `Out_of_memory` is converted to `Plan9.error`.

## Deterministic close

`close channel` uses operation `Plan9.In_channel.close`.

From stable open:

- allocate the close-attempt representation before changing state;
- recheck stable open immediately before installing active close;
- call `Fd.Private.close` exactly once through the committed token;
- on any normal `Ok` or `Error`, transition allocation-free to terminal
  closed before mapping and returning the result;
- remap a lower error's operation to `Plan9.In_channel.close` while preserving
  kind and exact native message; and
- discard any unread buffered data as part of channel close.

During active close, reentrant close returns `Invalid_argument`, message
`input channel close is already in progress`, without nested lower work.
After terminal close, repeated close returns retained `Ok ()` without lower
work.

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
| reentrant input-family operation | invoked input operation | `Invalid_argument` | `input channel operation is already in progress` |
| close during active input | `Plan9.In_channel.close` | `Invalid_argument` | `input channel operation is already in progress` |
| input during active/inactive close | invoked input operation | `Invalid_argument` | `input channel close is already in progress` |
| input after terminal close | invoked input operation | `Invalid_argument` | `input channel is closed` |
| close during active close | `Plan9.In_channel.close` | `Invalid_argument` | `input channel close is already in progress` |
| malformed fill count | invoking input operation | `Protocol_error` | `invalid input buffer fill result: buffer length {buffer_length}, returned count {count}` |

Lower failures preserve kind and message but are always rebound to the
invoked channel operation. Do not leak `Plan9.Fd.Private.prepare_attach` or
`Plan9.Fd.read` as a public-facing operation.

## Build and dependency integration

Add `plan9_in_channel.cmo` after `plan9_fd.cmo` and before
`plan9_process.cmo` in `CAMLOBJS`:

```make
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo \
  plan9_in_channel.cmo plan9_process.cmo plan9.cmo
```

`plan9_in_channel` depends on `Plan9_types` and `Plan9_fd`, never on the
`Plan9` umbrella or `Plan9_primitive`. No cycle is permitted.

Wire both new focused tests into the ordinary Plan 9 test inventory. The
lifecycle test links private CMIs/CMOs and exercises the functor; the native
I/O test links the source-tree `plan9.cma` and private CMI as needed until
Phase 2.4 publishes the umbrella. Neither test is installed.

Make hand-written source and Makefile changes in the authoritative Windows
checkout, but never hand-edit `.depend`. Generate dependencies only on native
Plan 9 storage using the configured target compiler and documented APE/GNU
Make lane. Bring back and review only the generated `.depend` file, then prove
its source reasons. If dependency generation changes anything else, stop and
report it.

The archive remains ML-only. This subphase adds no primitive name, runtime
object, C object, C option, dynamic library, or installed CMI.

## Required fake-backend tests

`in_channel_lifecycle_test.ml` should compose `Plan9_fd.Make` with a counted
fake primitive and instantiate `Plan9_in_channel.Make` over that `Fd` module.
At minimum, prove:

- successful `of_fd` commits exactly one token and revokes every public alias;
- preparation failure and deliberately lost commit return the exact public
  error and do not let the failed channel escape;
- allocation callbacks before commit may close or attach the descriptor, and
  final commit never overwrites the competing state;
- one scratch buffer is reused across refills;
- invalid ranges `(-1,0)`, `(0,-1)`, `(buffer_length+1,0)`,
  `(buffer_length,1)`, `(max_int,1)`, and `(1,max_int)` return the exact error
  before lifecycle or lower work;
- authorized `(buffer_length,0)` returns zero without buffer movement or lower
  read, while closed and closing channels reject it;
- buffered input returns without a lower read and retains unused suffix bytes;
- an empty buffer causes exactly one lower read even when the logical request
  is larger than the scratch capacity;
- positive short reads, embedded NUL, zero EOF, and arbitrary caller offsets
  preserve exact bytes and untouched prefix/suffix regions;
- negative and oversized fake counts produce the exact protocol error without
  an out-of-bounds access or caller mutation;
- lower errors retain kind/message, use `Plan9.In_channel.input`, and are not
  retried;
- repeated EOF calls may perform later lower reads and can observe later fake
  data;
- active-input callbacks attempting input, close, public `Fd` operations, or
  token operations receive their exact accepted rejection and make no nested
  lower call;
- a designated allocated exception raised by lower read restores stable
  channel and descriptor state and is re-raised with physical identity;
- close callbacks cover active close, input rejection, reentrant close,
  exception-left inactive retry, normal native error terminalization, and
  repeated terminal close; and
- forced minor collection, full major collection, and compaction around live
  channels, active markers, buffered data, and close attempts do not lose or
  duplicate ownership.

Use fake callbacks for timing-sensitive or impossible outcomes. Add no
production fault switch.

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
Actual timing-sensitive note interruption remains outside this checkpoint
unless separately authorized.

## Source and packaging review

Before VM work, inspect and record evidence that:

- every `of_fd` success-side allocation precedes commit;
- no callback, allocation, or safe point occurs between successful commit and
  return of the preallocated success;
- commit loss cannot leak a channel or overwrite competing descriptor state;
- all buffer cursor arithmetic is ordered and bounded before indexing;
- input range validation precedes lifecycle and lower work;
- one public `input` performs at most one refill and never retries failure;
- active state encloses every mutation-sensitive operation and exception paths
  restore the exact stable state before reraise;
- close follows the accepted owner-close terminal and inactive-retry boundary;
- no public alias is restored after attachment;
- the new module depends only on accepted private predecessors;
- the primitive table and runtime object set are unchanged;
- `plan9.cma` contains ML only; and
- `CMIFILES` remains exactly `plan9.cmi`.

No claim should exceed the accepted APE-independent descriptor path. Existing
`Plan9.Env`, `Sys`, `Unix`, and unrelated runtime operations retain their
documented APE behavior.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state, implement only the authorized source boundary, run safe
host-side text/diff checks, and leave generated `.depend` untouched.

### 2. Complete host review

Inspect every changed line, authorized path, module dependency, error template,
buffer invariant, callback boundary, and test expectation. Report the proposed
source and any discrepancy to the user.

### 3. Explicit VM confirmation

Stop and obtain user confirmation of the exact writable instance, unique
loopback address, intended start/use action, and WHPX profile. Inspect the
P9QEMU/Python/QEMU chain, exact QEMU PID, address, disk, and seven listeners as
required by repository policy. Do not start or reuse another project's VM.

### 4. Native dependency generation and authoritative return

Transfer the reviewed source set without `.git` through `/mnt/term`, copy it
to native Plan 9 storage, enter APE through `ape/psh`, use the exact shell setup
from `build-aux/plan9/README.md`, resolve the actual GNU Make executable, and
generate `.depend` with the target compiler. Return only that generated file
to the authoritative Windows checkout, inspect its diff, and repeat host
review. Do not approximate the APE namespace manually.

### 5. Native qualification

Return the final reviewed source set to native storage, build in the accepted
APE/GNU Make lane, run the new focused tests and all regressions, inspect the
archive, installed-file selection logic, primitive inventory, symbols, and
descriptor cleanup relevant to this checkpoint. No installation is needed in
Phase 2.1.

If final host review changes a transferred source byte, invalidate the native
result and repeat from an exact reviewed source set. Do not silently patch the
guest tree.

### 6. Report and stop

Report the complete evidence and stop. Do not begin Phase 2.2, commit, push,
install, merge, or publish unless the user explicitly asks.

## Completion report

Report:

- exact foundation, roadmap, and handoff paths;
- exact branch, starting `HEAD`, reviewed documentation checkpoint, tested
  source identity, and final Git state;
- files added/changed and why;
- internal `Descriptor`, `S`, channel, attachment, state, and buffer shapes;
- every error operation/kind/message and lower-error mapping result;
- fake-backend callback, exception, GC, and call-count results;
- native binary, buffer-split, EOF, alias, close, and `/fd` cleanup results;
- complete regression results;
- `.depend`, archive order, primitive, ML-only, and installed-CMI evidence;
- guest release/architecture, VM instance/address/PID/listeners/disk state;
- every skipped gate, deviation, uncertainty, and open criterion; and
- one conclusion: accepted Phase 2.1 checkpoint, implementation awaiting
  native qualification, or blocked/rejected with exact reason.

## Strict exclusions

This subphase does not include:

- `input_line`, `input_all`, `input_lines`, limit policy, or line parsing;
- public `Plan9.In_channel` re-export or public documentation;
- installed-prefix work or installed-consumer tests;
- changes to `Plan9.Fd`, `Plan9.Process`, `Plan9.Raw`, or `Plan9.Env` semantics;
- new primitives, raw syscalls, runtime C, process migration, capture, or
  command convenience;
- ordinary channels, raw descriptors, standard input, file opening, seeking,
  positions, length, text translation, or finalizers;
- timing-sensitive note injection without separate approval; or
- snapshots, checkpoint replacement, branch merge, release publication, or
  Caml9 changes.

If excluded work appears necessary, stop and report the evidence.
