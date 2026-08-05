# Phase 0.2 capability lifecycle handoff

Status: reviewed execution handoff; Phase 0.1 accepted at
`0d3ac056a37e597e9673607de591cb8a0b5247bb`

## Authority and required reading

This handoff delegates only Phase 0.2. Before editing, read:

- `docs/design/handoffs/plan9-native-syscall-veneer-phase0.md` completely;
- the accepted Phase 0.1 facts below and the implementation diff from
  `4209e21088f8ba0f5c5985fcec79e41d4cffcb77` through
  `0d3ac056a37e597e9673607de591cb8a0b5247bb`;
- the foundation's repository identities, APE-independence boundary, qualified
  source facts, private syscall veneer sections on internal tiers, capability
  defense, error handling, OCaml heap/blocking sections, proposed source
  boundary, and Phase 0 acceptance criteria;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before their actions occur.

Do not implement Phase 0.3 or `Plan9.Fd`. If the accepted Phase 0.1 result does
not match the assumptions below, stop and return the mismatch for design
review.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. The accepted Phase 0.1 code predecessor is
exactly `0d3ac056a37e597e9673607de591cb8a0b5247bb`. The executing request must
name the exact user-approved documentation-checkpoint `HEAD` created after
this review. Verify that the starting `HEAD` descends directly from the
accepted predecessor with only reviewed documentation changes after it, and
that the index and worktree are clean with no unexpected history.

Do not begin from an uncommitted, dirty, unqualified, or rejected Phase 0.1
tree. Do not stash, reset, clean, or absorb unrelated work.

## Accepted Phase 0.1 facts

Phase 0.1 was implemented, reviewed, natively qualified, committed, and pushed
as `0d3ac056a37e597e9673607de591cb8a0b5247bb` (`plan9: add raw amd64 syscall
veneer`). Its code predecessor is the documentation checkpoint
`4209e21088f8ba0f5c5985fcec79e41d4cffcb77`.

The accepted private boundary contains exactly the checked-in raw
`ERRSTR`, `CLOSE`, `PIPE`, `PREAD`, and `PWRITE` entries, their private native
declarations and bytecode-runtime archive integration, and the private native
raw harness. It contains no `CAMLprim`, ML capability, public interface,
installed API, or `plan9.cma` C payload.

Native qualification established these configured build facts:

- `HOST=x86_64-unknown-plan9`;
- `ARCH=none` for the bytecode-only Plan 9 configuration;
- `O=o`; and
- the exact assembly rule produces `plan9_syscall_amd64.o` with `6a`.

The source and object audits established that the raw object has no undefined
library calls or forbidden APE references, and the repeated raw harness has
clean descriptor postconditions. The matching qualified 9front release source
is the clean release-11554 checkout at
`2191d72205863d2c53ea6ac36991cb4c13204c7c`.

For Phase 0.2 lifecycle and error claims, the matching authoritative sources
are `sys/src/9/port/sysfile.c` (`newfd2` and `syspipe`),
`sys/src/9/port/sysproc.c` (`generrstr` and `syserrstr`), and
`sys/man/2/errstr` in that checkout. They establish atomic pair publication
and cleanup on pipe failure, plus zero return and bounded NUL-terminated text
for a positive-sized `ERRSTR` buffer.

Two Phase 0.1 build findings are requirements for this subphase: use the
canonical configured `HOST` CPU name rather than `ARCH` or the spelling
`amd64`, and place shared other-library Makefile inclusion before any
`HOST`-dependent conditional.

## Delegated outcome

Add the minimum OCaml runtime integration needed to prove:

- opaque runtime-owned descriptor capabilities;
- preallocated, all-or-nothing pipe ownership publication;
- deterministic terminal close with idempotent repetition;
- immediate native error capture and private native-failure construction; and
- a dedicated negative-path probe that exercises raw error capture without
  exposing an integer descriptor to ML.

