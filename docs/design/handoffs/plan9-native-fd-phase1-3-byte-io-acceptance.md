# Phase 1.3 `Plan9.Fd` byte I/O and final acceptance handoff

Status: accepted and completed; reviewed Phase 1.3 documentation checkpoint
`c676b7a506c569c7b7824beba687d96949c7711f`; accepted Phase 1 and Phase 1.3
checkpoint `ee8f799bba40f2ed8caa57a4ef7e91726f2f4283`

## Authority and required reading

This handoff delegates only Phase 1.3 and final Phase 1 qualification. Before
editing, read:

- `docs/design/handoffs/plan9-native-fd-phase1.md` completely;
- the accepted Phase 1.1 and Phase 1.2 completion reports and implementation
  diffs;
- the foundation's APE-independence boundary, private syscall veneer sections
  on capability defense, error handling, heap/blocking sections and staging,
  `Plan9.Fd` target contract, complete Phase 0 acceptance criteria, non-goals,
  and required reports;
- the Phase 0.3 byte-I/O handoff and accepted implementation for exact private
  read/write ABI and staging behavior;
- release-11554 `sys/man/2/pipe` and `sys/man/2/read` facts recorded in the
  roadmap;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before those actions occur.

If either predecessor differs from its accepted report, or this handoff
conflicts with the reviewed roadmap or foundation, stop and return the
evidence.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. The accepted Phase 1.2 implementation
checkpoint is exactly
`ff4a65b9b0b99c10725957fe318cebce95f0e968`, whose reviewed documentation
predecessor is exactly
`fab00d79c52990c5203845e38dd62da24e531a18`. The reviewed Phase 1.3
documentation-checkpoint `HEAD` is exactly
`c676b7a506c569c7b7824beba687d96949c7711f`. Verify that this starting `HEAD`
descends from the accepted Phase 1.2 implementation with only the reviewed
Phase 1.3 documentation delta after it. Then verify a clean index and worktree,
expected branch and remote tracking, and no unrelated history.

Do not begin from an unnamed or unapproved Phase 1.3 documentation checkpoint,
or from an uncommitted, dirty, unqualified, or rejected Phase 1.2. Do not
stash, reset, clean, or absorb unrelated work.

## Accepted predecessor facts

Phase 0 supplies an accepted private primitive transfer capacity of 4096
bytes. Each primitive read or write validates its capability and arguments,
processes pending actions, revalidates callback-mutable state, stages bytes
outside the movable OCaml heap, invokes at most one raw syscall for exactly the
positive requested count, validates the returned count, and captures native
failure immediately. The primitive never loops or clamps.

Phase 1.1 is accepted at
`fff8fc57552523e37a03dcf55a98466d471a9b8a` and supplies the private type
and primitive modules. Phase 1.2 is accepted at the exact checkpoint above
and supplies the production descriptor capability, pipe, and close bindings
plus the uninstalled `Plan9_fd` functor and production instance,
allocation-safe pipe wrapper, shared ownership lifecycle, deterministic
close, and exact private attachment-token authorization. It is not yet
public and has no production read/write bindings or typed byte I/O.

This subphase consumes the accepted primitive and ownership boundaries. If a
runtime primitive change appears necessary, stop and review the evidence
rather than silently reopening Phase 0.

## Delegated outcome

Extend `Plan9_primitive` with production bindings for the accepted descriptor
read and write primitives. Complete `Plan9_fd` with typed public-owner and
private-attached-owner reads and writes, publish the complete `Plan9.Fd`
module, add focused and public tests, update source-tree public documentation
and the installed public compilation interface, make the one authorized
build-generator portability correction below, and perform the complete fresh
native and installed-prefix acceptance gate for Phase 1.

The new production bindings retain the accepted exact logical shapes and C
symbols:

```ocaml
val descriptor_read :
  descriptor_capability -> int ->
  ((bytes * int), Plan9_types.native_failure) result

val descriptor_write :
  descriptor_capability -> bytes -> int -> int ->
  (int, Plan9_types.native_failure) result
```

The uninstalled `Plan9_fd.Primitive` module type gains exactly these backend
members, implemented by the fake backend in tests and mapped directly to the
two production bindings by the production functor instance:

```ocaml
val read :
  capability -> int ->
  ((bytes * int), Plan9_types.native_failure) result

val write :
  capability -> bytes -> int -> int ->
  (int, Plan9_types.native_failure) result
```

The uninstalled `Plan9_fd.S` module type gains exactly these public-owner
members:

```ocaml
val read :
  t -> bytes -> pos:int -> len:int ->
  (int, Plan9_types.error) result

val write :
  t -> bytes -> pos:int -> len:int ->
  (int, Plan9_types.error) result
```

Its existing `S.Private` submodule gains exactly these attachment-owner
members:

```ocaml
val read :
  attachment -> bytes -> pos:int -> len:int ->
  (int, Plan9_types.error) result

val write :
  attachment -> bytes -> pos:int -> len:int ->
  (int, Plan9_types.error) result
```

Apply these exact names, argument order, labels, and result types to both
`plan9_fd.ml` and `plan9_fd.mli`. Do not introduce an alternate backend shape,
unlabeled private range arguments, or a second attachment-I/O interface.

## Fresh-build generator prerequisite

The accepted Phase 1.2 native evidence found that Plan 9 APE `tr` interprets
the tracked `tr -d '\r'` operand in `lambda/generate_runtimedef.sh` as
deleting the literal letter `r`. That corrupts generated runtime-definition
identifiers and prevents the required standard fresh build. Phase 1.3 owns
exactly this narrow tracked portability correction:

```text
tr -d '\r'  ->  tr -d '\015'
```

Do not change any other generator logic. Prove on a non-Plan-9 host that the
old and new commands produce byte-identical output for the repository's
LF-only `runtime/caml/fail.h`, prove with a controlled CRLF input that the new
operand removes only carriage returns, and preserve both command logs and
output hashes.

On the confirmed guest, before the final fresh build, resolve `tr` through the
exact PATH used by `build-aux/plan9/build-world.sh`. That PATH should select the
tracked `build-aux/plan9/shims/bin/tr` first. Record the shim's canonical path,
tracked executable mode, native executable observation, and content hash;
review and record its dispatch behavior. For the corrected `\015` operand the
shim delegates to `/bin/tr`, so also record the available identity of that
underlying guest executable. An unexpected resolution or dispatch chain stops
qualification.

Run a controlled byte probe through that exact shim/delegate chain whose input
contains at least a literal `r`, carriage return, and line feed. Preserve the
input and output in a bytewise or hexadecimal form and require
`tr -d '\015'` to remove only the carriage return while retaining the literal
`r` and line feed. A different result stops qualification; do not guess
another operand, substitute another guest tool, or patch generated output.

The final fresh Plan 9 build must then invoke the corrected tracked generator
through the ordinary Makefile rule; do not substitute an evidence-directory
generator, patch generated output, or repair the guest source after transfer.
This source change is build portability, not a runtime primitive or
descriptor-ABI change.

Do not change the capability type, pipe/close bindings, C symbol names,
arities, result layouts, staging capacity, or runtime implementation. The
production archive's primitive-name set may differ from accepted Phase 1.2
only by exact addition of `caml_plan9_syscall_read` and
`caml_plan9_syscall_write`; the Phase 0 hostile test retains its independent
direct bindings.

The final public interface is exactly:

```ocaml
module Fd : sig
  type t

  val pipe : unit -> ((t * t), error) result
  val read : t -> bytes -> pos:int -> len:int -> (int, error) result
  val write : t -> bytes -> pos:int -> len:int -> (int, error) result
  val close : t -> (unit, error) result
end
```

No other public descriptor function is added.

## Typed range and lifecycle validation

`read` and `write` accept only OCaml `bytes` through their public type. Validate
the destination or source range before any backend call using subtraction,
not `pos + len`:

1. require `pos >= 0` and `len >= 0`;
2. require `pos <= Bytes.length buffer`; and
3. require `len <= Bytes.length buffer - pos`.

An invalid range returns `Invalid_argument` with operation
`Plan9.Fd.read` or `Plan9.Fd.write` and performs no primitive call. Include the
invalid position/length relationship without relying on an overflowing sum.
Every numeric message synthesized by `Plan9_fd` for an invalid byte range,
malformed backend success, or positive-request short write uses decimal
`string_of_int` rendering with no leading sign for nonnegative values, padding,
grouping, or locale-dependent text, and this exact operation/kind/message
table. Braced names below are decimal substitutions, not literal output:

| Condition | Operation and kind | Exact message template |
| --- | --- | --- |
| invalid source or destination range | the invoked `Plan9.Fd.read` or `Plan9.Fd.write`; `Invalid_argument` | `invalid byte range: buffer length {buffer_length}, position {pos}, length {len}` |
| read success with a staging-length or count violation | `Plan9.Fd.read`; `Protocol_error` | `invalid descriptor read result: requested {requested} bytes, staging has {staging_length} bytes, returned count {count}` |
| write success with a negative or oversized count | `Plan9.Fd.write`; `Protocol_error` | `invalid descriptor write result: requested {requested} bytes, returned count {count}` |
| positive native short write, including zero | `Plan9.Fd.write`; `Other` | `descriptor write was short: requested {requested} bytes, wrote {written} bytes` |

