# Phase 1.1 private ML regroup handoff

Status: draft execution handoff for review; Phase 0 accepted at
`aa627e94e9db4a680a30c8e3671a00e709a97320`

## Authority and required reading

This handoff delegates only the Phase 1.1 architectural regroup. Before
editing, read:

- `docs/design/handoffs/plan9-native-fd-phase1.md` completely;
- the foundation's repository identities, APE-independence boundary, layered
  architecture, proposed source boundary, `Plan9.Fd` target contract,
  implementation sequence, non-goals, and required reports;
- the accepted Phase 0 implementation diff through
  `aa627e94e9db4a680a30c8e3671a00e709a97320`;
- the repository `AGENTS.md`; and
- the applicable local VM and native-build skills before those actions occur.

If the accepted predecessor differs from the facts below, or this handoff
conflicts with the reviewed roadmap or foundation, stop and return the
evidence.

## Start gate

Work only in `C:\Users\dharm\src\ocaml` on
`codex/plan9-native-io-foundation`. The accepted code predecessor is exactly
`aa627e94e9db4a680a30c8e3671a00e709a97320`. The executing request must name
the exact user-approved Phase 1 documentation-checkpoint `HEAD` created after
review of these drafts.

Verify that the starting `HEAD` descends from the accepted predecessor with
only the reviewed documentation changes after it, and that the index and
worktree are clean with no unexpected history. Do not begin from an
uncommitted, dirty, unqualified, or rejected predecessor. Do not stash, reset,
clean, or absorb unrelated work.

## Accepted predecessor facts

Phase 0 is implemented, reviewed, natively qualified, committed, and pushed at
`aa627e94e9db4a680a30c8e3671a00e709a97320`. The accepted source includes the
five raw amd64 entries, validated opaque capability primitives for pipe,
close, read, and write, the negative read probe, focused private tests, and
the required GNU Make, runtime archive, primitive inventory, and Dune mirror
wiring.

The current Plan 9 ML library predates the foundation's intended private
module split:

- `Plan9_process` owns shared public error and identity types as well as
  process-specific state;
- `plan9.ml` contains the built-in primitive bindings and the `Native` adapter;
- `plan9.ml` aliases shared public types through `Plan9_process`; and
- the process primitive-validation and Phase 0 syscall-capability tests
  intentionally declare hostile test-local bindings directly.

The installed public interface is only `plan9.cmi`. The current archive order
is `plan9_process.cmo plan9.cmo`; internal interfaces are not installed.
`plan9.cma` has no C payload. Existing `Env`, `Raw`, and `Process` behavior is
accepted and must not change in this regroup.

## Delegated outcome

Establish the private one-way ML source boundaries promised by the foundation
before implementing descriptor ownership:

1. `Plan9_types` owns shared public-compatible types and native error mapping;
2. `Plan9_primitive` owns private built-in primitive bindings and the exact ML
   shapes crossing those bindings;
3. `Plan9_process` owns only process coordination and public process types,
   while consuming the shared types and primitive ABI types; and
4. `plan9.ml` remains the umbrella implementation, re-exporting public types
   and modules without owning private primitive declarations.

This is a behavior-preserving refactor. It adds no `Plan9.Fd`, no public name,
no public signature change, no native primitive, no C or assembly change, and
no new APE-independence claim.

## Exact private source boundary

### `Plan9_types`

Add uninstalled `otherlibs/plan9/plan9_types.mli` and `.ml`. They own exactly
the shared definitions needed by more than one high-level module:

```ocaml
type error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

type pid = int
type process_id = int64

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

type native_failure = {
  native_kind : int;
  native_message : string;
}

val wait_succeeded : wait_msg -> bool
val error_of_native : string -> native_failure -> error
```

`wait_succeeded` retains the exact accepted implementation predicate:

```ocaml
let wait_succeeded wait_msg = wait_msg.message = ""
```

The `native_failure` declaration is a positional two-field native ABI record,
not merely a shared ML type. `runtime/plan9_process.c` stores the native kind
at field `0` and the native message at field `1`; neither field may be
reordered, inserted, removed, or changed in type during this regroup.

