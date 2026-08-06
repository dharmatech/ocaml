# Phase 0.3 byte I/O and final acceptance handoff

Status: reviewed execution handoff; Phase 0.1 accepted at
`0d3ac056a37e597e9673607de591cb8a0b5247bb`; Phase 0.2 accepted at
`f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`

## Authority and required reading

This handoff delegates only Phase 0.3 and final Phase 0 qualification. Before
editing, read:

- `docs/design/handoffs/plan9-native-syscall-veneer-phase0.md` completely;
- the accepted predecessor facts below and the implementation diffs from
  `4209e21088f8ba0f5c5985fcec79e41d4cffcb77` through
  `0d3ac056a37e597e9673607de591cb8a0b5247bb`, and from
  `3c2fe24efb50aff2b7b00795868228712e01848a` through
  `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`;
- the foundation's APE-independence boundary, qualified source facts, private
  syscall veneer sections on capability defense, error handling, OCaml
  heap/blocking sections and staging, proposed source boundary, complete Phase
  0 acceptance criteria, explicit non-goals, and required reports;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before their actions occur.

If either predecessor differs from the accepted facts below, or this handoff
conflicts with the roadmap or foundation, stop and return the evidence.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. The accepted Phase 0.2 code predecessor is
exactly `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`. The executing request must
name the exact user-approved documentation-checkpoint `HEAD` created after
this review. Verify that the starting `HEAD` descends directly from the
accepted predecessor with only reviewed documentation changes after it, and
that the index and worktree are clean with no unexpected history.

Do not begin from an uncommitted, dirty, unqualified, or rejected predecessor.
Do not stash, reset, clean, or absorb unrelated work.

## Accepted predecessor facts

Phase 0.1 was accepted at
`0d3ac056a37e597e9673607de591cb8a0b5247bb` (`plan9: add raw amd64 syscall
veneer`). Phase 0.2 was accepted at
`f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b` (`plan9: add syscall capability
lifecycle`), whose documentation predecessor is
`3c2fe24efb50aff2b7b00795868228712e01848a`.

The accepted Phase 0.2 private capability is a runtime-owned custom block with
an exact two-`int` payload containing lifecycle state and descriptor. Its only
consistent pairs are `unpublished`/`-1`, `open`/nonnegative, and
`closed`/`-1`; its private operations identifier is exactly
`_ocaml_plan9_syscall_capability_v1`. It has no finalizer and exposes no
descriptor to ML. Its accepted built-in primitives are
`caml_plan9_syscall_pipe`, `caml_plan9_syscall_close`, and
`caml_plan9_syscall_negative_read_probe`, with logical results
`((capability * capability), native_failure) result`,
`(unit, native_failure) result`, and `native_failure`, respectively. The
private failure kinds remain invalid `0`, other native error `1`, interrupted
`2`, no children `3`, and protocol failure `4`. Phase 0.3 must extend that
representation and the existing static validation/failure helpers in
`runtime/plan9_syscall.c`, not refactor the accepted lifecycle.

Native qualification used the standard bytecode runtime configured as
`HOST=x86_64-unknown-plan9`, `ARCH=none`, and `O=o`, with no native-code,
shared-library, or systhreads lane. On release 11554, the Phase 0.1 raw harness
retained its behavior, the focused ML test completed 256 capability cycles,
every primitive had one generated-table entry and one linked definition, and
`plan9.cma` remained ML-only. No installation occurred and the known-working
prefix `/usr/glenda/lib/unix/ocaml-4.14.3` was unchanged.

Earlier native build trees and the `q002` qualification instance may be used
only as read-only evidence or diagnostics. Final Phase 0.3 qualification must
use a fresh, artifact-free copy of the exact approved source set from the
reviewed Windows worktree and must not reuse their objects, archives,
generated primitive tables, or binaries.

## Delegated outcome

Complete the private runtime proof by adding validated logical byte read and
write primitives over the accepted opaque capability and raw `PREAD`/`PWRITE`
entries. Then perform the complete Phase 0 acceptance gate.

This subphase implements:

- bounded native staging;
- defensive argument and capability validation;
- pending-action ordering and revalidation;
- GC-safe preallocation and rooting;
- exact publication of valid native counts;
- EOF, positive-short, zero-length, and interruption semantics;
- the complete private ML test; and
- final fresh-build, regression, symbol, cleanup, and installed-prefix proof.

It adds no public `Plan9` API, `Plan9.Fd`, process change, capture behavior, or
C payload to `plan9.cma`.

## Exact private primitive ABI

Extend the existing focused private ML test with exactly these logical
bindings:

```ocaml
external private_read :
  capability -> int -> ((bytes * int), native_failure) result
  = "caml_plan9_syscall_read"

external private_write :
  capability -> bytes -> int -> int ->
  (int, native_failure) result
  = "caml_plan9_syscall_write"
```

Read takes a capability and requested length; it has no position argument.
Write takes a capability, source bytes, source position, and requested length.
The write position is an ML source index, not a native file offset. Both raw
syscalls continue to use `CAML_PLAN9_SYSCALL_STREAM_OFFSET`.

Manual C construction must use these exact layouts:

- a read-success pair is a tag-`0`, two-word block whose field `0` is the
  rooted fresh byte block and whose field `1` is `Val_int(count)`;
- `Ok read_pair` is a tag-`0`, one-word block containing that rooted pair;
- `Ok write_count` is a tag-`0`, one-word block containing `Val_int(count)`;
- `native_failure` remains the accepted tag-`0`, two-word block containing
  `Val_int(native_kind)` and the rooted message string; and
- `Error native_failure` remains a tag-`1`, one-word block containing that
  rooted failure record.

Before any later allocation, initialize exactly the fresh read value's
`requested_length` logical payload bytes to zero. Preserve the OCaml block
header, padding, and trailing string-length offset byte established by the
runtime allocator. Then initialize the read pair to the rooted byte block and
count zero, initialize the enclosing read `Ok` to that pair, and initialize
the write `Ok` field to `Val_int(0)`. Do not mark either external
`[@@noalloc]`.

## Defensive primitive contract

Correct-arity private primitive calls may receive arbitrary well-formed OCaml
values, including false types passed through `Obj.magic`. Preserve the accepted
Phase 0.2 threat boundary: wrong external arities and unsafe mutation,
truncation, retagging, or duplication of a valid capability are out of scope,
and no global registry or descriptor-closing finalizer is added.

For each operation, validate before native work:

- immediate/block shape and the exact expected argument kinds;
- capability tag, size, runtime identity, and open state in the accepted order;
- string-tagged write source shape;
- integer form and native representability of positions and lengths; and
- range validity without integer overflow.

The read length and write position and length must be immediate integers and
nonnegative. As with the accepted unit boundary, a false-typed value with the
identical immediate integer representation cannot and need not be
distinguished. For write, accept the runtime `String_tag` used by both OCaml
`string` and `bytes`; correct-arity hostile calls can supply either and the
runtime cannot distinguish them. Validate the source range using subtraction,
first `position <= source_length` and then
`length <= source_length - position`, never `position + length`.

Both lengths must be no greater than the exact private staging capacity of
4096 bytes. A larger request is a structured invalid-input failure of kind `0`
before pending processing or native work. Do not clamp a request to the
capacity: every valid primitive call issues either no syscall for length zero
or at most one raw syscall whose count is exactly the requested length.

No read or write primitive accepts or returns a raw descriptor integer. A
forged, closed, or wrong-state capability fails before native work, including
when the requested length is zero.

Neither primitive may allocate or construct an OCaml value while inside a
blocking section.

## Read primitive

The private read primitive has no caller-supplied byte block and must return a
fresh primitive-owned result.

Perform complete initial argument and open-capability validation before
allocating success. Then allocate and root a fresh byte result and
zero-initialize exactly its logical payload as specified above, preserving its
header, padding, and trailing string-length offset byte. Also allocate,
initialize to the exact GC-safe values specified above, and root every
structural success block required to return that value and the successful
count. No scanned block may contain uninitialized OCaml fields when a later
allocation can occur.

