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
let input_line_operation = "Plan9.In_channel.input_line"
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

let negative_bound_message maximum =
  "maximum byte count must be nonnegative: " ^ string_of_int maximum

let oversized_bound_message maximum =
  "maximum byte count exceeds Sys.max_string_length: "
  ^ string_of_int maximum

let line_limit_message maximum =
  "input line exceeds maximum of " ^ string_of_int maximum ^ " bytes"

let expect_line label expected result =
  match expect_ok label result with
  | None -> fail (label ^ " unexpectedly returned EOF")
  | Some actual ->
      if actual <> expected then
        fail
          (label ^ ": expected " ^ String.escaped expected ^ " but got "
           ^ String.escaped actual)

let expect_some_line label result =
  match expect_ok label result with
  | None -> fail (label ^ " unexpectedly returned EOF")
  | Some line -> line

let expect_no_line label result =
  match expect_ok label result with
  | None -> ()
  | Some line ->
      fail (label ^ " returned line " ^ String.escaped line ^ " at EOF")

let expect_bound_error label maximum message result =
  expect_error label input_line_operation Plan9_types.Invalid_argument
    (message maximum) result

let expect_line_limit label maximum result =
  expect_error label input_line_operation Plan9_types.Other
    (line_limit_message maximum) result

let check_repeated_string label character length value =
  if String.length value <> length then
    fail
      (label ^ " length was " ^ string_of_int (String.length value)
       ^ " instead of " ^ string_of_int length);
  for index = 0 to length - 1 do
    if String.unsafe_get value index <> character then
      fail (label ^ " differed at byte " ^ string_of_int index)
  done

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
    mutable generated_read_action : read_action option;
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
      generated_read_action = None;
      close_actions = [];
      prepare_calls = 0;
      commit_calls = 0;
      read_calls = 0;
      close_calls = 0;
      scratch_buffers = [];
    }

  let add_read_action descriptor action =
    descriptor.read_actions <- descriptor.read_actions @ [action]

  let set_read_actions descriptor actions =
    descriptor.read_actions <- actions

  let set_generated_read_action descriptor action =
    descriptor.generated_read_action <- Some action

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
      | [] ->
          begin match descriptor.generated_read_action with
          | None -> fail "direct read called without an injected result"
          | Some action -> action destination pos len
          end
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

let direct_error kind message _destination _position _length =
  Error
    {
      Plan9_types.operation = fd_read_operation;
      kind;
      message;
    }

let install_generated_line ?(on_read = fun () -> ()) descriptor
    ~body_length ~body_byte ~terminated ~max_chunk =
  let remaining = ref body_length in
  let newline_pending = ref terminated in
  let produced_counts = ref [] in
  Direct_descriptor.set_generated_read_action descriptor
    (fun destination position length ->
      on_read ();
      let capacity = if max_chunk < length then max_chunk else length in
      let body_count =
        if !remaining < capacity then !remaining else capacity
      in
      if body_count > 0 then
        Bytes.fill destination position body_count body_byte;
      remaining := !remaining - body_count;
      let count = ref body_count in
      if !remaining = 0 && !newline_pending && !count < capacity then begin
        Bytes.set destination (position + !count) '\n';
        newline_pending := false;
        incr count
      end;
      produced_counts := !count :: !produced_counts;
      Ok !count);
  produced_counts

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
    expect_error "input_line during active input" input_line_operation
      Plan9_types.Invalid_argument input_in_progress_message
      (Accepted_channel.input_line ~max_bytes:0 channel);
    expect_bound_error "invalid input_line bound during active input" (-1)
      negative_bound_message
      (Accepted_channel.input_line ~max_bytes:(-1) channel);
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
    expect_error "input_line during accepted close" input_line_operation
      Plan9_types.Invalid_argument close_in_progress_message
      (Accepted_channel.input_line ~max_bytes:0 channel);
    expect_bound_error "invalid input_line bound during accepted close" (-1)
      negative_bound_message
      (Accepted_channel.input_line ~max_bytes:(-1) channel);
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
  expect_error "input_line after accepted close" input_line_operation
    Plan9_types.Invalid_argument channel_closed_message
    (Accepted_channel.input_line ~max_bytes:0 channel);
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
  expect_error "input_line during inactive close" input_line_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Direct_channel.input_line ~max_bytes:0 before_channel);
  expect_bound_error "invalid input_line during inactive close" (-1)
    negative_bound_message
    (Direct_channel.input_line ~max_bytes:(-1) before_channel);
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
  expect_error "input_line after lower-terminal exception" input_line_operation
    Plan9_types.Invalid_argument close_in_progress_message
    (Direct_channel.input_line ~max_bytes:0 after_channel);
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

