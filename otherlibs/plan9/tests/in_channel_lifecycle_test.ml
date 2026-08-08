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
  prerr_endline ("in_channel_lifecycle_test: " ^ message);
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

let expect_bytes label expected actual =
  if not (Bytes.equal expected actual) then
    fail
      (label ^ ": expected " ^ String.escaped (Bytes.to_string expected)
       ^ " but got " ^ String.escaped (Bytes.to_string actual))

exception Injected of string ref

let expect_physical_exception label expected operation =
  try
    ignore (operation ());
    fail (label ^ " did not raise")
  with
  | actual when actual == expected -> ()
  | _ -> fail (label ^ " replaced the designated exception value")

let of_fd_operation = "Plan9.In_channel.of_fd"
let input_operation = "Plan9.In_channel.input"
let close_operation = "Plan9.In_channel.close"
let fd_read_operation = "Plan9.Fd.read"
let fd_write_operation = "Plan9.Fd.write"
let fd_close_operation = "Plan9.Fd.close"
let fd_prepare_operation = "Plan9.Fd.Private.prepare_attach"

let not_detached_message = "descriptor is not open and detached"
let input_in_progress_message =
  "input channel operation is already in progress"
let close_in_progress_message = "input channel close is already in progress"
let channel_closed_message = "input channel is closed"
let ownership_transferred_message =
  "descriptor ownership has been transferred"
let unauthorized_token_message = "attachment token is not the committed owner"

let range_message buffer_length position length =
  "invalid byte range: buffer length " ^ string_of_int buffer_length
  ^ ", position " ^ string_of_int position
  ^ ", length " ^ string_of_int length

let fill_protocol_message buffer_length count =
  "invalid input buffer fill result: buffer length "
  ^ string_of_int buffer_length ^ ", returned count " ^ string_of_int count

let expect_range_error label buffer_length position length result =
  expect_error label input_operation Plan9_types.Invalid_argument
    (range_message buffer_length position length) result

module Primitive = struct
  type capability = { id : int }

  type read_action =
    capability -> int ->
    ((bytes * int), Plan9_types.native_failure) result

  type write_action =
    capability -> bytes -> int -> int ->
    (int, Plan9_types.native_failure) result

  type close_action =
    capability -> (unit, Plan9_types.native_failure) result

  let next_id = ref 0
  let read_action : read_action option ref = ref None
  let write_action : write_action option ref = ref None
  let close_action : close_action option ref = ref None
  let read_calls = ref 0
  let write_calls = ref 0
  let close_calls = ref 0

  let reset () =
    read_action := None;
    write_action := None;
    close_action := None;
    read_calls := 0;
    write_calls := 0;
    close_calls := 0

  let set_read_action action = read_action := Some action
  let set_write_action action = write_action := Some action
  let set_close_action action = close_action := Some action

  let pipe () =
    let left = { id = !next_id } in
    incr next_id;
    let right = { id = !next_id } in
    incr next_id;
    Ok (left, right)

  let read capability length =
    let _capability_id = capability.id in
    incr read_calls;
    match !read_action with
    | None -> fail "accepted-shape read called without an injected result"
    | Some action ->
        read_action := None;
        action capability length

  let write capability source position length =
    let _capability_id = capability.id in
    incr write_calls;
    match !write_action with
    | None -> Ok length
    | Some action ->
        write_action := None;
        action capability source position length

  let close capability =
    let _capability_id = capability.id in
    incr close_calls;
    match !close_action with
    | None -> Ok ()
    | Some action ->
        close_action := None;
        action capability
end

module Fd = Plan9_fd.Make (Primitive)
module Accepted_channel = Plan9_in_channel.Make (Fd)

let accepted_pipe label = expect_ok label (Fd.pipe ())

