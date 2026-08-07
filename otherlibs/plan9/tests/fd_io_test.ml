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
  prerr_endline ("fd_io_test: " ^ message);
  exit 1

let check label condition =
  if not condition then fail label

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      fail
        (label ^ " failed: " ^ error.Plan9.operation ^ ": "
         ^ error.Plan9.message)

let expect_error label operation kind message = function
  | Ok _ -> fail (label ^ " unexpectedly succeeded")
  | Error error ->
      if error.Plan9.operation <> operation then
        fail (label ^ " returned the wrong operation");
      if error.Plan9.kind <> kind then
        fail (label ^ " returned the wrong kind");
      if error.Plan9.message <> message then
        fail
          (label ^ " returned message " ^ String.escaped error.Plan9.message)

let expect_internal_ok label = function
  | Ok value -> value
  | Error error ->
      fail
        (label ^ " failed: " ^ error.Plan9_types.operation ^ ": "
         ^ error.Plan9_types.message)

let expect_internal_error label operation kind message = function
  | Ok _ -> fail (label ^ " unexpectedly succeeded")
  | Error error ->
      if error.Plan9_types.operation <> operation then
        fail (label ^ " returned the wrong operation");
      if error.Plan9_types.kind <> kind then
        fail (label ^ " returned the wrong kind");
      if error.Plan9_types.message <> message then
        fail
          (label ^ " returned message "
           ^ String.escaped error.Plan9_types.message)

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

let force_gc () =
  Gc.minor ();
  Gc.full_major ();
  Gc.compact ()

let expect_bytes label expected actual =
  if not (Bytes.equal expected actual) then
    fail
      (label ^ ": expected " ^ String.escaped (Bytes.to_string expected)
       ^ " but got " ^ String.escaped (Bytes.to_string actual))

let write_all descriptor source =
  let rec loop position progress =
    if position = Bytes.length source then List.rev progress
    else
      let remaining = Bytes.length source - position in
      match Plan9.Fd.write descriptor source ~pos:position ~len:remaining with
      | Ok count when count > 0 && count <= remaining ->
          loop (position + count) (count :: progress)
      | Ok count ->
          fail ("write_all returned invalid progress " ^ string_of_int count)
      | Error error ->
          fail
            ("write_all failed: " ^ error.Plan9.operation ^ ": "
             ^ error.Plan9.message)
  in
  loop 0 []

let read_exact descriptor destination =
  let rec loop position progress =
    if position = Bytes.length destination then List.rev progress
    else
      let remaining = Bytes.length destination - position in
      match
        Plan9.Fd.read descriptor destination ~pos:position ~len:remaining
      with
      | Ok count when count > 0 && count <= remaining ->
          loop (position + count) (count :: progress)
      | Ok 0 -> fail "read_exact reached EOF before the requested payload"
      | Ok count ->
          fail ("read_exact returned invalid progress " ^ string_of_int count)
      | Error error ->
          fail
            ("read_exact failed: " ^ error.Plan9.operation ^ ": "
             ^ error.Plan9.message)
  in
  loop 0 []

let close_pair left right =
  ignore (expect_ok "close left peer" (Plan9.Fd.close left));
  ignore (expect_ok "close right peer" (Plan9.Fd.close right))

