# Phase 2.3 bounded `Plan9.In_channel` aggregate input handoff

Status: reviewed and accepted focused handoff; implementation has not begun

Reviewed Phase 2 documentation checkpoint:
`2b3c42ef032d41676abab721da6a70632b09443f`.

## Authority and required reading

Read completely before implementation:

- repository `AGENTS.md`, top-level `README.md`, and
  `build-aux/plan9/README.md`;
- `docs/design/plan9-native-io-foundation.md`;
- `docs/design/handoffs/plan9-native-in-channel-phase2.md`;
- the accepted Phase 2.1 ownership/buffered-input handoff and report; and
- the accepted Phase 2.2 bounded-lines handoff and report.

Phase 1 remains the fixed descriptor predecessor. Phase 2.4 is not authority
to publish anything early. If accepted documents or source disagree, stop and
report the exact discrepancy.

## Start gate

Begin only from a reviewed, implemented, natively qualified, coherent Phase
2.2 checkpoint. Record branch, `HEAD`, predecessor commit, upstream, recent
log, worktree/index state, and retained native-tree identity. The branch must
be `codex/plan9-native-io-foundation`, the checkout must be clean, and no
unrelated change may be present.

If the predecessor is uncommitted, dirty, partially tested, or not explicitly
accepted, stop. Do not reset, stash, clean, switch, or infer permission.

## Accepted predecessor facts

Phase 2.2 supplies one internal channel implementation with:

- allocation-safe `Fd` ownership transfer and deterministic close;
- a reusable scratch buffer and single common refill path;
- a channel-wide active-operation guard across allocations and lower reads;
- caller-buffer `input` with at most one refill;
- an overflow-safe bounded line accumulator and exact byte-`0x0a` semantics;
- exact-limit lookahead that consumes a terminator but leaves the first excess
  content byte buffered and unconsumed; and
- finite default line policy with invalid and excess errors.

Do not create a second buffer, refill path, line scanner, lifecycle guard, or
error mapper for aggregate operations. Extract shared internal helpers only
when the complete diff proves the accepted behavior remains identical.

## Delegated outcome

Extend the uninstalled `Plan9_in_channel` surface with:

```ocaml
val input_all :
  ?max_bytes:int -> t ->
  (string, Plan9_types.error) result

val input_lines :
  ?max_bytes:int -> ?max_line_bytes:int ->
  t -> (string list, Plan9_types.error) result
```

Defaults are exact:

- `input_all`: `max_bytes = 16_777_216`;
- `input_lines`: `max_bytes = 16_777_216`; and
- `input_lines`: `max_line_bytes = 1_048_576`.

This subphase completes internal Phase 2 functionality but does not publish
`Plan9.In_channel`, edit public docs, install, or add consumer probes.

## Authorized source boundary

Update only:

- `otherlibs/plan9/plan9_in_channel.mli`;
- `otherlibs/plan9/plan9_in_channel.ml`;
- `otherlibs/plan9/tests/in_channel_lifecycle_test.ml`;
- `otherlibs/plan9/tests/in_channel_io_test.ml`; and
- generated `otherlibs/plan9/.depend` only if target-native generation proves
  a real source reason.

No new source path or Makefile/archive change is expected. Public umbrella and
documentation paths belong to Phase 2.4.

## Shared bound validation

Use operation `Plan9.In_channel.input_all` or
`Plan9.In_channel.input_lines` as invoked.

For `max_bytes`:

- negative returns `Invalid_argument`, message
  `maximum byte count must be nonnegative: {max_bytes}`;
- greater than `Sys.max_string_length` returns `Invalid_argument`, message
  `maximum byte count exceeds Sys.max_string_length: {max_bytes}`.

For `input_lines` `max_line_bytes`:

- negative returns `Invalid_argument`, message
  `maximum line byte count must be nonnegative: {max_line_bytes}`;
- greater than `Sys.max_string_length` returns `Invalid_argument`, message
  `maximum line byte count exceeds Sys.max_string_length: {max_line_bytes}`.

Validate `max_bytes` first, then `max_line_bytes`, before lifecycle, allocation,
buffer inspection, or lower work. Every inclusive value from zero through
`Sys.max_string_length` is valid. Do not clamp, treat negative as unlimited,
or allocate the maximum eagerly.

