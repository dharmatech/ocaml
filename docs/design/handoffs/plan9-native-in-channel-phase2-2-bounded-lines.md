# Phase 2.2 bounded `Plan9.In_channel.input_line` handoff

Status: refined focused handoff under renewed review; Phase 2.2 implementation
has not begun; accepted Phase 2.1 predecessor
`d5fde712098a96259f986bb1bf301e931b4b63c5`

Reviewed Phase 2 umbrella documentation checkpoint:
`2b3c42ef032d41676abab721da6a70632b09443f`.

Refined Phase 2.2 documentation checkpoint: not yet recorded.

## Refined documentation checkpoint gate

The umbrella checkpoint above remains the accepted Phase 2 design base, but it
predates the focused refinements in this handoff. Phase 2.2 implementation must
not begin from an uncommitted or merely conversational version of this file.
After the renewed review is complete:

1. create one documentation-content commit containing the exact final refined
   handoff and its agreed foundation/roadmap consistency edits;
2. record that content commit's exact hash in this handoff, the Phase 2
   roadmap, and the foundation through a follow-up checkpoint-recording commit;
   and
3. require the implementation starting `HEAD` to contain both commits with a
   clean worktree and index.

The follow-up commit cannot serve as the content checkpoint because a commit
cannot contain its own hash. Until the `not yet recorded` line above is
replaced by the exact documentation-content hash and the recording commit is
in branch history, the start gate is closed.

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
- exact `HEAD` and accepted Phase 2.1 commit
  `d5fde712098a96259f986bb1bf301e931b4b63c5`;
- exact refined Phase 2.2 documentation-content checkpoint and its follow-up
  recording commit from the gate above;
- clean worktree and index;
- expected upstream and recent log;
- no unrelated source, generated file, or native artifact in the Windows
  checkout; and
- the retained native build tree, if reused, is halted, uniquely owned by this
  project, has the exact canonical path and final common-schema identity
  recorded for the accepted retained Phase 2.1 tree, uses the recorded
  unchanged read-only dependency prefix, and is derived from the accepted
  Phase 2.1 source set.

If Phase 2.1 is uncommitted, unreviewed, partially qualified, or dirty, stop.
Do not clean, stash, reset, switch, or infer acceptance.

## Accepted predecessor facts

Phase 2.1 supplies:

- one abstract channel owning exactly one committed `Plan9_fd` attachment;
- an allocation-safe `of_fd` transition and permanently revoked public aliases;
- a reusable fixed scratch buffer with ordered unread cursors;
- a channel-wide active-operation guard covering callbacks and allocations;
- one lower refill path, currently inlined in `input`, that validates counts,
  rebinds errors to the invoking channel operation, and never retries;
- `input` with range-first validation, buffered progress, at most one refill,
  and exact destination mutation; and
- deterministic close with active/inactive/terminal state.

Do not copy or bypass the Phase 2.1 refill, state guard, error mapper, scratch
buffer, or close implementation. A need to change a predecessor contract is a
design issue, not incidental line-parser work.

The accepted Phase 2.1 source inlines its lifecycle gate and refill path in
`input`, and its lifecycle and malformed-fill constructors currently select
the `Plan9.In_channel.input` operation directly. This subphase explicitly
authorizes a behavior-preserving extraction inside `plan9_in_channel.ml` of:

- one operation-parameterized lifecycle check and active-state installation
  path;
- one operation-parameterized refill path using the existing scratch buffer;
  and
- operation-parameterized lifecycle and malformed-fill error constructors.

Both `input` and `input_line` must use the extracted paths. The refactor must
not add a second lower read implementation, change `input` range precedence,
allow more than one refill in a caller-buffer `input`, alter cursor movement,
or weaken any accepted Phase 2.1 callback, exception, close, retained-result,
or bytecode property. Extraction is implementation structure, not authority
to revise the predecessor contract.

Do not implement the common lifecycle path as a higher-order wrapper that
requires a newly allocated operation closure or result block before the
lifecycle decision. In particular, preserve the accepted positive and zero-
length `input` pre-entry allocation and callback schedule. A successful
guarded entry must install `Input_active` and return only an immediate,
nonallocating success signal; it must not allocate an `Ok ()`, tuple, closure,
or other success block after the state write. The caller must then install its
operation exception handler immediately, before accumulator creation, refill,
result construction, or any other allocation, callback, safe point, pending-
action processing, or fallible work. A lifecycle-rejected entry does not
install active state and retains the rejection ownership rule below.

For positive-length `input` and every valid `input_line` operation, the shared
guarded-entry path must perform its final `Stable_open` recheck immediately
before installing `Input_active`, with no allocation, callback, safe point,
pending-action processing, or fallible work between the recheck and immediate
state write. From that write through the caller's immediate exception-handler
installation, the successful helper return and caller instructions must also
be allocation-, callback-, polling-, pending-action-, and fallibility-free.
Valid zero-length `input` continues to check lifecycle without installing
active state and returns the unit-scoped retained `Ok 0` binding without
allocation or lower work. Helper extraction must not route that fast path
through a newly allocated guard result.

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

