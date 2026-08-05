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

external private_negative_read_probe :
  unit -> native_failure
  = "caml_plan9_syscall_negative_read_probe"

let repeat_count = 256
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
    close_values

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

let test_gc_survival () =
  let left, right = expect_pipe_ok "GC pipe" in
  let left_alias = left in
  let right_alias = right in
  Gc.minor ();
  Gc.full_major ();
  Gc.compact ();
  expect_close_ok "close compacted left alias" left_alias;
  expect_close_ok "close compacted right alias" right_alias;
  expect_close_ok "repeat close compacted left" left;
  expect_close_ok "repeat close compacted right" right

let test_repeated_lifecycle () =
  for iteration = 1 to repeat_count do
    let left, right = expect_pipe_ok "repeated pipe" in
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
  expect_clean_descriptors "GC-surviving capabilities" test_gc_survival;
  expect_clean_descriptors "negative read probe"
    (expect_probe_error "negative read probe");
  expect_clean_descriptors "repeated capability lifecycle"
    test_repeated_lifecycle;
  print_endline
    ("syscall_capability_test: passed " ^ string_of_int repeat_count
     ^ " repeated pipe/close/probe lifecycles")
