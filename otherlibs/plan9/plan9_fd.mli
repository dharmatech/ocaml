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
end

module type S = sig
  type t
  type attachment

  val pipe : unit -> ((t * t), Plan9_types.error) result
  val close : t -> (unit, Plan9_types.error) result

  module Private : sig
    val prepare_attach :
      t -> (attachment, Plan9_types.error) result
    val commit_attach : attachment -> bool
    val close : attachment -> (unit, Plan9_types.error) result
  end
end

module Make (_ : Primitive) : S

include S
