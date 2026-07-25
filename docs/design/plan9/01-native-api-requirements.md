# Native Plan 9 API requirements

The process contract in this document promotes the accepted
[P2 process-primitives design package](exploration/process-primitives/README.md).
The numbered exchange remains useful provenance, but this file is the
normative API and safety contract.

## Packaging

`Plan9` is a Plan 9-only otherlib. Its installed archive is ML-only and must
report no custom linking, C objects, or dynamic libraries. Its native
`caml_plan9_*` primitive implementations are conditionally compiled into the
standard Plan 9 `ocamlrun` and included once in the generated built-in
primitive tables known to both the runtime and bytecode compiler.

Acceptance requires:

```text
ocamlc -I +plan9 plan9.cma program.ml -o program
```

That command must emit no consumer-side C compiler or linker invocation and
must continue to work when those tools are absent from `PATH`.

An older runtime presented with bytecode requiring a new primitive must fail
clearly with an unknown-primitive error. It must never substitute APE behavior.

## Error model

Every operation preserves its native error text:

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
```

Classifications are conveniences, not replacements for the exact native
message. Capture `errstr` immediately after failure, before another C or OCaml
operation can overwrite it.

## Environment

Use a lossless representation:

```ocaml
module Env : sig
  type value = string list

  val get : string -> (value option, error) result
  val get_exn : string -> value
  val set : string -> value -> (unit, error) result
  val remove : string -> (unit, error) result
  val names : unit -> (string list, error) result
end
```

`get_exn` raises `Not_found` for absence and `Plan9.Error` for validation or
I/O failure. Removing an absent variable returns the native removal error.
Direct writes are not transactional: an I/O failure may leave a truncated or
partially written live file, and callers should reread it when recovery
matters.

Required distinctions are:

| Native meaning | OCaml value | `/env` encoding |
| --- | --- | --- |
| absent | `None` | no file |
| empty list | `Some []` | zero bytes |
| empty scalar | `Some [""]` | one NUL |
| scalar | `Some ["x"]` | `x\000` |
| list | `Some ["x"; "y"]` | `x\000y\000` |

The decoder may accept an unterminated last element for compatibility. The
encoder emits canonical NUL-terminated elements and does not trim whitespace
or newlines. Reject empty names, `.`, `..`, `/`, and embedded NUL. Allow
ordinary Plan 9 names such as `fn#...`.

Read and write native `/env` directly. Do not consult or update APE `environ`,
and do not add a process-global mutation map. Phase 1 may implement this
entirely in ML using the existing runtime's file-I/O machinery; that does not
make the complete executable or runtime APE-free. Built-in primitives remain
the packaging boundary for later native process operations.

## Native identity and wait records

Preserve the native record and give each managed child a separate logical
identity:

```ocaml
type pid = private int
type process_id = private int64

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

val wait_succeeded : wait_msg -> bool
```

`wait_succeeded m` is true exactly when `m.message = ""`. Preserve the
complete native `Waitmsg.msg`, including any native program-name or PID
prefix, rather than reducing it to an `_exits` argument, Unix exit code, or
signal constructor. The installed ABI probe must confirm the width and unit
conversion for all three timing fields.

Every managed child receives a monotonically allocated `process_id` before
rfork. It is never reused during the runtime instance. Process-ID exhaustion,
wraparound, reservation collision, or inability to preallocate the ownership
record fails before rfork and therefore creates no child.

## Narrow `Plan9.Raw` boundary

The stable low-level surface is deliberately small:

```ocaml
module Raw : sig
  val copy_environment : unit -> (unit, error) result

  val exec :
    program:string ->
    argv:string array ->
    ('a, error) result
end
```

`copy_environment ()` performs only the current-process equivalent of
`rfork(RFENVG)`. It creates no child, accepts no mask, and returns once to the
calling OCaml process. The CPU-017 integration uses it exactly once after
finalizing globally intended `NPROC`, `sysname`, and prompt values and before
writing derived `auth` and `serviced` values. The continuing process and its
later service launchers share that deliberately selected copied environment
group; the original group does not receive the derived writes.

