# Phase 2.4 public `Plan9.In_channel` and final acceptance handoff

Status: proposed focused handoff for review; implementation has not begun

Reviewed Phase 2 documentation checkpoint: pending final documentation-content
commit and follow-up checkpoint-recording commit.

## Authority and required reading

Read completely before implementation:

- repository `AGENTS.md`;
- top-level `README.md`;
- `build-aux/plan9/README.md`;
- `docs/design/plan9-native-io-foundation.md`;
- `docs/design/handoffs/plan9-native-in-channel-phase2.md`;
- every accepted Phase 2.1, 2.2, and 2.3 handoff and completion report;
- the accepted Phase 1.3 final-acceptance handoff for fresh-source,
  installed-prefix, ML-only, and privacy-probe precedent; and
- current `otherlibs/plan9/README.md`, `REFERENCE.md`, `plan9.mli`, Makefile,
  and install rules.

This is the only Phase 2 handoff that may publish the module, install it, or
declare final Phase 2 acceptance. It does not authorize Phase 3 process work.
If accepted source and documents conflict, stop and report the exact conflict.

## Start gate

Begin only from a reviewed, implemented, natively qualified, coherent Phase
2.3 checkpoint. Verify and record:

- branch `codex/plan9-native-io-foundation`;
- exact `HEAD`, upstream, recent log, and accepted Phase 2.3 commit;
- clean worktree and index with no unrelated source or generated change;
- the complete reviewed Phase 2 documentation checkpoint; and
- no known-broken or open predecessor criterion.

If any condition differs, stop. Do not clean, stash, reset, switch branches,
or absorb another task's work.

Before any VM operation, separately obtain user confirmation of the exact
writable instance, unique loopback address, intended action, and WHPX profile.
Before configure or install, obtain an approved isolated test prefix and its
retain/remove disposition. The prefix must be nonexistent unless the user
explicitly approves replacement.

## Accepted predecessor facts

Phase 2.3 supplies the complete internal implementation:

- allocation-safe `Fd` attachment, permanent public-alias revocation, and
  explicit owner close;
- channel-wide reentrancy serialization and exception restoration;
- one common fixed scratch buffer/refill path with no implicit retry;
- range-validated `input`;
- byte-exact bounded `input_line`;
- byte-exact bounded `input_all` and `input_lines`;
- finite defaults, caller-supplied limit validation, exact-bound success,
  first-excess preservation, and documented non-transactional errors; and
- focused fake and native tests passing on the accepted Phase 2.3 tree.

Phase 2.4 must not redesign those semantics. Any source change beyond public
integration, documentation, consumer/privacy tests, dependency wiring, or a
review-proven defect blocks final qualification until the owning subphase is
reopened and revalidated.

## Delegated outcome

Publish exactly this installed surface:

```ocaml
module In_channel : sig
  type t

  val of_fd : Fd.t -> (t, error) result
  val close : t -> (unit, error) result
  val input :
    t -> bytes -> pos:int -> len:int -> (int, error) result
  val input_line :
    ?max_bytes:int -> t -> (string option, error) result
  val input_all :
    ?max_bytes:int -> t -> (string, error) result
  val input_lines :
    ?max_bytes:int -> ?max_line_bytes:int ->
    t -> (string list, error) result
end
```

`plan9.ml` re-exports the production implementation as
`module In_channel = Plan9_in_channel`. `plan9.mli` spells out the public
signature and documentation without importing or exposing private functors,
attachment tokens, scratch capacity, state constructors, or implementation
module names.

No existing public type, constructor, function, or behavior changes. In
particular, `error_kind` remains exactly:

```ocaml
type error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other
```

## Final public semantics

The installed documentation must state clearly:

- `In_channel.t` is distinct from `Stdlib.in_channel` and cannot be passed to
  `Stdlib`, `Sys`, `Unix`, or ordinary-channel functions;
- `of_fd` transfers operational ownership; after success every retained
  `Fd.t` alias permanently rejects read, write, close, and attachment;
- cleanup is explicit and deterministic with no descriptor-closing finalizer;
- `input` uses the exact subtraction-based range rule, validates authorized
  zero length, may return less than requested, and returns zero for the EOF
  observed by that call;
- a positive `input` consumes buffered bytes first and callers must honor its
  returned count;
- only byte newline terminates a line; CR, NUL, and every other byte are
  preserved;
- empty input, empty lines, trailing newline, and unterminated final-line
  behavior match the roadmap;
