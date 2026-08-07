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

(** Internal native descriptor ownership.

    This interface is not installed. *)

module type Primitive = sig
  type capability

  val pipe :
    unit ->
    ((capability * capability), Plan9_types.native_failure) result

  val close :
    capability -> (unit, Plan9_types.native_failure) result

  val read :
    capability -> int ->
    ((bytes * int), Plan9_types.native_failure) result

  val write :
    capability -> bytes -> int -> int ->
    (int, Plan9_types.native_failure) result
end

module type S = sig
  type t
  type attachment

  val pipe : unit -> ((t * t), Plan9_types.error) result
  val read :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
  val write :
    t -> bytes -> pos:int -> len:int ->
    (int, Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val read :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val write :
      attachment -> bytes -> pos:int -> len:int ->
      (int, Plan9_types.error) result
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

(** Select the exact native request count for a validated logical length.
    This helper is private to the uninstalled implementation and its tests. *)
val primitive_count : int -> int

module Make (_ : Primitive) : S

include S
