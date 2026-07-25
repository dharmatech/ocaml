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

let fail message =
  prerr_endline ("process_state_test: " ^ message);
  exit 1

let check condition message =
  if not condition then fail message

let native_failure native_kind native_message =
  Plan9_process.{ native_kind; native_message }

module Make_backend (Configuration : sig
  val capacity : int
end) = struct
  let foreign_capacity = Configuration.capacity
  let spawn_flags = 8212

  type handshake =
    | Executed
    | Exec_failed of string
    | Handshake_interrupted
    | Handshake_protocol_error

  type acknowledgment_fault =
    | Acknowledge_normally
    | Raise_before_release
    | Raise_after_release

  exception Acknowledgment_fault of string

  let next_process_id = ref 1L
  let next_pid = ref 100
  let next_sequence = ref 1L
  let handshake = ref Executed
  let spawn_failure = ref None
  let pending_records = ref []
  let wait_events = ref []
  let retained_wait = ref None
  let await_calls = ref 0
  let acknowledged_waits = ref 0
  let pending_acknowledgment_fault = ref Acknowledge_normally
  let wait_acknowledgment_fault = ref Acknowledge_normally
  let pending_acknowledgment_attempts = ref []
  let wait_acknowledgment_attempts = ref []
  let last_spawn = ref None

  let fresh_sequence () =
    let sequence = !next_sequence in
    next_sequence := Int64.succ sequence;
    sequence

  let enqueue event =
    wait_events := !wait_events @ [event]

  let completion ?(user = 1L) ?(system = 2L) ?(elapsed = 3L)
      ?(message = "") pid =
    enqueue
      Plan9_process.
        {
          native_sequence = fresh_sequence ();
          native_event_kind = 0;
          native_wait_pid = pid;
          native_user_time_ms = user;
          native_system_time_ms = system;
          native_elapsed_time_ms = elapsed;
          native_event_detail = native_failure 1 message;
        }

  let await_error kind message =
    enqueue
      Plan9_process.
        {
          native_sequence = fresh_sequence ();
          native_event_kind = 1;
          native_wait_pid = 0;
          native_user_time_ms = 0L;
          native_system_time_ms = 0L;
          native_elapsed_time_ms = 0L;
          native_event_detail = native_failure kind message;
        }

  let publish_pending ?(handshake = 1) ?queue_loss process_id pid =
    let detail =
      match handshake with
      | 1 -> native_failure 1 ""
      | 2 -> native_failure 1 "exec failed"
      | 3 -> native_failure 2 "interrupted"
      | _ -> native_failure 4 "bad handshake"
    in
    let pending =
      Plan9_process.
        {
          native_process_id = process_id;
          native_pid = pid;
          native_handshake = handshake;
          native_detail = detail;
          native_queue_loss = queue_loss;
        }
    in
    pending_records := pending :: !pending_records;
    pending

  let spawn program argv stdout_kind stdout_path flags =
    last_spawn := Some (program, Array.copy argv, stdout_kind, stdout_path,
                        flags);
    match !spawn_failure with
    | Some failure -> Result.Error failure
    | None ->
        let process_id = !next_process_id in
        let pid = !next_pid in
        next_process_id := Int64.succ process_id;
        incr next_pid;
        let native_handshake, native_detail =
          match !handshake with
          | Executed -> 1, native_failure 1 ""
          | Exec_failed message -> 2, native_failure 1 message
          | Handshake_interrupted -> 3, native_failure 2 "interrupted"
          | Handshake_protocol_error ->
              4, native_failure 4 "invalid P9E1 frame"
        in
        let pending =
          Plan9_process.
            {
              native_process_id = process_id;
              native_pid = pid;
              native_handshake;
              native_detail;
              native_queue_loss = None;
            }
        in
        pending_records := pending :: !pending_records;
        Ok pending

  let pending () = Array.of_list !pending_records

  let acknowledge_pending process_id =
    pending_acknowledgment_attempts :=
      process_id :: !pending_acknowledgment_attempts;
    begin match !pending_acknowledgment_fault with
    | Raise_before_release ->
        pending_acknowledgment_fault := Acknowledge_normally;
        raise
          (Acknowledgment_fault
             "pending acknowledgment raised before release")
    | Acknowledge_normally | Raise_after_release -> ()
    end;
    let kept =
      List.filter
        (fun pending ->
          not (Int64.equal pending.Plan9_process.native_process_id
                 process_id))
        !pending_records
    in
    let removed = List.length kept <> List.length !pending_records in
    pending_records := kept;
    begin match !pending_acknowledgment_fault with
    | Raise_after_release when removed ->
        pending_acknowledgment_fault := Acknowledge_normally;
        raise
          (Acknowledgment_fault
             "pending acknowledgment raised after release")
    | Raise_after_release ->
        pending_acknowledgment_fault := Acknowledge_normally
    | Acknowledge_normally | Raise_before_release -> ()
    end;
    removed

  let await () =
    incr await_calls;
    match !retained_wait with
    | Some event -> event
    | None ->
        let event =
          match !wait_events with
          | event :: rest ->
              wait_events := rest;
              event
          | [] ->
              Plan9_process.
                {
                  native_sequence = fresh_sequence ();
                  native_event_kind = 1;
                  native_wait_pid = 0;
                  native_user_time_ms = 0L;
                  native_system_time_ms = 0L;
                  native_elapsed_time_ms = 0L;
                  native_event_detail =
                    native_failure 3 "no living children";
                }
        in
        retained_wait := Some event;
        event

  let acknowledge_wait sequence =
    wait_acknowledgment_attempts :=
      sequence :: !wait_acknowledgment_attempts;
    begin match !wait_acknowledgment_fault with
    | Raise_before_release ->
        wait_acknowledgment_fault := Acknowledge_normally;
        raise
          (Acknowledgment_fault
             "wait acknowledgment raised before release")
    | Acknowledge_normally | Raise_after_release -> ()
    end;
    match !retained_wait with
    | Some event
      when Int64.equal event.Plan9_process.native_sequence sequence ->
        retained_wait := None;
        incr acknowledged_waits;
        begin match !wait_acknowledgment_fault with
        | Raise_after_release ->
            wait_acknowledgment_fault := Acknowledge_normally;
            raise
              (Acknowledgment_fault
                 "wait acknowledgment raised after release")
        | Acknowledge_normally | Raise_before_release -> true
        end
    | Some _ | None -> false
