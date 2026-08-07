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
  prerr_endline ("fd_lifecycle_test: " ^ message);
  exit 1

let check label condition =
  if not condition then fail label

let force_gc () =
  Gc.minor ();
  Gc.full_major ();
  Gc.compact ()

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      fail
        (label ^ " failed: " ^ error.Plan9_types.operation ^ ": "
         ^ error.Plan9_types.message)

let expect_error label operation kind message = function
  | Ok _ -> fail (label ^ " unexpectedly succeeded")
  | Error error ->
      if error.Plan9_types.operation <> operation then
        fail
          (label ^ " used operation " ^ error.Plan9_types.operation
           ^ " instead of " ^ operation);
      if error.Plan9_types.kind <> kind then
        fail (label ^ " returned the wrong error kind");
      if error.Plan9_types.message <> message then
        fail
          (label ^ " returned message "
           ^ String.escaped error.Plan9_types.message)

let close_operation = "Plan9.Fd.close"
let read_operation = "Plan9.Fd.read"
let write_operation = "Plan9.Fd.write"
let prepare_operation = "Plan9.Fd.Private.prepare_attach"
let transferred_message = "descriptor ownership has been transferred"
let close_in_progress_message = "descriptor close is already in progress"
let io_in_progress_message = "descriptor I/O is already in progress"
let closed_message = "descriptor is closed"
let not_detached_message = "descriptor is not open and detached"
let unauthorized_message = "attachment token is not the committed owner"

let expect_transferred label result =
  expect_error label close_operation Plan9_types.Invalid_argument
    transferred_message result

let expect_close_in_progress label result =
  expect_error label close_operation Plan9_types.Invalid_argument
    close_in_progress_message result

let expect_not_detached label result =
  expect_error label prepare_operation Plan9_types.Invalid_argument
    not_detached_message result

let expect_unauthorized label result =
  expect_error label close_operation Plan9_types.Invalid_argument
    unauthorized_message result

let expect_io_in_progress label operation result =
  expect_error label operation Plan9_types.Invalid_argument
    io_in_progress_message result

let expect_closed label operation result =
  expect_error label operation Plan9_types.Invalid_argument closed_message
    result

let expect_transferred_operation label operation result =
  expect_error label operation Plan9_types.Invalid_argument
    transferred_message result

let expect_unauthorized_operation label operation result =
  expect_error label operation Plan9_types.Invalid_argument
    unauthorized_message result

module Fake = struct
  type capability = { id : int }

  type call =
    | Pipe
    | Close of int
    | Read of int * int
    | Write of int * bytes * int * int

  type pipe_action =
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  type close_action =
    capability -> (unit, Plan9_types.native_failure) result

  type read_action =
    capability -> int ->
    ((bytes * int), Plan9_types.native_failure) result

  type write_action =
    capability -> bytes -> int -> int ->
    (int, Plan9_types.native_failure) result

  let calls_reversed = ref []
  let next_pipe_action : pipe_action option ref = ref None
  let next_close_action : close_action option ref = ref None
  let next_read_action : read_action option ref = ref None
  let next_write_action : write_action option ref = ref None

  let reset () =
    calls_reversed := [];
    next_pipe_action := None;
    next_close_action := None;
    next_read_action := None;
    next_write_action := None

  let capability id = { id }
  let calls () = List.rev !calls_reversed

  let close_count () =
    List.fold_left
      (fun count -> function Close _ -> count + 1 | _ -> count)
      0 !calls_reversed

  let read_count () =
    List.fold_left
      (fun count -> function Read _ -> count + 1 | _ -> count)
      0 !calls_reversed

  let write_count () =
    List.fold_left
      (fun count -> function Write _ -> count + 1 | _ -> count)
      0 !calls_reversed

  let set_pipe_action action = next_pipe_action := Some action
  let set_close_action action = next_close_action := Some action
  let set_read_action action = next_read_action := Some action
  let set_write_action action = next_write_action := Some action

  let pipe () =
    calls_reversed := Pipe :: !calls_reversed;
    match !next_pipe_action with
    | None -> fail "fake pipe called without an injected result"
    | Some action ->
        next_pipe_action := None;
        action ()

  let close capability =
    calls_reversed := Close capability.id :: !calls_reversed;
    match !next_close_action with
    | None -> Ok ()
    | Some action ->
        next_close_action := None;
        action capability


  let read capability length =
    calls_reversed := Read (capability.id, length) :: !calls_reversed;
    match !next_read_action with
    | None -> fail "fake read called without an injected result"
    | Some action ->
        next_read_action := None;
        action capability length

  let write capability source position length =
    calls_reversed :=
      Write (capability.id, source, position, length) :: !calls_reversed;
    match !next_write_action with
    | None -> fail "fake write called without an injected result"
    | Some action ->
        next_write_action := None;
        action capability source position length
end

module Fd = Plan9_fd.Make (Fake)

let show_call = function
  | Fake.Pipe -> "pipe"
  | Fake.Close id -> "close(" ^ string_of_int id ^ ")"
  | Fake.Read (id, length) ->
      "read(" ^ string_of_int id ^ "," ^ string_of_int length ^ ")"
  | Fake.Write (id, _, position, length) ->
      "write(" ^ string_of_int id ^ "," ^ string_of_int position ^ ","
      ^ string_of_int length ^ ")"

let show_calls calls = String.concat "," (List.map show_call calls)

let expect_calls label expected =
  let actual = Fake.calls () in
  if actual <> expected then
    fail
      (label ^ " calls: expected [" ^ show_calls expected ^ "] but got ["
       ^ show_calls actual ^ "]")

let expect_no_close_call label before =
  let after = Fake.close_count () in
  if after <> before then
    fail
      (label ^ " changed close count from " ^ string_of_int before ^ " to "
       ^ string_of_int after)

let expect_no_io_call label before_read before_write =
  let after_read = Fake.read_count () in
  let after_write = Fake.write_count () in
  if after_read <> before_read || after_write <> before_write then
    fail
      (label ^ " changed I/O counts from ("
       ^ string_of_int before_read ^ "," ^ string_of_int before_write
       ^ ") to (" ^ string_of_int after_read ^ ","
       ^ string_of_int after_write ^ ")")

let fake_pipe left_id right_id =
  let left_capability = Fake.capability left_id in
  let right_capability = Fake.capability right_id in
  Fake.set_pipe_action
    (fun () -> Ok (left_capability, right_capability));
  expect_ok "fake pipe" (Fd.pipe ())

exception Injected of string ref

