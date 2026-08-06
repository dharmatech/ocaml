# Phase 1.3 `Plan9.Fd` byte I/O and final acceptance handoff

Status: draft execution handoff for review; starts only after accepted Phase
1.2

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
`codex/plan9-native-io-foundation`. The executing request must name the exact
accepted Phase 1.2 checkpoint and its reviewed documentation predecessor.
Verify a clean index and worktree, expected branch and remote tracking, and no
unrelated history.

Do not begin from an uncommitted, dirty, unqualified, or rejected Phase 1.2.
Do not stash, reset, clean, or absorb unrelated work.

## Accepted predecessor facts

Phase 0 supplies an accepted private primitive transfer capacity of 4096
bytes. Each primitive read or write validates its capability and arguments,
processes pending actions, revalidates callback-mutable state, stages bytes
outside the movable OCaml heap, invokes at most one raw syscall for exactly the
positive requested count, validates the returned count, and captures native
failure immediately. The primitive never loops or clamps.

Phase 1.1 supplies the private type and primitive modules. Phase 1.2 supplies
the production descriptor capability, pipe, and close bindings plus the
uninstalled `Plan9_fd` functor and production instance, allocation-safe pipe
wrapper, shared ownership lifecycle, deterministic close, and exact private
attachment-token authorization. It is not yet public and has no production
read/write bindings or typed byte I/O.

This subphase consumes the accepted primitive and ownership boundaries. If a
runtime primitive change appears necessary, stop and review the evidence
rather than silently reopening Phase 0.

## Delegated outcome

Extend `Plan9_primitive` with production bindings for the accepted descriptor
read and write primitives. Complete `Plan9_fd` with typed public-owner and
private-attached-owner reads and writes, publish the complete `Plan9.Fd`
module, add focused and public tests, update installed documentation, and
perform the complete fresh native and installed-prefix acceptance gate for
Phase 1.

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
invalid position/length relationship in a stable message without relying on
an overflowing sum.

After range validation, authorize the owner:

- a public call requires the stable open-and-detached state;
- public-closing, publicly closed, attached, owner-closing, and owner-closed
  cells reject every public read and write;
- a private call requires both the stable attached state and the exact
  committed attachment token;
- a stale, uncommitted, or losing token rejects I/O in every state;
- even the exact committed token rejects I/O while its owner-close attempt is
  active or inactive, and after the cell is owner-closed; and
- invalid lifecycle or authorization returns `Invalid_argument` without a
  primitive call.

The public operation names remain `Plan9.Fd.read` and `Plan9.Fd.write` even
when a private attached owner performs the operation on behalf of a later
public module. Phase 2 will assign its own higher-level operation when it needs
to wrap or contextualize an `Fd` error; Phase 1 does not erase the exact lower
operation.

For a valid authorized owner and valid range, `len:0` returns `Ok 0` without a
primitive call. Validation still occurs, so zero length cannot revive a
closed handle or bypass attachment authority. A zero-length write emits no
pipe message, and a zero-length read consumes no byte.

## One-transfer public-call policy

The exact capacity `4096` remains private and absent from `plan9.mli`, README
API signatures, and the installed reference. `Plan9_primitive` or
`Plan9_fd` may hold a private synchronized ML constant for chunk selection;
source review and focused tests must prove it matches the accepted primitive
capacity.

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
`primitive_count`. On native failure, return
`Plan9_types.error_of_native "Plan9.Fd.read" failure` without retry.

On success `(staging, count)`, defensively verify before indexing or copying:

- `Bytes.length staging = primitive_count`;
- `count >= 0`; and
- `count <= primitive_count`.

Although the accepted primitive already guarantees these facts, the ML layer
must not turn a future integration regression into an out-of-bounds blit. An
invalid success shape becomes `Protocol_error` and does not modify the caller
destination.

For a valid count, copy exactly `count` bytes from staging offset zero into the
caller destination at `pos`, leave every destination byte outside that prefix
unchanged, and return `Ok count`. A positive short count is normal. `Ok 0` for
a positive request is EOF. Embedded NUL is ordinary data.

Do not copy the deterministically zeroed staging tail. Do not retry an
interrupted read: Plan 9 documents that an interrupted pipe operation may have
transferred an unknown number of bytes. A returned read error leaves the
caller destination unchanged because native bytes never entered it.

## Write behavior

Call the accepted primitive write with the original caller `bytes`, original
`pos`, and `primitive_count`; do not allocate or pre-slice a per-chunk ML byte
block. The primitive owns post-pending-action source revalidation and native
staging of the current slice.

On native failure, return
`Plan9_types.error_of_native "Plan9.Fd.write" failure` without retry. The
source is never mutated.

On success, defensively require `0 <= count <= primitive_count`. A count larger
than the exact primitive request or a negative typed fake-backend result is a
`Protocol_error` and must never become an index or progress value.

For a positive primitive request:

