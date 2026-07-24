# P2-002: Initial native process-primitives design

Status: proposed

Origin: OCaml Plan 9 port task

Materialized by: OCaml Plan 9 port task

Responds to: `plan9-phase-2-process-primitives-design-001`

Date: 2026-07-24

Repository boundary: original read-only gate on OCaml branch
`plan9-4.14.3-000`, HEAD
`924786f313afbe7181596728b2f250110564d01c`, tree
`155e1c7dc643708547028355d145a725d7ab0e01`, and
`otherlibs/plan9` tree `4951e6b2defbeb0c12b368c67d6fa989a0e591c1`

Canonical impact: none; this is a retrospective initial proposal awaiting its
numbered review, not the corrected or accepted normative API

Requested next action: direct caml9 review in P2-003 under an exclusive
documentation lease

## Retrospective materialization notice

This document is a normalized materialization of the completed
`plan9-phase-2-process-primitives-design-001` report. It preserves the initial
proposal, including choices that the later review was expected to challenge.
It is not a verbatim transcript and does not import corrections from the later
design-correction gate. Those belong in P2-003 and P2-004.

The original gate was architectural and read-only. It changed no OCaml or
caml9 file, index, VM, guest, endpoint, native tree, compiler prefix, build,
installation, commit, or remote ref. This later materialization changes only
the exchange record and does not claim that P2-002 existed during the original
gate.

## Evidence and inputs

The initial report separated its inputs as follows.

### Source-backed facts

- The Plan 9 target selected the ML-only `plan9` otherlib through
  [configure.ac](../../../../../configure.ac), and
  [otherlibs/plan9/Makefile](../../../../../otherlibs/plan9/Makefile) contained
  only `plan9.cmo` in `plan9.cma`.
- The ordinary runtime generated its built-in primitive name and function
  tables from `runtime/primitives`; see
  [runtime/Makefile](../../../../../runtime/Makefile),
  [runtime/gen_primitives.sh](../../../../../runtime/gen_primitives.sh), and
  [runtime/dynlink.c](../../../../../runtime/dynlink.c).
- The bytecode compiler used the same primitive inventory while linking; see
  [bytecomp/symtable.ml](../../../../../bytecomp/symtable.ml) and
  [bytecomp/bytelink.ml](../../../../../bytecomp/bytelink.ml).
- The runtime resolved the executable's `PRIM` section against built-ins and
  reported an unknown C primitive rather than substituting another operation;
  see [runtime/startup_byt.c](../../../../../runtime/startup_byt.c).
- Blocking-section entry and exit were available in the bytecode runtime; see
  [runtime/signals.c](../../../../../runtime/signals.c). The existing Unix
  library already used that boundary around blocking waits, but normalized
  results into POSIX exit and signal constructors; see
  [otherlibs/unix/wait.c](../../../../../otherlibs/unix/wait.c).
- The existing [Plan9 interface](../../../../../otherlibs/plan9/plan9.mli)
  supplied the Phase 1 error model and direct live `/env` API but no process
  primitive.
- Caml9's CPU-017 source and design called for synchronous setup commands,
  background and long-lived services, continuation after successful launch,
  direct environment delivery, output redirection, and later observation of
  child failure. Those were source observations, not an execution of caml9.

### Evidence-backed observations

The accepted Phase 1 record established that:

- `plan9.cma` was ML-only and installed beneath `+plan9`;
- an ordinary consumer linked with
  `ocamlc -I +plan9 plan9.cma program.ml -o program`;
- consumer linking invoked no C compiler, linker, archiver, `ocamlmklib`, or
  `flexlink`;
- `Plan9.Env` read and mutated the live `/env` namespace;
- native rc and APE launch cross-checks passed at the Phase 1 boundary; and
- the experimental prefix
  `/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001` remained isolated from the
  known-working compiler.

These were recorded results from the accepted Phase 1 evidence, not probes
performed during the process-design gate. The machine-local record was
[current-state.md](../../../../../.agents/skills/ocaml-plan9-local/references/current-state.md).

### Explicit inferences

The initial design inferred, pending a native ABI probe, that:

- native Plan 9 process calls could be linked into the existing APE-linked
  bytecode runtime without making the complete runtime APE-free;
- reopening a pipe descriptor through `#d/<fd>` with `OCEXEC` could provide a
  race-free close-on-success exec handshake;
- a combined C rfork/exec primitive could avoid all OCaml execution in the
  child;
- the process's live environment group would be inherited when spawn omitted
  `RFENVG`, while requesting `RFENVG` would provide a copied snapshot; and