The read protocol template records all three observed values even when more
than one invariant is false. These templates are public error behavior and
must be asserted byte-for-byte; do not add punctuation, exception text,
lifecycle state, capability data, or alternate singular/plural forms.
They do not replace the separate lifecycle matrix below or mapped native
failures: lifecycle errors retain their exact operation/kind/message rows, and
native failures retain the exact `Plan9_types.error_of_native` mapping stated
in the read and write sections.

After range validation, authorize the owner:

- a public call requires the stable open-and-detached state;
- public-I/O, public-closing, publicly closed, attached, owner-I/O,
  owner-closing, and owner-closed cells reject every public read and write;
- a private call requires both the stable attached state and the exact
  committed attachment token;
- a stale, uncommitted, or losing token rejects I/O in every state;
- even the exact committed token rejects I/O while an owner-I/O operation is
  active, while its owner-close attempt is active or inactive, and after the
  cell is owner-closed; and
- invalid lifecycle or authorization returns the exact `Invalid_argument`
  result below without a primitive call.

Every I/O lifecycle rejection uses its own public operation,
`Plan9.Fd.read` or `Plan9.Fd.write`, and this exact message matrix. The
publicly closed and owner-closed rows are the terminal phases of their retained
close-attempt representations.

| Path | Rejected condition | Exact message |
| --- | --- | --- |
| public `read` or `write` | public I/O active | `descriptor I/O is already in progress` |
| public `read` or `write` | public-close attempt active or inactive | `descriptor close is already in progress` |
| public `read` or `write` | publicly closed | `descriptor is closed` |
| public `read` or `write` | attached, owner I/O active, owner-close attempt active or inactive, or owner-closed | `descriptor ownership has been transferred` |
| exact-owner private `read` or `write` | owner I/O active | `descriptor I/O is already in progress` |
| exact-owner private `read` or `write` | owner-close attempt active or inactive | `descriptor close is already in progress` |
| exact-owner private `read` or `write` | owner-closed | `descriptor is closed` |
| private `read` or `write` | uncommitted, stale, losing, foreign, competing, or otherwise unauthorized token in any state | `attachment token is not the committed owner` |

These rows extend, but do not rename or reinterpret, the accepted Phase 1.2
close and attachment errors. Do not broaden the messages with lifecycle dumps,
capability data, token identities, or descriptor integers.

### In-flight I/O serialization

The initial authorization check alone is insufficient. The accepted read and
write primitives process pending actions before native work, and those
actions may run an OCaml callback. Without an installed ML I/O state, such a
callback could commit a prepared attachment or perform nested owner I/O after
the outer public check but before the outer native transfer.

Extend the Phase 1.2 state machine with transient public-I/O and owner-I/O
states. The public representation should be an immediate state, and each
attachment should preallocate and retain its exact owner-I/O state just as it
retains its attached state. An equivalent representation is acceptable only
if its complete allocation-free behavior is proved from generated bytecode.
For every positive authorized request:

1. preallocate any final success value whose contents are known before native
   work, including the full-write `Ok primitive_count`, before the
   authoritative state observation;
2. perform the authoritative public-state or exact-token check;
3. install the corresponding I/O state without allocation, callback, safe
   point, or pending-action processing;
4. invoke the backend only after that state is visible;
5. after every normal backend result, restore the exact stable
   open-and-detached or attached state before native-error mapping,
   protocol-error construction, final result allocation, or destination
   copying; and
6. if the backend raises, restore that exact stable state and re-raise the
   physically identical exception using ordinary `RERAISE` compilation.

Any callback or collection caused by the preallocation in step 1 occurs before
the authoritative check. If it changes the shared lifecycle, the later check
must observe that new state and reject without backend work. There is no
allocation between the authoritative check and transient-state installation.

While public I/O is active, public read, write, and close return
`Invalid_argument` with their own operation and the exact message
`descriptor I/O is already in progress`; attachment preparation returns its
existing not-open-and-detached error; every prepared token fails commit; and
token I/O or close is unauthorized. While owner I/O is active, the exact
owner token's read, write, and close return the same in-progress message,
foreign tokens remain unauthorized, attachment preparation fails, every
commit returns `false`, and every public operation retains the ownership-
transferred result. No callback path may issue nested descriptor primitive
work through the cell.

I/O has no inactive or terminal attempt state: it never changes ownership,
and both normal and exceptional returns restore the same stable owner. This
does not authorize an automatic retry after interruption or any other native
failure.

The public operation names remain `Plan9.Fd.read` and `Plan9.Fd.write` even
when a private attached owner performs the operation on behalf of a later
public module. Phase 2 will assign its own higher-level operation when it needs
to wrap or contextualize an `Fd` error; Phase 1 does not erase the exact lower
operation.

For a valid authorized owner and valid range, `len:0` returns a retained,
preallocated `Ok 0` without a primitive call or transient I/O state. The
authoritative state/token check must be followed immediately by that retained
return with no allocation, callback, safe point, or pending-action
processing. An implementation that allocates a zero result per call must
instead allocate before and repeat the authoritative check immediately before
return. Validation still occurs, so zero length cannot revive a closed handle
or bypass attachment authority. A zero-length write emits no pipe message,
and a zero-length read consumes no byte.

## One-transfer public-call policy

The exact capacity `4096` remains private and absent from `plan9.mli` and from
the API signatures and compatibility promises in the source-tree `README.md`
and `REFERENCE.md`. `Plan9_primitive` or `Plan9_fd` may hold a private
synchronized ML constant for chunk selection; source review and focused tests
must prove it matches the accepted primitive capacity.

For a positive valid public request, choose:

```text
primitive_count = min len private_capacity
```

Each `Fd.read` or `Fd.write` call invokes at most one accepted primitive with
exactly `primitive_count`. The wrapper does not loop to complete the caller's
entire `len`, because:

- read is not `readn` and must not merge multiple native reads or cross a
  preserved pipe write boundary; and
- silently issuing multiple writes would turn one public call into multiple
  native messages and would make actual native short-write handling
  ambiguous.

Consequently, a caller may receive positive progress smaller than its logical
`len` solely because the private staging boundary limited that individual
call. That is wrapper-imposed progress, not a native short result. Callers
that want to consume or produce a larger logical byte sequence must make
additional `Fd` calls and honor every returned count. The numeric capacity is
not a compatibility promise.

This policy maps every positive public call to one native read or write and
preserves the ability to distinguish the exact count requested from the
kernel from the caller's larger logical range.

## Read behavior

Call the accepted primitive read with the authorized capability and
`primitive_count` only after installing the transient I/O state. Restore the
stable owner state immediately after the backend returns. On native failure,
then return
`Plan9_types.error_of_native "Plan9.Fd.read" failure` without retry.

On success `(staging, count)`, defensively verify before indexing or copying:

- `Bytes.length staging = primitive_count`;
- `count >= 0`; and
- `count <= primitive_count`.

Although the accepted primitive already guarantees these facts, the ML layer
must not turn a future integration regression into an out-of-bounds blit. An
invalid success shape becomes the exact `Protocol_error` above and does not
modify the caller destination.

For a valid zero count, return the same retained `Ok 0` used by zero-length
calls, without mutating the caller destination. For a positive valid count,
allocate the final `Ok count` before mutating the destination. Then copy
exactly `count` bytes from staging offset zero into the caller destination at
`pos`, leave every destination byte outside that prefix unchanged, and return
that retained result without another fallible allocation. A positive short
count is normal. `Ok 0` for a positive request is EOF. Embedded NUL is ordinary
data.

Do not copy the deterministically zeroed staging tail. Do not retry an
interrupted read: Plan 9 documents that an interrupted pipe operation may have
transferred an unknown number of bytes. A returned read error leaves the
caller destination unchanged because native bytes never entered it.

## Write behavior

Before the authoritative owner check for a positive request, allocate and
retain the normal full-success value `Ok primitive_count`. Then call the
accepted primitive write with the original caller `bytes`, original `pos`, and
`primitive_count` only after the final owner check and allocation-free
installation of the transient I/O state. Do not allocate or pre-slice a
per-chunk ML byte block. The primitive owns post-pending-action source
revalidation and native staging of the current slice. Restore the stable owner
state immediately after every normal backend result and before classifying or
mapping that result.

On native failure, return
`Plan9_types.error_of_native "Plan9.Fd.write" failure` without retry. The
source is never mutated.

On success, defensively require `0 <= count <= primitive_count`. A count larger
than the exact primitive request or a negative typed fake-backend result is a
`Protocol_error` with the exact template above and must never become an index
or progress value.

For a positive primitive request:

- `count = primitive_count` returns the retained full-success value without
  allocation after native transfer;
- `0 <= count < primitive_count` is an actual native short write and returns a
  structured `Other` error with the exact operation and message template above,
  recording both the exact requested and written counts; and
- no short-write path retries, writes the remainder, or reports successful
  progress.

`Other` is used because release-11554 `write(2)` explicitly says a short write
must be regarded as an operational error; it is not the same as the primitive
protocol violation in which the kernel reports more than requested. Do not add
a new public `error_kind` merely for this layer.

An interrupted write likewise returns the exact captured native failure once.
Because the transferred prefix is documented as unknown, the caller must not
retry automatically. The public API does not claim transactional writes.

## Attachment-owner byte I/O