end

module Launch_backend = Make_backend (struct let capacity = 2 end)
module Launch_process = Plan9_process.Make (Launch_backend)

let test_launch_vector () =
  let program = "/bin/echo" in
  let args = [| "one"; ""; "\255" |] in
  let process =
    match Launch_process.spawn ~program ~args () with
    | Ok (Launch_process.Launch_started process) -> process
    | _ -> fail "ordinary spawn did not return Launch_started"
  in
  check (Launch_process.id process = 1L)
    "first logical identity was not stable";
  check (Launch_process.pid process = 100)
    "first fake PID was not retained";
  begin match !(Launch_backend.last_spawn) with
  | Some (seen_program, seen_argv, stdout_kind, stdout_path, flags) ->
      check (seen_program = program) "spawn changed the program path";
      check (seen_argv = [| program; "one"; ""; "\255" |])
        "high-level spawn did not synthesize literal argv0";
      check (stdout_kind = 0 && stdout_path = "")
        "default stdout policy was not inherited";
      check (flags = 8212) "spawn used the wrong fixed rfork policy"
  | None -> fail "fake backend did not observe spawn"
  end;
  check (!(Launch_backend.await_calls) = 0)
    "ordinary spawn invoked native await without a synchronous coordinator"

module Order_backend = Make_backend (struct let capacity = 2 end)
module Order_process = Plan9_process.Make (Order_backend)

module Handshake_backend = Make_backend (struct let capacity = 2 end)
module Handshake_process = Plan9_process.Make (Handshake_backend)

let test_launch_incomplete_preserves_handle () =
  Handshake_backend.handshake := Handshake_backend.Handshake_interrupted;
  begin match
    Handshake_process.spawn ~program:"/bin/interrupted" ~args:[||] ()
  with
  | Ok (Handshake_process.Launch_incomplete
          { process;
            reason = Handshake_process.Handshake_interrupted error }) ->
      check (Handshake_process.id process = 1L)
        "handshake interruption lost the logical handle";
      check (error.message = "interrupted")
        "handshake interruption changed the native error"
  | _ -> fail "handshake interruption was not handle-preserving"
  end