let expect_physical_exception label expected operation =
  try
    ignore (operation ());
    fail (label ^ " did not raise")
  with
  | actual when actual == expected -> ()
  | _ -> fail (label ^ " replaced the designated exception value")

let test_pipe_public_close_and_errors () =
  Fake.reset ();
  let left_capability = Fake.capability 10 in
  let right_capability = Fake.capability 11 in
  Fake.set_pipe_action
    (fun () ->
      force_gc ();
      Ok (left_capability, right_capability));
  let left, right = expect_ok "forced-GC fake pipe" (Fd.pipe ()) in
  check "pipe returned the same ownership cell twice" (left != right);
  let alias = left in
  check "copying a descriptor did not preserve cell identity" (alias == left);
  ignore (expect_ok "first public close" (Fd.close alias));
  ignore (expect_ok "idempotent public close" (Fd.close left));
  ignore (expect_ok "second endpoint close" (Fd.close right));
  expect_calls "forced-GC publication"
    [Fake.Pipe; Fake.Close 10; Fake.Close 11];

  Fake.reset ();
  let pipe_failure : Plan9_types.native_failure =
    {
      Plan9_types.native_kind = 2;
      native_message = "injected pipe interruption"
    }
  in
  Fake.set_pipe_action (fun () -> Error pipe_failure);
  expect_error "pipe failure" "Plan9.Fd.pipe" Plan9_types.Interrupted
    pipe_failure.native_message (Fd.pipe ());
  expect_calls "pipe failure" [Fake.Pipe];

  Fake.reset ();
  let pipe_exception = Injected (ref "pipe callback") in
  Fake.set_pipe_action (fun () -> raise pipe_exception);
  expect_physical_exception "pipe callback" pipe_exception Fd.pipe;
  expect_calls "raising pipe callback" [Fake.Pipe];

  Fake.reset ();
  let left, right = fake_pipe 20 21 in
  let close_failure : Plan9_types.native_failure =
    {
      Plan9_types.native_kind = 4;
      native_message = "injected terminal close failure"
    }
  in
  Fake.set_close_action (fun capability ->
    check "public close used the wrong capability" (capability.Fake.id = 20);
    Error close_failure);
  expect_error "public close failure" close_operation
    Plan9_types.Protocol_error close_failure.native_message (Fd.close left);
  ignore (expect_ok "terminal public close" (Fd.close left));
  expect_calls "terminal public close failure" [Fake.Pipe; Fake.Close 20];
  ignore (expect_ok "public close failure companion" (Fd.close right))

let test_prepare_close_and_public_attempts () =
  Fake.reset ();
  let left, right = fake_pipe 30 31 in
  let token =
    expect_ok "prepare before public close" (Fd.Private.prepare_attach left)
  in
  let before = Fake.close_count () in
  expect_unauthorized "uncommitted token close" (Fd.Private.close token);
  expect_no_close_call "uncommitted token rejection" before;
  ignore (expect_ok "public close after prepare" (Fd.close left));
  check "stale token committed after public close"
    (not (Fd.Private.commit_attach token));
  let before = Fake.close_count () in
  expect_unauthorized "stale token close after public close"
    (Fd.Private.close token);
  expect_not_detached "prepare after public close"
    (Fd.Private.prepare_attach left);
  expect_no_close_call "publicly closed rejection paths" before;
  ignore (expect_ok "prepare/close companion" (Fd.close right));

  Fake.reset ();
  let left, right = fake_pipe 40 41 in
  let token =
    expect_ok "prepare before active public close"
      (Fd.Private.prepare_attach left)
  in
  Fake.set_close_action (fun capability ->
    check "active public close used the wrong capability"
      (capability.Fake.id = 40);
    force_gc ();
    check "token committed during active public close"
      (not (Fd.Private.commit_attach token));
    let before = Fake.close_count () in
    expect_close_in_progress "reentrant public close" (Fd.close left);
    expect_not_detached "prepare during active public close"
      (Fd.Private.prepare_attach left);
    expect_unauthorized "token close during active public close"
      (Fd.Private.close token);
    expect_no_close_call "active public close rejection paths" before;
    Ok ());
  ignore (expect_ok "outer public close" (Fd.close left));
  ignore (expect_ok "terminal outer public close" (Fd.close left));
  expect_calls "active public close" [Fake.Pipe; Fake.Close 40];
  ignore (expect_ok "active public close companion" (Fd.close right));

  Fake.reset ();
  let left, right = fake_pipe 50 51 in
  let token =
    expect_ok "prepare before raising public close"
      (Fd.Private.prepare_attach left)
  in
  let close_exception = Injected (ref "public close callback") in
  Fake.set_close_action (fun capability ->
    check "raising public close used the wrong capability"
      (capability.Fake.id = 50);
    force_gc ();
    let before = Fake.close_count () in
    expect_close_in_progress "raising reentrant public close"
      (Fd.close left);
    expect_not_detached "prepare during raising public close"
      (Fd.Private.prepare_attach left);
    check "token committed during raising public close"
      (not (Fd.Private.commit_attach token));
    expect_unauthorized "token close during raising public close"
      (Fd.Private.close token);
    expect_no_close_call "raising public callback rejection paths" before;
    raise close_exception);
  expect_physical_exception "public close callback" close_exception
    (fun () -> Fd.close left);
  let before = Fake.close_count () in
  expect_not_detached "prepare during inactive public close"
    (Fd.Private.prepare_attach left);
  check "token committed during inactive public close"
    (not (Fd.Private.commit_attach token));
  expect_unauthorized "token close during inactive public close"
    (Fd.Private.close token);
  expect_no_close_call "inactive public close rejection paths" before;
  force_gc ();
  ignore (expect_ok "public close retry" (Fd.close left));
  ignore (expect_ok "public close after retry" (Fd.close left));
  expect_calls "inactive public close retry"
    [Fake.Pipe; Fake.Close 50; Fake.Close 50];
  ignore (expect_ok "public close retry companion" (Fd.close right))

