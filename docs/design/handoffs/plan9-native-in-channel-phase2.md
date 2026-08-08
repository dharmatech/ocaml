# Phase 2 `Plan9.In_channel` roadmap

Status: proposed roadmap for review; no Phase 2 implementation is authorized
until this roadmap and its focused handoffs are accepted

Reviewed Phase 2 documentation checkpoint: pending final documentation-content
commit and the follow-up checkpoint-recording commit described below.

## Authority and required reading

The authoritative foundation is:

`C:\Users\dharm\src\ocaml\docs\design\plan9-native-io-foundation.md`

This roadmap proposes four sequential, independently reviewed and natively
validated subphases:

1. `plan9-native-in-channel-phase2-1-ownership-buffered-input.md`;
2. `plan9-native-in-channel-phase2-2-bounded-lines.md`;
3. `plan9-native-in-channel-phase2-3-bounded-aggregates.md`; and
4. `plan9-native-in-channel-phase2-4-public-acceptance.md`.

For a subphase, read this roadmap, that subphase's focused handoff, the
foundation sections it names, the repository `AGENTS.md`, the top-level
`README.md`, `build-aux/plan9/README.md`, and every applicable local skill.
Later-subphase handoffs are not implementation authority for an earlier
subphase. The complete foundation remains authoritative if a cross-reference
is unclear. If accepted documents genuinely conflict, stop and ask the user.

## Repository and predecessor identity

- Authoritative editing repository: `C:\Users\dharm\src\ocaml`.
- Published Plan 9 baseline branch: `plan9-4.14.3-000`.
- Published baseline commit:
  `a98e773a80311653d7a78763bd017328b5c26b52`.
- Sequential implementation branch: `codex/plan9-native-io-foundation`.
- Accepted Phase 0 checkpoint:
  `aa627e94e9db4a680a30c8e3671a00e709a97320`.
- Accepted Phase 1 checkpoint:
  `ee8f799bba40f2ed8caa57a4ef7e91726f2f4283`.
- Phase 1 documentation/status base from which this design was prepared:
  `50f022919198c24ca4e5697b79b1cd52411da83e`.
- Preserved rejected capture prototype:
  `codex/archive/plan9-process-capture-prototype` at
  `1eb780b1b8467d1b80b35102e40371b87dde5604`.

The accepted implementation predecessor is Phase 1 at `ee8f799bba...`; the
later documentation commits through `50f0229191...` clarify its completed
status and remain part of the required starting history. Before implementation
begins, freeze and review the complete Phase 2 document set, then create a
documentation-content commit. That commit's exact hash is the reviewed Phase 2
documentation checkpoint. Because a commit cannot contain its own hash, record
that hash in this roadmap and every focused handoff in a follow-up checkpoint-
recording commit. The pending marker above is not a checkpoint, and no Phase 2
implementation may begin until both commits are in the branch history and
every recorded hash agrees.

Before any subphase edits code, verify that:

- the branch is exactly `codex/plan9-native-io-foundation`;
- `HEAD` contains the accepted Phase 1 checkpoint, the documentation/status
  base above, and the complete reviewed Phase 2 handoff set;
- the index and worktree are clean; and
- no unexpected commit, merge, rebase, or unrelated local change is present.

If any condition differs, report the exact state and stop. Do not clean,
stash, reset, switch branches, or absorb another task's work.

## Accepted Phase 1 boundary

Phase 1 supplies the exact lower boundary consumed here:

- `Plan9.Fd.t` is one abstract shared ownership cell, never a raw descriptor;
- `Plan9.Fd.Private.prepare_attach` preallocates an opaque token without
  reserving or changing the cell;
- `Plan9.Fd.Private.commit_attach` is an allocation-free, final recheck and
  ownership transition that authorizes exactly one prepared token;
- a committed token exclusively owns `Private.read`, `Private.write`, and
  `Private.close`, while every retained public alias remains revoked;
- private reads perform at most one accepted native transfer, return valid
  positive short progress, return zero at the observed EOF, and never retry an
  interruption;
- private close is deterministic and idempotent for the exact owner, while an
  unexpected native close failure still terminalizes the capability; and
- the standard runtime remains APE-linked, but this accepted five-operation
  descriptor path performs no APE operating-system I/O or descriptor work.

