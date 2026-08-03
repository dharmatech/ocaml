# Phase 0 native syscall veneer implementation handoff

Status: ready for execution after a documentation-only checkpoint

## Authority and required reading

This handoff delegates only Phase 0 of the native I/O foundation described in:

`C:\Users\dharm\src\ocaml\docs\design\plan9-native-io-foundation.md`

Read that document completely before editing code. Its architectural decisions,
APE-independence definition, source provenance, and Phase 0 acceptance criteria
are authoritative. Also read the repository `AGENTS.md` and every applicable
local skill before acting.

If this handoff appears to conflict with the foundation document, stop and ask
the user. Do not resolve an architectural conflict by silently expanding the
implementation.

## Repository and branch identity

- Authoritative editing repository: `C:\Users\dharm\src\ocaml`.
- Published Plan 9 baseline branch: `plan9-4.14.3-000`.
- Published baseline commit:
  `a98e773a80311653d7a78763bd017328b5c26b52`.
- Local source-and-workflow base:
  `835bc29b0c276a83211a517b950a55f0fb9c2bfe`.
- Implementation branch: `codex/plan9-native-io-foundation`.
- Preserved rejected prototype:
  `codex/archive/plan9-process-capture-prototype` at
  `1eb780b1b8467d1b80b35102e40371b87dde5604`.

The implementation task should start after the foundation document and this
handoff have been committed together as a documentation-only checkpoint. That
checkpoint cannot record its own Git identity inside itself, so the executor
must record the exact starting `HEAD` before editing. Its source-code parent is
the local base identified above.

Before implementation, verify:

- the current branch is exactly `codex/plan9-native-io-foundation`;
- `HEAD` contains both design documents;
- the index and worktree are clean; and
- no unexpected commit, merge, rebase, or unrelated local change is present.

If any condition differs, report the exact state and stop rather than cleaning,
stashing, resetting, or absorbing someone else's work.

## Delegated outcome

Implement and qualify the smallest private, OCaml-owned Plan 9 syscall veneer
that proves these five logical operations:

1. native error capture;
2. pipe creation;
3. logical read;
4. logical write; and
5. close.

The proof must establish that a standard amd64 Plan 9 `ocamlrun`, although
still linked with APE for the portable runtime, can perform these operations
without using APE's I/O, descriptor, error, or private syscall-entry machinery.

Phase 0 changes no installed public `Plan9` API. Its result is private runtime
infrastructure, private tests, build integration, evidence, and documentation
needed to decide whether work may proceed to `Plan9.Fd`.

## Exact native boundary

Use the release-qualified mapping recorded in the foundation document:

| Logical operation | Native syscall | Number | Required raw form |
| --- | --- | ---: | --- |
| capture error | `ERRSTR` | 41 | `int (char *, unsigned int)` |
| close | `CLOSE` | 4 | `int (int)` |
| pipe | `PIPE` | 21 | `int (int *)` |
| read | `PREAD` | 50 | `long (int, void *, long, long long)`, offset `-1` |
| write | `PWRITE` | 51 | `long (int, void *, long, long long)`, offset `-1` |

The qualified native `ERRMAX` is 128 bytes. Define it under a
repository-prefixed private name. Do not include APE's private `sys9.h` or use
that header as the source of any veneer declaration, type, or constant.

Do not use legacy `_READ` or `_WRITE` syscall numbers merely because their
names resemble the logical operations. Native 9front libc implements logical
`read` and `write` using `pread` and `pwrite` with offset `-1`, and the veneer
must preserve that choice.

The initial ABI reference is the clean WSL checkout:

- `/home/dharmatech/src/9front-11554`;
- commit `2191d72205863d2c53ea6ac36991cb4c13204c7c`; and
- architecture amd64.

Inspect it read-only. Do not fetch, pull, switch, reset, or modify it. A future
guest must independently report a matching release and architecture before its
results count as Phase 0 acceptance.

## Required implementation properties

### Raw syscall tier

Provide checked-in, amd64 Plan 9 assembly entries under repository-prefixed
symbols such as `caml_plan9_sys_pipe` and `caml_plan9_sys_pread`.

The raw tier must:

- accept only native C values and caller-owned buffers;
- return the kernel value without `errno` translation;
- allocate nothing and construct no OCaml value;
- call no C, OCaml runtime, native libc, or APE function;
- neither define nor reference native libc syscall names or APE's
  underscore-prefixed direct entries;
- be suitable for a future constrained post-`rfork`, pre-`exec` child path;
  and
- record the source path, 9front commit, syscall name and number, and
  MIT-licensed provenance in its comments.

Do not generate the assembly from the guest's `/sys/src` during an ordinary
build. The checked-in file is the reviewed build input.

### Runtime integration tier