let test_attachment_owner_close_and_errors () =
  Fake.reset ();
  let left, right = fake_pipe 60 61 in
  let winner = expect_ok "prepare winner" (Fd.Private.prepare_attach left) in
  let loser = expect_ok "prepare loser" (Fd.Private.prepare_attach left) in
  force_gc ();
  check "first attachment did not commit" (Fd.Private.commit_attach winner);
  check "winning token committed twice"
    (not (Fd.Private.commit_attach winner));
  check "losing token committed" (not (Fd.Private.commit_attach loser));
  let before = Fake.close_count () in
  expect_transferred "public close after attachment" (Fd.close left);
  expect_not_detached "prepare after attachment"
    (Fd.Private.prepare_attach left);
  expect_unauthorized "losing token close while attached"
    (Fd.Private.close loser);
  expect_no_close_call "attached rejection paths" before;
  force_gc ();
  ignore (expect_ok "owner close" (Fd.Private.close winner));
  ignore (expect_ok "idempotent owner close" (Fd.Private.close winner));
  let before = Fake.close_count () in
  expect_transferred "public close after owner close" (Fd.close left);
  expect_not_detached "prepare after owner close"
    (Fd.Private.prepare_attach left);
  expect_unauthorized "losing token close after owner close"
    (Fd.Private.close loser);
  check "winner committed from owner-closed state"
    (not (Fd.Private.commit_attach winner));
  check "loser committed from owner-closed state"
    (not (Fd.Private.commit_attach loser));
  expect_no_close_call "owner-closed rejection paths" before;
  expect_calls "owner lifecycle" [Fake.Pipe; Fake.Close 60];
  ignore (expect_ok "owner lifecycle companion" (Fd.close right));

  Fake.reset ();
  let left, right = fake_pipe 70 71 in
  let winner =
    expect_ok "prepare owner-error winner"
      (Fd.Private.prepare_attach left)
  in
  let loser =
    expect_ok "prepare owner-error loser" (Fd.Private.prepare_attach left)
  in
  check "owner-error attachment did not commit"
    (Fd.Private.commit_attach winner);
  let close_failure : Plan9_types.native_failure =
    {
      Plan9_types.native_kind = 2;
      native_message = "injected owner close interruption"
    }
  in
  Fake.set_close_action (fun capability ->
    check "owner-error close used the wrong capability"
      (capability.Fake.id = 70);
    Error close_failure);
  expect_error "owner close failure" close_operation Plan9_types.Interrupted
    close_failure.native_message (Fd.Private.close winner);
  ignore (expect_ok "terminal owner close failure"
    (Fd.Private.close winner));
  let before = Fake.close_count () in
  expect_transferred "public close after failed owner close" (Fd.close left);
  expect_not_detached "prepare after failed owner close"
    (Fd.Private.prepare_attach left);
  expect_unauthorized "loser after failed owner close"
    (Fd.Private.close loser);
  expect_no_close_call "failed owner-close terminal state" before;
  expect_calls "terminal owner close failure" [Fake.Pipe; Fake.Close 70];
  ignore (expect_ok "owner close failure companion" (Fd.close right))

let test_owner_close_attempts () =
  Fake.reset ();
  let left, right = fake_pipe 80 81 in
  let winner =
    expect_ok "prepare active owner winner" (Fd.Private.prepare_attach left)
  in
  let loser =
    expect_ok "prepare active owner loser" (Fd.Private.prepare_attach left)
  in
  check "active owner attachment did not commit"
    (Fd.Private.commit_attach winner);
  Fake.set_close_action (fun capability ->
    check "active owner close used the wrong capability"
      (capability.Fake.id = 80);
    force_gc ();
    let before = Fake.close_count () in
    expect_close_in_progress "reentrant owner close"
      (Fd.Private.close winner);
    expect_transferred "public close during active owner close"
      (Fd.close left);
    expect_not_detached "prepare during active owner close"
      (Fd.Private.prepare_attach left);
    expect_unauthorized "loser during active owner close"
      (Fd.Private.close loser);
    check "winner committed during active owner close"
      (not (Fd.Private.commit_attach winner));
    check "loser committed during active owner close"
      (not (Fd.Private.commit_attach loser));
    expect_no_close_call "active owner rejection paths" before;
    Ok ());
  ignore (expect_ok "outer owner close" (Fd.Private.close winner));
  ignore (expect_ok "terminal outer owner close"
    (Fd.Private.close winner));
  let before = Fake.close_count () in
  expect_transferred "public close after active owner close" (Fd.close left);
  expect_unauthorized "loser after active owner close"
    (Fd.Private.close loser);
  expect_no_close_call "active owner terminal rejections" before;
  expect_calls "active owner close" [Fake.Pipe; Fake.Close 80];
  ignore (expect_ok "active owner close companion" (Fd.close right));

  Fake.reset ();
  let left, right = fake_pipe 90 91 in
  let winner =
    expect_ok "prepare raising owner winner"
      (Fd.Private.prepare_attach left)
  in
  let loser =
    expect_ok "prepare raising owner loser" (Fd.Private.prepare_attach left)
  in
  check "raising owner attachment did not commit"
    (Fd.Private.commit_attach winner);
  let close_exception = Injected (ref "owner close callback") in
  Fake.set_close_action (fun capability ->
    check "raising owner close used the wrong capability"
      (capability.Fake.id = 90);
    force_gc ();
    let before = Fake.close_count () in
    expect_close_in_progress "raising reentrant owner close"
      (Fd.Private.close winner);
    expect_transferred "public close during raising owner close"
      (Fd.close left);
    expect_not_detached "prepare during raising owner close"
      (Fd.Private.prepare_attach left);
    expect_unauthorized "loser during raising owner close"
      (Fd.Private.close loser);
    check "winner committed during raising owner close"
      (not (Fd.Private.commit_attach winner));
    check "loser committed during raising owner close"
      (not (Fd.Private.commit_attach loser));
    expect_no_close_call "raising owner callback rejection paths" before;
    raise close_exception);
  expect_physical_exception "owner close callback" close_exception
    (fun () -> Fd.Private.close winner);
  let before = Fake.close_count () in
  expect_transferred "public close during inactive owner close"
    (Fd.close left);
  expect_not_detached "prepare during inactive owner close"
    (Fd.Private.prepare_attach left);
  expect_unauthorized "loser during inactive owner close"
    (Fd.Private.close loser);
  check "winner committed during inactive owner close"
    (not (Fd.Private.commit_attach winner));
  check "loser committed during inactive owner close"
    (not (Fd.Private.commit_attach loser));
  expect_no_close_call "inactive owner rejection paths" before;
  force_gc ();
  ignore (expect_ok "owner close retry" (Fd.Private.close winner));
  ignore (expect_ok "owner close after retry" (Fd.Private.close winner));
  let before = Fake.close_count () in
  expect_transferred "public close after owner retry" (Fd.close left);
  expect_unauthorized "loser after owner retry" (Fd.Private.close loser);
  expect_no_close_call "owner retry terminal rejections" before;
  expect_calls "inactive owner close retry"
    [Fake.Pipe; Fake.Close 90; Fake.Close 90];
  ignore (expect_ok "owner close retry companion" (Fd.close right))