module Direct_descriptor = struct
  type read_action =
    bytes -> int -> int -> (int, Plan9_types.error) result

  type close_action = unit -> (unit, Plan9_types.error) result

  type t = {
    mutable open_detached : bool;
    mutable committed : bool;
    mutable lower_closed : bool;
    mutable force_commit_loss : bool;
    mutable prepare_exception : exn option;
    mutable read_actions : read_action list;
    mutable close_actions : close_action list;
    mutable prepare_calls : int;
    mutable commit_calls : int;
    mutable read_calls : int;
    mutable close_calls : int;
    mutable scratch_buffers : bytes list;
  }

  type attachment = t

  let create ?(force_commit_loss = false) ?prepare_exception () =
    {
      open_detached = true;
      committed = false;
      lower_closed = false;
      force_commit_loss;
      prepare_exception;
      read_actions = [];
      close_actions = [];
      prepare_calls = 0;
      commit_calls = 0;
      read_calls = 0;
      close_calls = 0;
      scratch_buffers = [];
    }

  let add_read_action descriptor action =
    descriptor.read_actions <- descriptor.read_actions @ [action]

  let add_close_action descriptor action =
    descriptor.close_actions <- descriptor.close_actions @ [action]

  module Private = struct
    let prepare_attach descriptor =
      descriptor.prepare_calls <- descriptor.prepare_calls + 1;
      match descriptor.prepare_exception with
      | Some exception_value -> raise exception_value
      | None ->
          if descriptor.open_detached && not descriptor.committed then
            Ok descriptor
          else
            Error
              {
                Plan9_types.operation = fd_prepare_operation;
                kind = Plan9_types.Invalid_argument;
                message = not_detached_message;
              }

    let commit_attach descriptor =
      descriptor.commit_calls <- descriptor.commit_calls + 1;
      if descriptor.force_commit_loss then false
      else if descriptor.open_detached && not descriptor.committed then begin
        descriptor.open_detached <- false;
        descriptor.committed <- true;
        true
      end else
        false

    let read descriptor destination ~pos ~len =
      descriptor.read_calls <- descriptor.read_calls + 1;
      descriptor.scratch_buffers <-
        destination :: descriptor.scratch_buffers;
      match descriptor.read_actions with
      | [] -> fail "direct read called without an injected result"
      | action :: rest ->
          descriptor.read_actions <- rest;
          action destination pos len

    let close descriptor =
      descriptor.close_calls <- descriptor.close_calls + 1;
      if descriptor.lower_closed then Ok ()
      else
        match descriptor.close_actions with
        | [] ->
            descriptor.lower_closed <- true;
            Ok ()
        | action :: rest ->
            descriptor.close_actions <- rest;
            action ()
  end
end

module Direct_channel = Plan9_in_channel.Make (Direct_descriptor)
module Direct_channel_2 = Plan9_in_channel.Make (Direct_descriptor)

let direct_data text destination position length =
  let source = Bytes.of_string text in
  let count = Bytes.length source in
  if position <> 0 || count > length then
    fail "direct data action received an invalid range";
  Bytes.blit source 0 destination position count;
  Ok count

let open_direct label descriptor =
  expect_ok label (Direct_channel.of_fd descriptor)

