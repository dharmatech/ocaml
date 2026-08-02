# OCaml Plan 9 process stdout capture

Status: adopted working design for review; implementation has not started

Source handoff:
`C:\Users\dharm\src\caml9\docs\design\handoffs\ocaml-plan9-process-run-capture.md`

The Caml9 source remains unchanged. This OCaml copy is the authoritative
working record for the feature branch.

## Repository identities

- Published base branch: `plan9-4.14.3-000`
- Published base commit:
  `a98e773a80311653d7a78763bd017328b5c26b52`
- Remote verification: `origin/plan9-4.14.3-000` resolved to the same commit
  before the feature branch was created.
- Feature branch: `codex/plan9-process-run-capture`

The feature branch must not be merged and no replacement OCaml release may be
published until Caml9 has reviewed the branch and its native Plan 9 validation
results.

## Goal

Add one native Plan 9 process operation that runs a program with a literal
argument vector and captures its standard output in OCaml memory.

The motivating Caml9 call is:

```ocaml
Plan9.Process.run_capture
  ~program:"/bin/ndb/query"
  ~args:[| "-a"; "sys"; sysname; "ether" |]
  ()
```

Caml9 will split the returned string into lines and compare Ethernet addresses
in ML. The OCaml library must contain no NDB-specific behavior.

## Existing ownership model

`Plan9.Process.run` already distinguishes three process outcomes:

- `Run_finished` contains the terminal native wait message;
- `Run_incomplete` retains the exact managed process handle after a
  nonterminal launch or wait result; and
- `Run_terminal_failure` retains the handle after terminal wait-queue loss.

An outer `Error` from `spawn` or `run` means that no child created by the call
remains. `run_capture` must preserve this contract.

Capturing stdout introduces one new failure interval: after `rfork` and exec
confirmation, but before the parent reaches EOF on the stdout pipe. Such a
failure cannot be represented by `run`, because the stdout stream is no longer
recoverable even though the managed child can still require a later `wait`.

## Proposed public API

```ocaml
type captured_run = {
  outcome : run;
  stdout : string;
}

type capture_failure =
  | Capture_launch_incomplete of launch_incomplete
  | Capture_read_error of error

type run_capture =
  | Capture_complete of captured_run
  | Capture_failed of {
      process : t;
      stdout_prefix : string;
      reason : capture_failure;
    }

val run_capture :
  program:string ->
  args:string array ->
  unit ->
  (run_capture, error) result
```

The type and value may both be named `run_capture`, following the existing
`type run` and `val run` convention.

`Capture_complete` means that the parent observed EOF and `stdout` contains
every byte written to standard output before it closed. Its nested `outcome`
may still be `Run_incomplete` or `Run_terminal_failure`; reaching stdout EOF
does not imply that the managed wait completed.

`Capture_failed` means that complete stdout is unavailable. It retains the
exact managed process handle. `stdout_prefix` contains, in order and without
decoding, the bytes read successfully before capture stopped. The prefix may
be empty. A failed capture stream cannot be resumed; callers may continue
process ownership only with the ordinary `Plan9.Process.wait` operations.

`Capture_launch_incomplete` is used when the exec handshake did not establish
a normal launched child and stdout capture therefore did not complete.
`Capture_read_error` is used after exec confirmation when draining the stdout
pipe failed.

An outer `Error` continues to mean that no child created by this call remains.
It covers validation and setup failures before `rfork`, and a known exec
failure only after the existing coordinator has reaped that child.

## Successful capture semantics

On `Capture_complete`, `stdout` is an exact byte string:

- embedded NUL bytes are preserved;
- empty output is `""`;
- newlines are neither added nor removed;
- an unterminated final line is unchanged; and
- no decoding, trimming, line splitting, or normalization occurs.

The operation buffers all standard output in memory. It is intended for
bounded output. Output that cannot fit in an OCaml string or the native
accumulation buffer is a capture failure that preserves the managed process
handle and the prefix accumulated before the failure. Large or unbounded
output should use direct file redirection or a future streaming API.

Standard error remains inherited.

## Failure and ownership matrix

| Failure point | Public result | Child ownership |
| --- | --- | --- |
| argument validation, pipe creation, or descriptor preparation before `rfork` | outer `Error` | no child exists |
| `rfork` failure | outer `Error` | no child exists |
| known exec failure, successfully reaped | outer `Error` | no child remains |
| exec or handshake failure not reaped | `Capture_failed` with `Capture_launch_incomplete` | exact handle retained |
| stdout read or accumulation failure | `Capture_failed` with `Capture_read_error` | exact handle retained |
| stdout EOF followed by interrupted or otherwise unresolved wait | `Capture_complete` with `outcome = Run_incomplete ...` | exact handle retained by `outcome` |
| stdout EOF followed by terminal wait-queue loss | `Capture_complete` with `outcome = Run_terminal_failure ...` | exact handle retained by `outcome` |
| stdout EOF and ordinary child completion, including nonempty status | `Capture_complete` with `outcome = Run_finished ...` | terminal result retained |

A nonempty child status is not an API error. It is a `Run_finished` outcome
whose `wait_msg` does not satisfy `Plan9.wait_succeeded`, accompanied by the
complete captured stdout.

## Native implementation

Use direct Plan 9 `pipe`, `dup`, `rfork`, `exec`, `read`, and the existing
managed wait coordinator.

1. Validate and copy the program and literal argument vector before native
   process work.
2. Reserve the native pending-child identity before `rfork`.
3. Create the existing close-on-exec failure-handshake pipe and a second pipe
   for stdout.
