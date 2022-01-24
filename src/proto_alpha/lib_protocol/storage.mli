(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

(** Tezos Protocol Implementation - Typed storage

    This module hides the hierarchical (key x value) database under
    pre-allocated typed accessors for all persistent entities of the
    tezos context.

    This interface enforces no invariant on the contents of the
    database. Its goal is to centralize all accessors in order to have
    a complete view over the database contents and avoid key
    collisions. *)

open Storage_sigs

module type Simple_single_data_storage = sig
  type value

  val get : Raw_context.t -> value tzresult Lwt.t

  val update : Raw_context.t -> value -> Raw_context.t tzresult Lwt.t

  val init : Raw_context.t -> value -> Raw_context.t tzresult Lwt.t
end

module Legacy_block_priority : Simple_single_data_storage with type value = int

module Block_round : Simple_single_data_storage with type value = Round_repr.t

module Roll_legacy : sig
  (** Storage from this submodule must only be accessed through the
      module `Roll_legacy`. *)

  module Owner :
    Indexed_data_snapshotable_storage
      with type key = Roll_repr_legacy.t
       and type snapshot = Cycle_repr.t * int
       and type value = Signature.Public_key.t
       and type t := Raw_context.t

  val clear : Raw_context.t -> Raw_context.t Lwt.t

  (** The next roll to be allocated. *)
  module Next :
    Single_data_storage
      with type value = Roll_repr_legacy.t
       and type t := Raw_context.t

  (** Rolls linked lists represent both account owned and free rolls.
      All rolls belongs either to the limbo list or to an owned list. *)

  (** Head of the linked list of rolls in limbo *)
  module Limbo :
    Single_data_storage
      with type value = Roll_repr_legacy.t
       and type t := Raw_context.t

  (** Rolls associated to contracts, a linked list per contract *)
  module Delegate_roll_list :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Roll_repr_legacy.t
       and type t := Raw_context.t

  (** Use this to iter on a linked list of rolls *)
  module Successor :
    Indexed_data_storage
      with type key = Roll_repr_legacy.t
       and type value = Roll_repr_legacy.t
       and type t := Raw_context.t

  (** The tez of a contract that are not assigned to rolls *)
  module Delegate_change :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  (** Index of the randomly selected roll snapshot of a given cycle. *)
  module Snapshot_for_cycle :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = int
       and type t := Raw_context.t

  (** Last roll in the snapshoted roll allocation of a given cycle. *)
  module Last_for_snapshot :
    Indexed_data_storage
      with type key = int
       and type value = Roll_repr_legacy.t
       and type t = Raw_context.t * Cycle_repr.t
end

type deposits = {initial_amount : Tez_repr.t; current_amount : Tez_repr.t}

type missed_endorsements_info = {remaining_slots : int; missed_levels : int}

module Contract : sig
  (** Storage from this submodule must only be accessed through the
      module `Contract`. *)

  module Global_counter : Simple_single_data_storage with type value = Z.t

  (** The domain of alive contracts *)
  val fold :
    Raw_context.t ->
    order:[`Sorted | `Undefined] ->
    init:'a ->
    f:(Contract_repr.t -> 'a -> 'a Lwt.t) ->
    'a Lwt.t

  val list : Raw_context.t -> Contract_repr.t list Lwt.t

  (** The tez possessed by a contract and that can be used. A contract
     may also possess tez in frozen deposits. Empty balances (of zero
     tez) are only allowed for originated contracts, not for implicit
     ones. *)
  module Balance :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  (** If the value is not set, the delegate didn't miss any endorsing
     opportunity.  If it is set, this value is a record of type
     [missed_endorsements_info], where:
   - [remaining_slots] is the difference between the maximum number of
     slots that can be missed and the number of missed slots;
     therefore, when the number is positive, it represents the number
     of slots that a delegate can still miss before forfeiting its
     endorsing rewards for the current cycle; when the number is zero
     it means rewards are not lost, but no further slots can be
     missed anymore;
   - [missed_levels] represents the number of missed levels (for
     endorsing). *)
  module Missed_endorsements :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = missed_endorsements_info
       and type t := Raw_context.t

  (** Frozen balance, see 'delegate_storage.mli' for more explanation.
      Always update `Delegates_with_frozen_balance` accordingly.

      Deprecated only used for migration
  *)
  module Legacy_frozen_deposits :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  (** Deprecated only used for migration *)
  module Legacy_frozen_fees :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  (** Deprecated only used for migration *)
  module Legacy_frozen_rewards :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  (** The manager of a contract *)
  module Manager :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Manager_repr.t
       and type t := Raw_context.t

  (** The delegate of a contract, if any. *)
  module Delegate :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Signature.Public_key_hash.t
       and type t := Raw_context.t

  (** All contracts (implicit and originated) that are delegated, if any  *)
  module Delegated :
    Data_set_storage
      with type elt = Contract_repr.t
       and type t = Raw_context.t * Contract_repr.t

  (** The part of a delegate balance that can't be used. The total
     balance is frozen_deposits.current_amount + balance. It also stores
     the initial frozen balance in frozen_deposits.initial_amount. We
     have current_amount <= initial_amount and current_amount <
     initial_amount iff the delegate was slashed. *)
  module Frozen_deposits :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = deposits
       and type t := Raw_context.t

  (** If there is a value, the frozen balance for the contract won't
     exceed it (starting in preserved_cycles + 1). *)
  module Frozen_deposits_limit :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  module Inactive_delegate :
    Data_set_storage with type elt = Contract_repr.t and type t = Raw_context.t

  (** The last cycle where the delegate is considered active; that is,
     at the next cycle it will be considered inactive. *)
  module Delegate_desactivation :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Cycle_repr.t
       and type t := Raw_context.t

  module Counter :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t

  module Code :
    Non_iterable_indexed_carbonated_data_storage
      with type key = Contract_repr.t
       and type value = Script_repr.lazy_expr
       and type t := Raw_context.t

  module Storage :
    Non_iterable_indexed_carbonated_data_storage
      with type key = Contract_repr.t
       and type value = Script_repr.lazy_expr
       and type t := Raw_context.t

  (** Current storage space in bytes.
      Includes code, global storage and big map elements. *)
  module Used_storage_space :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t

  (** Maximal space available without needing to burn new fees. *)
  module Paid_storage_space :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t
end

module Big_map : sig
  type id = Lazy_storage_kind.Big_map.Id.t

  module Next : sig
    val incr : Raw_context.t -> (Raw_context.t * id) tzresult Lwt.t

    val init : Raw_context.t -> Raw_context.t tzresult Lwt.t
  end

  (** The domain of alive big maps *)
  val fold :
    Raw_context.t ->
    order:[`Sorted | `Undefined] ->
    init:'a ->
    f:(id -> 'a -> 'a Lwt.t) ->
    'a Lwt.t

  val list : Raw_context.t -> id list Lwt.t

  val remove : Raw_context.t -> id -> Raw_context.t Lwt.t

  val copy : Raw_context.t -> from:id -> to_:id -> Raw_context.t tzresult Lwt.t

  type key = Raw_context.t * id

  val rpc_arg : id RPC_arg.t

  module Contents : sig
    include
      Non_iterable_indexed_carbonated_data_storage
        with type key = Script_expr_hash.t
         and type value = Script_repr.expr
         and type t := key

    (** HACK *)
    val list_values :
      ?offset:int ->
      ?length:int ->
      Raw_context.t * id ->
      (Raw_context.t * Script_repr.expr list) tzresult Lwt.t
  end

  module Total_bytes :
    Indexed_data_storage
      with type key = id
       and type value = Z.t
       and type t := Raw_context.t

  module Key_type :
    Indexed_data_storage
      with type key = id
       and type value = Script_repr.expr
       and type t := Raw_context.t

  module Value_type :
    Indexed_data_storage
      with type key = id
       and type value = Script_repr.expr
       and type t := Raw_context.t
end

module Sapling : sig
  type id = Lazy_storage_kind.Sapling_state.Id.t

  val rpc_arg : id RPC_arg.t

  module Next : sig
    val incr : Raw_context.t -> (Raw_context.t * id) tzresult Lwt.t

    val init : Raw_context.t -> Raw_context.t tzresult Lwt.t
  end

  val copy : Raw_context.t -> from:id -> to_:id -> Raw_context.t tzresult Lwt.t

  val remove : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Total_bytes :
    Indexed_data_storage
      with type key = id
       and type value = Z.t
       and type t := Raw_context.t

  (* Used by both Commitments and Ciphertexts *)
  module Commitments_size :
    Single_data_storage with type t := Raw_context.t * id and type value = int64

  module Memo_size :
    Single_data_storage with type t := Raw_context.t * id and type value = int

  module Commitments :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Hash.t

  val commitments_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Ciphertexts :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Ciphertext.t

  val ciphertexts_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Nullifiers_size :
    Single_data_storage with type t := Raw_context.t * id and type value = int64

  module Nullifiers_ordered :
    Non_iterable_indexed_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Nullifier.t

  module Nullifiers_hashed :
    Carbonated_data_set_storage
      with type t := Raw_context.t * id
       and type elt = Sapling.Nullifier.t

  val nullifiers_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Roots :
    Non_iterable_indexed_data_storage
      with type t := Raw_context.t * id
       and type key = int32
       and type value = Sapling.Hash.t

  module Roots_pos :
    Single_data_storage with type t := Raw_context.t * id and type value = int32

  module Roots_level :
    Single_data_storage
      with type t := Raw_context.t * id
       and type value = Raw_level_repr.t
end

(** Set of all registered delegates. *)
module Delegates :
  Data_set_storage
    with type t := Raw_context.t
     and type elt = Signature.Public_key_hash.t

type slashed_level = {for_double_endorsing : bool; for_double_baking : bool}

(** Set used to avoid slashing multiple times the same event *)
module Slashed_deposits :
  Indexed_data_storage
    with type t := Raw_context.t * Cycle_repr.t
     and type key = Raw_level_repr.t * Signature.Public_key_hash.t
     and type value = slashed_level

(** Set of all active delegates with rolls. *)
module Legacy_active_delegates_with_rolls :
  Data_set_storage
    with type t := Raw_context.t
     and type elt = Signature.Public_key_hash.t

module Stake : sig
  (** The map of all the staking balances of all delegates, including
     those with less than one roll. It might be large *)
  module Staking_balance :
    Indexed_data_snapshotable_storage
      with type key = Signature.Public_key_hash.t
       and type value = Tez_repr.t
       and type snapshot = int
       and type t := Raw_context.t

  (** This is a set, encoded in a map with value unit. This should be
     fairly small compared to staking balance *)
  module Active_delegate_with_one_roll :
    Indexed_data_snapshotable_storage
      with type key = Signature.Public_key_hash.t
       and type value = unit
       and type snapshot = int
       and type t := Raw_context.t

  module Last_snapshot :
    Single_data_storage with type value = int and type t := Raw_context.t

  (** List of active stake *)
  module Selected_distribution_for_cycle :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = (Signature.Public_key_hash.t * Tez_repr.t) list
       and type t := Raw_context.t
end

(** Sum of the active stakes of all the delegates with rolls *)
module Total_active_stake :
  Indexed_data_storage
    with type key = Cycle_repr.t
     and type value = Tez_repr.t
     and type t := Raw_context.t

(** State of the sampler used to select delegates. Managed synchronously
    with [Stake.Selected_distribution_for_cycle]. *)
module Delegate_sampler_state :
  Indexed_data_storage
    with type key = Cycle_repr.t
     and type value =
          (Signature.Public_key.t * Signature.Public_key_hash.t) Sampler.t
     and type t := Raw_context.t

(** Set of all the delegates with frozen rewards/deposits/fees for a given cycle.
    Deprecated: This is now only used for stitching while migrating from an
    emmy protocol. This is to be removed in the next version.

    This table must be cleaned after migration. *)
module Legacy_delegates_with_frozen_balance :
  Data_set_storage
    with type t = Raw_context.t * Cycle_repr.t
     and type elt = Signature.Public_key_hash.t

(** Votes *)

module Vote : sig
  module Pred_period_kind :
    Single_data_storage
      with type value = Voting_period_repr.kind
       and type t := Raw_context.t

  module Current_period :
    Single_data_storage
      with type value = Voting_period_repr.t
       and type t := Raw_context.t

  (** Participation exponential moving average, in centile of percentage *)
  module Participation_ema :
    Single_data_storage with type value = int32 and type t := Raw_context.t

  module Current_proposal :
    Single_data_storage
      with type value = Protocol_hash.t
       and type t := Raw_context.t

  (** Sum of all rolls of all delegates. *)
  module Listings_size :
    Single_data_storage with type value = int32 and type t := Raw_context.t

  (** Contains all delegates with their assigned number of rolls. *)
  module Listings :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = int32
       and type t := Raw_context.t

  (** Set of protocol proposal with corresponding proposer delegate *)
  module Proposals :
    Data_set_storage
      with type elt = Protocol_hash.t * Signature.Public_key_hash.t
       and type t := Raw_context.t

  (** Keeps for each delegate the number of proposed protocols *)
  module Proposals_count :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = int
       and type t := Raw_context.t

  (** Contains for each delegate its ballot *)
  module Ballots :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Vote_repr.ballot
       and type t := Raw_context.t
end

module type FOR_CYCLE = sig
  val init :
    Raw_context.t ->
    Cycle_repr.t ->
    Seed_repr.seed ->
    Raw_context.t tzresult Lwt.t

  val mem : Raw_context.t -> Cycle_repr.t -> bool Lwt.t

  val get : Raw_context.t -> Cycle_repr.t -> Seed_repr.seed tzresult Lwt.t

  val remove_existing :
    Raw_context.t -> Cycle_repr.t -> Raw_context.t tzresult Lwt.t
end

(** Seed *)

module Seed : sig
  (** Storage from this submodule must only be accessed through the
      module `Seed`. *)

  type unrevealed_nonce = {
    nonce_hash : Nonce_hash.t;
    delegate : Signature.Public_key_hash.t;
  }

  type nonce_status =
    | Unrevealed of unrevealed_nonce
    | Revealed of Seed_repr.nonce

  module Nonce :
    Non_iterable_indexed_data_storage
      with type key := Level_repr.t
       and type value := nonce_status
       and type t := Raw_context.t

  module Nonce_legacy :
    Non_iterable_indexed_data_storage
      with type key := Level_repr.t
       and type value := nonce_status
       and type t := Raw_context.t

  module For_cycle : FOR_CYCLE
end

(** Commitments *)

module Commitments :
  Indexed_data_storage
    with type key = Blinded_public_key_hash.t
     and type value = Tez_repr.t
     and type t := Raw_context.t

(** Ramp up rewards *)
module Ramp_up : sig
  type reward = {
    baking_reward_fixed_portion : Tez_repr.t;
    baking_reward_bonus_per_slot : Tez_repr.t;
    endorsing_reward_per_slot : Tez_repr.t;
  }

  module Rewards :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value := reward
       and type t := Raw_context.t
end

module Pending_migration : sig
  module Balance_updates :
    Single_data_storage
      with type value = Receipt_repr.balance_updates
       and type t := Raw_context.t

  module Operation_results :
    Single_data_storage
      with type value = Migration_repr.origination_result list
       and type t := Raw_context.t

  val remove :
    Raw_context.t ->
    (Raw_context.t
    * Receipt_repr.balance_updates
    * Migration_repr.origination_result list)
    tzresult
    Lwt.t
end

module Liquidity_baking : sig
  (** Exponential moving average (ema) of flags set in protocol_data.contents.
    If at any block it's above the threshold set in constants,
    liquidity baking permanently shuts off. **)
  module Escape_ema :
    Single_data_storage with type t := Raw_context.t and type value = Int32.t

  (** Constant product market maker contract that receives liquidity baking subsidy. **)
  module Cpmm_address :
    Single_data_storage
      with type t := Raw_context.t
       and type value = Contract_repr.t
end

(** A map of [Script_repr.expr] values, indexed by their hash ([Script_expr_hash.t]).
    Values from this map can be incorporated by any contract via the primitive
    [Michelson_v1_primitives.H_constant]. *)
module Global_constants : sig
  module Map :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t
       and type key = Script_expr_hash.t
       and type value = Script_repr.expr
end

(** This module exposes a balance table for tracking ticket ownership.
    The table is a mapping from keys to values where the keys consist of a
    hashed representation of:
      - A ticketer, i.e. the creator of the ticket
      - The content of a the ticket
      - The contract that owns some amount of the ticket
    The values of the table are the amounts owned by each key.
 *)
module Ticket_balance : sig
  module Table :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t
       and type key = Ticket_hash_repr.t
       and type value = Z.t
end

(** Tenderbake *)

module Tenderbake : sig
  module First_level :
    Single_data_storage
      with type t := Raw_context.t
       and type value = Raw_level_repr.t

  (** [Endorsement_branch] stores a single value composed of the
      grandparent hash and the predecessor's payload (computed with
      the grandparent hash) used to verify the validity of
      endorsements. *)
  module Endorsement_branch :
    Single_data_storage
      with type value = Block_hash.t * Block_payload_hash.t
       and type t := Raw_context.t

  (** [Grand_parent_branch] stores a single value composed of the
      great-grand parent hash and the grand parent's payload *)
  module Grand_parent_branch :
    Single_data_storage
      with type value = Block_hash.t * Block_payload_hash.t
       and type t := Raw_context.t
end

module Tx_rollup : sig
  (** Storage from this submodule must only be accessed through the
      module `Tx_rollup_storage`. *)

  module State :
    Indexed_data_storage
      with type key = Tx_rollup_repr.t
       and type value = Tx_rollup_repr.state
       and type t := Raw_context.t
end

(** Smart contract rollup *)
module Sc_rollup : sig
  (**

     Each smart contract rollup is associated to:

     - a PVM kind (provided at creation time, read-only) ;
     - a boot sector (provided at creation time, read-only).
     - a merkelized inbox, of which only the root hash is stored
  *)
  module PVM_kind :
    Indexed_data_storage
      with type key = Sc_rollup_repr.t
       and type value = Sc_rollup_repr.Kind.t
       and type t := Raw_context.t

  module Boot_sector :
    Indexed_data_storage
      with type key = Sc_rollup_repr.t
       and type value = Sc_rollup_repr.PVM.boot_sector
       and type t := Raw_context.t

  module Inbox :
    Non_iterable_indexed_carbonated_data_storage
      with type key = Sc_rollup_repr.t
       and type value = Sc_rollup_inbox.t
       and type t := Raw_context.t
end
