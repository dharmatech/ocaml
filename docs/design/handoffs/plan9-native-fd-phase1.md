# Phase 1 `Plan9.Fd` roadmap

Status: accepted and completed roadmap; Phase 1 natively qualified at
`ee8f799bba40f2ed8caa57a4ef7e91726f2f4283`

## Authority and required reading

The authoritative foundation is:

`C:\Users\dharm\src\ocaml\docs\design\plan9-native-io-foundation.md`

This roadmap divided Phase 1 into three sequential, independently reviewed
and natively validated subphases. Its reviewed documentation checkpoint is
`9369474ed38cf35bb0bf699e28d617a88c534e07`; the remainder is retained as the
accepted execution contract.

The focused execution handoffs are:

1. `plan9-native-fd-phase1-1-private-ml-regroup.md`;
2. `plan9-native-fd-phase1-2-ownership-lifecycle.md`; and
3. `plan9-native-fd-phase1-3-byte-io-acceptance.md`.

For a subphase, read this roadmap, that subphase's handoff, the foundation
sections it names, the repository `AGENTS.md`, and every applicable local
skill. Later-subphase handoffs are not implementation authority for an earlier
subphase. The complete foundation remains authoritative if a cross-reference
is unclear. If accepted documents genuinely conflict, stop and ask the user.

## Repository and predecessor identity

- Authoritative editing repository: `C:\Users\dharm\src\ocaml`.
- Published Plan 9 baseline branch: `plan9-4.14.3-000`.
- Published baseline commit:
  `a98e773a80311653d7a78763bd017328b5c26b52`.
- Local source-and-workflow base:
  `835bc29b0c276a83211a517b950a55f0fb9c2bfe`.
- Sequential implementation branch: `codex/plan9-native-io-foundation`.
- Accepted Phase 0.1 checkpoint:
  `0d3ac056a37e597e9673607de591cb8a0b5247bb`.
- Accepted Phase 0.2 checkpoint:
  `f2bc2dd152a3cb5e5541edc6aee4927ff4c6d83b`.
- Reviewed Phase 0.3 documentation checkpoint:
  `dcbb9f2d2b31a31a7ccf6d946957fa5e132df3d1`.
- Accepted Phase 0 and Phase 0.3 checkpoint:
  `aa627e94e9db4a680a30c8e3671a00e709a97320`.
- Preserved rejected prototype:
  `codex/archive/plan9-process-capture-prototype` at
  `1eb780b1b8467d1b80b35102e40371b87dde5604`.

The accepted predecessor is exactly the Phase 0 checkpoint above. The reviewed
Phase 1 documentation checkpoint is exactly
`9369474ed38cf35bb0bf699e28d617a88c534e07`.

Before any subphase edits code, verify that:

- the branch is exactly `codex/plan9-native-io-foundation`;
- `HEAD` contains accepted Phase 0 and the complete reviewed Phase 1
  documentation set;
- the index and worktree are clean; and
- no unexpected commit, merge, rebase, or unrelated local change is present.

If any condition differs, report the exact state and stop. Do not clean,
stash, reset, or absorb another task's work.

## Accepted Phase 0 boundary

Phase 0 established the private five-operation native path for `ERRSTR`,
`PIPE`, logical `PREAD`, logical `PWRITE`, and `CLOSE`. The accepted runtime
integration supplies:

- opaque runtime-owned descriptor capabilities with unpublished, open, and
  closed states;
- guarded all-or-nothing pipe publication;
- deterministic capability close with terminal state after any attempted
  native close;
- validated single-call reads and writes from zero through 4096 bytes;
- immediate native error capture without `errno` or APE error translation;
- pending-action processing followed by callback-mutable revalidation and
  non-pending blocking entry; and
- defensively ordered validation for correct-arity hostile primitive calls.

The accepted capability is a private runtime guard, not the public `Fd.t`
ownership cell. It has no descriptor-closing finalizer and exposes no raw
descriptor integer. The standard runtime remains APE-linked for portable OCaml
behavior, while the reviewed five-operation path is independent of APE's
operating-system I/O and descriptor machinery.

Phase 1 consumes this accepted native boundary. A need to change its raw ABI,
capability representation, validation order, staging capacity, blocking
discipline, or error capture is not an incidental Phase 1 refactor: stop,
report the evidence, and revise the owning design before changing it.

## Phase 1 outcome

Phase 1 delivers the first complete public native-I/O abstraction:

```ocaml
module Fd : sig
  type t

  val pipe : unit -> ((t * t), error) result
  val read : t -> bytes -> pos:int -> len:int -> (int, error) result
  val write : t -> bytes -> pos:int -> len:int -> (int, error) result
  val close : t -> (unit, error) result
end
```

`Fd.t` is an abstract shared ownership cell, never a descriptor integer and
never an ordinary OCaml channel. Aliases share one lifecycle. A public handle
may be open and detached, terminally closed by the public owner, or attached
to an authorized higher-level native owner. Attachment permanently revokes
public descriptor operations through every retained alias. The private
attachment token then owns I/O and close for the same cell.