Extend the Phase 1.2 private token interface with the exact `S.Private.read`
and `S.Private.write` signatures above and the same byte range, one-transfer,
error, short-I/O, zero-length, and interruption semantics as the public
functions. The only difference is authorization: the exact committed token may
operate only while the cell remains in the stable attached state, while all
public aliases reject. Once owner I/O is active, the transient state serializes
every operation as specified above. Once owner close begins, both its active
and inactive attempt states reject I/O through every token without primitive
work.

Public and private paths must share one implementation of range validation,
primitive result validation, error mapping, and transfer policy. Do not copy a
second subtly different I/O loop into the private owner module.

After private owner close, its I/O returns `Invalid_argument` without native
work and its repeated close remains idempotent. A public alias never regains
authority.

## Public integration and documentation

Add `module Fd` to `plan9.mli` with the exact final interface and concise
documentation for:

- abstract shared ownership and alias close;
- attachment revocation at a high level without exposing the private token;
- bidirectional Plan 9 pipe peers;
- valid range and zero-length behavior;
- exact operation, kind, and message templates for wrapper-synthesized invalid-
  range, malformed-result, and native-short-write errors;
- possible positive read progress, EOF, and wrapper-limited progress;
- successful reads modifying exactly the returned destination prefix, read
  errors leaving the destination unchanged, and writes never mutating their
  source;
- an interrupted read potentially consuming an unknown amount of input even
  though its destination remains unchanged, making automatic retry unsafe;
- native short-write error, the potentially unknown transferred prefix after
  an interrupted write, non-transactional write failure, and no implicit
  retry; and
- explicit deterministic close with no finalizer.

Re-export the production `Plan9_fd` implementation from `plan9.ml` while the
installed CMI hides its private functor and attachment interface.

Update the source-tree public documentation
`otherlibs/plan9/README.md` and `REFERENCE.md` to include only the accepted
public API and user-visible semantics. They remain repository documentation,
not installed files. Do not document private capacity, primitive names,
capability representation, token types, transient I/O states, or source
module names as public contracts.

The public examples use ordinary `Plan9.Fd.pipe`, explicit result handling,
byte buffers, returned counts, and deterministic close. They must not imply
Unix-directional endpoints, automatic exact writes, standard-channel
conversion, finalizer cleanup, or descriptor integer access.

The installed library payload remains `plan9.cma` and only the public
`plan9.cmi`. The accepted Plan 9 install wrapper sets
`INSTALL_SOURCE_ARTIFACTS=false`, so `plan9.mli` and `plan9.cmti` remain
source/build-tree material rather than installed files. `plan9_types.cmi`,
`plan9_primitive.cmi`, `plan9_process.cmi`, and `plan9_fd.cmi` remain
uninstalled. `README.md` and `REFERENCE.md` are likewise not selected by the
existing install rules. `plan9.cma` remains ML-only.

## Build and dependency integration

`CAMLOBJS` and archive order remain exactly the accepted Phase 1.2 order:

```make
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo plan9_process.cmo plan9.cmo
```

Publishing `module Fd = Plan9_fd` adds `plan9_fd.cmi` to the generated
prerequisites of `plan9.cmo` and `plan9_fd.cmx` to those of `plan9.cmx`.
Because `plan9.mli` spells the public signature explicitly, `plan9.cmi` must
gain no private `Plan9_fd` compilation-interface import. The existing
`plan9_fd.cmi`, `plan9_fd.cmo`, and `plan9_fd.cmx` prerequisite sets otherwise
remain exact unless native dependency generation proves a reviewed source
reason for a change.

Wire only `tests/fd_io_test` into the ordinary Plan 9 test-program inventory.
The installed-consumer source and two expected-failure privacy probes are
qualification inputs, not ordinary build/test targets; do not add them to
`TEST_PROGRAMS`, compile them during `all` or `test`, or turn their expected
failures into generated dependency rules.

Make the hand-written Makefile and source changes in the authoritative
Windows checkout but leave tracked `otherlibs/plan9/.depend` byte-for-byte at
the accepted Phase 1.2 checkpoint until the native dependency gate below.
Never hand-edit generated dependency output.

## Required fake-backend tests

Extend the accepted `otherlibs/plan9/tests/fd_lifecycle_test.ml`; do not create
a second fake-backend test file. The fake backend records read/write calls and
supplies controlled results. At minimum, prove:

- exact invalid ranges `(-1, 0)`, `(0, -1)`,
  `(buffer_length + 1, 0)`, `(buffer_length, 1)`, `(max_int, 1)`, and
  `(1, max_int)` return the byte-for-byte exact range errors above without a
  backend call;
- for both `read` and `write`, a representative invalid range on a publicly
  closed alias and an attached public alias, and through uncommitted, stale,
  losing, foreign, and exact owner-closed private tokens, returns the same
  byte-for-byte range error before any lifecycle or authorization error and
  performs no backend call;
- valid `(buffer_length, 0)` succeeds only on an authorized open owner and
  performs no backend call;
- publicly closed handles reject zero and nonzero lengths with the exact
  closed result, while attached public aliases use the exact
  ownership-transferred result, all without a backend call;
- stale, losing, uncommitted, and foreign attachment tokens use the exact
  unauthorized result, while the exact owner-closed token uses the exact
  closed result, all without a backend call;
- a logical request of exactly the private capacity produces one backend call
  of that size;
- a valid request of capacity plus one produces one backend call of exactly
  the private capacity, with no per-chunk ML staging allocation;
- the private pure chunk-selection helper maps `max_int` to exactly the
  private capacity without allocation or overflow, while the typed public
  `(1, max_int)` range remains invalid and performs no backend call;
- read copies only the valid returned prefix at the requested destination
  offset and leaves prefix, suffix, and short-result tail bytes unchanged;
- read preserves embedded NUL and returns zero as EOF;
- malformed read staging length, negative count, and oversized count become
  the byte-for-byte exact read `Protocol_error` above without destination
  mutation, including the complete observed-value tuple when multiple
  invariants are false;
- EOF for a positive read returns the retained zero-success value, and a full
  write returns the preallocated primitive-chunk success without a
  post-transfer allocation;
- a synthesized positive short write and zero write for a positive request
  return the byte-for-byte exact short-write error after exactly one backend
  call and never issue a remainder;
- an oversized or negative fake write count becomes the byte-for-byte exact
  write `Protocol_error` above;
- native-failure mapping preserves operation, kind, and exact message; and
- committed attachment-owner I/O follows the same transfer policy while
  public aliases remain rejected.

The fake backend must also invoke controlled callbacks from both read and
write. For public I/O, exercise reentrant public read, write, and close,
attachment preparation, a previously prepared token's commit, and token I/O
or close. For owner I/O, exercise reentrant I/O and close through the exact
token, foreign-token operations, public aliases, preparation, and every
commit path. Require the exact I/O-in-progress, close-in-progress, closed,
transferred, not-detached, unauthorized, and `false` results above; require no
nested primitive call; and prove that the outer operation restores its exact
stable owner afterward.

For both public and owner paths, make the fake backend raise an allocated
designated exception after the same callback matrix. Require physical
exception identity, stable-state restoration before rethrow, ordinary
`RERAISE`, and a successful later authorized operation through the same cell
or token. Force minor collection, full major collection, and compaction around
retained zero-success, preallocated full-write-success, and owner-I/O-state
cases.

Also extend the accepted Phase 1.2 close-backend callbacks. During active and
exception-left inactive public close, require public and token I/O rejection
with the exact matrix result and without a read/write backend call. During
active and inactive owner close, require public, exact-token, and foreign-token
I/O rejection with their exact matrix results and without backend work. Repeat
the same assertions after each close reaches its terminal state.

Use the fake backend, not a production fault switch, to synthesize impossible
or timing-sensitive results.

## Required native and public tests

Add exactly these two positive Phase 1.3 source files:

- `otherlibs/plan9/tests/fd_io_test.ml`, the production `Plan9.Fd` focused
  native test wired into the Plan 9 test target; and
- `otherlibs/plan9/tests/fd_installed_consumer_test.ml`, the public installed-
  consumer smoke source used only by the installed-prefix gate.

The installed-consumer source is not a source-tree test target and is not
compiled by the ordinary library build. Together with the two negative probe
files named below, these are the only new test-source paths authorized by this
handoff. Extend the existing lifecycle test for fake-backend coverage rather
than adding another source path. At minimum, prove:

- both pipe endpoints are bidirectional peers;
- a binary payload containing embedded NUL round-trips exactly;
- a payload of exactly `2 * 4096 + 3` bytes round-trips by caller-owned loops,
  with recorded public progress demonstrating the private wrapper split but
  without per-chunk caller source allocation;
- a small completed native write followed by a larger read returns the exact
  positive short count at the preserved write boundary;
- closing the designated writer yields EOF only after all queued data is read;
- a zero-length write creates no EOF-like pipe message and a zero-length read
  consumes no queued byte;
- alias close, repeated close, use after close, attachment revocation, private
  owner I/O/close, and owner-closed behavior match the accepted lifecycle;
- the unchanged Phase 0 internal negative-path probe still captures its exact
  native error message, while the fake-backend suite proves that public and
  exact-owner read/write mapping preserves the high-level operation, kind, and
  exact supplied message;