This subphase uses the accepted raw `ERRSTR`, `PIPE`, `PREAD`, and `CLOSE`
entries. The raw `PWRITE` entry remains present but is not exposed through an
ML primitive yet.

Phase 0.2 adds no general ML-facing read or write primitive, byte staging,
public API, installed interface, or `plan9.cma` C payload.

## Threat model and capability boundary

A built-in primitive remains callable through a user-declared `external` even
when no interface installs it. Treat every correct-arity primitive call as
receiving arbitrary well-formed OCaml values, including false types introduced
through `Obj.magic`.

Deliberately wrong `external` arities and mutation, truncation, retagging, or
duplication of a valid capability through unsafe `Obj` representation
operations remain outside the supported contract. Do not add a global
ownership registry merely to defend against those operations. The capability
must have no descriptor-closing GC finalizer; release remains explicit.

No primitive may accept or return a raw descriptor integer. A capability must
be accepted only when it was created by this runtime path and is in the state
required by the operation.

Before reading representation-specific payload, validate in this order:

1. immediate versus block;
2. expected tag;
3. sufficient or exact block size, as appropriate; and
4. runtime-owned capability identity.

Only then may code inspect capability state or its native descriptor. A forged
look-alike must never trigger an out-of-bounds access or dereference
attacker-controlled metadata.

The Phase 0.2 capability is guarded private runtime state, not the future
public `Plan9.Fd` shared ownership cell or attachment protocol.

### Required capability representation

Represent the capability as an exact-size private `Custom_tag` block allocated
with `caml_alloc_custom`, passing external-memory accounting arguments `mem=0`
and `max=1`. Its private payload contains only:

- one native descriptor stored as a C `int`; and
- one lifecycle state stored as a C `int`, with distinct `unpublished`, `open`,
  and `closed` values.

The qualified amd64 payload is therefore exactly eight bytes. The only
consistent state/descriptor combinations are `unpublished` with `-1`, `open`
with a nonnegative descriptor, and `closed` with `-1`.

Use a private static `struct custom_operations` as the runtime identity. Give
it the exact stable, repository-unique private identifier
`_ocaml_plan9_syscall_capability_v1`. Set finalize, compare, hash, serialize,
deserialize, extended compare, and fixed-length hooks to their corresponding
default null values. Do not register it for unmarshalling. In particular, it
has no descriptor-closing finalizer.

Initialize a new capability with descriptor `-1` and state `unpublished`.
Publication changes it to a nonnegative descriptor and state `open`.
Terminalization changes it to descriptor `-1` and state `closed`. An
unpublished state, unknown state, or state/descriptor combination outside the
three exact pairs above is invalid. A closed capability is accepted only by
close, where it produces the idempotent success without a syscall; operations
requiring an open descriptor reject it before native work.

Validation is exactly:

1. `Is_block`;
2. `Tag_val(value) == Custom_tag`;
3. `Wosize_val(value)` equals the size produced for the private payload,
   including the custom-operations word;
4. `Custom_ops_val(value)` equals the address of the private static operations
   structure, compared without dereferencing attacker-controlled metadata;
5. the lifecycle state is one of the three known values;
6. the descriptor and state form one of the three exact consistent pairs; and
7. the lifecycle state is accepted by the requested operation.

Do not call `Data_custom_val`, inspect state, or inspect the descriptor before
the first four checks succeed. This is an API and memory-safety boundary, not
confidentiality against unsupported `Obj` representation mutation or copying.

### Root and payload-pointer lifetime

Every incoming or allocated OCaml `value` that remains live across an
allocation, pending-action check, callback-capable operation, safe point, or
blocking-section entry must be registered with the appropriate `CAMLparam` or
`CAMLlocal` root. A root keeps the `value` current when the garbage collector
moves a block; it does not update a C pointer previously derived from that
value.