Only `plan9.cmi` is installed. The internal `Plan9_types`, `Plan9_primitive`,
`Plan9_process`, and `Plan9_fd` interfaces remain uninstalled. `plan9.cma`
remains ML-only and ordinary use continues to need no `-custom`, alternate
runtime, C compiler, linker, or wrapper compiler.

## Sequential execution plan

```text
Phase 1.1: private ML module regroup with no public API change
                  |
                  v
Phase 1.2: Fd ownership cell, pipe, close, aliases, and attachment
                  |
                  v
Phase 1.3: Fd byte I/O and complete Phase 1 acceptance
```

### Phase 1.1: private ML regroup

Starting from accepted Phase 0, establish the one-way internal source
boundaries promised by the foundation. Move shared error and identity types
into `Plan9_types`, centralize only the production built-in primitive bindings
already present in `plan9.ml` and their private ABI types in
`Plan9_primitive`, and adapt `Plan9_process` and the umbrella without changing
any installed signature, primitive-import set, test runtime lane, or behavior.

This subphase adds no `Plan9.Fd`, no public API, no native primitive, and no
runtime C change. It proves that the architectural regroup is behavior- and
packaging-neutral before descriptor ownership is added.

### Phase 1.2: ownership lifecycle

Starting only from accepted Phase 1.1, add the private `Plan9_fd` ownership
cell; extend `Plan9_primitive` with the production capability, pipe, and close
bindings; add native pipe construction, deterministic public close, alias
behavior, and the preallocated private attachment token/commit protocol
required by `Plan9.In_channel`. Exercise lifecycle behavior with a fake
counted primitive backend and native pipe/close tests.

This checkpoint remains internal: it does not yet re-export `Plan9.Fd` from
the installed umbrella. It does not add byte I/O policy or begin Phase 2.

### Phase 1.3: byte I/O and final acceptance

Starting only from accepted Phase 1.2, add typed byte reads and writes to the
ownership cell and its authorized attachment token, extend `Plan9_primitive`
with the production read and write bindings, publish the complete `Plan9.Fd`
module, update public documentation, and perform the full fresh native build,
regression, symbol, descriptor-cleanup, and installed-prefix qualification for
Phase 1.

Only Phase 1.3 may conclude that Phase 1 is accepted or authorize the design
review for `Plan9.In_channel`.

## Shared semantic decisions

Every subphase preserves these decisions:

- portable `Stdlib`, `Sys`, and `Unix` behavior remains unchanged;
- the project keeps one standard APE-linked `ocamlrun` and the APE/GNU Make
  build lane;
- `plan9.cma` contains ML only and all native primitives come from the
  standard Plan 9 `ocamlrun`;
- internal modules depend on their actual private predecessors and never on
  the installed `Plan9` umbrella;
- no ML-facing primitive or public function accepts or returns a raw
  descriptor integer;
- no descriptor-closing finalizer, `of_int`, `to_int`, standard-descriptor
  adoption, arbitrary `dup`, ordinary-channel conversion, APE descriptor
  registration, or escape hatch is added;
- Plan 9 pipe endpoints remain bidirectional peers rather than false Unix
  read-end and write-end types;
- interruption is returned exactly once and is never retried implicitly;
- a native short read is valid, while a native write count smaller than the
  exact count passed to that raw call is reported as an error without issuing
  the remainder;
- zero-length I/O validates the typed range and lifecycle first, then returns
  `Ok 0` without invoking the native primitive;
- native errors preserve the high-level operation and exact captured native
  message; and
- invalid ranges, closed public handles, attached public handles, and invalid
  attachment tokens fail without native work.

Correct-arity hostile declarations of built-in primitives remain inside the
Phase 0 defensive threat model and are regression-tested. Forging or mutating
an abstract pure-ML `Fd.t` with unsafe `Obj` operations is outside the public
ML contract, as it is for ordinary OCaml abstract types; this does not weaken
the native primitive boundary.

The release-specific semantic reference remains the read-only checkout:

- `/home/dharmatech/src/9front-11554`;
- commit `2191d72205863d2c53ea6ac36991cb4c13204c7c`; and
- `sys/man/2/pipe`, `sys/man/2/read`, `sys/man/2/open`, and
  `sys/src/9/port/sysfile.c`.

Those sources establish bidirectional pipe endpoints, preserved write
boundaries, EOF after buffered data and the writer's close, ambiguous partial
transfer on interruption, ordinary positive short reads, short-write-as-error
policy, all-or-nothing pipe descriptor publication, and guaranteed close for
a valid open descriptor. Native guest identity must still be recorded during
qualification; source-tree correspondence is not silently assumed.

## Review, VM, and checkpoint protocol

Each subphase is one vertical slice owned by one executing task through source
implementation, host-side review, and native validation. For every subphase:

1. Record the starting Git and source state.
2. Implement only that subphase.
3. Run all safe host-side static checks and inspect the complete diff.
4. Report the proposed code and any design deviation to the user, then pause.
5. Before any VM operation, obtain explicit user confirmation of the exact
   writable instance, loopback address, intended action, and WHPX profile.
