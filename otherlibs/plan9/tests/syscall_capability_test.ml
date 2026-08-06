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

type capability

type native_failure = {
  native_kind : int;
  native_message : string;
}

external private_pipe :
  unit -> ((capability * capability), native_failure) result
  = "caml_plan9_syscall_pipe"

external private_close :
  capability -> (unit, native_failure) result
  = "caml_plan9_syscall_close"

external private_read :
  capability -> int -> ((bytes * int), native_failure) result
  = "caml_plan9_syscall_read"

external private_write :
  capability -> bytes -> int -> int -> (int, native_failure) result
  = "caml_plan9_syscall_write"

external private_negative_read_probe :
  unit -> native_failure
  = "caml_plan9_syscall_negative_read_probe"

let repeat_count = 256
let staging_capacity = 4096
let expected_probe_message = "fd out of range or not open"

let fail message =
  prerr_endline ("syscall_capability_test: " ^ message);
  exit 1

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

let expect_invalid_result label = function
  | Error { native_kind = 0; _ } -> ()
  | Error failure ->
      fail
        (label ^ " returned native kind "
         ^ string_of_int failure.native_kind)
  | Ok _ -> fail (label ^ " unexpectedly succeeded")

let expect_invalid_failure label failure =
  if failure.native_kind <> 0 then
    fail
      (label ^ " returned native kind "
       ^ string_of_int failure.native_kind)

let forged_pipe value = private_pipe (Obj.magic value)
let forged_close value = private_close (Obj.magic value)
let forged_read_capability value length =
  private_read (Obj.magic value) length
let forged_read_length capability value =
  private_read capability (Obj.magic value)
let forged_write_capability value source position length =
  private_write (Obj.magic value) source position length
let forged_write_source capability value position length =
  private_write capability (Obj.magic value) position length
let forged_write_position capability source value length =
  private_write capability source (Obj.magic value) length
let forged_write_length capability source position value =
  private_write capability source position (Obj.magic value)

let forged_probe value =
  private_negative_read_probe (Obj.magic value)

let expect_close_ok label capability =
  match private_close capability with
  | Ok () -> ()
  | Error failure ->
      fail
        (label ^ " failed with kind " ^ string_of_int failure.native_kind
         ^ ": " ^ failure.native_message)

let expect_pipe_ok label =
  match private_pipe () with
  | Error failure ->
      fail
        (label ^ " failed with kind " ^ string_of_int failure.native_kind
         ^ ": " ^ failure.native_message)
  | Ok pair -> pair

let expect_read_ok label capability length expected_count =
  match private_read capability length with
  | Error failure ->
      fail
        (label ^ " failed with kind " ^ string_of_int failure.native_kind
         ^ ": " ^ failure.native_message)
  | Ok (buffer, count) ->
      if Bytes.length buffer <> length then
        fail
          (label ^ " returned buffer length "
           ^ string_of_int (Bytes.length buffer));
      if count <> expected_count then
        fail
          (label ^ " returned count " ^ string_of_int count
           ^ " instead of " ^ string_of_int expected_count);
      buffer

let expect_write_ok label capability source position length expected_count =
  match private_write capability source position length with
  | Error failure ->
      fail
        (label ^ " failed with kind " ^ string_of_int failure.native_kind
         ^ ": " ^ failure.native_message)
  | Ok count ->
      if count <> expected_count then
        fail
          (label ^ " returned count " ^ string_of_int count
           ^ " instead of " ^ string_of_int expected_count)

let expect_bytes label expected actual count =
  if count > Bytes.length expected || count > Bytes.length actual then
    fail (label ^ " received an invalid comparison count");
  for index = 0 to count - 1 do
    if Bytes.get expected index <> Bytes.get actual index then
      fail (label ^ " differed at byte " ^ string_of_int index)
  done

let expect_zero_tail label buffer first =
  for index = first to Bytes.length buffer - 1 do
    if Bytes.get buffer index <> '\000' then
      fail (label ^ " had a nonzero tail byte at " ^ string_of_int index)
  done

type exact_write_failure =
  | Exact_native_failure of native_failure
  | Exact_short_write of { requested : int; written : int }

let exact_write_chunks writer source chunks =
  let rec loop = function
    | [] -> Ok ()
    | (position, length) :: remaining ->
        match writer source position length with
        | Error failure -> Error (Exact_native_failure failure)
        | Ok count when count = length -> loop remaining
        | Ok count ->
            Error (Exact_short_write { requested = length; written = count })
  in
  loop chunks

