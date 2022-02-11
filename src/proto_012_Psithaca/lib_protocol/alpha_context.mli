(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019-2021 Nomadic Labs <contact@nomadic-labs.com>           *)
(* Copyright (c) 2021 Trili Tech, <contact@trili.tech>                       *)
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

(** An [Alpha_context.t] is an immutable snapshot of the ledger state at some block
    height, preserving
    {{:https://tezos.gitlab.io/developer/entering_alpha.html#the-big-abstraction-barrier-alpha-context}
    type-safety and invariants} of the ledger state.

    {2 Implementation}

    [Alpha_context.t] is a wrapper over [Raw_context.t], which in turn is a
    wrapper around [Context.t] from the Protocol Environment.

    {2 Lifetime of an Alpha_context}

    - Creation, using [prepare] or [prepare_first_block]

    - Modification, using the operations defined in this signature

    - Finalization, using [finalize]
 *)

module type BASIC_DATA = sig
  type t

  include Compare.S with type t := t

  val encoding : t Data_encoding.t

  val pp : Format.formatter -> t -> unit
end

type t

type context = t

type public_key = Signature.Public_key.t

type public_key_hash = Signature.Public_key_hash.t

type signature = Signature.t

module Slot : sig
  type t

  include Compare.S with type t := t

  val pp : Format.formatter -> t -> unit

  val zero : t

  val succ : t -> t

  val of_int_do_not_use_except_for_parameters : int -> t

  val encoding : t Data_encoding.encoding

  val slot_range : min:int -> count:int -> t list tzresult

  module Map : Map.S with type key = t

  module Set : Set.S with type elt = t
end

module Tez : sig
  include BASIC_DATA

  type tez = t

  val zero : tez

  val one_mutez : tez

  val one_cent : tez

  val fifty_cents : tez

  val one : tez

  val ( -? ) : tez -> tez -> tez tzresult

  val sub_opt : tez -> tez -> tez option

  val ( +? ) : tez -> tez -> tez tzresult

  val ( *? ) : tez -> int64 -> tez tzresult

  val ( /? ) : tez -> int64 -> tez tzresult

  val of_string : string -> tez option

  val to_string : tez -> string

  val of_mutez : int64 -> tez option

  val to_mutez : tez -> int64

  val of_mutez_exn : int64 -> t

  val mul_exn : t -> int -> t

  val div_exn : t -> int -> t
end

module Period : sig
  include BASIC_DATA

  type period = t

  val rpc_arg : period RPC_arg.arg

  val of_seconds : int64 -> period tzresult

  val of_seconds_exn : int64 -> period

  val to_seconds : period -> int64

  val add : period -> period -> period tzresult

  val mult : int32 -> period -> period tzresult

  val zero : period

  val one_second : period

  val one_minute : period

  val one_hour : period

  val compare : period -> period -> int
end

module Timestamp : sig
  include BASIC_DATA with type t = Time.t

  type time = t

  val ( +? ) : time -> Period.t -> time tzresult

  val ( -? ) : time -> time -> Period.t tzresult

  val ( - ) : time -> Period.t -> time

  val of_notation : string -> time option

  val to_notation : time -> string

  val of_seconds : int64 -> time

  val to_seconds : time -> int64

  val of_seconds_string : string -> time option

  val to_seconds_string : time -> string

  val current : context -> time

  val predecessor : context -> time
end

module Raw_level : sig
  include BASIC_DATA

  type raw_level = t

  val rpc_arg : raw_level RPC_arg.arg

  val diff : raw_level -> raw_level -> int32

  val root : raw_level

  val succ : raw_level -> raw_level

  val pred : raw_level -> raw_level option

  val to_int32 : raw_level -> int32

  val of_int32 : int32 -> raw_level tzresult
end

module Cycle : sig
  include BASIC_DATA

  type cycle = t

  val rpc_arg : cycle RPC_arg.arg

  val root : cycle

  val succ : cycle -> cycle

  val pred : cycle -> cycle option

  val add : cycle -> int -> cycle

  val sub : cycle -> int -> cycle option

  val to_int32 : cycle -> int32

  module Map : Map.S with type key = cycle
end

module Round : sig
  (* A round represents an iteration of the single-shot consensus algorithm.
     This mostly simply re-exports [Round_repr]. See [Round_repr] for
     additional documentation of this module *)

  type t

  val zero : t

  val succ : t -> t

  val pred : t -> t tzresult

  val to_int32 : t -> int32

  val of_int32 : int32 -> t tzresult

  val of_int : int -> t tzresult

  val to_int : t -> int tzresult

  val to_slot : t -> committee_size:int -> Slot.t tzresult

  val pp : Format.formatter -> t -> unit

  val encoding : t Data_encoding.t

  include Compare.S with type t := t

  module Map : Map.S with type key = t

  type round_durations

  val pp_round_durations : Format.formatter -> round_durations -> unit

  val round_durations_encoding : round_durations Data_encoding.t

  val round_duration : round_durations -> t -> Period.t

  module Durations : sig
    val create :
      first_round_duration:Period.t ->
      delay_increment_per_round:Period.t ->
      round_durations tzresult

    val create_opt :
      first_round_duration:Period.t ->
      delay_increment_per_round:Period.t ->
      round_durations option
  end

  val level_offset_of_round : round_durations -> round:t -> Period.t tzresult

  val timestamp_of_round :
    round_durations ->
    predecessor_timestamp:Time.t ->
    predecessor_round:t ->
    round:t ->
    Time.t tzresult

  val timestamp_of_another_round_same_level :
    round_durations ->
    current_timestamp:Time.t ->
    current_round:t ->
    considered_round:t ->
    Time.t tzresult

  val round_of_timestamp :
    round_durations ->
    predecessor_timestamp:Time.t ->
    predecessor_round:t ->
    timestamp:Time.t ->
    t tzresult

  (* retrieve a round from the context *)
  val get : context -> t tzresult Lwt.t

  (* store a round in context *)
  val update : context -> t -> context tzresult Lwt.t
end

module Gas : sig
  (** This module implements the gas subsystem of the context.

     Gas reflects the computational cost of each operation to limit
     the cost of operations and, by extension, the cost of blocks.

     There are two gas quotas: one for operation and one for
     block. For this reason, we maintain two gas levels -- one for
     operations and another one for blocks -- that correspond to the
     remaining amounts of gas, initialized with the quota
     limits and decreased each time gas is consumed.

  *)

  module Arith :
    Fixed_point_repr.Safe
      with type 'a t = Saturation_repr.may_saturate Saturation_repr.t
  [@@coq_plain_module]

  (** For maintenance operations or for testing, gas can be
     [Unaccounted]. Otherwise, the computation is [Limited] by the
     [remaining] gas in the context. *)
  type t = private Unaccounted | Limited of {remaining : Arith.fp}

  val encoding : t Data_encoding.encoding

  val pp : Format.formatter -> t -> unit

  (** [check_limit_is_valid ctxt limit] checks that the given gas
     [limit] is well-formed, i.e., it does not exceed the hard gas
     limit per operation as defined in [ctxt] and it is positive. *)
  val check_limit_is_valid : context -> 'a Arith.t -> unit tzresult

  (** [set_limit ctxt limit] returns a context with a given
     [limit] level of gas allocated for an operation. *)
  val set_limit : context -> 'a Arith.t -> context

  (** [set_unlimited] allows unlimited gas consumption. *)
  val set_unlimited : context -> context

  (** [remaining_operation_gas ctxt] returns the current gas level in
     the context [ctxt] for the current operation. If gas is
     [Unaccounted], an arbitrary value will be returned. *)
  val remaining_operation_gas : context -> Arith.fp

  (** [reset_block_gas ctxt] returns a context where the remaining gas
     in the block is reset to the constant [hard_gas_limit_per_block],
     i.e., as if no operations have been included in the block.

     /!\ Do not call this function unless you want to validate
     operations on their own (like in the mempool). *)
  val reset_block_gas : context -> context

  (** [level ctxt] is the current gas level in [ctxt] for the current
     operation. *)
  val level : context -> t

  (** [update_remaining_operation_gas ctxt remaining] sets the current
     gas level for operations to [remaining]. *)
  val update_remaining_operation_gas : context -> Arith.fp -> context

  (** [consumed since until] is the operation gas level difference
     between context [since] and context [until]. This function
     returns [Arith.zero] if any of the two contexts allows for an
     unlimited gas consumption. This function also returns
     [Arith.zero] if [since] has less gas than [until]. *)
  val consumed : since:context -> until:context -> Arith.fp

  (** [block_level ctxt] returns the block gas level in context [ctxt]. *)
  val block_level : context -> Arith.fp

  (** Costs are computed using a saturating arithmetic. See
     {!Saturation_repr}. *)
  type cost = Saturation_repr.may_saturate Saturation_repr.t

  val cost_encoding : cost Data_encoding.encoding

  val pp_cost : Format.formatter -> cost -> unit

  (** [consume ctxt cost] subtracts [cost] to the current operation
     gas level in [ctxt]. This operation may fail with
     [Operation_quota_exceeded] if the operation gas level would
     go below zero. *)
  val consume : context -> cost -> context tzresult

  type error += Operation_quota_exceeded (* `Temporary *)

  (** [consume_limit_in_block ctxt limit] consumes [limit] in
     the current block gas level of the context. This operation may
     fail with error [Block_quota_exceeded] if not enough gas remains
     in the block. This operation may also fail with
     [Gas_limit_too_high] if [limit] is greater than the allowed
     limit for operation gas level. *)
  val consume_limit_in_block : context -> 'a Arith.t -> context tzresult

  type error += Block_quota_exceeded (* `Temporary *)

  type error += Gas_limit_too_high (* `Permanent *)

  (** The cost of free operation is [0]. *)
  val free : cost

  (** [atomic_step_cost x] corresponds to [x] milliunit of gas. *)
  val atomic_step_cost : _ Saturation_repr.t -> cost

  (** [step_cost x] corresponds to [x] units of gas. *)
  val step_cost : _ Saturation_repr.t -> cost

  (** Cost of allocating qwords of storage.
    [alloc_cost n] estimates the cost of allocating [n] qwords of storage. *)
  val alloc_cost : _ Saturation_repr.t -> cost

  (** Cost of allocating bytes in the storage.
    [alloc_bytes_cost b] estimates the cost of allocating [b] bytes of
    storage. *)
  val alloc_bytes_cost : int -> cost

  (** Cost of allocating bytes in the storage.

      [alloc_mbytes_cost b] estimates the cost of allocating [b] bytes of
      storage and the cost of an header to describe these bytes. *)
  val alloc_mbytes_cost : int -> cost

  (** Cost of reading the storage.
    [read_bytes_cost n] estimates the cost of reading [n] bytes of storage. *)
  val read_bytes_cost : int -> cost

  (** Cost of writing to storage.
    [write_bytes_const n] estimates the cost of writing [n] bytes to the
    storage. *)
  val write_bytes_cost : int -> cost

  (** Multiply a cost by a factor. Both arguments are saturated arithmetic values,
    so no negative numbers are involved. *)
  val ( *@ ) : _ Saturation_repr.t -> cost -> cost

  (** Add two costs together. *)
  val ( +@ ) : cost -> cost -> cost

  (** [cost_of_repr] is an internal operation needed to inject costs
     for Storage_costs into Gas.cost. *)
  val cost_of_repr : Gas_limit_repr.cost -> cost
end

module Script_string : module type of Script_string_repr

module Script_int : module type of Script_int_repr

module Script_timestamp : sig
  open Script_int

  type t

  val compare : t -> t -> int

  val to_string : t -> string

  val to_notation : t -> string option

  val to_num_str : t -> string

  val of_string : string -> t option

  val diff : t -> t -> z num

  val add_delta : t -> z num -> t

  val sub_delta : t -> z num -> t

  val now : context -> t

  val to_zint : t -> Z.t

  val of_zint : Z.t -> t

  val encoding : t Data_encoding.encoding
end

module Script : sig
  type prim = Michelson_v1_primitives.prim =
    | K_parameter
    | K_storage
    | K_code
    | K_view
    | D_False
    | D_Elt
    | D_Left
    | D_None
    | D_Pair
    | D_Right
    | D_Some
    | D_True
    | D_Unit
    | I_PACK
    | I_UNPACK
    | I_BLAKE2B
    | I_SHA256
    | I_SHA512
    | I_ABS
    | I_ADD
    | I_AMOUNT
    | I_AND
    | I_BALANCE
    | I_CAR
    | I_CDR
    | I_CHAIN_ID
    | I_CHECK_SIGNATURE
    | I_COMPARE
    | I_CONCAT
    | I_CONS
    | I_CREATE_ACCOUNT
    | I_CREATE_CONTRACT
    | I_IMPLICIT_ACCOUNT
    | I_DIP
    | I_DROP
    | I_DUP
    | I_VIEW
    | I_EDIV
    | I_EMPTY_BIG_MAP
    | I_EMPTY_MAP
    | I_EMPTY_SET
    | I_EQ
    | I_EXEC
    | I_APPLY
    | I_FAILWITH
    | I_GE
    | I_GET
    | I_GET_AND_UPDATE
    | I_GT
    | I_HASH_KEY
    | I_IF
    | I_IF_CONS
    | I_IF_LEFT
    | I_IF_NONE
    | I_INT
    | I_LAMBDA
    | I_LE
    | I_LEFT
    | I_LEVEL
    | I_LOOP
    | I_LSL
    | I_LSR
    | I_LT
    | I_MAP
    | I_MEM
    | I_MUL
    | I_NEG
    | I_NEQ
    | I_NIL
    | I_NONE
    | I_NOT
    | I_NOW
    | I_OR
    | I_PAIR
    | I_UNPAIR
    | I_PUSH
    | I_RIGHT
    | I_SIZE
    | I_SOME
    | I_SOURCE
    | I_SENDER
    | I_SELF
    | I_SELF_ADDRESS
    | I_SLICE
    | I_STEPS_TO_QUOTA
    | I_SUB
    | I_SUB_MUTEZ
    | I_SWAP
    | I_TRANSFER_TOKENS
    | I_SET_DELEGATE
    | I_UNIT
    | I_UPDATE
    | I_XOR
    | I_ITER
    | I_LOOP_LEFT
    | I_ADDRESS
    | I_CONTRACT
    | I_ISNAT
    | I_CAST
    | I_RENAME
    | I_SAPLING_EMPTY_STATE
    | I_SAPLING_VERIFY_UPDATE
    | I_DIG
    | I_DUG
    | I_NEVER
    | I_VOTING_POWER
    | I_TOTAL_VOTING_POWER
    | I_KECCAK
    | I_SHA3
    | I_PAIRING_CHECK
    | I_TICKET
    | I_READ_TICKET
    | I_SPLIT_TICKET
    | I_JOIN_TICKETS
    | I_OPEN_CHEST
    | T_bool
    | T_contract
    | T_int
    | T_key
    | T_key_hash
    | T_lambda
    | T_list
    | T_map
    | T_big_map
    | T_nat
    | T_option
    | T_or
    | T_pair
    | T_set
    | T_signature
    | T_string
    | T_bytes
    | T_mutez
    | T_timestamp
    | T_unit
    | T_operation
    | T_address
    | T_sapling_transaction
    | T_sapling_state
    | T_chain_id
    | T_never
    | T_bls12_381_g1
    | T_bls12_381_g2
    | T_bls12_381_fr
    | T_ticket
    | T_chest_key
    | T_chest
    | H_constant

  type location = Micheline.canonical_location

  type annot = Micheline.annot

  type expr = prim Micheline.canonical

  type lazy_expr = expr Data_encoding.lazy_t

  val lazy_expr : expr -> lazy_expr

  type 'location michelson_node = ('location, prim) Micheline.node

  type unlocated_michelson_node = unit michelson_node

  type node = location michelson_node

  type t = {code : lazy_expr; storage : lazy_expr}

  val location_encoding : location Data_encoding.t

  val expr_encoding : expr Data_encoding.t

  val prim_encoding : prim Data_encoding.t

  val encoding : t Data_encoding.t

  val lazy_expr_encoding : lazy_expr Data_encoding.t

  val deserialization_cost_estimated_from_bytes : int -> Gas.cost

  val deserialized_cost : expr -> Gas.cost

  val serialized_cost : bytes -> Gas.cost

  val bytes_node_cost : bytes -> Gas.cost

  (** Mode of deserialization gas consumption in {!force_decode}:

      - {!Always}: the gas is taken independently of the internal state of the
        [lazy_expr]
      - {!When_needed}: the gas is consumed only if the [lazy_expr] has never
        been deserialized before. *)
  type consume_deserialization_gas = Always | When_needed

  (** Decode an expression in the context after consuming the deserialization
      gas cost (see {!consume_deserialization_gas}). *)
  val force_decode_in_context :
    consume_deserialization_gas:consume_deserialization_gas ->
    context ->
    lazy_expr ->
    (expr * context) tzresult

  val force_bytes_in_context :
    context -> lazy_expr -> (bytes * context) tzresult

  val unit_parameter : lazy_expr

  val strip_locations_cost : _ michelson_node -> Gas.cost

  val strip_annotations_cost : node -> Gas.cost

  val strip_annotations : node -> node
end

module Constants : sig
  (** Fixed constants *)
  type fixed

  type delegate_selection =
    | Random
    | Round_robin_over of Signature.Public_key.t list list

  val fixed_encoding : fixed Data_encoding.t

  val proof_of_work_nonce_size : int

  val nonce_length : int

  val max_anon_ops_per_block : int

  val max_operation_data_length : int

  val max_proposals_per_delegate : int

  val michelson_maximum_type_size : int

  type ratio = {numerator : int; denominator : int}

  val ratio_encoding : ratio Data_encoding.t

  val pp_ratio : Format.formatter -> ratio -> unit

  (** Constants parameterized by context *)
  type parametric = {
    preserved_cycles : int;
    blocks_per_cycle : int32;
    blocks_per_commitment : int32;
    blocks_per_stake_snapshot : int32;
    blocks_per_voting_period : int32;
    hard_gas_limit_per_operation : Gas.Arith.integral;
    hard_gas_limit_per_block : Gas.Arith.integral;
    proof_of_work_threshold : int64;
    tokens_per_roll : Tez.t;
    seed_nonce_revelation_tip : Tez.t;
    origination_size : int;
    baking_reward_fixed_portion : Tez.t;
    baking_reward_bonus_per_slot : Tez.t;
    endorsing_reward_per_slot : Tez.t;
    cost_per_byte : Tez.t;
    hard_storage_limit_per_operation : Z.t;
    quorum_min : int32;
    quorum_max : int32;
    min_proposal_quorum : int32;
    liquidity_baking_subsidy : Tez.t;
    liquidity_baking_sunset_level : int32;
    liquidity_baking_escape_ema_threshold : int32;
    max_operations_time_to_live : int;
    minimal_block_delay : Period.t;
    delay_increment_per_round : Period.t;
    minimal_participation_ratio : ratio;
    consensus_committee_size : int;
    consensus_threshold : int;
    max_slashing_period : int;
    frozen_deposits_percentage : int;
    double_baking_punishment : Tez.t;
    ratio_of_frozen_deposits_slashed_per_double_endorsement : ratio;
    delegate_selection : delegate_selection;
  }

  module Generated : sig
    type t = {
      consensus_threshold : int;
      baking_reward_fixed_portion : Tez.t;
      baking_reward_bonus_per_slot : Tez.t;
      endorsing_reward_per_slot : Tez.t;
    }

    val generate : consensus_committee_size:int -> blocks_per_minute:ratio -> t
  end

  val parametric_encoding : parametric Data_encoding.t

  val parametric : context -> parametric

  val preserved_cycles : context -> int

  val blocks_per_cycle : context -> int32

  val blocks_per_commitment : context -> int32

  val blocks_per_stake_snapshot : context -> int32

  val blocks_per_voting_period : context -> int32

  val hard_gas_limit_per_operation : context -> Gas.Arith.integral

  val hard_gas_limit_per_block : context -> Gas.Arith.integral

  val cost_per_byte : context -> Tez.t

  val hard_storage_limit_per_operation : context -> Z.t

  val proof_of_work_threshold : context -> int64

  val tokens_per_roll : context -> Tez.t

  val seed_nonce_revelation_tip : context -> Tez.t

  val origination_size : context -> int

  val baking_reward_fixed_portion : context -> Tez.t

  val baking_reward_bonus_per_slot : context -> Tez.t

  val endorsing_reward_per_slot : context -> Tez.t

  val quorum_min : context -> int32

  val quorum_max : context -> int32

  val min_proposal_quorum : context -> int32

  val liquidity_baking_subsidy : context -> Tez.t

  val liquidity_baking_sunset_level : context -> int32

  val liquidity_baking_escape_ema_threshold : context -> int32

  val minimal_block_delay : context -> Period.t

  val delay_increment_per_round : context -> Period.t

  val round_durations : context -> Round.round_durations

  val consensus_committee_size : context -> int

  val consensus_threshold : context -> int

  val minimal_participation_ratio : context -> ratio

  val max_slashing_period : context -> int

  val frozen_deposits_percentage : context -> int

  val double_baking_punishment : context -> Tez.t

  val ratio_of_frozen_deposits_slashed_per_double_endorsement : context -> ratio

  val delegate_selection_encoding : delegate_selection Data_encoding.t

  (** All constants: fixed and parametric *)
  type t = private {fixed : fixed; parametric : parametric}

  val all : context -> t

  val encoding : t Data_encoding.t
end

module Global_constants_storage : sig
  type error += Expression_too_deep

  type error += Expression_already_registered

  (** A constant is the prim of the literal characters "constant".
    A constant must have a single argument, being a string with a
    well formed hash of a Micheline expression (i.e generated by
    [Script_expr_hash.to_b58check]). *)
  type error += Badly_formed_constant_expression

  type error += Nonexistent_global

  (** [get context hash] retrieves the Micheline value with the given hash.

    Fails with [Nonexistent_global] if no value is found at the given hash.

    Fails with [Storage_error Corrupted_data] if the deserialisation fails.

    Consumes [Gas_repr.read_bytes_cost <size of the value>]. *)
  val get : t -> Script_expr_hash.t -> (t * Script.expr) tzresult Lwt.t

  (** [register context value] Register a constant in the global table of constants,
    returning the hash and storage bytes consumed.

    Does not type-check the Micheline code being registered, allow potentially
    ill-typed Michelson values (see note at top of module in global_constants_storage.mli).

    The constant is stored unexpanded, but it is temporarily expanded at registration
    time only to check the expanded version respects the following limits.

    Fails with [Expression_too_deep] if, after fully, expanding all constants,
    the expression would contain too many nested levels, that is more than
    [Constants_repr.max_allowed_global_constant_depth].

    Fails with [Badly_formed_constant_expression] if constants are not
    well-formed (see declaration of [Badly_formed_constant_expression]) or with
    [Nonexistent_global] if a referenced constant does not exist in the table.

    Consumes serialization cost.
    Consumes [Gas_repr.write_bytes_cost <size>] where size is the number
    of bytes in the binary serialization provided by [Script.expr_encoding].*)
  val register :
    t -> Script.expr -> (t * Script_expr_hash.t * Z.t) tzresult Lwt.t

  (** [expand context expr] Replaces every constant in the
    given Michelson expression with its value stored in the global table.

    The expansion is applied recursively so that the returned expression
    contains no constant.

    Fails with [Badly_formed_constant_expression] if constants are not
    well-formed (see declaration of [Badly_formed_constant_expression]) or
    with [Nonexistent_global] if a referenced constant does not exist in
    the table. *)
  val expand : t -> Script.expr -> (t * Script.expr) tzresult Lwt.t

  module Internal_for_tests : sig
    (** [node_too_large node] returns true if:
      - The number of sub-nodes in the [node]
        exceeds [Global_constants_storage.node_size_limit].
      - The sum of the bytes in String, Int,
        and Bytes sub-nodes of [node] exceeds
        [Global_constants_storage.bytes_size_limit].

      Otherwise returns false.  *)
    val node_too_large : Script.node -> bool

    (** [bottom_up_fold_cps initial_accumulator node initial_k f]
        folds [node] and all its sub-nodes if any, starting from
        [initial_accumulator], using an initial continuation [initial_k].
        At each node, [f] is called to transform the continuation [k] into
        the next one. This explicit manipulation of the continuation
        is typically useful to short-circuit.

        Notice that a common source of bug is to forget to properly call the
        continuation in `f`. *)
    val bottom_up_fold_cps :
      'accumulator ->
      'loc Script.michelson_node ->
      ('accumulator -> 'loc Script.michelson_node -> 'return) ->
      ('accumulator ->
      'loc Script.michelson_node ->
      ('accumulator -> 'loc Script.michelson_node -> 'return) ->
      'return) ->
      'return

    (** [expr_to_address_in_context context expr] converts [expr]
       into a unique hash represented by a [Script_expr_hash.t].

       Consumes gas corresponding to the cost of converting [expr]
       to bytes and hashing the bytes. *)
    val expr_to_address_in_context :
      t -> Script.expr -> (t * Script_expr_hash.t) tzresult
  end
end

module Cache : sig
  type size = int

  type index = int

  module Admin : sig
    type key

    type value

    val pp : Format.formatter -> context -> unit

    val set_cache_layout : context -> size list -> context Lwt.t

    val sync : context -> cache_nonce:Bytes.t -> context Lwt.t

    val clear : context -> context

    val future_cache_expectation : context -> time_in_blocks:int -> context

    val cache_size : context -> cache_index:int -> size option

    val cache_size_limit : context -> cache_index:int -> size option

    val value_of_key :
      context -> Context.Cache.key -> Context.Cache.value tzresult Lwt.t
  end

  type namespace = private string

  val create_namespace : string -> namespace

  type identifier = string

  module type CLIENT = sig
    type cached_value

    val cache_index : index

    val namespace : namespace

    val value_of_identifier :
      context -> identifier -> cached_value tzresult Lwt.t
  end

  module type INTERFACE = sig
    type cached_value

    val update :
      context -> identifier -> (cached_value * size) option -> context tzresult

    val find : context -> identifier -> cached_value option tzresult Lwt.t

    val list_identifiers : context -> (string * int) list

    val identifier_rank : context -> string -> int option

    val size : context -> int

    val size_limit : context -> int
  end

  val register_exn :
    (module CLIENT with type cached_value = 'a) ->
    (module INTERFACE with type cached_value = 'a)
end

module Level : sig
  type t = private {
    level : Raw_level.t;
    level_position : int32;
    cycle : Cycle.t;
    cycle_position : int32;
    expected_commitment : bool;
  }

  include BASIC_DATA with type t := t

  val pp_full : Format.formatter -> t -> unit

  type level = t

  val root : context -> level

  val succ : context -> level -> level

  val pred : context -> level -> level option

  val from_raw : context -> Raw_level.t -> level

  (** Fails with [Negative_level_and_offset_sum] if the sum of the raw_level and the offset is negative. *)
  val from_raw_with_offset :
    context -> offset:int32 -> Raw_level.t -> level tzresult

  (** [add c level i] i must be positive *)
  val add : context -> level -> int -> level

  (** [sub c level i] i must be positive *)
  val sub : context -> level -> int -> level option

  val diff : level -> level -> int32

  val current : context -> level

  val last_level_in_cycle : context -> Cycle.t -> level

  val levels_in_cycle : context -> Cycle.t -> level list

  val levels_in_current_cycle : context -> ?offset:int32 -> unit -> level list

  val last_allowed_fork_level : context -> Raw_level.t

  val dawn_of_a_new_cycle : context -> Cycle.t option

  val may_snapshot_rolls : context -> bool
end

module Fitness : sig
  type error += Invalid_fitness | Wrong_fitness | Outdated_fitness

  type raw = Fitness.t

  type t

  val encoding : t Data_encoding.t

  val pp : Format.formatter -> t -> unit

  val create :
    level:Raw_level.t ->
    locked_round:Round.t option ->
    predecessor_round:Round.t ->
    round:Round.t ->
    t tzresult

  val create_without_locked_round :
    level:Raw_level.t -> predecessor_round:Round.t -> round:Round.t -> t

  val to_raw : t -> raw

  val from_raw : raw -> t tzresult

  val round_from_raw : raw -> Round.t tzresult

  val predecessor_round_from_raw : raw -> Round.t tzresult

  val level : t -> Raw_level.t

  val round : t -> Round.t

  val locked_round : t -> Round.t option

  val predecessor_round : t -> Round.t
end

module Nonce : sig
  type t

  type nonce = t

  val encoding : nonce Data_encoding.t

  type unrevealed = {nonce_hash : Nonce_hash.t; delegate : public_key_hash}

  val record_hash : context -> unrevealed -> context tzresult Lwt.t

  val reveal : context -> Level.t -> nonce -> context tzresult Lwt.t

  type status = Unrevealed of unrevealed | Revealed of nonce

  val get : context -> Level.t -> status tzresult Lwt.t

  val of_bytes : bytes -> nonce tzresult

  val hash : nonce -> Nonce_hash.t

  val check_hash : nonce -> Nonce_hash.t -> bool
end

module Seed : sig
  type seed

  type error += Unknown of {oldest : Cycle.t; cycle : Cycle.t; latest : Cycle.t}

  val for_cycle : context -> Cycle.t -> seed tzresult Lwt.t

  val cycle_end :
    context -> Cycle.t -> (context * Nonce.unrevealed list) tzresult Lwt.t

  val seed_encoding : seed Data_encoding.t
end

module Big_map : sig
  module Id : sig
    type t

    val encoding : t Data_encoding.t

    val rpc_arg : t RPC_arg.arg

    (** In the protocol, to be used in parse_data only *)
    val parse_z : Z.t -> t

    (** In the protocol, to be used in unparse_data only *)
    val unparse_to_z : t -> Z.t
  end

  val fresh : temporary:bool -> context -> (context * Id.t) tzresult Lwt.t

  val mem :
    context -> Id.t -> Script_expr_hash.t -> (context * bool) tzresult Lwt.t

  val get_opt :
    context ->
    Id.t ->
    Script_expr_hash.t ->
    (context * Script.expr option) tzresult Lwt.t

  val exists :
    context ->
    Id.t ->
    (context * (Script.expr * Script.expr) option) tzresult Lwt.t

  (** [list_values ?offset ?length ctxt id] lists all values stored in big map [id].

      The first [offset] values are ignored (if passed). Negative offsets are treated as [0].

      There will be no more than [length] values in the result list (if passed).
      Negative values are treated as [0].

      The returned {!context} takes into account gas consumption of loading values.
  *)
  val list_values :
    ?offset:int ->
    ?length:int ->
    context ->
    Id.t ->
    (context * Script.expr list) tzresult Lwt.t

  type update = {
    key : Script_repr.expr;
    key_hash : Script_expr_hash.t;
    value : Script_repr.expr option;
  }

  type updates = update list

  type alloc = {key_type : Script_repr.expr; value_type : Script_repr.expr}
end

module Sapling : sig
  module Id : sig
    type t

    val encoding : t Data_encoding.t

    val rpc_arg : t RPC_arg.arg

    val parse_z : Z.t -> t (* To be used in parse_data only *)

    val unparse_to_z : t -> Z.t (* To be used in unparse_data only *)
  end

  val fresh : temporary:bool -> context -> (context * Id.t) tzresult Lwt.t

  type diff = private {
    commitments_and_ciphertexts :
      (Sapling.Commitment.t * Sapling.Ciphertext.t) list;
    nullifiers : Sapling.Nullifier.t list;
  }

  val diff_encoding : diff Data_encoding.t

  module Memo_size : sig
    type t

    val encoding : t Data_encoding.t

    val equal : t -> t -> bool

    val parse_z : Z.t -> (t, string) result

    val unparse_to_z : t -> Z.t
  end

  type state = private {id : Id.t option; diff : diff; memo_size : Memo_size.t}

  (**
    Returns a [state] with fields filled accordingly.
    [id] should only be used by [extract_lazy_storage_updates].
   *)
  val empty_state : ?id:Id.t -> memo_size:Memo_size.t -> unit -> state

  type transaction = Sapling.UTXO.transaction

  val transaction_encoding : transaction Data_encoding.t

  val transaction_get_memo_size : transaction -> Memo_size.t option

  (**
    Tries to fetch a state from the storage.
   *)
  val state_from_id : context -> Id.t -> (state * context) tzresult Lwt.t

  val rpc_arg : Id.t RPC_arg.t

  type root = Sapling.Hash.t

  val root_encoding : root Data_encoding.t

  (* Function exposed as RPC. Returns the root and a diff of a state starting
     from an optional offset which is zero by default. *)
  val get_diff :
    context ->
    Id.t ->
    ?offset_commitment:Int64.t ->
    ?offset_nullifier:Int64.t ->
    unit ->
    (root * diff) tzresult Lwt.t

  val verify_update :
    context ->
    state ->
    transaction ->
    string ->
    (context * (Int64.t * state) option) tzresult Lwt.t

  type alloc = {memo_size : Memo_size.t}

  type updates = diff

  val transaction_in_memory_size : transaction -> Cache_memory_helpers.sint

  val diff_in_memory_size : diff -> Cache_memory_helpers.sint
end

module Lazy_storage : sig
  module Kind : sig
    type ('id, 'alloc, 'updates) t =
      | Big_map : (Big_map.Id.t, Big_map.alloc, Big_map.updates) t
      | Sapling_state : (Sapling.Id.t, Sapling.alloc, Sapling.updates) t
  end

  module IdSet : sig
    type t

    type 'acc fold_f = {f : 'i 'a 'u. ('i, 'a, 'u) Kind.t -> 'i -> 'acc -> 'acc}

    val empty : t

    val mem : ('i, 'a, 'u) Kind.t -> 'i -> t -> bool

    val add : ('i, 'a, 'u) Kind.t -> 'i -> t -> t

    val diff : t -> t -> t

    val fold : ('i, 'a, 'u) Kind.t -> ('i -> 'acc -> 'acc) -> t -> 'acc -> 'acc

    val fold_all : 'acc fold_f -> t -> 'acc -> 'acc
  end

  type ('id, 'alloc) init = Existing | Copy of {src : 'id} | Alloc of 'alloc

  type ('id, 'alloc, 'updates) diff =
    | Remove
    | Update of {init : ('id, 'alloc) init; updates : 'updates}

  type diffs_item

  val make : ('i, 'a, 'u) Kind.t -> 'i -> ('i, 'a, 'u) diff -> diffs_item

  type diffs = diffs_item list

  val encoding : diffs Data_encoding.t

  val diffs_in_memory_size : diffs -> Cache_memory_helpers.nodes_and_size

  val legacy_big_map_diff_encoding : diffs Data_encoding.t

  val cleanup_temporaries : context -> context Lwt.t

  val apply : t -> diffs -> (t * Z.t) tzresult Lwt.t
end

module Contract : sig
  include BASIC_DATA

  type contract = t

  val in_memory_size : t -> Cache_memory_helpers.sint

  val rpc_arg : contract RPC_arg.arg

  val to_b58check : contract -> string

  val of_b58check : string -> contract tzresult

  val implicit_contract : public_key_hash -> contract

  val is_implicit : contract -> public_key_hash option

  val exists : context -> contract -> bool tzresult Lwt.t

  val must_exist : context -> contract -> unit tzresult Lwt.t

  val allocated : context -> contract -> bool tzresult Lwt.t

  val must_be_allocated : context -> contract -> unit tzresult Lwt.t

  val list : context -> contract list Lwt.t

  val get_manager_key :
    ?error:error -> context -> public_key_hash -> public_key tzresult Lwt.t

  val is_manager_key_revealed :
    context -> public_key_hash -> bool tzresult Lwt.t

  val reveal_manager_key :
    context -> public_key_hash -> public_key -> context tzresult Lwt.t

  val get_script_code :
    context -> contract -> (context * Script.lazy_expr option) tzresult Lwt.t

  val get_script :
    context -> contract -> (context * Script.t option) tzresult Lwt.t

  val get_storage :
    context -> contract -> (context * Script.expr option) tzresult Lwt.t

  val get_counter : context -> public_key_hash -> Z.t tzresult Lwt.t

  val get_balance : context -> contract -> Tez.t tzresult Lwt.t

  val get_balance_carbonated :
    context -> contract -> (context * Tez.t) tzresult Lwt.t

  val init_origination_nonce : context -> Operation_hash.t -> context

  val unset_origination_nonce : context -> context

  val fresh_contract_from_current_nonce : context -> (context * t) tzresult

  val originated_from_current_nonce :
    since:context -> until:context -> contract list tzresult Lwt.t

  module Legacy_big_map_diff : sig
    type item = private
      | Update of {
          big_map : Z.t;
          diff_key : Script.expr;
          diff_key_hash : Script_expr_hash.t;
          diff_value : Script.expr option;
        }
      | Clear of Z.t
      | Copy of {src : Z.t; dst : Z.t}
      | Alloc of {
          big_map : Z.t;
          key_type : Script.expr;
          value_type : Script.expr;
        }

    type t = private item list

    val of_lazy_storage_diff : Lazy_storage.diffs -> t
  end

  type error += Balance_too_low of contract * Tez.t * Tez.t

  val update_script_storage :
    context ->
    contract ->
    Script.expr ->
    Lazy_storage.diffs option ->
    context tzresult Lwt.t

  val used_storage_space : context -> t -> Z.t tzresult Lwt.t

  val increment_counter : context -> public_key_hash -> context tzresult Lwt.t

  val check_counter_increment :
    context -> public_key_hash -> Z.t -> unit tzresult Lwt.t

  (**/**)

  (* Only for testing *)
  type origination_nonce

  val initial_origination_nonce : Operation_hash.t -> origination_nonce

  val originated_contract : origination_nonce -> contract

  val raw_originate :
    context ->
    prepaid_bootstrap_storage:bool ->
    t ->
    script:Script.t * Lazy_storage.diffs option ->
    context tzresult Lwt.t
end

module Receipt : sig
  type balance =
    | Contract of Contract.t
    | Legacy_rewards of Signature.Public_key_hash.t * Cycle.t
    | Block_fees
    | Legacy_deposits of Signature.Public_key_hash.t * Cycle.t
    | Deposits of public_key_hash
    | Nonce_revelation_rewards
    | Double_signing_evidence_rewards
    | Endorsing_rewards
    | Baking_rewards
    | Baking_bonuses
    | Legacy_fees of Signature.Public_key_hash.t * Cycle.t
    | Storage_fees
    | Double_signing_punishments
    | Lost_endorsing_rewards of Signature.Public_key_hash.t * bool * bool
    | Liquidity_baking_subsidies
    | Burned
    | Commitments of Blinded_public_key_hash.t
    | Bootstrap
    | Invoice
    | Initial_commitments
    | Minted

  val compare_balance : balance -> balance -> int

  type balance_update = Debited of Tez.t | Credited of Tez.t

  type update_origin =
    | Block_application
    | Protocol_migration
    | Subsidy
    | Simulation

  val compare_update_origin : update_origin -> update_origin -> int

  type balance_updates = (balance * balance_update * update_origin) list

  val balance_updates_encoding : balance_updates Data_encoding.t

  val group_balance_updates : balance_updates -> balance_updates tzresult
end

module Delegate : sig
  val init :
    context ->
    Contract.t ->
    Signature.Public_key_hash.t ->
    context tzresult Lwt.t

  val find : context -> Contract.t -> public_key_hash option tzresult Lwt.t

  val set :
    context -> Contract.t -> public_key_hash option -> context tzresult Lwt.t

  val frozen_deposits_limit :
    context -> Signature.Public_key_hash.t -> Tez.t option tzresult Lwt.t

  val set_frozen_deposits_limit :
    context -> Signature.Public_key_hash.t -> Tez.t option -> context Lwt.t

  val fold :
    context ->
    order:[`Sorted | `Undefined] ->
    init:'a ->
    f:(public_key_hash -> 'a -> 'a Lwt.t) ->
    'a Lwt.t

  val list : context -> public_key_hash list Lwt.t

  val check_delegate : context -> public_key_hash -> unit tzresult Lwt.t

  type participation_info = {
    expected_cycle_activity : int;
    minimal_cycle_activity : int;
    missed_slots : int;
    missed_levels : int;
    remaining_allowed_missed_slots : int;
    expected_endorsing_rewards : Tez.t;
  }

  val delegate_participation_info :
    context -> public_key_hash -> participation_info tzresult Lwt.t

  val cycle_end :
    context ->
    Cycle.t ->
    Nonce.unrevealed list ->
    (context * Receipt.balance_updates * Signature.Public_key_hash.t list)
    tzresult
    Lwt.t

  val already_slashed_for_double_endorsing :
    context -> public_key_hash -> Level.t -> bool tzresult Lwt.t

  val already_slashed_for_double_baking :
    context -> public_key_hash -> Level.t -> bool tzresult Lwt.t

  val punish_double_endorsing :
    context ->
    public_key_hash ->
    Level.t ->
    (context * Tez.t * Receipt.balance_updates) tzresult Lwt.t

  val punish_double_baking :
    context ->
    public_key_hash ->
    Level.t ->
    (context * Tez.t * Receipt.balance_updates) tzresult Lwt.t

  val full_balance : context -> public_key_hash -> Tez.t tzresult Lwt.t

  type level_participation = Participated | Didn't_participate

  val record_baking_activity_and_pay_rewards_and_fees :
    context ->
    payload_producer:Signature.Public_key_hash.t ->
    block_producer:Signature.Public_key_hash.t ->
    baking_reward:Tez.t ->
    reward_bonus:Tez.t option ->
    (context * Receipt.balance_updates) tzresult Lwt.t

  val record_endorsing_participation :
    context ->
    delegate:Signature.Public_key_hash.t ->
    participation:level_participation ->
    endorsing_power:int ->
    context tzresult Lwt.t

  type deposits = {initial_amount : Tez.t; current_amount : Tez.t}

  val frozen_deposits : context -> public_key_hash -> deposits tzresult Lwt.t

  val staking_balance :
    context -> Signature.Public_key_hash.t -> Tez.t tzresult Lwt.t

  val delegated_contracts :
    context -> Signature.Public_key_hash.t -> Contract.t list Lwt.t

  val delegated_balance :
    context -> Signature.Public_key_hash.t -> Tez.t tzresult Lwt.t

  val registered : context -> Signature.Public_key_hash.t -> bool tzresult Lwt.t

  val deactivated :
    context -> Signature.Public_key_hash.t -> bool tzresult Lwt.t

  val grace_period :
    context -> Signature.Public_key_hash.t -> Cycle.t tzresult Lwt.t

  val pubkey : context -> public_key_hash -> public_key tzresult Lwt.t

  val prepare_stake_distribution : context -> context tzresult Lwt.t
end

module Voting_period : sig
  type kind = Proposal | Exploration | Cooldown | Promotion | Adoption

  val kind_encoding : kind Data_encoding.encoding

  val pp_kind : Format.formatter -> kind -> unit

  (* This type should be abstract *)
  type voting_period = private {
    index : int32;
    kind : kind;
    start_position : int32;
  }

  type t = voting_period

  include BASIC_DATA with type t := t

  val encoding : voting_period Data_encoding.t

  val pp : Format.formatter -> voting_period -> unit

  val reset : context -> context tzresult Lwt.t

  val succ : context -> context tzresult Lwt.t

  val get_current : context -> voting_period tzresult Lwt.t

  val get_current_kind : context -> kind tzresult Lwt.t

  val is_last_block : context -> bool tzresult Lwt.t

  type info = {voting_period : t; position : int32; remaining : int32}

  val info_encoding : info Data_encoding.t

  val pp_info : Format.formatter -> info -> unit

  val get_rpc_current_info : context -> info tzresult Lwt.t

  val get_rpc_succ_info : context -> info tzresult Lwt.t
end

module Vote : sig
  type proposal = Protocol_hash.t

  val record_proposal :
    context -> Protocol_hash.t -> public_key_hash -> context tzresult Lwt.t

  val get_proposals : context -> int32 Protocol_hash.Map.t tzresult Lwt.t

  val clear_proposals : context -> context Lwt.t

  val recorded_proposal_count_for_delegate :
    context -> public_key_hash -> int tzresult Lwt.t

  val listings_encoding :
    (Signature.Public_key_hash.t * int32) list Data_encoding.t

  val update_listings : context -> context tzresult Lwt.t

  val listing_size : context -> int32 tzresult Lwt.t

  val in_listings : context -> public_key_hash -> bool Lwt.t

  val get_listings : context -> (public_key_hash * int32) list Lwt.t

  type ballot = Yay | Nay | Pass

  val get_voting_power_free :
    context -> Signature.Public_key_hash.t -> int32 tzresult Lwt.t

  val get_voting_power :
    context -> Signature.Public_key_hash.t -> (context * int32) tzresult Lwt.t

  val get_total_voting_power_free : context -> int32 tzresult Lwt.t

  val get_total_voting_power : context -> (context * int32) tzresult Lwt.t

  val ballot_encoding : ballot Data_encoding.t

  type ballots = {yay : int32; nay : int32; pass : int32}

  val ballots_encoding : ballots Data_encoding.t

  val has_recorded_ballot : context -> public_key_hash -> bool Lwt.t

  val record_ballot :
    context -> public_key_hash -> ballot -> context tzresult Lwt.t

  val get_ballots : context -> ballots tzresult Lwt.t

  val get_ballot_list :
    context -> (Signature.Public_key_hash.t * ballot) list Lwt.t

  val clear_ballots : context -> context Lwt.t

  val get_current_quorum : context -> int32 tzresult Lwt.t

  val get_participation_ema : context -> int32 tzresult Lwt.t

  val set_participation_ema : context -> int32 -> context tzresult Lwt.t

  val get_current_proposal : context -> proposal tzresult Lwt.t

  val find_current_proposal : context -> proposal option tzresult Lwt.t

  val init_current_proposal : context -> proposal -> context tzresult Lwt.t

  val clear_current_proposal : context -> context tzresult Lwt.t
end

module Block_payload : sig
  val hash :
    predecessor:Block_hash.t ->
    Round.t ->
    Operation_list_hash.t ->
    Block_payload_hash.t
end

module Block_header : sig
  type contents = {
    payload_hash : Block_payload_hash.t;
    payload_round : Round.t;
    seed_nonce_hash : Nonce_hash.t option;
    proof_of_work_nonce : bytes;
    liquidity_baking_escape_vote : bool;
  }

  type protocol_data = {contents : contents; signature : Signature.t}

  type t = {shell : Block_header.shell_header; protocol_data : protocol_data}

  type block_header = t

  type raw = Block_header.t

  type shell_header = Block_header.shell_header

  type block_watermark = Block_header of Chain_id.t

  val to_watermark : block_watermark -> Signature.watermark

  val of_watermark : Signature.watermark -> block_watermark option

  module Proof_of_work : sig
    val check_hash : Block_hash.t -> int64 -> bool

    val check_header_proof_of_work_stamp :
      shell_header -> contents -> int64 -> bool

    val check_proof_of_work_stamp :
      proof_of_work_threshold:int64 -> block_header -> unit tzresult
  end

  val raw : block_header -> raw

  val hash : block_header -> Block_hash.t

  val hash_raw : raw -> Block_hash.t

  val encoding : block_header Data_encoding.encoding

  val raw_encoding : raw Data_encoding.t

  val contents_encoding : contents Data_encoding.t

  val unsigned_encoding : (shell_header * contents) Data_encoding.t

  val protocol_data_encoding : protocol_data Data_encoding.encoding

  val shell_header_encoding : shell_header Data_encoding.encoding

  (** The maximum size of block headers in bytes *)
  val max_header_length : int

  type error +=
    | Invalid_block_signature of Block_hash.t * Signature.Public_key_hash.t
    | Invalid_stamp
    | Invalid_payload_hash of {
        expected : Block_payload_hash.t;
        provided : Block_payload_hash.t;
      }
    | Locked_round_after_block_round of {
        locked_round : Round_repr.t;
        round : Round_repr.t;
      }
    | Invalid_payload_round of {
        payload_round : Round_repr.t;
        round : Round_repr.t;
      }
    | Insufficient_locked_round_evidence of {
        voting_power : int;
        consensus_threshold : int;
      }
    | Invalid_commitment of {expected : bool}

  val check_timestamp :
    Round.round_durations ->
    timestamp:Time.t ->
    round:Round.t ->
    predecessor_timestamp:Time.t ->
    predecessor_round:Round.t ->
    unit tzresult

  val check_signature :
    t -> Chain_id.t -> Signature.Public_key.t -> unit tzresult

  val begin_validate_block_header :
    block_header:t ->
    chain_id:Chain_id.t ->
    predecessor_timestamp:Time.t ->
    predecessor_round:Round.t ->
    fitness:Fitness.t ->
    timestamp:Time.t ->
    delegate_pk:Signature.public_key ->
    round_durations:Round.round_durations ->
    proof_of_work_threshold:int64 ->
    expected_commitment:bool ->
    unit tzresult

  type locked_round_evidence = {
    preendorsement_round : Round.t;
    preendorsement_count : int;
  }

  type checkable_payload_hash =
    | No_check
    | Expected_payload_hash of Block_payload_hash.t

  val finalize_validate_block_header :
    block_header_contents:contents ->
    round:Round.t ->
    fitness:Fitness.t ->
    checkable_payload_hash:checkable_payload_hash ->
    locked_round_evidence:locked_round_evidence option ->
    consensus_threshold:int ->
    unit tzresult
end

module Kind : sig
  type preendorsement_consensus_kind = Preendorsement_consensus_kind

  type endorsement_consensus_kind = Endorsement_consensus_kind

  type 'a consensus =
    | Preendorsement_kind : preendorsement_consensus_kind consensus
    | Endorsement_kind : endorsement_consensus_kind consensus

  type preendorsement = preendorsement_consensus_kind consensus

  type endorsement = endorsement_consensus_kind consensus

  type seed_nonce_revelation = Seed_nonce_revelation_kind

  type 'a double_consensus_operation_evidence =
    | Double_consensus_operation_evidence

  type double_endorsement_evidence =
    endorsement_consensus_kind double_consensus_operation_evidence

  type double_preendorsement_evidence =
    preendorsement_consensus_kind double_consensus_operation_evidence

  type double_baking_evidence = Double_baking_evidence_kind

  type activate_account = Activate_account_kind

  type proposals = Proposals_kind

  type ballot = Ballot_kind

  type reveal = Reveal_kind

  type transaction = Transaction_kind

  type origination = Origination_kind

  type delegation = Delegation_kind

  type set_deposits_limit = Set_deposits_limit_kind

  type failing_noop = Failing_noop_kind

  type register_global_constant = Register_global_constant_kind

  type 'a manager =
    | Reveal_manager_kind : reveal manager
    | Transaction_manager_kind : transaction manager
    | Origination_manager_kind : origination manager
    | Delegation_manager_kind : delegation manager
    | Register_global_constant_manager_kind : register_global_constant manager
    | Set_deposits_limit_manager_kind : set_deposits_limit manager
end

type 'a consensus_operation_type =
  | Endorsement : Kind.endorsement consensus_operation_type
  | Preendorsement : Kind.preendorsement consensus_operation_type

val pp_operation_kind :
  Format.formatter -> 'kind consensus_operation_type -> unit

type consensus_content = {
  slot : Slot.t;
  level : Raw_level.t;
  (* The level is not required to validate an endorsement when it corresponds
     to the current payload, but if we want to filter endorsements, we need
     the level. *)
  round : Round.t;
  block_payload_hash : Block_payload_hash.t;
}

val consensus_content_encoding : consensus_content Data_encoding.t

val pp_consensus_content : Format.formatter -> consensus_content -> unit

type 'kind operation = {
  shell : Operation.shell_header;
  protocol_data : 'kind protocol_data;
}

and 'kind protocol_data = {
  contents : 'kind contents_list;
  signature : Signature.t option;
}

and _ contents_list =
  | Single : 'kind contents -> 'kind contents_list
  | Cons :
      'kind Kind.manager contents * 'rest Kind.manager contents_list
      -> ('kind * 'rest) Kind.manager contents_list

and _ contents =
  | Preendorsement : consensus_content -> Kind.preendorsement contents
  | Endorsement : consensus_content -> Kind.endorsement contents
  | Seed_nonce_revelation : {
      level : Raw_level.t;
      nonce : Nonce.t;
    }
      -> Kind.seed_nonce_revelation contents
  | Double_preendorsement_evidence : {
      op1 : Kind.preendorsement operation;
      op2 : Kind.preendorsement operation;
    }
      -> Kind.double_preendorsement_evidence contents
  | Double_endorsement_evidence : {
      op1 : Kind.endorsement operation;
      op2 : Kind.endorsement operation;
    }
      -> Kind.double_endorsement_evidence contents
  | Double_baking_evidence : {
      bh1 : Block_header.t;
      bh2 : Block_header.t;
    }
      -> Kind.double_baking_evidence contents
  | Activate_account : {
      id : Ed25519.Public_key_hash.t;
      activation_code : Blinded_public_key_hash.activation_code;
    }
      -> Kind.activate_account contents
  | Proposals : {
      source : Signature.Public_key_hash.t;
      period : int32;
      proposals : Protocol_hash.t list;
    }
      -> Kind.proposals contents
  | Ballot : {
      source : Signature.Public_key_hash.t;
      period : int32;
      proposal : Protocol_hash.t;
      ballot : Vote.ballot;
    }
      -> Kind.ballot contents
  | Failing_noop : string -> Kind.failing_noop contents
  | Manager_operation : {
      source : Signature.Public_key_hash.t;
      fee : Tez.tez;
      counter : counter;
      operation : 'kind manager_operation;
      gas_limit : Gas.Arith.integral;
      storage_limit : Z.t;
    }
      -> 'kind Kind.manager contents

and _ manager_operation =
  | Reveal : Signature.Public_key.t -> Kind.reveal manager_operation
  | Transaction : {
      amount : Tez.tez;
      parameters : Script.lazy_expr;
      entrypoint : string;
      destination : Contract.contract;
    }
      -> Kind.transaction manager_operation
  | Origination : {
      delegate : Signature.Public_key_hash.t option;
      script : Script.t;
      credit : Tez.tez;
      preorigination : Contract.t option;
    }
      -> Kind.origination manager_operation
  | Delegation :
      Signature.Public_key_hash.t option
      -> Kind.delegation manager_operation
  | Register_global_constant : {
      value : Script.lazy_expr;
    }
      -> Kind.register_global_constant manager_operation
  | Set_deposits_limit :
      Tez.t option
      -> Kind.set_deposits_limit manager_operation

and counter = Z.t

type 'kind internal_operation = {
  source : Contract.contract;
  operation : 'kind manager_operation;
  nonce : int;
}

type packed_manager_operation =
  | Manager : 'kind manager_operation -> packed_manager_operation

type packed_contents = Contents : 'kind contents -> packed_contents

type packed_contents_list =
  | Contents_list : 'kind contents_list -> packed_contents_list

type packed_protocol_data =
  | Operation_data : 'kind protocol_data -> packed_protocol_data

type packed_operation = {
  shell : Operation.shell_header;
  protocol_data : packed_protocol_data;
}

type packed_internal_operation =
  | Internal_operation : 'kind internal_operation -> packed_internal_operation

val manager_kind : 'kind manager_operation -> 'kind Kind.manager

module Operation : sig
  type nonrec 'kind contents = 'kind contents

  type nonrec packed_contents = packed_contents

  val contents_encoding : packed_contents Data_encoding.t

  type nonrec 'kind protocol_data = 'kind protocol_data

  type nonrec packed_protocol_data = packed_protocol_data

  type consensus_watermark =
    | Endorsement of Chain_id.t
    | Preendorsement of Chain_id.t

  val to_watermark : consensus_watermark -> Signature.watermark

  val of_watermark : Signature.watermark -> consensus_watermark option

  val protocol_data_encoding : packed_protocol_data Data_encoding.t

  val unsigned_encoding :
    (Operation.shell_header * packed_contents_list) Data_encoding.t

  type raw = Operation.t = {shell : Operation.shell_header; proto : bytes}

  val raw_encoding : raw Data_encoding.t

  val contents_list_encoding : packed_contents_list Data_encoding.t

  type 'kind t = 'kind operation = {
    shell : Operation.shell_header;
    protocol_data : 'kind protocol_data;
  }

  type nonrec packed = packed_operation

  val encoding : packed Data_encoding.t

  val raw : _ operation -> raw

  val hash : _ operation -> Operation_hash.t

  val hash_raw : raw -> Operation_hash.t

  val hash_packed : packed_operation -> Operation_hash.t

  val acceptable_passes : packed_operation -> int list

  type error += Missing_signature (* `Permanent *)

  type error += Invalid_signature (* `Permanent *)

  val check_signature : public_key -> Chain_id.t -> _ operation -> unit tzresult

  val internal_operation_encoding : packed_internal_operation Data_encoding.t

  val packed_internal_operation_in_memory_size :
    packed_internal_operation -> Cache_memory_helpers.nodes_and_size

  val pack : 'kind operation -> packed_operation

  type ('a, 'b) eq = Eq : ('a, 'a) eq

  val equal : 'a operation -> 'b operation -> ('a, 'b) eq option

  module Encoding : sig
    type 'b case =
      | Case : {
          tag : int;
          name : string;
          encoding : 'a Data_encoding.t;
          select : packed_contents -> 'b contents option;
          proj : 'b contents -> 'a;
          inj : 'a -> 'b contents;
        }
          -> 'b case

    val preendorsement_case : Kind.preendorsement case

    val endorsement_case : Kind.endorsement case

    val seed_nonce_revelation_case : Kind.seed_nonce_revelation case

    val double_preendorsement_evidence_case :
      Kind.double_preendorsement_evidence case

    val double_endorsement_evidence_case : Kind.double_endorsement_evidence case

    val double_baking_evidence_case : Kind.double_baking_evidence case

    val activate_account_case : Kind.activate_account case

    val proposals_case : Kind.proposals case

    val ballot_case : Kind.ballot case

    val failing_noop_case : Kind.failing_noop case

    val reveal_case : Kind.reveal Kind.manager case

    val transaction_case : Kind.transaction Kind.manager case

    val origination_case : Kind.origination Kind.manager case

    val delegation_case : Kind.delegation Kind.manager case

    val register_global_constant_case :
      Kind.register_global_constant Kind.manager case

    val set_deposits_limit_case : Kind.set_deposits_limit Kind.manager case

    module Manager_operations : sig
      type 'b case =
        | MCase : {
            tag : int;
            name : string;
            encoding : 'a Data_encoding.t;
            select : packed_manager_operation -> 'kind manager_operation option;
            proj : 'kind manager_operation -> 'a;
            inj : 'a -> 'kind manager_operation;
          }
            -> 'kind case

      val reveal_case : Kind.reveal case

      val transaction_case : Kind.transaction case

      val origination_case : Kind.origination case

      val delegation_case : Kind.delegation case

      val register_global_constant_case : Kind.register_global_constant case

      val set_deposits_limit_case : Kind.set_deposits_limit case
    end
  end

  val of_list : packed_contents list -> packed_contents_list tzresult

  val to_list : packed_contents_list -> packed_contents list
end

module Stake_distribution : sig
  val snapshot : context -> context tzresult Lwt.t

  val baking_rights_owner :
    context ->
    Level.t ->
    round:Round.t ->
    (context * Slot.t * (public_key * public_key_hash)) tzresult Lwt.t

  val slot_owner :
    context ->
    Level.t ->
    Slot.t ->
    (context * (public_key * public_key_hash)) tzresult Lwt.t

  val delegate_pubkey : context -> public_key_hash -> public_key tzresult Lwt.t

  val get_staking_balance :
    context -> Signature.Public_key_hash.t -> Tez.t tzresult Lwt.t
end

module Commitment : sig
  type t = {
    blinded_public_key_hash : Blinded_public_key_hash.t;
    amount : Tez.tez;
  }

  val encoding : t Data_encoding.t
end

module Bootstrap : sig
  val cycle_end : context -> Cycle.t -> context tzresult Lwt.t
end

module Migration : sig
  type origination_result = {
    balance_updates : Receipt.balance_updates;
    originated_contracts : Contract.t list;
    storage_size : Z.t;
    paid_storage_size_diff : Z.t;
  }
end

(** Create an [Alpha_context.t] from an untyped context (first block in the chain only). *)
val prepare_first_block :
  Context.t ->
  typecheck:
    (context ->
    Script.t ->
    ((Script.t * Lazy_storage.diffs option) * context) tzresult Lwt.t) ->
  level:Int32.t ->
  timestamp:Time.t ->
  context tzresult Lwt.t

(** Create an [Alpha_context.t] from an untyped context. *)
val prepare :
  Context.t ->
  level:Int32.t ->
  predecessor_timestamp:Time.t ->
  timestamp:Time.t ->
  (context * Receipt.balance_updates * Migration.origination_result list)
  tzresult
  Lwt.t

val activate : context -> Protocol_hash.t -> context Lwt.t

val reset_internal_nonce : context -> context

val fresh_internal_nonce : context -> (context * int) tzresult

val record_internal_nonce : context -> int -> context

val internal_nonce_already_recorded : context -> int -> bool

val description : context Storage_description.t

(** Finalize an {{!t} [Alpha_context.t]}, producing a [validation_result].
 *)
val finalize :
  ?commit_message:string -> context -> Fitness.raw -> Updater.validation_result

(** Should only be used by [Main.current_context] to return a context usable for RPCs *)
val current_context : context -> Context.t

val record_non_consensus_operation_hash : context -> Operation_hash.t -> context

val non_consensus_operations : context -> Operation_hash.t list

module Parameters : sig
  type bootstrap_account = {
    public_key_hash : public_key_hash;
    public_key : public_key option;
    amount : Tez.t;
  }

  type bootstrap_contract = {
    delegate : public_key_hash option;
    amount : Tez.t;
    script : Script.t;
  }

  type t = {
    bootstrap_accounts : bootstrap_account list;
    bootstrap_contracts : bootstrap_contract list;
    commitments : Commitment.t list;
    constants : Constants.parametric;
    security_deposit_ramp_up_cycles : int option;
    no_reward_cycles : int option;
  }

  val encoding : t Data_encoding.t
end

module Liquidity_baking : sig
  val get_cpmm_address : context -> Contract.t tzresult Lwt.t

  type escape_ema = Int32.t

  val on_subsidy_allowed :
    context ->
    escape_vote:bool ->
    (context -> Contract.t -> (context * 'a list) tzresult Lwt.t) ->
    (context * 'a list * escape_ema) tzresult Lwt.t
end

(** This module re-exports functions from [Ticket_storage]. See
    documentation of the functions there.
 *)
module Ticket_balance : sig
  type key_hash

  val script_expr_hash_of_key_hash : key_hash -> Script_expr_hash.t

  val make_key_hash :
    context ->
    ticketer:Script.node ->
    typ:Script.node ->
    contents:Script.node ->
    owner:Script.node ->
    (key_hash * context) tzresult

  val adjust_balance :
    context -> key_hash -> delta:Z.t -> (Z.t * context) tzresult Lwt.t

  val get_balance : context -> key_hash -> (Z.t option * context) tzresult Lwt.t
end

module First_level_of_tenderbake : sig
  val get : context -> Raw_level.t tzresult Lwt.t
end

module Consensus : sig
  include
    Raw_context.CONSENSUS
      with type t := t
       and type slot := Slot.t
       and type 'a slot_map := 'a Slot.Map.t
       and type slot_set := Slot.Set.t
       and type round := Round.t

  val store_endorsement_branch :
    context -> Block_hash.t * Block_payload_hash.t -> context Lwt.t

  val store_grand_parent_branch :
    context -> Block_hash.t * Block_payload_hash.t -> context Lwt.t
end

(** See 'token.mli' for more explanation. *)
module Token : sig
  type container =
    [ `Contract of Contract.t
    | `Collected_commitments of Blinded_public_key_hash.t
    | `Delegate_balance of Signature.Public_key_hash.t
    | `Frozen_deposits of Signature.Public_key_hash.t
    | `Block_fees
    | `Legacy_deposits of Signature.Public_key_hash.t * Cycle.t
    | `Legacy_fees of Signature.Public_key_hash.t * Cycle.t
    | `Legacy_rewards of Signature.Public_key_hash.t * Cycle.t ]

  type source =
    [ `Invoice
    | `Bootstrap
    | `Initial_commitments
    | `Revelation_rewards
    | `Double_signing_evidence_rewards
    | `Endorsing_rewards
    | `Baking_rewards
    | `Baking_bonuses
    | `Minted
    | `Liquidity_baking_subsidies
    | container ]

  type sink =
    [ `Storage_fees
    | `Double_signing_punishments
    | `Lost_endorsing_rewards of Signature.Public_key_hash.t * bool * bool
    | `Burned
    | container ]

  val allocated : context -> container -> bool tzresult Lwt.t

  val balance : context -> container -> Tez.t tzresult Lwt.t

  val transfer_n :
    ?origin:Receipt.update_origin ->
    context ->
    ([< source] * Tez.t) list ->
    [< sink] ->
    (context * Receipt.balance_updates) tzresult Lwt.t

  val transfer :
    ?origin:Receipt.update_origin ->
    context ->
    [< source] ->
    [< sink] ->
    Tez.t ->
    (context * Receipt.balance_updates) tzresult Lwt.t
end

module Fees : sig
  val record_paid_storage_space :
    context -> Contract.t -> (context * Z.t * Z.t) tzresult Lwt.t

  val record_global_constant_storage_space : context -> Z.t -> context * Z.t

  val burn_storage_fees :
    ?origin:Receipt.update_origin ->
    context ->
    storage_limit:Z.t ->
    payer:Token.source ->
    Z.t ->
    (context * Z.t * Receipt.balance_updates) tzresult Lwt.t

  val burn_origination_fees :
    ?origin:Receipt.update_origin ->
    context ->
    storage_limit:Z.t ->
    payer:Token.source ->
    (context * Z.t * Receipt.balance_updates) tzresult Lwt.t

  type error += Cannot_pay_storage_fee (* `Temporary *)

  type error += Operation_quota_exceeded (* `Temporary *)

  type error += Storage_limit_too_high (* `Permanent *)

  val check_storage_limit : context -> storage_limit:Z.t -> unit tzresult
end