Never retain the result of `Data_custom_val`, or any other pointer into the
OCaml heap, across an allocation, pending-action processing, callback-capable
call, safe point, or ordinary `caml_enter_blocking_section`. Reacquire such a
pointer from the current rooted `value` only after the last intervening
GC-capable operation and use it only while no further such operation can
occur.

For pipe, initialize each new capability payload immediately after that
capability's allocation, then discard the derived pointer before making the
next allocation. After all preallocation, ordinary blocking entry, raw native
work, and blocking-section exit, reacquire both payload addresses from the
rooted capability values immediately before back-to-back publication. For
close, discard any payload pointer obtained during initial validation before
success allocation or pending processing. The complete post-pending
revalidation must reacquire the payload from the current rooted argument and
lead directly to descriptor save, terminalization, non-pending entry, and raw
close with no intervening GC-capable operation.

## Required runtime integration

### Source boundary

Add `runtime/plan9_syscall.c` for validated OCaml runtime integration. Extend
`runtime/plan9_syscall.h` only with private native declarations genuinely
shared with it. Make the minimum Plan 9-only runtime build and primitive-table
changes.

Keep capability validation, native-failure allocation, and all Phase 0.2
helpers local to `runtime/plan9_syscall.c`. The existing helpers in
`runtime/plan9_process.c` are static and use the older APE-backed path; do not
refactor, migrate, or expose them merely to share construction code. Reproduce
only the established private record representation and numeric kind meanings
locally, without creating a second public error hierarchy.

Gate `runtime/plan9_syscall.c` with the configured-host predicate
`x86_64-%-plan9`, the same predicate as the accepted raw object. Append it only
to `BYTECODE_C_SOURCES`; do not add it to `NATIVE_C_SOURCES`, because the raw
object is intentionally wired only into bytecode runtime archives and a native
compiler is outside Phase 0. In `runtime/gen_primitives.sh`, retain
`plan9_process` discovery for every `*-plan9` host but add `plan9_syscall`
discovery only for `x86_64-*-plan9`. Do not select the source with `ARCH`, the
unconfigured spelling `amd64`, or a generic Plan 9 condition.

Every enabled bytecode runtime variant must contain its integration object and
the accepted `plan9_syscall_amd64.o`. Unsupported Plan 9 CPU configurations
must receive neither the integration source nor its built-in primitives; they
must never acquire references to missing amd64 raw symbols.

Keep the repository's `runtime/dune` dependency mirrors synchronized with
these source and generator changes. Add `plan9_syscall.c` to the dependency
list for the primitive-generation fallback rule. Add `plan9_syscall.c`,
`plan9_syscall.h`, and the accepted checked-in `plan9_syscall_amd64.s` to the
dependency list for the `libcamlrun.a` fallback rule. This keeps a
Dune-sandboxed fallback complete; it does not replace or broaden the native
APE/GNU Make build lane.

Keep each built-in definition discoverable by the existing anchored primitive
scanner: its definition line begins with `CAMLprim value` followed by the exact
name. Do not weaken the scanner or treat its final `sort | uniq` as proof that
a primitive was discovered only once.

Private ML tests belong under `otherlibs/plan9/tests`. They may declare exact
private `external` bindings and the existing private native-failure shape, but
no new name may appear in `plan9.mli`, installed documentation, or another
public interface.

Gate the focused ML test with `x86_64-%-plan9`, after
`Makefile.otherlibs.common` has supplied `HOST`, just like the accepted raw
harness. Add its program only to the supported host's `ML_TEST_PROGRAMS` and
`CLEANFILES`. Compile it as ordinary bytecode without `-custom`, a C payload,
or a wrapper runtime, and execute it through `$(NEW_OCAMLRUN)` so the tested
primitive table and definitions come from the newly built standard runtime.
Unsupported Plan 9 CPU configurations must neither build nor run this test.

No primitive may allocate or construct an OCaml value while inside a blocking
section.

### Exact private primitive ABI

Use these built-in names and logical ML shapes in the private test only:

```ocaml
type capability

type native_failure = {
  native_kind : int;
  native_message : string;
}

external private_pipe :
  unit -> ((capability * capability), native_failure) result
  = "caml_plan9_syscall_pipe"

external private_close :
  capability -> (unit, native_failure) result
  = "caml_plan9_syscall_close"

external private_negative_read_probe :
  unit -> native_failure
  = "caml_plan9_syscall_negative_read_probe"
```

Manual C construction must use these exact OCaml heap layouts:

- `native_failure` is a tag-`0`, two-word block whose field `0` is
  `Val_int(native_kind)` and whose field `1` is the rooted message string;
- the capability pair is a tag-`0`, two-word block containing the two rooted
  capabilities in tuple order;
- both `Ok pair` and `Ok ()` are tag-`0`, one-word blocks containing the rooted
  pair and `Val_unit`, respectively;
- `Error native_failure` is a tag-`1`, one-word block containing the rooted
  failure record; and
- the negative probe returns the `native_failure` record itself, without a
  result or other structural wrapper.

These tags, sizes, and field orders are part of the private C/ML ABI. Every
scanned field must contain a GC-safe value before a later allocation,
pending-action operation, callback-capable operation, safe point, or blocking
entry can occur.

Do not mark any of these externals `[@@noalloc]`. Each primitive has at least
one allocating path, even though allocation is forbidden while it is inside a
blocking section.

Keep the established private numeric failure meanings: invalid input `0`,
other native error `1`, interrupted `2`, no children `3`, and protocol failure
`4`. This subphase normally uses invalid, other, interrupted, and protocol.
Malformed arguments return a structured invalid failure rather than invoking
undefined behavior or native work. The probe always returns the structured
failure for the operation that prevented or completed its deliberate negative
path; it has no success result.

The unit-taking primitives accept exactly `Val_unit`. They cannot and need not
distinguish a false-typed value with the identical immediate representation.
Requirements to reject raw integers and other immediate values apply to the
capability-taking close primitive, not to a valid unit argument.

### Pipe publication

Validate the exact `Val_unit` argument before any success allocation. Before
calling raw `PIPE`, allocate, initialize to the safe unpublished state, and
root:

- both opaque capabilities;
- their pair container; and
- every structural success block needed to return the owning result.

Every scanned block must contain GC-safe values before any later allocation.
Use an initially `{-1, -1}` native stack descriptor array for raw `PIPE`; raw
code must not write directly into OCaml heap storage. After successful native
acquisition, leave the blocking section before touching either capability.
Under the accepted no-systhreads configuration, source review must account for
the complete `caml_leave_blocking_section` path: the default leave hook is
empty; the function scans the pending-signal array, may set the deferred-action
flag, and restores `errno`; it does not process a callback, allocate, raise, or
take an OCaml safe point. Then publish both descriptors and `open` states
back-to-back into the rooted capabilities and return without another fallible
allocation, callback, pending-action check, or safe point. A pending flag set
by the exit remains deferred until after return. The brief first-to-second
publication interval is unobservable because nothing may re-enter OCaml there.

After all allocations, initialization, and rooting are complete, pipe uses the
ordinary `caml_enter_blocking_section`. Any pending signal callback therefore
occurs before native acquisition, while all live values are rooted and both
capabilities remain unpublished. If entry raises, no native descriptor has
been acquired. Once entry succeeds, call raw `PIPE` directly.

If an allocation could still fail after acquisition, the implementation is
incorrect; do not retain such a path. Source review must account for the exact
blocking-section exit and prove that the post-acquisition path cannot raise
before both capabilities become open and the preallocated success is returned.

The qualified kernel `syspipe`/`newfd2` implementation publishes its pair
atomically and cleans both channels on native failure. Capture `ERRSTR`
immediately after a negative raw result, before leaving the blocking section
or performing cleanup. Only after the native text is safe may ML failure
allocation occur.