Preserve the accepted native-kind mapping exactly:

- kind `0` maps to `Invalid_argument`;
- kind `2` maps to `Interrupted`;
- kind `3` with exact message `"no living children"` maps to `No_children`;
- kind `3` with every other message maps to `Protocol_error`;
- kind `4` maps to `Protocol_error`; and
- every other kind maps to `Other`.

Do not broaden string-based classification or change existing public
operation names or messages.

The installed `plan9.mli` retains its existing declarations. The umbrella
implementation aliases them through `Plan9_types`, so the compiled
implementation has one shared identity without exposing `Plan9_types.cmi`.

### `Plan9_primitive`

Add uninstalled `otherlibs/plan9/plan9_primitive.mli` and `.ml`. In this
subphase, the module owns only the production built-in primitive declarations
already present in `plan9.ml`, together with their private ABI record types.
This preserves the exact primitive-import set of `plan9.cma`.

The private ABI record types are exactly the following, in this field order:

```ocaml
type native_pending = {
  native_process_id : int64;
  native_pid : int;
  native_handshake : int;
  native_detail : Plan9_types.native_failure;
  native_queue_loss : Plan9_types.native_failure option;
}

type native_wait_event = {
  native_sequence : int64;
  native_event_kind : int;
  native_wait_pid : int;
  native_user_time_ms : int64;
  native_system_time_ms : int64;
  native_elapsed_time_ms : int64;
  native_event_detail : Plan9_types.native_failure;
}
```

Field order is native ABI, not merely an ML presentation choice:
`runtime/plan9_process.c` allocates these records as positional five- and
seven-field blocks. Do not reorder, insert, remove, or change a field type
without rejecting this behavior-preserving subphase and reviewing a native ABI
change.

The production constants retain these exact implementation values:

```ocaml
let foreign_capacity = 64
let spawn_flags = 16 lor 4 lor 8192  (* 8212 *)
```

The production primitive declarations move from `plan9.ml` with these exact
ML binding names, types, C symbols, and arities:

```ocaml
external copy_environment :
  unit -> (unit, Plan9_types.native_failure) result
  = "caml_plan9_copy_environment"

external exec :
  string ->
  string array ->
  ('a, Plan9_types.native_failure) result
  = "caml_plan9_exec"

external spawn :
  string ->
  string array ->
  int ->
  string ->
  int ->
  (native_pending, Plan9_types.native_failure) result
  = "caml_plan9_process_spawn"

external pending :
  unit -> native_pending array
  = "caml_plan9_process_pending"

external acknowledge_pending :
  int64 -> bool
  = "caml_plan9_process_acknowledge"

external await :
  unit -> native_wait_event
  = "caml_plan9_process_await"

external acknowledge_wait :
  int64 -> bool
  = "caml_plan9_process_acknowledge_wait"
```

None of these declarations currently carries an external attribute. Do not
add `[@@noalloc]` or any other calling-convention or code-generation attribute
during the regroup. `Plan9_primitive.mli` exposes the corresponding values and
exact record representations; the implementation alone owns the `external`
declarations.

Do not add `descriptor_capability` or production bindings for
`caml_plan9_syscall_pipe`, `caml_plan9_syscall_close`,
`caml_plan9_syscall_read`, or `caml_plan9_syscall_write` in Phase 1.1. Those
names currently exist only in the Phase 0 hostile test. Phase 1.2 adds the
production capability, pipe, and close bindings together with their first
production owner; Phase 1.3 adds production read and write bindings together
with typed byte I/O. The negative probe remains test-only throughout.

The private ML binding names above are part of the reviewed boundary. Any
proposed renaming requires a documentation review before implementation. The
production C symbol names, arities, result layouts, external attributes, and
native failure type must remain exact.

`Plan9_primitive` depends only on `Plan9_types`. It must not depend on the
umbrella or on `Plan9_process`.

### `Plan9_process`

