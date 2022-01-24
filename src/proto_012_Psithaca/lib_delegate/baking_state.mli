(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Protocol
open Alpha_context

type delegate = {
  alias : string option;
  public_key : Signature.public_key;
  public_key_hash : Signature.public_key_hash;
  secret_key_uri : Client_keys.sk_uri;
}

val delegate_encoding : delegate Data_encoding.t

val pp_delegate : Format.formatter -> delegate -> unit

type validation_mode = Node | Local of Abstract_context_index.t

type prequorum = {
  level : int32;
  round : Round.t;
  block_payload_hash : Block_payload_hash.t;
  preendorsements : Kind.preendorsement operation list;
}

type block_info = {
  hash : Block_hash.t;
  shell : Block_header.shell_header;
  payload_hash : Block_payload_hash.t;
  payload_round : Round.t;
  round : Round.t;
  protocol : Protocol_hash.t;
  next_protocol : Protocol_hash.t;
  prequorum : prequorum option;
  quorum : Kind.endorsement operation list;
  payload : Operation_pool.payload;
  live_blocks : Block_hash.Set.t;
      (** Set of live blocks for this block that is used to filter
          old or too recent operations. *)
}

type cache = {
  known_timestamps : Timestamp.time Baking_cache.Timestamp_of_round_cache.t;
  round_timestamps :
    (Timestamp.time * Round.t * delegate)
    Baking_cache.Round_timestamp_interval_cache.t;
}

type global_state = {
  cctxt : Protocol_client_context.full;
  chain_id : Chain_id.t;
  config : Baking_configuration.t;
  constants : Constants.t;
  round_durations : Round.round_durations;
  operation_worker : Operation_worker.t;
  validation_mode : validation_mode;
  delegates : delegate list;
  cache : cache;
}

val block_info_encoding : block_info Data_encoding.t

val round_of_shell_header : Block_header.shell_header -> Round.t tzresult

module SlotMap : Map.S with type key = Slot.t

type endorsing_slot = {
  delegate : Signature.public_key_hash;
  slots : Slot.t trace;
  endorsing_power : int;
}

type delegate_slots = {
  own_delegate_slots : (delegate * endorsing_slot) SlotMap.t;
  all_delegate_slots : endorsing_slot SlotMap.t;
  all_slots_by_round : Slot.t array;
}

type proposal = {block : block_info; predecessor : block_info}

val proposal_encoding : proposal Data_encoding.t

type locked_round = {payload_hash : Block_payload_hash.t; round : Round.t}

val locked_round_encoding : locked_round Data_encoding.t

type endorsable_payload = {proposal : proposal; prequorum : prequorum}

val endorsable_payload_encoding : endorsable_payload Data_encoding.t

type elected_block = {
  proposal : proposal;
  endorsement_qc : Kind.endorsement operation list;
}

type level_state = {
  current_level : int32;
  latest_proposal : proposal;
  locked_round : locked_round option;
  endorsable_payload : endorsable_payload option;
  elected_block : elected_block option;
  delegate_slots : delegate_slots;
  next_level_delegate_slots : delegate_slots;
  next_level_proposed_round : Round.t option;
}

type phase = Idle | Awaiting_preendorsements | Awaiting_endorsements

val phase_encoding : phase Data_encoding.t

type round_state = {current_round : Round.t; current_phase : phase}

type state = {
  global_state : global_state;
  level_state : level_state;
  round_state : round_state;
}

type t = state

type timeout_kind =
  | End_of_round of {ending_round : Round.t}
  | Time_to_bake_next_level of {at_round : Round.t}

val timeout_kind_encoding : timeout_kind Data_encoding.t

type voting_power = int

type event =
  | New_proposal of proposal
  | Prequorum_reached of
      Operation_worker.candidate
      * voting_power
      * Kind.preendorsement operation list
  | Quorum_reached of
      Operation_worker.candidate
      * voting_power
      * Kind.endorsement operation list
  | Timeout of timeout_kind

val event_encoding : event Data_encoding.t

type state_data = {
  level_data : int32;
  locked_round_data : locked_round option;
  endorsable_payload_data : endorsable_payload option;
}

val state_data_encoding : state_data Data_encoding.t

val record_state : t -> unit tzresult Lwt.t

val may_record_new_state :
  previous_state:t -> new_state:t -> unit tzresult Lwt.t

val load_endorsable_data :
  Protocol_client_context.full ->
  [`State] Baking_files.location ->
  state_data option tzresult Lwt.t

val may_load_endorsable_data : t -> t tzresult Lwt.t

val compute_delegate_slots :
  Protocol_client_context.full ->
  delegate trace ->
  level:int32 ->
  chain:Shell_services.chain ->
  delegate_slots tzresult Lwt.t

val create_cache : unit -> cache

val pp_validation_mode : Format.formatter -> validation_mode -> unit

val pp_global_state : Format.formatter -> global_state -> unit

val pp_option :
  (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a option -> unit

val pp_block_info : Format.formatter -> block_info -> unit

val pp_proposal : Format.formatter -> proposal -> unit

val pp_locked_round : Format.formatter -> locked_round -> unit

val pp_endorsable_payload : Format.formatter -> endorsable_payload -> unit

val pp_elected_block : Format.formatter -> elected_block -> unit

val pp_endorsing_slot : Format.formatter -> delegate * endorsing_slot -> unit

val pp_delegate_slots : Format.formatter -> delegate_slots -> unit

val pp_level_state : Format.formatter -> level_state -> unit

val pp_phase : Format.formatter -> phase -> unit

val pp_round_state : Format.formatter -> round_state -> unit

val pp : Format.formatter -> t -> unit

val pp_timeout_kind : Format.formatter -> timeout_kind -> unit

val pp_event : Format.formatter -> event -> unit
