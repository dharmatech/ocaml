# Phase 2.2 bounded `Plan9.In_channel.input_line` handoff

Status: proposed focused handoff for review; implementation has not begun

## Authority and required reading

Read completely before implementation:

- repository `AGENTS.md`, top-level `README.md`, and
  `build-aux/plan9/README.md`;
- `docs/design/plan9-native-io-foundation.md`, especially the
  `Plan9.In_channel` target contract and Phase 2 gate;
- `docs/design/handoffs/plan9-native-in-channel-phase2.md`; and
- the accepted Phase 2.1 handoff and its final implementation/qualification
  report.

The accepted Phase 1 attachment and owner-I/O contracts remain inherited.
Later Phase 2 handoffs do not authorize aggregate or public-surface work here.
If any accepted source or document conflicts, stop and report the exact
conflict.

## Start gate

Begin only from a reviewed, implemented, natively qualified, coherent Phase
2.1 checkpoint. Verify and record:

- branch `codex/plan9-native-io-foundation`;
- exact `HEAD` and accepted Phase 2.1 commit;
- clean worktree and index;
- expected upstream and recent log;
- no unrelated source, generated file, or native artifact in the Windows
  checkout; and
- the retained native build tree, if reused, is halted, uniquely owned by this
  project, and derived from the accepted Phase 2.1 source set.

If Phase 2.1 is uncommitted, unreviewed, partially qualified, or dirty, stop.
Do not clean, stash, reset, switch, or infer acceptance.

## Accepted predecessor facts

Phase 2.1 supplies:

- one abstract channel owning exactly one committed `Plan9_fd` attachment;
- an allocation-safe `of_fd` transition and permanently revoked public aliases;
- a reusable fixed scratch buffer with ordered unread cursors;
- a channel-wide active-operation guard covering callbacks and allocations;
- one lower refill implementation that validates counts, rebinds errors to the
  invoking channel operation, and never retries;
- `input` with range-first validation, buffered progress, at most one refill,
  and exact destination mutation; and
- deterministic close with active/inactive/terminal state.

Do not copy or bypass the Phase 2.1 refill, state guard, error mapper, scratch
buffer, or close implementation. A need to change a predecessor contract is a
design issue, not incidental line-parser work.

## Delegated outcome

Extend only the uninstalled `Plan9_in_channel` surface with:

```ocaml
val input_line :
  ?max_bytes:int -> t ->
  (string option, Plan9_types.error) result
```

The default `max_bytes` is exactly `1_048_576`. The bound is the maximum line
body length in bytes and excludes the optional terminating byte `0x0a`.
`input_line channel` is therefore finite by default while retaining concise
ordinary use.

This subphase does not add `input_all`, `input_lines`, a public umbrella
module, a new `error_kind`, or installation work.

## Authorized source boundary

Update only:

- `otherlibs/plan9/plan9_in_channel.mli`;
- `otherlibs/plan9/plan9_in_channel.ml`;
- `otherlibs/plan9/tests/in_channel_lifecycle_test.ml`;
- `otherlibs/plan9/tests/in_channel_io_test.ml`; and
- generated `otherlibs/plan9/.depend` only if target-native dependency
  generation proves an actual source reason.

No new test source path is expected. The Makefile, archive order, umbrella,
public docs, runtime, primitives, and existing non-Phase-2 tests should remain
byte-for-byte unchanged unless native dependency evidence proves otherwise.

## Bound validation

Use operation `Plan9.In_channel.input_line`. Validate `max_bytes` before
channel lifecycle, buffer inspection, allocation, or lower read:

- negative values return `Invalid_argument`, message
  `maximum byte count must be nonnegative: {max_bytes}`;
- values greater than `Sys.max_string_length` return `Invalid_argument`,
  message
  `maximum byte count exceeds Sys.max_string_length: {max_bytes}`; and
- every value from zero through `Sys.max_string_length` is a valid policy.