Treat raw pipe success as exactly zero together with two nonnegative, distinct
outputs. A negative result takes the immediate `ERRSTR` path; the qualified
kernel has reset the output slots and owns no published endpoint on that path.

For every nonnegative raw result, establish native local ownership before any
heap publication: each nonnegative output is independently owned, but equal
output integers name one descriptor and receive only one ownership mark. If
any of these holds--the result is positive, either output is negative, or the
outputs are equal--classify a fixed protocol failure, publish nothing, and
make one raw close attempt for every distinct locally owned output before
leaving the blocking section. Attempt all independently owned cleanups even if
an earlier cleanup fails, never retry an uncertain close, and preserve the
protocol failure. Only exact zero with two nonnegative, distinct outputs may
take the nonraising-exit and heap-publication path above; that path transfers
both native ownership marks exactly once into the two open capabilities.

These structurally abnormal branches are source-review obligations; no
fault-injection primitive is authorized for them. This ownership bookkeeping
matches the accepted Phase 0.1 raw harness and prevents a partially returned
descriptor from being abandoned merely because the pair as a whole is
invalid.

### Deterministic close

Before native close, check for and process pending OCaml actions while every
live value and preallocated success result is rooted. Pending processing may
allocate, invoke a callback, close the same capability, or raise. Revalidate
the capability afterward.

On the successful native-work path, perform no allocation, safe point, or
pending-action processing after that revalidation. Save the descriptor and
terminalize the capability at a nonraising commit point immediately before
`caml_enter_blocking_section_no_pending`, which must lead directly to raw
close.

Repeated close is idempotent and performs no second syscall. If raw close or
later failure-result construction fails, the capability remains terminal so an
uncertain descriptor cannot be reused. Preallocate a success container unless
the chosen successful representation is immediate and allocation-free. After
a successful raw close, publish that preallocated or immediate success without
a fallible allocation.

For the required `(unit, native_failure) result` shape, `Ok ()` is a unary
allocated block, not an immediate value. Perform the complete initial
capability validation first. Reject an invalid or unpublished state; if the
capability is already closed, allocate and return idempotent success without
pending processing or a syscall. Only for an initially open capability,
initialize the native error buffer and all native status and ownership
bookkeeping, then preallocate and root success before pending-action
processing. After pending processing, repeat the complete identity, state, and
descriptor validation, reacquiring the payload from the current rooted
argument. If it is now closed, return the rooted idempotent success without a
syscall. If it is open, use that freshly acquired payload immediately to save
the descriptor locally and terminalize both state and descriptor before
`caml_enter_blocking_section_no_pending`. Do not place `memset`, a helper call,
or any other preparatory operation between final revalidation and this commit
sequence.

Raw close succeeds only when it returns exactly zero. A negative result takes
the immediate `ERRSTR` path; an unexpected positive result becomes a protocol
failure without consulting `ERRSTR`. In every failure case the capability
remains closed and the saved integer is never retried or made usable again.

Source review must confirm that the selected standard runtime hooks are
nonraising under the Phase 0 no-systhreads configuration and that the ordering
matches the established check-pending, re-read-state, non-pending-entry pattern
in `runtime/io.c`.

### Native failure shape

Use the existing private shape containing `native_kind` and `native_message`.
The runtime integration returns that private value; later ML layers assign the
high-level operation and convert it into `Plan9.error`. Do not construct the
public error record in C or add a second public error hierarchy.

A negative raw result is followed immediately by raw `ERRSTR` into an initially
empty, bounded 128-byte buffer before leaving the blocking section or making a
cleanup syscall. Do not use native `rerrstr`, `errno`, or an APE-private error
helper.

This immediate-capture rule applies to the failing primary operation whose
native text will be returned. Once a native or fixed protocol failure is safe
in native storage, a later cleanup failure must not call `ERRSTR` merely for
diagnostics, replace the preserved failure, or trigger a retry. Cleanup still
receives its single required attempt.