6. Transfer without `.git` through `/mnt/term`, copy onto native Plan 9
   storage, and run configure, GNU Make, tests, and installation only there.
7. Report results and stop; do not begin the next subphase.

Useful native build trees may be retained for incremental subphase work. Final
Phase 1.3 acceptance must additionally use a fresh, previously nonexistent,
artifact-free native source destination containing the exact approved source
set from the reviewed Windows worktree, with independently matching manifests
and no `.git`.

An install prefix is requested only in Phase 1.3. It must be isolated and
nonexistent unless the user explicitly approves replacement, and the user
chooses whether it is retained or removed afterward. Never overwrite the
known-working prefix `/usr/glenda/lib/unix/ocaml-4.14.3`; record matching
before/after manifests proving that it remained unchanged. No VM snapshot or
checkpoint replacement is authorized by these handoffs.

Do not commit or push documentation or implementation changes unless the user
explicitly asks. A later subphase must not begin from an unreviewed, dirty,
known-broken, or partially qualified predecessor.

## Final Phase 1 acceptance summary

The detailed criteria live in the foundation and Phase 1.3 handoff. At a
minimum, final acceptance requires:

- the Phase 1.1 internal regroup preserves the installed `plan9.cmi`, existing
  public semantics, and all process, environment, and primitive behavior;
- resource-producing `Fd.pipe` preallocates every ML wrapper needed for safe
  public ownership before native acquisition and performs no fallible
  allocation between successful primitive return and complete publication;
- public aliases observe one shared detached, attached, or terminal
  lifecycle, with deterministic and idempotent ownership-specific close;
- attachment commit is allocation-free, rechecks the cell immediately before
  transition, and authorizes exactly one preallocated private token;
- public reads and writes validate ranges without overflow, use at most one
  accepted primitive transfer per call, preserve short-read semantics, reject
  actual native short writes without retry, and keep the staging capacity
  private;
- focused fake-backend and native tests cover lifecycle, reentrancy-relevant
  state changes, zero length, large logical ranges, binary data, EOF, short
  I/O, error mapping, forged primitive calls, and descriptor cleanup;
- a fresh native build runs all existing Plan 9 regressions and the complete
  Phase 0 and Phase 1 focused suites;
- symbol and source audits retain the accepted APE-independence claim for the
  five-operation path and show one linked definition for every primitive;
- `plan9.cma` remains ML-only and only `plan9.cmi` is installed; and
- an approved installed-prefix smoke test compiles and runs an ordinary public
  `Plan9.Fd` consumer using the installed `ocamlc`, `ocamlrun`, and
  `-I +plan9 -linkall plan9.cma`, with no custom runtime or toolchain escape.

If installation is not authorized, the installed-prefix criterion remains
open and Phase 1 must not be reported as fully accepted.

## Strictly excluded work

No Phase 1 subphase includes:

- `Plan9.In_channel`, `Plan9.Out_channel`, `Plan9.File`, `Plan9.Stat`,
  `Plan9.Directory`, `Plan9.Command`, or `Plan9.Env` migration;
- modification of existing `Plan9.Raw` or `Plan9.Process` semantics;
- new raw syscalls, process migration, capture, line splitting, `dup`,
  `rfork`, `exec`, `exits`, or `await` work;
- seeking, file opening, file creation, length, position, or stat operations;
- temporary files, shell commands, PATH search, pipelines, or expansion;
- a second runtime, removal of APE, native-code support, shared libraries,
  custom-runtime work, or systhreads;
- standard-descriptor adoption or arbitrary foreign descriptor adoption;
- timing-sensitive note-interruption injection without a separate explicit
  qualification decision;
- VM snapshots, checkpoint replacement, merge, release publication, or Caml9
  changes.

If excluded work appears necessary, stop and return the evidence rather than
expanding the subphase.

## Shared completion report

Every subphase reports:

- adopted foundation, roadmap, and focused-handoff paths;
- exact starting branch, `HEAD`, predecessor checkpoint, tested tree, and
  final committed or uncommitted identities;
- selected 9front source and guest release/architecture provenance;
- files changed and why;
- internal and public module/type/API shapes relevant to that subphase;
- every host and native command with pass/fail result;
- focused and regression test results;
- primitive, symbol, packaging, APE-independence, and descriptor-cleanup
  evidence relevant to that subphase;
- source-tree, transfer, prefix, VM, listener, and writable-disk
  postconditions;
- every deviation, uncertainty, open criterion, or skipped gate; and
- final worktree, index, branch, and remote-tracking status.

Phase 1.3 additionally reports installed-prefix evidence and ends with exactly
one recommendation:

- **Phase 1 accepted; ready to design `Plan9.In_channel`**;
- **implementation ready but native qualification still required**; or
- **Phase 1 blocked or rejected**, with the exact reason.

No report may claim that the entire runtime or library is APE-free. The
accepted claim remains scoped to the reviewed native descriptor path inside
the standard APE-linked runtime.