let test_bidirectional_binary_peers () =
  let left, right = expect_ok "bidirectional pipe" (Plan9.Fd.pipe ()) in
  let left_payload = Bytes.of_string "left\000peer" in
  let right_payload = Bytes.of_string "right\000peer" in
  check "left-to-right write"
    (expect_ok "left-to-right write"
       (Plan9.Fd.write left left_payload ~pos:0
          ~len:(Bytes.length left_payload)) = Bytes.length left_payload);
  let left_received = Bytes.make (Bytes.length left_payload) '\165' in
  check "left-to-right read"
    (expect_ok "left-to-right read"
       (Plan9.Fd.read right left_received ~pos:0
          ~len:(Bytes.length left_received)) = Bytes.length left_payload);
  expect_bytes "left-to-right binary payload" left_payload left_received;
  check "right-to-left write"
    (expect_ok "right-to-left write"
       (Plan9.Fd.write right right_payload ~pos:0
          ~len:(Bytes.length right_payload)) = Bytes.length right_payload);
  let right_received = Bytes.make (Bytes.length right_payload) '\165' in
  check "right-to-left read"
    (expect_ok "right-to-left read"
       (Plan9.Fd.read left right_received ~pos:0
          ~len:(Bytes.length right_received)) = Bytes.length right_payload);
  expect_bytes "right-to-left binary payload" right_payload right_received;
  close_pair left right

let test_large_caller_loop_and_eof () =
  let transfer_size = (2 * 4096) + 3 in
  let payload = Bytes.init transfer_size (fun index ->
    if index = 4095 || index = 4096 || index = 8192 then '\000'
    else Char.chr (33 + (index mod 90)))
  in
  let reader, writer = expect_ok "large pipe" (Plan9.Fd.pipe ()) in
  let write_progress = write_all writer payload in
  check "large write split"
    (write_progress = [4096; 4096; 3]);
  ignore (expect_ok "large writer close" (Plan9.Fd.close writer));
  let received = Bytes.make transfer_size '\165' in
  let read_progress = read_exact reader received in
  check "large read split" (read_progress = [4096; 4096; 3]);
  expect_bytes "large binary round trip" payload received;
  check "EOF after queued payload"
    (expect_ok "EOF after queued payload"
       (Plan9.Fd.read reader received ~pos:0 ~len:1) = 0);
  ignore (expect_ok "large reader close" (Plan9.Fd.close reader))

let test_write_boundary_and_zero_length () =
  let reader, writer = expect_ok "boundary pipe" (Plan9.Fd.pipe ()) in
  let payload = Bytes.of_string "abc" in
  check "boundary write"
    (expect_ok "boundary write"
       (Plan9.Fd.write writer payload ~pos:0 ~len:3) = 3);
  let destination = Bytes.make 16 '\165' in
  check "positive short read boundary"
    (expect_ok "positive short read boundary"
       (Plan9.Fd.read reader destination ~pos:2 ~len:10) = 3);
  let expected_destination = Bytes.make 16 '\165' in
  Bytes.blit payload 0 expected_destination 2 3;
  expect_bytes "boundary destination" expected_destination destination;
  ignore (expect_ok "boundary writer close" (Plan9.Fd.close writer));
  check "boundary EOF"
    (expect_ok "boundary EOF"
       (Plan9.Fd.read reader destination ~pos:0 ~len:1) = 0);
  ignore (expect_ok "boundary reader close" (Plan9.Fd.close reader));

  let reader, writer = expect_ok "zero pipe" (Plan9.Fd.pipe ()) in
  let one = Bytes.of_string "z" in
  check "zero write"
    (expect_ok "zero write"
       (Plan9.Fd.write writer one ~pos:1 ~len:0) = 0);
  check "positive write after zero"
    (expect_ok "positive write after zero"
       (Plan9.Fd.write writer one ~pos:0 ~len:1) = 1);
  let one_destination = Bytes.make 1 '\165' in
  check "zero read"
    (expect_ok "zero read"
       (Plan9.Fd.read reader one_destination ~pos:1 ~len:0) = 0);
  check "queued byte survived zero read"
    (expect_ok "queued byte survived zero read"
       (Plan9.Fd.read reader one_destination ~pos:0 ~len:1) = 1);
  expect_bytes "queued byte after zero read" one one_destination;
  close_pair reader writer