Zero-initialize the whole buffer before native work and force its final byte to
NUL after `ERRSTR`. The qualified release manual and implementation establish
that `ERRSTR` returns zero and NUL-terminates a positive-sized buffer, but check
its return defensively. If it returns nonzero or leaves no usable message,
construct a fixed deterministic protocol failure after leaving the blocking
section. Do not call `ERRSTR` recursively to diagnose `ERRSTR`.

Classify the exact native text `interrupted` as private kind `2`; other
nonempty native text is kind `1`. Deterministic validation failures are kind
`0`, and impossible ABI results or unusable error capture are kind `4`.

### Dedicated negative-path probe

Add a private probe taking no ML descriptor. It must:

1. obtain a locally owned raw pipe pair;
2. close the selected target using the accepted raw close entry;
3. only if close succeeds, invoke raw read on the saved integer and capture
   `ERRSTR` immediately after its negative result;
4. close every other definitely owned local resource; and
5. return only the structured failure to ML.

Validate the exact unit argument before entering native work. Then use one
continuous `caml_enter_blocking_section_no_pending` region for raw pipe,
deliberate close, saved-integer read, immediate `ERRSTR`, and cleanup. Keep all
descriptor state and the 128-byte error buffer in native storage and perform no
OCaml heap access while inside that region.

Initialize the pipe outputs to `{-1, -1}`. Pipe and close succeed only on zero.
A negative pipe result takes the immediate `ERRSTR` path and owns no endpoint.
An unexpected positive pipe result or an exact-zero result without two
nonnegative distinct outputs is a fixed protocol failure. For any nonnegative
pipe result, independently own each nonnegative output, deduplicate equal
integers, and make one cleanup attempt for every distinct owned output before
leaving. Preserve the setup protocol failure if cleanup also fails, and do not
begin the deliberate close/read sequence.

If the deliberate close returns negative, capture its error immediately; if
it returns positive, record a fixed protocol failure without `ERRSTR`. In
either case never read, never retry the now-uncertain target, close only the
other definitely owned endpoint, and preserve the original close failure.

Only after exact close success, call raw `PREAD` on the saved closed integer
with an initialized one-byte native stack buffer, count `1`, and
`CAML_PLAN9_SYSCALL_STREAM_OFFSET` (`-1LL`). A negative result takes the
immediate `ERRSTR` path. Any nonnegative result, including zero, is a fixed
protocol failure and does not call `ERRSTR`. Cleanup of the other endpoint must
not replace the deliberate read failure or protocol failure. Leave the
blocking section only after every definitely owned resource has received its
single cleanup attempt, then allocate the returned private failure.

For the accepted release-11554 kernel path, that deliberate `PREAD` reaches
`fdtochan` with the now-closed integer and yields exact native text
`fd out of range or not open`. Classify it as private kind `1` and preserve
both that kind and exact text across cleanup. A different result fails the
focused qualification rather than being weakened to a merely nonempty error.

## Required tests and review evidence

### Executable private ML tests

At minimum, execute tests that establish:

- pipe and probe return private invalid kind `0`, do not crash, and preserve
  descriptor postconditions for representative non-unit immediates and block
  values passed through false types;
- close returns private invalid kind `0`, does not crash, and preserves
  descriptor postconditions for raw integers, immediate values, ordinary
  blocks, wrong-tag blocks, and well-formed foreign custom blocks;
- the foreign-custom cases use an `Int64` value as the custom block with an
  exact-eight-byte payload and another runtime-owned operations identity, and
  a `Bigarray.Array1` value as a valid wrong-size custom block; both cases use
  the standard runtime and require no test C payload;
- successful pipe returns two opaque capabilities and no integer descriptor;
- closing each endpoint succeeds and leaves no owned endpoint;
- closing through an ML alias terminalizes that same capability;
- both open capabilities and their aliases remain valid across an explicit
  minor collection followed by a full major collection and compaction, after
  which closing through the aliases succeeds and restores clean descriptor
  postconditions;