4. Prepare every internal descriptor so descriptor holes at 0, 1, or 2 cannot
   alias an internal pipe end or cause a later cleanup to close standard
   output accidentally.
5. In the child, close both parent-only read ends, duplicate the stdout pipe's
   write end onto descriptor 1, close the now-unused original write end, and
   execute the program directly.
6. In the parent, publish the pending-child record as the first action after a
   positive `rfork` result, then close both child-only write ends.
7. Complete the bounded exec-failure handshake.
8. After exec confirmation, drain stdout to EOF while the child runs. Do not
   wait first: output larger than the pipe buffer must not deadlock.
9. Leave the blocking section, adopt the native pending record through the
   existing pure-ML coordinator, and finish the managed child through the
   existing `run`/`wait` result mapping.

If the exec handshake is incomplete, do not block indefinitely trying to
finish capture. Close the parent capture end and return the handle-preserving
capture failure. If stdout reading fails, close the capture end and return the
handle-preserving failure without waiting first; a child that continues
writing after loss of its reader must not deadlock `run_capture`.

The private native backend may gain a capture-aware spawn result or an
equivalent dedicated entry point. This is not a public descriptor, pipe, or
streaming API. The existing public `spawn`, `run`, `stdout`, `Inherit`, and
`Truncate` behavior and types remain unchanged.

The descriptor preparation should be factored so the existing handshake pipe,
truncate destination, and new capture pipe share one checked descriptor-hole
implementation rather than two subtly different cleanup paths.

## Validation design

All compiler, runtime, library, and installed-prefix validation runs on native
Plan 9 storage. `/mnt/term` is transfer-only; `.git` is never transferred.

### Pure-ML coordinator tests

Extend the fake native backend to cover:

- complete capture followed by ordinary wait completion;
- complete capture followed by a foreign completion before the managed
  completion, proving that `run_capture` uses the same coordinator;
- complete capture followed by interrupted wait, with the exact handle
  retained and a successful later retry;
- deterministic capture-read failure with an exact stdout prefix and exact
  managed handle;
- exec failure that is reaped and therefore becomes an outer `Error`; and
- exec failure, handshake failure, or wait failure that cannot be reaped and
  therefore remains handle-preserving.

### Primitive validation tests

Exercise every new or changed built-in entry point with forged values. Verify
validation before native work, including:

- empty or NUL-containing program paths;
- malformed or NUL-containing argument arrays;
- forged capture policy values;
- forbidden `rfork` flags; and
- malformed unit or native result values where applicable.

### Ordinary native integration tests

Extend the repository-owned native helper and integration suite to cover:

- empty output;
- multiline output;
- embedded-NUL output;
- an unterminated final line;
- output comfortably larger than the native pipe buffer;
- literal arguments containing shell metacharacters;
- a nonempty child status with complete captured output;
- a known exec failure with no lost child and no leaked descriptor;
- descriptor holes at 0, 1, and 2;
- repeated capture calls with exact descriptor and ownership cleanup; and
- clean final managed, native-pending, foreign-FIFO, and `/fd` postconditions.

The helper should generate binary and large patterned output directly. The
operation under test must not use temporary files.

### Opt-in native interruption qualification

Timing-sensitive note delivery remains a separate, explicitly authorized
qualification gate.

Two cases are required:

1. The child writes a known prefix, keeps stdout open, and sends `interrupt`
   to the parent while the parent is blocked draining the pipe. The result
   must be `Capture_failed` with `Capture_read_error`, the exact prefix, and
   the exact managed handle; an ordinary later wait must close ownership.
2. The child closes stdout first, then sends `interrupt` while the parent is
   blocked in the existing managed wait coordinator. The result must be
   `Capture_complete` with the exact output and a `Run_incomplete` interrupted
   wait outcome; a later wait must complete through the same handle.

No production fault switch, public raw descriptor, or independent waiter is
added for testing.

### Documentation and compatibility checks

Update the installed interface documentation, `otherlibs/plan9/README.md`,
and `otherlibs/plan9/REFERENCE.md`. Verify that:

- `plan9.cma` remains ML-only;
- ordinary users need no `-custom`, `-use-runtime`, C compiler, linker, or
  wrapper compiler;
- the standard Plan 9 `ocamlrun` contains the primitive;
- existing `Process.run` and `Process.Truncate` tests remain unchanged in
  behavior; and
- a consumer built against the isolated installed prefix can call
  `run_capture`.

## Explicitly out of scope

This change does not add:

- a public raw file-descriptor or pipe API;
- capture-capable asynchronous `spawn`;
- multiple-process pipeline composition;
- standard-input, standard-error, or streaming capture;
- a caller-supplied output limit;
- line splitting or other text interpretation;
- additional file-output modes;
- PATH search, shell execution, quoting, expansion, or APE process dispatch;
- temporary-file capture; or
- Caml9- or NDB-specific code.

## Pre-implementation gates

Before editing runtime or library code:

- review this API and failure matrix with the user;
- inspect the qualified Plan 9 source/manual definitions for `pipe`, `dup`,
  close-on-exec descriptors, interrupted pipe reads, and writes after the
  reader closes;
- confirm the dedicated P9QEMU instance, loopback address, and explicit WHPX
  profile before any VM operation; and
- agree on an isolated install prefix so no known-working compiler is
  overwritten.

## Completion report

When the branch is ready for Caml9 review, report:

- this adopted design-document path;
- the exact base branch and commit;
- the feature branch and commit;
- the final public API;
- every changed file;
- native Plan 9 test commands and results;
- any departure from this design and why it was necessary; and
- final worktree, index, branch, and remote-tracking status.