Phase 2 adds no raw syscall and changes none of those contracts. If a proposed
channel implementation appears to require a raw integer, a new primitive, a
different attachment protocol, a larger primitive transfer, retry after
interruption, or conversion to an ordinary OCaml channel, stop and revise the
owning design rather than changing Phase 1 incidentally.

## Proposed Phase 2 outcome

After final acceptance, the installed umbrella adds this module:

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

`In_channel.t` is a distinct abstract native channel, not
`Stdlib.in_channel`. `of_fd` transfers operational ownership by the accepted
prepare/allocate/commit protocol. A successful channel permanently revokes
public operations through every retained `Fd.t` alias. The channel buffers in
ML, calls only the committed private `Fd` owner, and closes explicitly; it has
no descriptor-closing finalizer.

Input is binary. Only byte `0x0a` terminates a line, and the terminator is
omitted. Carriage return and embedded NUL are ordinary bytes. Empty input has
no lines, one newline has one empty line, a trailing newline adds no extra
line, and an unterminated final line is returned.

### Proposed resource policy

Every materializing helper is bounded by default and permits a caller to
choose a different explicit finite bound:

- `input_line` defaults `max_bytes` to `1_048_576`; the bound counts only the
  returned line body and excludes its optional newline terminator;
- `input_all` defaults `max_bytes` to `16_777_216`; the bound counts every
  returned byte;
- `input_lines` defaults total `max_bytes` to `16_777_216` and
  `max_line_bytes` to `1_048_576`; the total counts every consumed source byte,
  including newline terminators, while the per-line bound excludes the
  terminator; and
- each supplied bound must be between zero and `Sys.max_string_length`,
  inclusive, and is validated before channel lifecycle or native work.

These defaults are public policy, not the private descriptor staging size.
They are deliberately finite and materially below representability. A caller
may choose a larger reviewed bound explicitly, but no successful call has
representable memory as its implicit only limit.

A line-body bound succeeds at its exact value when followed by the owning
terminator or observed EOF. A whole-input bound succeeds at its exact value
only when followed by observed EOF; a following newline is another source byte
for whole-input accounting. To distinguish exact-bound success from excess,
the implementation may inspect one buffered byte beyond the accepted prefix.
On excess it consumes exactly the allowed prefix, leaves the first excess byte
and every byte already buffered after it unread, discards the partial result,
and returns an error. It does not drain an arbitrarily long record and does not
close the channel automatically. The caller still owns the channel and must
close it deterministically.

Limit excess uses the existing `error` shape and `Other` kind with exact
operation-specific messages; Phase 2 adds no new `error_kind`. Invalid bound
arguments use `Invalid_argument`. Phase 4 remains free to wrap a channel limit
in its own structured capture-failure type without expanding this lower
layer's shared error classification.

## Sequential execution plan

```text
Phase 2.1: ownership transfer, channel state, buffering, input, close
                  |
                  v
Phase 2.2: bounded line framing and input_line
                  |
                  v
Phase 2.3: bounded input_all and input_lines
                  |
                  v
Phase 2.4: installed public API and complete Phase 2 acceptance
```

### Phase 2.1: ownership and buffered input

Starting from accepted Phase 1, add the uninstalled `Plan9_in_channel`
module, allocate its channel, fixed private scratch buffer, and enclosing
success before attachment commit, then implement deterministic owner close
and caller-buffer `input`. Serialize reentrant operations at the channel
layer, preserve all unread buffer bytes, issue at most one lower read when a
public `input` call begins with an empty buffer, and never cache EOF as a
permanent property of a descriptor.

The module enters `plan9.cma` in dependency order but is not re-exported from
`Plan9`. Focused fake-backend and native tests validate transfer, aliases,
buffer splits, errors, close, reentrancy, and cleanup.

### Phase 2.2: bounded lines

Starting only from accepted Phase 2.1, add `input_line` internally. Implement
an overflow-safe bounded accumulator and delimiter scanner over arbitrary
lower-read and buffer splits. Settle exact empty, newline, NUL, carriage
return, long-line, exact-limit, excess-limit, EOF, error, and stream-position
semantics. Reuse the channel operation guard and lower refill path; add no
second descriptor-I/O implementation.

This checkpoint remains internal and adds no aggregate operation or installed
surface.

### Phase 2.3: bounded aggregates