Remove duplicate ownership of the shared types and native ABI records while
preserving the current private qualified names with exact manifest aliases:

- `error_kind`, `error`, `pid`, `process_id`, `wait_msg`, and
  `native_failure` alias their `Plan9_types` definitions;
- `native_pending` and `native_wait_event` alias their `Plan9_primitive`
  definitions; and
- `wait_succeeded` and `error_of_native` are value aliases to
  `Plan9_types`.

Every manifest alias preserves the complete existing representation,
independent of which names current tests happen to use:

- `error_kind` re-exports all five constructors in their existing order;
- `error`, `wait_msg`, and `native_failure` re-export every existing record
  field in its existing order and type; and
- `native_pending` and `native_wait_event` re-export every field from the exact
  `Plan9_primitive` records above in the same order and type.

Existing qualified constructors, qualified record labels, and
`Plan9_process.{ ... }` construction must all continue to compile. An `open`,
an unqualified constructor, or current test coverage is not a substitute for
preserving those names. The `Native` signature consumes these aliases and
therefore the exact `Plan9_primitive` record identities rather than defining a
second shape.

This is a type-level dependency on `Plan9_primitive.cmi`, not authorization
for `plan9_process.cmo` to import or initialize `Plan9_primitive` at runtime.

Preserve the `Make` functor, all process state transitions, managed identity,
pending/wait ownership, result constructors, public behavior, and focused
fake-backend testing. This handoff is not authorization to simplify or migrate
the process backend.

### Umbrella implementation

Remove the private `Native` external-binding module from `plan9.ml` and use
`Plan9_primitive` directly for existing `Raw` wrappers and as the backend for
`Plan9_process.Make`. Alias `error_kind`, `error`, `pid`, `process_id`, and
`wait_msg` through `Plan9_types`, and define `wait_succeeded` as the direct
value alias `Plan9_types.wait_succeeded`.

The `Raw` wrappers map primitive failures directly through
`Plan9_types.error_of_native`, retaining the exact operation strings
`"Plan9.Raw.copy_environment"` and `"Plan9.Raw.exec"`. Do not route either
shared value through the compatibility aliases in `Plan9_process`; those
aliases preserve the existing private qualified interface for process code
and tests, but `Plan9_types` is the actual owner consumed by the umbrella.

Do not change `plan9.mli`. Do not add `Fd`. `Env`, `Raw`, and `Process` retain
their exact public signatures and operation strings.

## Build and installation wiring

Update `otherlibs/plan9/Makefile` and the generated `.depend` for this layered
direct-dependency DAG:

| Artifact | Private interface dependencies | Runtime implementation imports |
| --- | --- | --- |
| `plan9_types.cmi` | no private predecessor | not applicable |
| `plan9_types.cmo` | `plan9_types.cmi` only | no private predecessor |
| `plan9_types.cmx` | `plan9_types.cmi` only | no private predecessor |
| `plan9_primitive.cmi` | `plan9_types.cmi` | not applicable |
| `plan9_primitive.cmo` | `plan9_primitive.cmi`, `plan9_types.cmi` | no `Plan9_types` runtime global |
| `plan9_primitive.cmx` | `plan9_primitive.cmi`, `plan9_types.cmx` | no `Plan9_types` runtime global |
| `plan9_process.cmi` | `plan9_types.cmi`, `plan9_primitive.cmi` | not applicable |
| `plan9_process.cmo` | `plan9_process.cmi`, `plan9_types.cmi`, `plan9_primitive.cmi` | `Plan9_types` only; no `Plan9_primitive` runtime global |
| `plan9_process.cmx` | `plan9_process.cmi`, `plan9_types.cmx`, `plan9_primitive.cmx` | `Plan9_types` only; no `Plan9_primitive` runtime global |
| `plan9.cmi` | no private interface import | not applicable |
| `plan9.cmo` | `plan9.cmi` and all three private CMIs | direct globals from `Plan9_types`, `Plan9_primitive`, and `Plan9_process` |
| `plan9.cmx` | `plan9.cmi` and all three private `.cmx` files | direct globals from `Plan9_types`, `Plan9_primitive`, and `Plan9_process` |

