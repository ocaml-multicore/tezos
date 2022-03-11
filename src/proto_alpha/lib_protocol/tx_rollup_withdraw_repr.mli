(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2022 Oxhead Alpha <info@oxheadalpha.com>                    *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** A [withdrawal] gives right to a L1 address [claimer] to
    retrieve the quantity [amount] of a ticket whose hash is [ticket_hash].
    Withdrawals result from layer-2-to-layer-1 transfers, and from
    failed layer-2 deposits.*)
type withdrawal = {
  claimer : Signature.Public_key_hash.t;
  ticket_hash : Ticket_hash_repr.t;
  amount : Tx_rollup_l2_qty.t;
}

type t = withdrawal

val encoding : t Data_encoding.t

(** A [withdrawals_merkle_root] is the hash of a list of withdrawals (as returned by
    [Tx_rollup_l2_apply.apply_message]), stored in commitments and used
    to validate the executions of withdrawals.

    Internally [withdrawals_merkle_root] is the root element of
    a merkle tree whose leaves are [withdrawal] hashes.
*)
type withdrawals_merkle_root

val withdrawals_merkle_root_encoding : withdrawals_merkle_root Data_encoding.t

val withdrawals_merkle_root_of_b58check_opt :
  string -> withdrawals_merkle_root option

(** A [merkle_tree_path] is the minimal information needed to
   recompute a [withdrawals_merkle_root] without having all
   withdrawals.

   Internally [merkle_tree_path] is the merkle tree path of sub-tree
   hash of a [withdrawals_merkle_root] *)
type merkle_tree_path

val merkle_tree_path_encoding : merkle_tree_path Data_encoding.t

(** [merkelize_list withdrawal_list] merkelizes [withdrawal_list] into
   a full binary tree and returns the [withdrawals_merkle_root] of
   that tree.  *)
val merkelize_list : t list -> withdrawals_merkle_root

val empty_withdrawals_merkle_root : withdrawals_merkle_root

val pp_withdrawals_merkle_root :
  Format.formatter -> withdrawals_merkle_root -> unit

(** [compute_path withdrawal_list index] computes the
   [merkle_tree_path] in the tree given by [merkelize_list
   withdrawal_list] of the [index]th element of the
   [withdrawal_list]. *)
val compute_path : t list -> int -> merkle_tree_path

(** [check_path merkle_tree_path withdrawal] returns the
   [withdrawals_merkle_root] computed for [withdrawal] and the index
   on the list. *)
val check_path : merkle_tree_path -> t -> withdrawals_merkle_root * int

(** [Withdrawal_accounting] provides an interface for the storage to
   account for which withdrawals (as identified by their index) have
   been consumed. *)
module Withdrawal_accounting : sig
  type t

  val encoding : t Data_encoding.t

  (** The state of withdrawal accounting where no
      withdrawals have been consumed. *)
  val empty : t

  (** [get l index] returns [true] if the withdrawal identified by
      [index] has been been consumed (as registered through
      {!Withdrawal_accounting.set}). Fails when [index] is negative. *)
  val get : t -> int -> bool tzresult

  (** [set l index] registers that the withdrawal identified by
      [index] has been consumed. Fails when [index] is negative. *)
  val set : t -> int -> t tzresult
end