Use operation `Plan9.In_channel.input_line`. Perform the pure integer
classification of `max_bytes` before channel lifecycle, buffer inspection,
accumulator or success-side allocation, or lower read:

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

Record the target fact that `Sys.max_string_length < max_int` before a test
forms the first representable value above the string limit. Bound
classification and message construction must handle `min_int` directly; do
not negate it, take its absolute value, or perform another transformation that
can overflow merely to recognize or print a negative bound.

Constructing the enclosing error, its record, and its decimal message for an
invalid bound may itself allocate and may therefore process a pending action
or callback. The invocation has not installed the active guard and owns no
lifecycle or cursor restoration. Any callback-selected channel state wins;
normal publication of the prepared bound error and any exception escaping its
construction must not restore or overwrite that state. This is the same
pure-argument rejection rule accepted for Phase 2.1 range errors.

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

```text
0 <= used <= logical_capacity <= max_bytes
```

- never request or represent a logical capacity above `max_bytes` merely for
  line content; for a chunked strategy, the sum of simultaneously retained
  addressable chunk capacities is the logical capacity;
- check remaining capacity with subtraction, not overflowing addition;
- when more capacity is required, choose a capacity at least as large as the
  required used length and strictly larger than the old capacity, unless the
  old capacity already equals `max_bytes`; limits zero and one must neither
  loop nor manufacture capacity above the bound;
- preserve exact bytes and order;
- avoid one allocation per input byte;
- make monotonic linear progress through the line: do not rescan committed
  content, do not repeatedly grow a contiguous block by a constant increment,
  and keep aggregate scan/copy/growth work linear in the bytes examined and
  retained by the operation;
- keep both the segment scanner and the enclosing accumulation/refill loop
  iterative or tail-recursive, with no live call stack proportional to line
  length, scratch-fill count, or positive-short-read count;
- allocate only under the channel's active-operation guard;
- initialize every scanned block to GC-safe contents before later allocation;
- construct exactly one returned string for a successful line; and
- release accumulator references when the operation completes or fails so the
  channel retains only its fixed scratch buffer and unread suffix.

A returned string must never alias the reusable channel scratch buffer or any
mutable storage that the channel can refill or reuse. If the implementation
uses `Bytes.unsafe_to_string` to transfer an exact accumulator block into the
result, it must own that block exclusively, retain no mutable alias that can
escape or be reused, and perform no later mutation through the original
`bytes` value. A capacity block with unused slack cannot be transferred as the
exact returned string.

The public bound controls line-body bytes and the accumulator's logical
content capacity, not exact OCaml heap overhead. A contiguous resize may
temporarily keep both the old and replacement byte blocks live, and final
string/result construction may coexist briefly with accumulator storage. Each
content block, the final string length, and the logical accumulator capacity
must remain within the selected bound; do not claim that total transient heap
occupancy is at most `max_bytes`.

An implementation may scan a buffered segment before copying it, then append
only the content preceding a newline. It must not convert the whole stream to
a string, use an unbounded `Buffer`, or call public `input` recursively in a
way that would conflict with the active-operation guard. Reuse the internal
refill primitive with the current operation name.

Factor the byte-`0x0a` search as one private policy-neutral segment scanner over
the existing unread scratch range. Give it an explicit maximum scan window. It
must report enough information for its caller to distinguish a newline within
that window, exhaustion of the available scratch segment, and exhaustion of
the permitted scan window, including the exact scanned-prefix length. It must
not advance a cursor, refill, construct an error or public result, or decide
whether the byte just outside the window is permitted. The caller owns boundary
candidate inspection and line-versus-total limit policy. In particular, Phase
2.2 may accept a newline immediately after the allowed line body, whereas
Phase 2.3 must be able to reject that same newline when it lies beyond an
exhausted whole-input bound. Phase 2.3 must reuse this scanner rather than
create a second delimiter implementation.

The scanner entry and result arithmetic is exact. At entry require:

```text
0 <= unread_start <= unread_end <= Bytes.length scratch
0 <= scan_window
available = unread_end - unread_start
```

Every outcome reports `scanned` satisfying
`0 <= scanned <= min(available, scan_window)`. A newline outcome means that
`scanned` is the number of non-newline prefix bytes, excludes the delimiter,
and identifies byte `0x0a` exactly at `unread_start + scanned`, with
`scanned < available` and `scanned < scan_window`. In the absence of a newline
outcome, scratch exhaustion means `scanned = available`, scan-window exhaustion
means `scanned = scan_window`, and both equalities may hold simultaneously.
Derive all positions from the validated entry invariants without an overflowing
addition or an out-of-range scratch access. When it exists inside the unread
range, the byte at `unread_start + scan_window` is a caller-owned boundary
candidate and is never part of the scanner's permitted window.

Scratch exhaustion and scan-window exhaustion are not necessarily mutually
exclusive. If the available unread segment length exactly equals the remaining
window and no newline occurs within it, report that simultaneous boundary (or
return equivalent information from which the caller must derive both facts).
The caller must consume the permitted segment and perform the required
lookahead refill; it must not treat the tie alone as EOF, excess, or permission
to inspect nonexistent scratch data.