let test_out_of_order_routing () =
  let first =
    match Order_process.spawn ~program:"/bin/one" ~args:[||] () with
    | Ok (Order_process.Launch_started process) -> process
    | _ -> fail "first order-test launch failed"
  in
  let second =
    match Order_process.spawn ~program:"/bin/two" ~args:[||] () with
    | Ok (Order_process.Launch_started process) -> process
    | _ -> fail "second order-test launch failed"
  in
  Order_backend.completion (Order_process.pid second);
  Order_backend.completion (Order_process.pid first);
  begin match Order_process.wait first with
  | Order_process.Wait_finished message ->
      check (message.pid = Order_process.pid first)
        "particular wait returned the wrong managed completion"
  | _ -> fail "particular wait did not finish after out-of-order completions"
  end;
  let calls_after_first = !(Order_backend.await_calls) in
  begin match Order_process.wait second with
  | Order_process.Wait_finished message ->
      check (message.pid = Order_process.pid second)
        "memoized completion was routed to the wrong handle"
  | _ -> fail "memoized out-of-order completion was not returned"
  end;
  check (!(Order_backend.await_calls) = calls_after_first)
    "repeated managed wait invoked native await after memoization"

module Pressure_backend = Make_backend (struct let capacity = 2 end)
module Pressure_process = Plan9_process.Make (Pressure_backend)

let test_foreign_backpressure () =
  let target =
    match Pressure_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Pressure_process.Launch_started process) -> process
    | _ -> fail "backpressure target launch failed"
  in
  Pressure_backend.completion 900;
  Pressure_backend.completion 901;
  begin match Pressure_process.wait target with
  | Pressure_process.Wait_unresolved
      { process;
        reason = Pressure_process.Foreign_backpressure { queued; capacity } } ->
      check (Pressure_process.id process = Pressure_process.id target)
        "backpressure did not retain the target handle";
      check (queued = 2 && capacity = 2)
        "foreign backpressure reported the wrong occupancy"
  | _ -> fail "full foreign FIFO was not retryable backpressure"
  end;
  let foreign = Pressure_process.take_foreign_completions () in
  check (List.map (fun message -> message.Plan9_process.pid) foreign
         = [900; 901])
    "foreign completions were not drained in FIFO order";
  Pressure_backend.completion (Pressure_process.pid target);
  begin match Pressure_process.wait target with
  | Pressure_process.Wait_finished _ -> ()
  | _ -> fail "managed wait did not resume after draining backpressure"
  end

module Any_backend = Make_backend (struct let capacity = 1 end)
module Any_process = Plan9_process.Make (Any_backend)

let test_wait_any_prefers_queued_foreign () =
  let target =
    match Any_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Any_process.Launch_started process) -> process
    | _ -> fail "wait_any target launch failed"
  in
  Any_backend.completion 902;
  begin match Any_process.wait target with
  | Any_process.Wait_unresolved
      { reason = Any_process.Foreign_backpressure _; _ } -> ()
  | _ -> fail "one-slot FIFO did not apply backpressure"
  end;
  let calls = !(Any_backend.await_calls) in
  begin match Any_process.wait_any () with
  | Ok (Any_process.Wait_any_finished
          (Any_process.Foreign message)) ->
      check (message.pid = 902) "wait_any returned the wrong foreign record"
  | _ -> fail "wait_any did not return the queued foreign record"
  end;
  check (!(Any_backend.await_calls) = calls)
    "wait_any invoked native await before returning queued foreign data";
  Any_backend.completion (Any_process.pid target);
  begin match Any_process.wait target with
  | Any_process.Wait_finished _ -> ()
  | _ -> fail "wait_any test target was not subsequently resolvable"
  end

module Interrupt_backend = Make_backend (struct let capacity = 2 end)
module Interrupt_process = Plan9_process.Make (Interrupt_backend)