`Raw.exec` replaces the current process on success. It accepts a literal,
nonempty native vector and never rewrites `argv[0]`. Reject an empty vector,
embedded NUL in the program or any argument, malformed direct primitive
values, and any length or aggregate allocation that the native representation
cannot express.

There is no public raw wait operation, raw integer rfork mask, child-returning
rfork, or Phase 2 `RFNOMNT` option.

## Canonical `Plan9.Process` interface

`Plan9.Process` executes programs directly and preserves ownership across
every post-rfork nonterminal result:

```ocaml
module Process : sig
  type t

  type stdout =
    | Inherit
    | Truncate of string

  type launch_incomplete =
    | Exec_failure_unreaped of error
    | Handshake_interrupted of error
    | Handshake_protocol_error of error

  type launch =
    | Launch_started of t
    | Launch_incomplete of {
        process : t;
        reason : launch_incomplete;
      }

  type wait_unresolved =
    | Await_interrupted of error
    | Await_error of error
    | Foreign_backpressure of {
        queued : int;
        capacity : int;
      }
    | Coordinator_invariant_failure of error
    | Malformed_native_record of error

  type wait_terminal_failure =
    | Wait_queue_lost of error

  type wait_result =
    | Wait_finished of wait_msg
    | Wait_unresolved of {
        process : t;
        reason : wait_unresolved;
      }
    | Wait_terminal_failure of {
        process : t;
        reason : wait_terminal_failure;
      }

  type completion =
    | Managed of t * wait_msg
    | Foreign of wait_msg

  type wait_any_result =
    | Wait_any_finished of completion
    | Wait_any_unresolved of {
        processes : t list;
        reason : wait_unresolved;
      }
    | Wait_any_terminal_failure of {
        processes : t list;
        reason : wait_terminal_failure;
      }

  type run_incomplete =
    | Run_launch_incomplete of launch_incomplete
    | Run_wait_unresolved of wait_unresolved

  type run_terminal_failure =
    | Run_wait_queue_lost of {
        wait_error : error;
        exec_error : error option;
      }

  type run =
    | Run_finished of wait_msg
    | Run_incomplete of {
        process : t;
        reason : run_incomplete;
      }
    | Run_terminal_failure of {
        process : t;
        reason : run_terminal_failure;
      }

  val spawn :
    ?stdout:stdout ->
    program:string ->
    args:string array ->
    unit ->
    (launch, error) result

  val run :
    ?stdout:stdout ->
    program:string ->
    args:string array ->
    unit ->
    (run, error) result

  val id : t -> process_id
  val pid : t -> pid

  val wait : t -> wait_result
  val wait_any : unit -> (wait_any_result, error) result

  val unresolved : unit -> t list
  val take_foreign_completions : unit -> wait_msg list
end
```

The public constructor names above are canonical for Phase 2. An outer
`Error` from `spawn` or `run` means no child created by that call remains:
either no child was created, or a known exec-failure child was confirmed
reaped through the shared coordinator. Every result for a child that may
still be live, waitable, or otherwise unresolved carries its exact handle.

A matching completion produces `Wait_finished` or `Run_finished`. Exact
`No_children` loss produces `Wait_terminal_failure` or
`Run_terminal_failure`, retaining the handle for identity and diagnosis even
though the child is gone. Interruption, ordinary await error, foreign
backpressure, invariant failure, and malformed-record failure produce
`Wait_unresolved` or a handle-bearing `Run_incomplete` as applicable.
`Run_wait_queue_lost` carries the exact wait error and also the exact exec
error when the child had already reported one.

`spawn` and `run` take a final unit argument so the optional `stdout`
argument remains erasable. They accept arguments after `argv[0]` and construct
the exact native vector:

```text
argv = [| program; args.(0); ...; args.(n - 1) |]
```