Braced values are decimal substitutions. The default is subjected to the same
logic and must be proved valid on the target. Do not clamp, silently substitute
another limit, interpret a negative value as unlimited, or allocate the full
limit eagerly.

After bound validation, apply the accepted Phase 2.1 lifecycle guard. A valid
bound on a closing or closed channel still returns the exact lifecycle error.
An invalid bound takes precedence over lifecycle state and native work.

## Exact binary line semantics

Only byte `0x0a` terminates a line. The returned string omits that byte.
Byte `0x0d`, embedded NUL, invalid UTF-8, and every other byte are ordinary
line content. No text-mode translation or Unicode decoding occurs.

The exact cases are:

| Remaining bytes | Result |
| --- | --- |
| immediate observed EOF | `Ok None` |
| `\n` | `Ok (Some "")` |
| `abc\n` | `Ok (Some "abc")` |
| `abc` followed by observed EOF | `Ok (Some "abc")` |
| `abc\n` followed by EOF | first call `Some "abc"`, next call `None` |
| `\n\n` | two empty lines, then `None` |
| `a\000b\n` | `Ok (Some "a\000b")` |
| `a\r\n` | `Ok (Some "a\r")` |

Delimiter recognition must work when the newline is the first or last byte of
a scratch fill, when it follows an arbitrary sequence of positive short
fills, and when the line is much longer than the scratch capacity.

Do not permanently cache observed EOF. A later call may perform another lower
read and observe appended data, as required by Phase 2.1.

## Bounded accumulator

Use an explicitly bounded, overflow-safe accumulator that grows on demand.
Its storage may double or use bounded chunks, but it must satisfy:

- never request or represent a capacity above `max_bytes` merely for line
  content;
- check remaining capacity with subtraction, not overflowing addition;
- preserve exact bytes and order;
- avoid one allocation per input byte;
- allocate only under the channel's active-operation guard;
- initialize every scanned block to GC-safe contents before later allocation;
- construct exactly one returned string for a successful line; and
- release accumulator references when the operation completes or fails so the
  channel retains only its fixed scratch buffer and unread suffix.

An implementation may scan a buffered segment before copying it, then append
only the content preceding a newline. It must not convert the whole stream to
a string, use an unbounded `Buffer`, or call public `input` recursively in a
way that would conflict with the active-operation guard. Reuse the internal
refill primitive with the current operation name.

## Exact-limit and excess behavior

The bound applies to content, not the newline:

- a line of exactly `max_bytes` followed by newline succeeds and consumes the
  newline;
- a line of exactly `max_bytes` followed by observed EOF succeeds as an
  unterminated final line;
- if the next byte after exactly `max_bytes` content is not newline, return
  `Other` with message
  `input line exceeds maximum of {max_bytes} bytes`;
- consume and discard exactly the allowed prefix on that limit failure;
- leave the first excess non-newline byte and the complete already-buffered
  suffix in the channel scratch buffer, unconsumed for a later operation; and
- do not scan or drain the rest of the oversized line and do not close the
  channel automatically.

When exactly the allowed prefix ends at the scratch boundary, perform only the
lookahead needed to distinguish newline, EOF, native error, or excess. A
lookahead read may fill the scratch with more data, but only a newline is
consumed on exact-limit success; the first excess content byte and every byte
already buffered after it remain unread on limit failure.

Zero limit is not a special unlimited mode:

- immediate EOF returns `None`;
- immediate newline returns `Some ""` and consumes it; and
- any other next byte returns the exact limit error without consuming that
  byte.

The limit error is a normal result, not an exception. The channel remains open
and deterministically closeable. Because the discarded prefix is not restored,
retrying `input_line` resumes at the first excess byte, which is now the start
of the next logical operation's view, followed by the preserved buffered
suffix.

## Native errors and partial consumption

Every lower error is rebound to operation `Plan9.In_channel.input_line` while
preserving kind and exact message. Do not retry interruption or any other
failure.