- 256 or another reviewed deterministic repeated lifecycle/I/O cycles leave
  the sorted complete `/fd` inventory unchanged;
- forced minor and major GC with live public and attached owners does not lose
  or duplicate ownership; and
- the complete Phase 0 hostile primitive matrix still rejects forged,
  wrong-state, and closed capabilities before native work.

Source review and fake call counts prove interruption is not retried. Actual
timing-sensitive note injection is not part of ordinary Phase 1 acceptance and
requires separate explicit authorization if later desired.

Do not deliberately provoke a native public-read or public-write failure in
the ordinary native suite. With no foreign-descriptor adoption or production
fault switch, the public pipe API has no deterministic safe setup for that
case: release-11554 `pipe(2)` documents that writing after all readers close
generates a note, and timing-sensitive note injection is excluded. The fake
backend proves the complete high-level mapping, and the unchanged Phase 0
negative-path probe independently proves native error capture and exact native
message preservation. This separation is the accepted Phase 1 error evidence,
not an open criterion.

Run every existing Plan 9 environment, process, raw-syscall, primitive, and
native-integration regression unchanged in addition to the new focused tests.

## Complete source, symbol, and packaging audit

Review and record:

- typed range validation and overflow avoidance;
- exact lifecycle/token authorization and complete operation/kind/message
  matrix before zero-length success or native work;
- retained allocation-free zero success and allocation-free installation of
  the exact transient public-I/O or owner-I/O state;
- domination of every backend call by its installed I/O state, rejection of
  reentrant ownership and I/O operations, and stable-state restoration on
  every normal and exceptional backend edge;
- private chunk selection and one primitive call per public call;
- read result validation and final-success allocation before blit, followed
  by retained-zero EOF or exact prefix-only copy and no later fallible
  allocation;
- preallocation of the full-write success before the final owner check,
  allocation-free return after a full native write, write result
  classification, no short-write retry, and no per-chunk source copy in ML;
- identical public and attachment-owner transfer policy;
- exact `Plan9_fd.Primitive` and `Plan9_fd.S` read/write names, argument order,
  labels, result types, production-adapter mapping, and matching additions to
  the `Private` submodule of `Plan9_fd.S`;
- no raw descriptor integer, finalizer, ordinary channel, APE descriptor
  registration, foreign adoption, `dup`, or new syscall;
- unchanged accepted runtime C, assembly, capability identity, primitive ABI,
  validation order, staging, blocking, and error capture;
- exact addition of only descriptor read/write primitive imports to the
  production archive, with every force-linked `plan9.cma` consumer continuing
  to run under `$(NEW_OCAMLRUN)` and the isolated pure process-state test
  retaining its bootstrap-runtime lane;
- one generated primitive-table entry and one linked definition for every
  accepted primitive;
- absence of forbidden APE I/O/process/private-entry references in the exact
  descriptor-path audit scope defined below;
- ML-only `plan9.cma`;
- exact generated dependency edges, including the new `Plan9_fd` dependency
  of the umbrella implementation but no private import in `plan9.cmi`;
- the single reviewed `generate_runtimedef.sh` portability delta and its
  cross-platform output-equivalence evidence, plus resolved guest `tr`
  shim/delegate identities, dispatch chain, and byte-probe evidence;
- exact public surface in the reviewed explicit `plan9.mli`, with CMI tooling
  used only for unit/import evidence rather than a claimed signature dump; and
- installation of build-identical public `plan9.cmi` and `plan9.cma`, with no
  internal CMI, `plan9.mli`, `plan9.cmti`, README, or reference-document
  installation.

The descriptor-path APE audit is deliberately artifact- and layer-scoped.
Repeat the accepted Phase 0 raw-veneer and runtime-integration object audits
unchanged against the exact fresh artifacts. Audit
`runtime/plan9_syscall_amd64.$(O)` as the raw veneer object and require exactly
the accepted repository-prefixed raw entries `caml_plan9_sys_close`,
`caml_plan9_sys_pipe`, `caml_plan9_sys_errstr`, `caml_plan9_sys_pread`, and
`caml_plan9_sys_pwrite`, with the accepted absence of undefined library calls
and forbidden APE entry references. Audit every selected object named by
`PLAN9_SYSCALL_INTEGRATION_OBJECTS` that is derived from
`runtime/plan9_syscall.c` as a runtime-integration object. That layer has the
four descriptor-facing `CAMLprim` definitions
`caml_plan9_syscall_pipe`, `caml_plan9_syscall_close`,
`caml_plan9_syscall_read`, and `caml_plan9_syscall_write`; it uses the private
raw `ERRSTR` entry internally for immediate native-error capture rather than
exporting a fifth ML error primitive.

Separately audit `Plan9_primitive` by exact external primitive name. After
Phase 1.3 its descriptor import set is exactly those same four
descriptor-facing built-ins, and the only delta from accepted Phase 1.2 is
addition of the exact read and write names. Audit the fresh
`otherlibs/plan9/plan9_fd.cmo` source/bytecode path for its reviewed
`Plan9_primitive` descriptor-operation and `Plan9_types.error_of_native`
dependencies and for absence of ordinary channel, APE descriptor, process, or
private-entry use. Do not misreport `Plan9_types.error_of_native` as a native
primitive import.

Do not claim whole-`plan9.cmo`, whole-`plan9.cma`, or whole-runtime absence of
APE references: those aggregates intentionally retain unrelated accepted
`Env`, `Raw`, `Process`, and portable runtime behavior. The archive must still
be ML-only, but that property is separate from this scoped five-operation
descriptor-path audit. Preserve exact artifact paths, object-selection values,
content identities, audit commands and results, and these explicit exclusions.

Source review alone does not prove the callback-sensitive I/O regions. Build
the repository `tools/dumpobj` in the fresh native tree with this exact
target-scoped command from Phase 1.2:

```text
<GNU Make> -C tools -W make_opcodes.mll -W dumpobj.ml dumpobj
```

The two `-W` operands force the required opcode-input regeneration and
disassembler recompilation without the unsafe unrelated CMI rebuilding caused
by global `-B`. Do not infer a root-level target or substitute a host-built
tool. Run the resulting `tools/dumpobj` under that tree's newly built runtime
against the freshly built `plan9_fd.cmo`, and preserve the complete
disassembly. Because Phase 1.3 changes the state variant and attachment
representation, repeat the complete accepted Phase 1.2 bytecode audit against
this new object; the earlier `plan9_fd.cmo` audit is not evidence for the
modified object. Then map every reachable control-flow edge for:

- attachment preparation through initialization and retention of both the
  attached and owner-I/O states and its final authoritative recheck/return;
- authoritative owner check through transient I/O-state installation;
- installed I/O state through the backend invocation;
- every normal backend return through exact stable-state restoration before
  mapping, result allocation, or destination mutation;
- every backend exception through exact stable-state restoration and
  `RERAISE`;
- zero-length authoritative check through return of retained `Ok 0`;
- positive-request EOF through return of the same retained `Ok 0`;
- positive valid read count through final-success allocation, prefix copy, and
  return; and
- full write through return of the success value preallocated before the
  authoritative owner check.

Record boundary PCs, branch and switch targets, tool/object identities, and
complete output. Prove that every check-to-install, restoration, exception,
retained-zero, and full-write-success return region contains no allocation,
polling, callback-capable instruction, or unreviewed call; that each backend
call is dominated by the installed state; and that no destination mutation
precedes final-success allocation.

No report may generalize the descriptor-path APE-independence proof to the
whole runtime or to existing `Env`, `Raw`, or `Process` implementations.

## Fresh source and installed-prefix acceptance

Final qualification starts from a fresh native destination that passes the
shared creation-and-ownership gate below before population and then contains
exactly the approved source set from the reviewed Windows worktree. Follow the
foundation's Phase 0 manifest discipline:

- derive the transfer set from every existing regular worktree file at a path
  reported by `git ls-files`, using current worktree bytes, adjusted only for
  explicitly reviewed new or deleted paths;
- record complete untracked and ignored inventories separately;
- add exactly the four reviewed new test-source paths
  `otherlibs/plan9/tests/fd_io_test.ml`,
  `otherlibs/plan9/tests/fd_installed_consumer_test.ml`,
  `otherlibs/plan9/tests/fd_private_surface_negative.ml`, and
  `otherlibs/plan9/tests/plan9_fd_surface_negative.ml`. No other new or deleted
  path is expected; stop for review if implementation proves one necessary;
- record and review the complete `git ls-files -s` mode/object/path inventory.
  The accepted index has one non-file gitlink, exactly mode `160000`, object
  `a47f93667bd4dcc7c7e85aa02f34446d47d28915`, path `flexdll`. It has no
  worktree-file bytes, is not part of the Plan 9 source transfer, must not be
  materialized or copied, and must be absent from the native destination. A
  changed gitlink identity, additional gitlink, symlink, or any other index
  mode outside `100644`, `100755`, and that one exact `160000` entry stops the
  gate for review;
- derive a separate executable-mode manifest from the Git index for every
  transferred `100755` path; record its canonical path and mode without
  treating Windows worktree mode bits as authoritative;
- transfer no `.git`, build artifact, or unrelated path;
- emit canonical repository-relative path, decimal length, and lowercase
  digest tuples with one reviewed hash algorithm on host and guest;