Scanning alone never advances a cursor. For a nonterminal content segment,
first complete any required bounded accumulator growth and validated
nonallocating copy, then advance `unread_start` immediately with no intervening
allocation, callback, lower work, or other fallible operation. A growth,
callback, or copy exception before that commit leaves the current scratch
segment unread; content committed by earlier iterations remains consumed.

For a segment that completes a terminated line, allocate and fill the exact
returned string, construct `Some`, and construct the enclosing `Ok` while the
body bytes and delimiter in that current segment remain unread. Prepare an
outcome containing the complete result and exact validated final cursor value,
and keep the outcome, channel, result, accumulator data, and every live copy
source rooted while leaving the operation exception handler normally through
its bytecode `POPTRAP`. That handler exit occurs while `Input_active` remains
visible and before the current body or delimiter cursor commit. A pending
callback at `POPTRAP` therefore receives the ordinary in-progress rejection;
if its selected exception escapes, the still-active handler restores stable
state and reraises it physically unchanged while the complete current segment,
including its delimiter, remains unread. Earlier committed segments are not
restored.

Only after normal `POPTRAP` completion may the code commit the prepared body-
plus-delimiter cursor value, restore stable state, and immediately publish the
prepared result. That entire suffix contains no allocation, handler exit,
callback, polling, pending-action processing, arithmetic not already dominated
by validated invariants, or other fallible work. This rule also applies to an
immediate empty line and to exact-limit success when the boundary candidate is
newline.

After the scanner and caller have established a limit failure, construct the
complete dynamic `Error` result while the current allowed-prefix portion and
boundary candidate remain unread, and prepare the exact validated discard
cursor. Leave the handler normally through `POPTRAP` with that result and cursor
rooted, `Input_active` still visible, and no current-prefix mutation. A callback
exception at that boundary restores stable state with the current allowed
prefix, first excess byte, and complete suffix unread. Only after normal
handler exit may the code commit the allowed-prefix discard, restore stable
state, and publish the prepared error through the same fallibility-free suffix.
The first excess byte and complete suffix remain unread. Earlier committed
segments remain consumed.

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

The same lookahead can also produce a malformed successful lower count. That
case returns the inherited protocol error under the line operation with empty
unread cursors; it is neither exact-limit success nor line-limit excess.

Every delimiter search is bound-aware. Search only the still-permitted content
window and then inspect the single boundary candidate separately, using
subtraction and branches rather than an overflowing `remaining + 1`
calculation. A newline at that candidate succeeds and is consumed. A
non-newline candidate fails immediately and remains unread even if another
newline occurs later in the buffered suffix. For example, `abcd\n` with
`max_bytes = 3` returns the limit error after consuming `abc` and leaves
`d\n` unread.

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

A validated successful refill count authorizes scanning only the scratch
prefix of exactly that length. In particular, count zero authorizes no scratch
byte and leaves normalized empty cursors, even if an adversarial fake backend
modified scratch before returning `Ok 0`. Neither that write nor any scratch
tail outside a later positive count may become input to this or a subsequent
operation.

The cursor-commit rule above still applies to the current segment. An exception
during required growth, copying, complete success construction, or complete
limit-error construction, including a selected exception processed at the
normal handler-exit `POPTRAP`, leaves that segment's exact uncommitted bytes
unread. The conforming post-`POPTRAP` final cursor/restoration/publication
suffix has no exception point. An exception after an earlier nonterminal
content commit does not reconstruct an already consumed prefix. When EOF must
first be observed after every line-body byte has already been accumulated and
committed, an exception during construction of the unterminated final-line
result or at its handler exit likewise does not restore that body. No partial
string is returned on any exception.

## Reentrancy and close

After valid-bound lifecycle acceptance, the Phase 2.1 active-operation guard
covers the entire line operation, including accumulator growth, delimiter
scanning, every refill, final string construction, `Some` construction, and
the complete enclosing success, limit-error, protocol-error, or rebound lower-
error result. During active `input_line`:

- reentrant `input` or `input_line` returns
  `input channel operation is already in progress` under the invoked operation;
- reentrant close returns the same in-progress message under
  `Plan9.In_channel.close`;
- no nested lower read or close occurs; and
- the outer scanner's accumulator and scratch cursors remain authoritative.

`input_line` during active `input`, active `input_line`, active or inactive
close, and terminal close uses the invoked operation with the accepted input-
family lifecycle messages. Existing `input` during active `input_line`, active
or inactive close, and terminal close retains its Phase 2.1 errors. Pure range
or bound rejection continues to precede those lifecycle states.

A lifecycle-rejected invocation never installs the guard and owns no state or
cursor restoration. Constructing its lifecycle error may allocate and process
a callback; the error describes the state at its decision point, while any
callback-selected later state wins and must not be overwritten. This retains
the accepted Phase 2.1 rejection rule after helper extraction.