let test_attachment_and_precommit_semantics () =
  Primitive.reset ();
  let descriptor, _peer = accepted_pipe "accepted attachment pipe" in
  let alias = descriptor in
  let stale =
    expect_ok "prepare stale token" (Fd.Private.prepare_attach descriptor)
  in
  let channel =
    expect_ok "accepted channel attach" (Accepted_channel.of_fd descriptor)
  in
  check "accepted attach did not commit exactly once"
    (not (Fd.Private.commit_attach stale));
  let byte = Bytes.make 1 'x' in
  expect_error "attached public read" fd_read_operation
    Plan9_types.Invalid_argument ownership_transferred_message
    (Fd.read alias byte ~pos:0 ~len:1);
  expect_error "attached public write" fd_write_operation
    Plan9_types.Invalid_argument ownership_transferred_message
    (Fd.write alias byte ~pos:0 ~len:1);
  expect_error "attached public close" fd_close_operation
    Plan9_types.Invalid_argument ownership_transferred_message
    (Fd.close alias);
  expect_error "attached prepare" fd_prepare_operation
    Plan9_types.Invalid_argument not_detached_message
    (Fd.Private.prepare_attach alias);
  ignore (expect_ok "accepted channel close" (Accepted_channel.close channel));

  Primitive.reset ();
  let descriptor, _peer = accepted_pipe "precommit read pipe" in
  let token = expect_ok "precommit read prepare"
      (Fd.Private.prepare_attach descriptor) in
  Primitive.set_read_action (fun _ length ->
    check "precommit read request" (length = 1);
    Ok (Bytes.of_string "r", 1));
  let destination = Bytes.make 1 '\000' in
  check "precommit public read"
    (expect_ok "precommit public read"
       (Fd.read descriptor destination ~pos:0 ~len:1) = 1);
  expect_bytes "precommit public read byte" (Bytes.of_string "r") destination;
  check "precommit read token did not commit"
    (Fd.Private.commit_attach token);
  ignore (expect_ok "precommit read owner close" (Fd.Private.close token));

  Primitive.reset ();
  let descriptor, _peer = accepted_pipe "precommit write pipe" in
  let token = expect_ok "precommit write prepare"
      (Fd.Private.prepare_attach descriptor) in
  let observed = ref Bytes.empty in
  Primitive.set_write_action (fun _ source position length ->
    observed := Bytes.sub source position length;
    Ok length);
  let source = Bytes.of_string "write" in
  check "precommit public write"
    (expect_ok "precommit public write"
       (Fd.write descriptor source ~pos:0 ~len:(Bytes.length source))
     = Bytes.length source);
  expect_bytes "precommit public write bytes" source !observed;
  check "precommit write token did not commit"
    (Fd.Private.commit_attach token);
  ignore (expect_ok "precommit write owner close" (Fd.Private.close token));

  Primitive.reset ();
  let closed_descriptor, _peer = accepted_pipe "preparation failure pipe" in
  ignore (expect_ok "close before channel attach" (Fd.close closed_descriptor));
  expect_error "preparation failure mapping" of_fd_operation
    Plan9_types.Invalid_argument not_detached_message
    (Accepted_channel.of_fd closed_descriptor);

  let lost = Direct_descriptor.create ~force_commit_loss:true () in
  expect_error "forced lost commit" of_fd_operation
    Plan9_types.Invalid_argument not_detached_message
    (Direct_channel.of_fd lost);
  check "lost commit call count"
    (lost.prepare_calls = 1 && lost.commit_calls = 1 && lost.close_calls = 0
     && lost.open_detached && not lost.committed);

  let direct_success = Direct_descriptor.create () in
  let direct_channel = open_direct "direct successful attach" direct_success in
  check "direct successful attach call count"
    (direct_success.prepare_calls = 1 && direct_success.commit_calls = 1
     && direct_success.close_calls = 0 && direct_success.committed
     && not direct_success.open_detached);
  ignore (expect_ok "direct successful attach close"
    (Direct_channel.close direct_channel));

  let prepare_exception = Injected (ref "prepare") in
  let raising = Direct_descriptor.create
      ~prepare_exception:prepare_exception () in
  expect_physical_exception "prepare exception" prepare_exception (fun () ->
    Direct_channel.of_fd raising);
  check "prepare exception performed later ownership work"
    (raising.prepare_calls = 1 && raising.commit_calls = 0
     && raising.close_calls = 0 && raising.open_detached)

