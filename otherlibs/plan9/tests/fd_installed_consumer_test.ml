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
  prerr_endline ("fd_installed_consumer_test: " ^ message);
  exit 1

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      fail (label ^ ": " ^ error.Plan9.operation ^ ": " ^ error.message)

let descriptor_inventory () =
  let entries = Sys.readdir "/fd" in
  Array.sort String.compare entries;
  Array.to_list entries

let () =
  let before = descriptor_inventory () in
  let left, right = expect_ok "pipe" (Plan9.Fd.pipe ()) in
  let payload = Bytes.of_string "installed\000Plan9.Fd" in
  let alias = left in
  let written =
    expect_ok "write"
      (Plan9.Fd.write right payload ~pos:0 ~len:(Bytes.length payload))
  in
  if written <> Bytes.length payload then fail "write count changed";
  ignore (expect_ok "writer close" (Plan9.Fd.close right));
  let received = Bytes.make (Bytes.length payload) '\165' in
  let count =
    expect_ok "read"
      (Plan9.Fd.read alias received ~pos:0 ~len:(Bytes.length received))
  in
  if count <> Bytes.length payload || not (Bytes.equal payload received) then
    fail "binary payload changed";
  if expect_ok "EOF" (Plan9.Fd.read alias received ~pos:0 ~len:1) <> 0 then
    fail "EOF was not returned";
  ignore (expect_ok "alias close" (Plan9.Fd.close alias));
  ignore (expect_ok "repeated close" (Plan9.Fd.close left));
  let after = descriptor_inventory () in
  if before <> after then fail "descriptor inventory changed";
  print_endline "fd_installed_consumer_test: ok"