Before proceeding to native work, check for and process pending OCaml actions
with every live argument and preallocated result rooted. Pending processing may
allocate, invoke a callback, close the capability, or raise. Revalidate the
capability afterward.

After successful final open-capability validation, save the descriptor in a
native local without retaining a capability-payload or other heap-interior
pointer. Permit no allocation, safe point, callback, or pending-action
processing before `caml_enter_blocking_section_no_pending`. For a nonzero
request, this entry leads immediately to one raw read. The raw read receives
only a bounded native staging buffer, never a pointer into the movable OCaml
heap.

After leaving the blocking section, first classify the native result safely.
For a nonnegative result, verify that it is no greater than the exact count
passed to that raw call before using it as an index, copy length, or published
count. An oversized result becomes a structured protocol failure without any
out-of-bounds access.

For a valid result, copy only that prefix from staging into the fresh result
and publish the already allocated success value without another fallible
allocation. The unused tail remains deterministically zero. A result of zero
on a positive native request denotes EOF.

## Write primitive

Perform complete initial argument, source-range, and open-capability validation
before allocating success. Allocate and root the structural success result
before the post-callback sequence. Check and process pending actions while all
live values are rooted. Because a callback may mutate the caller-owned source
or close the capability, then:

1. revalidate the source shape and range;
2. copy the current requested slice into bounded native staging; and
3. perform final capability-state validation immediately before the
   non-pending blocking entry.

Permit no allocation, safe point, callback, or pending-action processing in
that sequence or between final capability validation and
`caml_enter_blocking_section_no_pending`. Final validation saves the descriptor
in a native local without retaining a capability-payload or source heap-interior
pointer. For a nonzero request, the non-pending entry leads immediately to one
raw write. The raw write receives only the staging buffer.

After leaving the blocking section, verify every nonnegative result is no
greater than the exact count requested in that raw call. Preserve every valid
positive count. Publish success without a fallible allocation after the count
passes validation.

Native `read(2)` permits positive short reads. Native `write(2)` says a short
write should be treated as an error. The primitive still preserves the actual
positive count so a higher layer can apply policy; it must not silently issue
the remainder. Wrapper-imposed staging chunks are distinct from a native
result smaller than the count passed to that individual raw call. A native
write result of zero for a positive request is likewise a valid preserved
`Ok 0`, not EOF or a protocol failure; the higher layer owns exact-write
policy.

## Zero-length and error behavior

Zero length follows the same full initial validation, success preallocation,
pending-action processing, post-callback source/range revalidation where
applicable, and final open-capability revalidation as a nonzero call. It then
returns the preallocated success without entering a blocking section or
issuing a native syscall. A capability closed by a pending callback therefore
still fails. A zero-length read returns `Ok (fresh_empty_bytes, 0)` and
consumes no queued byte. A zero-length write returns `Ok 0` and emits no Plan
9 pipe message, avoiding the native ambiguity between such a message and EOF.

Do not retry an interrupted native read or write. A negative raw result is
followed immediately by raw `ERRSTR` into an initially empty 128-byte buffer
before leaving the blocking section or performing cleanup. Only after that
text is preserved may code allocate the existing private native-failure value.
Do not consult `errno`, use `rerrstr`, or invoke an APE error helper.

After a native read or write result passes bounds validation and will be
published as success, no fallible allocation may occur before publication. A
safely classified protocol or native failure may allocate its result after
ownership and error text are safe.

## Staging capacity

Use an exact bounded per-call native staging capacity of 4096 bytes. It is
independent of total stream size, lies far below the native signed `long`
range, and is a conservative automatic-storage allocation under the qualified
release-11554 amd64 16 MiB user stack. It also remains below the qualified
64 KiB `Maxatomic` and the default 256 KiB pipe queue. Those native values are
justification, not a promise that the private capacity will become public.

