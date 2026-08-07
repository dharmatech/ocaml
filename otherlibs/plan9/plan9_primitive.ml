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

type descriptor_capability

external descriptor_pipe :
  unit ->
  ((descriptor_capability * descriptor_capability),
   Plan9_types.native_failure) result
  = "caml_plan9_syscall_pipe"

external descriptor_close :
  descriptor_capability ->
  (unit, Plan9_types.native_failure) result
  = "caml_plan9_syscall_close"

external descriptor_read :
  descriptor_capability -> int ->
  ((bytes * int), Plan9_types.native_failure) result
  = "caml_plan9_syscall_read"

external descriptor_write :
  descriptor_capability -> bytes -> int -> int ->
  (int, Plan9_types.native_failure) result
  = "caml_plan9_syscall_write"

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

let foreign_capacity = 64

(* RFPROC | RFFDG | RFREND.  The C primitive independently requires this
   exact value; this private constant is not a generic rfork interface. *)
let spawn_flags = 16 lor 4 lor 8192

external copy_environment :
  unit -> (unit, Plan9_types.native_failure) result
  = "caml_plan9_copy_environment"

external exec :
  string ->
  string array ->
  ('a, Plan9_types.native_failure) result
  = "caml_plan9_exec"

external spawn :
  string ->
  string array ->
  int ->
  string ->
  int ->
  (native_pending, Plan9_types.native_failure) result
  = "caml_plan9_process_spawn"

external pending :
  unit -> native_pending array
  = "caml_plan9_process_pending"

external acknowledge_pending :
  int64 -> bool
  = "caml_plan9_process_acknowledge"

external await :
  unit -> native_wait_event
  = "caml_plan9_process_await"

external acknowledge_wait :
  int64 -> bool
  = "caml_plan9_process_acknowledge_wait"