- `count = primitive_count` returns `Ok count`;
- `0 <= count < primitive_count` is an actual native short write and returns a
  structured `Other` error naming `Plan9.Fd.write` and recording both the
  exact requested and written counts; and
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

Extend the Phase 1.2 private token interface with typed `read` and `write`
operations having the same byte range, one-transfer, error, short-I/O,
zero-length, and interruption semantics as the public functions. The only
difference is authorization: the exact committed token may operate only while
the cell remains in the stable attached state, while all public aliases
reject. Once owner close begins, both its active and inactive attempt states
reject I/O through every token without primitive work.

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
- possible positive read progress, EOF, and wrapper-limited progress;
- native short-write error and no implicit retry; and
- explicit deterministic close with no finalizer.

Re-export the production `Plan9_fd` implementation from `plan9.ml` while the
installed CMI hides its private functor and attachment interface.

Update `otherlibs/plan9/README.md` and `REFERENCE.md` to include only the
accepted public API and user-visible semantics. Do not document private
capacity, primitive names, capability representation, token types, or source
module names as public contracts.

The public examples use ordinary `Plan9.Fd.pipe`, explicit result handling,
byte buffers, returned counts, and deterministic close. They must not imply
Unix-directional endpoints, automatic exact writes, standard-channel
conversion, finalizer cleanup, or descriptor integer access.

Only `plan9.cmi` is installed. `plan9_types.cmi`, `plan9_primitive.cmi`,
`plan9_process.cmi`, and `plan9_fd.cmi` remain uninstalled. `plan9.cma` remains
ML-only.

## Required fake-backend tests

Extend the focused functor test or add one clearly owned Phase 1 test program.
The fake backend records read/write calls and supplies controlled results. At
minimum, prove:

- exact invalid ranges `(-1, 0)`, `(0, -1)`,
  `(buffer_length + 1, 0)`, `(buffer_length, 1)`, `(max_int, 1)`, and
  `(1, max_int)` return `Invalid_argument` without a backend call;
- valid `(buffer_length, 0)` succeeds only on an authorized open owner and
  performs no backend call;
- closed and attached public owners reject zero and nonzero lengths without a
  backend call;
- stale, losing, uncommitted, and closed attachment tokens reject I/O without
  a backend call;
- a logical request of exactly the private capacity produces one backend call
  of that size;
- a request of capacity plus one and a request of `max_int` each produce one
  backend call of exactly the private capacity, with no overflow or large ML
  staging allocation;
- read copies only the valid returned prefix at the requested destination
  offset and leaves prefix, suffix, and short-result tail bytes unchanged;
- read preserves embedded NUL and returns zero as EOF;
- malformed read staging length, negative count, and oversized count become
  `Protocol_error` without destination mutation;
- a full write returns the primitive chunk count;
- a synthesized positive short write and zero write for a positive request
  return the structured short-write error after exactly one backend call and
  never issue a remainder;
- an oversized or negative fake write count becomes `Protocol_error`;
- native-failure mapping preserves operation, kind, and exact message; and
- committed attachment-owner I/O follows the same transfer policy while
  public aliases remain rejected.

Use the fake backend, not a production fault switch, to synthesize impossible
or timing-sensitive results.

## Required native and public tests

Add a production `Plan9.Fd` focused test and an installed-consumer smoke source
under `otherlibs/plan9/tests` as appropriate. At minimum, prove:

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
- native error operation and exact message are preserved;
- 256 or another reviewed deterministic repeated lifecycle/I/O cycles leave
  the sorted complete `/fd` inventory unchanged;
- forced minor and major GC with live public and attached owners does not lose
  or duplicate ownership; and
- the complete Phase 0 hostile primitive matrix still rejects forged,
  wrong-state, and closed capabilities before native work.

Source review and fake call counts prove interruption is not retried. Actual
timing-sensitive note injection is not part of ordinary Phase 1 acceptance and
requires separate explicit authorization if later desired.

Run every existing Plan 9 environment, process, raw-syscall, primitive, and
native-integration regression unchanged in addition to the new focused tests.

## Complete source, symbol, and packaging audit

Review and record:

- typed range validation and overflow avoidance;
- exact lifecycle/token authorization before zero-length success or native
  work;
- private chunk selection and one primitive call per public call;
- read result validation before blit and exact prefix-only copy;
- write result classification, no short-write retry, and no per-chunk source
  copy in ML;
- identical public and attachment-owner transfer policy;
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
- absence of forbidden APE I/O/process/private-entry references in the
  accepted descriptor-path objects;
- ML-only `plan9.cma`; and
- installation of exactly the public CMI and intended archive/reference files,
  with no internal CMI.

No report may generalize the descriptor-path APE-independence proof to the
whole runtime or to existing `Env`, `Raw`, or `Process` implementations.

## Fresh source and installed-prefix acceptance

Final qualification starts from a fresh, previously nonexistent native
destination containing exactly the approved source set from the reviewed
Windows worktree. Follow the foundation's Phase 0 manifest discipline:

- derive the transfer set from every existing path reported by `git ls-files`
  using current worktree bytes, adjusted only for explicitly reviewed new or
  deleted paths;
- record complete untracked and ignored inventories separately;
- transfer no `.git`, build artifact, or unrelated path;
- emit canonical repository-relative path, decimal length, and lowercase
  digest tuples with one reviewed hash algorithm on host and guest;
- compare parsed, bytewise-path-sorted manifests and prove the destination has
  no extra file; and
- configure and build only after manifests match.

Ask the user to approve an isolated, nonexistent install prefix or explicitly
approve replacement, plus its retain/remove postcondition. Never modify the
known-working `/usr/glenda/lib/unix/ocaml-4.14.3`; record sorted path, length,
and content-hash manifests before and after qualification.

Outside source and build trees, compile the manifest-verified public smoke
source using exactly the ordinary consumer shape:

```text
<installed ocamlc> -I +plan9 -linkall plan9.cma <fd smoke>.ml -o <smoke>
```

Run it with the installed `ocamlrun`. Use no `-custom`, `-use-runtime`, C
compiler, linker, wrapper compiler, additional archive, source-tree include,
or competing `plan9.cma`. Unset `OCAMLPARAM`, `OCAMLLIB`, legacy `CAMLLIB`, and
`CAML_LD_LIBRARY_PATH`. Record:

- exact compiler and runtime paths;
- exact `ocamlc -where`, proven inside the approved prefix;
- resolution of `+plan9` to that prefix's `plan9` directory;
- path, size, and content hash of installed `plan9.cma`, `plan9.cmi`, and
  installed public reference material;
- absence of internal CMIs from the installed directory;
- ML-only archive evidence; and
- successful public `Fd` pipe, binary I/O, EOF, alias close, and repeated
  descriptor-cleanup behavior under the installed runtime.

If installation is not authorized or any environment-isolation condition is
not met, report the criterion as open and do not declare Phase 1 accepted.

## Execution sequence and mandatory pauses

### 1. Preflight and implementation

Record Git state, complete untracked and ignored inventories, accepted Phase
1.1/1.2 identities, ownership interfaces, primitive capacity and shapes,
public documentation state, build rules, and test inventory. Implement only
the production descriptor read/write bindings, typed byte I/O, final public
integration, documentation, and focused tests.

### 2. Source review before VM work

Run all safe host-side checks and inspect the complete diff from accepted Phase
1.2 and the cumulative Phase 1 diff from the reviewed Phase 1 documentation
checkpoint. Report range, chunk, count, copy, short-write, error, lifecycle,
attachment, publication, and packaging behavior. Stop before VM access.

### 3. Explicit VM and prefix confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, and WHPX profile. Ask separately for the isolated
install prefix, create/replace action, and retain/remove postcondition. Never
boot a protected checkpoint, guess an endpoint, share a writable disk, take
an unauthorized snapshot, or overwrite the known-working prefix.

Use the repository VM and native-build skills. Transfer without `.git` through
`/mnt/term`, copy onto native storage, and never build on `/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record guest release, `cputype`, `objtype`, configured host identity,
   compiler/assembler/archive tools, GNU Make path, and source destination.
2. Verify the accepted amd64 release assumptions or stop.
3. Produce and compare the authoritative host and pre-configure native
   manifests in the fresh artifact-free destination.
4. Configure and build the standard bytecode runtime and Plan 9 library.
5. Run all Phase 0, Phase 1.1, Phase 1.2, and Phase 1.3 focused tests and every
   existing Plan 9 regression.
6. Perform the complete source, symbol, primitive, descriptor, archive, and
   installation-selection audits.
7. If approved, install into the isolated prefix and run the environment-
   isolated public smoke test.
8. Record descriptor, process, temporary-file, source-tree, prefix, VM,
   listener, and writable-disk postconditions.

### 5. Report and stop

Do not begin `Plan9.In_channel`, process migration, capture, command
convenience, merge, tag, release publication, or Caml9 changes. Commit and push
only if the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- final public `Plan9.Fd` API and installed documentation;
- exact production read/write binding shapes and primitive-import delta;
- exact public and attachment-owner range, chunk, read, write, and close
  semantics;
- fake-backend call traces and malformed-result evidence;
- native binary, boundary, EOF, alias, attachment, GC, repeated-cycle, and
  descriptor-inventory results;
- complete Phase 0 and existing regression results;
- cumulative Phase 1 source/symbol audit and scoped APE-independence
  conclusion;
- primitive uniqueness, public-CMI-only installation, and ML-only
  `plan9.cma` evidence;
- transfer-set basis, additions/deletions, untracked/ignored inventories,
  exclusions, matching manifests, hash algorithm, and artifact-free native
  destination;
- approved prefix, isolated smoke evidence, and proof the known-working prefix
  was unchanged, or the exact open criterion;
- cleanup and VM postconditions; and
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