let test_interruption_is_nonconsuming () =
  let target =
    match Interrupt_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Interrupt_process.Launch_started process) -> process
    | _ -> fail "interruption target launch failed"
  in
  Interrupt_backend.await_error 2 "interrupted";
  begin match Interrupt_process.wait target with
  | Interrupt_process.Wait_unresolved
      { process; reason = Interrupt_process.Await_interrupted error } ->
      check (Interrupt_process.id process = Interrupt_process.id target)
        "interruption lost the managed handle";
      check (error.message = "interrupted")
        "interruption did not preserve the exact native error"
  | _ -> fail "wait interruption was not returned distinctly"
  end;
  Interrupt_backend.completion (Interrupt_process.pid target);
  begin match Interrupt_process.wait target with
  | Interrupt_process.Wait_finished _ -> ()
  | _ -> fail "interrupted wait consumed the later completion"
  end

module Loss_backend = Make_backend (struct let capacity = 2 end)
module Loss_process = Plan9_process.Make (Loss_backend)

let test_exact_no_children_terminalizes_all () =
  let spawn program =
    match Loss_process.spawn ~program ~args:[||] () with
    | Ok (Loss_process.Launch_started process) -> process
    | _ -> fail "queue-loss launch failed"
  in
  let first = spawn "/bin/one" in
  let second = spawn "/bin/two" in
  Loss_backend.await_error 3 "no living children";
  let expect_lost process =
    match Loss_process.wait process with
    | Loss_process.Wait_terminal_failure
        { process = retained;
          reason = Loss_process.Wait_queue_lost error } ->
        check (Loss_process.id retained = Loss_process.id process)
          "queue loss did not preserve the queried handle";
        check (error.message = "no living children")
          "queue loss did not preserve the exact native error"
    | _ -> fail "exact No_children did not terminalize a managed owner"
  in
  expect_lost first;
  expect_lost second

module Adoption_backend = Make_backend (struct let capacity = 2 end)
module Adoption_process = Plan9_process.Make (Adoption_backend)

let test_pending_adoption_is_identity_preserving () =
  ignore (Adoption_backend.publish_pending 42L 142);
  let first =
    match Adoption_process.unresolved () with
    | [process] -> process
    | _ -> fail "pending native owner was not adopted exactly once"
  in
  let second =
    match Adoption_process.unresolved () with
    | [process] -> process
    | _ -> fail "adopted native owner disappeared or duplicated"
  in
  check (Adoption_process.id first = 42L
         && Adoption_process.id second = 42L
         && Adoption_process.pid first = 142)
    "pending adoption changed native ownership identity";
  Adoption_backend.await_error 3 "no living children";
  begin match Adoption_process.wait first with
  | Adoption_process.Wait_terminal_failure _ -> ()
  | _ -> fail "adopted owner did not observe exact queue loss"
  end;
  ignore
    (Adoption_backend.publish_pending
       ~queue_loss:(native_failure 3 "no living children") 43L 143);
  let terminal =
    match Adoption_process.unresolved () with
    | [process] -> process
    | _ -> fail "native-pending queue loss was not adopted"
  in
  begin match Adoption_process.wait terminal with
  | Adoption_process.Wait_terminal_failure
      { process; reason = Adoption_process.Wait_queue_lost error } ->
      check (Adoption_process.id process = 43L)
        "native-pending queue loss changed the process identity";
      check (error.message = "no living children")
        "native-pending queue loss changed the exact native error"
  | _ -> fail "native-pending owner was not adopted as terminal"
  end

module Collision_backend = Make_backend (struct let capacity = 2 end)
module Collision_process = Plan9_process.Make (Collision_backend)

let test_pid_collision_fails_closed () =
  ignore (Collision_backend.publish_pending 51L 151);
  ignore (Collision_backend.publish_pending 52L 151);
  let owners = Collision_process.unresolved () in
  check (List.length owners = 2)
    "PID collision discarded an owned logical handle";
  let target = List.hd owners in
  begin match Collision_process.wait target with
  | Collision_process.Wait_unresolved
      { process;
        reason = Collision_process.Coordinator_invariant_failure _ } ->
      check (Collision_process.id process = Collision_process.id target)
        "PID-collision invariant failure lost the queried handle"
  | _ -> fail "active PID collision did not fail closed"
  end;
  check (!(Collision_backend.await_calls) = 0)
    "failed-closed PID collision invoked native await"

module Malformed_backend = Make_backend (struct let capacity = 2 end)
module Malformed_process = Plan9_process.Make (Malformed_backend)

