# P2-003: Caml9 review of the initial process design

Status: proposed

Origin: caml9 CPU-017 review task

Materialized by: caml9 CPU-017 review task

Responds to: [P2-002](P2-002-ocaml-initial-process-design.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, published HEAD
`351d53555cbb1268271665840e4b778734c6aa17`, tree
`5b608847e1f549ed441c76352a8b7abc11cff60e`, with the index unchanged.
At lease acceptance the README was modified and P2-002 was untracked;
P2-002's SHA-256 was
`4e5498fc024fe66954e217c51d6ead6c58c798c0e82f619d4bdc4050716be4de`.

Canonical impact: none yet. This review asks the OCaml task to issue a
corrected exploration response before any conclusions are promoted into the
canonical Plan 9 port design.

Requested next action: the OCaml task should answer this review in P2-004,
accepting, refining, or rejecting each required correction with explicit
reasoning. No implementation or operational work is implied.

## Retrospective-review notice

This document materializes the caml9 review that followed the original Phase 2
proposal. It evaluates P2-002 as written. It does not rewrite that proposal in
light of later discussion and does not claim that the requested corrections
have already been adopted.

## Overall disposition

P2-002 has the right architectural center:

- Plan 9 process support belongs in the normal Plan 9 `ocamlrun`, not in an
  application-specific custom runtime;
- `plan9.cma` should remain an ordinary ML-only library from the consumer's
  perspective;
- the child-side `rfork` and `exec` transition must be implemented below OCaml
  and must never return into the OCaml runtime;
- the safe public API must make `RFMEM` unrepresentable;
- spawn-time exec failure needs a close-on-exec parent/child handshake;
- the native wait record must be preserved instead of collapsed prematurely
  into Unix exit-status conventions; and
- Phase 2 must qualify independently before caml9 consumes it.

Those decisions should remain. The proposal is not yet ready for canonical
adoption or implementation, however. Its environment policy conflicts with the
CPU-017 compatibility boundary, and its wait and exec-failure models leave
process ownership ambiguous in cases that are normal consequences of Plan 9's
process-wide wait queue. The public raw surface is also broader than the
demonstrated need.

The corrected design should resolve the findings below before implementation.

## Accepted foundation

### Built-in runtime primitives

The primitive implementation should be linked into the standard Plan 9 runtime
and registered in the ordinary primitive table. A user should be able to write
and link:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

without `-custom`, application C sources, or a consumer-side C toolchain. This
is the same packaging contract established by Phase 1. It provides native
Plan 9 semantics at the process boundary without claiming that the whole OCaml
runtime is free of APE.

### Non-returning child transition

The combined low-level spawn primitive is the correct safety boundary. After
`rfork(RFPROC | ...)` succeeds, the child must execute only bounded
async-signal-safe native code needed to arrange descriptors, report a
pre-exec error, and call `exec`. It must terminate natively if `exec` fails.
It must not allocate OCaml values, raise an OCaml exception, run finalizers, or
return into duplicated OCaml runtime state.

Consequently, a general public `Raw.rfork` operation that can create a child
which resumes OCaml execution is out of scope. A current-process operation that
changes only the caller's environment group is a different and safe case; that
case is required below.

### RFMEM prohibition

`RFMEM` must remain impossible through the safe API and must also be rejected
defensively by the primitive. A documentation warning alone is insufficient.
The proposed library does not have a runtime model that can safely share the
OCaml data segment between independently executing Plan 9 processes.

### Default process isolation

`RFPROC | RFFDG | RFREND`, while sharing namespace, note group, and the
caller's current environment group, is the right CPU-017 process-creation
default:

- `RFPROC` creates the child;
- `RFFDG` gives it a copied descriptor group;
- omitting `RFNAMEG` shares the namespace;
- omitting `RFNOTEG` preserves the note group expected by the boot process;
- `RFREND` prevents accidental rendezvous collision with the parent; and
- omitting both `RFENVG` and `RFCENVG` makes the child inherit the environment
  group that the parent deliberately selected before spawning it.

The corrected API may expose a smaller set of additional safe isolation
choices, but CPU-017 should not require callers to construct raw flag masks.

### Native wait information

The public completion record should retain the native `Waitmsg` fields: pid,
time values, and message. The high-level success predicate should be derived
from an empty native message. Unix-style integer exit statuses should not
replace the underlying Plan 9 result.

### Focused redirection

The initial high-level process surface needs only inherited standard streams
and an explicit stdout-to-file form sufficient for the CPU-017 listener
branch. General pipelines, arbitrary descriptor actions, shell parsing, and
Unix process emulation should remain out of the first implementation.

## Required correction 1: environment-group ownership

### The conflict in P2-002

P2-002 proposes writing `NPROC`, `sysname`, `auth`, and `serviced` with
`Plan9.Env` before spawning the CPU-017 children. With the proposed default
spawn flags, those writes mutate the boot process's shared environment group.
That is not equivalent to the stock `cpurc` boundary.

The caml9 CPU-017 review records the relevant compatibility rule in decision
D044: globally established boot identity belongs to the main boot process,
while service-setup variables derived for the final child-delivery block must
not leak back into the long-lived `init` environment merely because OCaml
lacks rc's execution boundary.

`NPROC` and the finalized `sysname` are global boot state. The derived `auth`
and `serviced` values are local inputs to service startup. Treating all four
identically would make Phase 2 native but behaviorally less faithful.

### Required sequence

The corrected design should support this sequence:

1. Finalize globally intended boot variables, including `NPROC`, `sysname`,
   and prompt, in the current environment group.
2. Before deriving or installing child-only service variables, call a
   current-process native operation equivalent to `rfork(RFENVG)`.
3. Confirm that this operation changes only the caller's environment-group
   membership and does not create a process.
4. Write `auth` and `serviced` through `Plan9.Env` into the new copied group.
5. Spawn service children without another environment-group flag, so they
   share this deliberately selected private group.
6. Leave the original `init` group with the global variables but without the
   derived service-only additions.

The public surface may name this narrowly, for example:

```ocaml
val copy_environment : unit -> (unit, error) result
```

or represent it as the only safe current-process use of an `rfork` flag. It
must not be confused with process creation.

### Rejected Phase 2 alternative

An environment overlay copied separately for every spawned child could also
prevent leakage, but it complicates ordering and makes a family of CPU-017
children harder to place in the same deliberately prepared environment group.
The one-time current-process `RFENVG` split is closer to rc's block boundary
and should be preferred unless the OCaml task finds contrary native evidence.

The ABI probe must establish the exact native behavior of current-process
`RFENVG`, including which pre-existing values are copied and whether later
writes remain isolated in both directions.

## Required correction 2: one owner for the native wait queue

### The process-wide constraint

Plan 9 `await` returns the next wait message available to the calling process;
it is not a PID-specific kernel wait. Therefore `Plan9.Process.wait`,
`Plan9.Process.wait_any`, a public `Plan9.Raw.wait_any`, `Sys.command`, and
APE/Unix wait functions cannot safely act as independent consumers. Any one of
them may remove the completion that another layer expects.

This is not merely a documentation caveat. It determines the ownership model
for the whole API.

### Required coordinator model

While any managed `Plan9.Process` child remains unresolved, one coordinator
must be the exclusive native wait-queue consumer for the library. All
high-level waits must route through it. A public raw wait primitive would
defeat that invariant and should not be exposed in Phase 2.

The coordinator should:

- give every spawn a library-unique handle identity that is not just the pid;
- keep a pid-to-handle entry only while that handle is unresolved;
- retain an out-of-order completion on the corresponding handle;
- remove the active pid mapping as soon as the handle becomes terminal;
- classify a completion for an unknown pid at the moment it is reaped; and
- never attach an earlier unknown completion to a later process merely because
  the kernel reused the same numeric pid.

This eliminates the P2-002 idea of an indefinitely retained pid-keyed
completion table. Such a table cannot distinguish pid reuse and may silently
deliver a stale completion to a new child.

Unknown completions still need an explicit disposition. The corrected design
should state whether they are returned by high-level `wait_any`, placed in a
bounded foreign-completion queue, or reported through another observable
mechanism. Whatever choice is made must not permit later pid aliasing.

### External waiters

The library cannot prevent unrelated code in the same process from calling an
APE or native wait function. If such a waiter steals a managed completion,
the library may never receive evidence that the child ended. The API therefore
needs a terminal ownership-failure result such as `Lost` or `Protocol_error`
rather than promising that every managed handle can always become a normal
`Waitmsg`.

The corrected design must specify:

- when mixing with `Sys.command`, `Unix`, or another native waiter is
  prohibited;
- how an unresolved handle reports loss or protocol failure;
- whether the restriction lasts only while managed children are unresolved;
  and
- how tests can demonstrate the supported boundary without hanging.

## Required correction 3: exec-failure ownership and interruption

### No private wait in the spawn primitive

The C spawn primitive must not call `await` to reap an exec-failed child. An
`await` issued there could consume an unrelated managed or foreign completion.
The shared coordinator is the only component permitted to reap after a child
has been created.

The primitive's responsibilities end after it:

- creates the child;
- establishes durable OCaml-side ownership of that child;
- reads the close-on-exec error protocol to the extent possible; and
- reports the handshake observation without consuming the process-wide wait
  queue.

### Required launch-state distinction

The design needs at least these distinct launch outcomes:

1. **No child created.** Validation, descriptor setup before `rfork`, or
   `rfork` itself failed. A plain spawn `Error` is valid because no child
   remains.
2. **Registered and exec confirmed.** The parent observed clean close-on-exec
   EOF and returns the managed handle.
3. **Registered and exec failed.** The child reported a framed native error.
   The managed handle still exists and must be resolved through the shared
   wait coordinator.
4. **Registered but handshake indeterminate.** The parent was interrupted,
   saw truncation, or otherwise could not prove whether exec succeeded. The
   child remains owned and the caller must receive a handle-bearing incomplete
   result.

A plain `Error` must never discard knowledge of a possibly live or waitable
child.

### Ownership must precede interruption

There must be no async-exception or allocation window after successful
`rfork` in which the child exists but no durable owner can recover it.
P2-004 should identify the implementation boundary that guarantees this.
Possible mechanisms include a native pending-child registry or an already
rooted ML handle whose state is updated by the primitive. Choosing between
those mechanisms is an implementation-design decision; it is not a harmless
ABI fact and should not be delegated to the guest probe.

The high-level API also needs a way to enumerate or resolve incomplete
ownership, such as `Process.unresolved`, if a launch returns indeterminate or
an asynchronous exception crosses the parent-side handshake.

### Error-pipe framing

The `#d/<fd>` plus `OCEXEC` handshake remains a good Plan 9 mechanism, subject
to guest verification. The corrected design must define a bounded frame rather
than interpreting arbitrary EOF or text:

- a version or fixed tag;
- a declared or fixed payload length;
- a maximum error length;
- complete-read behavior;
- truncated-frame classification;
- unexpected-data classification; and
- preservation of the native error text.

Descriptor allocation and redirection must be ordered so that the handshake
cannot collide with file descriptors 0, 1, or 2, including when one or more of
those descriptors started closed.

## Required correction 4: native wait naming

The record field called `status` in P2-002 should be called `message`. Plan 9's
native `Waitmsg.msg` is a message string and may include the child's identity
prefix; it is not the Unix status integer implied by the proposed name.

A representative public shape is:

```ocaml
type wait_msg = {
  pid : int;
  user_time_ms : int64;
  system_time_ms : int64;
  real_time_ms : int64;
  message : string;
}
```

The exact integer representation should follow measured ABI ranges and OCaml
4.14.3 conventions, but the semantic name and preservation requirement should
not depend on that probe. Convenience functions may interpret empty versus
non-empty messages without destroying the original field.

## Required correction 5: defer RFNOMNT

P2-002 includes a public `Forbid_mounts` or `RFNOMNT` option. It is not needed
for CPU-017, and its interaction with the proposed process machinery is
actively problematic:

- the error channel relies on opening `#d/<fd>`; and
- a fallback pipe implementation would use `#|`, another mount-like device
  access.

Phase 2 should remove this option from the public safe surface. It can be
reconsidered later as a separately justified sandboxing feature after native
tests establish exactly which already-open devices, new device opens, mounts,
and binds remain possible. The initial process API should not advertise a
policy it cannot reliably compose with its own launch protocol.

## Required correction 6: distinguish raw and high-level argv

The low-level exec primitive should preserve the Plan 9 contract exactly: it
receives the complete argv vector, including `argv[0]`, and rejects an empty
vector.

The high-level API should instead accept a program and its arguments:

```ocaml
val spawn :
  ?stdout:stdout ->
  program:string ->
  args:string list ->
  unit ->
  (handle, launch_error) result
```

It should construct the low-level vector as `program :: args`. Thus an empty
high-level `args` list is valid and produces a one-element argv. This removes a
repetitive and error-prone obligation from normal callers without weakening
the raw contract.

## Required correction 7: split harmless ABI work from service behavior

### Harmless ABI probe

The first guest probe should be narrow, disposable, and incapable of starting
real boot services. Its scope may include:

- availability and signatures of `rfork`, `exec`, `await`, `Waitmsg`, `OCEXEC`,
  `#d`, and related headers or symbols;
- a harmless child executing a purpose-built probe program;
- default and explicit argv observations;
- `await` field units, formatting, success message, error message, and
  truncation behavior;
- `#d/<fd>` plus `OCEXEC` close-on-exec behavior;
- the bounded exec-error frame and malformed/truncated cases;
- stdout inheritance and stdout-to-disposable-file redirection;
- descriptor collision cases when 0, 1, or 2 begins closed;
- bounded interruption observations that cannot leave an unowned child;
- current-process `RFENVG` copy and isolation behavior; and
- repeated completion ordering sufficient to validate the coordinator model.

The probe must use disposable files and purpose-built children with bounded
timeouts and cleanup. It should not modify an installed compiler prefix.

### Separate stateful service-behavior probe

The following are not harmless ABI facts and must not be smuggled into the
first probe:

- authentication-server selection;
- `keyfs` or `/adm/keys`;
- `aux/listen`;
- actual `/rc/bin/service` startup;
- real service directories or listeners;
- caml9 installation or boot replacement; and
- any interaction with a protected or shared guest.

If these behaviors need qualification, authorize a later stateful probe with a
disposable scratch VM, unique loopback address, private namespace and
environment setup, synthetic key or service data, explicit listener inventory,
bounded cleanup, and separately recorded evidence. Passing the ABI probe must
not be described as CPU-017 boot acceptance.

## Required correction 8: reconcile cross-repository operational state

At review time, the caml9 tracked current-state and the OCaml Phase 1 record did
not describe the `.40` compiler lab from the same observation boundary. One
still described the planned or unbooted lab under caml9 ownership while the
other recorded the completed Phase 1 lifecycle under OCaml ownership.

That disagreement does not invalidate this read-only design exchange, but no
further stateful gate should rely on either record alone. Before any VM,
endpoint, guest, transfer, build, or installation action:

1. identify the sole stateful operator;
2. revalidate the live process, listener, disk, instance, and repository state;
3. update the authoritative tracked handoff record without inventing history;
   and
4. make the exact next authorization and exclusions agree across the handoff.

The documentation exchange lease does not transfer operational ownership.

## Requested corrected public boundary

P2-004 need not freeze final OCaml syntax, but it should make the following
boundary unambiguous.

### Plan9.Raw

The first public raw layer should contain only primitives that are safe for
advanced callers:

- exact-vector `exec`, if exposing it independently is safe and useful;
- a current-process environment-group copy operation;
- constants or values that cannot encode `RFMEM`; and
- low-level data conversion needed by the safe layer.

It should not expose:

- a child-returning `rfork`;
- `RFMEM`;
- a process-wide `wait_any`;
- `RFNOMNT` in the Phase 2 safe flag set; or
- an escape hatch accepting arbitrary integer masks.

If the combined non-returning spawn primitive must remain internal to implement
`Plan9.Process`, it need not be public merely because it is native.

### Plan9.Process

The high-level layer should own:

- program-plus-args argv synthesis;
- safe isolation selection;
- inherited or file-backed stdout;
- the exec handshake;
- unique handle creation;
- all wait-queue consumption for managed children;
- out-of-order completion storage on active handles;
- foreign-completion classification;
- normal, exec-failed, indeterminate, lost, and protocol-error states; and
- inspection of unresolved owned children.

The result types should make "no child exists" distinguishable from "a child
exists but launch confirmation is incomplete." Exceptions may be layered on
top only if they preserve that ownership information.

## CPU-017 compatibility matrix

The corrected response should include an explicit mapping at least this
precise:

| CPU-017 need | Required Phase 2 facility | Environment visibility |
| --- | --- | --- |
| publish `NPROC` | `Plan9.Env.set` before the split | original and copied groups |
| finalize `sysname` and prompt | existing native/environment facilities before the split | original and copied groups |
| isolate service setup | current-process environment-group copy | creates the child-delivery boundary |
| publish derived `auth` and `serviced` | `Plan9.Env.set` after the split | copied service group only |
| start selected service scripts | `Plan9.Process.spawn` with inherited stdout | copied service group |
| start CPU listener branch | `Plan9.Process.spawn` with stdout-to-file | copied service group |
| preserve continuation | retain handles without forcing immediate sequential waits | boot program continues |
| avoid zombies and stolen completions | single wait coordinator and explicit lifecycle policy | process-wide invariant |

This mapping is necessary but not sufficient for CPU-017. Service-directory
precedence, configured-versus-ndb authentication values, rc pattern semantics,
auth-server selection, `keyfs`, process lifetime, and the machine/default
branches remain caml9 behavior questions.

## Evidence required before implementation acceptance

The corrected design should classify evidence rather than treating all open
questions alike.

### Source-contract evidence

The design can settle from authoritative source and headers:

- which `rfork` flags exist and which combinations are structurally unsafe;
- `Waitmsg` field meanings;
- the process-wide nature of `await`;
- `OCEXEC` intent;
- `#d` and `#|` interfaces; and
- the installed runtime primitive-registration mechanism.

### Harmless guest evidence

The first native probe should settle:

- actual installed header and linker availability;
- numeric/time conversion behavior;
- exact wait-message observations;
- close-on-exec and descriptor-collision behavior;
- exec-error framing;
- interruption behavior under bounded tests;
- current-process environment-group copying; and
- enough ordering cases to validate the coordinator.

### Implementation proof

Tests and review of the candidate runtime must settle:

- no return to OCaml in the child;
- no `RFMEM` encoding or integer escape hatch;
- durable ownership immediately after successful `rfork`;
- no private `await` in spawn;
- no public competing raw waiter;
- pid-reuse-safe completion routing;
- no-C-tool consumer linking; and
- recovery or observability for every unresolved handle.

### Later caml9 evidence

Only after independent Phase 2 acceptance should caml9 test:

- the global/private environment split;
- all service-directory precedence branches;
- configured, ndb-derived, and absent auth cases;
- auth-server and `keyfs` behavior;
- CPU-only and non-CPU listener choices;
- child lifetime and boot continuation; and
- exact developmental or promotion-lane boot evidence.

## Canonical-document implications

If P2-004 adopts these corrections, the later canonicalization pass should
update the Plan 9 native API requirements, implementation plan, and acceptance
plan together. In particular, canonical text must not retain:

- globally written child-only CPU-017 variables;
- a public raw waiter competing with `Plan9.Process`;
- pid-only long-lived completion storage;
- a spawn error that can lose an existing child;
- `status` as the name of the native wait message;
- Phase 2 `RFNOMNT`;
- caller-supplied argv0 in the high-level API; or
- auth/service startup inside a supposedly harmless ABI probe.

This P2 document is not itself authorization to make those canonical edits.

## Required P2-004 response checklist

P2-004 should answer each of the following directly:

1. Does it adopt the `RFENVG` current-process split before derived CPU-017
   variables, and what exact public operation provides it?
2. Which component exclusively consumes the native wait queue?
3. Is public `Raw.wait_any` removed?
4. How are handle identity, active pid mapping, unknown completions, and pid
   reuse separated?
5. How is a stolen completion represented without an indefinite hang?
6. At what exact point after `rfork` does durable child ownership exist?
7. Can any spawn error path lose a live or waitable child?
8. Who reaps a child that reports exec failure?
9. How are interrupted and malformed handshakes represented?
10. Is the native field named `message`, with the original text retained?
11. Is `RFNOMNT` deferred?
12. Does the high-level API synthesize argv0 while the raw API preserves exact
    argv?
13. Are the harmless ABI and stateful service probes separate?
14. Which questions remain implementation decisions rather than probe facts?
15. What canonical documents would change after the exploration is accepted?

Until that response is reviewed, Phase 2 implementation, guest probes,
canonical promotion, and caml9 integration should remain unstarted.