let test_ranges_zero_and_buffering () =
  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "range channel" descriptor in
  let destination = Bytes.make 4 '\165' in
  let invalid_ranges =
    [(-1, 0); (0, -1); (5, 0); (4, 1); (max_int, 1); (1, max_int)]
  in
  List.iter
    (fun (position, length) ->
      expect_range_error "open invalid range" 4 position length
        (Direct_channel.input channel destination ~pos:position ~len:length))
    invalid_ranges;
  check "invalid range initiated a read" (descriptor.read_calls = 0);

  let zero_one =
    Direct_channel.input channel destination ~pos:4 ~len:0
  in
  let zero_two =
    Direct_channel.input channel destination ~pos:4 ~len:0
  in
  check "repeated zero result identity" (zero_one == zero_two);
  check "zero result value" (expect_ok "zero input" zero_one = 0);
  check "zero input initiated a read" (descriptor.read_calls = 0);

  let second_descriptor = Direct_descriptor.create () in
  let second_channel =
    expect_ok "second Make channel"
      (Direct_channel_2.of_fd second_descriptor)
  in
  let second_zero =
    Direct_channel_2.input second_channel destination ~pos:4 ~len:0
  in
  check "cross-Make zero result identity" (zero_one == second_zero);

  Direct_descriptor.add_read_action descriptor (direct_data "ab\000cdef");
  let first = Bytes.make 6 '\165' in
  check "first buffered input count"
    (expect_ok "first buffered input"
       (Direct_channel.input channel first ~pos:1 ~len:3) = 3);
  let expected_first = Bytes.make 6 '\165' in
  Bytes.blit (Bytes.of_string "ab\000") 0 expected_first 1 3;
  expect_bytes "first buffered destination" expected_first first;
  check "first buffered read count" (descriptor.read_calls = 1);
  let second = Bytes.make 6 '\165' in
  check "buffered suffix count"
    (expect_ok "buffered suffix"
       (Direct_channel.input channel second ~pos:1 ~len:4) = 4);
  let expected_second = Bytes.make 6 '\165' in
  Bytes.blit (Bytes.of_string "cdef") 0 expected_second 1 4;
  expect_bytes "buffered suffix destination" expected_second second;
  check "buffered suffix performed another read" (descriptor.read_calls = 1);

  Direct_descriptor.add_read_action descriptor (direct_data "z");
  let third = Bytes.make 1 '\165' in
  check "second refill count"
    (expect_ok "second refill"
       (Direct_channel.input channel third ~pos:0 ~len:1) = 1);
  expect_bytes "second refill byte" (Bytes.of_string "z") third;
  check "second refill call count" (descriptor.read_calls = 2);
  begin match List.rev descriptor.scratch_buffers with
  | first_scratch :: second_scratch :: _ ->
      check "scratch buffer was not physically reused"
        (first_scratch == second_scratch)
  | _ -> fail "scratch-buffer trace was incomplete"
  end;

  let large_descriptor = Direct_descriptor.create () in
  let large_channel = open_direct "large request channel" large_descriptor in
  let payload = Bytes.init 4096 (fun index -> Char.chr (index land 255)) in
  Direct_descriptor.add_read_action large_descriptor
    (fun scratch position length ->
      check "large lower range" (position = 0 && length = 4096);
      Bytes.blit payload 0 scratch 0 4096;
      Ok 4096);
  let large_destination = Bytes.make 5000 '\165' in
  check "large request progress"
    (expect_ok "large request"
       (Direct_channel.input large_channel large_destination ~pos:0 ~len:5000)
     = 4096);
  check "large request lower call count" (large_descriptor.read_calls = 1);
  expect_bytes "large request prefix" payload
    (Bytes.sub large_destination 0 4096);
  check "large request suffix changed"
    (Bytes.get large_destination 4096 = '\165');
  ignore (expect_ok "range channel close" (Direct_channel.close channel));
  ignore (expect_ok "second Make close" (Direct_channel_2.close second_channel));
  ignore (expect_ok "large channel close" (Direct_channel.close large_channel))