The capacity stays private, uninstalled, and absent from public ML interfaces.
Larger logical operations are split into requests of at most 4096 bytes by the
test-local ML helper in this subphase and by the future owning layer later.
The primitive itself neither loops nor clamps. Tests must record the exact
per-call chunk sizes and distinguish those staging-imposed calls from a native
result smaller than the exact count passed to one raw call.

## Required focused tests

Extend the existing focused
`otherlibs/plan9/tests/syscall_capability_test.ml`; do not create a second
ordinary test program or production wrapper. The test remains private and
uninstalled and may declare the private external bindings and native-failure
shape directly. No new name appears in `plan9.mli` or installed reference
documentation.

Add pure-ML chunking helpers local to that test. Their native round-trip path
must use one original payload of exactly `2 * 4096 + 3` bytes. Without
pre-slicing or copying that write source into per-chunk ML blocks, issue and
record exact `(position, length)` write calls `(0, 4096)`, `(4096, 4096)`, and
`(8192, 3)`. Request reads in exact per-call lengths `4096`, `4096`, and `3`,
and verify multi-call completion. Place embedded NUL bytes on both sides of a
staging boundary and keep the total payload below the qualified default pipe
queue. Give the exact-write helper a fake low-level writer that returns
`requested - 1` on its first call. Verify that it reports failure after that
one invocation and never issues the remainder. Do not add, install, or expose
the helpers as production code; production exact-write behavior belongs to a
later owning layer.

At minimum, test and review:

- raw descriptor integers, malformed capability values, forged look-alikes,
  and wrong-state capabilities fail before native work;
- structurally distinguishable hostile correct-arity capability, source,
  position, and length values fail safely; use an `Int64` foreign custom block
  and a `Bigarray.Array1` foreign custom block as accepted well-formed
  counterexamples for every argument position where they have the wrong
  required shape;
- false-typed immediate aliases with the same representation as a valid
  integer follow that integer's semantics rather than being expected to fail;
  specifically exercise zero-valued aliases as write position zero and as
  zero read/write lengths;
- a deterministic numeric-boundary matrix proves that read lengths `-1`,
  `4097`, and `max_int` return invalid-input failure kind `0` before pending
  processing or native work, zero returns without native work, and the exact
  `4096` capacity is accepted on a data-ready capability;
- using a source whose `source_length` is at least `4097`, the write matrix
  uses exact invalid `(position, length)` tuples `(-1, 0)`, `(0, -1)`,
  `(source_length + 1, 0)`, `(source_length, 1)`, `(0, 4097)`,
  `(max_int, 1)`, and `(1, max_int)`; each returns invalid-input failure kind
  `0` before pending processing or native work;
- the same matrix proves that `(source_length, 0)` succeeds without native
  work and that `(1, 4096)` succeeds with the expected slice; the `max_int`
  tuples prove rejection without overflow, and the source-end cases exercise
  the required subtraction-based range validation rather than computing
  `position + length`;
- an ordinary OCaml `string` supplied through `Obj.magic` as the write source
  is accepted because it has `String_tag`, round-trips correctly, and is not
  mutated;
- validation checks outer shape, tag, size, and runtime-owned identity before
  representation-specific payload;
- reads and writes through a closed capability fail before native work;
- zero-length read and write on an open capability return zero without native
  work, while closed or forged capabilities remain errors;
- a zero-length read consumes no queued byte and a zero-length write emits no
  EOF-like pipe event;
- empty input is represented by closing the designated writer without issuing
  a zero-length write;
- an empty payload and a binary payload containing embedded NUL round-trip
  through a native pipe;
- the multi-chunk payload above round-trips exactly, with recorded primitive
  call counts, write positions, and read/write chunk sizes;
- a small completed native write followed by a larger read request produces a
  deterministic positive short read at the preserved write boundary;
- every read result byte block has exactly the requested chunk length; a short
  read exposes the exact returned-count prefix and retains a fully initialized,
  deterministically zeroed tail;
- every preallocated scanned success block has GC-safe contents before later
  allocation;
- every nonnegative native result is checked against the exact raw request
  before indexing, copying, or publication, with oversized results classified
  without an out-of-bounds access;
