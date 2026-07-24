# Verification and recovery

The process verification contract promotes the accepted
[P2 process-primitives design package](exploration/process-primitives/README.md).
Evidence must establish the claim assigned to its lane without silently
authorizing implementation, service operation, or caml9 integration.

## Validation lanes

Use the smallest lane that proves the current claim.

### Host-only review

Use for source archaeology, API review, documentation, generated-file
consistency analysis, implementation review, and offline tests. It authorizes
no guest, Drawterm, VM, transfer, build, install, service, or checkpoint
action.

Source contracts and repository review settle architectural requirements such
as:

- the available rfork flags and structurally forbidden combinations;
- process-wide native await behavior;
- native `Waitmsg` field meanings;
- the required `OCEXEC`, `#d`, pipe, and `_exits` mechanisms;
- built-in primitive registration;
- the native pending-child registry and adoption protocol;
- unique process identities and active-PID-map lifetime;
- the handle state machine and result types;
- exclusive synchronous coordinator ownership;
- foreign-FIFO bounds and retry behavior; and
- the absence of public raw wait, generic rfork masks, `RFMEM`, and
  `RFNOMNT`.

Installed behavior does not choose those implementation invariants.

### Compiler-lab development

Use one mutable, isolated P9QEMU instance for fast changed-file transfer,
native builds, versioned-prefix installs, and focused runtime tests. The lab
may accumulate state and may remain running when recorded accurately.

Developmental success is not release acceptance and does not make the mutable
disk a recovery checkpoint.

### Exact-source milestone

Build a fresh exact-index archive in a fresh native tree. Install into a new
versioned prefix and run both source-tree and installed-prefix tests. Preserve
the prior compiler and recovery source.

### Release or recovery promotion

Use only when explicitly selected. Start from a clean writable instance
derived without booting a protected checkpoint, use the exact-source build,
perform comprehensive installed-compiler and runtime checks, shut down
cleanly, verify host and disk integrity, and create a new checkpoint only in a
separately authorized phase.

## Prerequisite to stateful Phase 2 work

Before any Phase 2 VM, endpoint, transfer, guest build, installation, ABI
probe, or service probe, complete a separately authorized record-only
cross-repository reconciliation:

1. revalidate live OCaml Git and the assigned halted compiler-lab boundary;
2. preserve the completed Phase 1 history;
3. under an explicit documentation handoff, correct any dated caml9 record
   that still assigns or describes the OCaml lab incorrectly;
4. name the sole stateful operator and the exact next gate consistently; and
5. keep the caml9 VM, guest, processes, listeners, disks, and checkpoints
   untouched.

Reconciliation changes records only. It does not itself boot a VM, inspect
the caml9 operational lane, transfer source, or begin a probe.

## Packaging acceptance

The ML-only packaging gate must prove:

- the installed archive is beneath `$(ocamlc -where)/plan9`;
- `ocamlobjinfo $(ocamlc -where)/plan9/plan9.cma` reports no forced custom
  linking, C objects, or DLLs;
- `ocamlc -I +plan9 plan9.cma smoke.ml -o smoke` invokes no C compiler or
  linker;
- the link still succeeds with those tools absent from `PATH`;
- the executable runs under the matching standard runtime;
- ordinary bytecode not using `Plan9` remains unaffected; and
- non-Plan-9 builds neither compile the primitives nor select or install the
  library.

The built-in-primitive packaging gate must additionally prove:

- the standard Plan 9 `ocamlrun -p` lists each `caml_plan9_*` primitive
  exactly once;
- the bytecode compiler's known-primitive table agrees with the runtime;
- `plan9.cma` remains ML-only after adding the external declarations;
- an ordinary installed consumer still needs no `-custom`, `-use-runtime`, C
  compiler, linker, wrapper, or user-written C; and
- an older runtime fails clearly when bytecode requires a newer primitive.

## Environment acceptance

For `Plan9.Env`, test absence, empty list, empty scalar, scalar, multiple
values, embedded empty elements, overwrite/truncation, removal, invalid names,
and embedded-NUL rejection. Cross-check both directions with native `rc` and
prove that APE `getenv` state is neither consulted nor updated.

For `Plan9.Raw.copy_environment ()`, harmless installed-ABI evidence must
prove:

- it creates no child;
- values present before the split appear in the copied group;
- mutations after the split do not cross in either direction; and
- the operation performs only the current-process `RFENVG` copy.

The CPU-017 integration later proves the ordering: finalize globally intended
values, copy the environment group once, then write derived `auth` and
`serviced` values in the copied group.

## Harmless process ABI probe