`input_line` is not transactional. If it consumed buffered content before a
later refill failed, that prefix is not restored and no partial string is
returned. The first still-buffered unread byte remains available. An
interrupted native refill may additionally have consumed an unknown amount of
underlying input under the accepted Plan 9 rule.

Malformed lower fill counts use the Phase 2.1 protocol message but the
`Plan9.In_channel.input_line` operation. An arbitrary OCaml exception restores
stable channel state before physical-identity reraise; already advanced buffer
cursors are not rolled back merely to mask non-transactional progress.

## Reentrancy and close

The Phase 2.1 active-operation guard covers the entire line operation,
including accumulator growth and every refill. During active `input_line`:

- reentrant `input` or `input_line` returns
  `input channel operation is already in progress` under the invoked operation;
- reentrant close returns the same in-progress message under
  `Plan9.In_channel.close`;
- no nested lower read or close occurs; and
- the outer scanner's accumulator and scratch cursors remain authoritative.

Input during active/inactive close and input after terminal close retain the
Phase 2.1 exact errors. Successful, EOF, limit, and lower-error results all
restore stable open before returning. Do not alter close semantics here.

## Exact error additions

| Condition | Operation | Kind | Message |
| --- | --- | --- | --- |
| negative bound | `Plan9.In_channel.input_line` | `Invalid_argument` | `maximum byte count must be nonnegative: {max_bytes}` |
| bound above representability | `Plan9.In_channel.input_line` | `Invalid_argument` | `maximum byte count exceeds Sys.max_string_length: {max_bytes}` |
| line content exceeds bound | `Plan9.In_channel.input_line` | `Other` | `input line exceeds maximum of {max_bytes} bytes` |

All Phase 2.1 lifecycle, malformed-fill, and lower-native messages remain
unchanged except that the invoked operation is `Plan9.In_channel.input_line`.
Do not add `Limit_exceeded` or another shared error constructor in Phase 2.

## Required fake-backend tests

Extend `in_channel_lifecycle_test.ml`. At minimum, prove:

- invalid bounds `-1` and `max_int` return the exact errors before lifecycle,
  accumulator allocation visible to callbacks, or lower work;
- valid bounds `0`, `1`, default, and `Sys.max_string_length` reach lifecycle
  validation without overflow;
- immediate EOF, empty line, consecutive empty lines, one terminated line,
  one unterminated line, and trailing-newline behavior match the table;
- CR, embedded NUL, all byte values, and invalid UTF-8 are preserved exactly;
- newlines at every position around the scratch boundary and across arbitrary
  positive short-read schedules are recognized once;
- a line spanning many scratch fills produces one exact string;
- exact custom limits succeed before newline and EOF, including limit zero;
- one-byte excess returns the exact error, consumes exactly the allowed
  prefix, leaves the first excess byte and complete buffered suffix unread,
  and performs no unbounded drain;
- excess already present in the scratch and excess discovered by a separate
  lookahead refill have identical stream position;
- newline as the lookahead byte is consumed and succeeds, whereas another byte
  is retained and fails;
- a native error before any byte and after several buffered segments is mapped
  once without retry, with the documented non-transactional position;
- a malformed negative or oversized refill count uses the line operation and
  never becomes an index;
- callbacks during scan allocation and every lower refill reject reentrant
  input and close without mutating accumulator or cursors;
- an allocated designated exception restores stable state and retains
  physical exception identity; and
- forced minor/major GC and compaction during long-line accumulation preserve
  exact bytes and ownership.

Use small custom limits for deterministic boundary matrices. Separately test
that omitting the argument selects exactly the documented default without
allocating a default-sized buffer eagerly.

## Required native tests

Extend `in_channel_io_test.ml`. Through a production pipe/channel, prove:

- empty input and immediate writer close return `None`;
- one newline, consecutive newlines, terminated lines, trailing newline, and
  an unterminated final line match exact semantics;
