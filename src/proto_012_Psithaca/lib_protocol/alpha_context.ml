(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>           *)
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

type t = Raw_context.t

type context = t

module type BASIC_DATA = sig
  type t

  include Compare.S with type t := t

  val encoding : t Data_encoding.t

  val pp : Format.formatter -> t -> unit
end

module Tez = Tez_repr
module Period = Period_repr

module Timestamp = struct
  include Time_repr

  let current = Raw_context.current_timestamp

  let predecessor = Raw_context.predecessor_timestamp
end

module Slot = struct
  include Slot_repr

  let slot_range = List.slot_range
end

include Operation_repr

module Operation = struct
  type 'kind t = 'kind operation = {
    shell : Operation.shell_header;
    protocol_data : 'kind protocol_data;
  }

  type packed = packed_operation

  let unsigned_encoding = unsigned_operation_encoding

  include Operation_repr
end

module Block_header = Block_header_repr

module Vote = struct
  include Vote_repr
  include Vote_storage
end

module Block_payload = struct
  include Block_payload_repr
end

module First_level_of_tenderbake = struct
  let get = Storage.Tenderbake.First_level.get
end

module Raw_level = Raw_level_repr
module Cycle = Cycle_repr
module Script_string = Script_string_repr
module Script_int = Script_int_repr

module Script_timestamp = struct
  include Script_timestamp_repr

  let now ctxt =
    let {Constants_repr.minimal_block_delay; _} = Raw_context.constants ctxt in
    let first_delay = Period_repr.to_seconds minimal_block_delay in
    let current_timestamp = Raw_context.predecessor_timestamp ctxt in
    Time.add current_timestamp first_delay |> Timestamp.to_seconds |> of_int64
end

module Script = struct
  include Michelson_v1_primitives
  include Script_repr

  type consume_deserialization_gas = Always | When_needed

  let force_decode_in_context ~consume_deserialization_gas ctxt lexpr =
    let gas_cost =
      match consume_deserialization_gas with
      | Always -> Script_repr.stable_force_decode_cost lexpr
      | When_needed -> Script_repr.force_decode_cost lexpr
    in
    Raw_context.consume_gas ctxt gas_cost >>? fun ctxt ->
    Script_repr.force_decode lexpr >|? fun v -> (v, ctxt)

  let force_bytes_in_context ctxt lexpr =
    Raw_context.consume_gas ctxt (Script_repr.force_bytes_cost lexpr)
    >>? fun ctxt ->
    Script_repr.force_bytes lexpr >|? fun v -> (v, ctxt)
end

module Fees = Fees_storage

type public_key = Signature.Public_key.t

type public_key_hash = Signature.Public_key_hash.t

type signature = Signature.t

module Constants = struct
  include Constants_repr
  include Constants_storage

  let round_durations ctxt = Raw_context.round_durations ctxt

  let all ctxt = all (parametric ctxt)
end

module Voting_period = struct
  include Voting_period_repr
  include Voting_period_storage
end

module Round = struct
  include Round_repr
  module Durations = Durations

  type round_durations = Durations.t

  let pp_round_durations = Durations.pp

  let round_durations_encoding = Durations.encoding

  let round_duration = Round_repr.Durations.round_duration

  let update ctxt round = Storage.Block_round.update ctxt round

  let get ctxt = Storage.Block_round.get ctxt
end

module Gas = struct
  include Gas_limit_repr

  type error += Gas_limit_too_high = Raw_context.Gas_limit_too_high

  type error += Block_quota_exceeded = Raw_context.Block_quota_exceeded

  type error += Operation_quota_exceeded = Raw_context.Operation_quota_exceeded

  let check_limit_is_valid = Raw_context.check_gas_limit_is_valid

  let set_limit = Raw_context.set_gas_limit

  let consume_limit_in_block = Raw_context.consume_gas_limit_in_block

  let set_unlimited = Raw_context.set_gas_unlimited

  let consume = Raw_context.consume_gas

  let remaining_operation_gas = Raw_context.remaining_operation_gas

  let update_remaining_operation_gas =
    Raw_context.update_remaining_operation_gas

  let reset_block_gas ctxt =
    let gas = Constants.hard_gas_limit_per_block ctxt in
    Raw_context.update_remaining_block_gas ctxt gas

  let level = Raw_context.gas_level

  let consumed = Raw_context.gas_consumed

  let block_level = Raw_context.block_gas_level

  (* Necessary to inject costs for Storage_costs into Gas.cost *)
  let cost_of_repr cost = cost
end

module Level = struct
  include Level_repr
  include Level_storage
end

module Lazy_storage = struct
  module Kind = Lazy_storage_kind
  module IdSet = Kind.IdSet
  include Lazy_storage_diff

  let legacy_big_map_diff_encoding =
    Data_encoding.conv
      Contract_storage.Legacy_big_map_diff.of_lazy_storage_diff
      Contract_storage.Legacy_big_map_diff.to_lazy_storage_diff
      Contract_storage.Legacy_big_map_diff.encoding
end

module Contract = struct
  include Contract_repr
  include Contract_storage

  let init_origination_nonce = Raw_context.init_origination_nonce

  let unset_origination_nonce = Raw_context.unset_origination_nonce

  let is_manager_key_revealed = Contract_manager_storage.is_manager_key_revealed

  let reveal_manager_key = Contract_manager_storage.reveal_manager_key

  let get_manager_key = Contract_manager_storage.get_manager_key
end

module Global_constants_storage = Global_constants_storage