- repeated close succeeds idempotently without a second observable close;
- the negative probe returns private kind `1` with exact native message
  `fd out of range or not open` from its deliberate read path, preserves both
  fields unchanged across cleanup, and uses neither `errno` translation nor
  descriptor exposure; and
- repeated pipe/close/probe runs have clean descriptor postconditions.

For ML-side descriptor postconditions, use the established private integration
test method: capture and sort complete `Sys.readdir "/fd"` inventories before
and after the tested sequence, then compare those like-for-like snapshots.
This accounts consistently for the observer opened internally by
`Sys.readdir` without relying on unnormalized totals. Do not add a self-PID
primitive, a test C payload, or a Unix-stub linkage dependency solely for
observation. Retain the normalized `/proc/<pid>/fd` method in the Phase 0.1
native C harness, where `getpid()` and the observer's `fileno()` are available.

Use only well-formed OCaml values for hostile-input tests. In particular, do
not manufacture an invalid `Custom_tag` block with an attacker-chosen
operations word through `Obj.new_block`; the garbage collector may dereference
that invalid metadata independently of this primitive, and such a value lies
outside the stated threat model. Existing valid custom values such as boxed
integer or bigarray values provide safe size/identity counterexamples.

### Mandatory source and object review

Establish by source and object review, without adding raw-descriptor exposure
or general fault-injection primitives, that:

- each capability uses only the exact two-`int` payload, is allocated with
  `caml_alloc_custom` using `mem=0` and `max=1`, and is initialized to the safe
  `unpublished`/`-1` pair before any later allocation;
- its operations structure is private and static, has the exact unique
  identifier `_ocaml_plan9_syscall_capability_v1`, and does not collide with
  another custom-operations identifier in the runtime; every hook is set to
  the corresponding default null value, the structure is not registered for
  unmarshalling, and it has no descriptor-closing finalizer;
- every manually constructed failure record, capability pair, `Ok`, and
  `Error` block has the exact required tag, word size, field order, rooted
  child values, and GC-safe initialization, while the probe returns its failure
  record directly without a structural wrapper;
- validation checks block shape, `Custom_tag`, exact size, and private
  operations identity before payload, state, or descriptor;
- validation accepts only the exact three state/descriptor pairs and then only
  a lifecycle state permitted by the requested operation;
- every live OCaml value has the required `CAMLparam` or `CAMLlocal` root, and
  no `Data_custom_val` or other heap-interior pointer survives allocation,
  pending processing, a callback-capable call, a safe point, or ordinary
  blocking entry;
- pipe and probe reject every value other than exact `Val_unit` before success
  allocation, blocking entry, or a raw call, and close rejects malformed
  capability values before pending processing or a raw call;
- unpublished, inconsistent, and unknown states fail before native work,
  while closed is accepted only for idempotent close;
- successful pipe acquisition touches only native storage while blocked and
  publishes both capabilities after the nonraising exit without a
  post-acquisition fallible allocation or safe point;
- every nonnegative pipe result validates exact zero and two distinct
  nonnegative outputs before publication, while a protocol anomaly retires and
  closes each distinct locally owned output once;
- pending actions occur before final close validation, followed immediately by
  freshly reacquired payload use, terminalization, non-pending entry, and raw
  close, with native buffers and bookkeeping already initialized;
- successful raw close reaches the preallocated `Ok ()` without a fallible
  allocation;
- an initially closed capability returns idempotent success without entering a
  blocking section or issuing another raw close;
- negative and abnormal raw results follow their required immediate-`ERRSTR`
  or fixed-protocol paths;
- an unexpected close failure or positive result cannot make the capability
  usable again;
- the probe does not read after any nonzero close result, does not retry the
  uncertain close, performs its deliberate read with one native byte and the
  stream offset, cleans only definitely owned resources, and preserves the
  original error; its qualified read-failure path maps exact native text
  `fd out of range or not open` to private kind `1`;
