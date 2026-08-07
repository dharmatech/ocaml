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

module type Primitive = sig
  type capability

  val pipe :
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  val close :
    capability -> (unit, Plan9_types.native_failure) result

  val read :
    capability -> int ->
    ((bytes * int), Plan9_types.native_failure) result

  val write :
    capability -> bytes -> int -> int ->
    (int, Plan9_types.native_failure) result
end

module type S = sig
  type t
  type attachment

  val pipe : unit -> ((t * t), Plan9_types.error) result
  val read :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
  val write :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val read :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val write :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

let private_capacity = 4096

let primitive_count length =
  if length <= private_capacity then length else private_capacity

module Make (Primitive : Primitive) : S = struct
  type close_phase =
    | Inactive
    | Active
    | Terminal

  type t = {
    mutable capability : Obj.t;
    mutable state : state;
  }

  and state =
    | Unpublished
    | Open_detached
    | Public_io
    | Public_closing of public_close_attempt
    | Attached of attachment
    | Owner_io of attachment
    | Owner_closing of owner_close_attempt

  and public_close_attempt = {
    mutable public_phase : close_phase;
  }

  and attachment = {
    cell : t;
    mutable attached_state : state;
    mutable owner_io_state : state;
  }

  and owner_close_attempt = {
    owner : attachment;
    mutable owner_phase : close_phase;
  }

  type io_owner =
    | Public_owner of t
    | Attachment_owner of attachment

  let pipe_operation = "Plan9.Fd.pipe"
  let read_operation = "Plan9.Fd.read"
  let write_operation = "Plan9.Fd.write"
  let close_operation = "Plan9.Fd.close"
  let prepare_operation = "Plan9.Fd.Private.prepare_attach"

  let ownership_transferred_message =
    "descriptor ownership has been transferred"

  let close_in_progress_message =
    "descriptor close is already in progress"

  let io_in_progress_message =
    "descriptor I/O is already in progress"

  let closed_message = "descriptor is closed"

  let not_open_and_detached_message =
    "descriptor is not open and detached"

  let unauthorized_token_message =
    "attachment token is not the committed owner"

  let lifecycle_error operation message =
    let error : Plan9_types.error =
      {
        Plan9_types.operation = operation;
        kind = Plan9_types.Invalid_argument;
        message = message;
      }
    in
    Error error

  let native_error operation failure =
    Error (Plan9_types.error_of_native operation failure)

  let zero_success = Ok 0

  let range_is_valid buffer_length position length =
    position >= 0
    && length >= 0
    && position <= buffer_length
    && length <= buffer_length - position

  let range_error operation buffer_length position length =
    lifecycle_error operation
      ("invalid byte range: buffer length " ^ string_of_int buffer_length
       ^ ", position " ^ string_of_int position
       ^ ", length " ^ string_of_int length)

  let read_protocol_error requested staging_length count =
    let error : Plan9_types.error =
      {
        Plan9_types.operation = read_operation;
        kind = Plan9_types.Protocol_error;
        message =
          "invalid descriptor read result: requested "
          ^ string_of_int requested ^ " bytes, staging has "
          ^ string_of_int staging_length ^ " bytes, returned count "
          ^ string_of_int count;
      }
    in
    Error error

  let write_protocol_error requested count =
    let error : Plan9_types.error =
      {
        Plan9_types.operation = write_operation;
        kind = Plan9_types.Protocol_error;
        message =
          "invalid descriptor write result: requested "
          ^ string_of_int requested ^ " bytes, returned count "
          ^ string_of_int count;
      }
    in
    Error error

  let short_write_error requested written =
    let error : Plan9_types.error =
      {
        Plan9_types.operation = write_operation;
        kind = Plan9_types.Other;
        message =
          "descriptor write was short: requested "
          ^ string_of_int requested ^ " bytes, wrote "
          ^ string_of_int written ^ " bytes";
      }
    in
    Error error

  let public_io_lifecycle_error operation cell =
    match cell.state with
    | Unpublished -> assert false
    | Open_detached -> assert false
    | Public_io -> lifecycle_error operation io_in_progress_message
    | Public_closing attempt ->
        begin match attempt.public_phase with
        | Active | Inactive ->
            lifecycle_error operation close_in_progress_message
        | Terminal -> lifecycle_error operation closed_message
        end
    | Attached _ | Owner_io _ | Owner_closing _ ->
        lifecycle_error operation ownership_transferred_message

  let attachment_io_lifecycle_error operation token =
    match token.cell.state with
    | Unpublished -> assert false
    | Open_detached | Public_io | Public_closing _ ->
        lifecycle_error operation unauthorized_token_message
    | Attached owner ->
        if owner == token then assert false
        else lifecycle_error operation unauthorized_token_message
    | Owner_io owner ->
        if owner == token then
          lifecycle_error operation io_in_progress_message
        else
          lifecycle_error operation unauthorized_token_message
    | Owner_closing attempt ->
        if attempt.owner != token then
          lifecycle_error operation unauthorized_token_message
        else
          begin match attempt.owner_phase with
          | Active | Inactive ->
              lifecycle_error operation close_in_progress_message
          | Terminal -> lifecycle_error operation closed_message
          end

  let io_lifecycle_error operation = function
    | Public_owner cell -> public_io_lifecycle_error operation cell
    | Attachment_owner token ->
        attachment_io_lifecycle_error operation token

  let pipe () =
    let left =
      { capability = Obj.repr (); state = Unpublished }
    in
    let right =
      { capability = Obj.repr (); state = Unpublished }
    in
    let pair = left, right in
    let success = Ok pair in
    match Primitive.pipe () with
    | Error failure -> native_error pipe_operation failure
    | Ok (left_capability, right_capability) ->
        left.capability <- Obj.repr left_capability;
        right.capability <- Obj.repr right_capability;
        left.state <- Open_detached;
        right.state <- Open_detached;
        success

  let read_with_owner owner buffer ~pos ~len =
    let buffer_length = Bytes.length buffer in
    if not (range_is_valid buffer_length pos len) then
      range_error read_operation buffer_length pos len
    else if len = 0 then
      let authorized =
        match owner with
        | Public_owner cell -> cell.state == Open_detached
        | Attachment_owner token ->
            begin match token.cell.state with
            | Attached current_owner -> current_owner == token
            | Unpublished | Open_detached | Public_io | Public_closing _
            | Owner_io _ | Owner_closing _ -> false
            end
      in
      if authorized then zero_success
      else io_lifecycle_error read_operation owner
    else
      let requested = primitive_count len in
      let cell =
        match owner with
        | Public_owner cell -> cell
        | Attachment_owner token -> token.cell
      in
      let stable_state =
        match owner with
        | Public_owner _ -> Open_detached
        | Attachment_owner token -> token.attached_state
      in
      let io_state =
        match owner with
        | Public_owner _ -> Public_io
        | Attachment_owner token -> token.owner_io_state
      in
      let authorized =
        match owner with
        | Public_owner _ -> cell.state == Open_detached
        | Attachment_owner token ->
            begin match cell.state with
            | Attached current_owner -> current_owner == token
            | Unpublished | Open_detached | Public_io | Public_closing _
            | Owner_io _ | Owner_closing _ -> false
            end
      in
      if not authorized then io_lifecycle_error read_operation owner
      else begin
        cell.state <- io_state;
        let result =
          try
            let result =
              Primitive.read (Obj.obj cell.capability) requested
            in
            cell.state <- stable_state;
            result
          with exception_value ->
            cell.state <- stable_state;
            raise exception_value
        in
        match result with
        | Error failure -> native_error read_operation failure
        | Ok (staging, count) ->
            let staging_length = Bytes.length staging in
            if staging_length <> requested || count < 0 || count > requested
            then read_protocol_error requested staging_length count
            else if count = 0 then zero_success
            else
              let success = Ok count in
              Bytes.blit staging 0 buffer pos count;
              success
      end

  let write_with_owner owner buffer ~pos ~len =
    let buffer_length = Bytes.length buffer in
    if not (range_is_valid buffer_length pos len) then
      range_error write_operation buffer_length pos len
    else if len = 0 then
      let authorized =
        match owner with
        | Public_owner cell -> cell.state == Open_detached
        | Attachment_owner token ->
            begin match token.cell.state with
            | Attached current_owner -> current_owner == token
            | Unpublished | Open_detached | Public_io | Public_closing _
            | Owner_io _ | Owner_closing _ -> false
            end
      in
      if authorized then zero_success
      else io_lifecycle_error write_operation owner
    else
      let requested = primitive_count len in
      let full_success = Ok requested in
      let cell =
        match owner with
        | Public_owner cell -> cell
        | Attachment_owner token -> token.cell
      in
      let stable_state =
        match owner with
        | Public_owner _ -> Open_detached
        | Attachment_owner token -> token.attached_state
      in
      let io_state =
        match owner with
        | Public_owner _ -> Public_io
        | Attachment_owner token -> token.owner_io_state
      in
      let authorized =
        match owner with
        | Public_owner _ -> cell.state == Open_detached
        | Attachment_owner token ->
            begin match cell.state with
            | Attached current_owner -> current_owner == token
            | Unpublished | Open_detached | Public_io | Public_closing _
            | Owner_io _ | Owner_closing _ -> false
            end
      in
      if not authorized then io_lifecycle_error write_operation owner
      else begin
        cell.state <- io_state;
        let result =
          try
            let result =
              Primitive.write (Obj.obj cell.capability) buffer pos requested
            in
            cell.state <- stable_state;
            result
          with exception_value ->
            cell.state <- stable_state;
            raise exception_value
        in
        match result with
        | Error failure -> native_error write_operation failure
        | Ok count ->
            if count < 0 || count > requested then
              write_protocol_error requested count
            else if count = requested then full_success
            else short_write_error requested count
      end

  let read cell buffer ~pos ~len =
    read_with_owner (Public_owner cell) buffer ~pos ~len

  let write cell buffer ~pos ~len =
    write_with_owner (Public_owner cell) buffer ~pos ~len

  let rec close cell =
    match cell.state with
    | Unpublished -> assert false
    | Open_detached ->
        let attempt = { public_phase = Inactive } in
        let closing = Public_closing attempt in
        begin match cell.state with
        | Open_detached ->
            attempt.public_phase <- Active;
            cell.state <- closing;
            let result =
              try Primitive.close (Obj.obj cell.capability)
              with exception_value ->
                attempt.public_phase <- Inactive;
                raise exception_value
            in
            attempt.public_phase <- Terminal;
            begin match result with
            | Ok () -> Ok ()
            | Error failure -> native_error close_operation failure
            end
        | _ -> close cell
        end
    | Public_io ->
        lifecycle_error close_operation io_in_progress_message
    | Public_closing attempt ->
        begin match attempt.public_phase with
        | Active ->
            lifecycle_error close_operation close_in_progress_message
        | Inactive ->
            attempt.public_phase <- Active;
            let result =
              try Primitive.close (Obj.obj cell.capability)
              with exception_value ->
                attempt.public_phase <- Inactive;
                raise exception_value
            in
            attempt.public_phase <- Terminal;
            begin match result with
            | Ok () -> Ok ()
            | Error failure -> native_error close_operation failure
            end
        | Terminal -> Ok ()
        end
    | Attached _ | Owner_io _ | Owner_closing _ ->
        lifecycle_error close_operation ownership_transferred_message

  module Private = struct
    let prepare_attach cell =
      match cell.state with
      | Open_detached ->
          let token =
            {
              cell;
              attached_state = Unpublished;
              owner_io_state = Unpublished;
            }
          in
          let attached_state = Attached token in
          let owner_io_state = Owner_io token in
          token.attached_state <- attached_state;
          token.owner_io_state <- owner_io_state;
          let success = Ok token in
          begin match cell.state with
          | Open_detached -> success
          | _ ->
              lifecycle_error prepare_operation not_open_and_detached_message
          end
      | Unpublished -> assert false
      | Public_io | Public_closing _ | Attached _ | Owner_io _
      | Owner_closing _ ->
          lifecycle_error prepare_operation not_open_and_detached_message

    let commit_attach token =
      match token.cell.state with
      | Open_detached ->
          token.cell.state <- token.attached_state;
          true
      | Unpublished | Public_io | Public_closing _ | Attached _ | Owner_io _
      | Owner_closing _ ->
          false

    let read token buffer ~pos ~len =
      read_with_owner (Attachment_owner token) buffer ~pos ~len

    let write token buffer ~pos ~len =
      write_with_owner (Attachment_owner token) buffer ~pos ~len

    let rec close token =
      match token.cell.state with
      | Unpublished -> assert false
      | Open_detached | Public_io | Public_closing _ ->
          lifecycle_error close_operation unauthorized_token_message
      | Attached owner ->
          if owner != token then
            lifecycle_error close_operation unauthorized_token_message
          else
            let attempt = { owner = token; owner_phase = Inactive } in
            let closing = Owner_closing attempt in
            begin match token.cell.state with
            | Attached current_owner when current_owner == token ->
                attempt.owner_phase <- Active;
                token.cell.state <- closing;
                let result =
                  try Primitive.close (Obj.obj token.cell.capability)
                  with exception_value ->
                    attempt.owner_phase <- Inactive;
                    raise exception_value
                in
                attempt.owner_phase <- Terminal;
                begin match result with
                | Ok () -> Ok ()
                | Error failure -> native_error close_operation failure
                end
            | _ -> close token
            end
      | Owner_io owner ->
          if owner == token then
            lifecycle_error close_operation io_in_progress_message
          else
            lifecycle_error close_operation unauthorized_token_message
      | Owner_closing attempt ->
          if attempt.owner != token then
            lifecycle_error close_operation unauthorized_token_message
          else
            begin match attempt.owner_phase with
            | Active ->
                lifecycle_error close_operation close_in_progress_message
            | Inactive ->
                attempt.owner_phase <- Active;
                let result =
                  try Primitive.close (Obj.obj token.cell.capability)
                  with exception_value ->
                    attempt.owner_phase <- Inactive;
                    raise exception_value
                in
                attempt.owner_phase <- Terminal;
                begin match result with
                | Ok () -> Ok ()
                | Error failure -> native_error close_operation failure
                end
            | Terminal -> Ok ()
            end
  end
end

include Make (struct
  type capability = Plan9_primitive.descriptor_capability

  let pipe = Plan9_primitive.descriptor_pipe
  let close = Plan9_primitive.descriptor_close
  let read = Plan9_primitive.descriptor_read
  let write = Plan9_primitive.descriptor_write
end)