- apply executable permission only to the exact paths in that mode manifest,
  verify every listed native path is executable, and preserve the before/
  after mode evidence; this restores tracked transfer metadata and is not a
  guest source edit;
- compare parsed, bytewise-path-sorted content manifests, prove the destination
  has no extra file, and prove it has no `flexdll` path; and
- configure and build only after manifests match.

The transfer/archive method must preserve or deterministically restore those
tracked executable modes. A native `Permission denied` followed by an ad hoc
`chmod`, an external generator, or a generated-source patch invalidates the
fresh-build attempt; correct the authoritative transfer procedure and repeat
from a new nonexistent destination.

Ask the user to approve an exact canonical, isolated, nonexistent install root
or explicitly approve replacement, plus its retain/remove postcondition. The
approved root must be disjoint from the source/build tree and from the
known-working `/usr/glenda/lib/unix/ocaml-4.14.3` tree.

Every complete identity inventory required below uses one common schema. Stat
the canonical root and every descendant and emit one bytewise-root-relative-
path-sorted tuple for each, using `.` for the root itself. Every tuple records
canonical root-relative path, the exact entry-type token `regular` or
`directory`, native mode, server type and device, Qid type, version, and path,
and `uid`, `gid`, and `muid`. Every tuple ends with content-length and content-
hash fields: a regular file records its decimal byte length and digest, while a
directory uses zero-length values for both fields and is represented even when
empty. Record the canonical absolute root separately with the same length-
prefixed field encoding.
Use the same one reviewed hash algorithm selected for the source-transfer
manifests, record its exact name and tool identity, and render every digest as
lowercase hexadecimal. Serialize each tuple with a fixed field order and an
unambiguous length-prefixed encoding. Render every integral identity field as
unsigned decimal ASCII, using `0` for zero and no leading zeros; preserve the
exact guest bytes of paths and ownership names. Prefix every rendered field's
exact byte string with its decimal byte length and a colon, then concatenate
the fixed sequence. Determine sorting from the raw root-relative path bytes,
not from the encoded record or locale collation. Compare decoded field tuples,
not human-formatted or delimiter-split display text. Do not compare access or
modification times. An inability to stat and walk one consistent population,
an unsupported entry kind, an unavailable or changed hash/encoding method, or
a changed identity tuple stops any ownership, unchanged-tree, retain, or
removal claim.

Before populating any newly selected native work-tree root in this handoff,
including the final fresh qualification destination and every separate
non-final dependency tree, apply one shared creation-and-ownership gate. Select
and record its exact canonical path and intended role, prove it is disjoint
from the approved and protected install prefixes, consumer and evidence roots,
every other native work tree, and any pre-existing retained tree, and prove it
is absent. Invoke creation only for that exact root and preserve the command,
output, and status. Claim task ownership only after exact status zero followed
immediately by canonical re-resolution to the same root, a complete initial
identity inventory using the common schema, and proof that it contains exactly
the root directory and no descendant.

If creation is nonzero, interrupted, or unknown, or canonical identity,
ownership, disjointness, or emptiness cannot be proved, stop before transferring
or generating any file and perform one read-only re-resolution. Record the
exact selected-but-not-created sentinel if the path is absent. If it exists
without proved task ownership, record the exact foreign-or-ownership-unproven
work-tree collision sentinel, canonical path, and root stat identity obtainable
without walking or modifying it. Never populate, retain as task-owned, or
remove an unowned path. Follow the applicable dependency-cycle or final-attempt
failure rule rather than selecting another root in the same attempt. A
pre-existing retained native tree selected for dependency generation is not a
new root, never passes through this ownership gate, remains non-task-owned, and
is never removable under this handoff.

On the confirmed guest and before configuration, resolve and record the exact
canonical approved root and observe whether it exists. If the user approved a
new prefix, require it to be absent; an unexpected existing path stops the
attempt and requires new direction. If replacement was explicitly approved,
verify that the observed path is exactly the approved target and record its
complete pre-replacement identity inventory before any removal. Immediately
before removal, re-resolve the root and require its complete current identity
inventory to match that record exactly. Apply the repository's exact-path and
destructive-action checks, remove only that approved root, and prove the root
is absent afterward. Failure to prove identity, complete removal, or absence
stops the attempt. Never interpret approval of a new prefix as approval to
replace an existing path, and never use an overlaid or partially retained
prefix for qualification.

Configure the fresh tree with the explicit later override:

```text
build-aux/plan9/configure.sh --prefix=<approved-root>
```

Do not rely on the wrapper's known-working default. Immediately after
configuration and before any build or install, inspect the generated
configuration and effective GNU Make installation variables. Invoke the
top-level build and install with `DESTDIR` explicitly empty, record its value,
and reject inherited `MAKEFLAGS`, `GNUMAKEFLAGS`, `MFLAGS`, or other GNU Make
variable assignments or options that redirect, suppress, or rewrite the
reviewed commands or installation directories. Record the exact effective
values of `prefix`, `exec_prefix`, `BINDIR`, `LIBDIR`, `STUBLIBDIR`,
`COMPLIBDIR`, `MANDIR`, `PROGRAMS_MAN_DIR`, `LIBRARIES_MAN_DIR`, `DOCDIR`, and
every derived nonempty `INSTALL_*` destination used by the root or recursive
install rules, including `INSTALL_OTHERLIBDIR` for `plan9`. Resolve every
destination canonically, require `prefix` to equal the exact approved root,
and prove that every other effective destination either equals that root or
lies strictly below it. Repeat this environment and complete destination-table
check immediately before installation. A missing value, override, path escape,
or mismatch invalidates the configured tree and stops the attempt; do not
repair generated configuration by hand.

The authoritative complete world-build command for the final qualification is
exactly:

```text
build-aux/plan9/build-world.sh
```

The authoritative ordinary Plan 9 focused-suite command is exactly:

```text
<GNU Make> -C otherlibs/plan9 TEST_SUFFIX=<fresh-reviewed-suffix> test
```

Use the same recorded GNU Make executable selected before configuration. The
suffix is new for every test attempt and contains only 1--40 ASCII letters,
digits, or underscores. Record the exact environment, command, complete output,
and exit status for configure, world build, and focused suite, and require
exact status zero before later evidence counts. The ordinary target must run
the complete Phase 0 and Phase 1 inventory, including the new `fd_io_test`; do
not replace it with a hand-selected subset.

Never modify the known-working prefix. Record whether it exists before
qualification. If it exists, record its complete identity inventory using the
common schema before qualification. After all qualification and cleanup,
re-resolve the canonical root and require its canonical path and complete
identity inventory to match exactly. If the protected root is absent, record
that exact sentinel and prove it remains absent afterward; do not describe a
nonexistent tree as having a manifest.

Immediately before invoking `build-aux/plan9/install.sh`, repeat the canonical
approved-root existence and identity check. For a new-prefix approval, it must
still be absent. For an approved replacement, require the recorded exact-root
removal and prove that root likewise remains absent. Do not silently install
over a previous prefix or a path that appeared after the earlier observation.
Any mismatch stops qualification and requires new user direction. Preserve the
complete pre-removal identity inventory, post-removal absence proof, and
immediate pre-install absence observation.

When installation is invoked, preserve its exact command, output, and exit
status. Immediately after that command returns, successfully or not, and
before compiling or running any consumer, observe the approved root again. If
it exists, record its complete identity inventory using the common schema. If
the root does not exist, record the exact absence sentinel. This immediate
complete identity inventory, or the absence sentinel, is the final-cleanup
ownership baseline. Reject any later canonical-root, entry-identity,
population, length, or content difference. No other action may write inside
the approved root after that baseline. If the root cannot be statted and
walked consistently, or unrelated activity or another creator could have
populated the path after the immediate pre-install absence check, stop rather
than claim the resulting tree as task-owned.

Only an exact zero exit status from the recorded install command authorizes
the installed consumer smoke or either negative-surface probe to count toward
acceptance. A nonzero, interrupted, or unknown install status leaves installed
qualification failed even if enough files exist to compile or run a consumer;
do not treat such probe results as qualifying evidence. Select and create the
consumer directory only after an exact zero install status. For a nonzero,
interrupted, or unknown status, do not select or create that directory; record
the exact not-created sentinel, and do not apply consumer retain/remove
semantics. Never rerun installation over the partial or uncertain root. First
enforce the approved retain/remove postcondition against the immediate
ownership baseline. Another install attempt requires new user direction and a
newly absent root or an explicitly approved replacement root, followed by the
complete pre-install checks; preserve every failed, interrupted, unknown,
cleanup, and retry record.

After an exact zero install status, select and record an exact canonical
consumer-directory path that is disjoint from the source tree, build tree,
approved install prefix, protected known-working prefix, dependency tree, and
every evidence directory. Prove the path is absent, invoke creation only for
that exact path, and preserve the creation command, output, and status. Claim
task ownership only after exact status zero followed immediately by canonical
re-resolution to that same root, a complete initial identity inventory using
the common schema, and proof that it is an empty directory.

If creation is nonzero, interrupted, or unknown, or if canonical identity,
task ownership, or emptiness cannot be proved, stop before copying or compiling
anything and perform one read-only re-resolution. If the path is absent, record
the exact selected-but-not-created sentinel and failure reason. If it exists
without proved task ownership, record the exact foreign-or-ownership-unproven
collision sentinel, canonical path, and root stat identity obtainable without
walking or modifying that tree. In either branch, apply no consumer retain or
remove semantics, leave any unowned path untouched, skip the consumer smoke and
privacy probes, and follow the final-attempt failure rule rather than selecting
another path within the same attempt.