- no path exposes a raw descriptor integer to ML; and
- none of the private ML externals is marked `[@@noalloc]`.

Exact pending-callback interleavings and impossible raw-result branches may be
tested only if they are deterministically reachable through existing safe
runtime facilities. Their source proof remains mandatory; do not broaden the
private ABI merely to inject them.

The Phase 0.1 native raw harness must retain its accepted behavior. Existing
`otherlibs/plan9` tests must also remain unchanged in behavior.

## Symbol, source, and packaging audit

Record evidence that:

- each new `CAMLprim` appears exactly once in the generated primitive table and
  has one linked definition in the standard Plan 9 `ocamlrun`;
- the runtime integration object references repository-prefixed raw entries,
  not `_PIPE`, `_PREAD`, `_READ`, `_CLOSE`, `_ERRSTR`, or ordinary OS I/O;
- source contains no `_fdinfo`, raw ML descriptor conversion, `errno`
  translation, APE registration, or private `sys9.h` inclusion in the new path;
- the accepted raw object remains free of undefined library calls and forbidden
  references;
- `runtime/dune` names the new primitive-generator input and all integration,
  header, and raw-assembly inputs required by its fallback runtime rule; and
- `plan9.cma` remains ML-only and no public interface or installed reference
  changes.

The primitive generator ends with `sort | uniq`; inventory membership alone
does not prove unique discovery. Inspect the generated table and linked
definitions separately.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state, the accepted Phase 0.1 facts in this handoff, the exact
user-approved starting documentation checkpoint, current runtime hooks,
allocation helpers, custom-block conventions, build rules, and
primitive-generation inputs. Implement only Phase 0.2.

### 2. Source review before VM work

Run safe host-side checks and inspect the complete proposed diff from the exact
starting documentation checkpoint. Also audit the cumulative Phase 0.2 source
boundary against accepted Phase 0.1 commit
`0d3ac056a37e597e9673607de591cb8a0b5247bb`. Review validation ordering,
allocation/rooting, pending actions, terminalization, error capture, and
cleanup. Report to the user and stop before VM access.

### 3. Explicit VM confirmation

Obtain user confirmation of the exact writable instance, loopback address,
action, and acceleration profile. Use the repository VM and native-build
skills. Transfer without `.git`, copy onto native storage, and never build on
`/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record guest and toolchain identity and verify the accepted amd64 release.
2. Create a fresh artifact-free native copy of the exact reviewed tree.
3. Configure and build through the existing APE/GNU Make lane.
4. Run the Phase 0.1 raw harness, the focused Phase 0.2 ML test, and existing
   Plan 9 regression suites.
5. Perform primitive uniqueness, linked-definition, raw-object, integration
   object, and public-interface audits.
6. Record descriptor, temporary-file, tree, VM, listener, and disk
   postconditions.

No installation or installed-prefix change is authorized in Phase 0.2.

### 5. Report and stop

Do not implement general byte reads or writes, begin Phase 0.3 or `Plan9.Fd`,
install, merge, tag, or publish. Commit and push only if the user explicitly
asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact capability representation and validation sequence;
- exact private primitive names and ML result shapes;
- allocation/rooting, payload-pointer lifetime, live-capability GC-survival,
  and pipe-publication proof;
- pending-action and close-commit proof;
- native-failure and negative-probe cleanup proof, including exact qualified
  probe kind `1` and message `fd out of range or not open`;
- exact handling of abnormal positive results and unusable `ERRSTR` capture;
- primitive uniqueness, linked raw symbol, APE-isolation, ML-only packaging,
  and public-interface evidence; and
- one recommendation:
  - **Phase 0.2 accepted; ready to checkpoint and regroup before Phase 0.3**;
  - **implementation ready but native qualification still required**; or
  - **Phase 0.2 blocked or rejected**, with the exact reason.