`plan9-phase-2-process-primitives-abi-probe-001` is a separately authorized
guest gate. It may establish only installed native behavior needed before
implementation:

- header declarations, symbol linkability, and native flag values;
- exact-vector exec behavior in bounded purpose-built programs;
- wait-field widths, timing units, formatting, messages, and exact errors;
- `#d/<fd>` reopening with `OCEXEC`;
- feasibility and bounds for the versioned exec-error frame;
- complete and short pipe reads and writes;
- inherited stdout and parent-opened disposable truncate-file output;
- descriptor collisions involving 0, 1, and 2;
- bounded interruption observations;
- current-process `RFENVG` copy and isolation; and
- completion ordering among short-lived purpose-built children.

It must not start, inspect, or alter `auth/keyfs`, `aux/listen`, real service
directories, authentication state, listeners, caml9 executables, or
long-lived service processes. It does not modify an installed compiler prefix
or implement OCaml runtime or library source. Passing it is not service,
CPU-017, or boot acceptance.

## Process implementation acceptance

Source review and focused candidate tests must prove the canonical interface
in
[01-native-api-requirements.md](01-native-api-requirements.md).
Tests and implementation use the canonical `Launch_started`,
`Launch_incomplete`, `Wait_finished`, `Wait_unresolved`,
`Wait_terminal_failure`, `Wait_any_finished`, `Wait_any_unresolved`,
`Wait_any_terminal_failure`, `Run_finished`, `Run_incomplete`, and
`Run_terminal_failure` constructor names without a transitional alias layer.
The `Run_wait_queue_lost` reason preserves both the exact wait error and an
already known exec error.

### Primitive and child safety

Prove:

- every public and private primitive validates direct forged OCaml values,
  string and array shapes, embedded NUL, integer conversions, allocation
  bounds, and fixed policies;
- `RFMEM`, `RFNOWAIT`, `RFNOMNT`, generic masks, unknown flags, and a
  child-returning rfork remain unavailable and are rejected defensively;
- all program, argument, path, policy, and frame storage is C-owned before
  rfork;
- the child runs no OCaml code, allocator, callback, finalizer, channel, or
  runtime-return path before exec or `_exits`;
- descriptor moves remain correct for closed or colliding descriptors 0, 1,
  and 2;
- the spawn primitive never invokes await; and
- every failure path releases only resources it owns and leaks no descriptor,
  allocation, registry entry, or child.

### Launch ownership and handshake

Test:

- process-ID reservation and pending-record allocation fail before rfork on
  exhaustion, wraparound, collision, or allocation failure;
- positive parent PIDs are published allocation-free before handshake I/O,
  blocking-section entry, ML allocation, asynchronous exception delivery, or
  return to ML;
- `Process.unresolved` adoption is idempotent and identity-preserving;
- acknowledgment removes a native pending entry only after the handle and
  active PID map are established;
- clean EOF means exec success;
- exact exec error, short writes, partial reads, truncated header or payload,
  invalid tag or length, trailing data, and premature EOF have the specified
  distinct results;
- known exec failure is reaped only through the shared coordinator; and
- interruption, malformed handshake, GC pressure, and asynchronous exception
  paths always return or preserve the owned handle until reaping is proved.

An outer `spawn` or `run` error is acceptable only when the test proves that
no child from that call remains.

### Literal execution and resources

Test empty high-level `args` and literal arguments containing spaces, quotes,
shell metacharacters, redirection characters, newlines, and empty strings.
Prove that high-level calls synthesize `argv[0]` from `program`, while
`Raw.exec` preserves its exact nonempty vector. Test missing programs,
permission failures, invalid paths, arbitrary non-NUL argument bytes, and all
length bounds.

Prove the fixed `RFPROC | RFFDG | RFREND` child policy, copied descriptor
group, selected shared environment group, shared namespace and note group,
new rendezvous group, inherited stdout, truncate-file stdout, and absence of
shell, PATH, quoting, globbing, APE environment replay, or command wrappers.

### Wait coordinator and lifecycle

Use bounded purpose-built children so every test reaches a completion or exact
`No_children` without an unbounded hang. Prove:

- `Process.wait`, `Process.wait_any`, `Process.run`, and known exec-failure
  cleanup use one coordinator and one native await path;
- successful `spawn` starts no helper, thread, event loop, or background
  reaper;
- no native await occurs until a synchronous coordinator operation invokes
  it;
- completion order may differ from spawn order without misrouting;
- each handle has a never-reused process identity separate from PID;
- active PID mappings disappear atomically on terminal transition;
- terminal completion and loss are memoized on the handle;
- repeated wait returns the same terminal result;
- unknown completions are classified as foreign immediately and never attach
  to a later PID reuse;