- a wait-any coordinator could implement wait-for-handle by retaining
  completions for other PIDs.

These were design conclusions from source contracts. They were not yet
confirmed against the installed guest ABI.

## Packaging and runtime placement

The proposal kept the accepted packaging shape:

```text
standard Plan 9 ocamlrun
  conditionally contains caml_plan9_* primitives

ML-only, Plan 9-only plan9.cma
  declares and wraps those built-ins

ordinary program
  ocamlc -I +plan9 plan9.cma program.ml -o program
```

The native implementations belonged in a Plan 9-specific runtime source such
as `runtime/plan9.c`, not in an otherlib C archive. The runtime build and
primitive-generation rules would include that source only when the configured
target was Plan 9. The generated primitive inventory used by `ocamlrun` and
the bytecode compiler had to contain each `caml_plan9_*` name exactly once.
Non-Plan-9 builds had to compile and advertise none of them.

This placement was preferred over:

1. an otherlib containing C objects, which would force consumer custom
   linking or dynamic-stub support;
2. a dedicated runtime selected through `-use-runtime`, which would make
   ordinary users select and distribute a second executable; and
3. per-consumer `-custom`, which was already a separate broken capability on
   the port and would require a C toolchain.

The general custom-runtime repair remained outside Phase 2.

## Proposed public interface

The following was the initial public shape. Names were provisional, but the
semantic divisions were part of the proposal.

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

exception Error of error

type pid = private int

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  status : string;
}

val wait_succeeded : wait_msg -> bool

type environment_policy =
  | Share_environment
  | Copy_environment

type namespace_policy =
  | Share_namespace
  | Copy_namespace

type note_policy =
  | Share_note_group
  | New_note_group

type rendezvous_policy =
  | Share_rendezvous_group
  | New_rendezvous_group

type mount_policy =
  | Allow_mounts
  | Forbid_mounts

type isolation = {
  environment : environment_policy;
  namespace : namespace_policy;
  notes : note_policy;
  rendezvous : rendezvous_policy;
  mounts : mount_policy;
}

val default_isolation : isolation

type stdout =
  | Inherit_stdout
  | Truncate_stdout of string

