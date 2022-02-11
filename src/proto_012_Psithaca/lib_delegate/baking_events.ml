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

let section = [Protocol.name; "baker"]

let pp_int32 fmt n = Format.fprintf fmt "%ld" n

let pp_int64 fmt n = Format.fprintf fmt "%Ld" n

module State_transitions = struct
  include Internal_event.Simple

  let section = section @ ["transitions"]

  let new_head_with_increasing_level =
    declare_0
      ~section
      ~name:"new_head_with_increasing_level"
      ~level:Info
      ~msg:"received new head with level increasing"
      ()

  let no_proposal_slot =
    declare_1
      ~section
      ~name:"no_proposal_slot"
      ~level:Notice
      ~msg:"no proposal slot at round {round}"
      ~pp1:Round.pp
      ("round", Round.encoding)

  let proposal_slot =
    declare_2
      ~section
      ~name:"proposal_slot"
      ~level:Notice
      ~msg:"proposal slot at round {round} for {delegate}"
      ~pp1:Round.pp
      ("round", Round.encoding)
      ~pp2:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let new_head_while_waiting_for_qc =
    declare_0
      ~section
      ~name:"new_head_while_waiting_for_qc"
      ~level:Info
      ~msg:"received new head while waiting for a quorum"
      ()

  let unexpected_proposal_round =
    declare_2
      ~section
      ~name:"unexpected_proposal_round"
      ~level:Info
      ~msg:
        "unexpected proposal round, expected: {expected_round}, got: \
         {proposal_round}"
      ~pp1:Round.pp
      ("expected_round", Round.encoding)
      ~pp2:Round.pp
      ("proposal_round", Round.encoding)

  let proposal_for_round_already_seen =
    declare_3
      ~section
      ~name:"proposal_for_round_already_seen"
      ~level:Warning
      ~msg:
        "proposal {new_proposal} for current round ({current_round}) has \
         already been seen {previous_proposal}"
      ~pp1:Block_hash.pp
      ("new_proposal", Block_hash.encoding)
      ~pp2:Round.pp
      ("current_round", Round.encoding)
      ~pp3:Block_hash.pp
      ("previous_proposal", Block_hash.encoding)

  let updating_latest_proposal =
    declare_1
      ~section
      ~name:"updating_latest_proposal"
      ~msg:"updating latest proposal to {block_hash}"
      ~level:Info
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)

  let baker_is_ahead_of_node =
    declare_2
      ~section
      ~name:"baker_is_ahead"
      ~level:Info
      ~msg:
        "baker (level: {baker_level}) is ahead of the node (level: \
         {node_level})"
      ~pp1:pp_int32
      ("baker_level", Data_encoding.int32)
      ~pp2:pp_int32
      ("node_level", Data_encoding.int32)

  let new_proposal_is_on_another_branch =
    declare_2
      ~section
      ~name:"new_proposal_is_on_another_branch"
      ~level:Info
      ~msg:
        "received a proposal on another branch - current: current \
         pred{current_branch}, new pred {new_branch}"
      ~pp1:Block_hash.pp
      ("current_branch", Block_hash.encoding)
      ~pp2:Block_hash.pp
      ("new_branch", Block_hash.encoding)

  let switching_branch =
    declare_0
      ~section
      ~name:"switching_branch"
      ~level:Info
      ~msg:"switching branch"
      ()

  let branch_proposal_has_better_fitness =
    declare_0
      ~section
      ~name:"branch_proposal_has_better_fitness"
      ~level:Info
      ~msg:"different branch proposal has a better fitness than us"
      ()

  let branch_proposal_has_no_prequorum =
    declare_0
      ~section
      ~name:"branch_proposal_has_no_prequorum"
      ~level:Info
      ~msg:"different branch proposal has no prequorum but we do"
      ()

  let branch_proposal_has_lower_prequorum =
    declare_0
      ~section
      ~name:"branch_proposal_has_lower_prequorum"
      ~level:Info
      ~msg:"different branch proposal has a lower prequorum than us"
      ()

  let branch_proposal_has_better_prequorum =
    declare_0
      ~section
      ~name:"branch_proposal_has_better_prequorum"
      ~level:Info
      ~msg:"different branch proposal has a better prequorum"
      ()

  let branch_proposal_has_same_prequorum =
    declare_0
      ~section
      ~name:"branch_proposal_has_same_prequorum"
      ~level:Error
      ~msg:"different branch proposal has the same prequorum"
      ()

  let preendorsing_proposal =
    declare_1
      ~section
      ~name:"preendorsing_proposal"
      ~level:Info
      ~msg:"preendorsing proposal {block_hash}"
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)

  let skipping_invalid_proposal =
    declare_0
      ~section
      ~name:"skipping_invalid_proposal"
      ~level:Info
      ~msg:"invalid proposal, skipping"
      ()

  let outdated_proposal =
    declare_1
      ~section
      ~name:"outdated_proposal"
      ~level:Debug
      ~msg:"outdated proposal {block_hash}"
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)

  let proposing_fresh_block =
    declare_2
      ~section
      ~name:"proposing_fresh_block"
      ~level:Info
      ~msg:"proposing fresh block for {delegate} at round {round}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)
      ~pp2:Round.pp
      ("round", Round.encoding)

  let no_endorsable_payload_fresh_block =
    declare_0
      ~section
      ~name:"no_endorsable_payload_fresh_block"
      ~level:Info
      ~msg:"no endorsable payload, proposing fresh block"
      ()

  let repropose_block =
    declare_1
      ~section
      ~name:"repropose_block"
      ~level:Info
      ~msg:"repropose block with payload {payload}"
      ~pp1:Block_payload_hash.pp
      ("payload", Block_payload_hash.encoding)

  let unexpected_prequorum_received =
    declare_2
      ~section
      ~name:"unexpected_prequorum_received"
      ~level:Info
      ~msg:
        "unexpected prequorum received for {received_hash} instead of \
         {expected_hash}"
      ~pp1:Block_hash.pp
      ("received_hash", Block_hash.encoding)
      ~pp2:Block_hash.pp
      ("expected_hash", Block_hash.encoding)

  let unexpected_quorum_received =
    declare_2
      ~section
      ~name:"unexpected_quorum_received"
      ~level:Info
      ~msg:
        "unexpected quorum received for {received_hash} instead of \
         {expected_hash}"
      ~pp1:Block_hash.pp
      ("received_hash", Block_hash.encoding)
      ~pp2:Block_hash.pp
      ("expected_hash", Block_hash.encoding)

  let step_current_phase =
    declare_2
      ~section
      ~name:"step_current_phase"
      ~level:Debug
      ~msg:"automaton step: current phase {phase}, event {event}"
      ~pp1:Baking_state.pp_phase
      ("phase", Baking_state.phase_encoding)
      ~pp2:Baking_state.pp_event
      ("event", Baking_state.event_encoding)
