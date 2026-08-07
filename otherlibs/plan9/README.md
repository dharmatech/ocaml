# Plan 9 native library

This directory builds the Plan 9-only `Plan9` module. The installed bytecode
archive is ML-only and lives in the `plan9` standard-library subdirectory:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

That normal link does not require `-custom`, `-use-runtime`, C stubs, a C
compiler, or a linker. On the Plan 9 target, the standard `ocamlrun` provides
the native primitives used by the ML-only archive.

For user-facing examples and the complete public API, see the
[`Plan9` library reference](REFERENCE.md). This README records implementation
semantics, validation details, and qualification evidence for maintainers.

## `Plan9.Env`

`Plan9.Env` reads and mutates the calling process's live `/env` namespace.
Each lookup enumerates `/env` and, when present, opens the corresponding file.
Each set creates or truncates that file, and each removal calls `Sys.remove`
on that file. There is no environment mirror, mutation registry, APE
`getenv`/`putenv` call, command wrapper, or child-specific inference.

The representation is lossless:

| Native meaning | OCaml value | `/env` bytes |
| --- | --- | --- |
| absent | `Ok None` | no file |
| empty list | `Ok (Some [])` | zero bytes |
| empty scalar | `Ok (Some [""])` | one NUL |
| scalar | `Ok (Some ["x"])` | `x\000` |
| list | `Ok (Some ["x"; "y"])` | `x\000y\000` |

The decoder also accepts an unterminated final element. The encoder always
emits a trailing NUL for every element. It preserves arbitrary non-NUL bytes,
whitespace, newlines, empty elements, and element boundaries.

Lookups do not retry namespace races. A name absent from the fresh directory
enumeration returns `Ok None`; a file removed after that enumeration but before
the read produces its I/O error.

Names must not be empty, `.`, `..`, contain `/`, or contain NUL. Other Plan 9
names, including `fn#...`, are allowed. Invalid names and values return an
error with kind `Invalid_argument`.

`Plan9.Env.get_exn` returns the value, raises `Not_found` for absence, and
raises `Plan9.Error` for validation or I/O failure. The result-returning
operations preserve the `Sys_error` message produced by the existing runtime
file-I/O machinery. Removing an absent file is an error. A failed direct write
may leave the live file truncated or partially written; the module provides no
rollback overlay.

This phase deliberately relies on the existing runtime's file-I/O path. It
does not claim that the runtime or executable is APE-free. `Sys`, `Unix`,
`Sys.command`, and `Unix.putenv` retain their existing portable behavior.

## `Plan9.Raw`

`Plan9.Raw.copy_environment ()` is the only public current-process rfork
operation. It performs exactly `rfork(RFENVG)`, creates no child, and accepts
no caller-supplied mask.

`Plan9.Raw.exec ~program ~argv` directly replaces the current process and
preserves the caller's exact nonempty argument vector, including `argv.(0)`.
It performs no PATH search, shell expansion, quoting, or APE process dispatch.
An empty program or vector, embedded NUL, malformed primitive value, or
unrepresentable native length is rejected before native exec.

There is no public raw waiter, integer rfork-mask operation, child-returning
rfork path, `RFMEM`, `RFNOWAIT`, or `RFNOMNT` facility.

## `Plan9.Fd`

`Plan9.Fd.t` is an abstract shared owner of a native descriptor. It is not a
descriptor integer and cannot be passed to `Stdlib`, `Sys`, `Unix`, or an
ordinary OCaml channel. Copies alias one lifecycle: closing any public alias
closes them all, and repeated close is idempotent. Cleanup is explicit and
deterministic; the type has no descriptor-closing finalizer.

`Plan9.Fd.pipe ()` returns two bidirectional Plan 9 pipe peers. It deliberately
does not encode Unix-style read-end and write-end roles. A descriptor attached
to a higher-level native owner permanently rejects public read, write, close,
and reattachment through every retained alias, without exposing the private
attachment mechanism.

`read` and `write` accept only `bytes` and validate `pos` and `len` without an
overflowing addition. The valid relationship is:

```text
pos >= 0
len >= 0
pos <= Bytes.length buffer
len <= Bytes.length buffer - pos
```

After range and ownership validation, a zero-length call returns `Ok 0`
without native work. A positive public call performs at most one native
transfer. The private transfer boundary can therefore produce successful
progress smaller than the logical `len`; callers complete a larger logical
operation with later calls and honor every returned count.

A positive short read is ordinary progress and `Ok 0` for a positive request
is EOF. A successful read changes exactly its returned prefix in the caller's
destination. Read errors leave that destination unchanged, but an interrupted
native read may already have consumed an unknown amount of input, so automatic
retry is unsafe.

Writes never mutate their source. A native write count smaller than the exact
count requested by that call is an `Other` error, and the wrapper never writes
the remainder. Any failed or interrupted write is non-transactional and may
have transferred an unknown prefix, so it likewise must not be retried
automatically.

Wrapper-generated errors use these exact public templates; braced fields are
decimal substitutions:

| Condition | Operation and kind | Message |
| --- | --- | --- |
| invalid range | invoked `Plan9.Fd.read` or `Plan9.Fd.write`; `Invalid_argument` | `invalid byte range: buffer length {buffer_length}, position {pos}, length {len}` |
| malformed read result | `Plan9.Fd.read`; `Protocol_error` | `invalid descriptor read result: requested {requested} bytes, staging has {staging_length} bytes, returned count {count}` |
| malformed write result | `Plan9.Fd.write`; `Protocol_error` | `invalid descriptor write result: requested {requested} bytes, returned count {count}` |
| native short write | `Plan9.Fd.write`; `Other` | `descriptor write was short: requested {requested} bytes, wrote {written} bytes` |