The arrows are therefore layered rather than a single chain:
`Plan9_types` is a direct predecessor of every private consumer and the
umbrella; `Plan9_primitive` is a type-level predecessor of `Plan9_process` and
a runtime predecessor of the umbrella; and `Plan9_process` is a runtime
predecessor of the umbrella. The generated dependency file is authoritative
for exact build prerequisites, while object inspection is authoritative for
the runtime-global distinction.

The generated `.cmx` edges are conservative native-compilation prerequisites,
not proof of a runtime-global reference. In particular, the generated
`plan9_process.cmx` prerequisite on `plan9_primitive.cmx` does not authorize
`Plan9_process` to import or initialize `Plan9_primitive` at runtime. Preserve
these generated rules for repository and non-Plan-9 build consistency, but do
not build them or report native-code qualification: this Plan 9 port and this
handoff qualify the standard bytecode lane only.

The archive order is exactly `plan9_types.cmo plan9_primitive.cmo
plan9_process.cmo plan9.cmo`, placing every private ML object before its
consumers.
`CMIFILES` remains exactly `plan9.cmi`; none of `plan9_types.cmi`,
`plan9_primitive.cmi`, or `plan9_process.cmi` is installed.

Delete the predecessor's explicit `plan9.cmo: plan9.cmi plan9_process.cmi`
and `plan9.cmx: plan9.cmi plan9_process.cmx` rules from
`otherlibs/plan9/Makefile`. They duplicate the tracked generated graph and
would become a second hand-maintained dependency source during this regroup.
Do not replace them with expanded manual module-prerequisite rules. The native
generated `.depend` is the sole authority for ML module compilation
prerequisites; explicit test-program linkage and non-ML object rules remain in
the Makefile for their separate purposes.

Preserve the pure process-state test lane explicitly. Its executable links, in
order, `plan9_types.cmo` and `plan9_process.cmo`, but not
`plan9_primitive.cmo` or `plan9.cma`, and it continues to run with bootstrap
`$(OCAMLRUN)`. Compilation may require `plan9_primitive.cmi` for manifest type
aliases; linking and execution must not require the primitive implementation
unit or any built-in Plan 9 primitive. Object and executable inspection must
confirm that `plan9_process.cmo` has no runtime import of `Plan9_primitive`.

Because Phase 1.1 adds no descriptor primitive binding to the production
archive, `plan9.cma` must retain exactly the predecessor's primitive-name set.
The existing environment test must retain its accepted bootstrap
runtime lane. A change in primitive imports or required test runtime is a
scope violation, not an incidental regroup artifact.

Every existing source file below `otherlibs/plan9/tests` must remain
byte-for-byte unchanged. In particular, do not adapt the hostile primitive
declarations, fake backends, record construction, or qualified field uses to
make the regroup compile. Necessary Makefile linkage changes do not authorize
test-source changes. A narrowly scoped additive regroup test is permitted if
review evidence requires one, but it must run in addition to every unchanged
predecessor test and must not substitute for their compatibility evidence.

Keep generated dependency rules authoritative. The hand-written implementation
and pre-VM source review leave `.depend` unchanged and explicitly pending; do
not hand-maintain a predicted version. After the mandatory VM confirmation,
run the repository's existing dependency target by itself on native Plan 9
storage, return that generated `.depend` through `/mnt/term` to the
authoritative Windows checkout, and compare the returned content byte for byte
with the guest copy. Perform a final host-side diff and dependency review
before any native build or test. Preserve non-Plan-9 behavior and do not invent
a Dune library for `otherlibs/plan9` in this subphase.

No file below `runtime/` should change. The primitive generator, runtime
archive membership, raw assembly objects, and C integration remain exactly the
accepted Phase 0 implementation.

## Required tests and review evidence

### Host-side review

Before VM work:

- verify `plan9.mli` is byte-for-byte unchanged;
- inspect the hand-written source dependencies against the exact DAG above,
  prove no internal module depends on the umbrella, and record that generated
  `.depend` remains intentionally pending until the confirmed native step;
- distinguish the expected generated `.cmx` prerequisites from runtime-global
  imports and confirm that no native-code build or qualification is claimed;
- confirm the redundant explicit `plan9.cmo` and `plan9.cmx` module dependency
  rules are removed from the Makefile without changing explicit test linkage
  or non-ML object rules;
- inventory every primitive declaration and preserve the intentional direct
  hostile bindings in both
  `tests/process_primitive_validation_test.ml` and
  `tests/syscall_capability_test.ml`; production declarations otherwise live
  only in `Plan9_primitive`; compare every production ML binding name, type,
  C symbol, arity, and absence of external attributes with the exact boundary
  above;
- compare the `native_failure`, `native_pending`, and `native_wait_event` field
  order with the predecessor and with the positional allocations in
  `runtime/plan9_process.c`, while confirming that runtime source is unchanged;
- confirm `foreign_capacity` is exactly `64` and `spawn_flags` is exactly
  `8212` (`16 lor 4 lor 8192`);
- search for duplicate definitions of shared public types and native failure
  mapping;
- confirm `plan9.ml` aliases `wait_succeeded` directly from `Plan9_types` and
  maps both `Raw` primitive failures directly through
  `Plan9_types.error_of_native`, with no shared-value route through
  `Plan9_process`;
- review that every old public operation string and result constructor is
  unchanged;
- verify every predecessor source below `otherlibs/plan9/tests` is
  byte-for-byte unchanged; inspect any additive regroup test for type-identity
  changes hidden by aliases and confirm that it does not replace predecessor
  coverage;
- prove that the pure process-state executable links no
  `plan9_primitive.cmo`, imports no built-in Plan 9 primitive, and still runs
  with bootstrap `OCAMLRUN`;
- compare the primitive-name set imported by `plan9.cma` with the exact
  predecessor and require no addition or deletion; and
- confirm no runtime, assembly, primitive inventory, installed reference, or
  public documentation file changed.

If host OCaml tools suitable for syntax or dependency checks are available in
the repository's supported workflow, use them. Do not treat an unrelated
Windows OCaml installation as native Plan 9 qualification.

### Native qualification

On the user-confirmed writable guest and native source tree:

- after the native dependency-generation round trip and final host review,
  build the standard bytecode runtime and `otherlibs/plan9` archive through the
  existing APE/GNU Make lane;
- run the ordinary `otherlibs/plan9` `test` target, including environment,
  process state, process primitive validation, process frame parser, raw
  syscall, syscall capability, and process native integration tests together
  with its native helper;
- do not run `test-native-interruption`; timing-sensitive note injection
  remains separately authorized and is not part of this regroup;
- record the exact accepted execution matrix: environment and process state
  use bootstrap `$(OCAMLRUN)`; process primitive validation, syscall
  capability, and process native integration use `$(NEW_OCAMLRUN)`; process
  frame parser and raw syscall execute directly as native test programs; and
  the native process helper remains a directly executed child selected by the
  integration test;
- inspect `plan9.cma` and the built/installed-file staging inventory to prove
  that the new private ML objects are in the archive but only `plan9.cmi` is
  selected for installation;
