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

module Process = Plan9.Process

let fail message =
  prerr_endline ("process_native_integration_test: " ^ message);
  exit 1

let check condition message =
  if not condition then fail message

let show_error error =
  error.Plan9.operation ^ ": " ^ error.Plan9.message

let read_file path =
  let input_channel = open_in_bin path in
  let chunk = Bytes.create 4096 in
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

let write_file path contents =
  let output_channel = open_out_bin path in
  match output_string output_channel contents with
  | () -> close_out output_channel
  | exception exn ->
      close_out_noerr output_channel;
      raise exn

let remove_noerr path =
  try Sys.remove path with Sys_error _ -> ()

let registered_files = ref []
let registered_environment = ref []

let register_file path =
  remove_noerr path;
  registered_files := path :: !registered_files;
  path

let register_environment name =
  ignore (Plan9.Env.remove name);
  registered_environment := name :: !registered_environment;
  name

let cleanup () =
  List.iter remove_noerr !registered_files;
  List.iter (fun name -> ignore (Plan9.Env.remove name))
    !registered_environment

let () = at_exit cleanup

let validate_suffix suffix =
  let valid_character = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  let length = String.length suffix in
  if length < 1 || length > 40 then
    fail "TEST_SUFFIX must contain 1-40 characters";
  String.iter
    (fun character ->
      if not (valid_character character) then
        fail "TEST_SUFFIX contains a non-ASCII-name character")
    suffix

let u32 contents offset =
  if offset < 0 || offset + 4 > String.length contents then
    fail "truncated native vector length";
  (Char.code contents.[offset] lsl 24)
  lor (Char.code contents.[offset + 1] lsl 16)
  lor (Char.code contents.[offset + 2] lsl 8)
  lor Char.code contents.[offset + 3]

let decode_vector path =
  let contents = read_file path in
  let count = u32 contents 0 in
  let offset = ref 4 in
  let values =
    Array.init count
      (fun _ ->
        let length = u32 contents !offset in
        offset := !offset + 4;
        if length < 0 || !offset + length > String.length contents then
          fail "truncated native vector element";
        let value = String.sub contents !offset length in
        offset := !offset + length;
        value)
  in
  check (!offset = String.length contents)
    "native vector contained trailing bytes";
  values

let wait_message_equal left right =
  left.Plan9.pid = right.Plan9.pid
  && Int64.equal left.Plan9.user_time_ms right.Plan9.user_time_ms
  && Int64.equal left.Plan9.system_time_ms right.Plan9.system_time_ms
  && Int64.equal left.Plan9.elapsed_time_ms right.Plan9.elapsed_time_ms
  && String.equal left.Plan9.message right.Plan9.message

let check_timings label message =
  check (message.Plan9.user_time_ms >= 0L)
    (label ^ " returned a negative user time");
  check (message.Plan9.system_time_ms >= 0L)
    (label ^ " returned a negative system time");
  check (message.Plan9.elapsed_time_ms >= 0L)
    (label ^ " returned a negative elapsed time")

let expect_run_finished label = function
  | Ok (Process.Run_finished message) ->
      check_timings label message;
      message
  | Result.Error error ->
      fail (label ^ " returned outer Error: " ^ show_error error)
  | Ok (Process.Run_incomplete _) ->
      fail (label ^ " remained incomplete")
  | Ok (Process.Run_terminal_failure _) ->
      fail (label ^ " ended in terminal queue loss")

let expect_spawn_started label = function
  | Ok (Process.Launch_started process) -> process
  | Result.Error error ->
      fail (label ^ " returned outer Error: " ^ show_error error)
  | Ok (Process.Launch_incomplete _) ->
      fail (label ^ " returned an incomplete launch")

let expect_wait_finished label process =
  match Process.wait process with
  | Process.Wait_finished message ->
      check_timings label message;
      message
  | Process.Wait_unresolved _ -> fail (label ^ " remained unresolved")
  | Process.Wait_terminal_failure _ ->
      fail (label ^ " ended in terminal queue loss")

let contains text fragment =
  let text_length = String.length text in
  let fragment_length = String.length fragment in
  let rec search offset =
    if offset + fragment_length > text_length then false
    else if String.sub text offset fragment_length = fragment then true
    else search (offset + 1)
  in
  fragment_length = 0 || search 0

let raw_exec_mode helper output =
  let argv =
    [|
      "caller supplied argv zero";
      "record-argv";
      output;
      "";
      "raw argument with spaces";
      "raw\nnewline";
      "\255\128raw";
    |]
  in
  match Plan9.Raw.exec ~program:helper ~argv with
  | Result.Error error ->
      fail ("Raw.exec failed: " ^ show_error error)
  | Ok _ -> fail "Raw.exec returned after reported success"

