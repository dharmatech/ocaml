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

external forged_copy_environment :
  Obj.t -> (unit, Plan9_process.native_failure) result
  = "caml_plan9_copy_environment"

external forged_exec :
  Obj.t ->
  Obj.t ->
  (unit, Plan9_process.native_failure) result
  = "caml_plan9_exec"

external forged_spawn :
  Obj.t ->
  Obj.t ->
  Obj.t ->
  Obj.t ->
  Obj.t ->
  (Plan9_process.native_pending, Plan9_process.native_failure) result
  = "caml_plan9_process_spawn"

external forged_pending :
  Obj.t -> Plan9_process.native_pending array
  = "caml_plan9_process_pending"

external forged_acknowledge_pending :
  Obj.t -> bool
  = "caml_plan9_process_acknowledge"

external forged_await :
  Obj.t -> Plan9_process.native_wait_event
  = "caml_plan9_process_await"

external forged_acknowledge_wait :
  Obj.t -> bool
  = "caml_plan9_process_acknowledge_wait"

let fail message =
  prerr_endline ("process_primitive_validation_test: " ^ message);
  exit 1

let expect_invalid label = function
  | Result.Error failure
    when failure.Plan9_process.native_kind = 0 -> ()
  | Result.Error failure ->
      fail
        (label ^ " returned the wrong native kind: "
         ^ string_of_int failure.Plan9_process.native_kind)
  | Ok _ -> fail (label ^ " unexpectedly entered native process work")

let expect_invalid_argument label operation =
  match operation () with
  | exception Invalid_argument _ -> ()
  | exception exn ->
      fail (label ^ " raised " ^ Printexc.to_string exn)
  | _ -> fail (label ^ " accepted a forged primitive value")

let object_string value = Obj.repr value
let object_array value = Obj.repr value
let object_int value = Obj.repr value

let safe_program = object_string "/bin/true"
let safe_argv = object_array [| "/bin/true" |]
let inherited_stdout = object_int 0
let empty_path = object_string ""
let fixed_spawn_flags = 16 lor 4 lor 8192

let test_exact_rfork_policy () =
  let rejected =
    [
      "zero/generic", 0;
      "RFENVG", 2;
      "RFFDG", 4;
      "RFPROC", 16;
      "RFMEM", 32;
      "RFNOWAIT", 64;
      "RFREND", 8192;
      "RFNOMNT", 16384;
      "unknown bit", fixed_spawn_flags lor 1;
      "fixed plus RFMEM", fixed_spawn_flags lor 32;
      "fixed plus RFNOWAIT", fixed_spawn_flags lor 64;
      "fixed plus RFNOMNT", fixed_spawn_flags lor 16384;
      "wide OCaml integer", max_int;
    ]
  in
  List.iter
    (fun (label, flags) ->
      expect_invalid ("spawn policy " ^ label)
        (forged_spawn safe_program safe_argv inherited_stdout empty_path
           (object_int flags)))
    rejected;
  expect_invalid "non-integer spawn policy"
    (forged_spawn safe_program safe_argv inherited_stdout empty_path
       (object_string "8212"))

let test_spawn_shape_validation () =
  expect_invalid "empty program"
    (forged_spawn (object_string "") safe_argv inherited_stdout empty_path
       (object_int fixed_spawn_flags));
  expect_invalid "program NUL"
    (forged_spawn (object_string "/bin/\000true") safe_argv inherited_stdout
       empty_path (object_int fixed_spawn_flags));
  expect_invalid "empty argv"
    (forged_spawn safe_program (object_array [||]) inherited_stdout empty_path
       (object_int fixed_spawn_flags));
  expect_invalid "argv element NUL"
    (forged_spawn safe_program
       (object_array [| "/bin/true"; "bad\000argument" |])
       inherited_stdout empty_path (object_int fixed_spawn_flags));
  expect_invalid "non-array argv"
    (forged_spawn safe_program (object_string "/bin/true")
       inherited_stdout empty_path (object_int fixed_spawn_flags));
  expect_invalid "unknown stdout policy"
    (forged_spawn safe_program safe_argv (object_int 2) empty_path
       (object_int fixed_spawn_flags));
  expect_invalid "truncate with empty path"
    (forged_spawn safe_program safe_argv (object_int 1) empty_path
       (object_int fixed_spawn_flags));
  expect_invalid "inherited stdout with path"
    (forged_spawn safe_program safe_argv inherited_stdout
       (object_string "/tmp/output") (object_int fixed_spawn_flags))

let test_exec_validation () =
  expect_invalid "exec empty program"
    (forged_exec (object_string "") safe_argv);
  expect_invalid "exec empty argv"
    (forged_exec safe_program (object_array [||]));
  expect_invalid "exec program NUL"
    (forged_exec (object_string "bad\000path") safe_argv);
  expect_invalid "exec argument NUL"
    (forged_exec safe_program
       (object_array [| "/bin/true"; "bad\000argument" |]));
  expect_invalid "exec non-array argv"
    (forged_exec safe_program (object_int 0))

let test_all_entry_points_validate_independently () =
  expect_invalid "copy_environment forged unit"
    (forged_copy_environment (object_int 1));
  if forged_acknowledge_pending (object_string "not-int64") then
    fail "acknowledge_pending accepted a non-int64 identity";
  if forged_acknowledge_wait (object_string "not-int64") then
    fail "acknowledge_wait accepted a non-int64 identity";
  expect_invalid_argument "pending forged unit"
    (fun () -> forged_pending (object_int 1));
  expect_invalid_argument "await forged unit"
    (fun () -> forged_await (object_int 1))

let () =
  test_exact_rfork_policy ();
  test_spawn_shape_validation ();
  test_exec_validation ();
  test_all_entry_points_validate_independently ();
  print_endline "process_primitive_validation_test: passed"
