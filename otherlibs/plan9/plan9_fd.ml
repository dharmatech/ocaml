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
end

module type S = sig
  type t
  type attachment

  val pipe : unit -> ((t * t), Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

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
    | Public_closing of public_close_attempt
    | Attached of attachment
    | Owner_closing of owner_close_attempt

  and public_close_attempt = {
    mutable public_phase : close_phase;
  }

  and attachment = {
    cell : t;
    mutable attached_state : state;
  }

  and owner_close_attempt = {
    owner : attachment;
    mutable owner_phase : close_phase;
  }

  let pipe_operation = "Plan9.Fd.pipe"
  let close_operation = "Plan9.Fd.close"
  let prepare_operation = "Plan9.Fd.Private.prepare_attach"

  let ownership_transferred_message =
    "descriptor ownership has been transferred"

  let close_in_progress_message =
    "descriptor close is already in progress"

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
    | Attached _ | Owner_closing _ ->
        lifecycle_error close_operation ownership_transferred_message

  module Private = struct
    let prepare_attach cell =
      match cell.state with
      | Open_detached ->
          let token = { cell; attached_state = Unpublished } in
          let attached_state = Attached token in
          token.attached_state <- attached_state;
          let success = Ok token in
          begin match cell.state with
          | Open_detached -> success
          | _ ->
              lifecycle_error prepare_operation not_open_and_detached_message
          end
      | Unpublished -> assert false
      | Public_closing _ | Attached _ | Owner_closing _ ->
          lifecycle_error prepare_operation not_open_and_detached_message

    let commit_attach token =
      match token.cell.state with
      | Open_detached ->
          token.cell.state <- token.attached_state;
          true
      | Unpublished | Public_closing _ | Attached _ | Owner_closing _ ->
          false

    let rec close token =
      match token.cell.state with
      | Unpublished -> assert false
      | Open_detached | Public_closing _ ->
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
end)