Only a successfully created, identity-proved, empty task-owned directory may
receive these three repository-owned, manifest-verified qualification sources:

- `otherlibs/plan9/tests/fd_installed_consumer_test.ml`, the positive public
  smoke source;
- `otherlibs/plan9/tests/fd_private_surface_negative.ml`, containing a direct
  reference to `Plan9.Fd.Private`; and
- `otherlibs/plan9/tests/plan9_fd_surface_negative.ml`, containing a direct
  reference to top-level `Plan9_fd`.

All three files are reviewed Phase 1.3 source additions, not guest-authored
evidence. Verify each copied source's canonical repository path, decimal
length, and content hash against its final native source-manifest entry. Before
compilation, record a complete identity inventory using the common schema and
require the directory to contain exactly those three regular source files and
no other entry. From that directory, compile the positive smoke with exactly:

```text
<installed ocamlc> -I +plan9 -linkall plan9.cma fd_installed_consumer_test.ml -o fd_installed_consumer_test
```

Run it with exactly
`<installed ocamlrun> ./fd_installed_consumer_test`. Use no `-custom`,
`-use-runtime`, C
compiler, linker, wrapper compiler, additional archive, source-tree include,
or competing `plan9.cma`. Unset `OCAMLPARAM`, `OCAMLLIB`, legacy `CAMLLIB`, and
`CAML_LD_LIBRARY_PATH`. Record:

- exact compiler and runtime paths;
- exact `ocamlc -where`, proven inside the approved prefix;
- resolution of `+plan9` to that prefix's `plan9` directory;
- path, size, and content hash of the fresh-build and installed `plan9.cma`
  and `plan9.cmi`, with byte-for-byte identity required for each corresponding
  pair;
- a complete inventory of the resolved `+plan9` directory, which must contain
  exactly two entries, both regular files: the build-identical `plan9.cma` and
  `plan9.cmi`; no other file or directory is permitted there;
- a complete-prefix exact-basename search proving that `plan9_types.cmi`,
  `plan9_primitive.cmi`, `plan9_process.cmi`, `plan9_fd.cmi`, `plan9.mli`, and
  `plan9.cmti` occur nowhere below the fresh approved prefix;
- absence of `README.md` and `REFERENCE.md` from the resolved `+plan9`
  directory under the unchanged Plan 9 packaging policy, already implied by
  and explicitly checked against its exact two-file inventory;
- ML-only archive evidence; and
- successful compilation and execution through every reviewed public `Fd`
  member (`pipe`, `read`, `write`, and `close`), including binary I/O, EOF,
  alias close, and repeated descriptor-cleanup behavior under the installed
  runtime.

After ordinary repository headers or comments, the only compilation
declaration in each negative source is respectively:

```ocaml
module Probe = Plan9.Fd.Private
```

and:

```ocaml
module Probe = Plan9_fd
```

In the same environment-isolated directory and only after successful positive
smoke compilation and execution, compile the probes separately with exactly:

```text
<installed ocamlc> -I +plan9 -c fd_private_surface_negative.ml
<installed ocamlc> -I +plan9 -c plan9_fd_surface_negative.ml
```

Each command must fail at the right-hand side of its module alias. Preserve
the exact command, nonzero status, source location, and complete diagnostic.
The first primary diagnostic must be exactly
`Error: Unbound module Plan9.Fd.Private`; the second must be exactly
`Error: Unbound module Plan9_fd`. The normal compiler file/line/caret prefix
may reflect the reviewed source header, but the primary diagnostic text may
not differ. A syntax error, missing `Plan9`, linker/archive failure,
compiler/tool failure, unrelated dependency failure, or other generic nonzero
status is not evidence. Use no `-open`, source/build-tree include, archive, or
additional compiler option. Verify that neither command resolves a source/
build-tree CMI and that neither probe's `.cmi`, `.cmo`, or other successful
output artifact exists afterward.

Whenever a task-owned consumer directory was successfully established and its
qualification lane terminates, successfully or otherwise, stop all writes to
it and record the exact successful, failed, interrupted, unknown, or incomplete
status and reason. Then record its complete final identity inventory using the
common schema, including partial compiler outputs or other entries left by a
stopped command. Retain that exact directory, status label, and identity
inventory by default as qualification evidence. Removing it is a separate
destructive action requiring explicit user authorization: re-resolve the exact
canonical path, prove it remains disjoint from every protected tree, require
its complete current identity inventory to match the preserved final identity
inventory, remove only that exact task-owned directory, and prove it is absent.
An inability to complete or match the final inventory blocks removal and leaves
the retained workspace and open criterion recorded. A selected-but-not-created
or foreign-or-ownership-unproven path follows the no-action branch above, not
this task-owned-workspace rule. Approval to remove the isolated install prefix
or fresh source tree does not authorize removal of the consumer directory.

Do not claim that `ocamlobjinfo` prints or proves a CMI signature. Exact public
surface evidence consists of source review of the explicit `plan9.mli`, the
fresh-build/installed `plan9.cmi` identity, positive compilation through every
reviewed public member, and the two negative privacy probes. Use
`ocamlobjinfo` on the build and installed CMIs only for unit identity and
imported-interface CRC evidence, including absence of a private `Plan9_fd`
interface import. Together these checks prove the reviewed `Plan9.Fd` surface
without its functor, attachment type, token operations, or private source
module.

After preserving every installed-prefix result and regardless of whether the
smoke, negative probes, or another post-install check passed, enforce the
user-approved final postcondition for the isolated prefix:

- first re-resolve the exact canonical root, prove it is still the approved
  root and remains disjoint from the protected and source/build trees, and
  independently reproduce the complete current identity inventory using the
  common schema, or the absence sentinel;
- require that current observation to match the immediate post-install
  ownership baseline exactly. Any canonical-root or entry-identity change,
  added, removed, or changed entry, or existence/absence mismatch stops cleanup
  and requires user direction; do not remove the root merely because its path
  still matches;
- for **retain**, preserve the matching final identity inventory and leave the
  exact root in place; or
- for **remove**, preserve that matching identity inventory as the separate
  final-cleanup pre-removal identity inventory, repeat the destructive-action
  checks, remove only the exact approved root, and prove that root is absent
  afterward.

If installation never created the approved root, a remove postcondition is
satisfied only by a recorded final absence observation; retain requires new
user direction because there is no installed tree to retain. Never reinterpret
a failed qualification as authority to choose a different postcondition.
Failure to enforce or prove the approved postcondition leaves qualification
open or blocked and must be reported. Take the known-working-prefix final
complete identity inventory or absence observation only after this prefix
action and all other authorized cleanup, so cleanup itself is covered by the
protection proof.

If installation is not authorized or any environment-isolation condition is
not met, report the criterion as open and do not declare Phase 1 accepted.

## Execution sequence and mandatory pauses

### 1. Preflight and implementation

Record Git state, complete untracked and ignored inventories, accepted Phase
1.1/1.2 identities, the exact user-approved Phase 1.3 documentation-checkpoint
identity and ancestry, ownership interfaces, primitive capacity and shapes,
public documentation state, build rules, tracked executable-mode inventory,
generator behavior, dependency state, and test inventory. Implement only the
production descriptor read/write bindings, typed byte I/O and serialization,
final public integration, documentation, focused tests, and the exact generator
portability correction authorized above. Make the hand-written Makefile
changes but leave tracked `.depend` at accepted Phase 1.2 bytes.

### 2. Source review before VM work

Run all safe host-side checks and separately inspect:

- the implementation-only diff from the exact user-approved Phase 1.3
  documentation checkpoint;
- the complete Phase 1.3 documentation-and-implementation diff from accepted
  Phase 1.2 checkpoint `ff4a65b9b0b99c10725957fe318cebce95f0e968`; and
- the cumulative Phase 1 diff from reviewed Phase 1 documentation checkpoint
  `9369474ed38cf35bb0bf699e28d617a88c534e07`.

Report range, chunk, count, copy, short-write, error, lifecycle, attachment,
transient-I/O serialization, publication, generator, dependency, and packaging
behavior. Stop before VM access.

### 3. Explicit VM and prefix confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, and WHPX profile. Ask separately for the isolated
install prefix, create/replace action, and retain/remove postcondition. Never
boot a protected checkpoint, guess an endpoint, share a writable disk, take
an unauthorized snapshot, or overwrite the known-working prefix.

Retain the final fresh native source/build tree by default because it is useful
for the next phase. After every evidence-producing final qualification gate has
succeeded and all writes to that tree have stopped, but before the protected-
prefix final comparison, record its exact canonical path and complete final
identity inventory using the common schema and enforce its selected retained or
removed postcondition. Retention preserves that exact inventory. Removal is a
separate destructive action requiring explicit user authorization: re-resolve
the exact canonical root and its disjointness from every protected tree,
require its complete current identity inventory to match the recorded final
inventory exactly, remove only that exact task-owned root, and prove it is
absent. This closes the source-tree resource before the protected-prefix last
look but does not yet assign an accepted-final label.