Prepare the entire normal result and any final cursor description inside the
operation handler while the guard is active. Leave that handler normally
through `POPTRAP` with active state still visible and before a terminal cursor
commit. Then perform only the applicable prepared cursor commit, restore stable
open, and return the already prepared result immediately. This publication
suffix has no allocation, handler exit, callback, safe point, pending-action
processing, or other fallible work. An exception restores stable state only if
this invocation successfully installed the guard, then reraises the physically
identical selected exception through ordinary `RERAISE`. Do not alter close
semantics here.

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

- invalid bounds `min_int`, `-1`, `Sys.max_string_length + 1`, and `max_int`
  return the exact decimal-substituted errors before lifecycle, accumulator
  allocation, buffer inspection, or lower work while preserving callback-
  selected state during error construction; form the first-above value only
  after recording the target representability fact required above;
- valid bounds `0`, `1`, default, and `Sys.max_string_length` reach lifecycle
  validation without overflow;
- valid `input_line` during active `input`, active `input_line`, active and
  inactive close, and terminal close returns the exact invoked-operation
  lifecycle error without lower work; invalid bounds retain precedence in
  every one of those states;
- during active `input_line`, valid reentrant `input`, `input_line`, and close
  are rejected without nested lower work, while invalid `input` ranges and
  invalid `input_line` bounds retain pure-argument precedence;
- immediate EOF, empty line, consecutive empty lines, one terminated line,
  one unterminated line, and trailing-newline behavior match the table;
- a call returning `None` does not cache EOF: a later call may refill and
  return newly available data;
- EOF observed after returning an unterminated `Some` line is likewise not
  cached: after both an ordinary unterminated line and an exact-limit
  unterminated line, a later call refills and returns newly available data as a
  new line;
- CR, embedded NUL, every non-newline byte value, and invalid UTF-8 are
  preserved exactly, while byte `0x0a` alone is consumed as the delimiter;
- newlines at every position around the scratch boundary and across arbitrary
  positive short-read schedules are recognized once; the fake trace records
  the actual configured lower counts and call count for each schedule;
- a line spanning many scratch fills produces one exact string;
- terminated and unterminated bodies of at least `16_384` bytes delivered by
  one-byte positive fills complete with exact contents, exact lower-call
  traces, and no stack growth proportional to the body or refill count;
- exact custom limits succeed before newline and EOF, including limit zero;
- one-byte excess returns the exact error, consumes exactly the allowed
  prefix, leaves the first excess byte and complete buffered suffix unread,
  and performs no unbounded drain;
- a delimiter or first excess byte already buffered completes without another
  lower read;
- an ordinary `input` can consume a prefix from one refill and leave
  `abc\nrest` buffered; the next `input_line` returns `abc` without another
  lower read, and the following `input` observes `rest` unchanged;
- a newline after the first excess byte cannot cause success; for example,
  `abcd\n` at limit `3` fails and leaves `d\n` unread;
- exact-limit newline success preserves its suffix: `abc\nrest` at limit `3`
  returns `abc`, consumes only the newline after the allowed body, and leaves
  `rest` unread for the next `input`; record the exact fake lower-read count
  across both operations;
- a terminated line followed by another terminated line in the same scratch
  fill is returned by two `input_line` calls without a second lower read;
- excess already present in the scratch and excess discovered by a separate
  lookahead refill have identical stream position;
- newline as the lookahead byte is consumed and succeeds, whereas another byte
  is retained and fails;
- when exact-limit lookahead refills scratch with `\nrest`, the operation
  succeeds, consumes only the newline, and a following ordinary `input`
  returns `rest` without another lower read; record the exact refill count
  across both operations;
- when the allowed prefix ends exactly with simultaneous scratch/window
  exhaustion, separate fake schedules make the lookahead refill return
  newline, EOF, a positive fill beginning with excess, a lower `Error`, a
  negative count, and an oversized count; prove the exact success, retained-
  excess, rebound-error, or protocol-error result and cursor state for every
  branch;
- with one fake fill containing `abcd\nnext\n`, `max_bytes = 3` first returns
  the limit error and leaves `d\nnext\n`; a second `input_line` at limit `3`
  returns `d`, and a third call with an omitted bound returns `next`, all
  without another lower refill and with the exact call count recorded;
- a native error before any byte and after several buffered segments is mapped
  once without retry, with the documented non-transactional position;
- a fake lower refill that raises a designated allocated exception before any
  progress, after one or more committed content segments, and during exact-
  limit lookahead restores stable state, reraises the physically identical
  exception, preserves the exact documented stream position, and is never
  retried by that invocation; a later operation must prove the resulting
  position in every schedule;
- a lower error whose adversarial backend first writes bytes into scratch maps
  once under the line operation, leaves the cursors normalized empty, never
  exposes those bytes, and permits a later valid refill;
- a malformed negative or oversized refill count uses the line operation,
  never becomes an index, leaves the cursors normalized empty, never exposes
  adversarial scratch bytes, and permits a later valid refill;
- an adversarial fake refill that writes scratch and returns `Ok 0`, both at
  immediate EOF and during exact-limit lookahead, exposes none of those bytes,
  leaves normalized empty cursors, returns the applicable `None` or exact-
  limit unterminated `Some` result, and permits a later shorter positive refill
  without exposing its stale tail;
