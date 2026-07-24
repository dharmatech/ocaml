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

(** Native Plan 9 interfaces.

    This library is available only in OCaml installations targeting Plan 9.
    Portable Unix-compatible behavior remains in {!Sys} and {!Unix}. *)

type error_kind =
  | No_children
  | Interrupted
  | Invalid_argument
  | Protocol_error
  | Other

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

exception Error of error
(** Raised by explicitly raising operations when a native operation fails. *)

module Env : sig
  (** Direct access to the process's live Plan 9 environment namespace.

      Every operation reads or mutates files below [/env]. The module does not
      consult APE's cached environment and keeps no in-memory mirror. *)

  type value = string list

  val get : string -> (value option, error) result
  (** [get name] reads [/env/name].

      [Ok None] means that the file was absent when [/env] was enumerated.
      [Ok (Some value)] preserves the native scalar or list representation.
      Invalid names and I/O failures are returned as [Error _]. If another
      process removes a listed file before it is opened, the race is reported
      as an I/O error rather than retried or treated as absence. *)

  val get_exn : string -> value
  (** [get_exn name] is the explicitly raising lookup.

      @raise Not_found if [name] is absent.
      @raise Error if name validation or native I/O fails. *)

  val set : string -> value -> (unit, error) result
  (** [set name value] creates or truncates [/env/name] and writes the
      canonical NUL-terminated Plan 9 encoding.

      An empty list writes zero bytes; [[""]] writes one NUL byte. Elements
      may contain arbitrary bytes except NUL. The write is direct rather than
      transactional, so an I/O failure can leave the file truncated or
      partially written; callers may use [get] to observe the resulting live
      state. *)

  val remove : string -> (unit, error) result
  (** [remove name] directly removes [/env/name].

      Removing an absent name returns the native removal error rather than
      silently succeeding. *)

  val names : unit -> (string list, error) result
  (** [names ()] returns the names currently visible in [/env].

      The order is unspecified and no snapshot is retained. *)
end
