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

(** Internal native input channels.

    This interface is not installed. *)

module type Descriptor = sig
  type t
  type attachment

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val read :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

module type S = sig
  type fd
  type t

  val of_fd : fd -> (t, Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result
  val input :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
end

module Make (Fd : Descriptor) : S with type fd = Fd.t

include S with type fd = Plan9_fd.t
