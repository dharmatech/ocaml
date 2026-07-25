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

type error_kind = Plan9_process.error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other

type error = Plan9_process.error = {
  operation : string;
  kind : error_kind;
  message : string;
}

exception Error of error

type pid = Plan9_process.pid
type process_id = Plan9_process.process_id

type wait_msg = Plan9_process.wait_msg = {
  pid : pid;
  user_time_ms : int64;
  system_time_ms : int64;
  elapsed_time_ms : int64;
  message : string;
}

let wait_succeeded = Plan9_process.wait_succeeded

module Env = struct
  type value = string list

  let root = "/env"

  let invalid operation message =
    Result.Error { operation; kind = Invalid_argument; message }

  let validate_name operation name =
    if name = "" then
      invalid operation "environment variable name is empty"
    else if name = "." || name = ".." then
      invalid operation "environment variable name is a reserved path name"
    else if String.contains name '/' then
      invalid operation "environment variable name contains '/'"
    else if String.contains name '\000' then
      invalid operation "environment variable name contains NUL"
    else
      Ok ()

  let rec validate_value operation = function
    | [] -> Ok ()
    | element :: rest ->
        if String.contains element '\000' then
          invalid operation "environment variable value element contains NUL"
        else
          validate_value operation rest

  let protect_io operation f =
    try Ok (f ()) with
    | Sys_error message ->
        Result.Error { operation; kind = Other; message }

  let path name = Filename.concat root name

  let read_all input_channel =
    let chunk = Bytes.create 4096 in
    let buffer = Buffer.create 128 in
    let rec loop () =
      match input input_channel chunk 0 (Bytes.length chunk) with
      | 0 -> Buffer.contents buffer
      | count ->
          Buffer.add_subbytes buffer chunk 0 count;
          loop ()
    in
    loop ()

  let read_file filename =
    let input_channel = open_in_bin filename in
    match read_all input_channel with
    | contents ->
        close_in input_channel;
        contents
    | exception exn ->
        close_in_noerr input_channel;
        raise exn

  let decode contents =
    let length = String.length contents in
    let rec loop values element_start index =
      if index = length then
        if element_start = length then List.rev values
        else
          let element =
            String.sub contents element_start (length - element_start)
          in
          List.rev (element :: values)
      else if contents.[index] = '\000' then
        let element =
          String.sub contents element_start (index - element_start)
        in
        loop (element :: values) (index + 1) (index + 1)
      else
        loop values element_start (index + 1)
    in
    loop [] 0 0

  let read_names operation =
    protect_io operation (fun () -> Array.to_list (Sys.readdir root))

  let names () = read_names "Plan9.Env.names"

  let get name =
    let operation = "Plan9.Env.get" in
    match validate_name operation name with
    | Result.Error _ as error -> error
    | Ok () ->
        begin match read_names operation with
        | Result.Error error -> Result.Error error
        | Ok names ->
            if not (List.exists (String.equal name) names) then Ok None
            else
              protect_io operation
                (fun () -> Some (decode (read_file (path name))))
        end

  let get_exn name =
    match get name with
    | Ok (Some value) -> value
    | Ok None -> raise Not_found
    | Result.Error error -> raise (Error error)

  let write_value filename value =
    let output_channel = open_out_bin filename in
    match
      List.iter
        (fun element ->
          output_string output_channel element;
          output_char output_channel '\000')
        value
    with
    | () -> close_out output_channel
    | exception exn ->
        close_out_noerr output_channel;
        raise exn

  let set name value =
    let operation = "Plan9.Env.set" in
    match validate_name operation name with
    | Result.Error _ as error -> error
    | Ok () ->
        begin match validate_value operation value with
        | Result.Error _ as error -> error
        | Ok () ->
            protect_io operation (fun () -> write_value (path name) value)
        end

  let remove name =
    let operation = "Plan9.Env.remove" in
    match validate_name operation name with
    | Result.Error _ as error -> error
    | Ok () -> protect_io operation (fun () -> Sys.remove (path name))
end

module Native = struct
  let foreign_capacity = 64

  (* RFPROC | RFFDG | RFREND.  The C primitive independently requires this
     exact value; this private constant is not a generic rfork interface. *)
  let spawn_flags = 16 lor 4 lor 8192

  external copy_environment :
    unit -> (unit, Plan9_process.native_failure) result
    = "caml_plan9_copy_environment"

  external exec :
    string ->
    string array ->
    ('a, Plan9_process.native_failure) result
    = "caml_plan9_exec"

  external spawn :
    string ->
    string array ->
    int ->
    string ->
    int ->
    (Plan9_process.native_pending, Plan9_process.native_failure) result
    = "caml_plan9_process_spawn"

  external pending :
    unit -> Plan9_process.native_pending array
    = "caml_plan9_process_pending"

  external acknowledge_pending :
    int64 -> bool
    = "caml_plan9_process_acknowledge"

  external await :
    unit -> Plan9_process.native_wait_event
    = "caml_plan9_process_await"

  external acknowledge_wait :
    int64 -> bool
    = "caml_plan9_process_acknowledge_wait"
end

module Raw = struct
  let copy_environment () =
    match Native.copy_environment () with
    | Ok () -> Ok ()
    | Result.Error native_error ->
        Result.Error
          (Plan9_process.error_of_native
             "Plan9.Raw.copy_environment" native_error)

  let exec ~program ~argv =
    match Native.exec program argv with
    | Ok value -> Ok value
    | Result.Error native_error ->
        Result.Error
          (Plan9_process.error_of_native "Plan9.Raw.exec" native_error)
end

module Process = Plan9_process.Make (Native)
