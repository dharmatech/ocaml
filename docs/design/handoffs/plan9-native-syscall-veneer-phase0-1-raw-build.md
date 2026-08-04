# Phase 0.1 raw ABI and build proof handoff

Status: ready for execution after the documentation-only checkpoint

## Authority and required reading

This handoff delegates only Phase 0.1. Before editing, read:

- `docs/design/handoffs/plan9-native-syscall-veneer-phase0.md` completely;
- the foundation's repository identities, APE-independence boundary,
  qualified source facts, private syscall veneer through the proposed source
  boundary, Phase 0 acceptance criteria, explicit non-goals, and required
  reports;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before their actions occur.

Do not implement Phase 0.2 or 0.3. If this handoff conflicts with the roadmap
or foundation, stop and ask the user.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. Record the exact starting `HEAD` and verify
that it contains the reviewed documentation checkpoint, with a clean index and
worktree and no unexpected history. The source-code base remains
`835bc29b0c276a83211a517b950a55f0fb9c2bfe`.

If the state differs, report it and stop. Do not stash, reset, clean, or absorb
unrelated work.

## Delegated outcome

Implement and natively qualify the raw amd64 Plan 9 syscall tier and its build
integration for exactly five operations:

1. native error capture;
2. pipe creation;
3. logical read;
4. logical write; and
5. close.

This subphase proves the raw ABI and build facts only. It adds no `CAMLprim`,
OCaml value handling, opaque ML capability, ML test, installed library content,
or public `Plan9` API.

## Exact native boundary

Use this release-qualified mapping:

| Logical operation | Native syscall | Number | Required raw form |
| --- | --- | ---: | --- |
| capture error | `ERRSTR` | 41 | `int (char *, unsigned int)` |
| close | `CLOSE` | 4 | `int (int)` |
| pipe | `PIPE` | 21 | `int (int *)` |
| read | `PREAD` | 50 | `long (int, void *, long, long long)`, offset `-1` |
| write | `PWRITE` | 51 | `long (int, void *, long, long long)`, offset `-1` |

The qualified native `ERRMAX` is 128 bytes. Define it under a private,
repository-prefixed name. Do not include APE's private `sys9.h` or derive any
declaration, type, or constant from it. Do not use legacy `_READ` or `_WRITE`;
logical native I/O uses `PREAD` and `PWRITE` at offset `-1`.

The read-only ABI reference is:

- `/home/dharmatech/src/9front-11554` in WSL;
- commit `2191d72205863d2c53ea6ac36991cb4c13204c7c`; and
- architecture amd64.

Relevant reference locations are recorded in the foundation. Inspect that
checkout without fetching, pulling, switching, resetting, or modifying it. The
future guest must independently report a matching release and architecture.

## Required implementation

### Checked-in raw entries

Add `runtime/plan9_syscall_amd64.s` with repository-prefixed entries such as
`caml_plan9_sys_pipe` and `caml_plan9_sys_pread`. Each entry must:

- accept only native C values and caller-owned buffers;
- return the kernel value unchanged, without `errno` translation;
- allocate nothing and construct no OCaml value;
- call no C, OCaml runtime, native libc, or APE function;
- neither define nor reference native libc syscall names or APE's
  underscore-prefixed entries;
- be usable later by the constrained post-`rfork`, pre-`exec` child path; and
- record the source path, 9front commit, syscall name and number, and
  MIT-licensed provenance in comments.

Follow the qualified amd64 entry convention rather than copying unrelated
9front assembly. The assembly is reviewed source and must not be generated
from a guest `/sys/src` tree during an ordinary build.

### Private native header

Add `runtime/plan9_syscall.h` containing only the private native declarations,
qualified error bound, and raw child-safe contracts required by this tier.
Keep it outside `runtime/caml`; the wildcard install rule for that directory
must not publish the header.

### Build integration

Make the minimum Plan 9-only GNU Make changes needed to assemble the checked-in
source and place its object in every standard Plan 9 bytecode runtime archive
variant. Prove rather than assume:

- the exact `6a` invocation;
- the object suffix and explicit output name accepted by the native toolchain;
- archive membership for each applicable bytecode runtime variant;
- dependency and cleanup behavior; and
- the configured build fact that selects amd64 Plan 9.

The Plan 9 `c89` driver ignores `.s` input, and the bytecode-only configuration
may not expose amd64 through OCaml's native-code `ARCH` variable. Do not route
the assembly through `c89` or select it using an unverified variable.

Unsupported Plan 9 CPUs must omit the unavailable raw facility or fail clearly
according to the reviewed build result; they must never use APE as a silent
fallback. Non-Plan-9 builds remain unchanged.

The raw archive member may remain unextracted from the final `ocamlrun` in this
subphase because no runtime integration object references it yet. Do not force
linkage merely to make the symbols appear in the executable. Prove archive
membership now; final linked presence belongs to Phase 0.2 and 0.3.

Do not add or change primitive inventory entries. Verify that Phase 0.1 leaves
the generated built-in primitive set unchanged.

### Test-only native harness

Add the smallest private C harness under `otherlibs/plan9/tests` needed to call
the raw entries directly. It is test-only, uninstalled, and not linked into
`plan9.cma` or a standard runtime archive.

Link the harness directly with the exact freshly assembled raw object produced
by the reviewed production build rule in the same native build tree. Do not
obtain the repository-prefixed entries from `ocamlrun`, `libcamlrun`, an
installed runtime, or another archive. Record the exact harness compile and
link commands and the selected raw-object path. The object linked into the
harness must be the same artifact added to the runtime archives; if the build
necessarily materializes copies, prove that their object contents are
identical.

The harness may use the ordinary test program environment to report pass or
failure, but every operation on a descriptor created by the raw `PIPE` entry
must use only repository-prefixed raw entries. It must never pass such a
descriptor to APE I/O, an ordinary OCaml channel, or descriptor registration.
Keep harness dependencies separate from the raw-object audit.

At minimum, the harness must:

- create a native pipe;
- round-trip a binary payload containing an embedded NUL;
- complete a small write and request more bytes to observe a deterministic
  positive short read at the preserved write boundary;
- close the designated writer and observe EOF on a positive-length read after
  buffered bytes are consumed;
- close both endpoints on all ordinary paths;
- deliberately close a locally owned target, invoke raw read on its saved
  integer only if close succeeds, and call raw `ERRSTR` immediately after the
  negative read;
- if the deliberate close unexpectedly fails, follow the general close-failure
  rule below and return without reading;
- preserve the original failing-operation error across cleanup; and
- repeat the round trip for a fixed, recorded count using a recorded
  leak-detection method. After all loop resources are closed, compare the
  descriptor inventory or count with its pre-loop baseline using the same
  observer method. Exclude or otherwise account for descriptors temporarily
  opened by that observer; the normalized result must show zero net growth.

Apply one ownership rule to every raw close, including ordinary cleanup and the
deliberate negative-path probe. Immediately before the call, retire the target
from the harness's definitely-owned set. If close returns a negative result,
capture that error immediately, never retry or reuse the now-uncertain target,
and clean up only other definitely owned resources.

Use an initially empty 128-byte error buffer. To make the termination proof
independent of pre-existing zero fill, initialize bytes 1 through 127 with a
nonzero sentinel and then set byte 0 to NUL, preserving a valid empty input
string. After raw `ERRSTR`, require a nonempty result followed by a NUL within
the 128-byte bound. Do not use an all-zero initialization as evidence of
termination. Check the raw `ERRSTR` result before inspecting the buffer. If
`ERRSTR` itself returns a negative result, treat error capture as a terminal
harness failure: do not retry it, do not call it recursively, stop issuing raw
test syscalls, and report a fixed diagnostic identifying error capture itself
as the failure.

After any other unexpected negative raw result, call raw `ERRSTR` immediately
before another raw syscall, cleanup, or diagnostic output, and preserve that
original error across cleanup. Do not retry interrupted read or write
operations.