The two `input_lines` bounds are independent. `max_line_bytes` may exceed
`max_bytes`; in that case the whole-input bound can dominate before the line
bound. The documented defaults remain finite public policy, independent of
the private scratch capacity.

## `input_all` semantics

`input_all channel` reads all bytes remaining until the EOF observed by that
call and returns one exact string. It includes newlines, carriage returns,
embedded NUL, and arbitrary byte sequences without decoding or translation.

It loops over buffered bytes and the accepted common refill path while the
channel's one active-operation guard remains installed. It uses a bounded,
overflow-safe accumulator with the same allocation rules as the accepted line
accumulator. It must not call the public guarded `input` recursively or use an
unbounded `Buffer`.

Exact bound behavior:

- zero bytes followed by observed EOF returns `Ok ""`;
- exactly `max_bytes` remaining bytes followed by observed EOF succeeds;
- if any byte exists beyond the allowed prefix, return `Other`, message
  `input exceeds maximum of {max_bytes} bytes`;
- consume and discard exactly the allowed prefix on that limit failure;
- leave the first excess byte and complete already-buffered suffix unread;
- do not read or drain beyond the lookahead needed to prove excess; and
- leave the channel open and deterministically closeable.

With `max_bytes = 0`, observed EOF succeeds with the empty string and any
available byte fails without consuming that byte.

Observed EOF is not permanently cached. A later call may read again and
observe appended descriptor data. `input_all` describes one call's observed
remaining stream, not an immutable file promise.

On a lower error after partial accumulation, return the error once under
`Plan9.In_channel.input_all`, discard the partial result, and do not restore
already consumed bytes. Interruption may additionally have unknown native
consumption. An arbitrary OCaml exception restores stable channel state and
is re-raised unchanged.

## `input_lines` semantics

`input_lines channel` returns all remaining lines as exact strings. It uses
the accepted binary line rules:

- only byte `0x0a` terminates a line and is omitted;
- CR, NUL, and every other byte are content;
- empty input returns `[]`;
- one newline returns `[""]`;
- consecutive newlines produce corresponding empty elements;
- a trailing newline does not add an extra final empty element; and
- an unterminated final line is returned.

The implementation must stream through the shared scanner. Do not implement
`input_lines` as unbounded `input_all` followed by splitting, and do not first
materialize a whole-input string merely to enforce a per-line limit. The
accumulated reversed list, current bounded line, total byte count, and scratch
buffer all remain owned by one active channel operation.

### Whole-input accounting

`max_bytes` counts every source byte consumed for the result, including each
newline terminator. It therefore bounds line contents plus delimiter bytes and
also bounds the maximum number of returned empty lines.

An exact total bound succeeds only if EOF has been observed at that boundary.
If another byte exists, including newline, return `Other`, message
`input exceeds maximum of {max_bytes} bytes`, consume/discard exactly the
allowed total prefix, and leave the first excess byte plus the complete
already-buffered suffix unread.

### Per-line accounting

`max_line_bytes` counts each returned line body and excludes its newline. A
line of exactly that length succeeds if the next byte is newline or observed
EOF. A next non-newline byte returns `Other`, message
`input line exceeds maximum of {max_line_bytes} bytes`, after consuming the
allowed line prefix and leaving the first excess byte plus the complete
already-buffered suffix unread.

The bound resets only after consuming a newline. It applies equally to a
terminated or unterminated final line.

### Limit precedence

If one candidate byte would exceed both the whole-input and per-line bounds,
report the whole-input error first. More generally:

1. validate caller arguments;
2. account whole-input capacity for the next source byte;
3. account line-body capacity if the byte is not newline; and
4. consume the byte only after both owning bounds permit it.

This ordering makes stream position and error identity independent of scratch
and native-write boundaries. A newline counts against total before it can
terminate a line; if total capacity is exhausted, that newline is retained
unconsumed and the whole-input error wins.

### Zero-bound matrix

- total `0`, immediate EOF: `Ok []`;
- total `0`, any byte including newline: whole-input limit error with the byte
  unconsumed;
- positive total, line `0`, immediate newline: one empty line;
- positive total, line `0`, immediate EOF: `Ok []`;
- positive total, line `0`, immediate non-newline: line-limit error with the
  byte unconsumed.

## Allocation and result construction