- source review proves that a positive native short-write count is preserved;
- source review proves that a zero native write result for a positive request
  is preserved as `Ok 0`;
- the test-local exact-write helper reports failure after one synthesized
  positive short count and makes no second call;
- source review distinguishes wrapper staging chunks from actual native short
  writes;
- pending actions run before native work and every callback-mutable state or
  write-source range is revalidated afterward;
- write staging captures the current post-callback source slice before final
  capability validation;
- on every nonzero native-work path, final capability validation is followed
  immediately by the non-pending entry, with no intervening allocation or safe
  point;
- no fallible allocation follows a validated successful count before its
  publication;
- closing the designated writer yields EOF only after buffered data is read;
- an open zero-length write followed by a nonzero write produces no EOF-like
  event, and an open zero-length read performed while one byte is queued leaves
  that byte for the following nonzero read;
- capability and write-source aliases remain valid after an explicit minor
  collection, full major collection, and compaction before I/O;
- both endpoints close and repeated round trips leave no descriptor behind;
- all Phase 0.1 raw-harness and Phase 0.2 capability/error tests retain their
  accepted behavior; and
- all existing `otherlibs/plan9` regression tests pass.

The focused test must not use an ordinary OCaml channel, `Unix`, `Sys.command`,
a temporary file, shell execution, APE descriptor registration, or another
process for the pipe path.

Use the accepted sorted complete `Sys.readdir "/fd"` inventory comparison for
descriptor postconditions. Exact pending-callback interleavings, impossible
oversized nonnegative raw results, and actual interrupted pipe I/O are
mandatory source-review obligations unless an existing safe deterministic
runtime mechanism makes them executable. Do not add a fault-injection
primitive, test hook, raw-descriptor exposure, or other private-ABI expansion
to reach them.

## Source and build boundary

Keep the implementation lean: extend the current static helpers and accepted
capability lifecycle in `runtime/plan9_syscall.c`, and extend the current
focused ML test. The existing build already selects that source and discovers
built-in primitive definitions. No `Makefile`, `dune`, primitive-generator,
public interface, `plan9.cma` payload, or general file abstraction change is
expected; justify any such change if inspection proves one genuinely
necessary. Do not refactor Phase 0.2 merely while adding Phase 0.3.

## Complete symbol and source audit

Inspect the raw assembly and runtime integration objects separately. Record
commands and relevant output proving that:

- the raw object has no undefined library calls;
- the new objects neither define nor reference `_PIPE`, `_PREAD`, `_READ`,
  `_PWRITE`, `_WRITE`, `_CLOSE`, `_ERRSTR`, `_WAIT`, ordinary `pipe`, `read`,
  `write`, or `close` as their operating-system path;
- only repository-prefixed raw entries issue the selected syscalls;
- source contains no `_fdinfo`, raw ML descriptor conversion, `errno`
  translation, ordinary-channel conversion, APE registration, or private
  `sys9.h` inclusion in the new path;
- every private primitive appears exactly once in the generated table and has
  one linked definition; and
- the source has exactly one definition line beginning `CAMLprim value` for
  each exact name `caml_plan9_syscall_read` and
  `caml_plan9_syscall_write`; and
- unrelated whole-runtime APE symbols are not misreported as dependencies of
  the isolated five-operation path.

If the expected symbol utility is unavailable, determine and document the
narrow native equivalent rather than weakening the criterion.

## Build and installed-prefix acceptance

Final qualification must start from a fresh, artifact-free copy of the exact
approved source set from the reviewed Windows worktree, placed on native Plan
9 storage. Configure and build without reusing objects, archives, generated
primitive tables, or binaries from an earlier native build.

Immediately after the final host-side source review and before transfer,
define the approved transfer set from every existing worktree file at a path
reported by `git ls-files`, using current worktree bytes rather than index or
`HEAD` contents. Record any reviewed deletion and add only explicitly reviewed
new source paths. No new source path is expected in Phase 0.3; report and
justify one before VM work if inspection proves it necessary. Separately
record complete untracked and ignored path inventories without modifying,
deleting, stashing, or transferring any path outside the approved set. Never
transfer `.git`.