An empty `args` array is valid. There is no shell, PATH search, quoting,
globbing, redirection parsing, variable expansion, environment overlay, or
argument rewriting. `stdout` is limited initially to inherited output or a
parent-opened truncate-file destination.

## Combined rfork and exec primitive

Production spawn uses one private C primitive:

1. validate every OCaml value, string, length, allocation, and fixed policy;
2. reserve the never-reused process ID and preallocate all native
   pending-child storage before rfork;
3. copy every program, argument, path, and policy input into C-owned memory;
4. create the close-on-exec error pipe before rfork;
5. invoke rfork with exactly `RFPROC | RFFDG | RFREND`;
6. in the positive-PID parent branch, publish the preallocated native
   pending-child record allocation-free before handshake I/O, a blocking
   section, OCaml allocation, asynchronous-exception delivery, or return to
   ML;
7. in the child, perform only collision-safe descriptor preparation, direct
   native exec, bounded error-frame output on failure, and native `_exits`;
8. never allocate, callback, finalize, use an OCaml channel, run OCaml code, or
   return to the OCaml runtime in the child; and
9. never call await inside the primitive.

The fixed flags copy the file-descriptor group and create the process and
rendezvous group while sharing the deliberately selected environment,
namespace, and note groups. Phase 2 does not expose `RFNOMNT`. The installed
ABI retains `#d/<fd>` under that flag, but its broader namespace-sandbox policy
remains unselected and requires a separate future design.

The parent-side ML coordinator creates the handle, installs its active PID
mapping, and then acknowledges adoption by process ID. Only that
acknowledgment removes the native pending entry. `Process.unresolved ()`
adopts a still-pending entry idempotently: repeated inspection returns the
same logical process identity and memoized state. A pending entry already
terminalized by exact `No_children` is adopted as that same terminal handle.

Clean EOF before any frame byte means exec success. Exec failure uses the
bounded versioned frame:

```text
4 bytes  ASCII tag and version: "P9E1"
4 bytes  unsigned big-endian payload length
N bytes  exact native error text within the measured fixed bound
EOF      required immediately after the payload
```

The child handles short writes without allocation. The parent performs
complete bounded reads and rejects a truncated header or payload, invalid tag
or length, trailing data, or premature EOF. Handshake interruption and
malformation are distinct handle-bearing launch results. The pipe endpoint is
close-on-exec, and descriptor moves must remain correct when descriptors 0, 1,
or 2 begin closed or collide with the pipe or stdout destination.

A known exec-failure child is adopted and reaped only through the shared
coordinator. If reaping is confirmed, `spawn` may return the preserved exec
error as outer `Error`. Interruption, ambiguity, or another nonterminal
condition returns `Launch_incomplete` with the owned handle.

If exact `No_children` occurs before the matching exec-failure completion is
observed, the handle is terminal `Wait_queue_lost` but the launch remains
`Launch_incomplete` with its exact exec error. It is not converted to outer
`Error`, because the coordinator did not observe the matching completion.
`run` reports that terminal wait state as `Run_terminal_failure` with the same
handle and both exact errors.

## Synchronous wait coordinator

Native await consumes one process-wide wait queue. Plan9.Process is its sole
consumer while any adopted handle or native pending-child record remains
unresolved. During that interval, `Sys.command`, `Unix.wait`, APE wait
functions, and unrelated native waiters are unsupported and must not run.
There is no public `Plan9.Raw.wait_any`.

The interval begins immediately after the first successful managed rfork and
ends only when no adopted or native-pending owner remains unresolved.
Coordinator ownership does not create a background reaper. Native await runs
only when known exec-failure cleanup, `Process.wait`, `Process.wait_any`, or
`Process.run` invokes the coordinator synchronously. Successful `spawn`
starts no hidden worker. Retaining a long-lived handle retains the obligation
to drive its eventual wait; discarding it does not imply `RFNOWAIT` or
automatic cleanup.