end

module Node_rpc = struct
  include Internal_event.Simple

  let section = section @ ["rpc"]

  let error_while_monitoring_heads =
    declare_1
      ~section
      ~name:"error_while_monitoring_heads"
      ~level:Error
      ~msg:"error while monitoring heads {trace}"
      ~pp1:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let raw_info =
    declare_2
      ~section
      ~name:"raw_info"
      ~level:Debug
      ~msg:"raw info for {block_hash} at level {level}"
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)
      ~pp2:pp_int32
      ("level", Data_encoding.int32)
end

module Scheduling = struct
  include Internal_event.Simple

  let section = section @ ["scheduling"]

  let error_while_baking =
    declare_1
      ~section
      ~name:"error_while_baking"
      ~level:Warning
      ~msg:"error while baking {trace}"
      ~pp1:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let waiting_for_new_head =
    declare_0
      ~section
      ~name:"waiting_for_new_head"
      ~level:Info
      ~msg:"no possible timeout, waiting for a new head to arrive..."
      ()

  let compute_next_timeout_elected_block =
    declare_2
      ~section
      ~name:"compute_next_timeout_elected_block"
      ~level:Debug
      ~msg:
        "found an elected block at level {level}, round {round}... checking \
         baking rights"
      ~pp1:pp_int32
      ("level", Data_encoding.int32)
      ~pp2:Round.pp
      ("round", Round.encoding)

  let proposal_already_injected =
    declare_0
      ~section
      ~name:"proposal_already_injected"
      ~level:Debug
      ~msg:"proposal already injected for next level round, skipping..."
      ()

  let next_potential_slot =
    declare_4
      ~section
      ~name:"next_potential_slot"
      ~level:Info
      ~msg:
        "next potential slot for level {level} is at round {round} at \
         {timestamp} for {delegate}"
      ~pp1:pp_int32
      ("level", Data_encoding.int32)
      ~pp2:Round.pp
      ("round", Round.encoding)
      ~pp3:Timestamp.pp
      ("timestamp", Timestamp.encoding)
      ~pp4:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let waiting_end_of_round =
    declare_3
      ~section
      ~name:"waiting_end_of_round"
      ~level:Info
      ~msg:"waiting {timespan} until end of round {round} at {timestamp}"
      ~pp1:Ptime.Span.pp
      ("timespan", Time.System.Span.encoding)
      ~pp2:pp_int32
      ("round", Data_encoding.int32)
      ~pp3:Timestamp.pp
      ("timestamp", Timestamp.encoding)

  let waiting_delayed_end_of_round =
    declare_4
      ~section
      ~name:"waiting_delayed_end_of_round"
      ~level:Info
      ~msg:
        "waiting {timespan} until {timestamp} (end of round {round} plus \
         {delay}s delay)"
      ~pp1:Ptime.Span.pp
      ("timespan", Time.System.Span.encoding)
      ~pp2:pp_int32
      ("round", Data_encoding.int32)
      ~pp3:Timestamp.pp
      ("timestamp", Timestamp.encoding)
      ~pp4:pp_int64
      ("delay", Data_encoding.int64)

  let waiting_time_to_bake =
    declare_2
      ~section
      ~name:"waiting_time_to_bake"
      ~level:Info
      ~msg:"waiting {timespan} until it's time to bake at {timestamp}"
      ~pp1:Ptime.Span.pp
      ("timespan", Time.System.Span.encoding)
      ~pp2:Timestamp.pp
      ("timestamp", Timestamp.encoding)

  let no_need_to_wait_for_proposal =
    declare_0
      ~section
      ~name:"no_need_to_wait_for_proposal"
      ~level:Info
      ~msg:"no need to wait to propose a block"
      ()

  let state_synchronized_to_round =
    declare_1
      ~section
      ~name:"state_synchronized_to_round"
      ~level:Debug
      ~msg:"state synchronized to round {round}"
      ~pp1:Round.pp
      ("round", Round.encoding)

  let proposal_in_the_future =
    declare_1
      ~section
      ~name:"proposal_in_the_future"
      ~level:Debug
      ~msg:"received proposal in the future {block_hash}"
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)

  let process_proposal_in_the_future =
    declare_1
      ~section
      ~name:"process_proposal_in_the_future"
      ~level:Debug
      ~msg:"process proposal received in the future with hash {block_hash}"
      ~pp1:Block_hash.pp
      ("block_hash", Block_hash.encoding)
