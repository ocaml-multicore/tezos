(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020-2021 Nomadic Labs <contact@nomadic-labs.com>           *)
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

val fitness_version_number : string

val proof_of_work_nonce_size : int

val nonce_length : int

val max_anon_ops_per_block : int

val max_proposals_per_delegate : int

val max_operation_data_length : int

(** A global size limit on the size of Micheline expressions
    after expansion.

    We want to prevent constants from being
    used to create huge values that could potentially do damage
    if ever printed or sent over the network. We arrived at this
    number by finding the largest possible contract in terms of
    number of nodes. The number of nodes is constrained by the
    current "max_operation_data_length" (32768) to be ~10,000 (
    see "largest_flat_contract.tz" in the tezt suite for the largest
    contract with constants that can be originated). As a first
    approximation, we set the node size limit to 5 times this amount. *)
val max_micheline_node_count : int

(** Same as [max_micheline_node_count] but for limiting the combined
    bytes of the strings, ints and bytes in a expanded Micheline
    expression.  *)
val max_micheline_bytes_limit : int

(** Represents the maximum depth of an expression stored
    in the table after all references to other constants have
    (recursively) been expanded, where depth refers to the
    nesting of [Prim] and/or [Seq] nodes.

    The size was chosen arbitrarily to match the typechecker
    in [Script_ir_translator]. *)
val max_allowed_global_constant_depth : int

val michelson_maximum_type_size : int

type fixed

val fixed_encoding : fixed Data_encoding.encoding

type ratio = {numerator : int; denominator : int}

val ratio_encoding : ratio Data_encoding.t

val pp_ratio : Format.formatter -> ratio -> unit

type parametric = {
  preserved_cycles : int;
  blocks_per_cycle : int32;
  blocks_per_commitment : int32;
  blocks_per_stake_snapshot : int32;
  blocks_per_voting_period : int32;
  hard_gas_limit_per_operation : Gas_limit_repr.Arith.integral;
  hard_gas_limit_per_block : Gas_limit_repr.Arith.integral;
  proof_of_work_threshold : int64;
  tokens_per_roll : Tez_repr.t;
  seed_nonce_revelation_tip : Tez_repr.t;
  origination_size : int;
  baking_reward_fixed_portion : Tez_repr.t;
  baking_reward_bonus_per_slot : Tez_repr.t;
  endorsing_reward_per_slot : Tez_repr.t;
  cost_per_byte : Tez_repr.t;
  hard_storage_limit_per_operation : Z.t;
  quorum_min : int32;
  (* in centile of a percentage *)
  quorum_max : int32;
  min_proposal_quorum : int32;
  liquidity_baking_subsidy : Tez_repr.t;
  liquidity_baking_sunset_level : int32;
  liquidity_baking_escape_ema_threshold : int32;
  max_operations_time_to_live : int;
  minimal_block_delay : Period_repr.t;
  delay_increment_per_round : Period_repr.t;
  minimal_participation_ratio : ratio;
  consensus_committee_size : int;
  (* in slots *)
  consensus_threshold : int;
  (* in slots *)
  max_slashing_period : int;
  (* in cycles *)
  frozen_deposits_percentage : int;
  (* that is, (100 * delegated tz / own tz) *)
  double_baking_punishment : Tez_repr.t;
  ratio_of_frozen_deposits_slashed_per_double_endorsement : ratio;
  initial_seed : State_hash.t option;
  cache_script_size : int;
  (* in bytes *)
  cache_stake_distribution_cycles : int;
  (* in cycles *)
  cache_sampler_state_cycles : int;
  (* in cycles *)
  tx_rollup_enable : bool;
  tx_rollup_origination_size : int;
  sc_rollup_enable : bool;
  sc_rollup_origination_size : int;
}

val parametric_encoding : parametric Data_encoding.encoding

type t = private {fixed : fixed; parametric : parametric}

val all : parametric -> t

val encoding : t Data_encoding.encoding

type error += (* `Permanent *) Invalid_protocol_constants of string

(** performs some consistency checks on the protocol parameters *)
val check_constants : parametric -> unit tzresult

module Generated : sig
  type t = {
    consensus_threshold : int;
    baking_reward_fixed_portion : Tez_repr.t;
    baking_reward_bonus_per_slot : Tez_repr.t;
    endorsing_reward_per_slot : Tez_repr.t;
  }

  (* This function is meant to be used just in lib_parameters and in the
     migration code to be sure that the parameters are consistent. *)
  val generate : consensus_committee_size:int -> blocks_per_minute:ratio -> t
end

module Proto_previous : sig
  type delegate_selection =
    | Random
    | Round_robin_over of Signature.Public_key.t list list

  type parametric = {
    preserved_cycles : int;
    blocks_per_cycle : int32;
    blocks_per_commitment : int32;
    blocks_per_stake_snapshot : int32;
    blocks_per_voting_period : int32;
    hard_gas_limit_per_operation : Gas_limit_repr.Arith.integral;
    hard_gas_limit_per_block : Gas_limit_repr.Arith.integral;
    proof_of_work_threshold : int64;
    tokens_per_roll : Tez_repr.t;
    seed_nonce_revelation_tip : Tez_repr.t;
    origination_size : int;
    baking_reward_fixed_portion : Tez_repr.t;
    baking_reward_bonus_per_slot : Tez_repr.t;
    endorsing_reward_per_slot : Tez_repr.t;
    cost_per_byte : Tez_repr.t;
    hard_storage_limit_per_operation : Z.t;
    quorum_min : int32;
    quorum_max : int32;
    min_proposal_quorum : int32;
    liquidity_baking_subsidy : Tez_repr.t;
    liquidity_baking_sunset_level : int32;
    liquidity_baking_escape_ema_threshold : int32;
    max_operations_time_to_live : int;
    minimal_block_delay : Period_repr.t;
    delay_increment_per_round : Period_repr.t;
    minimal_participation_ratio : ratio;
    consensus_committee_size : int;
    consensus_threshold : int;
    max_slashing_period : int;
    frozen_deposits_percentage : int;
    double_baking_punishment : Tez_repr.t;
    ratio_of_frozen_deposits_slashed_per_double_endorsement : ratio;
    delegate_selection : delegate_selection;
  }

  val parametric_encoding : parametric Data_encoding.encoding
end

(** For each subcache, a size limit needs to be declared once. However,
    depending how the protocol will be instantiated (sandboxed mode,
    test network, ...) we may want to change this limit. For each
    subcache, a parametric constant can be used to change the limit
    (see {parametric}).

    The number of subcaches and the limits for all those subcaches form 
    together what is called the [cache_layout]. *)
val cache_layout_size : int

(** The [cache_layout] depends on parametric constants. *)
val cache_layout : parametric -> int list