Add only the internal `CAMLprim` operations needed for the Phase 0 proof.
They must:

- validate OCaml shapes, descriptor values, byte ranges, lengths, and unit
  arguments before native work;
- reject forged or unrepresentable values deterministically;
- root every live OCaml value correctly;
- use bounded native staging storage around blocking sections instead of
  passing an OCaml heap pointer to a blocking syscall;
- copy write input before entering the blocking section;
- copy successful read bytes back only after leaving it;
- tolerate and report positive short reads and writes;
- avoid automatic retry after interruption;
- call raw `ERRSTR` immediately after a negative result, before leaving the
  blocking section or performing cleanup that could replace the error; and
- never allocate in a blocking section or leave a newly created native
  resource exposed to an allocating return path.

For `pipe`, preallocate and root the OCaml blocks needed to publish the owning
success value before entering the native call. After successful acquisition,
either publish both descriptors without another fallible allocation or close
both before such an allocation can occur. Error text may be converted to an
OCaml value after a failed `pipe`, because no pipe descriptor then exists.

Use the existing structured native failure conventions where they fit without
making a public API. Do not duplicate a second public error hierarchy merely
for the test.

The staging capacity is an implementation experiment, not a public constant.
Keep it bounded and document the reason for the chosen size.

### Build and primitive integration

The expected source boundary is:

- `runtime/plan9_syscall_amd64.s`;
- `runtime/plan9_syscall.h`;
- `runtime/plan9_syscall.c`;
- focused private tests under `otherlibs/plan9/tests`; and
- the minimum runtime and test Makefile/primitive-inventory changes.

Keep the private header outside `runtime/caml`, whose wildcard install rule
would otherwise publish it with OCaml's installed runtime headers.

These names may change only when the actual build requires it; report any
change and its reason.

Prove rather than assume:

- the exact `6a` invocation;
- the object suffix and requested output name accepted by the toolchain;
- archive membership for every standard Plan 9 bytecode runtime variant;
- dependencies and cleanup rules;
- the configured fact used to select amd64 Plan 9; and
- registration of each new primitive exactly once.

The Plan 9 `c89` driver ignores `.s` input, and the bytecode-focused OCaml
configuration may not expose amd64 through OCaml's native-code `ARCH` setting.
Do not route the assembly through `c89` or key the rule to an unverified
variable. Unsupported Plan 9 CPUs must fail clearly or omit the unexposed
facility according to a reviewed build result; they must never fall back to
APE silently. Non-Plan-9 builds must remain unchanged.

`plan9.cma` must remain ML-only. Ordinary users must continue to require no
`-custom`, `-use-runtime`, C compiler, linker, wrapper compiler, or additional
archive.

## Required focused tests

The Phase 0 test interface is private and uninstalled. It may declare private
`external` bindings directly, but no new name appears in `plan9.mli` or the
installed reference as public API.

At minimum, test:

- forged primitive arguments fail before native work;
- an empty payload and a binary payload containing embedded NUL round-trip
  through a native pipe;
- the I/O loops handle positive short counts rather than assuming one call
  completes the request;
- closing the writer produces EOF after all bytes are read;
- closing both endpoints leaves no owned descriptor;
- source review confirms that successful pipe acquisition reaches ownership
  publication without a fallible OCaml allocation;
- reading a deliberately closed endpoint returns a nonempty immediate native
  error without `errno` translation;
- close and error cleanup preserve the error from the operation that failed;
- repeated round trips have clean descriptor postconditions; and
- existing `otherlibs/plan9` tests retain their behavior.

For the empty-payload case, close the designated writer without issuing a
zero-length write. The matching `pipe(2)` manual warns that a zero-length pipe
write is indistinguishable from EOF to the reader, so it is not a useful event
to assert independently.

The test must not use an ordinary OCaml channel, `Unix`, `Sys.command`, a
temporary file, shell execution, APE descriptor registration, or another
process.

## Symbol and source audit

Inspect the new raw object and runtime integration object separately.

Acceptance requires evidence that:

- the raw assembly object has no undefined library calls;
- the new objects neither define nor reference `_PIPE`, `_PREAD`, `_READ`,
  `_PWRITE`, `_WRITE`, `_CLOSE`, `_ERRSTR`, `_WAIT`, ordinary `pipe`, `read`,
  `write`, or `close` as their operating-system path;
- only the repository-prefixed raw entries issue the relevant syscalls;
- source search finds no `_fdinfo`, `errno`, ordinary channel conversion, or
  APE registration or private `sys9.h` inclusion in the new path; and
- the whole-runtime presence of unrelated APE symbols is not misreported as a
  failure of the isolated veneer audit.

Record the exact inspection commands and relevant output. If the installed
toolchain lacks the initially expected symbol utility, determine and document
the narrow native equivalent rather than weakening the criterion.