let test_malformed_errors_eof_and_restoration () =
  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "malformed channel" descriptor in
  let destination = Bytes.make 5 '\165' in
  Direct_descriptor.add_read_action descriptor
    (fun scratch _ _ -> Bytes.set scratch 0 'x'; Ok (-1));
  expect_error "negative fill" input_operation Plan9_types.Protocol_error
    (fill_protocol_message 4096 (-1))
    (Direct_channel.input channel destination ~pos:1 ~len:2);
  expect_bytes "negative fill destination" (Bytes.make 5 '\165') destination;
  Direct_descriptor.add_read_action descriptor
    (fun scratch _ _ -> Bytes.fill scratch 0 16 'y'; Ok 4097);
  expect_error "oversized fill" input_operation Plan9_types.Protocol_error
    (fill_protocol_message 4096 4097)
    (Direct_channel.input channel destination ~pos:1 ~len:2);
  expect_bytes "oversized fill destination" (Bytes.make 5 '\165') destination;
  Direct_descriptor.add_read_action descriptor (direct_data "ok");
  check "valid refill after malformed counts"
    (expect_ok "valid refill after malformed counts"
       (Direct_channel.input channel destination ~pos:1 ~len:2) = 2);
  let expected = Bytes.make 5 '\165' in
  Bytes.blit (Bytes.of_string "ok") 0 expected 1 2;
  expect_bytes "valid refill destination" expected destination;

  let lower_error : Plan9_types.error =
    {
      operation = fd_read_operation;
      kind = Plan9_types.Interrupted;
      message = "designated lower read error";
    }
  in
  Direct_descriptor.add_read_action descriptor
    (fun _ _ _ -> Error lower_error);
  let unchanged = Bytes.make 3 '\165' in
  expect_error "lower error mapping" input_operation Plan9_types.Interrupted
    "designated lower read error"
    (Direct_channel.input channel unchanged ~pos:0 ~len:3);
  expect_bytes "lower error destination" (Bytes.make 3 '\165') unchanged;

  Direct_descriptor.add_read_action descriptor (fun _ _ _ -> Ok 0);
  check "first EOF"
    (expect_ok "first EOF"
       (Direct_channel.input channel unchanged ~pos:0 ~len:1) = 0);
  Direct_descriptor.add_read_action descriptor (direct_data "e");
  check "data after observed EOF"
    (expect_ok "data after EOF"
       (Direct_channel.input channel unchanged ~pos:0 ~len:1) = 1);
  check "EOF was cached" (descriptor.read_calls = 6);
  check "data after EOF byte" (Bytes.get unchanged 0 = 'e');

  let read_exception = Injected (ref "read") in
  Direct_descriptor.add_read_action descriptor
    (fun _ _ _ -> raise read_exception);
  expect_physical_exception "lower read exception" read_exception (fun () ->
    Direct_channel.input channel unchanged ~pos:0 ~len:1);
  Direct_descriptor.add_read_action descriptor (direct_data "r");
  check "read after exception"
    (expect_ok "read after exception"
       (Direct_channel.input channel unchanged ~pos:0 ~len:1) = 1);
  check "read restoration byte" (Bytes.get unchanged 0 = 'r');
  ignore (expect_ok "malformed channel close" (Direct_channel.close channel));

  Primitive.reset ();
  let accepted_descriptor, _peer = accepted_pipe "malformed Fd pipe" in
  let accepted_channel =
    expect_ok "malformed Fd channel"
      (Accepted_channel.of_fd accepted_descriptor)
  in
  Primitive.set_read_action (fun _ length ->
    Ok (Bytes.make (length - 1) '\000', length));
  expect_error "sanitized Fd malformed result" input_operation
    Plan9_types.Protocol_error
    "invalid descriptor read result: requested 4096 bytes, staging has 4095 bytes, returned count 4096"
    (Accepted_channel.input accepted_channel unchanged ~pos:0 ~len:1);
  ignore (expect_ok "malformed Fd channel close"
    (Accepted_channel.close accepted_channel))