- materializing calls are finite by default, expose the exact optional bounds,
  and accept bounds only from zero through `Sys.max_string_length`;
- line bounds exclude newline; `input_lines` whole-input bounds include it;
- an exact line bound succeeds before newline or EOF, an exact whole-input
  bound succeeds only before EOF, and excess discards the allowed prefix,
  leaves the first excess byte and complete already-buffered suffix unread,
  returns `Other`, and does not close;
- lower read errors and interruption are never retried; partial buffered
  progress is non-transactional and an interrupted native read may have
  unknown underlying consumption;
- close discards unread buffered data, normal close failure is terminal, and
  repeated close after terminal state is idempotent; and
- no EOF cache promises that later calls avoid a new descriptor read.

Do not claim exact-fill `input`, seek/position/length, file opening, standard
input, text translation, Unicode semantics, automatic close, or unbounded
operation.

## Exact default and error contract

Public documentation records:

- `input_line` default `max_bytes = 1_048_576`;
- `input_all` default `max_bytes = 16_777_216`;
- `input_lines` defaults `max_bytes = 16_777_216` and
  `max_line_bytes = 1_048_576`.

It also records these exact wrapper messages, with decimal substitution:

| Condition | Kind | Message |
| --- | --- | --- |
| invalid byte range | `Invalid_argument` | `invalid byte range: buffer length {buffer_length}, position {pos}, length {len}` |
| negative total/single bound | `Invalid_argument` | `maximum byte count must be nonnegative: {max_bytes}` |
| total/single bound above representability | `Invalid_argument` | `maximum byte count exceeds Sys.max_string_length: {max_bytes}` |
| negative line bound | `Invalid_argument` | `maximum line byte count must be nonnegative: {max_line_bytes}` |
| line bound above representability | `Invalid_argument` | `maximum line byte count exceeds Sys.max_string_length: {max_line_bytes}` |
| line excess | `Other` | `input line exceeds maximum of {max_bytes} bytes` for `input_line`, or `input line exceeds maximum of {max_line_bytes} bytes` for `input_lines` |
| whole-input excess | `Other` | `input exceeds maximum of {max_bytes} bytes` |
| operation overlap | `Invalid_argument` | `input channel operation is already in progress` |
| input during close | `Invalid_argument` | `input channel close is already in progress` |
| input after close | `Invalid_argument` | `input channel is closed` |
| malformed fill count | `Protocol_error` | `invalid input buffer fill result: buffer length {buffer_length}, returned count {count}` |

`of_fd` failed preparation/commit and close-in-progress messages remain as in
the focused handoffs. Each error's `operation` is the invoked public channel
function. Native/lower messages retain exact text. Do not document private
`Plan9.Fd` operations as part of the channel API.

## Authorized source and documentation boundary

This subphase may update:

- `otherlibs/plan9/plan9.mli`;
- `otherlibs/plan9/plan9.ml`;
- `otherlibs/plan9/README.md`;
- `otherlibs/plan9/REFERENCE.md`;
- top-level `README.md` for the concise native-API summary;
- `otherlibs/plan9/Makefile` only for the final public focused-test link shape;
- generated `otherlibs/plan9/.depend` through the native gate;
- existing Phase 2 tests only if public re-export requires their positive path
  to be extended; and
- exactly three new qualification-only test sources:
  `tests/in_channel_installed_consumer_test.ml`,
  `tests/plan9_in_channel_surface_negative.ml`, and
  `tests/in_channel_private_surface_negative.ml`.

The installed-consumer and negative sources are qualification inputs, not
ordinary `TEST_PROGRAMS`; do not compile them during `all` or `test` and do not
add generated dependency rules for them.

If final review discovers a semantic implementation defect in
`plan9_in_channel.ml` or its focused tests, stop and return to the owning
subphase rather than silently expanding this boundary.

After accepted qualification, update `build-aux/plan9/README.md` with the
exact Phase 2 commit, fresh native tree, approved prefix, protected-prefix
result, and ordinary installed-consumer command. That evidence update occurs
only after the facts exist; do not predeclare success.

## Build and dependency integration

The final archive order remains:

```make
plan9_types.cmo plan9_primitive.cmo plan9_fd.cmo \
  plan9_in_channel.cmo plan9_process.cmo plan9.cmo
```