Record a manifest of that approved source set and copy only that set into a
new, previously nonexistent native destination. Before configure,
independently produce the same manifest on the native copy with the same
content-hash algorithm and require an exact match. Each side must emit one
canonical tuple per transferred file: a `/`-separated repository-relative
path, decimal byte length, and lowercase hexadecimal digest. Sort tuples
bytewise by normalized path and compare the parsed tuples rather than raw,
tool-decorated output. Store manifests and comparison evidence outside both
source trees so producing them cannot change the compared population. Verify
that `.git` is absent and that the destination contains exactly the manifested
set, with no additional file or output from an earlier configure or build.
Record the transfer-set basis, reviewed additions or deletions, untracked and
ignored inventories, exclusions, manifest commands, tool identities, hash
algorithm, comparison result, and destination. A Git commit identity by itself
does not satisfy this gate because the reviewed runtime changes are
intentionally uncommitted during native qualification.

Verify that:

- the standard amd64 Plan 9 `ocamlrun` builds through the existing APE/GNU Make
  lane and contains every private primitive exactly once;
- the accepted raw object is present in every applicable bytecode runtime
  archive and linked where referenced;
- non-Plan-9 builds remain unchanged by source/build-rule review;
- `runtime/plan9_syscall_amd64.s` remains checked-in source;
- `plan9.cma` remains ML-only.

Before installation, obtain explicit user approval for an isolated test
prefix and for whether that prefix is retained or removed after testing. The
prefix must not exist before installation unless the user explicitly
authorizes replacement. Never silently delete or reuse a prefix, and never
alter the known-working compiler prefix
`/usr/glenda/lib/unix/ocaml-4.14.3`.

When approved, install into that prefix and run a private pipe smoke test that:

- uses the manifest-verified expanded
  `otherlibs/plan9/tests/syscall_capability_test.ml` from the exact reviewed
  authoritative worktree, copied into the fresh smoke-test directory rather
  than replaced by a guest-authored test, and verifies before compilation that
  the copied file's content hash matches its native source-manifest entry;
- is compiled and linked by the exact installed `ocamlc` using the ordinary
  consumer command shape
  `<installed ocamlc> -I +plan9 -linkall plan9.cma <copied test>.ml -o <smoke>`;
- is run by the exact installed `ocamlrun`;
- exercises private primitive pipe creation, write, read, EOF, and close;
- uses no `-custom`, `-use-runtime`, C compiler, linker, wrapper compiler, or
  additional archive;
- runs from a fresh native directory outside source and build trees;
- has `OCAMLPARAM`, `OCAMLLIB`, legacy `CAMLLIB`, and
  `CAML_LD_LIBRARY_PATH` unset;
- uses no source- or build-tree `-I` path, uses exactly `-I +plan9` as its only
  explicit include path, and has no competing `plan9.cma` in the smoke-test
  directory; and
- records the exact installed `ocamlc -where` result, proves it lies within
  the approved prefix, verifies that `+plan9` resolves to its `plan9`
  subdirectory, and verifies and records the existence and content hash of the
  derived absolute `<installed ocamlc -where>/plan9/plan9.cma`.

Record exact compiler, runtime, library, environment, command, and working
directory evidence. Before and after the isolated installation and smoke test,
record a byte-for-byte manifest of the protected known-working prefix using
the available narrow native equivalent: sorted relative paths, file lengths,
and content hashes. The manifests must match exactly. Also report the approved
test prefix's final retained or removed state. Source-tree execution,
source-tree artifact resolution, or installed-file inventory alone does not
satisfy this gate.

After every artifact-dependent audit and any installed smoke test, use a
disposable configured native tree for these cleanup proofs in this exact
order. Resolve `<GNU Make>` to the previously recorded exact GNU Make
executable and run every command from the disposable tree root:

1. verify that checked-in `runtime/plan9_syscall_amd64.s` and derived
   `runtime/plan9_syscall_amd64.o` both exist and record the source digest;
