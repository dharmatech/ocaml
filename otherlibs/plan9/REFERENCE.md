# `Plan9` library reference

The `Plan9` library gives OCaml programs explicit access to native Plan 9
environment and process semantics. It is available only in OCaml installations
targeting Plan 9.

Use `Sys` and `Unix` when portable Unix-compatible behavior is desired. Those
modules retain their existing APE-backed semantics. Use `Plan9` when a program
deliberately needs the live `/env` namespace, direct native execution, or
native wait messages.

## Contents

- [Compile and link](#compile-and-link)
- [Errors](#errors)
- [Native wait messages](#native-wait-messages)
- [`Plan9.Env`](#plan9env)
- [`Plan9.Process`](#plan9process)
- [`Plan9.Raw`](#plan9raw)
- [Current scope and limitations](#current-scope-and-limitations)

## Compile and link

The library is installed beneath `+plan9`:

```sh
ocamlc -I +plan9 plan9.cma program.ml -o program
```

This normal bytecode link does not require:

- `-custom`;
- `-use-runtime`;
- a C compiler or linker;
- user-written C stubs; or
- a wrapper compiler.

The standard Plan 9 `ocamlrun` contains the required native primitives.
`plan9.cma` itself is ML-only.

## Errors

Result-returning operations use:

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

`operation` identifies the failed operation. `message` preserves the native or
runtime error text. `kind` provides the small amount of classification needed
for safe control flow without replacing the original message.

A simple reporter is:

```ocaml
let report_error (error : Plan9.error) =
  Printf.eprintf "%s: %s\n" error.operation error.message
```

`Plan9.Error` is the exception used by explicitly raising operations such as
`Plan9.Env.get_exn`.

## Native wait messages

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

`pid` is the native Plan 9 PID. `process_id` is a runtime-local managed
identity allocated before `rfork`; it is never reused by the running runtime,
even if the kernel later reuses a PID.

The three timing fields preserve the native unsigned millisecond values,
zero-extended into `int64`. `message` is the complete native `Waitmsg.msg`
text. A native wait is successful exactly when `message = ""`;
`Plan9.wait_succeeded` performs that test.

## `Plan9.Env`

`Plan9.Env` reads and mutates the calling process's live `/env` namespace. It
does not use APE's cached environment and keeps no in-memory mirror.

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

### Representation

| Plan 9 meaning | OCaml value | `/env` bytes |
| --- | --- | --- |
| absent | `Ok None` | no file |
| empty list | `Ok (Some [])` | zero bytes |
| empty scalar | `Ok (Some [""])` | one NUL |
| scalar | `Ok (Some ["x"])` | `x\000` |
| list | `Ok (Some ["x"; "y"])` | `x\000y\000` |

The decoder also accepts a final element without a terminating NUL. The
encoder writes one trailing NUL for every element. Arbitrary non-NUL bytes,
whitespace, newlines, and empty elements are preserved.

Names must not be empty, `.`, `..`, contain `/`, or contain NUL. Other valid
Plan 9 names, including `fn#...`, are accepted. Values may contain arbitrary
bytes except NUL.

Every lookup rereads the namespace. A name absent from a fresh `/env`
enumeration returns `Ok None`. If the file is removed between enumeration and
open, the resulting I/O error is returned rather than converted to absence.

`set` writes directly and is not transactional; an I/O failure can leave the
live file truncated or partially written. `remove` returns an error when the
file is already absent.

### Example

```ocaml
let () =
  match Plan9.Env.get "sysname" with
  | Ok None ->
      print_endline "sysname is absent"
  | Ok (Some elements) ->
      List.iter print_endline elements
  | Error error ->
      report_error error;
      exit 1
```

Setting and removing a list:

```ocaml
let name = "my_program_state"

let () =
  match Plan9.Env.set name ["ready"; ""; "native"] with
  | Error error ->
      report_error error;
      exit 1
  | Ok () ->
      match Plan9.Env.remove name with
      | Ok () -> ()
      | Error error ->
          report_error error;
          exit 1
```

`Plan9.Env.get_exn name` returns the value, raises `Not_found` for absence,
and raises `Plan9.Error error` for validation or I/O failure.

## `Plan9.Process`

`Plan9.Process` starts programs directly through native `rfork` and `exec`,
then owns the native wait queue synchronously while managed or pending owners
remain.

It performs no shell invocation, PATH search, quoting, expansion, globbing, or
APE process dispatch. Pass a literal program path.

### Output selection

```ocaml
type stdout =
  | Inherit
  | Truncate of string
```

`Inherit` is the default. `Truncate path` opens or creates `path` in the
parent, truncates it, and connects the child's standard output to that file.

### Prefer `run` for synchronous commands

```ocaml
val run :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  unit ->
  (run, error) result
```

`args` contains the arguments after `argv.(0)`. `run` constructs the native
vector by prepending `program`.

```ocaml
let () =
  match
    Plan9.Process.run
      ~stdout:(Plan9.Process.Truncate "/tmp/hello.out")
      ~program:"/bin/echo"
      ~args:[|"hello"; "Plan 9"|]
      ()
  with
  | Error error ->
      (* No child created by this call remains. *)
      report_error error;
      exit 1
  | Ok (Plan9.Process.Run_finished message) ->
      if not (Plan9.wait_succeeded message) then begin
        prerr_endline message.message;
        exit 1
      end
  | Ok (Plan9.Process.Run_incomplete { process; _ }) ->
      (* The result still owns [process]. Do not discard it. *)
      ignore process;
      prerr_endline "the managed child remains unresolved";
      exit 1
  | Ok (Plan9.Process.Run_terminal_failure { process; _ }) ->
      (* The handle is preserved, but the native wait queue was lost. *)
      ignore process;
      prerr_endline "the managed child lost its wait-queue completion";
      exit 1
```

An outer `Error` from `run` or `spawn` means no child created by that call
remains. Every post-`rfork` nonterminal result contains the exact owned
process handle.

### Spawn and wait separately

```ocaml
val spawn :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  unit ->
  (launch, error) result

val wait : t -> wait_result
```

`spawn` returns promptly after its bounded exec handshake. It does not start a
background reaper.

```ocaml
let wait_once process =
  match Plan9.Process.wait process with
  | Plan9.Process.Wait_finished message ->
      `Finished message
  | Plan9.Process.Wait_unresolved { process; reason } ->
      (* [process] remains the owned handle. *)
      `Unresolved (process, reason)
  | Plan9.Process.Wait_terminal_failure { process; reason } ->
      `Terminal_failure (process, reason)

let () =
  match
    Plan9.Process.spawn
      ~program:"/bin/echo"
      ~args:[|"started"|]
      ()
  with
  | Error error ->
      report_error error;
      exit 1
  | Ok (Plan9.Process.Launch_incomplete { process; _ }) ->
      (* Exec failed or the handshake was interrupted, but the child still
         has an owned handle that must be resolved. *)
      ignore process;
      prerr_endline "launch remains unresolved";
      exit 1
  | Ok (Plan9.Process.Launch_started process) ->
      ignore (wait_once process)
```

Applications must decide explicitly whether and when to retry an unresolved
wait. In particular, interruption consumes neither the native completion nor
the handle. Foreign-FIFO backpressure is also retryable after the foreign
queue is drained. Coordinator invariant or malformed-record failures are
failed-closed states and must not be treated as ordinary interruption.

### Process result types

```ocaml
type t

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
```

### Coordinator operations

```ocaml
val id : t -> process_id
val pid : t -> pid
val wait_any : unit -> (wait_any_result, error) result
val unresolved : unit -> t list
val take_foreign_completions : unit -> wait_msg list
```

`id` returns the stable runtime-local identity. `pid` returns the native PID.

`wait_any` returns the oldest queued foreign completion before calling native
await. A nonterminal result contains the complete set of adopted managed
owners.

`unresolved` adopts recoverable native pending-child records and returns their
identity-preserving handles. It does not call native await.

`take_foreign_completions` drains retained unknown-PID wait messages in FIFO
order. Draining a full foreign queue permits a managed wait to be retried.

### Exclusive wait ownership

The native Plan 9 wait queue is process-wide. While any
`Plan9.Process`-managed or native-pending child remains unresolved:

- do not call `Sys.command`;
- do not call `Unix.wait` or another Unix/APE wait function;
- do not invoke an independent native waiter; and
- keep progressing children only through `Plan9.Process`.

After every managed and native-pending owner is terminal, the exclusivity
interval is closed and later APE child/wait use may resume.

## `Plan9.Raw`

`Plan9.Raw` is deliberately narrow. It does not expose a generic `rfork`
mask, a child-returning raw `rfork`, or a raw waiter.

### Copy the current environment group

```ocaml
val copy_environment : unit -> (unit, error) result
```

`copy_environment ()` performs exactly `rfork(RFENVG)` in the current
process. It creates no child. Existing values are copied into a new
environment group; later mutations no longer cross the split.

This is a one-time isolation operation, not a general process-spawning
primitive:

```ocaml
let () =
  match Plan9.Raw.copy_environment () with
  | Ok () -> ()
  | Error error ->
      report_error error;
      exit 1
```

### Replace the current process

```ocaml
val exec :
  program:string ->
  argv:string array ->
  ('a, error) result
```

`exec` passes the caller's exact nonempty vector, including caller-supplied
`argv.(0)`, and replaces the current process on success:

```ocaml
let () =
  match
    Plan9.Raw.exec
      ~program:"/bin/echo"
      ~argv:[|"chosen-argv0"; "literal argument"|]
  with
  | Error error ->
      report_error error;
      exit 1
  | Ok _ ->
      assert false
```

There is no PATH search, shell, quoting, expansion, or argument rewriting.
Empty arguments and arbitrary non-NUL bytes are preserved. An empty program,
an empty vector, embedded NUL, or an unrepresentable native length is rejected
before native exec.

## Current scope and limitations

- The port currently supports the bytecode compiler and runtime, not the
  native-code compiler.
- Shared libraries and systhreads are disabled.
- The containing `ocamlrun` remains APE-linked; the native `Plan9` process
  boundary does not make the whole executable APE-free.
- `Sys`, `Unix`, `Sys.command`, and `Unix.putenv` are unchanged.
- `Plan9.Process` exposes no shell or PATH-search convenience layer.
- Process stdout supports only inheritance or a parent-opened truncate-file
  destination.
- `RFMEM`, `RFNOWAIT`, `RFNOMNT`, generic rfork masks, child-returning raw
  rfork, and public raw wait are not exposed.
- General downstream custom-runtime linking remains a separate port
  capability; it is not required for ordinary `plan9.cma` use.

## Additional documentation

- [`plan9.mli`](plan9.mli) is the canonical public interface.
- [`README.md`](README.md) records implementation semantics and focused-test
  coverage.
- [`../../docs/design/plan9/`](../../docs/design/plan9/) contains design and
  verification rationale for port maintainers.