let expect_probe_error label () =
  let failure = private_negative_read_probe () in
  if failure.native_kind <> 1 then
    fail
      (label ^ " returned native kind "
       ^ string_of_int failure.native_kind);
  if failure.native_message <> expected_probe_message then
    fail
      (label ^ " returned message " ^ String.escaped failure.native_message)

let test_hostile_inputs () =
  let non_unit_values =
    [
      "non-unit immediate", Obj.repr 17;
      "non-unit block", Obj.repr "not unit";
    ]
  in
  List.iter
    (fun (label, value) ->
      expect_invalid_result ("pipe " ^ label) (forged_pipe value);
      expect_invalid_failure ("probe " ^ label) (forged_probe value))
    non_unit_values;

  let foreign_int64 = Obj.repr 0x1020304050607080L in
  let foreign_bigarray =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout 1
  in
  let close_values =
    [
      "raw integer", Obj.repr 37;
      "other immediate", Obj.repr false;
      "ordinary block", Obj.repr ("ordinary", 1);
      "wrong-tag block", Obj.repr "wrong tag";
      "foreign exact-size Int64 custom block", foreign_int64;
      "foreign wrong-size Bigarray custom block", Obj.repr foreign_bigarray;
    ]
  in
  List.iter
    (fun (label, value) ->
      expect_invalid_result ("close " ^ label) (forged_close value))
    close_values;

  let reader, writer = expect_pipe_ok "hostile read/write pipe" in
  let source = Bytes.of_string "source" in
  List.iter
    (fun (label, value) ->
      expect_invalid_result
        ("read capability " ^ label)
        (forged_read_capability value 0);
      expect_invalid_result
        ("write capability " ^ label)
        (forged_write_capability value source 0 0))
    close_values;
  let foreign_values =
    [
      "Int64 custom block", foreign_int64;
      "Bigarray custom block", Obj.repr foreign_bigarray;
    ]
  in
  List.iter
    (fun (label, value) ->
      expect_invalid_result
        ("read length " ^ label)
        (forged_read_length reader value);
      expect_invalid_result
        ("write source " ^ label)
        (forged_write_source writer value 0 0);
      expect_invalid_result
        ("write position " ^ label)
        (forged_write_position writer source value 0);
      expect_invalid_result
        ("write length " ^ label)
        (forged_write_length writer source 0 value))
    foreign_values;
  let malformed_sources =
    [
      "raw integer", Obj.repr 37;
      "ordinary block", Obj.repr ("ordinary", 1);
    ]
  in
  List.iter
    (fun (label, value) ->
      expect_invalid_result
        ("write source " ^ label)
        (forged_write_source writer value 0 0))
    malformed_sources;
  expect_close_ok "hostile close reader" reader;
  expect_close_ok "hostile close writer" writer

let test_alias_and_idempotent_close () =
  let left, right = expect_pipe_ok "alias pipe" in
  if Obj.is_int (Obj.repr left) || Obj.is_int (Obj.repr right) then
    fail "pipe exposed an immediate descriptor instead of capabilities";
  let left_alias = left in
  expect_close_ok "close left" left;
  expect_close_ok "close left alias" left_alias;
  expect_close_ok "repeat close left" left;
  expect_close_ok "close right" right;
  expect_close_ok "repeat close right" right

let test_numeric_boundaries () =
  let reader, writer = expect_pipe_ok "numeric boundary pipe" in
  List.iter
    (fun length ->
      expect_invalid_result
        ("read length " ^ string_of_int length)
        (private_read reader length))
    [-1; staging_capacity + 1; max_int];

  let source_length = staging_capacity + 1 in
  let source =
    Bytes.init source_length (fun index -> Char.chr ((index * 37 + 11) land 255))
  in
  let invalid_ranges =
    [
      -1, 0;
      0, -1;
      source_length + 1, 0;
      source_length, 1;
      0, staging_capacity + 1;
      max_int, 1;
      1, max_int;
    ]
  in
  List.iter
    (fun (position, length) ->
      expect_invalid_result
        ("write range (" ^ string_of_int position ^ ","
         ^ string_of_int length ^ ")")
        (private_write writer source position length))
    invalid_ranges;
  ignore (expect_read_ok "zero-length boundary read" reader 0 0);
  expect_write_ok "source-end zero write" writer source source_length 0 0;
  expect_write_ok "capacity write" writer source 1 staging_capacity
    staging_capacity;
  let actual =
    expect_read_ok "capacity read" reader staging_capacity staging_capacity
  in
  for index = 0 to staging_capacity - 1 do
    if Bytes.get actual index <> Bytes.get source (index + 1) then
      fail ("capacity slice differed at byte " ^ string_of_int index)
  done;
  expect_close_ok "numeric close reader" reader;
  expect_close_ok "numeric close writer" writer