2. run `<GNU Make> clean`, verify the source digest is unchanged, and verify
   the derived object is absent;
3. run `<GNU Make> -C runtime plan9_syscall_amd64.o` and verify that only the
   required object rebuild occurred and that the object exists; and
4. run `<GNU Make> distclean`, verify the source digest is unchanged, verify
   the derived object is absent, and verify at minimum that root
   `Makefile.config`, `Makefile.build_config`, and `config.status`, plus
   `runtime/caml/m.h`, `runtime/caml/s.h`, and `runtime/caml/version.h`, are
   absent.

These are independent `clean` and `distclean` proofs; do not infer one from
the other.

If installation is not authorized, report the installed-prefix criterion as
open and do not claim full Phase 0 acceptance.

## Execution sequence and mandatory pauses

### 1. Preflight and implementation

Record Git state, complete untracked and ignored path inventories, the
accepted predecessor facts in this handoff, accepted raw and capability
shapes, runtime pending-action hooks, allocation/rooting conventions, build
rules, and primitive-generation inputs. Do not delete or absorb paths outside
the approved work. Implement only the byte I/O completion described here.

### 2. Source review before VM work

Run all safe host-side checks, inspect the complete diff from accepted Phase
0.2 checkpoint `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`, and perform a fresh
correctness review. Report validation order, rooting, staging, pending-action,
count-check, allocation, and error behavior to the user. Stop before VM
access.

### 3. Explicit VM and prefix confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, and acceleration profile. Ask separately for the
isolated install prefix, its create/replace action, and its retain/remove
postcondition if installation will be tested. Never boot a protected
checkpoint, guess an endpoint, share a writable disk, take an unauthorized
snapshot, or overwrite the known-working prefix.

Use the repository VM and native-build skills. Transfer without `.git` through
`/mnt/term`, copy onto native storage, and never build on `/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record release, `cputype`, `objtype`, configured host identity, exact
   compiler/assembler/archive tools, and GNU Make path.
2. Verify the accepted amd64 release assumptions or stop.
3. Copy only the approved source set into the required fresh artifact-free
   native destination, prove the pre-transfer host and pre-configure native
   manifests match exactly with no extra native file, and then configure and
   build it.
4. Run the complete Phase 0.1, 0.2, and 0.3 focused tests and existing Plan 9
   regression suites.
5. Perform the complete object/source, primitive, linked-definition, and
   packaging audits.
6. If approved, install into the isolated prefix and run the installed smoke
   test with the required environment isolation.
7. Execute the exact independent `clean`, object-only rebuild, and `distclean`
   sequence on a disposable native tree after other artifact-dependent checks
   finish.
8. Record descriptor, process, temporary-file, source-tree, prefix, VM,
   listener, and writable-disk postconditions.

### 5. Report and stop

Do not begin `Plan9.Fd`, migrate process code, implement capture, merge, tag,
publish a release, or modify Caml9. Commit and push only if the user explicitly
asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact read/write primitive and private result shapes;
- staging capacity and its justification;
- argument, range, count, capability, pending-action, allocation, rooting, and
  publication evidence;
- every focused and regression test command and result;
- complete raw/integration symbol audit and APE-independence conclusion;
- primitive uniqueness and `plan9.cma` ML-only evidence;
- the approved transfer-set basis, reviewed additions or deletions, complete
  untracked and ignored inventories, exclusions, matching authoritative-host
  and pre-configure native source manifests, hash algorithm, and artifact-free
  destination evidence;
- approved install prefix, isolated smoke-test evidence, and proof that the
  known-working prefix was unchanged, or an explicit open criterion;
- cleanup results after `clean`, `distclean`, and VM use; and
- exactly one final recommendation:
  - **Phase 0 accepted; ready for architectural regroup before `Plan9.Fd`**;
  - **implementation ready but native qualification still required**; or
  - **Phase 0 blocked or rejected**, with the exact reason.

Do not claim that the entire runtime is APE-free. The accepted claim is limited
to the reviewed five-operation path inside the existing APE-linked runtime.