Starting only from accepted Phase 2.2, add `input_all` and `input_lines`
internally. `input_all` applies its whole-input bound incrementally.
`input_lines` enforces both whole-input and per-line bounds while constructing
the final list without treating CR or NUL specially and without manufacturing
a trailing empty line. Simultaneous excess at one byte reports the whole-input
bound first.

Extend the same focused tests. This checkpoint still does not re-export the
module or perform installation.

### Phase 2.4: public integration and final acceptance

Starting only from accepted Phase 2.3, publish the complete exact interface in
`plan9.mli` and `plan9.ml`, update user and maintainer documentation, add the
installed-consumer and expected-failure privacy probes, and perform the full
fresh native build, regression, symbol, descriptor-cleanup, packaging, and
approved isolated-prefix qualification.

Only Phase 2.4 may conclude that Phase 2 is accepted or authorize Phase 3
process-backend migration.

## Shared channel semantics

Every subphase preserves these decisions:

- range and bound arguments are checked without overflowing arithmetic before
  lifecycle state or descriptor work;
- a valid zero-length `input` still requires an open channel and returns
  `Ok 0` without a lower read;
- a positive `input` returns buffered bytes immediately when available;
- when no byte is buffered, one `input` call performs at most one private
  `Fd.read`, preserves positive short progress, and returns zero only for that
  observed lower EOF;
- line and aggregate helpers may perform multiple sequential refills because
  their contracts own complete materialization up to a boundary;
- EOF is not cached permanently: a later call may perform another lower read,
  which keeps the channel suitable for future native regular-file adoption;
- interruption and every other lower read failure are returned once and never
  retried; already consumed buffered bytes are not rolled back;
- successful reads preserve exact bytes, including NUL, and a read error does
  not synthesize data;
- only the committed attachment token performs lower reads and close;
- an active channel operation rejects reentrant input or close without nested
  descriptor work; arbitrary exceptions restore the channel's stable state
  and are re-raised unchanged;
- once close begins, new input is rejected; repeated close is idempotent after
  a normal terminal result, and an exception-left close attempt is retryable
  only through the same channel owner;
- a normal lower close error is mapped to `Plan9.In_channel.close` and leaves
  the channel terminal, because the accepted capability is already terminal;
- no finalizer, raw descriptor, APE registration, ordinary channel,
  standard-descriptor adoption, or public private-owner token is introduced;
  and
- `plan9.cma` remains ML-only and only `plan9.cmi` is installed.

Correct-arity hostile native primitive declarations remain inside the Phase 0
defensive boundary and are rerun unchanged. Unsafe `Obj` forging or mutation
of the abstract pure-ML `Fd.t` or `In_channel.t` representation is outside the
public ML contract.

## Documentation provenance

Phase 2 is an ML buffering layer over the accepted `Plan9.Fd` contract. It
does not reopen the completed release-11554 syscall and pipe gates. The
matching native references retained from the accepted design are:

- `/home/dharmatech/src/9front-11554` at
  `2191d72205863d2c53ea6ac36991cb4c13204c7c`;
- `sys/man/2/read` for positive short reads, EOF, and interruption ambiguity;
- `sys/man/2/pipe` for pipe message and hangup behavior; and
- the accepted Phase 1 source and qualification evidence for capability,
  attachment, and byte-I/O behavior.

The user-visible line and resource-bound rules are repository-owned OCaml API
decisions rather than claims copied from Plan 9 manuals. Record the actual
guest release and architecture at every native qualification gate; do not
silently infer correspondence from the reference checkout.

## Review, VM, and checkpoint protocol

Each subphase is one vertical slice owned by one executing task through source
implementation, host review, and native validation. For every subphase:

1. Record the starting Git and source state.
2. Implement only that subphase.
3. Run safe host-side static checks and inspect the complete diff.
4. Report the proposed source and any design deviation to the user, then
   pause before VM work.
5. Obtain explicit user confirmation of the exact writable P9QEMU instance,
   loopback address, intended action, and WHPX profile.
6. Follow the top-level and build-helper READMEs exactly, entering APE through
   `ape/psh`; transfer through `/mnt/term`, copy to native storage, never copy
   `.git`, and run configure, GNU Make, compiler, runtime, library, tests, and
   installation only on native Plan 9 storage.
7. Report the native results and stop; do not begin the next subphase.

Useful native build trees may be retained for incremental work through Phase
2.3. Final Phase 2.4 acceptance additionally uses a fresh, previously
nonexistent, artifact-free native destination populated from the exact
reviewed Windows worktree source set, with independently matching manifests
and no `.git`.

