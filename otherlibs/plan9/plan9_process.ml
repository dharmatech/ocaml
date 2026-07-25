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

let wait_succeeded wait_msg = wait_msg.message = ""

type native_failure = {
  native_kind : int;
  native_message : string;
}

type native_pending = {
  native_process_id : int64;
  native_pid : int;
  native_handshake : int;
  native_detail : native_failure;
  native_queue_loss : native_failure option;
}

type native_wait_event = {
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

module Make (Native : Native) = struct
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

  and handle_state =
    | Active
    | Completed of int64 * wait_msg
    | Queue_lost of int64 * error

  and handshake_state =
    | Exec_confirmed
    | Exec_failed of error
    | Handshake_failed of launch_incomplete

  and t = {
    process_id : process_id;
    pid : pid;
    handshake : handshake_state;
    mutable state : handle_state;
  }

  type coordinator_failure =
    | Invariant_failure of error
    | Malformed_failure of error

  type foreign_item = {
    sequence : int64;
    wait_msg : wait_msg;
  }

  type processed =
    | Processed_managed of t * wait_msg
    | Processed_foreign_queued of foreign_item
    | Processed_foreign_returned of wait_msg
    | Processed_error of error * t list
    | Processed_malformed of error * t list

  type retained_processing = {
    event : native_wait_event;
    processed : processed;
    mutable applied : bool;
  }

  type foreign_action =
    | Queue_foreign
    | Return_foreign

  type pending_acknowledgment =
    | Acknowledging_pending of t
    | Recovered_pending of t

  let owners_by_id : (process_id, t) Hashtbl.t = Hashtbl.create 17
  let active_by_pid : (pid, t) Hashtbl.t = Hashtbl.create 17
  let pending_handles : (process_id, t) Hashtbl.t = Hashtbl.create 17
  let pending_acknowledgments :
      (process_id, pending_acknowledgment) Hashtbl.t =
    Hashtbl.create 17
  let coordinator_failure : coordinator_failure option ref = ref None
  let retained_processing : retained_processing option ref = ref None
  let acknowledging_processing : retained_processing option ref = ref None

  let dummy_wait_msg =
    {
      pid = 0;
      user_time_ms = 0L;
      system_time_ms = 0L;
      elapsed_time_ms = 0L;
      message = "";
    }

  let foreign_capacity =
    if Native.foreign_capacity <= 0 then
      invalid_arg "Plan9.Process: foreign FIFO capacity must be positive"
    else
      Native.foreign_capacity

  let foreign_sequences = Array.make foreign_capacity 0L
  let foreign_messages = Array.make foreign_capacity dummy_wait_msg
  let foreign_head = ref 0
  let foreign_count = ref 0

  let protocol_error operation message =
    { operation; kind = Protocol_error; message }

  let fail_invariant message =
    let error = protocol_error "Plan9.Process.coordinator" message in
    begin match !coordinator_failure with
    | None -> coordinator_failure := Some (Invariant_failure error)
    | Some _ -> ()
    end;
    error

  let fail_malformed error =
    begin match !coordinator_failure with
    | None -> coordinator_failure := Some (Malformed_failure error)
    | Some _ -> ()
    end

  let unresolved_reason () =
    match !coordinator_failure with
    | Some (Invariant_failure error) ->
        Some (Coordinator_invariant_failure error)
    | Some (Malformed_failure error) ->
        Some (Malformed_native_record error)
    | None -> None

  let compare_handle left right =
    Int64.compare left.process_id right.process_id

  let owner_list () =
    Hashtbl.fold (fun _ process processes -> process :: processes)
      owners_by_id []
    |> List.sort compare_handle

  let same_handle left right =
    Int64.equal left.process_id right.process_id

  let remove_active_mapping process =
    begin match Hashtbl.find_opt active_by_pid process.pid with
    | Some mapped when same_handle mapped process ->
        Hashtbl.remove active_by_pid process.pid
    | Some _ ->
        ignore (fail_invariant
          "active PID mapping changed while terminalizing a process")
    | None ->
        ignore (fail_invariant
          "active PID mapping disappeared while terminalizing a process")
    end;
    Hashtbl.remove owners_by_id process.process_id

  let terminalize_completed sequence process wait_msg =
    match process.state with
    | Active ->
        process.state <- Completed (sequence, wait_msg);
        remove_active_mapping process
    | Completed (seen_sequence, _) when Int64.equal seen_sequence sequence ->
        ()
    | Queue_lost (seen_sequence, _) when Int64.equal seen_sequence sequence ->
        ignore (fail_invariant
          "one native wait event both completed and lost a process")
    | Completed _ | Queue_lost _ ->
        ignore (fail_invariant
          "a terminal process received a second native wait event")

  let terminalize_lost sequence error process =
    match process.state with
    | Active ->
        process.state <- Queue_lost (sequence, error);
        remove_active_mapping process
    | Queue_lost (seen_sequence, _) when Int64.equal seen_sequence sequence ->
        ()
    | Completed _ | Queue_lost _ -> ()

  let fifo_index offset =
    (!foreign_head + offset) mod foreign_capacity

  let fifo_contains sequence =
    let rec loop offset =
      if offset = !foreign_count then false
      else if Int64.equal foreign_sequences.(fifo_index offset) sequence then
        true
      else
        loop (offset + 1)
    in
    loop 0

  let fifo_enqueue item =
    if fifo_contains item.sequence then ()
    else if !foreign_count = foreign_capacity then
      ignore (fail_invariant
        "the foreign completion FIFO overflowed after its capacity check")
    else begin
      let index = fifo_index !foreign_count in
      foreign_sequences.(index) <- item.sequence;
      foreign_messages.(index) <- item.wait_msg;
      incr foreign_count
    end

  let fifo_take_one () =
    if !foreign_count = 0 then None
    else begin
      let wait_msg = foreign_messages.(!foreign_head) in
      foreign_messages.(!foreign_head) <- dummy_wait_msg;
      foreign_sequences.(!foreign_head) <- 0L;
      foreign_head := (!foreign_head + 1) mod foreign_capacity;
      decr foreign_count;
      Some wait_msg
    end

  let fifo_take_all () =
    let rec collect offset result =
      if offset = !foreign_count then List.rev result
      else collect (offset + 1)
          (foreign_messages.(fifo_index offset) :: result)
    in
    let result = collect 0 [] in
    Array.fill foreign_sequences 0 foreign_capacity 0L;
    Array.fill foreign_messages 0 foreign_capacity dummy_wait_msg;
    foreign_head := 0;
    foreign_count := 0;
    result

  let handshake_of_pending pending =
    let operation = "Plan9.Process.spawn" in
    let detail = error_of_native operation pending.native_detail in
    match pending.native_handshake with
    | 1 -> Exec_confirmed
    | 2 -> Exec_failed detail
    | 3 -> Handshake_failed (Handshake_interrupted detail)
    | 4 -> Handshake_failed (Handshake_protocol_error detail)
    | _ ->
        Handshake_failed
          (Handshake_protocol_error
             (protocol_error operation
                "native pending record has an unknown handshake state"))

  let validate_pending_record pending =
    let malformed message =
      fail_malformed (protocol_error "Plan9.Process.adopt" message)
    in
    if pending.native_process_id <= 0L then
      malformed "native pending record has a nonpositive logical identity";
    if pending.native_pid <= 0 then
      malformed "native pending record has a nonpositive PID";
    if pending.native_handshake < 1 || pending.native_handshake > 4 then
      malformed "native pending record has an unknown handshake state";
    match pending.native_queue_loss with
    | Some loss
      when loss.native_kind <> 3
           || loss.native_message <> "no living children" ->
        malformed
          "native pending record has an inexact wait-queue loss marker";
        false
    | Some _ -> true
    | None -> false

  let acknowledge_pending process =
    let process_id = process.process_id in
    (* The uncertainty table owns the ML recovery identity before the native
       registry can release its entry. *)
    Hashtbl.replace pending_acknowledgments process_id
      (Acknowledging_pending process);
    Hashtbl.remove pending_handles process_id;
    match Native.acknowledge_pending process_id with
    | true ->
        begin match process.state with
        | Active -> Hashtbl.remove pending_acknowledgments process_id
        | Completed _ | Queue_lost _ ->
            Hashtbl.replace pending_acknowledgments process_id
              (Recovered_pending process)
        end
    | false ->
        Hashtbl.replace pending_handles process_id process;
        Hashtbl.remove pending_acknowledgments process_id;
        ignore (fail_invariant
          "native pending-child adoption acknowledgment failed")
    | exception exn ->
        raise exn

  let settle_pending_acknowledgments () =
    let pending =
      Hashtbl.fold
        (fun process_id acknowledgment entries ->
          (process_id, acknowledgment) :: entries)
        pending_acknowledgments []
      |> List.sort
           (fun (left, _) (right, _) -> Int64.compare left right)
    in
    List.iter
      (fun (process_id, acknowledgment) ->
        match acknowledgment with
        | Recovered_pending _ -> ()
        | Acknowledging_pending process ->
            Hashtbl.remove pending_handles process_id;
            match Native.acknowledge_pending process_id with
            (* [false] is conclusive here: an earlier, interrupted call
               released this exact identity.  A different pending child
               cannot match it. *)
            | true | false ->
                begin match process.state with
                | Active ->
                    Hashtbl.remove pending_acknowledgments process_id
                | Completed _ | Queue_lost _ ->
                    Hashtbl.replace pending_acknowledgments process_id
                      (Recovered_pending process)
                end
            | exception exn ->
                raise exn)
      pending

  let apply_pending_loss pending process =
    match pending.native_queue_loss with
    | None -> ()
    | Some native_error ->
        let error =
          error_of_native "Plan9.Process.await" native_error
        in
        begin match process.state with
        | Active ->
            process.state <- Queue_lost (0L, error);
            begin match Hashtbl.find_opt active_by_pid process.pid with
            | Some mapped when same_handle mapped process ->
                Hashtbl.remove active_by_pid process.pid
            | Some _ | None -> ()
            end;
            Hashtbl.remove owners_by_id process.process_id
        | Completed _ | Queue_lost _ -> ()
        end

  let adopt_pending_record pending =
    let apply_queue_loss = validate_pending_record pending in
    let existing =
      match
        Hashtbl.find_opt pending_acknowledgments pending.native_process_id
      with
      | Some (Acknowledging_pending process)
      | Some (Recovered_pending process) -> Some process
      | None ->
          begin match
            Hashtbl.find_opt pending_handles pending.native_process_id
          with
          | Some process -> Some process
          | None -> Hashtbl.find_opt owners_by_id pending.native_process_id
          end
    in
    match existing with
    | Some process ->
        if process.pid <> pending.native_pid then
          ignore (fail_invariant
            "one native process identity was published with two PIDs");
        if apply_queue_loss then apply_pending_loss pending process;
        acknowledge_pending process;
        process
    | None ->
        let process =
          {
            process_id = pending.native_process_id;
            pid = pending.native_pid;
            handshake = handshake_of_pending pending;
            state = Active;
          }
        in
        Hashtbl.add pending_handles process.process_id process;
        if apply_queue_loss then
          apply_pending_loss pending process
        else begin
            Hashtbl.add owners_by_id process.process_id process;
            begin match Hashtbl.find_opt active_by_pid process.pid with
            | None -> Hashtbl.add active_by_pid process.pid process
            | Some earlier ->
                ignore earlier;
                ignore (fail_invariant
                  "two unresolved managed processes have the same native PID")
            end
        end;
        acknowledge_pending process;
        process

  let adopt_pending () =
    Native.pending ()
    |> Array.to_list
    |> List.sort
         (fun left right ->
           Int64.compare left.native_process_id right.native_process_id)
    |> List.map adopt_pending_record

  let unresolved_owners () =
    settle_pending_acknowledgments ();
    let adopted = adopt_pending () in
    let active = owner_list () in
    let acknowledgment_recoveries =
      Hashtbl.fold
        (fun _ acknowledgment processes ->
          match acknowledgment with
          | Recovered_pending process -> process :: processes
          | Acknowledging_pending _ -> processes)
        pending_acknowledgments []
    in
    let seen : (process_id, unit) Hashtbl.t =
      Hashtbl.create
        (List.length acknowledgment_recoveries
         + List.length adopted + List.length active)
    in
    let add process result =
      if Hashtbl.mem seen process.process_id then result
      else begin
        Hashtbl.add seen process.process_id ();
        process :: result
      end
    in
    List.fold_right add
      (List.rev_append acknowledgment_recoveries
         (List.rev_append adopted active))
      []
    |> List.sort compare_handle

  let wait_msg_of_event event =
    if event.native_wait_pid <= 0 then
      Result.Error
        (protocol_error "Plan9.Process.await"
           "native wait record has a nonpositive PID")
    else if event.native_user_time_ms < 0L
            || event.native_system_time_ms < 0L
            || event.native_elapsed_time_ms < 0L
    then
      Result.Error
        (protocol_error "Plan9.Process.await"
           "native wait record has a negative zero-extended timing field")
    else if String.length event.native_event_detail.native_message > 127 then
      Result.Error
        (protocol_error "Plan9.Process.await"
           "native wait record exceeds the measured message bound")
    else
      Ok
        {
          pid = event.native_wait_pid;
          user_time_ms = event.native_user_time_ms;
          system_time_ms = event.native_system_time_ms;
          elapsed_time_ms = event.native_elapsed_time_ms;
          message = event.native_event_detail.native_message;
        }

  let prepare_processing foreign_action event =
    let current_owners = owner_list () in
    let processed =
      if event.native_sequence <= 0L then
        Processed_malformed
          (protocol_error "Plan9.Process.await"
             "native wait event has a nonpositive logical sequence",
           current_owners)
      else if event.native_event_detail.native_kind = 3
              && event.native_event_detail.native_message
                 <> "no living children"
      then
        Processed_malformed
          (protocol_error "Plan9.Process.await"
             "native wait event has an inexact No_children marker",
           current_owners)
      else match event.native_event_kind with
      | 0 ->
          begin match wait_msg_of_event event with
          | Result.Error error ->
              Processed_malformed (error, current_owners)
          | Ok wait_msg ->
              begin match Hashtbl.find_opt active_by_pid wait_msg.pid with
              | Some process -> Processed_managed (process, wait_msg)
              | None ->
                  begin match foreign_action with
                  | Queue_foreign ->
                      Processed_foreign_queued
                        { sequence = event.native_sequence; wait_msg }
                  | Return_foreign -> Processed_foreign_returned wait_msg
                  end
              end
          end
      | 1 ->
          Processed_error
            (error_of_native "Plan9.Process.await" event.native_event_detail,
             current_owners)
      | 2 ->
          Processed_malformed
            (error_of_native "Plan9.Process.await" event.native_event_detail,
             current_owners)
      | _ ->
          Processed_malformed
            (protocol_error "Plan9.Process.await"
               "native wait event has an unknown kind",
             current_owners)
    in
    { event; processed; applied = false }

  let apply_processing processing =
    if not processing.applied then begin
      begin match processing.processed with
      | Processed_managed (process, wait_msg) ->
          terminalize_completed processing.event.native_sequence process
            wait_msg
      | Processed_foreign_queued item -> fifo_enqueue item
      | Processed_foreign_returned _ -> ()
      | Processed_error (error, processes) ->
          if error.kind = No_children then
            List.iter
              (terminalize_lost processing.event.native_sequence error)
              processes
      | Processed_malformed (error, _) -> fail_malformed error
      end;
      processing.applied <- true
    end

  let acknowledge_processing processing =
    (* [acknowledging_processing] preserves the routed result while the ML
       retained marker is cleared before C can release the native event. *)
    acknowledging_processing := Some processing;
    retained_processing := None;
    match Native.acknowledge_wait processing.event.native_sequence with
    | true ->
        acknowledging_processing := None;
        true
    | false ->
        retained_processing := Some processing;
        acknowledging_processing := None;
        ignore (fail_invariant "native wait-event acknowledgment failed");
        false
    | exception exn ->
        raise exn

  let settle_wait_acknowledgment () =
    match !acknowledging_processing with
    | None -> ()
    | Some processing ->
        begin match !retained_processing with
        | Some retained
          when Int64.equal retained.event.native_sequence
                 processing.event.native_sequence ->
            retained_processing := None
        | Some _ ->
            ignore (fail_invariant
              "wait acknowledgment recovery found a different retained event")
        | None -> ()
        end;
        match Native.acknowledge_wait processing.event.native_sequence with
        (* [false] means the interrupted call already released this exact
           sequence.  Retrying the old sequence cannot release its successor. *)
        | true | false ->
            acknowledging_processing := None
        | exception exn ->
            raise exn

  let consume_native_event foreign_action =
    settle_wait_acknowledgment ();
    let event = Native.await () in
    let processing, may_acknowledge =
      match !retained_processing with
      | None ->
          let processing = prepare_processing foreign_action event in
          retained_processing := Some processing;
          processing, true
      | Some processing
        when Int64.equal processing.event.native_sequence
               event.native_sequence ->
          processing, true
      | Some _ ->
          let error =
            fail_invariant
              "native await replaced an unacknowledged wait event"
          in
          let processes = owner_list () in
          {
            event;
            processed = Processed_malformed (error, processes);
            applied = false;
          },
          false
    in
    apply_processing processing;
    if may_acknowledge then ignore (acknowledge_processing processing);
    processing.processed

  let unresolved () =
    settle_wait_acknowledgment ();
    unresolved_owners ()

  let wait_result_of_terminal process =
    match process.state with
    | Completed (_, wait_msg) -> Some (Wait_finished wait_msg)
    | Queue_lost (_, error) ->
        Hashtbl.remove pending_acknowledgments process.process_id;
        Some
          (Wait_terminal_failure
             { process; reason = Wait_queue_lost error })
    | Active -> None

  let wait_unresolved process reason =
    Wait_unresolved { process; reason }

  let rec wait process =
    settle_wait_acknowledgment ();
    ignore (adopt_pending ());
    match wait_result_of_terminal process with
    | Some result -> result
    | None ->
        begin match unresolved_reason () with
        | Some reason -> wait_unresolved process reason
        | None when !foreign_count = foreign_capacity ->
            wait_unresolved process
              (Foreign_backpressure
                 { queued = !foreign_count; capacity = foreign_capacity })
        | None ->
            begin match consume_native_event Queue_foreign with
            | Processed_managed _ ->
                begin match wait_result_of_terminal process with
                | Some result -> result
                | None -> wait process
                end
            | Processed_foreign_queued _ ->
                if !foreign_count = foreign_capacity then
                  wait_unresolved process
                    (Foreign_backpressure
                       {
                         queued = !foreign_count;
                         capacity = foreign_capacity;
                       })
                else
                  wait process
            | Processed_foreign_returned _ ->
                wait_unresolved process
                  (Coordinator_invariant_failure
                     (fail_invariant
                        "particular wait returned an unqueued foreign event"))
            | Processed_error (error, _) ->
                if error.kind = No_children then
                  begin match wait_result_of_terminal process with
                  | Some result -> result
                  | None ->
                      wait_unresolved process
                        (Coordinator_invariant_failure
                           (fail_invariant
                              "No_children did not terminalize the target"))
                  end
                else if error.kind = Interrupted then
                  wait_unresolved process (Await_interrupted error)
                else
                  wait_unresolved process (Await_error error)
            | Processed_malformed (error, _) ->
                wait_unresolved process (Malformed_native_record error)
            end
        end

  let wait_any () =
    settle_wait_acknowledgment ();
    ignore (adopt_pending ());
    match fifo_take_one () with
    | Some wait_msg -> Ok (Wait_any_finished (Foreign wait_msg))
    | None ->
        let processes = owner_list () in
        begin match unresolved_reason () with
        | Some reason when processes <> [] ->
            Ok (Wait_any_unresolved { processes; reason })
        | Some (Coordinator_invariant_failure error)
        | Some (Malformed_native_record error) -> Result.Error error
        | Some _ ->
            Result.Error
              (fail_invariant
                 "coordinator exposed an impossible ownerless wait state")
        | None ->
            begin match consume_native_event Return_foreign with
            | Processed_managed (process, wait_msg) ->
                Ok (Wait_any_finished (Managed (process, wait_msg)))
            | Processed_foreign_returned wait_msg ->
                Ok (Wait_any_finished (Foreign wait_msg))
            | Processed_foreign_queued _ ->
                Result.Error
                  (fail_invariant
                     "wait_any queued a foreign event instead of returning it")
            | Processed_error (error, affected) ->
                if error.kind = No_children && affected <> [] then
                  Ok
                    (Wait_any_terminal_failure
                       {
                         processes = affected;
                         reason = Wait_queue_lost error;
                       })
                else if error.kind = No_children then
                  Result.Error error
                else
                  let reason =
                    if error.kind = Interrupted then Await_interrupted error
                    else Await_error error
                  in
                  if affected = [] then Result.Error error
                  else Ok (Wait_any_unresolved { processes = affected; reason })
            | Processed_malformed (error, affected) ->
                if affected = [] then Result.Error error
                else
                  Ok
                    (Wait_any_unresolved
                       {
                         processes = affected;
                         reason = Malformed_native_record error;
                       })
            end
        end

  let take_foreign_completions () =
    settle_wait_acknowledgment ();
    fifo_take_all ()

  let stdout_arguments = function
    | Inherit -> 0, ""
    | Truncate path -> 1, path

  let coordinator_launch_error () =
    match !coordinator_failure with
    | Some (Invariant_failure error) -> Some error
    | Some (Malformed_failure error) -> Some error
    | None -> None

  let adoption_launch_failure process =
    match unresolved_reason () with
    | Some (Coordinator_invariant_failure error)
    | Some (Malformed_native_record error) ->
        Some
          (Launch_incomplete
             {
               process;
               reason = Handshake_protocol_error error;
             })
    | Some (Await_interrupted _)
    | Some (Await_error _)
    | Some (Foreign_backpressure _) ->
        assert false
    | None -> None

  let spawn ?(stdout = Inherit) ~program ~args () =
    settle_wait_acknowledgment ();
    match coordinator_launch_error () with
    | Some error -> Result.Error error
    | None ->
        let argv =
          Array.init (Array.length args + 1)
            (fun index -> if index = 0 then program else args.(index - 1))
        in
        let stdout_kind, stdout_path = stdout_arguments stdout in
        begin match
          Native.spawn program argv stdout_kind stdout_path Native.spawn_flags
        with
        | Result.Error native_error ->
            Result.Error
              (error_of_native "Plan9.Process.spawn" native_error)
        | Ok pending ->
            let process = adopt_pending_record pending in
            begin match adoption_launch_failure process with
            | Some launch -> Ok launch
            | None ->
                begin match process.handshake with
                | Exec_confirmed -> Ok (Launch_started process)
                | Handshake_failed reason ->
                    Ok (Launch_incomplete { process; reason })
                | Exec_failed exec_error ->
                    begin match wait process with
                    | Wait_finished _ -> Result.Error exec_error
                    | Wait_unresolved _ | Wait_terminal_failure _ ->
                        Ok
                          (Launch_incomplete
                             {
                               process;
                               reason = Exec_failure_unreaped exec_error;
                             })
                    end
                end
            end
        end

  let run ?(stdout = Inherit) ~program ~args () =
    match spawn ~stdout ~program ~args () with
    | Result.Error error -> Result.Error error
    | Ok (Launch_started process) ->
        begin match wait process with
        | Wait_finished wait_msg -> Ok (Run_finished wait_msg)
        | Wait_unresolved { reason; _ } ->
            Ok
              (Run_incomplete
                 { process; reason = Run_wait_unresolved reason })
        | Wait_terminal_failure
            { reason = Wait_queue_lost wait_error; _ } ->
            Ok
              (Run_terminal_failure
                 {
                   process;
                   reason =
                     Run_wait_queue_lost
                       { wait_error; exec_error = None };
                 })
        end
    | Ok (Launch_incomplete
            ({ process; reason = Exec_failure_unreaped exec_error } as
              incomplete)) ->
        begin match process.state with
        | Queue_lost (_, wait_error) ->
            Ok
              (Run_terminal_failure
                 {
                   process;
                   reason =
                     Run_wait_queue_lost
                       { wait_error; exec_error = Some exec_error };
                 })
        | Active | Completed _ ->
            Ok
              (Run_incomplete
                 {
                   process;
                   reason = Run_launch_incomplete incomplete.reason;
                 })
        end
    | Ok (Launch_incomplete { process; reason }) ->
        Ok
          (Run_incomplete
             { process; reason = Run_launch_incomplete reason })

  let id process = process.process_id
  let pid process = process.pid
end