let test_false_zero_aliases () =
  let reader, writer = expect_pipe_ok "false-zero pipe" in
  let false_zero : int = Obj.magic false in
  let source = Bytes.of_string "z" in
  expect_write_ok "false zero-length write" writer source false_zero
    false_zero 0;
  expect_write_ok "false zero-position write" writer source false_zero 1 1;
  ignore (expect_read_ok "false zero-length read" reader false_zero 0);
  let actual = expect_read_ok "read after false-zero operations" reader 1 1 in
  if Bytes.get actual 0 <> 'z' then
    fail "false-zero operations changed the following payload";
  expect_close_ok "false-zero close reader" reader;
  expect_close_ok "false-zero close writer" writer

let test_closed_io () =
  let reader, writer = expect_pipe_ok "closed I/O pipe" in
  expect_close_ok "closed I/O close reader" reader;
  expect_close_ok "closed I/O close writer" writer;
  expect_invalid_result "read from closed capability" (private_read reader 1);
  expect_invalid_result "write to closed capability"
    (private_write writer (Bytes.of_string "x") 0 1)

let test_string_source () =
  let reader, writer = expect_pipe_ok "string source pipe" in
  let source = "string\000source\255" in
  let preserved = Bytes.to_string (Bytes.of_string source) in
  let source_as_bytes : bytes = Obj.magic source in
  expect_write_ok "string source write" writer source_as_bytes 0
    (String.length source) (String.length source);
  let actual =
    expect_read_ok "string source read" reader (String.length source)
      (String.length source)
  in
  if Bytes.to_string actual <> source then
    fail "ordinary string source did not round-trip";
  if source <> preserved then fail "ordinary string source was modified";
  expect_close_ok "string source close reader" reader;
  expect_close_ok "string source close writer" writer

let test_short_read_and_eof () =
  let reader, writer = expect_pipe_ok "short read pipe" in
  let payload = Bytes.of_string "s\000r" in
  expect_write_ok "short read write" writer payload 0 3 3;
  let actual = expect_read_ok "positive short read" reader 16 3 in
  expect_bytes "positive short read prefix" payload actual 3;
  expect_zero_tail "positive short read" actual 3;
  expect_close_ok "short read close writer" writer;
  let eof_buffer = expect_read_ok "EOF after buffered data" reader 1 0 in
  expect_zero_tail "EOF after buffered data" eof_buffer 0;
  expect_close_ok "short read close reader" reader;

  let empty_reader, empty_writer = expect_pipe_ok "empty EOF pipe" in
  expect_close_ok "empty EOF close writer" empty_writer;
  let empty = expect_read_ok "empty payload EOF" empty_reader 16 0 in
  expect_zero_tail "empty payload EOF" empty 0;
  expect_close_ok "empty EOF close reader" empty_reader

let test_exact_write_short_policy () =
  let calls = ref 0 in
  let fake_writer _source _position requested =
    incr calls;
    Ok (requested - 1)
  in
  let source = Bytes.of_string "abcdefgh" in
  match exact_write_chunks fake_writer source [0, 4; 4, 4] with
  | Error (Exact_short_write { requested = 4; written = 3 }) ->
      if !calls <> 1 then
        fail "exact-write helper continued after a positive short write"
  | Error (Exact_short_write _) ->
      fail "exact-write helper reported the wrong short-write count"
  | Error (Exact_native_failure _) ->
      fail "exact-write helper misreported a synthesized short write"
  | Ok () -> fail "exact-write helper accepted a positive short write"