- callbacks during accumulator growth, final-result construction, every lower
  refill, and every deterministically injectable scanner/loop callback point
  reject valid reentrant `input`, `input_line`, and close without stale
  accumulator or cursor mutation;
- a callback processed at the operation handler's normal `POPTRAP` observes
  active input and, if it raises, leaves a terminated current segment or limit-
  failure current prefix exactly unread as specified above;
- an allocated designated exception restores stable state, retains physical
  exception identity, and leaves the next operation at the exact cursor
  position specified above for a nonterminal copy, terminated-result
  construction, limit-error construction, and EOF-final-result construction;
- retained short and multi-scratch returned strings remain byte-for-byte
  unchanged across later refills, later `input_line` calls, forced minor/major
  GC, and compaction, proving that neither result aliases scratch nor reusable
  mutable accumulator storage;
- forced minor/major GC and compaction during long-line accumulation preserve
  exact bytes and ownership.

Construct and dispatch every long generated fake schedule in linear time. The
accepted `Direct_descriptor.add_read_action` helper currently appends one
action with list `@`; do not invoke that append once per byte or fill for the
stress/default schedules. Use one stateful generated read action or bulk-build
a queue in linear time and consume it from the head in constant time. Record
the generator, setup complexity, dispatch complexity, and exact produced-count
trace so quadratic test-harness work cannot masquerade as scanner or
accumulator behavior.

Use small custom limits for deterministic boundary matrices. Separately and
mechanically prove the omitted-argument default: a generated line body of
exactly `1_048_576` bytes followed by newline succeeds, while a generated body
of `1_048_577` bytes followed by newline returns the exact default-limit error
after discarding only the allowed prefix and leaves the first excess byte
unread. Both calls must omit `max_bytes`, use bounded generated fill schedules
rather than a giant source literal, and record exact lower counts. Separately,
an omitted-bound immediate-EOF or empty-line call must prove that no default-
sized accumulator is allocated eagerly. Complete all payload, fake-schedule,
descriptor, channel, and GC-stabilization setup before taking an allocation
baseline, then bracket only the `input_line` invocation. If a target allocation
counter is used, first prove and record that it includes large byte-block
allocations, record its exact before/after values, and require the invocation's
delta to be less than `1_048_576` bytes; pair that measurement with source
evidence identifying every reachable allocation on the path. If no trustworthy
target counter is available, exact target-bytecode/control-flow evidence that
the immediate-EOF or empty-line path cannot reach a default-sized accumulator
allocation is the permitted substitute, and the unavailable measurement must
be reported. Do not add a production or test-only allocation hook.

If an allocation-triggered callback schedule cannot be injected
deterministically on the target, classify it explicitly as a conditional
runtime schedule and supply source plus bytecode control-flow evidence that
the successful entry helper returns an immediate without a post-state-write
allocation and is followed by immediate handler installation, the active guard
dominates every accumulator and final-result allocation, complete terminated-
success and limit-error construction dominates the normal active-state
`POPTRAP`, and that handler exit dominates the specified final cursor commit
and nonallocating prepared-result publication suffix. The same evidence must
enumerate every allocation, application, poll, safe point, and pending-action
site in the scanner and accumulation/refill loop. Every such site must be
dominated by active state and the operation handler; if its selected callback
raises, the current uncommitted segment remains unread, earlier committed
segments remain consumed, stable state is restored, and the exception is
reraised with physical identity. Do not silently count a forced collection
without an observed callback as that schedule.

## Required native tests

Extend `in_channel_io_test.ml`. Through a production pipe/channel, prove:

- empty input and immediate writer close return `None`;
- one newline, consecutive newlines, terminated lines, trailing newline, and
  an unterminated final line match exact semantics;
- embedded NUL and carriage return are preserved;
- a line longer than 4096 bytes is assembled across native buffer fills;
- retained short and longer-than-4096-byte line results remain unchanged after
  subsequent line reads, scratch refills, forced GC, and compaction;
- write boundaries deliberately split before, on, and after newline without
  changing results;
- exact small custom limits followed by newline and writer-close EOF succeed;
- `abc\nrest` at limit `3` returns `abc`, and a later internal channel `input`
  observes `rest` unchanged;
- one-byte excess returns the exact limit error and a later internal channel
  `input` begins with the retained first excess byte and complete buffered
  suffix;
- channel close after every success, EOF, limit failure, and native test path
  leaves no descriptor; and
- repeated deterministic cycles leave the sorted `/fd` inventory unchanged.

Do not provoke timing-sensitive native read interruption in the ordinary
suite. Fake evidence proves no-retry mapping; actual note injection remains a
separately authorized gate.

Run every existing Plan 9 regression and all accepted Phase 2.1 tests
unchanged.

Native writer-call boundaries are test inputs, not proof that the production
pipe returned identical lower-read boundaries. Record the exact writer
segmentation and observed public results without claiming an unobservable
one-to-one read split. The fake-backend trace supplies deterministic evidence
for exact lower returned counts and arbitrary split schedules.

## Build, source, and packaging review