After the source-tree, isolated-prefix, consumer, auxiliary, rejected-tree, and
other authorized cleanup postconditions are closed, perform the protected-
prefix final comparison. Then prove the remaining descriptor, process,
temporary-file, guest, VM, listener, and writable-disk postconditions. Only
after every one succeeds may the source/build destination receive the
accepted-final label and the final attempt become complete.

An inability to complete the source-tree inventory or selected postcondition,
or a failure in any later protected, guest, or VM postcondition, withholds or
revokes the accepted-final label, makes the attempt incomplete, and records the
tree under the rejected-destination rule below with its already proved retained
or removed disposition. Leave an unresolved tree physically retained with the
open postcondition recorded unless that rule's complete identity and explicitly
authorized removal gate can be satisfied. A tree from any other unsuccessful
attempt likewise must never receive the accepted-final label. Permission to
remove an isolated install prefix does not authorize removal of the source/
build tree.

Use the repository VM and native-build skills. Transfer without `.git` through
`/mnt/term`, copy onto native storage, and never build on `/mnt/term`.

### 4. Native dependency generation and authoritative return

Before creating the final fresh qualification destination, transfer the exact
reviewed source into a confirmed retained native build tree or a separate
non-final dependency tree that first passed the shared creation-and-ownership
gate. Restore and verify its tracked executable modes, then run the accepted
APE/GNU Make dependency target from that native tree:

```text
<GNU Make> -C otherlibs/plan9 depend
```

Record the complete command, tool identity, output, exit status, pre/post
`.depend` identities, and native source-manifest delta. The recipe redirects
directly to `.depend`, so accept output only after exit status zero. Require a
nonempty complete generated file containing `.cmi`, `.cmo`, and `.cmx` rules
for `plan9_types`, `plan9_primitive`, `plan9_fd`, `plan9_process`, and `plan9`,
with the exact expected DAG described above. Require the successful manifest
delta to contain only `otherlibs/plan9/.depend`.

Return only that validated successful file through `/mnt/term`, compare it
byte-for-byte with the guest result, and replace only the authoritative Windows
`.depend`. A failed, empty, truncated, partial, or incomplete guest output is
rejected evidence and must not be returned as authoritative or update the
Windows file. Do not hand-edit it.

After any dependency-command failure that does not require a source correction,
preserve the failed artifact and diagnostics outside the source tree, then
either repopulate a new non-final dependency tree or restore the exact reviewed
Windows `.depend` through the validated transfer lane. Repeat the complete
pre-generation source and executable-mode manifest checks before rerunning the
target. Never retry from an unreviewed truncated source file. If the failure
exposes a source defect, use the full Windows-correction and invalidation rule
below. Preserve every failure/restoration/retry cycle.

For every separate non-final dependency tree whose shared gate established
task ownership, record its canonical path, initial empty identity inventory,
purpose, and success, failure, or superseded status, and close it with an
explicit final postcondition. Retain it by default with a complete final
identity inventory using the common schema. Removal requires explicit user
authorization, re-resolution of the exact canonical root and its disjointness,
and an exact match between the complete current identity inventory and the
recorded final inventory; remove only that exact root and prove it is absent.
Record the applicable selected-but-not-created or work-tree collision sentinel
for a failed ownership gate and apply no retain/remove action to that unowned
path. Merely using a pre-existing retained native tree neither makes it
task-owned nor authorizes its removal.

After the authoritative return, repeat `git diff --check`, complete untracked
and ignored inventories, the implementation-only Phase 1.3 checkpoint diff,
the complete diff from accepted Phase 1.2, the cumulative Phase 1 diff, every
safe source/API/allocation/generator/packaging audit, and the complete host
content and executable-mode manifests. Only those final reviewed Windows bytes
may populate the fresh qualification destination.

Any corrective source, Makefile, generator, test, or documentation edit after
native dependency generation invalidates the returned dependency evidence,
final host review, manifests, and guest copy. Make the correction only in the
Windows checkout, repeat this complete dependency-return gate, and then use a
new nonexistent fresh qualification destination. Never patch guest source or
continue from stale manifests.

### Authoritative retry rule for final qualification

Configure, world build, `dumpobj` production and disassembly, tests, and audits
are evidence-producing lanes, not guest source-editing lanes. Preserve the
exact command, environment, output, status, guest path, relevant artifact
identities, and postconditions for every attempt. A nonzero, interrupted,
unknown, incomplete, path-incomplete, unmappable, or contradictory result
stops the current final attempt and cannot be hidden by a later successful
subset.

Do not edit implementation, Makefile, generator, shim, test, generated source,
or dependency bytes in the guest; do not repair an object or log in place. If
the failure exposes a source defect, follow the corrective-source invalidation
rule above, including native dependency regeneration and return, final host
review, and a new nonexistent final destination.

If no source correction is required and the cause is confined to an approved
environment or tool selection, preserve the failure, restore and prove all
guest-global and prefix postconditions, recheck the unchanged final host source
and executable-mode manifests, and use a new nonexistent final destination.
Repeat the complete fresh qualification from guest/tool identification through
all pre-install tests and audits; do not resume only at the failed producer.
The approved install root must still pass its complete absence or explicit-
replacement precondition.

For this retry rule, a final qualification destination is task-owned only if
its shared creation-and-ownership gate succeeded. A selected-but-not-created
path or foreign-or-ownership-unproven work-tree collision is recorded with its
exact sentinel and no-action proof and is not a rejected tree that this task
may retain as its own or remove.

Except while performing the narrowly authorized same-artifact read-only
recapture below, every final qualification destination belonging to a failed,
interrupted, unknown, incomplete, path-incomplete, unmappable, or contradictory
attempt is a rejected tree once that attempt stops or is superseded; it is
never an accepted result or a retry source. Record its exact canonical path and
rejected status and retain it by default with a complete final identity
inventory using the common schema. Removal requires explicit user
authorization, re-resolution and disjointness of the exact root, and an exact
match between its complete current identity inventory and that recorded final
inventory; remove only that exact root and prove it is absent. Close and report
every rejected destination's retained or removed postcondition before the
final protected-prefix comparison, so stale trees cannot be mistaken for the
accepted final qualification tree.

Only a failed capture of otherwise successful, strictly read-only evidence may
be repeated against the same artifacts. Before doing so, prove that the
producer's exact status was zero, that the command could not modify the source,
build products, prefixes, or guest-global state, and that every input artifact,
including the capture tool executable, retains its canonical absolute path and
complete recorded common-schema identity tuple: entry type, mode, server and
device, Qid type/version/path, ownership fields, byte length, and content hash.
Where an input belongs to an inventoried tree, also require its canonical root
and raw root-relative path to match that inventory. Preserve both captures and
all identity comparisons. This exception cannot rehabilitate a failed or
unknown configure, build, test, install, or stateful audit. If the recapture
does not complete the otherwise successful evidence set, close the destination
under the rejected-tree postcondition above.

### 5. Fresh native qualification

On the confirmed guest:

1. Record guest release, `cputype`, `objtype`, configured host identity,
   compiler/assembler/archive tools, and GNU Make path. Select the exact final
   source destination and apply the shared creation-and-ownership gate before
   population, preserving its canonical path and initial empty identity
   inventory. A failed gate stops this attempt with the applicable unowned-path
   sentinel.
2. Verify the accepted amd64 release assumptions or stop.
3. Transfer only the final reviewed source into that task-owned destination,
   restore and verify the authoritative executable-mode manifest, then produce
   and compare the authoritative host and pre-configure native content
   manifests in the fresh artifact-free destination.
4. Observe and enforce the approved-prefix absence or exact-replacement
   precondition, record the known-working-prefix complete identity inventory
   using the common schema or its absence sentinel, resolve and record the
   guest `tr` shim/delegate chain, and pass the required byte probe.
5. Configure with the exact approved `--prefix` override and require status
   zero. Verify the complete effective destination table and clean install-
   control environment, then run the exact `build-world.sh` command and require
   status zero, including the corrected tracked runtime-definition generator.
6. Build the repository `dumpobj`, preserve the complete `plan9_fd.cmo`
   disassembly, and perform the required transient-I/O bytecode audit.
7. Run the exact ordinary Plan 9 test target with a new reviewed `TEST_SUFFIX`
   and require status zero for all Phase 0, Phase 1.1, Phase 1.2, and Phase 1.3
   focused tests and every existing Plan 9 regression.
8. Perform the complete source, symbol, primitive, descriptor, archive, and
   installation-selection audits.
9. If approved, repeat and pass the immediate pre-install prefix check, install
   into the isolated prefix, record the exact install status, and capture the
   complete immediate post-install ownership baseline even after a nonzero,
   interrupted, or unknown result. On any result other than exact zero, do not
   select or create a consumer workspace; record its exact not-created sentinel,
   skip installed qualification, enforce step 10, and do not retry over that
   root. After exact zero, require the complete consumer creation and task-
   ownership gate before running the environment-isolated public smoke and
   negative-surface probes. A failed creation or ownership gate records the
   exact selected-but-not-created or foreign-or-ownership-unproven collision
   sentinel, skips those probes, makes the final attempt unsuccessful, and
   proceeds to step 10 without selecting another path.