Both aggregate operations are bounded but must also avoid unnecessary peak
retention:

- grow byte storage geometrically or in bounded chunks with checked
  subtraction-based arithmetic;
- never allocate a whole default-sized buffer eagerly;
- for `input_lines`, finalize one exact string per completed line, prepend it
  to a reversed list, and release the mutable line accumulator before starting
  the next line when practical;
- reverse the completed list once at observed EOF;
- do not manufacture a final empty line merely because EOF follows a consumed
  newline;
- keep all scanned values GC-safe across allocations and lower reads; and
- release partial aggregate references on every result path so the open
  channel retains only fixed scratch storage and its unread suffix.

The public bound controls source bytes, not exact OCaml heap overhead. List
cells, string headers, and bounded growth slack remain proportional to the
chosen finite byte policy. This is a real resource policy even though it is
not a byte-for-byte heap quota.

No promise converts `Out_of_memory` into `Plan9.error`. An allocation exception
restores channel state before reraise but does not roll back consumed stream
bytes.

## Error, reentrancy, and close behavior

All lower errors preserve kind/message and use the invoked aggregate
operation. Malformed fill counts use the accepted protocol template with the
aggregate operation. No failure is retried.

The one channel active-operation guard covers every aggregate allocation,
scan, result construction, and refill. Reentrant `input`, `input_line`,
`input_all`, `input_lines`, or close receives the accepted in-progress error
without nested descriptor work. Normal success, observed EOF, explicit limit,
and lower-error results restore stable open. Close semantics remain unchanged.

Limit failure never closes automatically. The caller may inspect or continue
from the exact first excess byte, but the discarded prefix is not recoverable
through this channel. Deterministic close remains required.

## Exact error additions

| Condition | Operation | Kind | Message |
| --- | --- | --- | --- |
| negative total bound | invoked aggregate operation | `Invalid_argument` | `maximum byte count must be nonnegative: {max_bytes}` |
| total bound above representability | invoked aggregate operation | `Invalid_argument` | `maximum byte count exceeds Sys.max_string_length: {max_bytes}` |
| negative line bound | `Plan9.In_channel.input_lines` | `Invalid_argument` | `maximum line byte count must be nonnegative: {max_line_bytes}` |
| line bound above representability | `Plan9.In_channel.input_lines` | `Invalid_argument` | `maximum line byte count exceeds Sys.max_string_length: {max_line_bytes}` |
| input exceeds total bound | invoked aggregate operation | `Other` | `input exceeds maximum of {max_bytes} bytes` |
| line exceeds per-line bound | `Plan9.In_channel.input_lines` | `Other` | `input line exceeds maximum of {max_line_bytes} bytes` |

The existing Phase 2.1/2.2 lifecycle, range, line, malformed-fill, and native
errors remain byte-for-byte unchanged. Add no shared error constructor.

## Required fake-backend tests

Extend `in_channel_lifecycle_test.ml`. For `input_all`, prove:

- invalid, zero, one, default, exact, plus-one, and
  `Sys.max_string_length` bound paths without overflow;
- empty EOF, embedded NUL, newlines, arbitrary bytes, and many short fills
  produce the exact string;
- exact limit plus EOF succeeds, while one-byte excess from an existing buffer
  or lookahead refill returns the same error and stream position;
- zero limit distinguishes EOF from available data without consuming excess;
- lower errors before and after accumulated progress map once without retry;
  and
- accumulator allocation callbacks and lower callbacks reject reentrancy.

For `input_lines`, prove:

- empty, one newline, consecutive newlines, trailing newline, terminated and
  unterminated lines, CR, NUL, and arbitrary split schedules;
- lines and total input spanning many scratch fills remain exact;
- negative/oversized total is rejected before negative/oversized line, life-
  cycle, or lower work;
- exact per-line bounds succeed before newline or EOF, while exact total
  bounds succeed only before EOF;
- line excess and total excess preserve the first excess byte;
- simultaneous line/total excess chooses total and leaves the candidate byte
  unconsumed;
- newline at an exhausted total bound produces total failure, not a successful
  line;
- every zero-bound case above;
- a huge number of empty lines remains bounded by total source bytes;
- errors after completed lines discard the partial list and do not retry;
- reentrant calls and close never see or mutate partial aggregate state; and
- designated exception identity plus forced minor/major GC and compaction
  preserve stable ownership and exact completed data.