No archive-order or installed-file change is expected. Native dependency
generation may add a source-derived dependency only if the new signature
requires it; never hand-edit `.depend`.

### Pre-VM host review

Before VM work, inspect the complete host source and test definitions and
record that:

- the default is a finite policy value and is not confused with scratch size;
- the fake tests mechanically encode omitted-bound exact-default and default-
  plus-one behavior and the isolated immediate-EOF/empty-line eager-allocation
  proof procedure above;
- the fake tests encode the complete `min_int` through first-above-string-limit
  boundary matrix, while source inspection shows comparison and decimal
  rendering without overflow and every invalid limit preceding lifecycle and
  native work;
- all capacity and cursor arithmetic is overflow-safe;
- accumulator growth, segment scanning, and the enclosing refill loop make
  monotonic linear progress and use call-stack space independent of line
  length and positive-fill count;
- the scanner entry/result inequalities, newline index, exhaustion equalities,
  and caller-owned boundary candidate match the exact contract above;
- every long generated fake schedule has linear setup, constant-time dispatch,
  and exact produced-count tracing rather than repeated list append;
- exact-limit lookahead consumes only newline and preserves the first excess
  non-newline byte plus the complete buffered suffix;
- no path drains an oversized line or gives a content block, final string, or
  logical accumulator capacity a length above the chosen bound; transient heap
  overhead is not misreported as the public content bound;
- all delimiters are byte `0x0a` only;
- every lower `Error` is returned once under the line operation, and every
  raised lower exception restores stable state and is reraised with physical
  identity; neither form is retried and both preserve the documented
  non-transactional cursor position;
- every validated refill exposes only its exact returned prefix; a zero count
  leaves empty cursors and no adversarial scratch content reachable;
- active-state exception handling uses ordinary reraise and no stale overwrite;
- operation-parameterized helper extraction leaves accepted `input` range,
  pre-entry allocation/callback schedule, immediate handler installation, one-
  refill, copy, cursor, result-publication, and close behavior unchanged;
- the private segment scanner is the one delimiter implementation available
  for later Phase 2.3 reuse, is policy-neutral, never moves a cursor, and never
  searches or decides policy past its explicit scan window; simultaneous
  scratch/window exhaustion is represented without inventing a candidate;
- source control flow places every explicit scanner and accumulation/refill
  allocation, application, and safe point under active state and the operation
  handler, and the target-audit plan below will enumerate compiler-emitted poll
  and pending-action sites plus their exceptional cursor outcomes;
- every returned string owns immutable result storage independent of scratch
  and future accumulator storage; any `Bytes.unsafe_to_string` use satisfies
  the exclusive-ownership and no-later-mutation rule above;
- all final line results and mapped or synthesized errors are completely
  allocated while the active guard and operation handler are installed;
  terminated-success and limit-error results precede the normal active-state
  `POPTRAP`, which precedes their exact final cursor commit and the
  nonallocating stable-state publication suffix;
- no Phase 2.1 public, close, archive, primitive, runtime, or installation
  contract changed; and
- the build/archive/install-selection definitions retain an ML-only
  `plan9.cma` with only `plan9.cmi` selected for installation.

These are host source/test-definition findings, not claims that a target test,
allocation measurement, bytecode audit, archive inspection, or executable has
already passed. Do not report those forms of evidence before the native build.

### Post-build target review

During the retained-tree qualification sequence below, only after exact source-
input/mode agreement and the forced native rebuild, execute and record the fake,
native, and complete regression results; the selected eager-allocation proof;
the scanner/loop and inherited `input` bytecode audits; and the rebuilt CMI,
CMO, archive, executable, primitive, ML-only, and install-selection evidence.
Each result must identify the exact rebuilt artifact that produced it. A pre-VM
source finding does not substitute for this target evidence.

Because this subphase edits the same module and may extract the accepted
`input` control flow, repeat the affected Phase 2.1 source and bytecode audit.
Prove the original caller-buffer path still has no new pre-entry closure or
success-result allocation, installs its handler immediately after active state,
and retains its direct nonallocating byte copy followed immediately by cursor
and lifecycle commits. It must still perform at most one lower refill and
retain its accepted exception and result behavior. New accumulator copies may
add call sites for an already present byte-copy primitive; map every call site
and prove the primitive-name/runtime-symbol set is unchanged rather than
requiring the former whole-CMO call-site count to remain one.

Also map the complete target bytecode control flow for the private scanner and
the enclosing accumulation/refill loop. Every continuation after a scanned
segment or positive refill must use an iterative back edge or a verified tail
call, with no retained frame per byte, segment, or refill. The source and
bytecode audit must show that committed content is not rescanned and that
contiguous growth does not use a constant-increment copy cycle. The one-byte-
fill stress tests corroborate this structure but do not replace that audit.
For every mapped allocation, application, poll, safe point, or pending-action
site, record the dominating active-state/handler path and whether the current
segment has or has not been committed. Prove that a selected exception follows
the corresponding restoration and physical-reraise rule without an unintended
cursor write or retry.

## Retained-tree qualification discipline