let test_reentrancy_and_close_schedules () =
  Primitive.reset ();
  let descriptor, _peer = accepted_pipe "reentrant input pipe" in
  let alias = descriptor in
  let stale = expect_ok "reentrant stale prepare"
      (Fd.Private.prepare_attach descriptor) in
  let channel = expect_ok "reentrant input channel"
      (Accepted_channel.of_fd descriptor) in
  let destination = Bytes.make 2 '\165' in
  Primitive.set_read_action (fun _ length ->
    check "reentrant input request length" (length = 4096);
    force_gc ();
    let reads_before = !(Primitive.read_calls) in
    expect_error "reentrant zero input" input_operation
      Plan9_types.Invalid_argument input_in_progress_message
      (Accepted_channel.input channel destination ~pos:0 ~len:0);
    expect_range_error "reentrant invalid range" 2 (-1) 0
      (Accepted_channel.input channel destination ~pos:(-1) ~len:0);
    expect_error "close during input" close_operation
      Plan9_types.Invalid_argument input_in_progress_message
      (Accepted_channel.close channel);
    expect_error "public read during channel input" fd_read_operation
      Plan9_types.Invalid_argument ownership_transferred_message
      (Fd.read alias destination ~pos:0 ~len:1);
    expect_error "public write during channel input" fd_write_operation
      Plan9_types.Invalid_argument ownership_transferred_message
      (Fd.write alias destination ~pos:0 ~len:1);
    expect_error "public close during channel input" fd_close_operation
      Plan9_types.Invalid_argument ownership_transferred_message
      (Fd.close alias);
    expect_error "stale token read during channel input" fd_read_operation
      Plan9_types.Invalid_argument unauthorized_token_message
      (Fd.Private.read stale destination ~pos:0 ~len:1);
    expect_error "stale token close during channel input" fd_close_operation
      Plan9_types.Invalid_argument unauthorized_token_message
      (Fd.Private.close stale);
    check "reentrant operation reached primitive read"
      (!(Primitive.read_calls) = reads_before);
    let staging = Bytes.make length '\000' in
    Bytes.set staging 0 'q';
    Ok (staging, 1));
  check "outer input after callbacks"
    (expect_ok "outer input after callbacks"
       (Accepted_channel.input channel destination ~pos:1 ~len:1) = 1);
  check "outer input byte" (Bytes.get destination 1 = 'q');

  Primitive.set_close_action (fun _ ->
    force_gc ();
    let closes_before = !(Primitive.close_calls) in
    expect_error "input during accepted close" input_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Accepted_channel.input channel destination ~pos:0 ~len:1);
    expect_error "zero input during accepted close" input_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Accepted_channel.input channel destination ~pos:0 ~len:0);
    expect_range_error "invalid range during accepted close" 2 (-1) 0
      (Accepted_channel.input channel destination ~pos:(-1) ~len:0);
    expect_error "reentrant accepted close" close_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Accepted_channel.close channel);
    check "reentrant close reached primitive"
      (!(Primitive.close_calls) = closes_before);
    Ok ());
  let accepted_close = Accepted_channel.close channel in
  ignore (expect_ok "accepted close" accepted_close);
  let accepted_repeat = Accepted_channel.close channel in
  check "accepted repeated close identity" (accepted_close == accepted_repeat);
  expect_error "input after accepted close" input_operation
    Plan9_types.Invalid_argument channel_closed_message
    (Accepted_channel.input channel destination ~pos:0 ~len:0);
  expect_range_error "invalid range after accepted close" 2 (-1) 0
    (Accepted_channel.input channel destination ~pos:(-1) ~len:0);

  let before_descriptor = Direct_descriptor.create () in
  let before_channel = open_direct "raise-before close channel"
      before_descriptor in
  let before_exception = Injected (ref "close before terminal") in
  Direct_descriptor.add_close_action before_descriptor
    (fun () -> raise before_exception);
  expect_physical_exception "close raise before terminal" before_exception
    (fun () -> Direct_channel.close before_channel);
  expect_error "input during inactive close" input_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Direct_channel.input before_channel destination ~pos:0 ~len:0);
  expect_range_error "invalid range during inactive close" 2 (-1) 0
    (Direct_channel.input before_channel destination ~pos:(-1) ~len:0);
  ignore (expect_ok "retry raise-before close"
    (Direct_channel.close before_channel));
  check "raise-before close calls" (before_descriptor.close_calls = 2);
  check "raise-before retry restored public authority"
    (before_descriptor.committed && not before_descriptor.open_detached);

  let after_descriptor = Direct_descriptor.create () in
  let after_channel = open_direct "raise-after close channel"
      after_descriptor in
  let after_exception = Injected (ref "close after terminal") in
  Direct_descriptor.add_close_action after_descriptor
    (fun () ->
      after_descriptor.lower_closed <- true;
      raise after_exception);
  expect_physical_exception "close raise after lower terminal" after_exception
    (fun () -> Direct_channel.close after_channel);
  expect_error "input after lower-terminal exception" input_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Direct_channel.input after_channel destination ~pos:0 ~len:1);
  ignore (expect_ok "retry lower-terminal close"
    (Direct_channel.close after_channel));
  check "raise-after close calls" (after_descriptor.close_calls = 2);
  check "raise-after retry restored public authority"
    (after_descriptor.committed && not after_descriptor.open_detached);

  let error_descriptor = Direct_descriptor.create () in
  let error_channel = open_direct "close error channel" error_descriptor in
  let native_error : Plan9_types.error =
    {
      operation = fd_close_operation;
      kind = Plan9_types.Other;
      message = "designated close failure";
    }
  in
  Direct_descriptor.add_close_action error_descriptor (fun () ->
    error_descriptor.lower_closed <- true;
    Error native_error);
  expect_error "close error mapping" close_operation Plan9_types.Other
    "designated close failure" (Direct_channel.close error_channel);
  let repeated_one = Direct_channel.close error_channel in
  let repeated_two = Direct_channel.close error_channel in
  check "terminal close result identity" (repeated_one == repeated_two);
  check "terminal close repeated lower work" (error_descriptor.close_calls = 1);

  let second_descriptor = Direct_descriptor.create () in
  let second_channel = expect_ok "cross-Make close channel"
      (Direct_channel_2.of_fd second_descriptor) in
  let second_close = Direct_channel_2.close second_channel in
  ignore (expect_ok "cross-Make close" second_close);
  check "cross-Make close result identity" (repeated_one == second_close)