Publishing `module In_channel = Plan9_in_channel` adds the expected generated
dependency from `plan9.cmo`/`plan9.cmx` to the private implementation object.
Because `plan9.mli` spells the signature, installed `plan9.cmi` must not import
`Plan9_in_channel` or `Plan9_fd` CMIs as consumer dependencies. Verify with
`ocamlobjinfo` and an isolated installed compile.

`CMIFILES` remains exactly `plan9.cmi`. Internal `plan9_types.cmi`,
`plan9_primitive.cmi`, `plan9_fd.cmi`, `plan9_in_channel.cmi`, and
`plan9_process.cmi` remain uninstalled. Source docs and test sources remain
uninstalled under the accepted install wrapper.

`plan9.cma` remains ML-only. It gains no C object, C option, dynamic library,
custom-runtime force, alternate runtime, primitive payload, or wrapper
compiler requirement. No runtime primitive inventory change is expected.

Never hand-edit `.depend`. Generate it with the target compiler in the exact
native APE/GNU Make lane, return only the generated file to Windows, and
review every dependency change before final source manifest creation.

## Required public and privacy probes

### Ordinary source-tree public test

Before fresh final qualification, adapt the existing native Phase 2 positive
test to exercise the `Plan9.In_channel` umbrella surface as well as the
private implementation where private invariants still need coverage. Prove
the public CMI exposes exactly the final API and no `Private` submodule.

### Installed consumer

`in_channel_installed_consumer_test.ml` uses only `Plan9` and public standard
library modules. It must:

- inventory `/fd` before and after;
- create a public `Plan9.Fd.pipe`;
- attach one peer with `Plan9.In_channel.of_fd`;
- prove the retained public alias is revoked;
- write a binary multiline payload containing NUL through the other public
  peer and close that writer;
- exercise public `input`, `input_line`, `input_all`, or `input_lines` in a
  compact set covering buffered bytes, newline, EOF, and an explicit small
  exact limit;
- close the channel and repeat close;
- leave the exact sorted `/fd` inventory unchanged; and
- print one deterministic success marker.

It must not reference `Plan9_fd`, `Plan9_in_channel`, private attachment
tokens, raw descriptors, ordinary channels, source-tree paths, or a custom
runtime.

### Expected-failure privacy probes

Compile against only the installed prefix and require failure:

- `plan9_in_channel_surface_negative.ml` attempts to name
  `Plan9_in_channel`; it must fail because the private CMI is absent; and
- `in_channel_private_surface_negative.ml` attempts to name
  `Plan9.In_channel.Private`; it must fail because the installed umbrella does
  not expose private ownership operations.

Require the expected unbound-module/submodule diagnostics and fail if either
probe compiles. Keep their directories free of source-tree CMIs or archives.

## Complete focused and regression tests

Run the complete accepted Phase 0, Phase 1, and Phase 2 focused suites from the
fresh final tree. Phase 2 evidence must cover at least:

- preparation failure, commit loss, retained aliases, exact-owner close, and
  exception-left close retry;
- range precedence, authorized zero length, buffered progress, one empty-
  buffer refill, positive short reads, and observed EOF;
- all newline/empty/trailing/unterminated/NUL/CR semantics;
- arbitrary delimiter and native-write splits, long lines, large aggregates,
  and payloads beyond the private scratch capacity;
- invalid, zero, exact, plus-one, default, and maximum accepted limit values;
- exact line-limit newline/EOF success, exact whole-limit EOF success, and
  first-excess plus complete-buffered-suffix preservation;
- `input_lines` whole/per-line counting and simultaneous-limit precedence;
- lower/native errors, malformed fake counts, no retry, partial-consumption
  semantics, active-operation callbacks, exception identity, and GC;
- deterministic close after success, EOF, error, and limit failure;
- public umbrella behavior and privacy;
- at least 256 repeated native channel cycles with unchanged sorted complete
  `/fd` inventory; and
- all existing environment, process, frame, raw syscall, hostile primitive,
  descriptor lifecycle/I/O, and native integration regressions unchanged.

No production fault switch is added. Actual timing-sensitive note interruption
is excluded from ordinary Phase 2 acceptance unless separately authorized;
fake call counts plus accepted lower evidence prove the no-retry policy.

## Complete source, symbol, and packaging audit

Review and record evidence that:

- successful ownership commit is followed by immediate preallocated result
  publication;
- channel state serializes every mutation-sensitive operation and restores
  stable state before ordinary reraise;