Use small explicit bounds for exhaustive boundary matrices and separately
prove omission selects the documented defaults without eager allocation.

## Required native tests

Extend `in_channel_io_test.ml`. Through production pipes/channels, prove:

- `input_all` round-trips empty, binary, multiline, and payloads larger than
  the scratch capacity;
- deliberate writer boundaries do not change aggregate results;
- exact custom total plus writer-close EOF succeeds;
- total plus-one failure leaves the first excess byte for later `input`;
- `input_lines` returns exact empty, terminated, consecutive-empty,
  trailing-newline, embedded-NUL, CR, long-line, and unterminated-final-line
  results;
- exact line/total custom limits, line excess, total excess, and precedence
  behave as specified across native boundaries;
- every limit/error path can be closed deterministically; and
- repeated complete cycles leave the sorted `/fd` inventory unchanged.

Run every existing Plan 9 regression and the complete accepted Phase 2.1 and
2.2 suites. Ordinary qualification does not include timing-sensitive note
injection.

## Build, source, and packaging review

No Makefile, archive-order, primitive, runtime, or install selection change is
expected. Regenerate `.depend` only through target-native procedure if source
dependencies actually change, and never hand-edit it.

Before VM work, inspect and record that:

- default and caller-supplied bounds are finite, exact, and validated first;
- whole and per-line counting includes/excludes newline exactly as documented;
- simultaneous-limit precedence is independent of buffer splits;
- all cursor, capacity, total, and list-count arithmetic is overflow-safe;
- no aggregate uses an unbounded helper or eager maximum allocation;
- exact-limit lookahead leaves the first excess byte and complete buffered
  suffix unread;
- lower errors are rebound once to the aggregate operation and never retried;
- active-state and exception paths preserve the accepted lifecycle;
- no Phase 2.4 public or installed work appeared; and
- the archive remains ML-only with only `plan9.cmi` install-selected.

## Execution sequence and mandatory pause

1. Record exact accepted Phase 2.2 source/Git state.
2. Implement only the authorized source boundary and inspect the full host
   diff.
3. Report design decisions/deviations and pause for explicit VM instance,
   loopback address, intended action, and WHPX confirmation.
4. If required, regenerate target `.depend` through `ape/psh` and the exact
   documented GNU Make lane, return only that file, and repeat host review.
5. Transfer the exact reviewed set without `.git` to native storage, build,
   run focused and full regression tests, and collect archive, packaging,
   symbol, and descriptor-cleanup evidence. Do not install.
6. Report VM/disk/listener postconditions and stop. Do not begin Phase 2.4,
   commit, push, merge, or publish without explicit user instruction.

Any authoritative source change invalidates earlier native evidence and
requires an exact reviewed retransmission.

## Completion report

Report:

- exact branch, starting/ending commits, Phase 2.2 predecessor, and reviewed
  handoff checkpoint;
- files changed and complete internal signature;
- accumulator, counting, list-construction, precedence, and lookahead design;
- exact defaults, invalid matrices, exact-limit, excess, and stream-position
  results;
- complete fake/native focused and regression results;
- callback, exception, GC, native-error, no-retry, and close evidence;
- `.depend`, archive, primitive, ML-only, and installed-CMI evidence;
- descriptor inventory and VM postconditions;
- all deviations, uncertainty, skipped criteria, and open gates; and
- one conclusion: accepted Phase 2.3 checkpoint, implementation awaiting
  native qualification, or blocked/rejected with exact reason.

## Strict exclusions

This subphase excludes:

- public `Plan9.In_channel`, umbrella edits, public docs, installation, or
  consumer/privacy probes;
- changes to Phase 2.1 ownership/input/close or Phase 2.2 line semantics except
  reviewed shared-helper extraction with identical behavior;
- new error kinds, primitives, raw syscalls, runtime C, or `Fd` changes;
- process migration, capture, commands, file/stat/directory/output layers;
- ordinary channels, raw descriptors, standard input, text translation,
  seeking, length, positions, or finalizers;
- automatic close or unbounded drain on a limit;
- timing-sensitive note injection without separate authorization; and
- snapshots, checkpoint replacement, merge, release publication, or Caml9
  changes.

If excluded work appears necessary, stop and report the evidence.
