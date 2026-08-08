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
  prerr_endline ("in_channel_io_test: " ^ message);
  exit 1

let check label condition =
  if not condition then fail label

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
        fail (label ^ " returned the wrong operation");
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

let write_chunk descriptor source position length =
  let count =
    expect_ok "native channel write"
      (Plan9_fd.write descriptor source ~pos:position ~len:length)
  in
  if count <> length then
    fail
      ("native channel write returned " ^ string_of_int count
       ^ " for " ^ string_of_int length ^ " bytes")

let close_fd label descriptor =
  ignore (expect_ok label (Plan9_fd.close descriptor))

let close_channel label channel =
  ignore (expect_ok label (Plan9_in_channel.close channel))

let test_binary_buffer_boundaries () =
  let payload_length = 4096 + 7 + 123 in
  let payload =
    Bytes.init payload_length (fun index ->
      if index = 0 || index = 4095 || index = 4096 || index = 4102 then '\000'
      else Char.chr (33 + (index mod 90)))
  in
  let reader, writer = expect_ok "binary channel pipe" (Plan9_fd.pipe ()) in
  write_chunk writer payload 0 4096;
  write_chunk writer payload 4096 7;
  write_chunk writer payload 4103 123;
  close_fd "binary writer close" writer;
  let channel = expect_ok "binary channel attach"
      (Plan9_in_channel.of_fd reader) in
  let received = Bytes.make payload_length '\165' in
  let first = expect_ok "first small channel input"
      (Plan9_in_channel.input channel received ~pos:0 ~len:3) in
  check "first small channel input count" (first = 3);
  let second = expect_ok "buffered surplus channel input"
      (Plan9_in_channel.input channel received ~pos:3
         ~len:(payload_length - 3)) in
  check "buffered surplus did not preserve first fill" (second = 4093);
  let rec drain position request_index =
    if position = payload_length then ()
    else
      let request_sizes = [| 5000; 1; 19; 257; 4097 |] in
      let requested = request_sizes.(request_index mod Array.length request_sizes) in
      let remaining = payload_length - position in
      let length = if requested < remaining then requested else remaining in
      let count = expect_ok "uneven channel input"
          (Plan9_in_channel.input channel received ~pos:position ~len:length)
      in
      if count <= 0 || count > length then
        fail ("uneven channel input returned " ^ string_of_int count);
      drain (position + count) (request_index + 1)
  in
  drain (first + second) 0;
  expect_bytes "binary channel payload" payload received;
  let eof_destination = Bytes.make 1 '\165' in
  check "EOF after all queued bytes"
    (expect_ok "channel EOF"
       (Plan9_in_channel.input channel eof_destination ~pos:0 ~len:1) = 0);
  close_channel "binary channel close" channel;
  let repeated_one = Plan9_in_channel.close channel in
  let repeated_two = Plan9_in_channel.close channel in
  check "native repeated channel close identity"
    (repeated_one == repeated_two);
  ignore (expect_ok "native repeated channel close" repeated_one)

let test_zero_alias_close_and_gc () =
  let reader, writer = expect_ok "zero channel pipe" (Plan9_fd.pipe ()) in
  let alias = reader in
  let channel = expect_ok "zero channel attach"
      (Plan9_in_channel.of_fd reader) in
  let byte = Bytes.of_string "z" in
  write_chunk writer byte 0 1;
  close_fd "zero writer close" writer;
  let destination = Bytes.make 1 '\165' in
  let zero_one =
    Plan9_in_channel.input channel destination ~pos:1 ~len:0
  in
  let zero_two =
    Plan9_in_channel.input channel destination ~pos:1 ~len:0
  in
  check "native zero result identity" (zero_one == zero_two);
  check "native zero input count" (expect_ok "native zero input" zero_one = 0);
  check "queued byte consumed by zero input"
    (expect_ok "queued byte after zero"
       (Plan9_in_channel.input channel destination ~pos:0 ~len:1) = 1);
  expect_bytes "queued byte after zero" byte destination;
  check "zero channel EOF"
    (expect_ok "zero channel EOF"
       (Plan9_in_channel.input channel destination ~pos:0 ~len:1) = 0);

  expect_error "attached alias read" "Plan9.Fd.read"
    Plan9_types.Invalid_argument "descriptor ownership has been transferred"
    (Plan9_fd.read alias destination ~pos:0 ~len:1);
  expect_error "attached alias close" "Plan9.Fd.close"
    Plan9_types.Invalid_argument "descriptor ownership has been transferred"
    (Plan9_fd.close alias);
  expect_error "attached alias prepare" "Plan9.Fd.Private.prepare_attach"
    Plan9_types.Invalid_argument "descriptor is not open and detached"
    (Plan9_fd.Private.prepare_attach alias);

  force_gc ();
  close_channel "zero channel close" channel;
  force_gc ();
  ignore (expect_ok "zero channel repeated close"
    (Plan9_in_channel.close channel));
  expect_error "input after native channel close" "Plan9.In_channel.input"
    Plan9_types.Invalid_argument "input channel is closed"
    (Plan9_in_channel.input channel destination ~pos:0 ~len:0)

let test_repeated_cycles () =
  for iteration = 1 to 256 do
    let reader, writer = expect_ok "repeated channel pipe"
        (Plan9_fd.pipe ()) in
    let alias = reader in
    let channel = expect_ok "repeated channel attach"
        (Plan9_in_channel.of_fd reader) in
    let payload = Bytes.of_string "cycle\000payload" in
    write_chunk writer payload 0 (Bytes.length payload);
    close_fd "repeated writer close" writer;
    if iteration mod 16 = 0 then force_gc ();
    let received = Bytes.make (Bytes.length payload) '\165' in
    let rec read_all position =
      if position = Bytes.length received then ()
      else
        let count = expect_ok "repeated channel input"
            (Plan9_in_channel.input channel received ~pos:position
               ~len:(Bytes.length received - position))
        in
        if count <= 0 then fail "repeated channel reached early EOF";
        read_all (position + count)
    in
    read_all 0;
    expect_bytes "repeated channel payload" payload received;
    check "repeated channel EOF"
      (expect_ok "repeated channel EOF"
         (Plan9_in_channel.input channel received ~pos:0 ~len:1) = 0);
    expect_error "repeated alias remains revoked" "Plan9.Fd.close"
      Plan9_types.Invalid_argument "descriptor ownership has been transferred"
      (Plan9_fd.close alias);
    close_channel "repeated channel close" channel;
    close_channel "repeated channel idempotent close" channel
  done

let () =
  expect_clean_descriptors "binary channel buffer boundaries"
    test_binary_buffer_boundaries;
  expect_clean_descriptors "zero alias close and GC"
    test_zero_alias_close_and_gc;
  expect_clean_descriptors "repeated channel cycles" test_repeated_cycles;
  print_endline
    "in_channel_io_test: ok (256 repeated native channel lifecycles)"