- buffer and accumulator arithmetic is checked before indexing/allocation;
- no lower failure is retried and no line/aggregate limit drains unbounded
  input;
- exact first-excess positioning is independent of buffer/write splits;
- only the committed attachment token reaches lower read/close;
- retained `Fd.t` aliases remain revoked permanently;
- no raw descriptor or ordinary channel crosses the ML boundary;
- no APE I/O or descriptor symbol is introduced into the reviewed native path;
- raw syscall assembly objects remain free of undefined library calls;
- every Plan 9 primitive remains defined exactly once, with no new primitive;
- `plan9.cma` reports no forced custom mode, extra C object/options, or dynamic
  library requirement;
- only `plan9.cmi` is installed and its import set is consumer-complete;
- internal CMIs, test helpers, docs, and C sources are not installed; and
- portable `Stdlib`, `Sys`, `Unix`, current `Plan9.Env`, `Raw`, and `Process`
  behavior is unchanged.

The accepted APE-independence statement remains scoped to the native
descriptor/channel operating-system path within the standard APE-linked
runtime. Do not call the whole runtime or library APE-free.

## Fresh authoritative source-set gate

Final qualification begins only after complete host review. Build the transfer
set from every existing path reported by `git ls-files`, using current
authoritative Windows worktree bytes rather than index or `HEAD` bytes,
adjusted only for explicitly reviewed new/deleted source paths. Record:

- branch, `HEAD`, index and worktree status;
- tracked transfer paths;
- separately inventoried untracked and ignored paths;
- every reviewed addition/deletion and exclusion;
- hash algorithm and tool identities; and
- canonical host manifest location outside the source tree.

The canonical manifest has one tuple per transferred file:

```text
repository/relative/path<TAB>decimal-byte-length<TAB>lowercase-hex-digest
```

Normalize paths to `/`, sort bytewise by normalized path, keep manifests
outside both source trees, and compare parsed tuples rather than raw command
output. Never transfer `.git`.

Copy only that approved set through `/mnt/term`, then onto a fresh,
previously nonexistent native Plan 9 destination. Independently generate the
same manifest on native storage before configure. Require exact tuple equality,
absence of `.git`, no extra destination path, and no prior configure/build
artifact. A mismatch stops the gate.

Configure, build, test, and install only from this fresh native source tree.
Do not substitute a remote clone, Windows build, `/mnt/term` build, old object,
archive, generated primitive table, configured header, or retained incremental
tree for final evidence.

## Native configure, build, and test gate

From the fresh native tree:

1. Enter APE only through `ape/psh`.
2. Set the exact shim `PATH` documented by `build-aux/plan9/README.md`.
3. Resolve and export the actual GNU Make executable; do not assume the
   wrapper default exists.
4. Configure with `build-aux/plan9/configure.sh --prefix=<approved-prefix>`.
5. Build with `build-aux/plan9/build-world.sh`.
6. Run the full Plan 9 suite with a new valid unique `TEST_SUFFIX`.
7. Run all focused privacy/source probes that are intentionally outside the
   ordinary test target.
8. Record exact commands, versions, paths, exit status, and deterministic
   success markers.

Inspect the exact built runtime and archive, not a similarly named prior
artifact. Record guest release and amd64 architecture and compare them with
the retained release-11554 reference; mismatch stops acceptance pending
review.

## Installed-prefix acceptance

The approved test prefix must be isolated and nonexistent before install
unless replacement was explicitly approved. Never install over the protected
`/usr/glenda/lib/unix/ocaml-4.14.3`. Record sorted path/length/content-hash
manifests of the protected prefix before and after; if it is absent, record
that exact state both times.

Install with `build-aux/plan9/install.sh` under the same resolved GNU Make and
configured prefix. Then use the installed compiler and runtime, outside source,
build, and install trees, with `OCAMLPARAM`, `OCAMLLIB`, legacy `CAMLLIB`, and
`CAML_LD_LIBRARY_PATH` unset.

Record `<installed ocamlc> -where`, require it lies inside the approved prefix,
resolve `+plan9` to its `plan9` subdirectory, and hash the exact installed
`plan9.cma` and `plan9.cmi`. Keep the smoke directory free of competing copies.

Compile the manifest-verified installed consumer with exactly this ordinary
shape, where no other explicit include path is present:

```sh
<installed ocamlc> -I +plan9 -linkall plan9.cma \
  <copied in_channel_installed_consumer_test.ml> -o <smoke>
```