let test_malformed_record_fails_closed () =
  let target =
    match Malformed_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Malformed_process.Launch_started process) -> process
    | _ -> fail "malformed-record target launch failed"
  in
  Malformed_backend.completion ~user:(-1L)
    (Malformed_process.pid target);
  begin match Malformed_process.wait target with
  | Malformed_process.Wait_unresolved
      { process; reason = Malformed_process.Malformed_native_record _ } ->
      check (Malformed_process.id process = Malformed_process.id target)
        "malformed record lost the target handle"
  | _ -> fail "malformed native record did not fail closed"
  end;
  begin match Malformed_process.wait target with
  | Malformed_process.Wait_unresolved
      { reason = Malformed_process.Malformed_native_record _; _ } -> ()
  | _ -> fail "failed-closed malformed state was not persistent"
  end

module Ack_after_backend = Make_backend (struct let capacity = 2 end)
module Ack_after_process = Plan9_process.Make (Ack_after_backend)

let test_wait_acknowledgment_after_release_is_recoverable () =
  let spawn program =
    match Ack_after_process.spawn ~program ~args:[||] () with
    | Ok (Ack_after_process.Launch_started process) -> process
    | _ -> fail "acknowledgment-race launch failed"
  in
  let first = spawn "/bin/one" in
  let second = spawn "/bin/two" in
  Ack_after_backend.completion (Ack_after_process.pid first);
  Ack_after_backend.completion (Ack_after_process.pid second);
  Ack_after_backend.wait_acknowledgment_fault :=
    Ack_after_backend.Raise_after_release;
  let raised =
    try
      ignore (Ack_after_process.wait first);
      false
    with Ack_after_backend.Acknowledgment_fault _ -> true
  in
  check raised
    "post-release wait-acknowledgment fault did not reach the caller";
  check (!(Ack_after_backend.acknowledged_waits) = 1)
    "post-release fault did not release exactly the routed event";
  check (List.length !(Ack_after_backend.wait_events) = 1)
    "post-release fault consumed the following completion";
  begin match Ack_after_process.wait first with
  | Ack_after_process.Wait_finished message ->
      check (message.pid = Ack_after_process.pid first)
        "acknowledgment recovery changed the managed completion"
  | _ -> fail "managed completion was not memoized across acknowledgment fault"
  end;
  check (!(Ack_after_backend.acknowledged_waits) = 1)
    "acknowledgment recovery released the following completion prematurely";
  check (List.length !(Ack_after_backend.wait_events) = 1)
    "managed retry consumed the following completion prematurely";
  begin match List.rev !(Ack_after_backend.wait_acknowledgment_attempts) with
  | [first_attempt; retry_attempt] ->
      check (Int64.equal first_attempt retry_attempt)
        "acknowledgment recovery retried a different native sequence"
  | _ -> fail "managed recovery made an unexpected number of acknowledgments"
  end;
  begin match Ack_after_process.wait second with
  | Ack_after_process.Wait_finished message ->
      check (message.pid = Ack_after_process.pid second)
        "following completion was routed to the wrong handle"
  | _ -> fail "following completion was lost after acknowledgment recovery"
  end;
  check (!(Ack_after_backend.acknowledged_waits) = 2)
    "following completion was not acknowledged exactly once"

module Ack_before_backend = Make_backend (struct let capacity = 2 end)
module Ack_before_process = Plan9_process.Make (Ack_before_backend)

let test_wait_acknowledgment_before_release_is_idempotent () =
  let target =
    match Ack_before_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Ack_before_process.Launch_started process) -> process
    | _ -> fail "pre-release acknowledgment-race launch failed"
  in
  Ack_before_backend.completion (Ack_before_process.pid target);
  Ack_before_backend.wait_acknowledgment_fault :=
    Ack_before_backend.Raise_before_release;
  let raised =
    try
      ignore (Ack_before_process.wait target);
      false
    with Ack_before_backend.Acknowledgment_fault _ -> true
  in
  check raised
    "pre-release wait-acknowledgment fault did not reach the caller";
  check (!(Ack_before_backend.acknowledged_waits) = 0)
    "pre-release fault released the retained native event";
  check (!(Ack_before_backend.retained_wait) <> None)
    "pre-release fault discarded the retained native event";
  begin match Ack_before_process.wait target with
  | Ack_before_process.Wait_finished _ -> ()
  | _ -> fail "pre-release acknowledgment recovery was not idempotent"
  end;
  check (!(Ack_before_backend.acknowledged_waits) = 1)
    "pre-release recovery did not acknowledge exactly once"