- create a fresh isolated directory on native storage containing only copies
  of `plan9.cma`, `plan9.cmi`, and this minimal public consumer source before
  compilation:

  ```ocaml
  let () =
    ignore Plan9.wait_succeeded;
    print_endline "plan9 staging consumer: passed"
  ```

  Before copying, record the exact just-built source paths, sizes, and content
  hashes of `plan9.cma` and `plan9.cmi`. After copying, record the staged paths,
  sizes, and hashes and require byte-for-byte identity with those just-built
  artifacts. A mismatch is a failed staging gate: do not compile against it.
  Inventory the directory before compilation and prove that
  `plan9_types.cmi`, `plan9_primitive.cmi`, `plan9_process.cmi`, every private
  `.cmo`, and every C payload are absent. Compile the source against the staged
  archive and public CMI from that isolated directory, with no include path
  back to `otherlibs/plan9`, using the ordinary source-tree bytecode compiler
  in the shape `ocamlc -I . plan9.cma consumer.ml -o consumer`. Do not use
  `-custom`, `-use-runtime`, a C compiler, a linker, or a wrapper compiler; run
  the result with `$(NEW_OCAMLRUN)`. Consumer-generated `.cmi`, `.cmo`, and
  executable files may then exist in that isolated directory, but no private
  Plan 9 library interface may appear. Re-hash staged `plan9.cma` and
  `plan9.cmi` after compilation and execution and require that both remain
  byte-for-byte identical to the just-built source artifacts;
- confirm the archive has no C payload;
- confirm every existing primitive still has one generated entry and one
  linked definition; and
- compare descriptor, process, and temporary-file postconditions with the
  accepted baseline.

No installation or new prefix is required in Phase 1.1. If the build system
cannot demonstrate the private-CMI installation boundary without performing
an install, stop and ask before selecting a prefix.

## Execution sequence and mandatory pause

### 1. Preflight and hand-written implementation

Record Git state, the accepted Phase 0 predecessor, current ML type ownership,
primitive declarations, archive order, dependency rules, and test linkage.
Implement only the private regroup described here, including Makefile changes,
but leave the tracked `.depend` byte-for-byte at the documentation checkpoint
and mark its regeneration pending. Do not hand-edit it.

### 2. Source review before VM work

Run safe host-side checks and inspect the complete hand-written diff from the
exact user-approved Phase 1 documentation checkpoint. Report the intended
direct dependency DAG, moved type and primitive ownership, public-interface
comparison, packaging boundary, and the single pending generated `.depend`.
Stop before VM access. Do not describe this as the final implementation diff.

### 3. Explicit VM confirmation

Before any VM operation, ask the user to confirm the exact writable instance,
loopback address, action, WHPX profile, retained native source tree, and the
fact that the dependency-generation gate requires an already configured tree
with a working `$(OCAMLRUN)` and boot compiler. Use the repository VM and
native-build skills. This step authorizes and records the target; it does not
transfer source or start native work.

### 4. Native dependency generation and authoritative return

Record the guest release, `cputype`, `objtype`, configured host identity,
toolchain, GNU Make path, and retained native source destination. Before
transfer, verify that this exact retained tree is already configured and has
the working `$(OCAMLRUN)` and boot compiler required by the dependency target.
If any prerequisite is absent, stop and ask rather than configuring,
bootstrapping, or selecting another tree implicitly.

Transfer the reviewed source without `.git` through `/mnt/term`, copy it onto
the confirmed native storage destination, verify the intended source manifest,
and never build on `/mnt/term`. This is the one source-transfer action in the
initial execution sequence. Do not build `otherlibs/plan9`, relink the runtime
or `plan9.cma`, or run any test. Run only the existing `otherlibs/plan9`
dependency target with the recorded GNU Make.

Capture the dependency command, exit status, and diagnostics. Because the
current recipe redirects with `> .depend` and can leave a truncated or partial
file when its compiler fails, accept output only after a successful exit.
Require a nonempty generated file with `.cmi`, `.cmo`, and `.cmx` targets for
each of `plan9_types`, `plan9_primitive`, `plan9_process`, and `plan9`, and
verify its edges against the exact DAG above.

After that success gate, record the generated native `.depend` path, contents,
size, and content hash. Return only that validated text artifact through
`/mnt/term` to a validated exchange path, then update only the authoritative
Windows `otherlibs/plan9/.depend`. Verify its contents and hash match the
native copy exactly. If generation fails or the inventory is incomplete, do
not return or apply the output and leave the authoritative Windows file
unchanged. Treat any truncated or partial guest file as rejected evidence; a
fresh successful dependency generation must replace it before return. Do not
return build artifacts, generated binaries, `.git`, or any other guest path.

