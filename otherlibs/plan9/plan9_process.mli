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

(** Internal, pure-ML process coordinator.

    This interface is not installed. It separates deterministic ownership
    and routing tests from the Plan 9 runtime primitive backend. *)

type error_kind = Plan9_types.error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other

type error = Plan9_types.error = {
  operation : string;
  kind : error_kind;
  message : string;
}

type pid = Plan9_types.pid
type process_id = Plan9_types.process_id

type wait_msg = Plan9_types.wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

val wait_succeeded : wait_msg -> bool

type native_failure = Plan9_types.native_failure = {
  native_kind : int;
  native_message : string;
}

type native_pending = Plan9_primitive.native_pending = {
  native_process_id : int64;
  native_pid : int;
  native_handshake : int;
  native_detail : native_failure;
  native_queue_loss : native_failure option;
}

type native_wait_event = Plan9_primitive.native_wait_event = {
  native_sequence : int64;
  native_event_kind : int;
  native_wait_pid : int;
  native_user_time_ms : int64;
  native_system_time_ms : int64;
  native_elapsed_time_ms : int64;
  native_event_detail : native_failure;
}

module type Native = sig
  val foreign_capacity : int
  val spawn_flags : int

  val spawn :
    string ->
    string array ->
    int ->
    string ->
    int ->
    (native_pending, native_failure) result

  val pending : unit -> native_pending array
  val acknowledge_pending : int64 -> bool
  val await : unit -> native_wait_event
  val acknowledge_wait : int64 -> bool
end

val error_of_native : string -> native_failure -> error

module Make (_ : Native) : sig
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

  and wait_unresolved =
    | Await_interrupted of error
    | Await_error of error
    | Foreign_backpressure of {
        queued : int;
        capacity : int;
      }
    | Coordinator_invariant_failure of error
    | Malformed_native_record of error

  and wait_terminal_failure =
    | Wait_queue_lost of error

  and wait_result =
    | Wait_finished of wait_msg
    | Wait_unresolved of {
        process : t;
        reason : wait_unresolved;
      }
    | Wait_terminal_failure of {
        process : t;
        reason : wait_terminal_failure;
      }

  and completion =
    | Managed of t * wait_msg
    | Foreign of wait_msg

  and wait_any_result =
    | Wait_any_finished of completion
    | Wait_any_unresolved of {
        processes : t list;
        reason : wait_unresolved;
      }
    | Wait_any_terminal_failure of {
        processes : t list;
        reason : wait_terminal_failure;
      }

  and run_incomplete =
    | Run_launch_incomplete of launch_incomplete
    | Run_wait_unresolved of wait_unresolved

  and run_terminal_failure =
    | Run_wait_queue_lost of {
        wait_error : error;
        exec_error : error option;
      }

  and run =
    | Run_finished of wait_msg
    | Run_incomplete of {
        process : t;
        reason : run_incomplete;
      }
    | Run_terminal_failure of {
        process : t;
        reason : run_terminal_failure;
      }

  and t

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