module Ack_foreign_backend = Make_backend (struct let capacity = 2 end)
module Ack_foreign_process = Plan9_process.Make (Ack_foreign_backend)

let test_foreign_fifo_survives_post_release_fault () =
  let target =
    match Ack_foreign_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Ack_foreign_process.Launch_started process) -> process
    | _ -> fail "foreign acknowledgment-race launch failed"
  in
  Ack_foreign_backend.completion 990;
  Ack_foreign_backend.completion (Ack_foreign_process.pid target);
  Ack_foreign_backend.wait_acknowledgment_fault :=
    Ack_foreign_backend.Raise_after_release;
  let raised =
    try
      ignore (Ack_foreign_process.wait target);
      false
    with Ack_foreign_backend.Acknowledgment_fault _ -> true
  in
  check raised
    "foreign post-release acknowledgment fault did not reach the caller";
  check (!(Ack_foreign_backend.acknowledged_waits) = 1)
    "foreign post-release fault released the wrong number of events";
  check (List.length !(Ack_foreign_backend.wait_events) = 1)
    "foreign post-release fault consumed the managed completion";
  begin match Ack_foreign_process.take_foreign_completions () with
  | [message] ->
      check (message.Plan9_process.pid = 990)
        "foreign FIFO changed the routed completion"
  | _ -> fail "foreign FIFO duplicated or lost the routed completion"
  end;
  check (!(Ack_foreign_backend.acknowledged_waits) = 1)
    "foreign FIFO recovery acknowledged the managed completion prematurely";
  begin match
    List.rev !(Ack_foreign_backend.wait_acknowledgment_attempts)
  with
  | [first_attempt; retry_attempt] ->
      check (Int64.equal first_attempt retry_attempt)
        "foreign recovery retried a different native sequence"
  | _ -> fail "foreign recovery made an unexpected number of acknowledgments"
  end;
  begin match Ack_foreign_process.wait target with
  | Ack_foreign_process.Wait_finished _ -> ()
  | _ -> fail "managed completion was lost after foreign FIFO recovery"
  end;
  check (!(Ack_foreign_backend.acknowledged_waits) = 2)
    "managed completion was not acknowledged after foreign FIFO recovery"

module Pending_after_backend = Make_backend (struct let capacity = 2 end)
module Pending_after_process = Plan9_process.Make (Pending_after_backend)

let test_pending_acknowledgment_after_release_is_recoverable () =
  ignore
    (Pending_after_backend.publish_pending
       ~queue_loss:(native_failure 3 "no living children") 71L 171);
  Pending_after_backend.pending_acknowledgment_fault :=
    Pending_after_backend.Raise_after_release;
  let raised =
    try
      ignore (Pending_after_process.unresolved ());
      false
    with Pending_after_backend.Acknowledgment_fault _ -> true
  in
  check raised
    "post-release pending acknowledgment fault did not reach the caller";
  check (!(Pending_after_backend.pending_records) = [])
    "post-release pending fault left native ownership falsely retained";
  let process =
    match Pending_after_process.unresolved () with
    | [process] -> process
    | _ -> fail "post-release pending recovery lost or duplicated the handle"
  in
  check (Pending_after_process.id process = 71L)
    "post-release pending recovery changed the logical identity";
  check
    (List.rev !(Pending_after_backend.pending_acknowledgment_attempts)
     = [71L; 71L])
    "post-release pending recovery acknowledged a different identity";
  begin match Pending_after_process.wait process with
  | Pending_after_process.Wait_terminal_failure _ -> ()
  | _ -> fail "post-release pending recovery changed terminal queue loss"
  end

module Pending_before_backend = Make_backend (struct let capacity = 2 end)
module Pending_before_process = Plan9_process.Make (Pending_before_backend)