let test_multichunk_round_trip () =
  let total_length = (2 * staging_capacity) + 3 in
  let payload =
    Bytes.init total_length
      (fun index -> Char.chr ((index * 29 + 7) land 255))
  in
  Bytes.set payload (staging_capacity - 1) '\000';
  Bytes.set payload staging_capacity '\000';
  let expected_writes =
    [0, staging_capacity; staging_capacity, staging_capacity;
     2 * staging_capacity, 3]
  in
  let expected_reads = [staging_capacity; staging_capacity; 3] in
  let reader, writer = expect_pipe_ok "multi-chunk pipe" in
  let recorded_writes = ref [] in
  let native_writer source position length =
    recorded_writes := (position, length) :: !recorded_writes;
    private_write writer source position length
  in
  (match exact_write_chunks native_writer payload expected_writes with
   | Ok () -> ()
   | Error (Exact_native_failure failure) ->
       fail
         ("multi-chunk write failed with kind "
          ^ string_of_int failure.native_kind ^ ": "
          ^ failure.native_message)
   | Error (Exact_short_write { requested; written }) ->
       fail
         ("multi-chunk native short write: requested "
          ^ string_of_int requested ^ " wrote " ^ string_of_int written));
  if List.rev !recorded_writes <> expected_writes then
    fail "multi-chunk write calls differed from the staging split";
  expect_close_ok "multi-chunk close writer" writer;

  let output = Bytes.make total_length '\000' in
  let recorded_reads = ref [] in
  let rec read_chunks output_position = function
    | [] -> output_position
    | requested :: remaining ->
        recorded_reads := requested :: !recorded_reads;
        let buffer =
          expect_read_ok "multi-chunk read" reader requested requested
        in
        Bytes.blit buffer 0 output output_position requested;
        read_chunks (output_position + requested) remaining
  in
  let completed = read_chunks 0 expected_reads in
  if completed <> total_length then fail "multi-chunk read did not complete";
  if List.rev !recorded_reads <> expected_reads then
    fail "multi-chunk read requests differed from the staging split";
  if output <> payload then fail "multi-chunk payload differed";
  let eof_buffer = expect_read_ok "multi-chunk EOF" reader 1 0 in
  expect_zero_tail "multi-chunk EOF" eof_buffer 0;
  expect_close_ok "multi-chunk close reader" reader

let test_gc_survival () =
  let left, right = expect_pipe_ok "GC pipe" in
  let left_alias = left in
  let right_alias = right in
  let payload = Bytes.of_string "compact\000aliases" in
  let payload_alias = payload in
  Gc.minor ();
  Gc.full_major ();
  Gc.compact ();
  expect_write_ok "write through compacted aliases" right_alias payload_alias 0
    (Bytes.length payload_alias) (Bytes.length payload_alias);
  let actual =
    expect_read_ok "read through compacted alias" left_alias
      (Bytes.length payload) (Bytes.length payload)
  in
  expect_bytes "compacted alias payload" payload actual (Bytes.length payload);
  expect_close_ok "close compacted left alias" left_alias;
  expect_close_ok "close compacted right alias" right_alias;
  expect_close_ok "repeat close compacted left" left;
  expect_close_ok "repeat close compacted right" right

let test_repeated_lifecycle () =
  let payload = Bytes.of_string "\000\017\127\128\254\255" in
  for iteration = 1 to repeat_count do
    let left, right = expect_pipe_ok "repeated pipe" in
    expect_write_ok "repeated binary write" right payload 0
      (Bytes.length payload) (Bytes.length payload);
    let actual =
      expect_read_ok "repeated binary read" left (Bytes.length payload)
        (Bytes.length payload)
    in
    expect_bytes "repeated binary payload" payload actual
      (Bytes.length payload);
    expect_close_ok "repeated close left" left;
    expect_close_ok "repeated close left idempotent" left;
    expect_close_ok "repeated close right" right;
    let failure = private_negative_read_probe () in
    if failure.native_kind <> 1
       || failure.native_message <> expected_probe_message
    then
      fail
        ("repetition " ^ string_of_int iteration
         ^ " returned unexpected probe failure")
  done

let () =
  expect_clean_descriptors "hostile primitive calls" test_hostile_inputs;
  expect_clean_descriptors "alias and idempotent close"
    test_alias_and_idempotent_close;
  expect_clean_descriptors "numeric I/O boundaries" test_numeric_boundaries;
  expect_clean_descriptors "false immediate zero aliases"
    test_false_zero_aliases;
  expect_clean_descriptors "closed capability I/O" test_closed_io;
  expect_clean_descriptors "ordinary string write source" test_string_source;
  expect_clean_descriptors "short read and EOF" test_short_read_and_eof;
  expect_clean_descriptors "exact-write short policy"
    test_exact_write_short_policy;
  expect_clean_descriptors "multi-chunk round trip"
    test_multichunk_round_trip;
  expect_clean_descriptors "GC-surviving capabilities" test_gc_survival;
  expect_clean_descriptors "negative read probe"
    (expect_probe_error "negative read probe");
  expect_clean_descriptors "repeated capability lifecycle"
    test_repeated_lifecycle;
  print_endline
    ("syscall_capability_test: passed " ^ string_of_int repeat_count
     ^ " repeated binary read/write/close/probe lifecycles")