`run` invokes `spawn` and normally drives the same coordinator until the
direct child reaches a terminal result. It returns early only with the same
handle when launch or wait remains unresolved. It never introduces a private
wait path.

The coordinator maintains:

- one active PID mapping for each unresolved managed handle;
- terminal completion or loss state on the logical handle, not in a permanent
  PID cache;
- a bounded FIFO of completions classified as foreign when reaped; and
- the native pending-child registry until identity-preserving ML adoption.

A matching completion atomically removes the active PID mapping and memoizes
the complete native record on that handle. Repeated waits return the memoized
terminal result. An unknown-PID completion is classified as foreign
immediately and is never attached to a later handle after PID reuse.

While waiting for a particular handle, an unknown completion is appended to
the foreign FIFO. If the FIFO is already full, the coordinator returns
`Foreign_backpressure` without calling native await. If an appended record
fills the last slot, the coordinator returns backpressure before consuming
another record. The target remains active. `wait_any` returns the oldest
queued foreign completion before invoking native await, and
`take_foreign_completions` drains the FIFO in order. Either makes the original
particular-handle wait retryable.

A nonterminal `wait_any` result carries the complete current adopted-owner
set. Before it calls native await, `wait_any` adopts recoverable native pending
records. Outer `Error` from `wait_any` is permitted only when no managed or
native-pending owner exists.

## Wait failure semantics

Do not automatically retry interruption. `Await_interrupted` and ordinary
`Await_error` retain the active handle. `Foreign_backpressure` is explicitly
retryable after FIFO drainage.

Classify `No_children` only from the exact native no-living-children error and
retain its message. When that exact observation occurs while owners remain,
the coordinator atomically:

1. memoizes `Wait_queue_lost` on every adopted unresolved handle;
2. memoizes the same terminal loss on every unadopted native pending record;
3. removes active PID mappings that can no longer produce a completion; and
4. stops awaiting for those terminal owners.

Later adoption observes the original process ID and memoized loss; it never
creates an apparently active handle after the kernel proved no child remains.
A nil or failed native wait is not by itself evidence of `No_children`.

An external waiter may steal one completion while another child remains
alive. Before exact `No_children`, that is indistinguishable from the first
child still running. The library prohibits mixed waiting but does not promise
finite-time theft detection without native evidence.

An ownership invariant failure and a malformed or unrepresentable native
record are distinct failed-closed coordinator states. Already terminal
handles remain terminal; every representable nonterminal adopted or pending
owner remains owned and unresolved; no record is assigned arbitrarily; and
the coordinator performs no further native await. These failures do not prove
child absence, so the exclusive-wait interval remains open and another wait
facility may not take over. An active PID collision never overwrites the
earlier mapping.

## Rfork safety

Never expose `external rfork : int -> int`. Any OCaml program can redeclare a
built-in primitive by name, so the C entry point must validate its inputs
independently of ML abstraction.

Permanently reject:

- `RFMEM`;
- unknown or contradictory flags;
- a generic child-returning `RFPROC`;
- unsafe current-process resource clearing; and
- `RFNOWAIT` in the managed process API.

The only initial public current-process rfork operation is the exact
`Raw.copy_environment ()` copy described above. Process creation remains a
combined native rfork-exec operation whose child never returns to OCaml. Any
future child-returning facility belongs under an explicitly unstable
`Raw.Unsafe` boundary after a dedicated GC, runtime, note, channel, and
descriptor audit.

## Defensive primitive boundary

ML abstract types are not a security boundary because primitive names are
discoverable. Every primitive must validate:

- OCaml value tags and shapes;
- embedded NUL;
- array and string lengths;
- integer conversion and allocation overflow;
- contradictory policy values;
- forbidden rfork states; and
- resource cleanup on every failure path.

Release the OCaml runtime around genuinely blocking native calls and re-enter
before allocating OCaml results. The no-OCaml child rule is stricter: after
rfork, the child uses only prevalidated C-owned data and native operations
until exec or `_exits`.