let test_pending_acknowledgment_before_release_preserves_native_owner () =
  ignore
    (Pending_before_backend.publish_pending
       ~queue_loss:(native_failure 3 "no living children") 72L 172);
  Pending_before_backend.pending_acknowledgment_fault :=
    Pending_before_backend.Raise_before_release;
  let raised =
    try
      ignore (Pending_before_process.unresolved ());
      false
    with Pending_before_backend.Acknowledgment_fault _ -> true
  in
  check raised
    "pre-release pending acknowledgment fault did not reach the caller";
  check (List.length !(Pending_before_backend.pending_records) = 1)
    "pre-release pending fault released native ownership";
  let process =
    match Pending_before_process.unresolved () with
    | [process] -> process
    | _ -> fail "pre-release pending recovery lost or duplicated the handle"
  in
  check (Pending_before_process.id process = 72L)
    "pre-release pending recovery changed the logical identity";
  check (!(Pending_before_backend.pending_records) = [])
    "pre-release pending recovery did not acknowledge native ownership"

module Run_backend = Make_backend (struct let capacity = 2 end)
module Run_process = Plan9_process.Make (Run_backend)

module Inexact_loss_backend = Make_backend (struct let capacity = 2 end)
module Inexact_loss_process = Plan9_process.Make (Inexact_loss_backend)

let test_inexact_no_children_does_not_terminalize () =
  let target =
    match Inexact_loss_process.spawn ~program:"/bin/target" ~args:[||] () with
    | Ok (Inexact_loss_process.Launch_started process) -> process
    | _ -> fail "inexact-loss target launch failed"
  in
  Inexact_loss_backend.await_error 3 "no child";
  begin match Inexact_loss_process.wait target with
  | Inexact_loss_process.Wait_unresolved
      { process;
        reason = Inexact_loss_process.Malformed_native_record _ } ->
      check (Inexact_loss_process.id process
             = Inexact_loss_process.id target)
        "inexact No_children marker lost the target handle"
  | _ -> fail "inexact No_children marker terminalized ownership"
  end

let test_run_uses_same_coordinator () =
  Run_backend.completion 100;
  begin match Run_process.run ~program:"/bin/ok" ~args:[||] () with
  | Ok (Run_process.Run_finished message) ->
      check (message.pid = 100) "run returned the wrong completion"
  | _ -> fail "run did not drive its managed child to completion"
  end;
  Run_backend.handshake := Run_backend.Exec_failed "does not exist";
  Run_backend.completion ~message:"exec failure child" 101;
  begin match Run_process.run ~program:"/bin/missing" ~args:[||] () with
  | Result.Error error ->
      check (error.message = "does not exist")
        "reaped exec failure did not preserve the native exec error"
  | _ -> fail "outer run error did not mean the failed child was reaped"
  end

module Outer_error_backend = Make_backend (struct let capacity = 2 end)
module Outer_error_process = Plan9_process.Make (Outer_error_backend)

let test_outer_error_has_no_child () =
  Outer_error_backend.spawn_failure :=
    Some (native_failure 0 "rejected before rfork");
  begin match
    Outer_error_process.spawn ~program:"/bin/rejected" ~args:[||] ()
  with
  | Result.Error error ->
      check (error.message = "rejected before rfork")
        "outer spawn error changed the pre-rfork native error";
      check (Outer_error_process.unresolved () = [])
        "outer spawn error left a managed owner"
  | Ok _ -> fail "pre-rfork failure did not return outer spawn Error"
  end

let () =
  test_launch_vector ();
  test_launch_incomplete_preserves_handle ();
  test_out_of_order_routing ();
  test_foreign_backpressure ();
  test_wait_any_prefers_queued_foreign ();
  test_interruption_is_nonconsuming ();
  test_exact_no_children_terminalizes_all ();
  test_pending_adoption_is_identity_preserving ();
  test_pid_collision_fails_closed ();
  test_malformed_record_fails_closed ();
  test_wait_acknowledgment_after_release_is_recoverable ();
  test_wait_acknowledgment_before_release_is_idempotent ();
  test_foreign_fifo_survives_post_release_fault ();
  test_pending_acknowledgment_after_release_is_recoverable ();
  test_pending_acknowledgment_before_release_preserves_native_owner ();
  test_inexact_no_children_does_not_terminalize ();
  test_run_uses_same_coordinator ();
  test_outer_error_has_no_child ();
  print_endline "process_state_test: passed"