end

module Lib = struct
  include Internal_event.Simple

  let section = section @ ["lib"]

  let preendorsing_proposal =
    declare_1
      ~section
      ~name:"preendorsing_proposal"
      ~level:Debug
      ~msg:"preendorsing proposal {proposal}"
      ~pp1:Baking_state.pp_proposal
      ("proposal", Baking_state.proposal_encoding)

  let endorsing_proposal =
    declare_1
      ~section
      ~name:"endorsing_proposal"
      ~level:Debug
      ~msg:"endorsing proposal {proposal}"
      ~pp1:Baking_state.pp_proposal
      ("proposal", Baking_state.proposal_encoding)
end

module Actions = struct
  include Internal_event.Simple

  let section = section @ ["actions"]

  let skipping_preendorsement =
    declare_2
      ~section
      ~name:"skipping_preendorsement"
      ~level:Error
      ~msg:"skipping preendorsement for {delegate} -- {trace}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)
      ~pp2:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let skipping_endorsement =
    declare_2
      ~section
      ~name:"skipping_endorsement"
      ~level:Error
      ~msg:"skipping endorsement for {delegate} -- {trace}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)
      ~pp2:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let failed_to_inject_preendorsement =
    declare_2
      ~section
      ~name:"failed_to_inject_preendorsement"
      ~level:Error
      ~msg:"failed to inject preendorsement for {delegate} -- {trace}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)
      ~pp2:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let potential_double_baking =
    declare_2
      ~section
      ~name:"potential_double_baking"
      ~level:Warning
      ~msg:"potential double baking detected at level {level}, round {round}"
      ~pp1:pp_int32
      ~pp2:Round.pp
      ("level", Data_encoding.int32)
      ("round", Round.encoding)

  let preendorsement_injected =
    declare_2
      ~section
      ~name:"preendorsement_injected"
      ~level:Info
      ~msg:"injected preendorsement {ophash} for {delegate}"
      ~pp1:Operation_hash.pp
      ("ophash", Operation_hash.encoding)
      ~pp2:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let endorsement_injected =
    declare_2
      ~section
      ~name:"endorsement_injected"
      ~level:Info
      ~msg:"injected endorsement {ophash} for {delegate}"
      ~pp1:Operation_hash.pp
      ("ophash", Operation_hash.encoding)
      ~pp2:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let synchronizing_round =
    declare_1
      ~section
      ~name:"synchronizing_round"
      ~level:Info
      ~msg:"synchronizing round after block {block}"
      ~pp1:Block_hash.pp
      ("block", Block_hash.encoding)

  let forging_block =
    declare_3
      ~section
      ~name:"forging_block"
      ~level:Info
      ~msg:
        "forging block at level {level}, round {round} for delegate {delegate}"
      ~pp1:pp_int32
      ~pp2:Round.pp
      ~pp3:Baking_state.pp_delegate
      ("level", Data_encoding.int32)
      ("round", Round.encoding)
      ("delegate", Baking_state.delegate_encoding)

  let injecting_block =
    declare_3
      ~section
      ~name:"injecting_block"
      ~level:Debug
      ~msg:
        "injecting block at level {level}, round {round} for delegate \
         {delegate}"
      ~pp1:pp_int32
      ~pp2:Round.pp
      ~pp3:Baking_state.pp_delegate
      ("level", Data_encoding.int32)
      ("round", Round.encoding)
      ("delegate", Baking_state.delegate_encoding)

  let block_injected =
    declare_2
      ~section
      ~name:"block_injected"
      ~level:Notice
      ~msg:"block {block} injected for delegate {delegate}"
      ~pp1:Block_hash.pp
      ~pp2:Baking_state.pp_delegate
      ("block", Block_hash.encoding)
      ("delegate", Baking_state.delegate_encoding)

  let signing_preendorsement =
    declare_1
      ~section
      ~name:"signing_preendorsement"
      ~level:Info
      ~msg:"signing preendorsement for {delegate}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let signing_endorsement =
    declare_1
      ~section
      ~name:"signing_endorsement"
      ~level:Info
      ~msg:"signing endorsement for {delegate}"
      ~pp1:Baking_state.pp_delegate
      ("delegate", Baking_state.delegate_encoding)

  let invalid_json_file =
    declare_1
      ~section
      ~name:"invalid_json_file"
      ~level:Warning
      ~msg:"{filename} is not a valid JSON file"
      ("filename", Data_encoding.string)

  let no_mempool_found_in_file =
    declare_1
      ~section
      ~name:"no_mempool_found_in_file"
      ~level:Warning
      ~msg:"no mempool found in file {filename}"
      ("filename", Data_encoding.string)

  let cannot_fetch_mempool =
    declare_1
      ~section
      ~name:"cannot_fetch_mempool"
      ~level:Error
      ~msg:"cannot fetch mempool: {errs}"
      ("errs", Error_monad.(TzTrace.encoding error_encoding))
