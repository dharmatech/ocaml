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

module type Descriptor = sig
  type t
  type attachment

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val read :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

module type S = sig
  type fd
  type t

  val of_fd : fd -> (t, Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result
  val input :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
end

let zero_success : (int, Plan9_types.error) result = Ok 0
let close_success : (unit, Plan9_types.error) result = Ok ()

external blit_bytes_noalloc :
  bytes -> int -> bytes -> int -> int -> unit
  = "caml_blit_bytes" [@@noalloc]

module Make (Fd : Descriptor) : S with type fd = Fd.t = struct
  type fd = Fd.t

  type lifecycle =
    | Stable_open
    | Input_active
    | Close_active
    | Close_inactive
    | Terminal_closed

  type close_attempt = {
    mutable active : bool;
    mutable terminal : bool;
  }

  type t = {
    token : Fd.attachment;
    scratch : bytes;
    close_attempt : close_attempt;
    mutable lifecycle : lifecycle;
    mutable unread_start : int;
    mutable unread_end : int;
  }

  type prepared_input =
    | Input_result of (int, Plan9_types.error) result
    | Input_copy of int * int * (int, Plan9_types.error) result

  let scratch_capacity = 4096

  let of_fd_operation = "Plan9.In_channel.of_fd"
  let input_operation = "Plan9.In_channel.input"
  let close_operation = "Plan9.In_channel.close"

  let not_open_and_detached_message =
    "descriptor is not open and detached"

  let input_in_progress_message =
    "input channel operation is already in progress"

  let close_in_progress_message =
    "input channel close is already in progress"

  let closed_message = "input channel is closed"

  let error operation kind message =
    let error : Plan9_types.error =
      { Plan9_types.operation = operation; kind; message }
    in
    Error error

  let invalid_argument operation message =
    error operation Plan9_types.Invalid_argument message

  let rebind_error operation lower_error =
    let error : Plan9_types.error =
      {
        Plan9_types.operation = operation;
        kind = lower_error.Plan9_types.kind;
        message = lower_error.Plan9_types.message;
      }
    in
    Error error

  let input_lifecycle_error lifecycle =
    match lifecycle with
    | Stable_open -> assert false
    | Input_active ->
        invalid_argument input_operation input_in_progress_message
    | Close_active | Close_inactive ->
        invalid_argument input_operation close_in_progress_message
    | Terminal_closed ->
        invalid_argument input_operation closed_message

  let range_is_valid buffer_length position length =
    position >= 0
    && length >= 0
    && position <= buffer_length
    && length <= buffer_length - position

  let range_error buffer_length position length =
    invalid_argument input_operation
      ("invalid byte range: buffer length " ^ string_of_int buffer_length
       ^ ", position " ^ string_of_int position
       ^ ", length " ^ string_of_int length)

  let fill_protocol_error buffer_length count =
    error input_operation Plan9_types.Protocol_error
      ("invalid input buffer fill result: buffer length "
       ^ string_of_int buffer_length ^ ", returned count "
       ^ string_of_int count)

  let of_fd fd =
    match Fd.Private.prepare_attach fd with
    | Error _ ->
        invalid_argument of_fd_operation not_open_and_detached_message
    | Ok token ->
        let scratch = Bytes.create scratch_capacity in
        let close_attempt = { active = false; terminal = false } in
        let channel =
          {
            token;
            scratch;
            close_attempt;
            lifecycle = Stable_open;
            unread_start = 0;
            unread_end = 0;
          }
        in
        let lost_commit =
          invalid_argument of_fd_operation not_open_and_detached_message
        in
        let success = Ok channel in
        Gc.minor ();
        if Fd.Private.commit_attach token then success else lost_commit

  let input channel destination ~pos ~len =
    let destination_length = Bytes.length destination in
    if not (range_is_valid destination_length pos len) then
      range_error destination_length pos len
    else if len = 0 then
      begin match channel.lifecycle with
      | Stable_open -> zero_success
      | (Input_active | Close_active | Close_inactive | Terminal_closed)
          as lifecycle ->
          input_lifecycle_error lifecycle
      end
    else
      match channel.lifecycle with
      | (Input_active | Close_active | Close_inactive | Terminal_closed)
          as lifecycle ->
          input_lifecycle_error lifecycle
      | Stable_open ->
          channel.lifecycle <- Input_active;
          let prepared =
            try
              if channel.unread_start < channel.unread_end then
                let available = channel.unread_end - channel.unread_start in
                let count = if len < available then len else available in
                let success = Ok count in
                Input_copy (channel.unread_start, count, success)
              else begin
                channel.unread_start <- 0;
                channel.unread_end <- 0;
                let scratch_length = Bytes.length channel.scratch in
                match
                  Fd.Private.read channel.token channel.scratch
                    ~pos:0 ~len:scratch_length
                with
                | Error lower_error ->
                    Input_result (rebind_error input_operation lower_error)
                | Ok count ->
                    if count < 0 || count > scratch_length then
                      Input_result
                        (fill_protocol_error scratch_length count)
                    else if count = 0 then
                      Input_result zero_success
                    else begin
                      channel.unread_start <- 0;
                      channel.unread_end <- count;
                      let copy_count = if len < count then len else count in
                      let success = Ok copy_count in
                      Input_copy (0, copy_count, success)
                    end
              end
            with exception_value ->
              channel.lifecycle <- Stable_open;
              raise exception_value
          in
          begin match prepared with
          | Input_result result ->
              channel.lifecycle <- Stable_open;
              result
          | Input_copy (source_position, count, result) ->
              blit_bytes_noalloc channel.scratch source_position
                destination pos count;
              channel.unread_start <- source_position + count;
              channel.lifecycle <- Stable_open;
              result
          end

  let rec close channel =
    match channel.lifecycle with
    | Input_active ->
        invalid_argument close_operation input_in_progress_message
    | Close_active ->
        if channel.close_attempt.active then
          invalid_argument close_operation close_in_progress_message
        else
          assert false
    | Terminal_closed -> close_success
    | Stable_open -> start_close channel Stable_open
    | Close_inactive -> start_close channel Close_inactive

  and start_close channel expected_lifecycle =
    let attempt = channel.close_attempt in
    if channel.lifecycle != expected_lifecycle then close channel
    else begin
      attempt.active <- true;
      channel.lifecycle <- Close_active;
      let lower_result =
        try
          let lower_result = Fd.Private.close channel.token in
          attempt.terminal <- true;
          attempt.active <- false;
          channel.lifecycle <- Terminal_closed;
          channel.unread_start <- 0;
          channel.unread_end <- 0;
          lower_result
        with exception_value ->
          if attempt.terminal then raise exception_value
          else begin
            attempt.active <- false;
            channel.lifecycle <- Close_inactive;
            raise exception_value
          end
      in
      match lower_result with
      | Ok () -> close_success
      | Error lower_error -> rebind_error close_operation lower_error
    end
end

include Make (Plan9_fd)
