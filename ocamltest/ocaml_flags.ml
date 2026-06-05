(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Sebastien Hinderer, projet Gallium, INRIA Paris            *)
(*                                                                        *)
(*   Copyright 2018 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Flags used in OCaml commands *)

let stdlib =
  let stdlib_path = Ocaml_directories.stdlib in
  "-nostdlib -I " ^ stdlib_path

let include_toplevel_directory =
  "-I " ^ Ocaml_directories.toplevel

let c_includes =
  let dir = Ocaml_directories.runtime in
  "-ccopt -I" ^ dir

let runtime_variant_flags () = match Ocaml_files.runtime_variant() with
  | Ocaml_files.Normal -> ""
  | Ocaml_files.Debug -> " -runtime-variant d"
  | Ocaml_files.Instrumented -> " -runtime-variant i"

let custom_runtime_main_object () =
  let main_object = Filename.concat Ocaml_directories.runtime "main.b.o" in
  if Sys.file_exists main_object then " -ccopt " ^ main_object else ""

let output_complete_exe env =
  let flags =
    Environments.safe_lookup Ocaml_variables.flags env ^ " " ^
    Environments.safe_lookup Ocaml_variables.last_flags env in
  List.exists ((=) "-output-complete-exe") (Misc.rev_split_words flags)

let use_custom_runtime_main env =
  match Environments.lookup_as_bool Ocaml_variables.custom_runtime_main env with
  | Some false -> false
  | _ -> true

let runtime_flags env backend c_files =
  let runtime_library_flags = "-I " ^
    Ocaml_directories.runtime in
  let rt_flags = match backend with
    | Ocaml_backends.Native -> runtime_variant_flags ()
    | Ocaml_backends.Bytecode ->
      begin
        if c_files then begin (* custom mode *)
          let main_object =
            if output_complete_exe env || not (use_custom_runtime_main env)
            then ""
            else custom_runtime_main_object ()
          in
          "-custom " ^ (runtime_variant_flags ()) ^ main_object
        end else begin (* non-custom mode *)
          let use_runtime =
            Environments.lookup_as_bool Ocaml_variables.use_runtime env
          in
          if use_runtime = Some false
          then ""
          else "-use-runtime " ^ Ocaml_files.ocamlrun
        end
      end in
  rt_flags ^ " " ^ runtime_library_flags

let toplevel_default_flags = "-noinit -no-version -noprompt"

let ocamldebug_default_flags =
  "-no-version -no-prompt -no-time -no-breakpoint-message " ^
  ("-I " ^ Ocaml_directories.stdlib ^ " ") ^
  ("-topdirs-path " ^ Ocaml_directories.toplevel)

let ocamlobjinfo_default_flags = "-null-crc"
