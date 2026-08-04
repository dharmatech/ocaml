# Phase 0.3 byte I/O and final acceptance handoff

Status: execute only after an accepted Phase 0.2 checkpoint

## Authority and required reading

This handoff delegates only Phase 0.3 and final Phase 0 qualification. Before
editing, read:

- `docs/design/handoffs/plan9-native-syscall-veneer-phase0.md` completely;
- the accepted Phase 0.1 and 0.2 completion reports and implementation diffs;
- the foundation's APE-independence boundary, qualified source facts, private
  syscall veneer sections on capability defense, error handling, OCaml
  heap/blocking sections and staging, proposed source boundary, complete Phase
  0 acceptance criteria, explicit non-goals, and required reports;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before their actions occur.

If either predecessor differs from its accepted report, or this handoff
conflicts with the roadmap or foundation, stop and return the evidence.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. Record the exact starting `HEAD` and verify
that it is the user-approved Phase 0.2 checkpoint, with a clean index and
worktree and no unexpected history.

Do not begin from an uncommitted, dirty, unqualified, or rejected predecessor.
Do not stash, reset, clean, or absorb unrelated work.

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

No read or write primitive accepts or returns a raw descriptor integer. A
forged, closed, or wrong-state capability fails before native work, including
when the requested length is zero.

Neither primitive may allocate or construct an OCaml value while inside a
blocking section.

## Read primitive

The private read primitive must not mutate a caller-supplied OCaml byte block.
OCaml `string` and `bytes` share a runtime tag and cannot be distinguished
defensively at this boundary.

Before native work, allocate, fully zero-initialize, and root a fresh
primitive-owned byte result. Also allocate, initialize to GC-safe placeholders,
and root every structural success block required to return that value and the
successful count. No scanned block may contain uninitialized OCaml fields when
a later allocation can occur.

Before proceeding to native work, check for and process pending OCaml actions
with every live argument and preallocated result rooted. Pending processing may
allocate, invoke a callback, close the capability, or raise. Revalidate the
capability afterward.

After successful final validation, permit no allocation, safe point, callback,
or pending-action processing before
`caml_enter_blocking_section_no_pending`. The raw read receives only a bounded
native staging buffer, never a pointer into the movable OCaml heap.

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

Allocate and root any structural success result before the post-callback
sequence. Check and process pending actions while all live values are rooted.
Because a callback may mutate the caller-owned source or close the capability,
then:

1. revalidate the source shape and range;
2. copy the current requested slice into bounded native staging; and
3. perform final capability-state validation immediately before the
   non-pending blocking entry.

Permit no allocation, safe point, callback, or pending-action processing in
that sequence or between final capability validation and
`caml_enter_blocking_section_no_pending`. The raw write receives only the
staging buffer.

After leaving the blocking section, verify every nonnegative result is no
greater than the exact count requested in that raw call. Preserve every valid
positive count. Publish success without a fallible allocation after the count
passes validation.

Native `read(2)` permits positive short reads. Native `write(2)` says a short
write should be treated as an error. The primitive still preserves the actual
positive count so a higher layer can apply policy; it must not silently issue
the remainder. Wrapper-imposed staging chunks are distinct from a native
result smaller than the count passed to that individual raw call.

## Zero-length and error behavior

After full argument, range, capability-identity, and open-state validation, a
zero-length read or write returns a successful count of zero without a native
syscall. A zero-length read consumes no queued byte. A zero-length write emits
no Plan 9 pipe message, avoiding the native ambiguity between such a message
and EOF.

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

Choose and report one bounded per-call native staging capacity. It must be:

- independent of total stream size;
- no larger than the native signed `long` count range;
- within a reviewed safe automatic-storage bound for the Plan 9 runtime stack;
  and
- treated as a private implementation choice, never a public constant.

The implementation and tests must distinguish staging-imposed chunks from the
count requested in each native call.

## Required focused tests

The Phase 0 ML test remains private and uninstalled. It may declare the private
external bindings and native-failure shape directly. No new name appears in
`plan9.mli` or installed reference documentation.

The pure-ML exact-write helper below is local to the private test suite. Give it
a fake low-level writer that returns a synthesized positive count smaller than
the count requested for that call. Verify that it reports failure after that
single invocation and never issues the remainder. Do not add, install, or
expose it as production code; production exact-write behavior belongs to a
later owning layer.

At minimum, test and review:

- raw integers, malformed values, forged look-alikes, and wrong-state
  capabilities fail before native work;
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
- a small completed native write followed by a larger read request produces a
  deterministic positive short read at the preserved write boundary;
- the short-read result exposes only its returned-count prefix and retains a
  fully initialized, deterministically zeroed tail;
- every preallocated scanned success block has GC-safe contents before later
  allocation;
- every nonnegative native result is checked against the exact raw request
  before indexing, copying, or publication, with oversized results classified
  without an out-of-bounds access;
- source review proves that a positive native short-write count is preserved;
- the test-local exact-write helper reports failure after one synthesized
  positive short count and makes no second call;
