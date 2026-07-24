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

let fail format = Printf.ksprintf failwith format

let string_of_value value =
  let quote element = Printf.sprintf "%S" element in
  "[" ^ String.concat "; " (List.map quote value) ^ "]"

let expect_value expected = function
  | Ok (Some actual) when actual = expected -> ()
  | Ok (Some actual) ->
      fail "expected %s, got %s" (string_of_value expected)
        (string_of_value actual)
  | Ok None -> fail "expected a present value"
  | Result.Error error ->
      fail "%s failed: %s" error.Plan9.operation error.message

let expect_absent = function
  | Ok None -> ()
  | Ok (Some actual) ->
      fail "expected absence, got %s" (string_of_value actual)
  | Result.Error error ->
      fail "%s failed: %s" error.Plan9.operation error.message

let expect_unit = function
  | Ok () -> ()
  | Result.Error error ->
      fail "%s failed: %s" error.Plan9.operation error.message

let expect_invalid = function
  | Result.Error { Plan9.kind = Plan9.Invalid_argument; _ } -> ()
  | Result.Error error ->
      fail "expected Invalid_argument from %s: %s"
        error.Plan9.operation error.message
  | Ok _ -> fail "expected Invalid_argument"

let raw_path name = Filename.concat "/env" name

let raw_write name contents =
  let output_channel = open_out_bin (raw_path name) in
  match output_string output_channel contents with
  | () -> close_out output_channel
  | exception exn ->
      close_out_noerr output_channel;
      raise exn

let raw_read name =
  let input_channel = open_in_bin (raw_path name) in
  let chunk = Bytes.create 128 in
  let buffer = Buffer.create 128 in
  let rec loop () =
    match input input_channel chunk 0 (Bytes.length chunk) with
    | 0 -> Buffer.contents buffer
    | count ->
        Buffer.add_subbytes buffer chunk 0 count;
        loop ()
  in
  match loop () with
  | contents ->
      close_in input_channel;
      contents
  | exception exn ->
      close_in_noerr input_channel;
      raise exn

let raw_remove_noerr name =
  if Sys.file_exists (raw_path name) then
    try Sys.remove (raw_path name) with Sys_error _ -> ()

let contains name names = List.exists (String.equal name) names

let test name function_name =
  try function_name () with
  | exn -> fail "%s: %s" name (Printexc.to_string exn)

let valid_suffix_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
  | _ -> false

let test_suffix =
  if Array.length Sys.argv <> 2 then
    fail "usage: %s TEST_SUFFIX" Sys.argv.(0);
  let suffix = Sys.argv.(1) in
  if suffix = "" || String.length suffix > 40
     || not (String.for_all valid_suffix_char suffix)
  then
    fail "TEST_SUFFIX must be 1-40 ASCII letters, digits, or underscores";
  suffix

let () =
  let name = "ocaml_plan9_env_phase1_test_" ^ test_suffix in
  let function_name = "fn#ocaml_plan9_env_phase1_test_" ^ test_suffix in
  raw_remove_noerr name;
  raw_remove_noerr function_name;
  Fun.protect
    ~finally:(fun () ->
      raw_remove_noerr name;
      raw_remove_noerr function_name)
    (fun () ->
      test "absent value" (fun () ->
        expect_absent (Plan9.Env.get name);
        match Plan9.Env.get_exn name with
        | _ -> fail "get_exn did not raise Not_found"
        | exception Not_found -> ());

      test "empty list and empty scalar" (fun () ->
        raw_write name "";
        expect_value [] (Plan9.Env.get name);
        raw_write name "\000";
        expect_value [""] (Plan9.Env.get name));

      test "present scalar and list" (fun () ->
        raw_write name "scalar\000";
        expect_value ["scalar"] (Plan9.Env.get name);
        raw_write name "one\000two\000";
        expect_value ["one"; "two"] (Plan9.Env.get name));

      test "unterminated final element" (fun () ->
        raw_write name "one\000two";
        expect_value ["one"; "two"] (Plan9.Env.get name));

      test "live repeated reads" (fun () ->
        raw_write name "first\000";
        expect_value ["first"] (Plan9.Env.get name);
        raw_write name "second\000third\000";
        expect_value ["second"; "third"] (Plan9.Env.get name));

      test "set and canonical encoding" (fun () ->
        expect_unit (Plan9.Env.set name []);
        if raw_read name <> "" then fail "empty list was not zero bytes";
        expect_unit (Plan9.Env.set name [""]);
        if raw_read name <> "\000" then fail "empty scalar was not one NUL";
        expect_unit (Plan9.Env.set name ["left"; ""; "right"]);
        if raw_read name <> "left\000\000right\000" then
          fail "list was not canonically encoded";
        expect_value ["left"; ""; "right"] (Plan9.Env.get name);
        if Plan9.Env.get_exn name <> ["left"; ""; "right"] then
          fail "get_exn returned the wrong value");

      test "arbitrary non-NUL bytes" (fun () ->
        let value = [" leading and trailing "; "line\nbreak";
                     "\001\002\t\r\127\128\255"] in
        expect_unit (Plan9.Env.set name value);
        expect_value value (Plan9.Env.get name));

      test "names" (fun () ->
        expect_unit (Plan9.Env.set name ["listed"]);
        match Plan9.Env.names () with
        | Ok names when contains name names -> ()
        | Ok _ -> fail "new environment name was not listed"
        | Result.Error error ->
            fail "%s failed: %s" error.Plan9.operation error.message);

      test "ordinary Plan 9 function name" (fun () ->
        expect_unit (Plan9.Env.set function_name ["echo test"]);
        expect_value ["echo test"] (Plan9.Env.get function_name);
        expect_unit (Plan9.Env.remove function_name);
        expect_absent (Plan9.Env.get function_name));

      test "remove and absent removal" (fun () ->
        expect_unit (Plan9.Env.set name ["remove me"]);
        expect_unit (Plan9.Env.remove name);
        expect_absent (Plan9.Env.get name);
        match Plan9.Env.remove name with
        | Result.Error { Plan9.kind = Plan9.Other; message; _ }
          when message <> "" -> ()
        | Result.Error _ -> fail "absent removal lost its native error message"
        | Ok () -> fail "absent removal unexpectedly succeeded");

      test "invalid names" (fun () ->
        List.iter
          (fun invalid_name ->
            expect_invalid (Plan9.Env.get invalid_name);
            expect_invalid (Plan9.Env.set invalid_name ["value"]);
            expect_invalid (Plan9.Env.remove invalid_name))
          [""; "."; ".."; "with/slash"; "with\000nul"];
        match Plan9.Env.get_exn "" with
        | _ -> fail "invalid get_exn did not raise Plan9.Error"
        | exception
            Plan9.Error { kind = Plan9.Invalid_argument; _ } -> ()
        | exception Plan9.Error error ->
            fail "get_exn raised the wrong error kind: %s" error.message);

      test "invalid value element" (fun () ->
        expect_invalid (Plan9.Env.set name ["with\000nul"]));

      print_endline "Plan9.Env tests passed")
