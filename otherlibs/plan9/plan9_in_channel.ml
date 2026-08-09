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
  val input_line :
    ?max_bytes:int -> t ->
    (string option, Plan9_types.error) result
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

  type segment_scan =
    | Scan_newline of int
    | Scan_exhausted of {
        scanned : int;
        scratch_exhausted : bool;
        window_exhausted : bool;
      }

  type line_accumulator = {
    mutable storage : bytes;
    mutable used : int;
  }

  type prepared_line =
    | Line_result of (string option, Plan9_types.error) result
    | Line_cursor of int * (string option, Plan9_types.error) result

  let scratch_capacity = 4096
  let default_max_line_bytes = 1_048_576
  let initial_line_capacity = 256

  let of_fd_operation = "Plan9.In_channel.of_fd"
  let input_operation = "Plan9.In_channel.input"
  let input_line_operation = "Plan9.In_channel.input_line"
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

  let input_lifecycle_error operation lifecycle =
    match lifecycle with
    | Stable_open -> assert false
    | Input_active ->
        invalid_argument operation input_in_progress_message
    | Close_active | Close_inactive ->
        invalid_argument operation close_in_progress_message
    | Terminal_closed ->
        invalid_argument operation closed_message

  let enter_input operation channel activate =
    match channel.lifecycle with
    | Stable_open ->
        if activate then channel.lifecycle <- Input_active;
        None
    | (Input_active | Close_active | Close_inactive | Terminal_closed)
        as lifecycle ->
        Some (input_lifecycle_error operation lifecycle)

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

  let fill_protocol_error operation buffer_length count =
    error operation Plan9_types.Protocol_error
      ("invalid input buffer fill result: buffer length "
       ^ string_of_int buffer_length ^ ", returned count "
       ^ string_of_int count)

  let refill operation channel =
    channel.unread_start <- 0;
    channel.unread_end <- 0;
    let scratch_length = Bytes.length channel.scratch in
    match
      Fd.Private.read channel.token channel.scratch
        ~pos:0 ~len:scratch_length
    with
    | Error lower_error -> rebind_error operation lower_error
    | (Ok count as result) ->
        if count < 0 || count > scratch_length then
          fill_protocol_error operation scratch_length count
        else if count = 0 then
          zero_success
        else begin
          channel.unread_start <- 0;
          channel.unread_end <- count;
          result
        end

  let scan_segment scratch unread_start unread_end scan_window =
    let available = unread_end - unread_start in
    let scan_length =
      if scan_window < available then scan_window else available
    in
    let rec scan scanned =
      if scanned = scan_length then
        Scan_exhausted
          {
            scanned;
            scratch_exhausted = scanned = available;
            window_exhausted = scanned = scan_window;
          }
      else if Bytes.unsafe_get scratch (unread_start + scanned) = '\n' then
        Scan_newline scanned
      else
        scan (scanned + 1)
    in
    scan 0

  let ensure_line_capacity accumulator max_bytes required =
    let old_capacity = Bytes.length accumulator.storage in
    if required > old_capacity then begin
      let grown_capacity =
        if old_capacity = 0 then
          if max_bytes < initial_line_capacity then max_bytes
          else initial_line_capacity
        else if old_capacity > max_bytes - old_capacity then
          max_bytes
        else
          old_capacity + old_capacity
      in
      let new_capacity =
        if required > grown_capacity then required else grown_capacity
      in
      let replacement = Bytes.create new_capacity in
      if accumulator.used > 0 then
        blit_bytes_noalloc accumulator.storage 0 replacement 0
          accumulator.used;
      accumulator.storage <- replacement
    end

  let append_line_segment accumulator max_bytes channel source_position count =
    let required = accumulator.used + count in
    let final_cursor = source_position + count in
    ensure_line_capacity accumulator max_bytes required;
    if count > 0 then
      blit_bytes_noalloc channel.scratch source_position
        accumulator.storage accumulator.used count;
    accumulator.used <- required;
    channel.unread_start <- final_cursor

  let line_success accumulator scratch source_position count =
    let length = accumulator.used + count in
    let exact = Bytes.create length in
    if accumulator.used > 0 then
      blit_bytes_noalloc accumulator.storage 0 exact 0 accumulator.used;
    if count > 0 then
      blit_bytes_noalloc scratch source_position exact accumulator.used count;
    let line = Bytes.unsafe_to_string exact in
    Ok (Some line)

  let negative_line_bound_error max_bytes =
    invalid_argument input_line_operation
      ("maximum byte count must be nonnegative: " ^ string_of_int max_bytes)

  let oversized_line_bound_error max_bytes =
    invalid_argument input_line_operation
      ("maximum byte count exceeds Sys.max_string_length: "
       ^ string_of_int max_bytes)

  let line_limit_error max_bytes =
    error input_line_operation Plan9_types.Other
      ("input line exceeds maximum of " ^ string_of_int max_bytes ^ " bytes")

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
      begin match enter_input input_operation channel false with
      | None -> zero_success
      | Some result -> result
      end
    else
      match enter_input input_operation channel true with
      | Some result -> result
      | None ->
          let prepared =
            try
              if channel.unread_start < channel.unread_end then
                let available = channel.unread_end - channel.unread_start in
                let count = if len < available then len else available in
                let success = Ok count in
                Input_copy (channel.unread_start, count, success)
              else begin
                match refill input_operation channel with
                | Error _ as result -> Input_result result
                | Ok 0 -> Input_result zero_success
                | Ok count ->
                    let copy_count = if len < count then len else count in
                    let success = Ok copy_count in
                    Input_copy (0, copy_count, success)
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

  let input_line ?(max_bytes = default_max_line_bytes) channel =
    if max_bytes < 0 then
      negative_line_bound_error max_bytes
    else if max_bytes > Sys.max_string_length then
      oversized_line_bound_error max_bytes
    else
      match enter_input input_line_operation channel true with
      | Some result -> result
      | None ->
          let prepared =
            try
              let accumulator = { storage = Bytes.empty; used = 0 } in
              let rec read_line () =
                if channel.unread_start < channel.unread_end then begin
                  let source_position = channel.unread_start in
                  let remaining = max_bytes - accumulator.used in
                  match
                    scan_segment channel.scratch source_position
                      channel.unread_end remaining
                  with
                  | Scan_newline scanned ->
                      let final_cursor = source_position + scanned + 1 in
                      let result =
                        line_success accumulator channel.scratch
                          source_position scanned
                      in
                      Line_cursor (final_cursor, result)
                  | Scan_exhausted
                      { scanned; scratch_exhausted; window_exhausted } ->
                      if window_exhausted && not scratch_exhausted then begin
                        let boundary_position = source_position + scanned in
                        if Bytes.unsafe_get channel.scratch boundary_position
                           = '\n'
                        then
                          let result =
                            line_success accumulator channel.scratch
                              source_position scanned
                          in
                          Line_cursor (boundary_position + 1, result)
                        else
                          let result = line_limit_error max_bytes in
                          Line_cursor (boundary_position, result)
                      end else begin
                        append_line_segment accumulator max_bytes channel
                          source_position scanned;
                        read_line ()
                      end
                end else
                  match refill input_line_operation channel with
                  | Error error -> Line_result (Error error)
                  | Ok 0 ->
                      if accumulator.used = 0 then
                        Line_result (Ok None)
                      else
                        Line_result
                          (line_success accumulator channel.scratch 0 0)
                  | Ok _ -> read_line ()
              in
              read_line ()
            with exception_value ->
              channel.lifecycle <- Stable_open;
              raise exception_value
          in
          begin match prepared with
          | Line_result result ->
              channel.lifecycle <- Stable_open;
              result
          | Line_cursor (final_cursor, result) ->
              channel.unread_start <- final_cursor;
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