module Big_map = struct
  module Big_map = Lazy_storage_kind.Big_map

  module Id = struct
    type t = Big_map.Id.t

    let encoding = Big_map.Id.encoding

    let rpc_arg = Big_map.Id.rpc_arg

    let parse_z = Big_map.Id.parse_z

    let unparse_to_z = Big_map.Id.unparse_to_z
  end

  let fresh ~temporary c = Lazy_storage.fresh Big_map ~temporary c

  let mem c m k = Storage.Big_map.Contents.mem (c, m) k

  let get_opt c m k = Storage.Big_map.Contents.find (c, m) k

  let list_values ?offset ?length c m =
    Storage.Big_map.Contents.list_values ?offset ?length (c, m)

  let exists c id =
    Raw_context.consume_gas c (Gas_limit_repr.read_bytes_cost 0) >>?= fun c ->
    Storage.Big_map.Key_type.find c id >>=? fun kt ->
    match kt with
    | None -> return (c, None)
    | Some kt ->
        Storage.Big_map.Value_type.get c id >|=? fun kv -> (c, Some (kt, kv))

  type update = Big_map.update = {
    key : Script_repr.expr;
    key_hash : Script_expr_hash.t;
    value : Script_repr.expr option;
  }

  type updates = Big_map.updates

  type alloc = Big_map.alloc = {
    key_type : Script_repr.expr;
    value_type : Script_repr.expr;
  }
end

module Sapling = struct
  module Sapling_state = Lazy_storage_kind.Sapling_state

  module Id = struct
    type t = Sapling_state.Id.t

    let encoding = Sapling_state.Id.encoding

    let rpc_arg = Sapling_state.Id.rpc_arg

    let parse_z = Sapling_state.Id.parse_z

    let unparse_to_z = Sapling_state.Id.unparse_to_z
  end

  include Sapling_repr
  include Sapling_storage
  include Sapling_validator

  let fresh ~temporary c = Lazy_storage.fresh Sapling_state ~temporary c

  type updates = Sapling_state.updates

  type alloc = Sapling_state.alloc = {memo_size : Sapling_repr.Memo_size.t}
end

module Receipt = Receipt_repr

module Delegate = struct
  include Delegate_storage

  type deposits = Storage.deposits = {
    initial_amount : Tez.t;
    current_amount : Tez.t;
  }

  let grace_period = Delegate_activation_storage.grace_period

  let prepare_stake_distribution = Stake_storage.prepare_stake_distribution

  let registered = Contract_delegate_storage.registered

  let find = Contract_delegate_storage.find

  let delegated_contracts = Contract_delegate_storage.delegated_contracts
end

module Stake_distribution = struct
  let snapshot = Stake_storage.snapshot

  let baking_rights_owner = Delegate.baking_rights_owner

  let slot_owner = Delegate.slot_owner

  let delegate_pubkey = Delegate.pubkey

  let get_staking_balance = Delegate.staking_balance
end

module Nonce = Nonce_storage

module Seed = struct
  include Seed_repr
  include Seed_storage
end

module Fitness = struct
  type raw = Fitness.t

  include Fitness_repr
end

module Bootstrap = Bootstrap_storage

module Commitment = struct
  include Commitment_repr
  include Commitment_storage
end

module Migration = Migration_repr

module Consensus = struct
  include Raw_context.Consensus

  let load_endorsement_branch ctxt =
    Storage.Tenderbake.Endorsement_branch.find ctxt >>=? function
    | Some endorsement_branch ->
        Raw_context.Consensus.set_endorsement_branch ctxt endorsement_branch
        |> return
    | None -> return ctxt

  let store_endorsement_branch ctxt branch =
    let ctxt = set_endorsement_branch ctxt branch in
    Storage.Tenderbake.Endorsement_branch.add ctxt branch

  let load_grand_parent_branch ctxt =
    Storage.Tenderbake.Grand_parent_branch.find ctxt >>=? function
    | Some grand_parent_branch ->
        Raw_context.Consensus.set_grand_parent_branch ctxt grand_parent_branch
        |> return
    | None -> return ctxt

  let store_grand_parent_branch ctxt branch =
    let ctxt = set_grand_parent_branch ctxt branch in
    Storage.Tenderbake.Grand_parent_branch.add ctxt branch
end

let prepare_first_block = Init_storage.prepare_first_block

let prepare ctxt ~level ~predecessor_timestamp ~timestamp =
  Init_storage.prepare ctxt ~level ~predecessor_timestamp ~timestamp
  >>=? fun (ctxt, balance_updates, origination_results) ->
  Consensus.load_endorsement_branch ctxt >>=? fun ctxt ->
  Consensus.load_grand_parent_branch ctxt >>=? fun ctxt ->
  return (ctxt, balance_updates, origination_results)

let finalize ?commit_message:message c fitness =
  let context = Raw_context.recover c in
  {
    Updater.context;
    fitness;
    message;
    max_operations_ttl = (Raw_context.constants c).max_operations_time_to_live;
    last_allowed_fork_level =
      Raw_level.to_int32 @@ Level.last_allowed_fork_level c;
  }

let current_context c = Raw_context.recover c

let record_non_consensus_operation_hash =
  Raw_context.record_non_consensus_operation_hash

let non_consensus_operations = Raw_context.non_consensus_operations

let activate = Raw_context.activate

let reset_internal_nonce = Raw_context.reset_internal_nonce

let fresh_internal_nonce = Raw_context.fresh_internal_nonce

let record_internal_nonce = Raw_context.record_internal_nonce

let internal_nonce_already_recorded =
  Raw_context.internal_nonce_already_recorded

let description = Raw_context.description

module Parameters = Parameters_repr
module Liquidity_baking = Liquidity_baking_repr

module Ticket_balance = struct
  include Ticket_storage
end

module Token = Token
module Cache = Cache_repr