Phase 2.2 is expected to reuse the uniquely accepted, halted Phase 2.1 native
source/build root recorded by its completion report. After the required exact
VM, loopback, action, and WHPX confirmation but before starting the VM, inspect
the P9QEMU/Python/QEMU process chain and listeners and prove that no process
owns the confirmed writable disk. Only then start that exact mutable `dev`
instance. Once the confirmed QEMU process owns the disk, connect through the
confirmed address and, before the first task-authorized guest write, re-resolve
the canonical native root read-only and prove that its accepted common-schema
identity, project ownership, read-only dependency prefix, and Phase 2.1
provenance still match. Boot or guest-service activity is recorded separately
and is not mislabeled as a task write. Disk ownership by that one confirmed
live QEMU process is expected at this post-start gate; a second or uncertain
owner stops. Do not infer identity from the path name alone.

Reuse the complete accepted Phase 2.1 authoritative transfer and source-
identity discipline, including its canonical-path, regular-file, executable-
mode, lowercase-digest, bytewise-sorting, `.git`, gitlink, untracked/ignored,
and source-versus-artifact rules. Freeze the Phase 2.2 source-input path and
mode basis from every tracked regular file present at the refined documentation
checkpoint; all authorized Phase 2.2 implementation paths are already tracked,
and no new source path is expected. After implementation and final host review,
take each transfer member's content from that exact reviewed Windows worktree.
Transfer exactly those reviewed bytes and modes without `.git` through
`/mnt/term` and copy them to native storage.

The complete Windows/native content and mode comparison applies to that exact
source-input transfer set, not to the entire retained native source/build tree.
Inventory preexisting Phase 2.1 build products, later rebuilt products,
configuration outputs, and test artifacts separately; none is a source-input
manifest member or permission for a transferred source byte to differ. Before
compiling, require the parsed source-input content and mode manifests to agree
exactly. If target-native dependency generation changes `.depend`, return only
that generated file, repeat host review, regenerate the final source-input
manifest, retransfer the final source set, and re-establish exact agreement.
Recheck the same source-input and mode manifests after the last build and test
write, alongside the separate final build-artifact inventory.

Because the root contains accepted Phase 2.1 build products, force and visibly
record rebuilding the modified `plan9_in_channel.cmi`,
`plan9_in_channel.cmo`, `plan9.cma`, and both channel test executables with the
accepted target compiler/runtime path before accepting any focused result.
Normal timestamp inference alone is insufficient. Record before/after artifact
identities and prove the executed tests use the rebuilt products.

Maintain an append-only consumed-suffix ledger in the host evidence root,
outside every source/build tree. Before reserving a Phase 2.2 suffix, reconcile
the accepted Phase 2.1 completion record, every earlier Phase 2.2 attempt ledger
and captured command log, and all relevant residual guest artifacts. Absence
from the retained tree alone is not proof that a suffix was never used. If the
ledger cannot be written durably or the histories disagree, do not invoke the
suite.

For the first complete Phase 2.2 suite invocation, reserve
`TEST_SUFFIX=phase2_2_001` only if that reconciliation proves no prior Phase 2.2
reservation or invocation. Before reservation, resolve the actual GNU Make
executable selected by the required APE shell setup and record its canonical
guest path and complete accepted identity. Write the reservation, literal shell
command, resolved Make identity, and fully expanded Make path and
`TEST_SUFFIX` arguments to the host ledger before launching it. If resolution
changes or disagrees at launch, do not run the command; the reservation remains
consumed. Reservation also consumes the suffix if launch otherwise fails, the
command is interrupted, or evidence is incomplete; each later reservation
increments the three-digit suffix. After the attempt, append its launch result,
complete output location, and status without rewriting the earlier entry. The
intended initial literal command is:

```sh
"$MAKE" -C otherlibs/plan9 TEST_SUFFIX=phase2_2_001 test
```

No install is authorized. Preserve and compare the recorded read-only
dependency prefix and the protected `/usr/glenda/lib/unix/ocaml-4.14.3`
prefix before and after qualification, including matching absence sentinels
when applicable.

## Execution sequence and mandatory pause

1. Record the exact accepted Phase 2.1 Git and source state.
2. Implement only this handoff and inspect the complete host diff.
3. Report source decisions and deviations, then pause for explicit VM
   instance, loopback, action, and WHPX confirmation. After confirmation,
   perform the pre-start unowned-disk proof and the post-start read-only root
   identity gate in that order before the first task-authorized guest write.
4. If `.depend` needs regeneration, use the exact native APE/GNU Make workflow,
   return only the generated file, and repeat authoritative host review.
5. Apply the retained-tree qualification discipline above, run the focused
   tests and full regressions, and record symbol, archive, packaging, and `/fd`
   cleanup evidence. No install is required.
6. After all guest writes stop, record the final canonical source/build root,
   complete source-input/mode manifests, separate build-artifact identities,
   dependency-prefix state, and intended retained disposition for Phase 2.3.
7. Obtain fresh confirmation of the exact writable instance, per-start
   loopback address, and shutdown action. Halt through address-specific
   Drawterm `fshalt`, wait for the exact QEMU PID and its P9QEMU/Python parent
   chain to exit, verify all seven listeners close, and prove no live QEMU owns
   the writable disk.