let test_gc_and_buffer_recovery () =
  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "GC channel" descriptor in
  Direct_descriptor.add_read_action descriptor (direct_data "abcdef");
  let first = Bytes.make 2 '\165' in
  check "GC first input"
    (expect_ok "GC first input"
       (Direct_channel.input channel first ~pos:0 ~len:2) = 2);
  expect_bytes "GC first bytes" (Bytes.of_string "ab") first;
  force_gc ();
  let second = Bytes.make 4 '\165' in
  check "GC buffered input"
    (expect_ok "GC buffered input"
       (Direct_channel.input channel second ~pos:0 ~len:4) = 4);
  expect_bytes "GC buffered bytes" (Bytes.of_string "cdef") second;
  check "GC duplicated lower read" (descriptor.read_calls = 1);
  force_gc ();
  let close_one = Direct_channel.close channel in
  ignore (expect_ok "GC close" close_one);
  force_gc ();
  let close_two = Direct_channel.close channel in
  check "GC terminal close identity" (close_one == close_two);
  check "GC duplicated lower close" (descriptor.close_calls = 1)

let () =
  test_attachment_and_precommit_semantics ();
  test_ranges_zero_and_buffering ();
  test_malformed_errors_eof_and_restoration ();
  test_reentrancy_and_close_schedules ();
  test_gc_and_buffer_recovery ();
  print_endline
    "in_channel_lifecycle_test: ok (conditional precommit/POPTRAP schedules require static audit)"
