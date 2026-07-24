# Native Plan 9 API requirements

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

## Native processes

`Plan9.Process` executes a program directly:

```ocaml
module Process : sig
  type t

  val spawn :
    ?isolation:isolation ->
    program:string ->
    argv:string array ->
    (t, error) result

  val pid : t -> pid
  val wait : t -> (wait_msg, error) result
  val wait_any : unit -> (wait_msg, error) result
end
```

`argv` is literal, nonempty, and includes `argv[0]`. There is no shell, PATH
search, quoting, wildcard expansion, redirection, variable expansion, or
argument rewriting.

The production spawn boundary is one C primitive:

1. validate every string, length, allocation, and policy value;
2. copy all inputs into C-owned memory;
3. create a native close-on-exec error pipe before rfork;
4. perform native rfork;
5. in the child, prepare only the declared native resources, exec directly,
   report the exact exec error through the pipe if necessary, and exit
   natively;
6. never allocate, callback, finalize, use an OCaml channel, or return to the
   OCaml runtime in the child; and
7. return to OCaml in the parent only after the exec-success/error handshake.

Successful exec closes the child pipe writer and produces EOF in the parent.
An error payload means exec failed and must be preserved before the failed
child is reaped.

The child is waitable. The safe layer copies the file-descriptor group and
makes environment, namespace, note group, rendezvous group, and mount policy
explicit. A wait cache may retain other complete `Plan9.Process` wait records
while waiting for a particular PID.

## Wait

Preserve the native record:

```ocaml
type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  status : string;
}

val wait : unit -> (wait_msg, error) result
```

Do not use `option`: no living children, interruption, malformed records, and
other failures are distinct results. Do not automatically retry interruption.
Preserve empty status as native success and preserve nonempty status exactly.
Do not translate into Unix exit or signal constructors.

Prefer a bounded direct native await boundary with faithful Plan 9 field
parsing. Report truncation or malformed data as `Protocol_error`.

Classify `No_children` only from the exact native no-living-children error and
retain that message. A nil or failed native wait is not by itself evidence
that no children remain.

Native waits consume one process-wide child wait queue. `Plan9.Raw.wait`,
`Plan9.Process` waits, and `Unix.wait` cannot transparently coexist: one API
may consume another API's child record. The initial managed guarantee covers
children created and waited through `Plan9.Process`; mixing those waits with
`Unix.wait` or independent raw wait consumers is unsupported.

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

The initial public low-level current-process operation may permit only audited
copy/new-group policy. Process creation remains a combined native rfork-exec
operation whose child never returns to OCaml. Any future child-returning
facility belongs under an explicitly unstable `Raw.Unsafe` boundary after a
dedicated GC, runtime, note, channel, and descriptor audit.

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
before allocating OCaml results.