- a full foreign FIFO causes `Foreign_backpressure` without another native
  await or target terminalization;
- an unknown record that fills the last FIFO slot is retained before
  backpressure is returned;
- `wait_any` returns queued foreign records before native await;
- `take_foreign_completions` drains in FIFO order and permits retry of the
  same active target;
- wait interruption is returned without automatic retry and retains the
  handle;
- ordinary native await error remains distinct from interruption;
- exact `No_children` atomically terminalizes both adopted and native-pending
  owners as memoized `Wait_queue_lost`;
- later adoption of a lost pending owner retains its original process ID and
  terminal result;
- invariant failure preserves unresolved ownership, fails the coordinator
  closed, and prevents further await;
- a malformed or unrepresentable native record is never assigned to an
  arbitrary handle and produces its distinct failed-closed state; and
- active PID collision never overwrites an earlier mapping.

Exercise `Process.run` through completion, nonempty native message,
interruption, backpressure and retry, known exec failure, queue loss,
invariant failure, and malformed-record failure. Every nonterminal launch,
wait, run, or wait-any result must carry the applicable exact handle or
complete adopted-owner set.

Tests may deliberately demonstrate observable mixed-wait loss, but must not
promise finite-time detection before native evidence exists. While any
managed or native-pending owner remains unresolved, tests must not use
`Sys.command`, `Unix.wait`, APE wait functions, or an independent native
waiter except inside a deliberately isolated negative test.

### Blocking-runtime behavior

Confirm that genuinely blocking parent-side native operations release and
reacquire the OCaml runtime correctly, preserve `errstr` before any clobbering
operation, and allocate OCaml results only after re-entry. The child remains
subject to the stricter no-OCaml rule.

## Stateful service-behavior evidence

A later `plan9-phase-2-service-behavior-probe-001` is warranted only for
remaining service facts. Its separate authorization must name:

- a disposable scratch lab and unique endpoint set;
- private namespace and environment boundaries;
- synthetic rather than production key and service data;
- permitted guest mutations;
- service process and descendant inventory;
- credential protection;
- cleanup and shutdown behavior;
- retained evidence; and
- failure recovery.

Only this lane may establish `auth/keyfs` or `aux/listen` launcher behavior,
daemonization, descendants, listener ownership, service-directory precedence,
configured versus ndb authentication, or long-lived cleanup. It must remain
separate from the harmless ABI probe.

## CPU-017 integration acceptance

Integrate caml9 only after independent OCaml implementation qualification.
CPU-017 must:

1. finalize globally visible environment values;
2. call `Plan9.Raw.copy_environment ()` once;
3. write derived `auth` and `serviced` in the copied group;
4. invoke each direct `auth/keyfs` or `aux/listen` launcher with
   `Plan9.Process.run`, or spawn followed by wait through the same
   coordinator;
5. resolve that direct launcher before the next boot command;
6. preserve its exact native completion and apply stock's
   continue-after-native-failure policy only to a real terminal message;
7. drain and retry foreign-FIFO backpressure on the same handle; and
8. enter any later `Sys.command` or other APE child/wait path only after no
   managed or native-pending owner remains unresolved.

The direct launcher is distinct from any service descendant it intentionally
leaves behind. Stateful evidence, not the harmless ABI probe, determines
descendant and cleanup behavior.

## VM and recovery invariants

- One stateful operator owns the OCaml worktree, native tree, compiler VM,
  selected loopback address, install prefixes, and current-state.
- Every writable VM has one QEMU process and one unique explicit loopback
  address.
- Never boot a protected checkpoint directly or copy a live writable image.
- Before launch, validate the halted instance, QCOW2, P9QEMU dry run, selected
  endpoints, and evidence path.
- Record the exact process chain and listener owner after launch.
- Halt with `fshalt`, wait for the exact QEMU PID, require listener closure,
  then run the halted-instance checks again.
- If shutdown fails, preserve evidence and request separate approval before
  terminating only the exact recorded PID. Never kill by process name.

The machine-local skill supplies the concrete P9QEMU, Drawterm, transfer, and
checkpoint commands.

## Failure behavior

Do not overwrite failed evidence with a corrected retry. Do not infer success
from a prompt, a zero Drawterm exit, a disappeared QEMU process, or one passing
unit test. Record exactly which boundary passed and which remained untested.

Preserve the known compiler prefix and recovery source. A failed experimental
prefix or mutable lab can be abandoned without altering those boundaries.