let inherited_mode helper payload =
  let message =
    expect_run_finished "nested inherited stdout"
      (Process.run ~program:helper ~args:[| "emit"; payload |] ())
  in
  check (Plan9.wait_succeeded message)
    "nested inherited stdout child returned failure"

let descriptor_hole_mode helper output result payload =
  let message =
    expect_run_finished "nested descriptor-hole spawn"
      (Process.run ~stdout:(Process.Truncate output)
         ~program:helper ~args:[| "emit"; payload |] ())
  in
  check (Plan9.wait_succeeded message)
    "nested descriptor-hole child returned failure";
  check (read_file output = payload)
    "nested descriptor-hole output was not exact";
  write_file result "ok"

let wait_interruption_evidence_mode helper =
  let previous_sigint =
    Sys.signal Sys.sigint (Sys.Signal_handle (fun _ -> ()))
  in
  Fun.protect
    ~finally:(fun () -> Sys.set_signal Sys.sigint previous_sigint)
    (fun () ->
      let child =
        expect_spawn_started "wait-interruption evidence child"
          (Process.spawn ~program:helper
             ~args:[| "interrupt-parent"; "1" |] ())
      in
      begin match Process.wait child with
      | Process.Wait_unresolved
          { process; reason = Process.Await_interrupted error } ->
          check (Process.id process = Process.id child)
            "wait interruption did not retain the exact logical handle";
          check (error.Plan9.kind = Plan9.Interrupted)
            "wait interruption had the wrong native error kind";
          check (error.Plan9.message = "interrupted")
            "wait interruption changed the exact native error"
      | Process.Wait_unresolved _ ->
          fail "wait interruption returned the wrong unresolved reason"
      | Process.Wait_finished _ ->
          fail "wait-interruption evidence completed before interruption"
      | Process.Wait_terminal_failure _ ->
          fail "wait interruption was misclassified as terminal queue loss"
      end;
      let message =
        expect_wait_finished "wait-interruption evidence retry" child
      in
      check (Plan9.wait_succeeded message)
        "wait-interruption evidence child returned failure";
      check (Process.unresolved () = [])
        "wait-interruption retry retained managed ownership";
      print_endline "process_native_integration_test: interruption passed")

let run_child_mode () =
  match Array.to_list Sys.argv with
  | [_; "--raw-exec"; helper; output] ->
      raw_exec_mode helper output
  | [_; "--inherited"; helper; payload] ->
      inherited_mode helper payload;
      true
  | [_; "--descriptor-hole"; helper; output; result; payload] ->
      descriptor_hole_mode helper output result payload;
      true
  | [_; "--qualification-wait-interruption"; helper] ->
      wait_interruption_evidence_mode helper;
      true
  | _ -> false

let test_environment_copy path helper suffix =
  let name =
    register_environment ("p2_process_env_" ^ suffix)
  in
  let trigger = register_file (path "env_trigger") in
  let observed = register_file (path "env_observed") in
  begin match Plan9.Env.set name ["before"] with
  | Ok () -> ()
  | Result.Error error ->
      fail ("initial environment set failed: " ^ show_error error)
  end;
  let child =
    expect_spawn_started "environment observer"
      (Process.spawn ~program:helper
         ~args:
           [|
             "env-read-after";
             trigger;
             "/env/" ^ name;
             observed;
           |]
         ())
  in
  begin match Plan9.Raw.copy_environment () with
  | Ok () -> ()
  | Result.Error error ->
      fail ("RFENVG copy failed: " ^ show_error error)
  end;
  begin match Plan9.Env.set name ["after"] with
  | Ok () -> ()
  | Result.Error error ->
      fail ("post-copy environment set failed: " ^ show_error error)
  end;
  write_file trigger "go";
  let message = expect_wait_finished "environment observer" child in
  check (Plan9.wait_succeeded message)
    "environment observer returned failure";
  check (read_file observed = "before\000")
    "pre-copy child did not retain the old environment group";
  begin match Plan9.Env.get name with
  | Ok (Some ["after"]) -> ()
  | Ok _ -> fail "continuing process did not observe its copied environment"
  | Result.Error error ->
      fail ("post-copy environment read failed: " ^ show_error error)
  end;
  begin match Plan9.Env.remove name with
  | Ok () -> ()
  | Result.Error error ->
      fail ("environment cleanup failed: " ^ show_error error)
  end

