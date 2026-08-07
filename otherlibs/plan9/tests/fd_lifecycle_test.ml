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
let prepare_operation = "Plan9.Fd.Private.prepare_attach"
let transferred_message = "descriptor ownership has been transferred"
let close_in_progress_message = "descriptor close is already in progress"
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

module Fake = struct
  type capability = { id : int }

  type call =
    | Pipe
    | Close of int

  type pipe_action =
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  type close_action =
    capability -> (unit, Plan9_types.native_failure) result

  let calls_reversed = ref []
  let next_pipe_action : pipe_action option ref = ref None
  let next_close_action : close_action option ref = ref None

  let reset () =
    calls_reversed := [];
    next_pipe_action := None;
    next_close_action := None

  let capability id = { id }
  let calls () = List.rev !calls_reversed

  let close_count () =
    List.fold_left
      (fun count -> function Pipe -> count | Close _ -> count + 1)
      0 !calls_reversed

  let set_pipe_action action = next_pipe_action := Some action
  let set_close_action action = next_close_action := Some action

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
end

module Fd = Plan9_fd.Make (Fake)

let show_call = function
  | Fake.Pipe -> "pipe"
  | Fake.Close id -> "close(" ^ string_of_int id ^ ")"

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
  test_native_lifecycle ();
  print_endline "fd_lifecycle_test: ok"