- source review distinguishes wrapper staging chunks from actual native short
  writes;
- pending actions run before native work and every callback-mutable state or
  write-source range is revalidated afterward;
- write staging captures the current post-callback source slice before final
  capability validation;
- final capability validation is followed immediately by the non-pending
  entry, with no intervening allocation or safe point;
- no fallible allocation follows a validated successful count before its
  publication;
- closing the designated writer yields EOF only after buffered data is read;
- both endpoints close and repeated round trips leave no descriptor behind;
- all Phase 0.1 raw-harness and Phase 0.2 capability/error tests retain their
  accepted behavior; and
- all existing `otherlibs/plan9` regression tests pass.

The focused test must not use an ordinary OCaml channel, `Unix`, `Sys.command`,
a temporary file, shell execution, APE descriptor registration, or another
process for the pipe path.

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
- unrelated whole-runtime APE symbols are not misreported as dependencies of
  the isolated five-operation path.

If the expected symbol utility is unavailable, determine and document the
narrow native equivalent rather than weakening the criterion.

## Build and installed-prefix acceptance

Final qualification must start from a fresh, artifact-free source copy of the
exact reviewed Windows tree, transferred without `.git` and placed on native
Plan 9 storage. Configure and build without reusing objects, archives,
generated primitive tables, or binaries.

Verify that:

- the standard amd64 Plan 9 `ocamlrun` builds through the existing APE/GNU Make
  lane and contains every private primitive exactly once;
- the accepted raw object is present in every applicable bytecode runtime
  archive and linked where referenced;
- non-Plan-9 builds remain unchanged by source/build-rule review;
- `runtime/plan9_syscall_amd64.s` remains checked-in source;
- executed `clean` and `distclean` targets preserve that assembly and remove
  its derived object; and
- `plan9.cma` remains ML-only.

Before installation, obtain explicit user approval for an isolated test
prefix. Never alter the known-working compiler prefix.

When approved, install into that prefix and run a private pipe smoke test that:

- is compiled by the exact installed `ocamlc`;
- uses an ordinary bytecode link with the exact installed `plan9.cma`;
- is run by the exact installed `ocamlrun`;
- exercises private primitive pipe creation, write, read, EOF, and close;
- uses no `-custom`, `-use-runtime`, C compiler, linker, wrapper compiler, or
  additional archive;
- runs from a fresh native directory outside source and build trees;
- has `OCAMLLIB`, legacy `CAMLLIB`, and `CAML_LD_LIBRARY_PATH` unset;
- uses no source- or build-tree `-I` path; and
- records `ocamlc -where` and proves it lies within the approved prefix.

Record exact compiler, runtime, library, environment, command, and working
directory evidence. Source-tree execution, source-tree artifact resolution, or
installed-file inventory alone does not satisfy this gate.

If installation is not authorized, report the installed-prefix criterion as
open and do not claim full Phase 0 acceptance.

## Execution sequence and mandatory pauses

### 1. Preflight and implementation

Record Git state, predecessor identities/reports, accepted raw and capability
shapes, runtime pending-action hooks, allocation/rooting conventions, build
rules, and primitive-generation inputs. Implement only the byte I/O completion
described here.

### 2. Source review before VM work

Run all safe host-side checks, inspect the complete diff from the Phase 0.2
checkpoint, and perform a fresh correctness review. Report validation order,
rooting, staging, pending-action, count-check, allocation, and error behavior to
the user. Stop before VM access.

### 3. Explicit VM and prefix confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, and acceleration profile. Ask separately for the
isolated install prefix if installation will be tested. Never boot a protected
checkpoint, guess an endpoint, share a writable disk, take an unauthorized
snapshot, or overwrite the known-working prefix.

Use the repository VM and native-build skills. Transfer without `.git` through
`/mnt/term`, copy onto native storage, and never build on `/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record release, `cputype`, `objtype`, configured host identity, exact
   compiler/assembler/archive tools, and GNU Make path.
2. Verify the accepted amd64 release assumptions or stop.
3. Create and build the required fresh artifact-free native source copy.
4. Run the complete Phase 0.1, 0.2, and 0.3 focused tests and existing Plan 9
   regression suites.
5. Perform the complete object/source, primitive, linked-definition, and
   packaging audits.
6. If approved, install into the isolated prefix and run the installed smoke
   test with the required environment isolation.
7. Execute `clean` and `distclean` preservation checks on a disposable native
   tree after other artifact-dependent checks finish.
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
- approved install prefix, isolated smoke-test evidence, and proof that the
  known-working prefix was unchanged, or an explicit open criterion;
- cleanup results after `clean`, `distclean`, and VM use; and
- exactly one final recommendation:
  - **Phase 0 accepted; ready for architectural regroup before `Plan9.Fd`**;
  - **implementation ready but native qualification still required**; or
  - **Phase 0 blocked or rejected**, with the exact reason.

Do not claim that the entire runtime is APE-free. The accepted claim is limited
to the reviewed five-operation path inside the existing APE-linked runtime.