let test_line_bounds_and_lifecycle () =
  check "Sys.max_string_length is not below the default line bound"
    (Sys.max_string_length >= 1_048_576);
  check "Sys.max_string_length is not strictly below max_int"
    (Sys.max_string_length < max_int);
  let above_string_limit = Sys.max_string_length + 1 in
  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "line bound channel" descriptor in
  List.iter
    (fun maximum ->
      expect_bound_error "negative line bound" maximum negative_bound_message
        (Direct_channel.input_line ~max_bytes:maximum channel))
    [min_int; -1];
  List.iter
    (fun maximum ->
      expect_bound_error "oversized line bound" maximum
        oversized_bound_message
        (Direct_channel.input_line ~max_bytes:maximum channel))
    [above_string_limit; max_int];
  check "invalid line bound initiated lower work" (descriptor.read_calls = 0);
  Direct_descriptor.set_read_actions descriptor
    [ (fun _ _ _ -> Ok 0); (fun _ _ _ -> Ok 0);
      (fun _ _ _ -> Ok 0); (fun _ _ _ -> Ok 0) ];
  expect_no_line "zero valid line bound"
    (Direct_channel.input_line ~max_bytes:0 channel);
  expect_no_line "one valid line bound"
    (Direct_channel.input_line ~max_bytes:1 channel);
  expect_no_line "maximum valid line bound"
    (Direct_channel.input_line ~max_bytes:Sys.max_string_length channel);
  expect_no_line "default valid line bound"
    (Direct_channel.input_line channel);
  check "valid line bounds did not reach lifecycle and refill"
    (descriptor.read_calls = 4);

  let active_descriptor = Direct_descriptor.create () in
  let active_channel = open_direct "active line channel" active_descriptor in
  Direct_descriptor.add_read_action active_descriptor
    (fun destination position length ->
      let calls = active_descriptor.read_calls in
      let byte = Bytes.make 1 '\165' in
      expect_error "input during input_line" input_operation
        Plan9_types.Invalid_argument input_in_progress_message
        (Direct_channel.input active_channel byte ~pos:0 ~len:1);
      expect_error "input_line during input_line" input_line_operation
        Plan9_types.Invalid_argument input_in_progress_message
        (Direct_channel.input_line ~max_bytes:1 active_channel);
      expect_bound_error "invalid bound during input_line" (-1)
        negative_bound_message
        (Direct_channel.input_line ~max_bytes:(-1) active_channel);
      expect_range_error "invalid input range during input_line" 1 (-1) 0
        (Direct_channel.input active_channel byte ~pos:(-1) ~len:0);
      expect_error "close during input_line" close_operation
        Plan9_types.Invalid_argument input_in_progress_message
        (Direct_channel.close active_channel);
      check "reentrant line operation reached lower read"
        (active_descriptor.read_calls = calls);
      direct_data "x\n" destination position length);
  expect_line "outer input_line after reentrancy" "x"
    (Direct_channel.input_line ~max_bytes:1 active_channel);
  ignore (expect_ok "active line close"
    (Direct_channel.close active_channel));
  expect_error "input_line after terminal close" input_line_operation
    Plan9_types.Invalid_argument channel_closed_message
    (Direct_channel.input_line ~max_bytes:0 active_channel);
  expect_bound_error "invalid bound after terminal close" (-1)
    negative_bound_message
    (Direct_channel.input_line ~max_bytes:(-1) active_channel);
  ignore (expect_ok "line bound close" (Direct_channel.close channel))