## Required audits

Inspect the raw assembly source and object separately from the C harness.
Record exact commands and relevant output proving that:

- the raw object has no undefined library calls;
- it neither defines nor references `_PIPE`, `_PREAD`, `_READ`, `_PWRITE`,
  `_WRITE`, `_CLOSE`, `_ERRSTR`, ordinary `pipe`, `read`, `write`, or `close`;
- only repository-prefixed entries issue the five selected syscalls;
- it contains no `_fdinfo`, `errno`, APE registration, or private `sys9.h` use;
- the harness reaches the raw entries directly and does not route its pipe
  descriptors through APE;
- link or symbol evidence shows that the harness resolves every
  repository-prefixed entry from the recorded raw object, not from `ocamlrun`,
  `libcamlrun`, an installed runtime, or another archive;
- the raw object used by the harness is the same artifact placed in every
  applicable runtime archive, or its object contents are proven identical; and
- unrelated APE symbols in the harness or whole runtime are not misreported as
  raw-tier dependencies.

If the native toolchain lacks the expected symbol utility, document the narrow
native equivalent rather than weakening the audit.

## Execution sequence and mandatory pause

### 1. Preflight and implementation

Record Git state, remotes, source references, relevant current runtime build
rules, and primitive-generation behavior. Implement only the raw entries,
private header, build wiring, and native harness.

### 2. Source review before VM work

Run safe host-side checks, inspect the complete diff, and perform a fresh
correctness review. Report the proposed code, precise harness boundary, and any
design deviation to the user. Stop before any VM access.

### 3. Explicit VM confirmation

Ask the user to confirm the exact writable VM instance, loopback address,
start/access action, and acceleration profile. Never boot a protected
checkpoint, guess an endpoint, share a writable disk, or take a snapshot.

Use the repository's VM and native-build skills exactly. Transfer without
`.git` through `/mnt/term`, then copy to native Plan 9 storage. Never build on
`/mnt/term`.

### 4. Native qualification

On the confirmed guest:

1. Record release, `cputype`, `objtype`, configured host identity, `6a`, archive
   tool, C compiler, and GNU Make paths and versions where available.
2. Verify the guest matches the amd64 release assumptions or stop.
3. Create a fresh artifact-free native source copy of the exact reviewed tree.
4. Configure and build it through the existing APE/GNU Make lane without
   reusing objects, archives, generated primitive tables, or binaries.
5. Build the private raw harness directly against the recorded production raw
   object, record the exact compile and link commands, and run it.
6. Perform the raw source/object and archive-membership audits.
7. Verify the primitive inventory is unchanged.
8. On a disposable native tree, execute `clean` and `distclean`; verify the
   checked-in assembly survives and its derived object is removed.
9. Record descriptor, temporary-file, tree, VM, listener, and disk
   postconditions.

No installation or installed-prefix change is authorized in Phase 0.1.

### 5. Report and stop

Report the complete result and stop. Do not begin capability representation,
add a `CAMLprim`, implement ML read/write, install, merge, tag, or publish.
Commit and push only if the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact raw signatures, symbol names, syscall literals, and provenance;
- exact assembler rule, selection fact, object name, archive variants, and
  cleanup behavior;
- harness boundary, compile and link commands, resolved raw-object path, object
  identity evidence, and results for round-trip, short read, EOF, native error,
  sentinel-based termination, nonrecursive error-capture failure handling,
  terminal close ownership, and cleanup;
- repetition count, leak-detection and observer method, observer normalization,
  and pre-loop and post-loop descriptor inventory or count;
- raw-object undefined-symbol and forbidden-symbol evidence;
- confirmation that primitive inventory and public APIs did not change; and
- one recommendation:
  - **Phase 0.1 accepted; ready to checkpoint and regroup before Phase 0.2**;
  - **implementation ready but native qualification still required**; or
  - **Phase 0.1 blocked or rejected**, with the exact reason.