- embedded NUL and carriage return are preserved;
- a line longer than 4096 bytes is assembled across native buffer fills;
- write boundaries deliberately split before, on, and after newline without
  changing results;
- exact small custom limits followed by newline and writer-close EOF succeed;
- one-byte excess returns the exact limit error and a later raw `input` from
  the same channel begins with the retained first excess byte;
- channel close after every success, EOF, limit failure, and native test path
  leaves no descriptor; and
- repeated deterministic cycles leave the sorted `/fd` inventory unchanged.

Do not provoke timing-sensitive native read interruption in the ordinary
suite. Fake evidence proves no-retry mapping; actual note injection remains a
separately authorized gate.

Run every existing Plan 9 regression and all accepted Phase 2.1 tests
unchanged.

## Build, source, and packaging review

No archive-order or installed-file change is expected. Native dependency
generation may add a source-derived dependency only if the new signature
requires it; never hand-edit `.depend`.

Before VM work, inspect and record that:

- the default is a finite policy value and is not confused with scratch size;
- invalid limits precede lifecycle and native work;
- all capacity and cursor arithmetic is overflow-safe;
- exact-limit lookahead consumes only newline and preserves the first excess
  non-newline byte plus the complete buffered suffix;
- no path drains an oversized line or allocates beyond the chosen bound;
- all delimiters are byte `0x0a` only;
- every lower failure is returned once under the line operation;
- active-state exception handling uses ordinary reraise and no stale overwrite;
- no Phase 2.1 public, close, archive, primitive, runtime, or installation
  contract changed; and
- `plan9.cma` remains ML-only with only `plan9.cmi` selected for installation.

## Execution sequence and mandatory pause

1. Record the exact accepted Phase 2.1 Git and source state.
2. Implement only this handoff and inspect the complete host diff.
3. Report source decisions and deviations, then pause for explicit VM
   instance, loopback, action, and WHPX confirmation.
4. If `.depend` needs regeneration, use the exact native APE/GNU Make workflow,
   return only the generated file, and repeat authoritative host review.
5. Transfer the final reviewed source without `.git` to native storage, run
   the focused tests and full regressions, and record symbol, archive,
   packaging, and `/fd` cleanup evidence. No install is required.
6. Halt through Drawterm `fshalt`, wait for the exact QEMU PID, verify the
   selected seven listeners closed when the VM is stopped, report, and stop.

Any host source change after transfer invalidates the corresponding native
result. Do not patch the guest as the authority and do not begin Phase 2.3.

## Completion report

Report:

- exact branch, starting/ending identities, reviewed handoff checkpoint, and
  accepted Phase 2.1 predecessor;
- files changed and final internal signature;
- accumulator strategy, growth arithmetic, delimiter scan, and active-state
  behavior;
- exact default, validation, exact-limit, excess, and stream-position evidence;
- complete fake and native test results;
- every native/refill error, callback, exception, and no-retry result;
- `.depend`, archive, primitive, ML-only, and installed-CMI evidence;
- descriptor inventory and VM postconditions;
- all deviations, uncertainties, skipped criteria, and open gates; and
- one conclusion: accepted Phase 2.2 checkpoint, implementation awaiting
  native qualification, or blocked/rejected with exact reason.

## Strict exclusions

This subphase excludes:

- `input_all`, `input_lines`, whole-input aggregation, or aggregate limits;
- public umbrella publication, public docs, installation, or consumer probes;
- any new `error_kind`, primitive, raw syscall, runtime C, or `Fd` change;
- process migration, capture, command helpers, file/open/stat layers;
- text translation, CRLF folding, Unicode decoding, standard input, raw
  descriptors, ordinary channels, or finalizers;
- automatic close or unbounded drain after a limit failure;
- timing-sensitive note injection without separate approval; and
- snapshots, checkpoint replacement, merge, release publication, or Caml9
  changes.

If excluded work appears necessary, stop and report the evidence.