let test_literal_vectors path runtime bytecode helper =
  let output = register_file (path "argv_high") in
  let arguments =
    [|
      "record-argv";
      output;
      "";
      "space and\ttab";
      "line one\nline two";
      "$;*?[]{}<>|&'\"\\";
      "\255\128literal";
    |]
  in
  let message =
    expect_run_finished "literal high-level argv"
      (Process.run ~program:helper ~args:arguments ())
  in
  check (Plan9.wait_succeeded message)
    "literal high-level argv helper returned failure";
  let expected = Array.append [| helper |] arguments in
  check (decode_vector output = expected)
    "high-level literal argv bytes or synthesized argv0 changed";

  let raw_output = register_file (path "argv_raw") in
  let raw_message =
    expect_run_finished "literal Raw.exec argv"
      (Process.run ~program:runtime
         ~args:[| bytecode; "--raw-exec"; helper; raw_output |] ())
  in
  check (Plan9.wait_succeeded raw_message)
    "Raw.exec wrapper returned failure";
  check
    (decode_vector raw_output
     =
     [|
       "caller supplied argv zero";
       "record-argv";
       raw_output;
       "";
       "raw argument with spaces";
       "raw\nnewline";
       "\255\128raw";
     |])
    "Raw.exec changed caller argv0 or literal argument bytes"

let test_exec_failures path =
  let expect_pre_rfork_invalid label program =
    match Process.spawn ~program ~args:[||] () with
    | Result.Error error ->
        check (error.Plan9.kind = Plan9.Invalid_argument)
          (label ^ " had the wrong error kind")
    | Ok _ -> fail (label ^ " created or retained a child")
  in
  expect_pre_rfork_invalid "empty program" "";
  expect_pre_rfork_invalid "NUL program" "/bin/bad\000program";

  let missing = path "missing_program" in
  remove_noerr missing;
  begin match Process.spawn ~program:missing ~args:[||] () with
  | Result.Error error ->
      check (error.Plan9.message <> "")
        "missing program lost its native exec error";
      check (String.length error.Plan9.message <= 127)
        "missing-program error exceeded the bounded P9E1 payload"
  | Ok _ -> fail "missing program left an unresolved launch"
  end;
  check (Process.unresolved () = [])
    "known missing-program exec failure retained a child";

  let invalid = register_file (path "invalid_program") in
  write_file invalid "not an executable image\n";
  begin match Process.spawn ~program:invalid ~args:[||] () with
  | Result.Error error ->
      check (error.Plan9.message <> "")
        "invalid program lost its native exec error";
      check (String.length error.Plan9.message <= 127)
        "invalid-program error exceeded the bounded P9E1 payload"
  | Ok _ -> fail "invalid program left an unresolved launch"
  end

let test_stdout path runtime bytecode helper =
  let truncate_output = register_file (path "stdout_truncate") in
  let truncate_payload = "truncate:$;*:\255\n" in
  write_file truncate_output "older and longer contents";
  let truncate_message =
    expect_run_finished "truncate stdout"
      (Process.run ~stdout:(Process.Truncate truncate_output)
         ~program:helper ~args:[| "emit"; truncate_payload |] ())
  in
  check (Plan9.wait_succeeded truncate_message)
    "truncate stdout child returned failure";
  check (read_file truncate_output = truncate_payload)
    "truncate stdout was not exact";

  let inherited_output = register_file (path "stdout_inherited") in
  let inherited_payload = "inherited stdout\n" in
  let inherited_message =
    expect_run_finished "inherited stdout wrapper"
      (Process.run ~program:helper
         ~args:
           [|
             "exec-runtime";
             "0";
             inherited_output;
             runtime;
             bytecode;
             "--inherited";
             helper;
             inherited_payload;
           |]
         ())
  in
  check (Plan9.wait_succeeded inherited_message)
    "inherited stdout wrapper returned failure";
  check (read_file inherited_output = inherited_payload)
    "inherited stdout did not preserve exact bytes"