let test_commit_attach_boolean_matrix () =
  Fake.reset ();
  let cell, companion = fake_pipe 100 101 in
  let winner = expect_ok "matrix prepare winner"
      (Fd.Private.prepare_attach cell) in
  let loser = expect_ok "matrix prepare loser"
      (Fd.Private.prepare_attach cell) in
  check "matrix first commit was false" (Fd.Private.commit_attach winner);
  check "matrix repeated winning commit was true"
    (not (Fd.Private.commit_attach winner));
  check "matrix competing commit was true"
    (not (Fd.Private.commit_attach loser));
  let owner_matrix_exception = Injected (ref "matrix owner inactive") in
  Fake.set_close_action (fun _ ->
    check "matrix commit during active owner close was true"
      (not (Fd.Private.commit_attach winner));
    check "matrix loser commit during active owner close was true"
      (not (Fd.Private.commit_attach loser));
    raise owner_matrix_exception);
  expect_physical_exception "matrix owner close" owner_matrix_exception
    (fun () -> Fd.Private.close winner);
  check "matrix commit during inactive owner close was true"
    (not (Fd.Private.commit_attach winner));
  check "matrix loser commit during inactive owner close was true"
    (not (Fd.Private.commit_attach loser));
  ignore (expect_ok "matrix owner retry" (Fd.Private.close winner));
  check "matrix commit from owner-closed state was true"
    (not (Fd.Private.commit_attach winner));
  check "matrix loser commit from owner-closed state was true"
    (not (Fd.Private.commit_attach loser));
  ignore (expect_ok "matrix owner companion" (Fd.close companion));
  expect_calls "owner commit matrix"
    [Fake.Pipe; Fake.Close 100; Fake.Close 100; Fake.Close 101];

  Fake.reset ();
  let cell, companion = fake_pipe 110 111 in
  let token = expect_ok "matrix public prepare"
      (Fd.Private.prepare_attach cell) in
  let public_matrix_exception = Injected (ref "matrix public inactive") in
  Fake.set_close_action (fun _ ->
    check "matrix commit during active public close was true"
      (not (Fd.Private.commit_attach token));
    raise public_matrix_exception);
  expect_physical_exception "matrix public close" public_matrix_exception
    (fun () -> Fd.close cell);
  check "matrix commit during inactive public close was true"
    (not (Fd.Private.commit_attach token));
  ignore (expect_ok "matrix public retry" (Fd.close cell));
  check "matrix commit from publicly closed state was true"
    (not (Fd.Private.commit_attach token));
  ignore (expect_ok "matrix public companion" (Fd.close companion));
  expect_calls "public commit matrix"
    [Fake.Pipe; Fake.Close 110; Fake.Close 110; Fake.Close 111]

let range_message buffer_length position length =
  "invalid byte range: buffer length " ^ string_of_int buffer_length
  ^ ", position " ^ string_of_int position
  ^ ", length " ^ string_of_int length

let expect_range_error label operation buffer_length position length result =
  expect_error label operation Plan9_types.Invalid_argument
    (range_message buffer_length position length) result

let read_protocol_message requested staging_length count =
  "invalid descriptor read result: requested " ^ string_of_int requested
  ^ " bytes, staging has " ^ string_of_int staging_length
  ^ " bytes, returned count " ^ string_of_int count

let write_protocol_message requested count =
  "invalid descriptor write result: requested " ^ string_of_int requested
  ^ " bytes, returned count " ^ string_of_int count

let short_write_message requested written =
  "descriptor write was short: requested " ^ string_of_int requested
  ^ " bytes, wrote " ^ string_of_int written ^ " bytes"

let expect_bytes label expected actual =
  if not (Bytes.equal expected actual) then
    fail
      (label ^ ": expected " ^ String.escaped (Bytes.to_string expected)
       ^ " but got " ^ String.escaped (Bytes.to_string actual))