let test_alias_and_attachment_lifecycle () =
  let left, right = expect_ok "alias pipe" (Plan9.Fd.pipe ()) in
  let alias = left in
  ignore (expect_ok "alias close" (Plan9.Fd.close alias));
  ignore (expect_ok "alias repeated close" (Plan9.Fd.close left));
  let buffer = Bytes.make 1 'x' in
  expect_error "alias read after close" "Plan9.Fd.read"
    Plan9.Invalid_argument "descriptor is closed"
    (Plan9.Fd.read left buffer ~pos:0 ~len:1);
  expect_error "alias write after close" "Plan9.Fd.write"
    Plan9.Invalid_argument "descriptor is closed"
    (Plan9.Fd.write alias buffer ~pos:0 ~len:1);
  ignore (expect_ok "alias companion close" (Plan9.Fd.close right));

  let owner_cell, peer =
    expect_internal_ok "attachment pipe" (Plan9_fd.pipe ())
  in
  let alias = owner_cell in
  let token =
    expect_internal_ok "attachment prepare"
      (Plan9_fd.Private.prepare_attach owner_cell)
  in
  check "attachment commit" (Plan9_fd.Private.commit_attach token);
  expect_internal_error "attached public read" "Plan9.Fd.read"
    Plan9_types.Invalid_argument "descriptor ownership has been transferred"
    (Plan9_fd.read alias buffer ~pos:0 ~len:1);
  let payload = Bytes.of_string "native\000owner" in
  check "attachment owner write"
    (expect_internal_ok "attachment owner write"
       (Plan9_fd.Private.write token payload ~pos:0
          ~len:(Bytes.length payload)) = Bytes.length payload);
  let received = Bytes.make (Bytes.length payload) '\165' in
  check "attachment peer read"
    (expect_internal_ok "attachment peer read"
       (Plan9_fd.read peer received ~pos:0 ~len:(Bytes.length received))
     = Bytes.length payload);
  expect_bytes "attachment binary payload" payload received;
  force_gc ();
  ignore (expect_internal_ok "attachment owner close"
    (Plan9_fd.Private.close token));
  ignore (expect_internal_ok "attachment owner repeated close"
    (Plan9_fd.Private.close token));
  expect_internal_error "owner read after close" "Plan9.Fd.read"
    Plan9_types.Invalid_argument "descriptor is closed"
    (Plan9_fd.Private.read token buffer ~pos:0 ~len:1);
  ignore
    (expect_internal_ok "attachment peer close" (Plan9_fd.close peer))

let test_repeated_gc_cycles () =
  for iteration = 1 to 256 do
    let left, right = expect_ok "repeated pipe" (Plan9.Fd.pipe ()) in
    let payload = Bytes.of_string "cycle\000payload" in
    let alias = left in
    if iteration mod 16 = 0 then force_gc ();
    check "repeated write"
      (expect_ok "repeated write"
         (Plan9.Fd.write right payload ~pos:0 ~len:(Bytes.length payload))
       = Bytes.length payload);
    let received = Bytes.make (Bytes.length payload) '\165' in
    check "repeated read"
      (expect_ok "repeated read"
         (Plan9.Fd.read alias received ~pos:0 ~len:(Bytes.length received))
       = Bytes.length payload);
    expect_bytes "repeated payload" payload received;
    ignore (expect_ok "repeated alias close" (Plan9.Fd.close alias));
    ignore (expect_ok "repeated alias idempotent close" (Plan9.Fd.close left));
    ignore (expect_ok "repeated companion close" (Plan9.Fd.close right))
  done

let () =
  expect_clean_descriptors "bidirectional binary peers"
    test_bidirectional_binary_peers;
  expect_clean_descriptors "large caller loop and EOF"
    test_large_caller_loop_and_eof;
  expect_clean_descriptors "write boundary and zero length"
    test_write_boundary_and_zero_length;
  expect_clean_descriptors "alias and attachment lifecycle"
    test_alias_and_attachment_lifecycle;
  expect_clean_descriptors "repeated GC cycles" test_repeated_gc_cycles;
  print_endline
    "fd_io_test: ok (256 repeated native descriptor I/O lifecycles)"