### 5. Final host source review

Inspect the complete implementation diff from the exact documentation
checkpoint, now including the natively generated `.depend`. Verify that its
rules express the direct interface dependencies above, re-run all safe
host-side checks, and confirm the native source tree already contains the same
generated file and reviewed source manifest. Stop if the files differ or if
any unexpected path changed. No native build or test begins before this review
passes.

### 6. Native qualification

Build and run the ordinary `otherlibs/plan9` `test` target with the exact
execution matrix above, then perform the module, isolated-consumer,
CMI-installation, archive, primitive, and cleanup audits.
Do not interpret "ordinary test target" as authorization for the separate
`test-native-interruption` target.

### Authoritative retry rule for steps 4-6

Native dependency generation, compilation, tests, and audits are evidence
producers, not editing lanes. Apart from generated build products and the
native `.depend` produced by its target, do not edit implementation or test
source in the guest. If any native step exposes a defect:

1. preserve the exact command, output, guest path, and relevant artifact or
   postcondition evidence;
2. make every corrective source edit only in the authoritative Windows
   checkout, without modifying the immutable predecessor tests;
3. treat the prior reviewed source manifest, guest source copy, and final host
   review as invalid;
4. repeat the hand-written host review and transfer the corrected reviewed
   source to the same user-confirmed native destination; and
5. for every `.ml` or `.mli` change, source rename or addition, module-list
   change, or dependency-relevant Makefile change, repeat native `.depend`
   generation, authoritative return, byte-for-byte comparison, and final host
   review before resuming qualification.

Even when a permitted correction cannot affect `.depend`, re-run the complete
host diff, update and verify both source manifests, and retransfer the exact
authoritative source before resuming. Never patch the guest to make a native
failure disappear, never hand-edit generated dependency output, and never
continue from stale review evidence. If the confirmed retained destination
cannot be reused safely, return to the explicit VM-confirmation gate before
selecting or touching another native tree.

### 7. Report and stop

Do not begin the `Plan9_fd` ownership cell, publish `Plan9.Fd`, change runtime
primitives, migrate process code, or begin capture. Commit and push only if
the user explicitly asks in the executing task.

## Completion report

In addition to the roadmap's shared report, include:

- exact before/after ML dependency graphs;
- exact shared types and native ABI types moved, retained, or aliased;
- every primitive declaration location after the regroup;
- proof that `plan9.mli` and all public behavior are unchanged;
- generated dependency and archive order;
- exact generated `.cmx` prerequisites and confirmation that they preserve
  dependency metadata without constituting Plan 9 native-code qualification;
- removal of redundant hand-written ML module prerequisite rules and proof
  that the validated generated `.depend` contains the complete rule inventory;
- native `.depend` generation provenance, returned-file identity, and final
  host-review result;
- every native failure/retry cycle, its authoritative Windows correction, and
  the repeated manifest, dependency, and review gates it required;
- unchanged production primitive-import set and exact test runtime/link lanes;
- proof that every predecessor test source remained byte-for-byte unchanged,
  plus the purpose and additive status of any new regroup-only test;
- private-CMI non-installation, isolated staged-consumer compile/run, and
  ML-only `plan9.cma` evidence, including byte-identical just-built and staged
  `plan9.cma`/`plan9.cmi` paths, sizes, and hashes;
- complete existing test and primitive-uniqueness results;
- confirmation that no runtime source changed; and
- exactly one final recommendation:
  - **Phase 1.1 accepted; ready to checkpoint and review Phase 1.2**;
  - **implementation ready but native qualification still required**; or
  - **Phase 1.1 blocked or rejected**, with the exact reason.

## Strict exclusions

This handoff does not authorize production descriptor capability, pipe, close,
read, or write bindings; `Plan9_fd`; `Plan9.Fd`; public documentation changes;
new tests of descriptor ownership; native runtime changes;
`Plan9.In_channel`; process migration; capture; timing-sensitive interruption
injection; installation; VM snapshots; merge; release publication; or Caml9
changes.