end

module Nonces = struct
  include Internal_event.Simple

  let section = section @ ["nonces"]

  let found_nonce_to_reveal =
    declare_2
      ~section
      ~name:"found_nonce_to_reveal"
      ~level:Notice
      ~msg:"found nonce to reveal for block {block}, level {level}"
      ~pp1:Block_hash.pp
      ("block", Block_hash.encoding)
      ~pp2:pp_int32
      ("level", Data_encoding.int32)

  let revealing_nonce =
    declare_3
      ~section
      ~name:"revealing_nonce"
      ~level:Notice
      ~msg:
        "revaling nonce of level {level} (chain {chain} with operation \
         {ophash})"
      ~pp1:pp_int32
      ("level", Data_encoding.int32)
      ~pp2:Format.pp_print_string
      ("chain", Data_encoding.string)
      ~pp3:Operation_hash.pp
      ("ophash", Operation_hash.encoding)

  let cannot_fetch_chain_head_level =
    declare_0
      ~section
      ~name:"cannot_fetch_chain_head_level"
      ~level:Error
      ~msg:"cannot fetch chain head level, aborting nonces filtering"
      ()

  let incoherent_nonce =
    declare_1
      ~section
      ~name:"incoherent_nonce"
      ~level:Error
      ~msg:"incoherent nonce for level {level}"
      ~pp1:pp_int32
      ("level", Data_encoding.int32)

  let cannot_read_nonces =
    declare_1
      ~section
      ~name:"cannot_read_nonces"
      ~level:Error
      ~msg:"cannot read nonces {trace}"
      ~pp1:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let cannot_retrieve_unrevealed_nonces =
    declare_1
      ~section
      ~name:"cannot_retrieve_unrevealed_nonces"
      ~level:Error
      ~msg:"cannot retrieve unrevealed nonces {trace}"
      ~pp1:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let cannot_inject_nonces =
    declare_1
      ~section
      ~name:"cannot_inject_nonces"
      ~level:Error
      ~msg:"cannot inject nonces {trace}"
      ~pp1:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let cant_retrieve_block_header_for_nonce =
    declare_2
      ~section
      ~name:"cant_retrieve_block_header_for_nonce"
      ~level:Warning
      ~msg:
        "cannot retrieved block header {header} associated with nonce {trace}"
      ("header", Data_encoding.string)
      ~pp2:Error_monad.pp_print_trace
      ("trace", Error_monad.trace_encoding)

  let too_many_nonces =
    declare_1
      ~section
      ~name:"too_many_nonces"
      ~level:Warning
      ~msg:
        "too many nonces associated with blocks unknown by node in \
         '$TEZOS_CLIENT/{filename}'. After checking that these blocks were \
         never included in the chain (e.g., via a block explorer), consider \
         using `tezos-client filter orphan nonces` to clear them."
      ("filename", Data_encoding.string)

  let registering_nonce =
    declare_1
      ~section
      ~name:"registering_nonce"
      ~level:Info
      ~msg:"registering nonce for block {block}"
      ~pp1:Block_hash.pp
      ("block", Block_hash.encoding)

  let nothing_to_reveal =
    declare_1
      ~section
      ~name:"nothing_to_reveal"
      ~level:Info
      ~msg:"nothing to reveal for block {block}"
      ~pp1:Block_hash.pp
      ("block", Block_hash.encoding)

  let revelation_worker_started =
    declare_0
      ~section
      ~name:"revelation_worker_started"
      ~level:Info
      ~msg:"revelation worker started"
      ()