10. Preserve the installed evidence, reproduce and match the ownership baseline,
    enforce and prove the approved isolated-prefix retain/remove postcondition
    even after a failed post-install check. If a task-owned consumer workspace
    was established, enforce and record its exact qualification status,
    complete final identity inventory, and retained-by-default or explicitly
    authorized removed
    postcondition. If no path was selected, record the exact not-created
    sentinel; if a selected path remained absent, record the exact selected-
    but-not-created sentinel; if it exists without proved ownership, record the
    collision sentinel and leave it untouched. Apply no consumer retain/remove
    action in every unowned branch. Close every auxiliary and rejected-tree
    postcondition and complete any other separately authorized cleanup. Then
    stop all source-tree writes, record the final source/build tree identity
    inventory, and enforce its retained-by-default or explicitly authorized
    removed postcondition without assigning the accepted-final label. Only
    after all of those actions are closed, record the known-working-prefix
    final complete identity inventory or absence sentinel.
11. Record and prove the remaining descriptor, process, temporary-file, guest,
    VM, listener, and writable-disk postconditions, together with every
    consumer-directory, not-created, selected-but-not-created, or foreign-or-
    ownership-unproven collision sentinel. If every preceding criterion and
    this complete postcondition set succeeded, assign the final source/build
    destination its accepted-final label and complete the attempt. Include its
    canonical path, complete final identity inventory, proved retained or
    removed postcondition, and, for an authorized removal, exact pre-removal
    match and absence proof. Otherwise withhold the label and report the tree
    under the rejected-destination rule with its proved disposition.

### 6. Report and stop

Do not begin `Plan9.In_channel`, process migration, capture, command
convenience, merge, tag, release publication, or Caml9 changes. Commit and push
only if the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact Phase 1.3 documentation-checkpoint identity and ancestry, plus the
  implementation-only, complete Phase 1.3, and cumulative Phase 1 diff
  baselines and results;
- final public `Plan9.Fd` API, source-tree README/reference updates, and
  installed public `plan9.cmi`;
- exact production read/write binding shapes and primitive-import delta, plus
  the exact uninstalled `Plan9_fd.Primitive` and `Plan9_fd.S` read/write
  signatures, matching `Private` submodule additions, and production-adapter
  mapping;
- exact public and attachment-owner range, chunk, read, write, and close
  semantics;
- the exact wrapper-synthesized range, read-protocol, write-protocol, and short-
  write operation/kind/message templates and byte-for-byte fake-backend
  results, alongside the separate lifecycle and mapped-native-error evidence;
- exact transient public-I/O and owner-I/O representations, complete
  reentrant-call and exception matrices, stable-state restoration proof, and
  retained zero-success and preallocated full-write-success proofs;
- fake-backend call traces and malformed-result evidence, including the exact
  range-before-lifecycle-and-authorization cross-state matrix for public and
  private reads and writes;
- split error evidence: exact high-level read/write mapping from the fake
  backend and exact native capture/message preservation from the unchanged
  Phase 0 negative-path probe;
- native binary, boundary, EOF, alias, attachment, GC, repeated-cycle, and
  descriptor-inventory results;
- complete Phase 0, Phase 1.1, Phase 1.2, and Phase 1.3 focused-suite results
  plus every existing regression result;
- cumulative Phase 1 source/symbol audit and scoped APE-independence
  conclusion, including the exact five raw entries, four runtime-integration
  `CAMLprim` definitions, four `Plan9_primitive` descriptor imports and exact
  read/write delta, separate raw-`ERRSTR` capture and
  `Plan9_types.error_of_native` evidence, exact raw-veneer, selected runtime-
  integration, `plan9_fd.cmo`, and `Plan9_primitive` artifact identities and
  commands, and the explicit whole-archive/whole-runtime exclusions;
- primitive uniqueness, public-CMI-only installation, and ML-only
  `plan9.cma` evidence;
- authoritative native dependency-generation command and status, successful
  completeness checks, returned `.depend` identity, expected DAG, rejected
  failed/partial artifact identities, restoration/retry history, and final host
  review, plus every newly selected non-final dependency tree's creation gate,
  canonical path, initial empty identity inventory, purpose/status label, and
  retained complete final identity inventory or explicitly authorized exact-
  path removal and absence proof, or its selected-but-not-created or work-tree
  collision sentinel and no-action proof;
- generator portability diff, cross-platform equivalence evidence, resolved
  guest `tr` shim/delegate identities and dispatch chain, and guest byte-probe
  evidence;
- native `dumpobj` tool/object identities, complete output location, mapped
  transient-I/O control-flow regions, boundary PCs, branch/switch coverage,
  allocation/callback/safe-point audit, and ordinary `RERAISE` evidence;
- exact configure and `build-world.sh` commands, environments, complete output,
  zero statuses, effective install-destination table, empty `DESTDIR`, reviewed
  GNU Make control variables, exact ordinary test command and new valid
  `TEST_SUFFIX`, complete output, and zero status;
- every failed, interrupted, unknown, incomplete, or contradictory final-
  qualification attempt, preserved evidence and postconditions, its classified
  source-correction, new-destination, or read-only-recapture lane, and the
  complete successful replacement chain; plus every rejected final
  destination's canonical path, rejected label, and retained complete identity
  inventory or explicitly authorized exact-path removal and absence proof, and
  for each read-only recapture the complete common-schema identity match for
  every input artifact and capture tool;
- transfer-set basis, additions/deletions, untracked/ignored inventories,
  exclusions, complete index-mode inventory, exact `flexdll` gitlink identity
  and non-transfer proof, executable-mode manifest and verification, matching
  content manifests, hash algorithm, and artifact-free native destination; the
  final destination's exact creation command/status, canonical path,
  disjointness, initial empty identity inventory and task-ownership proof, or
  its selected-but-not-created or work-tree collision sentinel and no-action
  proof; plus the exact common identity-inventory hash tool/algorithm, lowercase-
  digest rule, field order, length-prefixed encoding, and raw-path sorting
  method used for every retained, compared, or removed tree;
- approved-prefix pre-configuration and immediate pre-install observations,
  any replacement's complete pre-removal identity inventory, exact-root
  removal, post-removal absence proof, exact configure override, complete
  effective destination and environment verification repeated before install,
  exact install command and zero/nonzero/interrupted/unknown status, evidence
  that no qualifying probe followed a nonzero, interrupted, or unknown status,
  any newly directed retry's absent-or-explicit-replacement root and no-overlay
  proof, fresh consumer-directory evidence, its not-created or selected-but-
  not-created sentinel, or its foreign-or-ownership-unproven collision sentinel,
  build/installed CMI and archive identities plus isolated smoke evidence after
  an exact zero status, or the exact skipped-installed-qualification criterion,
  and proof by matching canonical roots and complete common-schema protected-
  prefix identity inventories, including
  every entry's server/device, Qid, mode, and ownership identity and each
  regular file's length and hash, or by matching absence sentinels, that the
  known-working prefix was unchanged, or the exact open criterion;
- the approved isolated-prefix final postcondition, its final retained identity
  inventory or final-cleanup pre-removal identity inventory and post-removal
  absence proof, the immediate post-install complete identity-inventory
  ownership baseline and exact pre-cleanup comparison, any mismatch/stop
  evidence, and confirmation that the protected-prefix comparison occurred
  afterward;
- the exact resolved `+plan9` inventory command and two-regular-file result,
  the complete fresh-prefix exact-basename negative-search command and result,
  and explicit `README.md`/`REFERENCE.md` absence from `+plan9`;
- repository paths, source-manifest identities, and copied-source identities
  for the positive smoke and both negative probes; the exact positive compile
  and execution commands and results; and the exact negative compile commands,
  intended source locations, statuses, absent output artifacts, and specific
  diagnostics proving `Plan9.Fd.Private` and top-level `Plan9_fd` are
  unavailable;
- for a task-owned consumer directory, its canonical path and disjointness
  proof, absent and exact-zero creation checks, complete initial empty identity
  inventory, exact three-source precompile identity inventory, exact successful,
  failed, interrupted, unknown, or incomplete qualification status and reason,
  complete final identity inventory including partial outputs, and retained
  inventory or explicitly authorized exact-path removal and absence proof; or,
  if no task-owned directory was established after any install status, the
  exact not-created, selected-but-not-created, or foreign-or-ownership-unproven
  collision sentinel, creation/identity failure reason, applicable read-only
  observation, and confirmation that no consumer retain/remove action was
  applied;
- the final fresh source/build tree's canonical path and complete final
  identity inventory, its retained postcondition or explicitly authorized exact
  pre-removal match and absence proof completed before the protected-prefix
  final comparison, that comparison's result, every subsequent descriptor,
  process, temporary-file, guest, VM, listener, and writable-disk postcondition,
  and only after all succeeded its accepted-final label; or the exact failure,
  withheld-label, and rejected-tree disposition; and
- exactly one final recommendation:
  - **Phase 1 accepted; ready to design `Plan9.In_channel`**;
  - **implementation ready but native qualification still required**; or
  - **Phase 1 blocked or rejected**, with the exact reason.

## Strict exclusions

This handoff does not authorize `Plan9.In_channel`, output channels, files,
stat, directories, environment migration, process migration, capture, new
runtime primitives, timing-sensitive note injection, standard-descriptor or
foreign-descriptor adoption, VM snapshots, merge, release publication, or
Caml9 changes.