8. Only after every tree, descriptor, process, listener, disk, and shutdown
   postcondition succeeds, assign that exact retained root the unique accepted
   Phase 2.2 native retained-tree label. It is eligible to serve as Phase 2.3's
   native predecessor only after the separate Git checkpoint gate below is
   satisfied. Report and stop.

Any host source change after transfer invalidates the corresponding native
result. Do not patch the guest as the authority and do not begin Phase 2.3.
If clean shutdown or final identity proof fails, withhold the accepted Phase
2.2 native retained-tree label and report the exact live or uncertain state.
Never inspect, hash, copy, move, checkpoint, or remove a live writable disk.
Retain the tree unless the user separately authorizes an exact-path removal
after clean shutdown.

### User-authorized Git checkpoint gate

Native qualification and the retained-tree label do not authorize a Git commit
or push. Until the user explicitly requests the applicable Git action and this
gate succeeds, report the implementation as natively qualified but awaiting its
Git checkpoint. Do not call it the accepted Phase 2.2 Git checkpoint and do not
begin Phase 2.3.

Only after an explicit user request to commit:

1. re-record the exact branch, `HEAD`, upstream, recent log, worktree, and index;
2. require the index to contain no preexisting staged change and rederive the
   complete current Windows source-input and mode manifests, proving exact
   equality with the final natively qualified host manifests and therefore no
   intervening source or mode change;
3. stage only the reviewed and natively qualified authorized implementation
   paths, including `.depend` only if its generated qualified change was
   accepted; never stage evidence or an unrelated path;
4. inspect the complete staged diff, names, statuses, modes, and
   `git diff --cached --check`, then independently derive the resulting index-
   tree source-input content and mode manifests and require exact equality with
   the qualified Windows manifests; also prove that current `HEAD` history
   contains the refined documentation-content and checkpoint-recording commits
   and the accepted Phase 2.1 predecessor;
5. create one coherent implementation commit without changing source bytes,
   then require its tree to match the verified index tree exactly and require
   the index and worktree to be clean; a hook, tool, or callback that changes a
   source byte or mode invalidates the native result rather than being absorbed
   silently; and
6. record the exact implementation commit hash and its qualified native source/
   tree identity before calling it the accepted Phase 2.2 Git checkpoint.

A push is a separate action and occurs only when the user explicitly requests
it, whether in the same instruction as the commit or later. Record the exact
remote-tracking result if performed.

## Completion report

Report:

- exact branch, starting/ending identities, umbrella and refined documentation
  checkpoints, their recording history, and accepted Phase 2.1 predecessor;
- files changed and final internal signature;
- accumulator invariants, logical-versus-transient storage policy, growth
  arithmetic and work complexity, constant-stack progress, returned-string
  ownership/non-aliasing, policy-neutral delimiter scan and its exact numeric
  entry/outcome invariants, exact cursor/result commit points, and atomic active-
  state behavior;
- exact omitted-argument default/default-plus-one, the eager-allocation proof
  method and its setup-before-baseline record, counter identity/capability and
  exact delta or substitute target-bytecode evidence, complete integer
  validation, exact-limit, simultaneous scratch/window boundary, excess, retry-
  as-line, both EOF-result forms, and stream-position evidence;
- complete fake and native test results, actual fake lower-read traces, native
  writer segmentation without an inferred read-boundary claim, long-schedule
  generator identity and linear setup/constant-time dispatch evidence, the
  append-only suffix-ledger identity and reconciliation inputs, resolved GNU
  Make identity, literal and expanded suite commands, and every reserved-and-
  therefore-consumed `TEST_SUFFIX`;
- every native/refill error, raised lower exception, scanner/loop callback or
  pending-action site, exception, adversarial zero-count fill, exact resulting
  cursor, and no-retry result;
- `.depend`, archive, primitive, ML-only, and install-selection/CMI packaging
  evidence;
- separate pre-VM host source/test-definition findings and post-build native
  test, bytecode, archive, and executed-artifact evidence without promoting the
  former into claims about the latter;
- authoritative Windows/native source-input and mode manifests, separate
  retained/build-artifact inventories, forced rebuild and executed-artifact
  identities, and dependency/protected-prefix comparisons;
- descriptor inventory, pre-start unowned-disk proof, post-start single-QEMU
  ownership and read-only root gate, final retained-tree common-schema
  identity, accepted Phase 2.2 native retained-tree label, Git-checkpoint state,
  and complete shutdown process/listener/disk postconditions;
- if the user authorized a Git checkpoint, the pre-stage source-input/mode
  manifest comparison, complete staged diff and index-tree manifest proof,
  commit-tree/index-tree equality, final clean index/worktree state, exact
  implementation commit, and any separately authorized remote-tracking result;
- all deviations, uncertainties, skipped criteria, and open gates; and
- one conclusion: accepted Phase 2.2 Git checkpoint at the named commit;
  natively qualified implementation awaiting a user-authorized Git checkpoint;
  implementation awaiting native qualification; or blocked/rejected with exact
  reason.

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