let test_range_chunk_and_io_lifecycle () =
  Fake.reset ();
  check "zero primitive count" (Plan9_fd.primitive_count 0 = 0);
  check "capacity primitive count"
    (Plan9_fd.primitive_count 4096 = 4096);
  check "capacity-plus-one primitive count"
    (Plan9_fd.primitive_count 4097 = 4096);
  check "max-int primitive count"
    (Plan9_fd.primitive_count max_int = 4096);
  let cell, companion = fake_pipe 120 121 in
  let buffer = Bytes.make 4 '\165' in
  let invalid_ranges =
    [-1, 0; 0, -1; 5, 0; 4, 1; max_int, 1; 1, max_int]
  in
  List.iter
    (fun (position, length) ->
      expect_range_error "public read invalid range" read_operation 4
        position length (Fd.read cell buffer ~pos:position ~len:length);
      expect_range_error "public write invalid range" write_operation 4
        position length (Fd.write cell buffer ~pos:position ~len:length))
    invalid_ranges;
  expect_no_io_call "invalid public range matrix" 0 0;
  let read_zero = Fd.read cell buffer ~pos:4 ~len:0 in
  let write_zero = Fd.write cell buffer ~pos:4 ~len:0 in
  ignore (expect_ok "open zero read" read_zero);
  ignore (expect_ok "open zero write" write_zero);
  check "zero read and write did not share retained success"
    (read_zero == write_zero);
  expect_no_io_call "open zero I/O" 0 0;
  ignore (expect_ok "range close" (Fd.close cell));
  expect_range_error "closed range precedes lifecycle" read_operation 4
    max_int 1 (Fd.read cell buffer ~pos:max_int ~len:1);
  expect_range_error "closed write range precedes lifecycle" write_operation
    4 max_int 1 (Fd.write cell buffer ~pos:max_int ~len:1);
  expect_closed "closed zero read" read_operation
    (Fd.read cell buffer ~pos:4 ~len:0);
  expect_closed "closed positive write" write_operation
    (Fd.write cell buffer ~pos:0 ~len:1);

  let uncommitted =
    expect_ok "range uncommitted prepare"
      (Fd.Private.prepare_attach companion)
  in
  expect_range_error "uncommitted range precedes authorization"
    read_operation 4 max_int 1
    (Fd.Private.read uncommitted buffer ~pos:max_int ~len:1);
  expect_range_error "uncommitted write range precedes authorization"
    write_operation 4 max_int 1
    (Fd.Private.write uncommitted buffer ~pos:max_int ~len:1);
  expect_unauthorized_operation "uncommitted valid read" read_operation
    (Fd.Private.read uncommitted buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "uncommitted valid write" write_operation
    (Fd.Private.write uncommitted buffer ~pos:0 ~len:1);
  let loser =
    expect_ok "range losing prepare" (Fd.Private.prepare_attach companion)
  in
  let foreign =
    expect_ok "range foreign prepare" (Fd.Private.prepare_attach companion)
  in
  check "range owner commit failed"
    (Fd.Private.commit_attach uncommitted);
  expect_range_error "attached public read range precedes lifecycle"
    read_operation 4 max_int 1
    (Fd.read companion buffer ~pos:max_int ~len:1);
  expect_range_error "attached public range precedes lifecycle"
    write_operation 4 max_int 1
    (Fd.write companion buffer ~pos:max_int ~len:1);
  expect_range_error "losing token read range precedes authorization"
    read_operation 4 max_int 1
    (Fd.Private.read loser buffer ~pos:max_int ~len:1);
  expect_range_error "losing token range precedes authorization"
    write_operation 4 max_int 1
    (Fd.Private.write loser buffer ~pos:max_int ~len:1);
  expect_range_error "foreign token read range precedes authorization"
    read_operation 4 max_int 1
    (Fd.Private.read foreign buffer ~pos:max_int ~len:1);
  expect_range_error "foreign token write range precedes authorization"
    write_operation 4 max_int 1
    (Fd.Private.write foreign buffer ~pos:max_int ~len:1);
  expect_transferred_operation "attached public zero read" read_operation
    (Fd.read companion buffer ~pos:4 ~len:0);
  expect_transferred_operation "attached public valid write" write_operation
    (Fd.write companion buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "losing token valid read" read_operation
    (Fd.Private.read loser buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "losing token zero write" write_operation
    (Fd.Private.write loser buffer ~pos:4 ~len:0);
  expect_unauthorized_operation "foreign token valid read" read_operation
    (Fd.Private.read foreign buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "foreign token valid write" write_operation
    (Fd.Private.write foreign buffer ~pos:0 ~len:1);
  let owner_zero =
    Fd.Private.read uncommitted buffer ~pos:4 ~len:0
  in
  ignore (expect_ok "attached owner zero read" owner_zero);
  check "owner zero did not reuse retained success" (owner_zero == read_zero);
  let owner_write_zero =
    Fd.Private.write uncommitted buffer ~pos:4 ~len:0
  in
  ignore (expect_ok "attached owner zero write" owner_write_zero);
  check "owner write zero did not reuse retained success"
    (owner_write_zero == read_zero);
  ignore (expect_ok "range owner close" (Fd.Private.close uncommitted));
  expect_range_error "owner-closed range precedes lifecycle" read_operation 4
    max_int 1
    (Fd.Private.read uncommitted buffer ~pos:max_int ~len:1);
  expect_range_error "owner-closed write range precedes lifecycle"
    write_operation 4 max_int 1
    (Fd.Private.write uncommitted buffer ~pos:max_int ~len:1);
  expect_closed "owner-closed zero read" read_operation
    (Fd.Private.read uncommitted buffer ~pos:4 ~len:0);
  expect_closed "owner-closed valid write" write_operation
    (Fd.Private.write uncommitted buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "loser after owner close" write_operation
    (Fd.Private.write loser buffer ~pos:0 ~len:1);

  let stale_cell, stale_companion = fake_pipe 122 123 in
  let stale =
    expect_ok "stale token prepare" (Fd.Private.prepare_attach stale_cell)
  in
  ignore (expect_ok "stale public close" (Fd.close stale_cell));
  expect_range_error "stale range precedes authorization" read_operation 4
    max_int 1 (Fd.Private.read stale buffer ~pos:max_int ~len:1);
  expect_range_error "stale write range precedes authorization"
    write_operation 4 max_int 1
    (Fd.Private.write stale buffer ~pos:max_int ~len:1);
  expect_unauthorized_operation "stale valid read" read_operation
    (Fd.Private.read stale buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "stale valid write" write_operation
    (Fd.Private.write stale buffer ~pos:0 ~len:1);
  ignore (expect_ok "stale companion close" (Fd.close stale_companion));
  expect_no_io_call "range and lifecycle rejection matrix" 0 0

let test_read_write_results () =
  Fake.reset ();
  let reader, writer = fake_pipe 130 131 in
  let destination = Bytes.of_string "pppppppp" in
  let staging = Bytes.of_string "A\000Cpp" in
  Fake.set_read_action (fun capability requested ->
    check "short read capability" (capability.Fake.id = 130);
    check "short read request" (requested = 5);
    Ok (staging, 3));
  let count =
    expect_ok "short read"
      (Fd.read reader destination ~pos:2 ~len:5)
  in
  check "short read count" (count = 3);
  expect_bytes "short read destination"
    (Bytes.of_string "ppA\000Cppp") destination;

  let eof_destination = Bytes.of_string "unchanged" in
  Fake.set_read_action (fun _ requested ->
    force_gc ();
    Ok (Bytes.make requested '\000', 0));
  let eof = Fd.read reader eof_destination ~pos:1 ~len:4 in
  ignore (expect_ok "positive EOF" eof);
  check "positive EOF did not reuse retained zero"
    (eof == Fd.read reader eof_destination ~pos:0 ~len:0);
  expect_bytes "EOF destination unchanged"
    (Bytes.of_string "unchanged") eof_destination;

  let large_destination = Bytes.make 4097 '\165' in
  let exact_destination = Bytes.make 4096 '\165' in
  let exact_read_before = Fake.read_count () in
  Fake.set_read_action (fun capability requested ->
    check "exact-capacity read capability" (capability.Fake.id = 130);
    check "exact-capacity read request" (requested = 4096);
    Ok (Bytes.make requested '\000', 0));
  check "exact-capacity read EOF"
    (expect_ok "exact-capacity read"
       (Fd.read reader exact_destination ~pos:0 ~len:4096) = 0);
  check "exact-capacity read call count"
    (Fake.read_count () = exact_read_before + 1);
  Fake.set_read_action (fun capability requested ->
    check "large read capability" (capability.Fake.id = 130);
    check "large read was not capped" (requested = 4096);
    Ok (Bytes.make requested 'r', requested));
  check "large read count"
    (expect_ok "large read"
       (Fd.read reader large_destination ~pos:0 ~len:4097) = 4096);
  check "large read modified logical tail"
    (Bytes.get large_destination 4096 = '\165');

  let expect_malformed_read label staging count requested =
    let destination = Bytes.of_string "sentinel" in
    let before = Bytes.copy destination in
    Fake.set_read_action (fun _ actual_requested ->
      check (label ^ " request") (actual_requested = requested);
      Ok (staging, count));
    expect_error label read_operation Plan9_types.Protocol_error
      (read_protocol_message requested (Bytes.length staging) count)
      (Fd.read reader destination ~pos:1 ~len:requested);
    expect_bytes (label ^ " destination") before destination
  in
  expect_malformed_read "short staging" (Bytes.make 3 's') 2 4;
  expect_malformed_read "negative read count" (Bytes.make 4 's') (-1) 4;
  expect_malformed_read "oversized read count" (Bytes.make 4 's') 5 4;
  expect_malformed_read "multiple malformed read facts"
    (Bytes.make 3 's') 5 4;

  let read_failure : Plan9_types.native_failure =
    { Plan9_types.native_kind = 2; native_message = "injected read failure" }
  in
  let failure_destination = Bytes.of_string "failure" in
  let failure_before = Bytes.copy failure_destination in
  Fake.set_read_action (fun _ _ -> Error read_failure);
  expect_error "read native mapping" read_operation Plan9_types.Interrupted
    read_failure.native_message
    (Fd.read reader failure_destination ~pos:0 ~len:1);
  expect_bytes "read failure destination" failure_before failure_destination;

  let source = Bytes.make 4097 'w' in
  let exact_source = Bytes.make 4096 'e' in
  let exact_write_before = Fake.write_count () in
  Fake.set_write_action (fun capability actual_source position requested ->
    check "exact-capacity write capability" (capability.Fake.id = 131);
    check "exact-capacity write source" (actual_source == exact_source);
    check "exact-capacity write position" (position = 0);
    check "exact-capacity write request" (requested = 4096);
    Ok requested);
  check "exact-capacity write count"
    (expect_ok "exact-capacity write"
       (Fd.write writer exact_source ~pos:0 ~len:4096) = 4096);
  check "exact-capacity write call count"
    (Fake.write_count () = exact_write_before + 1);
  Fake.set_write_action (fun capability actual_source position requested ->
    check "large write capability" (capability.Fake.id = 131);
    check "large write copied its source" (actual_source == source);
    check "large write position" (position = 0);
    check "large write was not capped" (requested = 4096);
    force_gc ();
    Ok requested);
  check "large write count"
    (expect_ok "large write" (Fd.write writer source ~pos:0 ~len:4097)
     = 4096);

  let expect_short_write label written =
    Fake.set_write_action (fun _ actual_source position requested ->
      check (label ^ " source") (actual_source == source);
      check (label ^ " position") (position = 1);
      check (label ^ " request") (requested = 4);
      Ok written);
    expect_error label write_operation Plan9_types.Other
      (short_write_message 4 written)
      (Fd.write writer source ~pos:1 ~len:4)
  in
  expect_short_write "positive short write" 3;
  expect_short_write "zero short write" 0;

  let expect_malformed_write label count =
    Fake.set_write_action (fun _ _ _ requested ->
      check (label ^ " request") (requested = 4);
      Ok count);
    expect_error label write_operation Plan9_types.Protocol_error
      (write_protocol_message 4 count)
      (Fd.write writer source ~pos:0 ~len:4)
  in
  expect_malformed_write "negative write count" (-1);
  expect_malformed_write "oversized write count" 5;

  let write_failure : Plan9_types.native_failure =
    { Plan9_types.native_kind = 4; native_message = "injected write failure" }
  in
  let source_before = Bytes.copy source in
  Fake.set_write_action (fun _ _ _ _ -> Error write_failure);
  expect_error "write native mapping" write_operation
    Plan9_types.Protocol_error write_failure.native_message
    (Fd.write writer source ~pos:0 ~len:1);
  expect_bytes "write failure source" source_before source;

  let owner =
    expect_ok "I/O owner prepare" (Fd.Private.prepare_attach writer)
  in
  check "I/O owner commit" (Fd.Private.commit_attach owner);
  Fake.set_write_action (fun capability actual_source position requested ->
    check "owner write capability" (capability.Fake.id = 131);
    check "owner write source" (actual_source == source);
    check "owner write position" (position = 2);
    Ok requested);
  check "owner write count"
    (expect_ok "owner write"
       (Fd.Private.write owner source ~pos:2 ~len:3) = 3);
  Fake.set_read_action (fun capability requested ->
    check "owner read capability" (capability.Fake.id = 131);
    Ok (Bytes.make requested 'o', requested));
  let owner_destination = Bytes.make 3 'x' in
  check "owner read count"
    (expect_ok "owner read"
       (Fd.Private.read owner owner_destination ~pos:0 ~len:3) = 3);
  expect_bytes "owner read bytes" (Bytes.make 3 'o') owner_destination;
  ignore (expect_ok "I/O owner close" (Fd.Private.close owner));
  ignore (expect_ok "I/O reader close" (Fd.close reader))

let exercise_public_io_matrix cell prepared =
  let buffer = Bytes.make 1 'x' in
  let before_read = Fake.read_count () in
  let before_write = Fake.write_count () in
  expect_io_in_progress "public nested read" read_operation
    (Fd.read cell buffer ~pos:0 ~len:1);
  expect_io_in_progress "public nested write" write_operation
    (Fd.write cell buffer ~pos:0 ~len:1);
  expect_io_in_progress "public close during I/O" close_operation
    (Fd.close cell);
  expect_not_detached "public prepare during I/O"
    (Fd.Private.prepare_attach cell);
  check "prepared token committed during public I/O"
    (not (Fd.Private.commit_attach prepared));
  expect_unauthorized_operation "token read during public I/O" read_operation
    (Fd.Private.read prepared buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "token write during public I/O"
    write_operation (Fd.Private.write prepared buffer ~pos:0 ~len:1);
  expect_unauthorized "token close during public I/O"
    (Fd.Private.close prepared);
  expect_no_io_call "public reentrant I/O matrix"
    before_read before_write

let exercise_owner_io_matrix cell owner foreign =
  let buffer = Bytes.make 1 'x' in
  let before_read = Fake.read_count () in
  let before_write = Fake.write_count () in
  expect_io_in_progress "owner nested read" read_operation
    (Fd.Private.read owner buffer ~pos:0 ~len:1);
  expect_io_in_progress "owner nested write" write_operation
    (Fd.Private.write owner buffer ~pos:0 ~len:1);
  expect_io_in_progress "owner close during I/O" close_operation
    (Fd.Private.close owner);
  expect_unauthorized_operation "foreign read during owner I/O"
    read_operation (Fd.Private.read foreign buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "foreign write during owner I/O"
    write_operation (Fd.Private.write foreign buffer ~pos:0 ~len:1);
  expect_unauthorized "foreign close during owner I/O"
    (Fd.Private.close foreign);
  expect_transferred_operation "public read during owner I/O" read_operation
    (Fd.read cell buffer ~pos:0 ~len:1);
  expect_transferred_operation "public write during owner I/O"
    write_operation (Fd.write cell buffer ~pos:0 ~len:1);
  expect_transferred "public close during owner I/O" (Fd.close cell);
  expect_not_detached "prepare during owner I/O"
    (Fd.Private.prepare_attach cell);
  check "owner committed during owner I/O"
    (not (Fd.Private.commit_attach owner));
  check "foreign committed during owner I/O"
    (not (Fd.Private.commit_attach foreign));
  expect_no_io_call "owner reentrant I/O matrix" before_read before_write

let test_reentrant_io_and_restoration () =
  Fake.reset ();
  let public_reader, companion = fake_pipe 140 141 in
  let prepared =
    expect_ok "public read callback prepare"
      (Fd.Private.prepare_attach public_reader)
  in
  Fake.set_read_action (fun _ requested ->
    force_gc ();
    exercise_public_io_matrix public_reader prepared;
    Ok (Bytes.make requested 'r', requested));
  let destination = Bytes.make 1 'x' in
  check "outer public callback read"
    (expect_ok "outer public callback read"
       (Fd.read public_reader destination ~pos:0 ~len:1) = 1);
  ignore (expect_ok "public read restored close" (Fd.close public_reader));
  ignore (expect_ok "public read callback companion" (Fd.close companion));

  let public_writer, companion = fake_pipe 142 143 in
  let prepared =
    expect_ok "public write callback prepare"
      (Fd.Private.prepare_attach public_writer)
  in
  let source = Bytes.make 1 'w' in
  Fake.set_write_action (fun _ actual_source _ requested ->
    check "public callback write source" (actual_source == source);
    force_gc ();
    exercise_public_io_matrix public_writer prepared;
    Ok requested);
  check "outer public callback write"
    (expect_ok "outer public callback write"
       (Fd.write public_writer source ~pos:0 ~len:1) = 1);
  ignore (expect_ok "public write restored close" (Fd.close public_writer));
  ignore (expect_ok "public write callback companion" (Fd.close companion));

  let owner_cell, companion = fake_pipe 144 145 in
  let owner =
    expect_ok "owner callback prepare"
      (Fd.Private.prepare_attach owner_cell)
  in
  let foreign =
    expect_ok "owner callback foreign prepare"
      (Fd.Private.prepare_attach owner_cell)
  in
  check "owner callback commit" (Fd.Private.commit_attach owner);
  Fake.set_read_action (fun _ requested ->
    force_gc ();
    exercise_owner_io_matrix owner_cell owner foreign;
    Ok (Bytes.make requested 'o', requested));
  check "outer owner callback read"
    (expect_ok "outer owner callback read"
       (Fd.Private.read owner destination ~pos:0 ~len:1) = 1);
  Fake.set_write_action (fun _ _ _ requested ->
    force_gc ();
    exercise_owner_io_matrix owner_cell owner foreign;
    Ok requested);
  check "outer owner callback write"
    (expect_ok "outer owner callback write"
       (Fd.Private.write owner source ~pos:0 ~len:1) = 1);
  ignore (expect_ok "owner callback restored close" (Fd.Private.close owner));
  ignore (expect_ok "owner callback companion" (Fd.close companion));

  let raising_public, companion = fake_pipe 146 147 in
  let prepared =
    expect_ok "raising public prepare"
      (Fd.Private.prepare_attach raising_public)
  in
  let public_exception = Injected (ref "public read I/O callback") in
  Fake.set_read_action (fun _ _ ->
    force_gc ();
    exercise_public_io_matrix raising_public prepared;
    raise public_exception);
  expect_physical_exception "raising public read" public_exception
    (fun () -> Fd.read raising_public destination ~pos:0 ~len:1);
  Fake.set_write_action (fun _ _ _ requested -> Ok requested);
  check "public state not restored after exception"
    (expect_ok "public post-exception write"
       (Fd.write raising_public source ~pos:0 ~len:1) = 1);
  ignore (expect_ok "raising public close" (Fd.close raising_public));
  ignore (expect_ok "raising public companion" (Fd.close companion));

  let raising_owner_cell, companion = fake_pipe 148 149 in
  let raising_owner =
    expect_ok "raising owner prepare"
      (Fd.Private.prepare_attach raising_owner_cell)
  in
  let foreign =
    expect_ok "raising owner foreign prepare"
      (Fd.Private.prepare_attach raising_owner_cell)
  in
  check "raising owner commit" (Fd.Private.commit_attach raising_owner);
  let owner_exception = Injected (ref "owner write I/O callback") in
  Fake.set_write_action (fun _ _ _ _ ->
    force_gc ();
    exercise_owner_io_matrix raising_owner_cell raising_owner foreign;
    raise owner_exception);
  expect_physical_exception "raising owner write" owner_exception
    (fun () ->
      Fd.Private.write raising_owner source ~pos:0 ~len:1);
  Fake.set_read_action (fun _ requested ->
    Ok (Bytes.make requested 'z', requested));
  check "owner state not restored after exception"
    (expect_ok "owner post-exception read"
       (Fd.Private.read raising_owner destination ~pos:0 ~len:1) = 1);
  ignore (expect_ok "raising owner close"
    (Fd.Private.close raising_owner));
  ignore (expect_ok "raising owner companion" (Fd.close companion))

let test_io_during_close_attempts () =
  Fake.reset ();
  let cell, companion = fake_pipe 150 151 in
  let token =
    expect_ok "public-close I/O token" (Fd.Private.prepare_attach cell)
  in
  let buffer = Bytes.make 1 'x' in
  let public_exception = Injected (ref "public close I/O matrix") in
  Fake.set_close_action (fun _ ->
    let before_read = Fake.read_count () in
    let before_write = Fake.write_count () in
    expect_error "read during active public close" read_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Fd.read cell buffer ~pos:0 ~len:1);
    expect_error "write during active public close" write_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Fd.write cell buffer ~pos:0 ~len:1);
    expect_unauthorized_operation "token read during active public close"
      read_operation (Fd.Private.read token buffer ~pos:0 ~len:1);
    expect_unauthorized_operation "token write during active public close"
      write_operation (Fd.Private.write token buffer ~pos:0 ~len:1);
    expect_no_io_call "active public-close I/O" before_read before_write;
    raise public_exception);
  expect_physical_exception "public close I/O matrix" public_exception
    (fun () -> Fd.close cell);
  let before_read = Fake.read_count () in
  let before_write = Fake.write_count () in
  expect_error "read during inactive public close" read_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Fd.read cell buffer ~pos:0 ~len:1);
  expect_error "write during inactive public close" write_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Fd.write cell buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "token read during inactive public close"
    read_operation (Fd.Private.read token buffer ~pos:0 ~len:1);
  expect_no_io_call "inactive public-close I/O" before_read before_write;
  ignore (expect_ok "public close I/O retry" (Fd.close cell));
  expect_closed "read after terminal public close" read_operation
    (Fd.read cell buffer ~pos:0 ~len:1);
  expect_closed "write after terminal public close" write_operation
    (Fd.write cell buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "token read after terminal public close"
    read_operation (Fd.Private.read token buffer ~pos:0 ~len:1);
  ignore (expect_ok "public-close I/O companion" (Fd.close companion));

  let owner_cell, companion = fake_pipe 152 153 in
  let owner =
    expect_ok "owner-close I/O owner"
      (Fd.Private.prepare_attach owner_cell)
  in
  let foreign =
    expect_ok "owner-close I/O foreign"
      (Fd.Private.prepare_attach owner_cell)
  in
  check "owner-close I/O commit" (Fd.Private.commit_attach owner);
  let owner_exception = Injected (ref "owner close I/O matrix") in
  Fake.set_close_action (fun _ ->
    let before_read = Fake.read_count () in
    let before_write = Fake.write_count () in
    expect_transferred_operation "public read during active owner close"
      read_operation (Fd.read owner_cell buffer ~pos:0 ~len:1);
    expect_transferred_operation "public write during active owner close"
      write_operation (Fd.write owner_cell buffer ~pos:0 ~len:1);
    expect_error "owner read during active owner close" read_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Fd.Private.read owner buffer ~pos:0 ~len:1);
    expect_error "owner write during active owner close" write_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Fd.Private.write owner buffer ~pos:0 ~len:1);
    expect_unauthorized_operation "foreign read during active owner close"
      read_operation (Fd.Private.read foreign buffer ~pos:0 ~len:1);
    expect_no_io_call "active owner-close I/O" before_read before_write;
    raise owner_exception);
  expect_physical_exception "owner close I/O matrix" owner_exception
    (fun () -> Fd.Private.close owner);
  let before_read = Fake.read_count () in
  let before_write = Fake.write_count () in
  expect_transferred_operation "public read during inactive owner close"
    read_operation (Fd.read owner_cell buffer ~pos:0 ~len:1);
  expect_error "owner read during inactive owner close" read_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Fd.Private.read owner buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "foreign write during inactive owner close"
    write_operation (Fd.Private.write foreign buffer ~pos:0 ~len:1);
  expect_no_io_call "inactive owner-close I/O" before_read before_write;
  ignore (expect_ok "owner close I/O retry" (Fd.Private.close owner));
  expect_transferred_operation "public read after terminal owner close"
    read_operation (Fd.read owner_cell buffer ~pos:0 ~len:1);
  expect_closed "owner read after terminal owner close" read_operation
    (Fd.Private.read owner buffer ~pos:0 ~len:1);
  expect_closed "owner write after terminal owner close" write_operation
    (Fd.Private.write owner buffer ~pos:0 ~len:1);
  expect_unauthorized_operation "foreign read after terminal owner close"
    read_operation (Fd.Private.read foreign buffer ~pos:0 ~len:1);
  ignore (expect_ok "owner-close I/O companion" (Fd.close companion))

let descriptor_inventory () =
  let entries = Sys.readdir "/fd" in
  Array.sort String.compare entries;
  Array.to_list entries

let show_inventory entries = String.concat "," entries

let expect_clean_descriptors label operation =
  let before = descriptor_inventory () in
  operation ();
  let after = descriptor_inventory () in
  if before <> after then
    fail
      (label ^ " changed /fd: before=[" ^ show_inventory before
       ^ "] after=[" ^ show_inventory after ^ "]")

let production_pipe label = expect_ok label (Plan9_fd.pipe ())

let test_native_lifecycle () =
  expect_clean_descriptors "native lifecycle" (fun () ->
    let left, right = production_pipe "native peer pipe" in
    ignore (expect_ok "native left close" (Plan9_fd.close left));
    ignore (expect_ok "native right close" (Plan9_fd.close right));

    let left, right = production_pipe "native alias pipe" in
    let alias = left in
    ignore (expect_ok "native alias close" (Plan9_fd.close alias));
    ignore (expect_ok "native alias idempotent close"
      (Plan9_fd.close left));
    ignore (expect_ok "native alias companion close"
      (Plan9_fd.close right));

    let left, right = production_pipe "native attachment pipe" in
    let token = expect_ok "native attachment prepare"
        (Plan9_fd.Private.prepare_attach left) in
    check "native attachment commit failed"
      (Plan9_fd.Private.commit_attach token);
    expect_transferred "native public close after attachment"
      (Plan9_fd.close left);
    ignore (expect_ok "native owner close" (Plan9_fd.Private.close token));
    ignore (expect_ok "native owner idempotent close"
      (Plan9_fd.Private.close token));
    ignore (expect_ok "native attachment companion close"
      (Plan9_fd.close right));

    for _iteration = 1 to 256 do
      let left, right = production_pipe "native repeated public pipe" in
      ignore (expect_ok "native repeated public left close"
        (Plan9_fd.close left));
      ignore (expect_ok "native repeated public right close"
        (Plan9_fd.close right));

      let left, right = production_pipe "native repeated owner pipe" in
      let token = expect_ok "native repeated owner prepare"
          (Plan9_fd.Private.prepare_attach left) in
      check "native repeated owner commit failed"
        (Plan9_fd.Private.commit_attach token);
      ignore (expect_ok "native repeated owner close"
        (Plan9_fd.Private.close token));
      ignore (expect_ok "native repeated owner companion close"
        (Plan9_fd.close right))
    done)

let () =
  test_pipe_public_close_and_errors ();
  test_prepare_close_and_public_attempts ();
  test_attachment_owner_close_and_errors ();
  test_owner_close_attempts ();
  test_commit_attach_boolean_matrix ();
  test_range_chunk_and_io_lifecycle ();
  test_read_write_results ();
  test_reentrant_io_and_restoration ();
  test_io_during_close_attempts ();
  test_native_lifecycle ();
  print_endline "fd_lifecycle_test: ok"
