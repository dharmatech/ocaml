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

type pid = int
type process_id = int64

type wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

type native_failure = {
  native_kind : int;
  native_message : string;
}

let wait_succeeded wait_msg = wait_msg.message = ""

let error_kind_of_native native_kind native_message =
  match native_kind, native_message with
  | 0, _ -> Invalid_argument
  | 2, _ -> Interrupted
  | 3, "no living children" -> No_children
  | 3, _ -> Protocol_error
  | 4, _ -> Protocol_error
  | _ -> Other

let error_of_native operation native =
  {
    operation;
    kind =
      error_kind_of_native native.native_kind native.native_message;
    message = native.native_message;
  }