end

module Liquidity_baking = struct
  include Internal_event.Simple

  let reading_per_block =
    declare_1
      ~section
      ~name:"reading_per_block"
      ~level:Notice
      ~msg:"reading per block vote file path: {path}"
      ("path", Data_encoding.string)

  let per_block_vote_file_notice =
    declare_1
      ~section
      ~name:"per_block_vote_file_notice"
      ~level:Notice
      ~msg:"per block vote file {event}"
      ("event", Data_encoding.string)

  let reading_liquidity_baking =
    declare_0
      ~section
      ~name:"reading_liquidity_baking"
      ~level:Notice
      ~msg:"reading liquidity baking escape vote"
      ()

  let liquidity_baking_escape_vote =
    declare_1
      ~section
      ~name:"liquidity_baking_escape_vote"
      ~level:Notice
      ~msg:"liquidity baking escape vote = {value}"
      ("value", Data_encoding.bool)

  let per_block_vote_file_fail =
    declare_1
      ~section
      ~name:"per_block_vote_file_error"
      ~level:Notice
      ~msg:"Error reading the block vote file: {errors}"
      ~pp1:pp_print_top_error_of_trace
      ("errors", Error_monad.(TzTrace.encoding error_encoding))

  let liquidity_baking_escape =
    declare_0
      ~section
      ~name:"liquidity_baking_continue"
      ~level:Notice
      ~msg:"Will vote to escape Liquidity Baking"
      ()

  let liquidity_baking_continue =
    declare_0
      ~section
      ~name:"liquidity_baking_escape"
      ~level:Notice
      ~msg:"Will vote to continue Liquidity Baking"
      ()
end