Run with the installed `ocamlrun`. Use fail-closed command sentinels or
equivalent accepted evidence to prove compilation/linking invoked no C
compiler, linker, archiver, `ocamlmklib`, `flexlink`, wrapper compiler, custom
runtime, or source-tree runtime. `ocamlobjinfo` must report ML-only/no forced
custom behavior.

Compile both negative privacy probes in isolated directories with the same
installed compiler and exactly `-I +plan9`; require their expected failures.
Source-tree execution, source-tree artifact resolution, installation inventory
alone, or a smoke linked against an unintended archive does not satisfy this
gate.

After qualification, follow the user's approved retain/remove disposition for
the test prefix and smoke directory. Deletion or replacement requires exact
target verification and authorization. Never alter the protected prefix.

## Execution sequence and mandatory pauses

### 1. Preflight and public integration

Record exact Phase 2.3 state. Implement only public integration, docs, and
qualification sources. Leave `.depend` untouched until native generation.

### 2. Complete source review

Inspect every changed line, public signature, docs claim, test, archive rule,
install selection, and private-surface boundary. Run safe host-side diff/text
checks. Report any deviation and pause.

### 3. Explicit VM and prefix confirmation

Obtain the exact writable VM instance, unique loopback address, action, WHPX
profile, approved isolated prefix, nonexistent/replacement condition, and
retain/remove disposition. Inspect the process chain, QEMU PID, disk, address,
and seven listeners before use.

### 4. Native dependency generation and authoritative return

Use a disposable native copy only to generate target `.depend` through the
documented APE environment. Return only `.depend`, inspect its exact source
reasons, then perform final authoritative host review. Any semantic source
change repeats this step.

### 5. Fresh manifest and qualification

Create matching host/native manifests and the fresh source destination, then
configure, build, run all tests/audits, install only to the approved prefix,
and execute installed positive/negative probes. Any mismatch or failure stops
acceptance; do not patch the guest or publish partial results.

### 6. Report and stop

Halt the VM through Drawterm `fshalt` if the user wants it stopped, wait for
the exact QEMU PID, and verify the selected listeners close. Report all source,
test, packaging, prefix, protected-prefix, VM, disk, listener, Git, and remote
state. Do not begin Phase 3, merge, or publish a release.

Implementation commit and push require explicit user instruction after the
complete reviewed and qualified result. Never publish a known-broken or
partially qualified runtime change.

## Completion report

Report:

- all adopted document paths and reviewed documentation checkpoint;
- exact branch, starting Phase 2.3 commit, final tested source identity,
  implementation commit if authorized, and remote-tracking state;
- complete public API and every file changed;
- exact default/limit/error/stream-position semantics;
- host review, generated dependency, fake, native, regression, privacy, and
  installed-consumer commands/results;
- source manifest basis, additions/deletions, inventories, tools, algorithm,
  locations, and exact comparison result;
- guest release/architecture, fresh source path, configure/build/test paths,
  and GNU Make identity;
- runtime primitive, symbol, archive, `ocamlobjinfo`, installed-file, and C-tool
  sentinel evidence;
- approved prefix, `ocamlc -where`, resolved `+plan9`, installed archive/CMI
  hashes, smoke directory, and disposition;
- protected-prefix before/after manifest equality or exact absent state;
- repeated `/fd` cleanup and all VM/PID/listener/disk postconditions;
- every deviation, skipped gate, uncertainty, or open criterion; and
- exactly one recommendation:
  - **Phase 2 accepted; ready to design process backend migration**;
  - **implementation ready but native qualification still required**; or
  - **Phase 2 blocked or rejected**, with the exact reason.

## Strict exclusions

This subphase excludes:

- semantic redesign of accepted Phase 2.1-2.3 behavior;
- process backend migration, stdout capture, `Plan9.Command`, or Phase 3/4;
- `Out_channel`, file, stat, directory, or environment migration;
- new primitives, raw syscalls, runtime C, `Fd` changes, raw descriptor
  exposure, ordinary channels, standard input, file opening, seeking, position,
  length, text translation, or finalizers;
- a new error kind or automatic close/unbounded drain on a limit;
- timing-sensitive note injection without separate approval;
- install over the protected prefix;
- snapshot/checkpoint replacement, branch merge, release publication, or
  Caml9 source changes.

If excluded work appears necessary, stop and report the evidence rather than
expanding Phase 2.4.