module Raw : sig
  type rfork_flag =
    | Copy_file_descriptors
    | Copy_environment
    | Copy_namespace
    | New_note_group
    | New_rendezvous_group
    | Forbid_mounts

  val rfork : rfork_flag list -> (unit, error) result

  val exec :
    program:string ->
    argv:string array ->
    ('a, error) result

  val wait_any : unit -> (wait_msg, error) result
end

module Process : sig
  type t

  val spawn :
    ?isolation:isolation ->
    ?stdout:stdout ->
    program:string ->
    argv:string array ->
    (t, error) result

  val pid : t -> pid

  val wait : t -> (wait_msg, error) result

  val wait_any : unit -> (wait_msg, error) result

  val run :
    ?isolation:isolation ->
    ?stdout:stdout ->
    program:string ->
    argv:string array ->
    (wait_msg, error) result
end
```

`Raw.exec` accepted the native vector literally. Success never returned because
the current process image had been replaced. Failure returned the exact native
error.

The initial high-level convention also required a nonempty literal `argv` and
required the caller to supply `argv[0]`. Neither layer performed PATH search,
shell invocation, quoting, globbing, redirection parsing, variable expansion,
or argument rewriting.

`wait_succeeded wait_msg` was true exactly when `wait_msg.status = ""`.
The field was intended to preserve the complete native wait text, not a Unix
exit code or signal variant.

### Default spawn policy

The proposed default native mask was:

```text
RFPROC | RFFDG | RFREND
```

It meant:

- create a waitable process;
- copy the file-descriptor group so child descriptor changes could not alter
  the parent's group;
- share the current environment group so live `Plan9.Env` state remained
  visible;
- share the current namespace;
- share the note group;
- create a new rendezvous group; and
- permit mounts.

The initial output policy was deliberately small. A child either inherited
stdout or used a truncate file opened by the parent and duplicated to
descriptor 1 in the native child path. It did not introduce arbitrary file
descriptor passing, pipes, stderr policy, or shell redirection syntax.

## Raw rfork boundary

The initial `Raw.rfork` was not a generic process-creation interface. Its
constructors mapped only to current-process group operations:

| OCaml constructor | Native flag | Initial purpose |
| --- | --- | --- |
| `Copy_file_descriptors` | `RFFDG` | copy the current descriptor group |
| `Copy_environment` | `RFENVG` | copy the current environment group |
| `Copy_namespace` | `RFNAMEG` | copy the current namespace group |
| `New_note_group` | `RFNOTEG` | enter a new note group |
| `New_rendezvous_group` | `RFREND` | enter a new rendezvous group |
| `Forbid_mounts` | `RFNOMNT` | irreversibly disallow later mounts |

The primitive returned once to the same OCaml process. `RFPROC` was not
representable through this API, so it could not return into OCaml in a child.
The C entry point still had to decode and validate every constructor and
combination because an OCaml program could redeclare the primitive by its
symbol name.

The following were unrepresentable and rejected at the C boundary:

- `RFPROC`;
- `RFMEM`;
- `RFNOWAIT`;
- integer masks and unknown bits;
- the clean descriptor, environment, and namespace group flags; and
- contradictory or unsafe combinations.

Any future child-returning rfork facility was deferred to an explicitly
unstable and separately audited `Raw.Unsafe` surface.

## Combined spawn primitive

High-level spawning used one primitive, provisionally
`caml_plan9_spawn`, with this flow:

1. Validate the OCaml value shapes, policy values, program, path, argument
   array, argument strings, output path, sizes, and overflow bounds.
2. Reject embedded NUL in every native C string and reject an empty argument
   vector.
3. Copy all program, argument, policy, and error-protocol data into C-owned
   storage before rfork.
4. If truncate output was requested, open it in the parent before a child
   existed.
5. Create a private pipe and arrange for the child writer to be close-on-exec,
   initially proposed by reopening `#d/<fd>` with `OCEXEC`.
6. Call native rfork with `RFPROC`, mandatory `RFFDG`, default `RFREND`, and
   the selected safe isolation flags.
7. In the child, close unused descriptors, duplicate the prepared stdout if
   requested, and invoke native exec with the copied literal vector.
8. If exec failed, capture the native error immediately, write a bounded
   error payload to the private pipe, and terminate through `_exits`.
9. Never allocate through OCaml, invoke an OCaml callback or finalizer, use an
   OCaml channel, reacquire the OCaml runtime, or return into OCaml in the
   child.
10. In the parent, distinguish exec success by EOF from a bounded exec-error
    payload, close every private resource, re-enter the runtime, and only then
    allocate an OCaml result.

The proposed private result distinguished:

```text
failed before a child existed
child PID with exec success proved
child PID with a known exec failure
```

A malformed or interrupted handshake was a protocol failure, but the initial
report did not freeze a separate public state for a PID whose launch outcome
was indeterminate.

### Why one primitive

A design in which raw rfork returned `0` to ordinary OCaml in the child was
rejected. Even without `RFMEM`, that child would resume with copied runtime
state, heap metadata, channels, finalizer queues, pending actions, debugger
state, and locks. Performing allocations, collections, callbacks, exception
construction, or channel I/O in that state before exec was not justified.

Keeping the child path entirely in C made its allowed operations auditable:
fixed or preallocated buffers, descriptor operations, exec, an error write,
and `_exits`.

## Exec-failure distinction

The private pipe distinguished two cases that a wait record alone could not:

- EOF on the close-on-exec writer proved that exec replaced the child image;
  a later nonempty wait status was therefore a failure of the executed
  program.
- A payload before EOF meant exec itself failed; the payload preserved the
  native error captured before `_exits`.

The initial ML policy proposed that a known exec-failure PID be reaped through
the common wait coordinator. Any unrelated completions encountered first
would be retained in the wait cache. Once the failed PID was reaped,
`Process.spawn` could return an ordinary `Error`.

The initial report required that no failed child become an unreaped zombie,
but it did not fully specify the public result if interruption or another
consumer prevented confirmed reaping. The atomic ownership handoff between
the C primitive and ML coordinator also remained a review point.

## Native wait model

The native boundary used wait-any semantics. It returned:

```ocaml
{
  pid;
  user_time_ms;
  system_time_ms;
  elapsed_time_ms;
  status;
}
```

The proposal preserved the native PID, three timing fields, and complete
native status string. Empty status meant success. Nonempty text was not
parsed into Unix exit codes or signal constructors.

The primitive had to:

- capture the native error string immediately on failure;
- distinguish the exact no-living-children error from interruption and other
  failures;
- avoid converting every null or failed native wait into `No_children`;
- bound and validate the native record;
- classify malformed or truncated data as `Protocol_error`;
- not automatically retry interruption; and
- release the OCaml runtime around a genuinely blocking native await, then
  reacquire it before allocating the result.

### Initial wait coordinator

`Process.wait handle` repeatedly consumed native wait-any records until it
found the requested PID. Complete records for other PIDs were retained in a
process-global PID-keyed cache. Each resolved handle memoized its completion
so repeated waits did not consume another native record.

`Process.wait_any` first returned a retained completion, otherwise called the
native wait primitive. `Raw.wait_any` exposed the native operation to advanced
callers.

The initial managed guarantee covered children created and waited through
`Plan9.Process`. Concurrent mixing with `Raw.wait_any`, `Unix.wait`,
`Sys.command`, or other code consuming the process-wide wait queue was
unsupported because any one of them could steal another's completion.

The initial report did not finish the lifetime rule for cached unknown PIDs or
PID reuse. That coordinator model was explicitly awaiting review.

## Safety analysis

### `RFPROC` and return into OCaml

`RFPROC` appeared only inside the combined spawn primitive. The parent
returned to OCaml after the handshake; the child either execed or called
`_exits`. Public `Raw.rfork` could not request it.

### `RFMEM`

`RFMEM` was permanently rejected, including when a caller bypassed the ML
constructors and called the primitive symbol directly.

Two independently scheduled bytecode interpreters sharing the same OCaml heap
would race on allocation pointers, GC phases, remembered sets, global roots,
channels, callbacks, finalizers, pending actions, and runtime locks. The
absence of systhreads did not make that safe. No stable or unsafe public API
was proposed for it.

### Allocation, GC, and runtime state

All fallible allocation and conversion occurred in the parent before rfork.
The C child performed no OCaml allocation or heap access. It did not enter or
leave an OCaml blocking section, run pending actions, raise an OCaml exception,
or call cleanup hooks.

The parent could enter a blocking section while waiting for the exec
handshake or a child completion only after every required OCaml input had been
copied or rooted. It reacquired the runtime before constructing results.

### Error handling

Every primitive captured native error text before another operation could
overwrite it. `Invalid_argument`, `No_children`, `Interrupted`, and
`Protocol_error` were classifications layered over the exact `message`;
unrecognized native errors remained `Other`.

Every failure path had to close pipe ends and parent-opened output
descriptors. The child used `_exits` rather than higher-level exit processing
that might touch copied runtime or library state.

### Descriptors

Mandatory `RFFDG` isolated descriptor-table mutations. The child closed only
its private copies. The parent opened truncate output before rfork, allowing
an open failure to return without creating a child.

Descriptor-number collisions, especially when 0, 1, or 2 were initially
closed, required native probe coverage before the duplication algorithm was
frozen.

### Environment

The default shared environment group made the caller's current live `/env`
state visible to a child. `Copy_environment` requested `RFENVG`, producing a
child snapshot at rfork. Neither path consulted APE `environ` or replayed an
OCaml environment map.

The initial CPU-017 recommendation was to finalize and write required values,
including `NPROC`, `sysname`, `auth`, and `serviced`, through `Plan9.Env`
before spawning the dependent services. Default spawn would share that live
environment group; copied-environment spawn would inherit its snapshot.

Per-child environment override maps were rejected because they would add
child-side mutation, serialization, and command-specific replay to a design
whose purpose was native inheritance.

### Namespace, notes, rendezvous, and mounts

The initial default shared the namespace and note group, matching a continuing
boot process that deliberately prepared its namespace before launching
services. Optional copying created a private namespace or note group when
requested. A new rendezvous group was the default. `Forbid_mounts` was
presented as an irreversible low-level or isolation policy for callers that
deliberately wanted it.

Clean namespace, environment, and descriptor groups were excluded because
they could invalidate paths, `/env`, standard descriptors, and runtime
assumptions.

## Alternatives considered

### Combined spawn versus child-returning rfork

**Alternative A:** expose native rfork and let OCaml code branch on parent or
child before calling `Raw.exec`.

**Alternative B:** copy inputs in the parent and perform rfork, child setup,
exec, error reporting, and `_exits` inside one primitive.

The proposal selected B. It made the child path small and made `RFMEM`,
allocation, callbacks, and returns into OCaml structurally impossible.

### Exec handshake versus wait-status inference

**Alternative A:** treat a child's first nonempty wait status as an exec
failure.

**Alternative B:** use a private close-on-exec pipe and report exec failure
before `_exits`.

The proposal selected B. A program may exec successfully and then immediately
exit with an error; wait text alone cannot distinguish that from exec failure.

### Wait-any only versus managed handle waits

**Alternative A:** expose only native wait-any and require every caller to
route records.

**Alternative B:** expose wait-any but add managed process handles and retain
out-of-order records so callers can wait for one child.

The proposal selected B for ordinary programs. CPU-017 needed to retain
long-lived service identities while synchronously waiting for other setup
commands.

### Shared versus copied environment

**Alternative A:** always share the current live environment group.

**Alternative B:** always request `RFENVG` and snapshot it.

**Alternative C:** default to sharing and expose an explicit copy policy.

The proposal selected C. Sharing preserved immediate `Plan9.Env` inheritance;
copying remained available for deliberate child isolation.

### Built-in versus separately linked primitives

**Alternative A:** otherlib C stubs and per-consumer custom linking.

**Alternative B:** a dedicated Plan 9 runtime selected with `-use-runtime`.

**Alternative C:** built-ins in the standard Plan 9 runtime with an ML-only
otherlib.

The proposal selected C because it preserved the ordinary installed-library
experience and required no consumer C toolchain.

## CPU-017 use-case matrix

| CPU-017 need | Initial mapping |
| --- | --- |
| Synchronous command | `Process.run` performs direct spawn and waits for its handle |
| Background service | `Process.spawn` proves exec success, returns a handle, and lets boot continue |
| Long-lived process | Retain the handle; do not infer success from continued execution |
| Launch failure | Exec-error pipe distinguishes native exec failure before `spawn` returns |
| Later process failure | `Process.wait` returns the exact nonempty native status and timings |
| Continue without waiting | Successful handshake is enough to continue after `spawn` |
| Output file | `Truncate_stdout path` opens in the parent and duplicates stdout in the child |
| `NPROC` and `sysname` | Write through `Plan9.Env` before spawn; default shared `/env` is inherited |
| `auth` and `serviced` | Initial proposal likewise wrote them before dependent spawns |
| Literal arguments | Pass the complete vector, including `argv[0]`, with no shell |
| Service-directory branch | Launch the selected native service program directly and retain its handle |

This mapping was an architectural fit inferred from caml9 source and design.
It was not a CPU-017 integration test and did not authorize caml9 changes.

## Focused test plan

### Packaging

- Build the exact candidate on native Plan 9 storage.
- Verify `ocamlrun -p` lists every `caml_plan9_*` primitive exactly once.
- Verify non-Plan-9 configurations do not compile or advertise them.
- Inspect installed `plan9.cma` with `ocamlobjinfo`: no C objects, DLLs,
  custom-link request, or external stub archive.
- Build and run
  `ocamlc -I +plan9 plan9.cma program.ml -o program` with fail-closed C
  compiler, linker, archiver, `ocamlmklib`, and `flexlink` sentinels.
- Run bytecode requiring the new primitives under an older runtime and require
  a clear unknown-primitive failure.

### Arguments and exec

- Direct exec success with a complete literal vector.
- Spaces, quotes, shell metacharacters, redirection characters, wildcard
  characters, newlines, empty strings, and many arguments.
- Empty vector rejection.
- Embedded NUL in program, argument, and output path rejection.
- Missing program, non-executable file, directory, and permission failure.
- A program that execs successfully and immediately exits with nonempty
  status, proving distinction from exec failure.
- Repeated exec failures under minor and major GC pressure.

### Wait and child lifetime

- Empty and nonempty native status, exact PID, and all timing fields.
- No-child and interrupted waits with exact native messages.
- Multiple children completing out of order.
- Wait for one child while retaining other completions.
- Repeated wait on a completed process handle.
- Background and long-lived children, later resolution, and clean reaping.
- Unknown child completion and interaction with low-level wait.
- Sequential use and explicitly unsupported overlap with APE/Unix waiting.

### Groups and descriptors

- Default `RFPROC | RFFDG | RFREND` behavior.
- Shared and copied environment groups with fresh `Plan9.Env` rereads.
- Shared and copied namespaces.
- Shared and new note groups.
- Shared and new rendezvous groups.
- Every public Raw flag and invalid combination.
- Forged primitive calls proving unconditional `RFMEM`, `RFPROC`,
  `RFNOWAIT`, unknown-bit, and clean-group rejection.
- Parent-opened truncate output and inherited stdout.
- Closed descriptors 0, 1, or 2 and private-pipe descriptor collisions.
- Cleanup after every pre-rfork, post-rfork, exec, pipe, dup, and wait failure.

### Independence from caml9

The process library had to pass all primitive, API, wait, inheritance,
interruption, leak, and packaging tests without invoking a caml9 executable or
using caml9 as its validation harness.

## Initial staged implementation plan

### Gate A: native ABI and behavior probe

The initial next gate was a separately authorized, source-free native probe
covering:

- installed native header names, flag values, structures, function
  signatures, and link symbols;
- whether the APE-linked OCaml runtime could call native rfork, exec, await,
  `_exits`, error-string, pipe, dup, and descriptor operations;
- `#d/<fd>` reopening with `OCEXEC`;
- exact wait formatting, timing widths, truncation bounds, no-child text, and
  interruption behavior;
- the fixed-size exec-error protocol and descriptor collisions;
- environment, namespace, descriptor, note, rendezvous, and mount-group
  behavior; and
- representative installed CPU-017 service behavior, including process
  lifetime, daemonization, output, environment, namespace, and cleanup facts
  needed before integration.

This probe was proposed, not authorized or run by the design gate.

### Gate B: runtime primitive implementation

- Add the conditionally compiled Plan 9 runtime source.
- Integrate its primitive names with the generated runtime/compiler inventory.
- Implement defensive decoders, raw current-process rfork, exact exec,
  combined spawn, native wait, error capture, and blocking boundaries.
- Add C-level negative tests, including forged values and `RFMEM`.

### Gate C: ML interface and coordinator

- Extend `plan9.mli` and `plan9.ml` with the proposed Raw and Process layers.
- Keep `plan9.cma` ML-only.
- Implement process handles, the wait-any coordinator, completion memoization,
  out-of-order retention, and `run`.
- Document the literal argv, environment, wait-queue, lifetime, and mixing
  rules.

### Gate D: exact-source native qualification

- Freeze an exact reviewed Windows index.
- Transfer only its deterministic archive.
- Build in a fresh native Plan 9 tree.
- Install under a new prefix such as
  `/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002`.
- Run the complete focused and installed-consumer suite.
- Preserve the known-working compiler and the accepted Phase 1 prefix.

### Gate E: caml9 integration

Only after independent qualification:

- make caml9 an integration consumer of the installed Plan9 library;
- replace selected command and environment boundaries incrementally;
- preserve branch-specific CPU-017 behavior;
- test service startup, continuation, failure, and cleanup; and
- keep formal boot promotion under caml9's own gates and stateful operator.

## Guest-dependent unresolved facts

The initial report reserved these facts for a narrow, separately authorized
native probe:

- the exact installed header declarations and numeric rfork flags;
- whether native symbols linked cleanly into the existing APE-linked runtime;
- exact `Waitmsg` field widths and ownership rules;
- exact await text, timing units, truncation behavior, and no-child error;
- exact interruption behavior and whether partial records could be observed;
- the correct `#d/<fd>` plus `OCEXEC` sequence;
- fixed-size error-payload bounds and short-read/write handling;
- descriptor duplication behavior when 0, 1, or 2 were closed;
- current-process and child group behavior for every proposed flag;
- executable path and empty-vector behavior at the raw native ABI;
- installed service daemonization, descendant, environment, namespace,
  descriptor, and cleanup behavior; and
- the precise managed result required if a child existed but exec-failure
  reaping or the private handshake could not be confirmed.

No unresolved item permitted a generic integer-mask rfork, `RFMEM`, a child
return into OCaml, APE process emulation, environment replay, or consumer
custom linking.

## Recommended initial Phase 2 boundary

The initial recommendation was to implement only:

- built-in Plan 9 runtime primitives;
- the constrained current-process Raw operations;
- exact Raw exec and wait-any;
- one combined native spawn primitive;
- the managed Process handle, wait, wait-any, and run layers;
- inherited or truncate-file stdout;
- focused native tests; and
- an isolated exact-source installation.

It excluded:

- changes to `Sys`, `Unix`, `Sys.command`, or APE semantics;
- `RFMEM` and child-returning rfork;
- PATH search, shell parsing, command wrappers, or environment replay;
- arbitrary descriptor plumbing;
- general custom-runtime repair;
- a fully APE-free runtime;
- caml9 implementation before independent qualification; and
- any VM, guest, build, installation, or checkpoint action without a separate
  named authorization.

## Requested next action

The caml9 review task should review this initial proposal directly in
`P2-003-caml9-process-design-review.md` under an exclusive documentation
lease. It should preserve P2-002 as the historical proposal, identify accepted
points and required corrections in P2-003, update only the matching README
index row, and perform no canonical, implementation, Git-publication, or
operational action unless separately authorized.