Native failures retain the high-level operation and exact captured Plan 9
message.

## `Plan9.Process`

`Plan9.Process.spawn` synthesizes literal `argv.(0)` from `program`;
`Plan9.Process.run` drives the same synchronous wait coordinator. Both use the
fixed native policy `RFPROC | RFFDG | RFREND`, followed immediately by direct
exec in the nonreturning child. Output is initially limited to inherited
stdout or a parent-opened truncate-file destination.

Every post-rfork nonterminal result retains its stable logical process handle.
The native pending-child record is allocated before rfork and published as
the first positive-PID parent action. The logical identity is never reused,
so wait records are routed without attaching an unknown completion to a
later process after kernel PID reuse.

The coordinator owns the native wait queue synchronously while managed or
native-pending owners remain. Successful spawn does not create a background
reaper. A particular wait retains unknown-PID completions in a bounded FIFO;
a full FIFO is retryable backpressure and consumes no additional native
record. `wait_any` returns queued foreign records before awaiting, and
`take_foreign_completions` drains them in order.

Exact native `no living children` terminalizes every adopted and native
pending owner as queue loss. Interruption consumes neither a completion nor
the managed handle. Invariant and malformed-record failures remain distinct
failed-closed states, preserve unresolved ownership, and prevent further
native await.

The error handshake is a bounded, versioned `P9E1` frame. Descriptor
preparation remains correct when the pipe or output file initially occupies
descriptor 0, 1, or 2. Native wait timing fields are the measured unsigned
32-bit millisecond values zero-extended into OCaml `int64`; the complete
native status string is preserved.

Mixing `Plan9.Process` ownership with `Sys.command`, `Unix.wait`, APE wait
functions, or any other wait consumer is unsupported until every managed and
native-pending owner is terminal. The containing runtime remains APE-linked;
only this process boundary uses the direct Plan 9 syscall entries.

## Focused test

On a configured Plan 9 source tree:

```sh
"$MAKE" -C otherlibs/plan9 TEST_SUFFIX=phase1_manual_001 test
```

The complete command includes:

- the live `/env` suite covers absent, empty, scalar, list, unterminated,
  live reread, set, remove, invalid-name, invalid-element, arbitrary-byte, and
  `fn#...` behavior;
- the descriptor fake-backend suite covers range and lifecycle precedence,
  one-transfer chunking, EOF, short and malformed results, exact error
  mapping, transferred ownership, callback reentrancy, lifecycle restoration,
  close interaction, GC, and exception identity;
- the native descriptor suite covers bidirectional peers, binary data,
  caller-owned multi-call completion, preserved write boundaries, EOF,
  zero-length behavior, alias and attachment ownership, GC, and repeated
  descriptor cleanup;
- a pure-ML fake backend deterministically covers argv0 synthesis,
  out-of-order routing, memoized waits, interruption, adoption, queue loss,
  foreign FIFO backpressure, queued-first `wait_any`, failed-closed malformed
  records, and `run`;
- primitive-forgery tests call every built-in entry point with malformed
  values and verify fail-before-native-work validation, including all
  forbidden rfork bits;
- a private header-only P9E1 codec suite drives the same writer and decoder
  used by the runtime through partial writes, clean EOF, one-byte reads, I/O
  failure, truncation, invalid tag and length, trailing data, and invalid
  callback-count cases; and
- a native integration suite uses bounded test-only helpers to cover RFENVG
  isolation, literal high-level and raw argv, missing and invalid exec,
  inherited and truncate-file stdout, every nonempty descriptor-hole mask
  over descriptors 0, 1, and 2, out-of-order completion routing, terminal
  memoization, native status and timing fields, `run`, known exec-failure
  cleanup, and clean descriptor/child postconditions.

Use a new 1-40 character ASCII letter, digit, or underscore suffix for each
run. The environment test cleans up its two resulting `/env` names on both
success and failure. The integration suite likewise uses only suffix-scoped
temporary files and an environment name and removes them at closeout.

The native helper and frame-codec executable are test artifacts only. They
are neither added to `plan9.cma` nor installed, and ordinary Plan9 consumers
still need no C compiler, linker, `-custom`, or alternate runtime. Actual
asynchronous note delivery remains outside the ordinary deterministic suite.
The same repository-owned helper and integration executable provide the
bounded, opt-in wait-interruption evidence driver:

```sh
"$MAKE" -C otherlibs/plan9 test-native-interruption
```

It starts one managed short-lived child, sends `interrupt` only to its parent
after a bounded delay, proves that the exact handle survives the interrupted
native await, retries through the same coordinator, and requires clean
ownership closeout. Run it only in an explicitly authorized qualification
gate. Handshake I/O edge cases use the shared private codec suite; no
production fault switch or independent waiter is added.

## Accepted Phase 1 validation

The exact Plan 9 library subtree
`c7c4d0b98ee94c7ca0fe601244af917dc02ee33f` was built, tested, installed
under an isolated prefix, and exercised through the installed interface on
2026-07-24. Installed `ocamlobjinfo` reported `Force custom: no` and no extra
C objects, C options, or dynamically loaded libraries. An ordinary installed
consumer compiled and ran while fail-closed C-tool sentinels remained
uninvoked.

The cross-environment checks also read an rc-created list and an APE-created
scalar from live `/env`, then proved that a direct `Plan9.Env` mutation was
visible through `/env` while APE's cached environment remained unchanged.
Child inheritance and native process creation are intentionally not claimed
by this phase.