let test_descriptor_holes path runtime bytecode helper =
  for mask = 1 to 7 do
    let suffix = string_of_int mask in
    let output = register_file (path ("hole_output_" ^ suffix)) in
    let result = register_file (path ("hole_result_" ^ suffix)) in
    let payload = "descriptor-hole-" ^ suffix ^ "\n" in
    let message =
      expect_run_finished ("descriptor-hole wrapper " ^ suffix)
        (Process.run ~program:helper
           ~args:
             [|
               "exec-runtime";
               suffix;
               "-";
               runtime;
               bytecode;
               "--descriptor-hole";
               helper;
               output;
               result;
               payload;
             |]
           ())
    in
    check (Plan9.wait_succeeded message)
      ("descriptor-hole wrapper " ^ suffix ^ " returned failure");
    check (read_file result = "ok")
      ("descriptor-hole case " ^ suffix ^ " did not finish cleanly");
    check (read_file output = payload)
      ("descriptor-hole case " ^ suffix ^ " changed output")
  done

let test_wait_lifecycle helper =
  let delayed =
    expect_spawn_started "no-background-await child"
      (Process.spawn ~program:helper
         ~args:[| "delay-exit"; "1"; "" |] ())
  in
  check
    (List.exists
       (fun process -> Process.id process = Process.id delayed)
       (Process.unresolved ()))
    "spawned child disappeared before a synchronous coordinator call";
  let delayed_message =
    expect_wait_finished "no-background-await child" delayed
  in
  check (Plan9.wait_succeeded delayed_message)
    "delayed child returned failure";

  let slow =
    expect_spawn_started "slow ordering child"
      (Process.spawn ~program:helper
         ~args:[| "delay-exit"; "2"; "" |] ())
  in
  let quick =
    expect_spawn_started "quick ordering child"
      (Process.spawn ~program:helper ~args:[| "exit"; "" |] ())
  in
  let slow_message = expect_wait_finished "slow ordering child" slow in
  let quick_message = expect_wait_finished "quick ordering child" quick in
  check (slow_message.Plan9.pid = Process.pid slow)
    "slow completion was routed to the wrong PID";
  check (quick_message.Plan9.pid = Process.pid quick)
    "quick completion was routed to the wrong PID";
  check (Plan9.wait_succeeded slow_message
         && Plan9.wait_succeeded quick_message)
    "ordered children did not both succeed";
  let quick_again = expect_wait_finished "memoized quick child" quick in
  check (wait_message_equal quick_message quick_again)
    "terminal wait result was not memoized exactly";

  let status_marker = "p2_native_wait_status" in
  let status_message =
    expect_run_finished "nonempty wait status"
      (Process.run ~program:helper ~args:[| "exit"; status_marker |] ())
  in
  check (not (Plan9.wait_succeeded status_message))
    "nonempty native status was classified as success";
  check (contains status_message.Plan9.message status_marker)
    "native wait status text was not preserved";

  let run_message =
    expect_run_finished "ordinary Process.run"
      (Process.run ~program:helper ~args:[| "exit"; "" |] ())
  in
  check (Plan9.wait_succeeded run_message)
    "ordinary Process.run did not finish successfully"

let test_clean_postconditions initial_descriptors =
  check (Process.unresolved () = [])
    "managed or native-pending ownership remained after the suite";
  check (Process.take_foreign_completions () = [])
    "foreign completions remained after the suite";
  begin match Process.wait_any () with
  | Result.Error error ->
      check (error.Plan9.kind = Plan9.No_children)
        "ownerless wait_any returned the wrong terminal error";
      check (error.Plan9.message = "no living children")
        "ownerless wait_any changed the exact native error"
  | Ok _ -> fail "ownerless wait_any reported a completion or owner"
  end;
  let final_descriptors =
    Array.to_list (Sys.readdir "/fd") |> List.sort compare
  in
  check (final_descriptors = initial_descriptors)
    "the native integration suite leaked a parent descriptor"

let run_main runtime bytecode helper suffix =
  validate_suffix suffix;
  let path role =
    "/tmp/ocaml_p2_process_" ^ suffix ^ "_" ^ role
  in
  let initial_descriptors =
    Array.to_list (Sys.readdir "/fd") |> List.sort compare
  in
  match
    test_environment_copy path helper suffix;
    test_literal_vectors path runtime bytecode helper;
    test_exec_failures path;
    test_stdout path runtime bytecode helper;
    test_descriptor_holes path runtime bytecode helper;
    test_wait_lifecycle helper;
    test_clean_postconditions initial_descriptors
  with
  | () ->
      cleanup ();
      print_endline "process_native_integration_test: passed"
  | exception exn ->
      cleanup ();
      raise exn

let () =
  if not (run_child_mode ()) then
    match Array.to_list Sys.argv with
    | [_; runtime; bytecode; helper; suffix] ->
        run_main runtime bytecode helper suffix
    | _ ->
        fail
          "expected RUNTIME BYTECODE HELPER TEST_SUFFIX or a private mode"