let test_line_semantics_and_boundaries () =
  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "basic line channel" descriptor in
  Direct_descriptor.set_read_actions descriptor
    [direct_data "\n\nabc\nunterminated"; (fun _ _ _ -> Ok 0)];
  expect_line "first empty line" "" (Direct_channel.input_line channel);
  expect_line "second empty line" "" (Direct_channel.input_line channel);
  expect_line "terminated basic line" "abc"
    (Direct_channel.input_line channel);
  expect_line "unterminated basic line" "unterminated"
    (Direct_channel.input_line channel);
  check "buffered basic lines refilled unexpectedly"
    (descriptor.read_calls = 2);
  Direct_descriptor.add_read_action descriptor (direct_data "later\n");
  expect_line "data after unterminated line EOF" "later"
    (Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor (fun _ _ _ -> Ok 0);
  expect_no_line "basic observed EOF" (Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor (direct_data "again\n");
  expect_line "data after observed line EOF" "again"
    (Direct_channel.input_line channel);
  check "line EOF was cached" (descriptor.read_calls = 5);
  let short_descriptor = Direct_descriptor.create () in
  let short_channel = open_direct "saved short channel" short_descriptor in
  Direct_descriptor.add_read_action short_descriptor (direct_data "short\n");
  let saved_short = expect_some_line "saved short line"
      (Direct_channel.input_line ~max_bytes:5 short_channel) in
  Direct_descriptor.add_read_action short_descriptor (direct_data "reuse\n");
  expect_line "short-line scratch reuse" "reuse"
    (Direct_channel.input_line short_channel);
  force_gc ();
  check "saved short line changed after GC" (saved_short = "short");
  ignore (expect_ok "saved short close" (Direct_channel.close short_channel));
  ignore (expect_ok "basic line close" (Direct_channel.close channel));

  let binary_content = Bytes.create 255 in
  let output = ref 0 in
  for byte = 0 to 255 do
    if byte <> 10 then begin
      Bytes.set binary_content !output (Char.chr byte);
      incr output
    end
  done;
  let binary_payload = Bytes.create 256 in
  Bytes.blit binary_content 0 binary_payload 0 255;
  Bytes.set binary_payload 255 '\n';
  let binary_descriptor = Direct_descriptor.create () in
  let binary_channel = open_direct "binary line channel" binary_descriptor in
  Direct_descriptor.add_read_action binary_descriptor
    (fun destination position length ->
      check "binary line lower capacity" (length >= 256);
      Bytes.blit binary_payload 0 destination position 256;
      Ok 256);
  expect_line "all binary non-newline bytes" (Bytes.to_string binary_content)
    (Direct_channel.input_line binary_channel);
  ignore (expect_ok "binary line close"
    (Direct_channel.close binary_channel));

  List.iter
    (fun length ->
      let boundary_descriptor = Direct_descriptor.create () in
      let boundary_channel = open_direct "boundary line channel"
          boundary_descriptor in
      let trace = install_generated_line boundary_descriptor
          ~body_length:length ~body_byte:'b' ~terminated:true
          ~max_chunk:4096 in
      let line = expect_some_line "scratch-boundary line"
          (Direct_channel.input_line boundary_channel) in
      check_repeated_string "scratch-boundary bytes" 'b' length line;
      let expected_calls = if length = 4095 then 1 else 2 in
      check "scratch-boundary lower-call count"
        (boundary_descriptor.read_calls = expected_calls
         && List.length !trace = expected_calls);
      ignore (expect_ok "boundary line close"
        (Direct_channel.close boundary_channel)))
    [4095; 4096; 4097];

  let stress_descriptor = Direct_descriptor.create () in
  let stress_channel = open_direct "one-byte terminated channel"
      stress_descriptor in
  let stress_trace = install_generated_line
      ~on_read:(fun () ->
        if stress_descriptor.read_calls mod 4096 = 0 then force_gc ())
      stress_descriptor
      ~body_length:16_384 ~body_byte:'s' ~terminated:true ~max_chunk:1 in
  let saved = expect_some_line "one-byte terminated line"
      (Direct_channel.input_line stress_channel) in
  check_repeated_string "one-byte terminated bytes" 's' 16_384 saved;
  check "one-byte terminated call trace"
    (stress_descriptor.read_calls = 16_385
     && List.length !stress_trace = 16_385
     && List.for_all (( = ) 1) !stress_trace);
  Direct_descriptor.add_read_action stress_descriptor (direct_data "mutate\n");
  expect_line "scratch mutation after saved line" "mutate"
    (Direct_channel.input_line stress_channel);
  force_gc ();
  check_repeated_string "saved line after scratch reuse and GC" 's' 16_384
    saved;
  ignore (expect_ok "terminated stress close"
    (Direct_channel.close stress_channel));

  let eof_stress_descriptor = Direct_descriptor.create () in
  let eof_stress_channel = open_direct "one-byte unterminated channel"
      eof_stress_descriptor in
  let eof_stress_trace = install_generated_line eof_stress_descriptor
      ~body_length:16_384 ~body_byte:'u' ~terminated:false ~max_chunk:1 in
  let eof_line = expect_some_line "one-byte unterminated line"
      (Direct_channel.input_line eof_stress_channel) in
  check_repeated_string "one-byte unterminated bytes" 'u' 16_384 eof_line;
  check "one-byte unterminated call trace"
    (eof_stress_descriptor.read_calls = 16_385
     && List.length !eof_stress_trace = 16_385
     && List.hd !eof_stress_trace = 0);
  force_gc ();
  check_repeated_string "unterminated line after GC" 'u' 16_384 eof_line;
  ignore (expect_ok "unterminated stress close"
    (Direct_channel.close eof_stress_channel))

let test_line_limits_and_positions () =
  let mixed_descriptor = Direct_descriptor.create () in
  let mixed_channel = open_direct "mixed input line channel"
      mixed_descriptor in
  Direct_descriptor.add_read_action mixed_descriptor
    (direct_data "xxabc\nrest");
  let prefix = Bytes.make 2 '\165' in
  check "mixed ordinary prefix count"
    (expect_ok "mixed ordinary prefix"
       (Direct_channel.input mixed_channel prefix ~pos:0 ~len:2) = 2);
  expect_bytes "mixed ordinary prefix bytes" (Bytes.of_string "xx") prefix;
  expect_line "line after ordinary prefix" "abc"
    (Direct_channel.input_line mixed_channel);
  let mixed_suffix = Bytes.make 4 '\165' in
  check "mixed suffix count"
    (expect_ok "mixed suffix"
       (Direct_channel.input mixed_channel mixed_suffix ~pos:0 ~len:4) = 4);
  expect_bytes "mixed suffix bytes" (Bytes.of_string "rest") mixed_suffix;
  check "mixed operations performed another refill"
    (mixed_descriptor.read_calls = 1);
  ignore (expect_ok "mixed input line close"
    (Direct_channel.close mixed_channel));

  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "limit position channel" descriptor in
  Direct_descriptor.add_read_action descriptor (direct_data "abcd\nnext\n");
  expect_line_limit "one-byte line excess" 3
    (Direct_channel.input_line ~max_bytes:3 channel);
  expect_line "line after retained excess" "d"
    (Direct_channel.input_line ~max_bytes:3 channel);
  expect_line "line after retained excess suffix" "next"
    (Direct_channel.input_line channel);
  check "buffered excess caused a refill" (descriptor.read_calls = 1);
  ignore (expect_ok "limit position close" (Direct_channel.close channel));

  let exact_descriptor = Direct_descriptor.create () in
  let exact_channel = open_direct "exact limit channel" exact_descriptor in
  Direct_descriptor.add_read_action exact_descriptor
    (direct_data "abc\nrest");
  expect_line "exact-limit newline" "abc"
    (Direct_channel.input_line ~max_bytes:3 exact_channel);
  let suffix = Bytes.make 4 '\165' in
  check "exact-limit suffix input count"
    (expect_ok "exact-limit suffix input"
       (Direct_channel.input exact_channel suffix ~pos:0 ~len:4) = 4);
  expect_bytes "exact-limit suffix bytes" (Bytes.of_string "rest") suffix;
  check "exact-limit suffix refilled" (exact_descriptor.read_calls = 1);
  ignore (expect_ok "exact limit close"
    (Direct_channel.close exact_channel));

  let lookahead_descriptor = Direct_descriptor.create () in
  let lookahead_channel = open_direct "newline lookahead channel"
      lookahead_descriptor in
  Direct_descriptor.set_read_actions lookahead_descriptor
    [direct_data "abc"; direct_data "\nrest"];
  expect_line "separate newline lookahead" "abc"
    (Direct_channel.input_line ~max_bytes:3 lookahead_channel);
  let lookahead_suffix = Bytes.make 4 '\165' in
  check "lookahead suffix count"
    (expect_ok "lookahead suffix"
       (Direct_channel.input lookahead_channel lookahead_suffix ~pos:0 ~len:4)
     = 4);
  expect_bytes "lookahead suffix bytes" (Bytes.of_string "rest")
    lookahead_suffix;
  check "lookahead suffix caused another read"
    (lookahead_descriptor.read_calls = 2);
  ignore (expect_ok "newline lookahead close"
    (Direct_channel.close lookahead_channel));

  let excess_descriptor = Direct_descriptor.create () in
  let excess_channel = open_direct "excess lookahead channel"
      excess_descriptor in
  Direct_descriptor.set_read_actions excess_descriptor
    [direct_data "abc"; direct_data "xrest"];
  expect_line_limit "separate excess lookahead" 3
    (Direct_channel.input_line ~max_bytes:3 excess_channel);
  let retained = Bytes.make 5 '\165' in
  check "retained lookahead excess count"
    (expect_ok "retained lookahead excess"
       (Direct_channel.input excess_channel retained ~pos:0 ~len:5) = 5);
  expect_bytes "retained lookahead excess bytes" (Bytes.of_string "xrest")
    retained;
  check "retained lookahead excess refilled"
    (excess_descriptor.read_calls = 2);
  ignore (expect_ok "excess lookahead close"
    (Direct_channel.close excess_channel));

  let zero_descriptor = Direct_descriptor.create () in
  let zero_channel = open_direct "zero line limit channel" zero_descriptor in
  Direct_descriptor.add_read_action zero_descriptor (direct_data "\n");
  expect_line "zero-limit empty line" ""
    (Direct_channel.input_line ~max_bytes:0 zero_channel);
  Direct_descriptor.add_read_action zero_descriptor (direct_data "x\n");
  expect_line_limit "zero-limit content" 0
    (Direct_channel.input_line ~max_bytes:0 zero_channel);
  expect_line "retained zero-limit content" "x"
    (Direct_channel.input_line ~max_bytes:1 zero_channel);
  ignore (expect_ok "zero line limit close"
    (Direct_channel.close zero_channel));

  let eof_descriptor = Direct_descriptor.create () in
  let eof_channel = open_direct "exact-limit EOF channel" eof_descriptor in
  ignore (install_generated_line eof_descriptor ~body_length:3
    ~body_byte:'e' ~terminated:false ~max_chunk:4096);
  expect_line "exact-limit unterminated line" "eee"
    (Direct_channel.input_line ~max_bytes:3 eof_channel);
  Direct_descriptor.add_read_action eof_descriptor (direct_data "new\n");
  expect_line "data after exact-limit unterminated EOF" "new"
    (Direct_channel.input_line eof_channel);
  ignore (expect_ok "exact-limit EOF close"
    (Direct_channel.close eof_channel))

let test_line_errors_and_exceptions () =
  let written_error_descriptor = Direct_descriptor.create () in
  let written_error_channel = open_direct "written line error channel"
      written_error_descriptor in
  let written_error : Plan9_types.error =
    {
      operation = fd_read_operation;
      kind = Plan9_types.Other;
      message = "written scratch line error";
    }
  in
  Direct_descriptor.add_read_action written_error_descriptor
    (fun scratch _ _ ->
      Bytes.fill scratch 0 8 'w';
      Error written_error);
  expect_error "written scratch line error" input_line_operation
    Plan9_types.Other "written scratch line error"
    (Direct_channel.input_line written_error_channel);
  Direct_descriptor.add_read_action written_error_descriptor
    (direct_data "z\n");
  expect_line "line after written scratch error" "z"
    (Direct_channel.input_line written_error_channel);
  ignore (expect_ok "written line error close"
    (Direct_channel.close written_error_channel));

  let descriptor = Direct_descriptor.create () in
  let channel = open_direct "line lower error channel" descriptor in
  Direct_descriptor.set_read_actions descriptor
    [ direct_data "abc";
      direct_error Plan9_types.Interrupted "designated line read error" ];
  expect_error "line lower error after progress" input_line_operation
    Plan9_types.Interrupted "designated line read error"
    (Direct_channel.input_line ~max_bytes:10 channel);
  check "line lower error retried" (descriptor.read_calls = 2);
  Direct_descriptor.add_read_action descriptor (direct_data "d\n");
  expect_line "position after line lower error" "d"
    (Direct_channel.input_line channel);

  Direct_descriptor.add_read_action descriptor
    (fun scratch _ _ -> Bytes.set scratch 0 'x'; Ok (-1));
  expect_error "negative line fill" input_line_operation
    Plan9_types.Protocol_error (fill_protocol_message 4096 (-1))
    (Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor
    (fun scratch _ _ -> Bytes.fill scratch 0 16 'y'; Ok 4097);
  expect_error "oversized line fill" input_line_operation
    Plan9_types.Protocol_error (fill_protocol_message 4096 4097)
    (Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor
    (fun scratch _ _ -> Bytes.set scratch 0 'z'; Ok 0);
  expect_no_line "adversarial zero line fill"
    (Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor (direct_data "ok\n");
  expect_line "line refill after malformed and stale scratch" "ok"
    (Direct_channel.input_line channel);

  let immediate_exception = Injected (ref "line immediate read") in
  Direct_descriptor.add_read_action descriptor
    (fun _ _ _ -> raise immediate_exception);
  expect_physical_exception "immediate line read exception"
    immediate_exception (fun () -> Direct_channel.input_line channel);
  Direct_descriptor.add_read_action descriptor (direct_data "i\n");
  expect_line "line after immediate exception" "i"
    (Direct_channel.input_line channel);
  ignore (expect_ok "line lower error close" (Direct_channel.close channel));

  let tie_error_descriptor = Direct_descriptor.create () in
  let tie_error_channel = open_direct "tie lower error channel"
      tie_error_descriptor in
  Direct_descriptor.set_read_actions tie_error_descriptor
    [ direct_data "abc";
      direct_error Plan9_types.Interrupted "tie lookahead error" ];
  expect_error "tie lookahead lower error" input_line_operation
    Plan9_types.Interrupted "tie lookahead error"
    (Direct_channel.input_line ~max_bytes:3 tie_error_channel);
  Direct_descriptor.add_read_action tie_error_descriptor (direct_data "d\n");
  expect_line "position after tie lookahead error" "d"
    (Direct_channel.input_line tie_error_channel);
  ignore (expect_ok "tie lower error close"
    (Direct_channel.close tie_error_channel));

  List.iter
    (fun malformed_count ->
      let malformed_descriptor = Direct_descriptor.create () in
      let malformed_channel = open_direct "tie malformed channel"
          malformed_descriptor in
      Direct_descriptor.set_read_actions malformed_descriptor
        [ direct_data "abc";
          (fun scratch _ _ ->
            Bytes.fill scratch 0 8 'm';
            Ok malformed_count) ];
      expect_error "tie malformed lookahead" input_line_operation
        Plan9_types.Protocol_error
        (fill_protocol_message 4096 malformed_count)
        (Direct_channel.input_line ~max_bytes:3 malformed_channel);
      Direct_descriptor.add_read_action malformed_descriptor
        (direct_data "n\n");
      expect_line "line after tie malformed lookahead" "n"
        (Direct_channel.input_line malformed_channel);
      ignore (expect_ok "tie malformed close"
        (Direct_channel.close malformed_channel)))
    [-1; 4097];

  let progress_descriptor = Direct_descriptor.create () in
  let progress_channel = open_direct "line progress exception channel"
      progress_descriptor in
  let progress_exception = Injected (ref "line progress read") in
  Direct_descriptor.set_read_actions progress_descriptor
    [direct_data "abc"; (fun _ _ _ -> raise progress_exception)];
  expect_physical_exception "line exception after committed segment"
    progress_exception (fun () ->
      Direct_channel.input_line ~max_bytes:10 progress_channel);
  Direct_descriptor.add_read_action progress_descriptor (direct_data "d\n");
  expect_line "position after committed-segment exception" "d"
    (Direct_channel.input_line progress_channel);
  ignore (expect_ok "line progress exception close"
    (Direct_channel.close progress_channel));

  let lookahead_descriptor = Direct_descriptor.create () in
  let lookahead_channel = open_direct "line lookahead exception channel"
      lookahead_descriptor in
  let lookahead_exception = Injected (ref "line lookahead read") in
  Direct_descriptor.set_read_actions lookahead_descriptor
    [direct_data "abc"; (fun _ _ _ -> raise lookahead_exception)];
  expect_physical_exception "line exact-limit lookahead exception"
    lookahead_exception (fun () ->
      Direct_channel.input_line ~max_bytes:3 lookahead_channel);
  Direct_descriptor.add_read_action lookahead_descriptor (direct_data "\n");
  expect_line "position after lookahead exception" ""
    (Direct_channel.input_line lookahead_channel);
  ignore (expect_ok "line lookahead exception close"
    (Direct_channel.close lookahead_channel))

let test_default_line_bound () =
  let eof_descriptor = Direct_descriptor.create () in
  let eof_channel = open_direct "default EOF channel" eof_descriptor in
  Direct_descriptor.add_read_action eof_descriptor (fun _ _ _ -> Ok 0);
  expect_no_line "omitted-bound immediate EOF"
    (Direct_channel.input_line eof_channel);
  check "omitted-bound EOF lower-call count" (eof_descriptor.read_calls = 1);
  ignore (expect_ok "default EOF close" (Direct_channel.close eof_channel));

  let exact_descriptor = Direct_descriptor.create () in
  let exact_channel = open_direct "default exact channel" exact_descriptor in
  let exact_trace = install_generated_line exact_descriptor
      ~body_length:1_048_576 ~body_byte:'a' ~terminated:true
      ~max_chunk:4096 in
  let exact = expect_some_line "default exact line"
      (Direct_channel.input_line exact_channel) in
  check_repeated_string "default exact bytes" 'a' 1_048_576 exact;
  let exact_counts = List.rev !exact_trace in
  check "default exact generated call count"
    (List.length exact_counts = 257
     && exact_descriptor.read_calls = 257);
  List.iteri
    (fun index count ->
      if index < 256 then
        check "default exact full-fill trace" (count = 4096)
      else
        check "default exact newline lookahead trace" (count = 1))
    exact_counts;
  ignore (expect_ok "default exact close"
    (Direct_channel.close exact_channel));

  let excess_descriptor = Direct_descriptor.create () in
  let excess_channel = open_direct "default excess channel"
      excess_descriptor in
  let excess_trace = install_generated_line excess_descriptor
      ~body_length:1_048_577 ~body_byte:'b' ~terminated:true
      ~max_chunk:4096 in
  expect_line_limit "default omitted-bound excess" 1_048_576
    (Direct_channel.input_line excess_channel);
  let excess_counts = List.rev !excess_trace in
  check "default excess generated call count"
    (List.length excess_counts = 257
     && excess_descriptor.read_calls = 257);
  List.iteri
    (fun index count ->
      if index < 256 then
        check "default excess full-fill trace" (count = 4096)
      else
        check "default excess boundary-fill trace" (count = 2))
    excess_counts;
  let first_excess = Bytes.make 1 '\165' in
  check "default excess retained byte count"
    (expect_ok "default excess retained byte"
       (Direct_channel.input excess_channel first_excess ~pos:0 ~len:1) = 1);
  check "default excess retained byte value" (Bytes.get first_excess 0 = 'b');
  check "default excess retained byte refilled"
    (excess_descriptor.read_calls = 257);
  ignore (expect_ok "default excess close"
    (Direct_channel.close excess_channel))

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
  test_line_bounds_and_lifecycle ();
  test_line_semantics_and_boundaries ();
  test_line_limits_and_positions ();
  test_line_errors_and_exceptions ();
  test_default_line_bound ();
  test_gc_and_buffer_recovery ();
  print_endline
    "in_channel_lifecycle_test: ok (linear generated line schedules; conditional allocation/POPTRAP schedules require static audit)"
