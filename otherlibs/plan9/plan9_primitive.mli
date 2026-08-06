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

(** Internal built-in primitive bindings for the Plan 9 library.

    This interface is not installed. *)

type native_pending = {
  native_process_id : int64;
  native_pid : int;
  native_handshake : int;
  native_detail : Plan9_types.native_failure;
  native_queue_loss : Plan9_types.native_failure option;
}

type native_wait_event = {
  native_sequence : int64;
  native_event_kind : int;
  native_wait_pid : int;
  native_user_time_ms : int64;
  native_system_time_ms : int64;
  native_elapsed_time_ms : int64;
  native_event_detail : Plan9_types.native_failure;
}

val foreign_capacity : int
val spawn_flags : int

val copy_environment :
  unit -> (unit, Plan9_types.native_failure) result

val exec :
  string ->
  string array ->
  ('a, Plan9_types.native_failure) result

val spawn :
  string ->
  string array ->
  int ->
  string ->
  int ->
  (native_pending, Plan9_types.native_failure) result

val pending : unit -> native_pending array
val acknowledge_pending : int64 -> bool
val await : unit -> native_wait_event
val acknowledge_wait : int64 -> bool