Installation is requested only in Phase 2.4. The prefix must be isolated and
nonexistent unless replacement is explicitly approved. The known-working
prefix `/usr/glenda/lib/unix/ocaml-4.14.3` remains protected whether it is
present or absent; matching before/after manifests must prove it was
unchanged. No VM snapshot, checkpoint replacement, merge, release
publication, or Caml9 change is authorized.

Do not commit or push implementation changes unless the user explicitly asks.
A later subphase must not begin from an unreviewed, dirty, known-broken, or
partially qualified predecessor.

## Final Phase 2 acceptance summary

The detailed criteria live in the foundation and Phase 2.4 handoff. At a
minimum, final acceptance requires:

- allocation-safe `Fd` attachment publishes one fully initialized channel or
  no channel, with no fallible allocation after successful commit;
- retained `Fd.t` aliases remain permanently revoked after successful
  transfer, while stale or losing prepared tokens never gain authority;
- channel buffering preserves exact bytes across every refill split and
  serializes reentrant operations without stale-state overwrite;
- `input` validates ranges first, performs no buffer movement or lower
  descriptor/native work for authorized zero length, returns buffered data
  without another read, and performs at most one lower read when empty;
- line and aggregate functions satisfy the exact EOF/newline/NUL/CR/trailing-
  newline rules and enforce their documented default and caller-supplied
  bounds without overflow or unbounded drain;
- exact-limit success and excess-limit failure preserve the specified stream
  position and complete already-buffered suffix, including zero limits and
  arbitrarily split lookahead;
- every native failure is mapped to the invoked channel operation, returned
  once without retry, and leaves the channel deterministically closeable;
- focused fake and native tests cover attachment races, active-operation and
  close reentrancy, arbitrary exceptions, buffer boundaries, long records,
  malformed lower results, EOF, limit failures, and descriptor cleanup;
- a fresh native build runs all existing Plan 9 regressions plus the complete
  Phase 0, Phase 1, and Phase 2 focused suites;
- symbol and source audits retain the accepted APE-independence claim for the
  native descriptor path without broadening it to the whole runtime;
- `plan9.cma` remains ML-only and only `plan9.cmi` is installed; and
- an approved installed-prefix smoke test builds and runs an ordinary public
  `Plan9.In_channel` consumer with installed `ocamlc`, `ocamlrun`, and exactly
  `-I +plan9 -linkall plan9.cma`, without a custom runtime or C tool escape.

If installation is not authorized, the installed-prefix criterion remains
open and Phase 2 must not be reported as fully accepted.

## Strictly excluded work

No Phase 2 subphase includes:

- `Plan9.Out_channel`, `Plan9.Stat`, `Plan9.Directory`, `Plan9.File`,
  `Plan9.Command`, or `Plan9.Env` migration;
- modification of existing `Plan9.Raw` or `Plan9.Process` semantics;
- process backend migration, stdout capture, line-oriented command helpers,
  child cleanup policy, `dup`, `rfork`, `exec`, `exits`, or `await` work;
- seeking, positions, length, file opening, creation, or stat operations;
- standard-input adoption, standard/foreign descriptor adoption, raw integers,
  ordinary-channel conversion, text-mode translation, or CRLF folding;
- implicit unbounded materialization or automatic channel close on a limit;
- new native primitives, a second runtime, removal of APE, native-code
  support, shared libraries, custom-runtime work, or systhreads;
- timing-sensitive note-interruption injection without a separately approved
  qualification gate; or
- VM snapshots, checkpoint replacement, branch merge, release publication,
  or Caml9 source changes.

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
- buffer, lifecycle, error, limit, symbol, packaging, APE-independence, and
  descriptor-cleanup evidence relevant to that subphase;
- source-tree, transfer, prefix, VM, listener, and writable-disk postconditions;
- every deviation, uncertainty, open criterion, or skipped gate; and
- final worktree, index, branch, and remote-tracking status.

Phase 2.4 additionally reports installed-prefix evidence and ends with exactly
one recommendation:

- **Phase 2 accepted; ready to design process backend migration**;
- **implementation ready but native qualification still required**; or
- **Phase 2 blocked or rejected**, with the exact reason.

No report may claim that the entire runtime or library is APE-free. The
accepted claim remains scoped to the reviewed native descriptor path inside
the standard APE-linked runtime.
