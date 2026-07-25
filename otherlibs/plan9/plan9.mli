(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                             Dharmatech                                 *)
(*                                                                        *)
(*   Copyright 2026 Dharmatech                                            *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the           *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Native Plan 9 interfaces.

    This library is available only in OCaml installations targeting Plan 9.
    Portable Unix-compatible behavior remains in {!Sys} and {!Unix}. *)

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
(** Raised by explicitly raising operations when a native operation fails. *)

type pid = private int
(** A native Plan 9 process identifier. *)

type process_id = private int64
(** A runtime-instance-local managed identity.

    Managed identities are allocated before rfork and are never reused by the
    running OCaml runtime, even if the kernel later reuses a native PID. *)

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}
(** A lossless native Plan 9 wait message.

    The timing fields are the native unsigned millisecond values zero-extended
    to [int64]. [message] is the complete native [Waitmsg.msg], including any
    program-name and PID prefix. *)

val wait_succeeded : wait_msg -> bool
(** [wait_succeeded message] is true exactly when [message.message = ""]. *)

module Env : sig
  (** Direct access to the process's live Plan 9 environment namespace.

      Every operation reads or mutates files below [/env]. The module does not
      consult APE's cached environment and keeps no in-memory mirror. *)

  type value = string list

  val get : string -> (value option, error) result
  (** [get name] reads [/env/name].

      [Ok None] means that the file was absent when [/env] was enumerated.
      [Ok (Some value)] preserves the native scalar or list representation.
      Invalid names and I/O failures are returned as [Error _]. If another
      process removes a listed file before it is opened, the race is reported
      as an I/O error rather than retried or treated as absence. *)

  val get_exn : string -> value
  (** [get_exn name] is the explicitly raising lookup.

      @raise Not_found if [name] is absent.
      @raise Error if name validation or native I/O fails. *)

  val set : string -> value -> (unit, error) result
  (** [set name value] creates or truncates [/env/name] and writes the
      canonical NUL-terminated Plan 9 encoding.

      An empty list writes zero bytes; [[""]] writes one NUL byte. Elements
      may contain arbitrary bytes except NUL. The write is direct rather than
      transactional, so an I/O failure can leave the file truncated or
      partially written; callers may use [get] to observe the resulting live
      state. *)

  val remove : string -> (unit, error) result
  (** [remove name] directly removes [/env/name].

      Removing an absent name returns the native removal error rather than
      silently succeeding. *)

  val names : unit -> (string list, error) result
  (** [names ()] returns the names currently visible in [/env].

      The order is unspecified and no snapshot is retained. *)
end

module Raw : sig
  (** Deliberately narrow native operations.

      This module exposes neither a generic rfork mask nor a raw waiter. *)

  val copy_environment : unit -> (unit, error) result
  (** [copy_environment ()] performs exactly the current-process
      [rfork(RFENVG)] operation.

      It creates no child. Existing values are copied into the continuing
      process's new environment group; later mutations no longer cross the
      split. The operation accepts no caller-supplied rfork flags. *)

  val exec :
    program:string ->
    argv:string array ->
    ('a, error) result
  (** [exec ~program ~argv] directly replaces the current process.

      [argv] must be nonempty and is passed literally, including the
      caller-supplied [argv.(0)]. No PATH search, shell, quoting, expansion, or
      APE process dispatch occurs. Empty and arbitrary non-NUL argument bytes
      are preserved. An empty program or vector and embedded NUL bytes are
      rejected before native exec. Success does not return. *)
end

module Process : sig
  (** Direct native Plan 9 process creation and synchronous wait ownership. *)

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
  (** [spawn ~program ~args ()] directly starts one managed child.

      The native vector is [[|program; args.(0); ...|]]. No shell or PATH
      search is used. An outer [Error] means no child created by this call
      remains. Every post-rfork nonterminal result carries its owned handle.
      Successful spawn starts no background reaper. *)

  val run :
    ?stdout:stdout ->
    program:string ->
    args:string array ->
    unit ->
    (run, error) result
  (** [run ~program ~args ()] uses [spawn] and the same synchronous wait
      coordinator.

      It normally drives the direct child to a terminal result. An outer
      [Error] means no child from the call remains; every unresolved result
      retains the exact managed handle. *)

  val id : t -> process_id
  val pid : t -> pid

  val wait : t -> wait_result
  (** Wait synchronously through the process-wide coordinator.

      Interruption is not retried. Foreign-FIFO backpressure leaves the target
      active and is retryable after draining foreign completions. *)

  val wait_any : unit -> (wait_any_result, error) result
  (** Return the oldest queued foreign completion before invoking native
      await. A nonterminal result contains the complete adopted owner set. *)

  val unresolved : unit -> t list
  (** Adopt recoverable native pending-child records and return owned handles.

      Adoption is identity-preserving and does not itself invoke native
      await. *)

  val take_foreign_completions : unit -> wait_msg list
  (** Drain retained foreign completions in FIFO order. *)
end