## Execution sequence and mandatory pauses

### 1. Preflight and design confirmation

Record branch, `HEAD`, remotes, worktree/index state, applicable repository
instructions, and exact source references. Re-read the relevant current
runtime build and primitive-generation code before proposing edits.

### 2. Build experiment and implementation

Implement the smallest build proof and five-operation veneer. Keep discoveries
classified as confirmed fact, implementation decision, or unresolved issue.
Do not begin `Plan9.Fd` as a way to make the test easier.

### 3. Source review before VM work

Run all safe host-side static checks, inspect the complete diff, and perform a
fresh correctness review. Report the proposed code and any design deviation to
the user. Do not start or access a VM yet.

This is a mandatory user-review point. If review changes the architecture,
update the foundation or handoff only with the user's agreement before
continuing.

### 4. Explicit VM and prefix confirmation

Before any VM operation, ask the user to confirm:

- the exact writable VM instance;
- the explicit loopback address;
- the intended start/access action and acceleration profile; and
- the isolated experimental install prefix, if installation will be tested.

Never boot a protected checkpoint, guess an endpoint, share a writable disk,
or overwrite the known-working compiler prefix. Use the repository's VM and
native-build skills exactly. Transfer source through `/mnt/term`, then build on
native Plan 9 storage; never transfer `.git` and never build on `/mnt/term`.

### 5. Native qualification

On the confirmed guest:

1. Record guest release, `cputype`, `objtype`, configured host identity, exact
   compiler/assembler/archive tools, and GNU Make path.
2. Verify that the guest matches the amd64 release assumptions or stop.
3. Build the reviewed exact source on native storage through the existing
   APE/GNU Make lane.
4. Run the focused Phase 0 test and the existing Plan 9 regression suites.
5. Perform the object-level symbol/source audit.
6. Verify primitive inventory and `plan9.cma` ML-only packaging.
7. If the user approved an isolated install prefix, install there and prove an
   ordinary installed consumer still needs no consumer C tools.
8. Record descriptor, process, temporary-file, source-tree, prefix, and VM
   postconditions.

If installation was not authorized, state that the installed-prefix acceptance
criterion remains open. Do not present source-tree success as full Phase 0
acceptance.

### 6. Report and stop

After validation, report the complete result and stop. Do not begin
`Plan9.Fd`, migrate process code, implement capture, merge, tag, or publish a
release.

Do not commit or push implementation changes unless the user explicitly asks
in the executing conversation. Never publish a known-broken or only partially
validated runtime change.

## Strictly excluded work

Phase 0 does not include:

- any public addition to `Plan9` or `plan9.mli`;
- `Plan9.Fd`, `Plan9.In_channel`, `Plan9.Out_channel`, `Plan9.File`,
  `Plan9.Stat`, `Plan9.Directory`, or `Plan9.Command`;
- modification or migration of `Plan9.Env`, `Plan9.Raw`, or `Plan9.Process`;
- `run_capture`, line splitting, command execution, process creation, `dup`,
  `rfork`, `exec`, `exits`, or `await`;
- standard input/output adoption or raw descriptor integers;
- changes to portable `Stdlib`, `Sys`, or `Unix`;
- a second runtime, removal of APE, custom-runtime repair, native-code support,
  shared libraries, or systhreads;
- temporary-file I/O, shell commands, or external service behavior; and
- VM snapshots, checkpoint replacement, release publication, or Caml9 changes.

If one of these appears necessary, stop and return the evidence. Do not expand
the phase on your own.

## Completion report

The executing conversation must report:

- adopted handoff and foundation-document paths;
- exact starting base, documentation checkpoint, branch, tested tree, and
  final commit identities, distinguishing committed and uncommitted states;
- selected 9front source and guest release/architecture provenance;
- files changed and why;
- raw symbols, syscall mapping, staging capacity, primitive shapes, and build
  integration actually used;
- every host and native validation command with pass/fail result;
- symbol-audit evidence and APE-independence conclusion;
- `plan9.cma` and ordinary-link packaging evidence;
- descriptor and guest cleanup results;
- every deviation, open criterion, uncertainty, or skipped gate;
- the approved install prefix and proof that the known-working prefix was not
  changed, if installation occurred; and
- final worktree, index, branch, remote-tracking, VM, listener, and writable
  disk status.

End the task with an explicit recommendation of either:

- **Phase 0 accepted; ready for architectural regroup before `Plan9.Fd`**;
- **implementation ready but native qualification still required**; or
- **Phase 0 blocked or rejected**, with the exact reason.

Do not claim that the entire runtime is APE-free. The only acceptance claim is
that the reviewed five-operation path is independent of APE's operating-system
I/O and descriptor machinery inside the existing APE-linked runtime.
