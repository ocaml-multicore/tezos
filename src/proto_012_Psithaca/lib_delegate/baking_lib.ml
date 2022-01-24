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

open Protocol
open Alpha_context
open Baking_state

let create_state cctxt ?synchronize ?monitor_node_mempool ~config
    ~current_proposal delegates =
  let chain = cctxt#chain in
  let monitor_node_operations = monitor_node_mempool in
  Operation_worker.create ?monitor_node_operations cctxt
  >>= fun operation_worker ->
  Baking_scheduling.create_initial_state
    cctxt
    ?synchronize
    ~chain
    config
    operation_worker
    ~current_proposal
    delegates

let get_current_proposal cctxt =
  Node_rpc.monitor_proposals cctxt ~chain:cctxt#chain ()
  >>=? fun (block_stream, _block_stream_stopper) ->
  Lwt_stream.peek block_stream >>= function
  | Some current_head -> return (block_stream, current_head)
  | None -> failwith "head stream unexpectedly ended"

module Events = Baking_events.Lib

let preendorse (cctxt : Protocol_client_context.full) ?(force = false) delegates
    =
  let open State_transitions in
  get_current_proposal cctxt >>=? fun (_, current_proposal) ->
  let config = Baking_configuration.make ~force () in
  create_state cctxt ~config ~current_proposal delegates >>=? fun state ->
  let proposal = state.level_state.latest_proposal in
  Events.(emit preendorsing_proposal state.level_state.latest_proposal)
  >>= fun () ->
  (if force then return_unit
  else
    is_acceptable_proposal_for_current_level state proposal >>= function
    | Invalid -> cctxt#error "Cannot preendorse an invalid proposal"
    | Outdated_proposal -> cctxt#error "Cannot preendorse an outdated proposal"
    | Valid_proposal -> return_unit)
  >>=? fun () ->
  let consensus_list = make_consensus_list state proposal in
  cctxt#message
    "@[<v 2>Preendorsing for:@ %a@]"
    Format.(pp_print_list ~pp_sep:pp_print_space Baking_state.pp_delegate)
    (List.map fst consensus_list)
  >>= fun () ->
  let state_recorder ~new_state =
    Baking_state.may_record_new_state ~previous_state:state ~new_state
  in
  Baking_actions.inject_preendorsements
    ~state_recorder
    state
    ~preendorsements:consensus_list
    ~updated_state:state
  >>=? fun _ -> return_unit

let endorse (cctxt : Protocol_client_context.full) ?(force = false) delegates =
  let open State_transitions in
  get_current_proposal cctxt >>=? fun (_, current_proposal) ->
  let config = Baking_configuration.make ~force () in
  create_state cctxt ~config ~current_proposal delegates >>=? fun state ->
  let proposal = state.level_state.latest_proposal in
  Events.(emit endorsing_proposal state.level_state.latest_proposal)
  >>= fun () ->
  (if force then return_unit
  else
    is_acceptable_proposal_for_current_level state proposal >>= function
    | Invalid -> cctxt#error "Cannot endorse an invalid proposal"
    | Outdated_proposal -> cctxt#error "Cannot endorse an outdated proposal"
    | Valid_proposal -> return_unit)
  >>=? fun () ->
  let consensus_list = make_consensus_list state proposal in
  cctxt#message
    "@[<v 2>Endorsing for:@ %a@]"
    Format.(pp_print_list ~pp_sep:pp_print_space Baking_state.pp_delegate)
    (List.map fst consensus_list)
  >>= fun () ->
  let state_recorder ~new_state =
    Baking_state.may_record_new_state ~previous_state:state ~new_state
  in
  Baking_actions.inject_endorsements
    ~state_recorder
    state
    ~endorsements:consensus_list
    ~updated_state:state
  >>=? fun _ -> return_unit

let bake_at_next_level state =
  let cctxt = state.global_state.cctxt in
  Baking_scheduling.compute_next_potential_baking_time_at_next_level state
  >>= function
  | None -> cctxt#error "No baking slot found for the delegates"
  | Some (timestamp, round) ->
      cctxt#message
        "Waiting until %a for round %a"
        Timestamp.pp
        timestamp
        Round.pp
        round
      >>= fun () ->
      Option.value
        ~default:Lwt.return_unit
        (Baking_scheduling.sleep_until timestamp)
      >>= fun () ->
      return (Baking_state.Timeout (Time_to_bake_next_level {at_round = round}))

(* Simulate the end of the current round to bootstrap the automaton
   or endorse the block if necessary *)
let first_automaton_event state =
  match state.level_state.elected_block with
  | None -> Lwt.return (Baking_scheduling.compute_bootstrap_event state)
  | Some _elected_block ->
      (* If there is an elected block we can directly bake at next
         level after waiting its date *)
      bake_at_next_level state

let endorsements_endorsing_power state endorsements =
  let get_endorsement_voting_power {slot; _} =
    match
      SlotMap.find slot state.level_state.delegate_slots.all_delegate_slots
    with
    | None -> assert false
    | Some {endorsing_power; _} -> endorsing_power
  in
  List.sort_uniq compare endorsements
  |> List.fold_left
       (fun power endorsement ->
         power + get_endorsement_voting_power endorsement)
       0

let generic_endorsing_power (filter : packed_operation list -> 'a list)
    (extract : 'a -> consensus_content) state =
  let current_mempool =
    Operation_worker.get_current_operations state.global_state.operation_worker
  in
  let latest_proposal = state.level_state.latest_proposal in
  let block_round = latest_proposal.block.round in
  let shell_level = latest_proposal.block.shell.level in
  let endorsements =
    filter (Operation_pool.Operation_set.elements current_mempool.consensus)
  in
  let endorsements_in_mempool =
    List.filter_map
      (fun v ->
        let consensus_content = extract v in
        if
          Round.(consensus_content.round = block_round)
          && Compare.Int32.(
               Raw_level.to_int32 consensus_content.level = shell_level)
        then Some consensus_content
        else None)
      endorsements
  in
  let power = endorsements_endorsing_power state endorsements_in_mempool in
  (power, endorsements)

let state_endorsing_power =
  generic_endorsing_power
    Operation_pool.filter_endorsements
    (fun
      ({
         protocol_data = {contents = Single (Endorsement consensus_content); _};
         _;
       } :
        Kind.endorsement operation)
    -> consensus_content)

let do_action (state, action) =
  let state_recorder ~new_state =
    Baking_state.may_record_new_state ~previous_state:state ~new_state
  in
  Baking_actions.perform_action ~state_recorder state action

let propose_at_next_level ~minimal_timestamp state =
  let cctxt = state.global_state.cctxt in
  assert (Option.is_some state.level_state.elected_block) ;
  if minimal_timestamp then
    (match
       Baking_scheduling.first_potential_round_at_next_level
         state
         ~earliest_round:Round.zero
     with
    | None -> cctxt#error "No potential baking slot for the given delegates."
    | Some first_potential_round -> return first_potential_round)
    >>=? fun (minimal_round, delegate) ->
    let pool =
      Operation_worker.get_current_operations
        state.global_state.operation_worker
    in
    let kind = Baking_actions.Fresh pool in
    let block_to_bake : Baking_actions.block_to_bake =
      {
        Baking_actions.predecessor = state.level_state.latest_proposal.block;
        round = minimal_round;
        delegate;
        kind;
      }
    in
    let state_recorder ~new_state =
      Baking_state.may_record_new_state ~previous_state:state ~new_state
    in
    Baking_actions.perform_action
      ~state_recorder
      state
      (Inject_block {block_to_bake; updated_state = state})
    >>=? fun state ->
    cctxt#message
      "Proposed block at round %a on top of %a "
      Round.pp
      block_to_bake.round
      Block_hash.pp
      block_to_bake.predecessor.hash
    >>= fun () -> return state
  else
    bake_at_next_level state >>=? fun event ->
    State_transitions.step state event >>= do_action >>=? fun state ->
    cctxt#message "Proposal injected" >>= fun () -> return state

let endorsement_quorum state =
  let (power, endorsements) = state_endorsing_power state in
  if
    Compare.Int.(
      power >= state.global_state.constants.parametric.consensus_threshold)
  then Some (power, endorsements)
  else None

(* Here's the sketch of the algorithm:
   Do I have an endorsement quorum for the current block or an elected block?
   - Yes :: wait and propose at next level
   - No  ::
     Is the current proposal at the right round?
     - Yes :: fail propose
     - No  ::
       Is there a preendorsement quorum or does the last proposal contain a prequorum?
       - Yes :: repropose block with right payload and preendorsements for current round
       - No  :: repropose fresh block for current round *)
let propose (cctxt : Protocol_client_context.full) ?minimal_fees
    ?minimal_nanotez_per_gas_unit ?minimal_nanotez_per_byte ?force
    ?(minimal_timestamp = false) ?extra_operations ?context_path delegates =
  get_current_proposal cctxt >>=? fun (_block_stream, current_proposal) ->
  let config =
    Baking_configuration.make
      ?minimal_fees
      ?minimal_nanotez_per_gas_unit
      ?minimal_nanotez_per_byte
      ?context_path
      ?force
      ?extra_operations
      ()
  in
  create_state cctxt ~config ~current_proposal delegates >>=? fun state ->
  (match state.level_state.elected_block with
  | Some _ -> propose_at_next_level ~minimal_timestamp state
  | None -> (
      match endorsement_quorum state with
      | Some (voting_power, endorsement_qc) ->
          let state =
            {
              state with
              round_state =
                {
                  state.round_state with
                  current_phase = Baking_state.Awaiting_endorsements;
                };
            }
          in
          let latest_proposal = state.level_state.latest_proposal.block in
          let candidate =
            {
              Operation_worker.hash = latest_proposal.hash;
              round_watched = latest_proposal.round;
              payload_hash_watched = latest_proposal.payload_hash;
            }
          in
          State_transitions.step
            state
            (Baking_state.Quorum_reached
               (candidate, voting_power, endorsement_qc))
          >>= do_action
          (* this will register the elected block *)
          >>=? fun state -> propose_at_next_level ~minimal_timestamp state
      | None -> (
          Baking_scheduling.compute_bootstrap_event state >>?= fun event ->
          State_transitions.step state event >>= fun (state, _action) ->
          let latest_proposal = state.level_state.latest_proposal in
          let open State_transitions in
          let round = state.round_state.current_round in
          is_acceptable_proposal_for_current_level state latest_proposal
          >>= function
          | Invalid | Outdated_proposal -> (
              let slotmap =
                state.level_state.delegate_slots.own_delegate_slots
              in
              match State_transitions.round_proposer state slotmap round with
              | Some (delegate, _) ->
                  State_transitions.repropose_block_action
                    state
                    delegate
                    round
                    state.level_state.latest_proposal
                  >>= fun action ->
                  do_action (state, action) >>=? fun state ->
                  cctxt#message
                    "Reproposed block at level %ld on round %a"
                    state.level_state.current_level
                    Round.pp
                    state.round_state.current_round
                  >>= fun () -> return state
              | None -> cctxt#error "No slots for current round")
          | Valid_proposal ->
              cctxt#error
                "Cannot propose: there's already a valid proposal for the \
                 current round %a"
                Round.pp
                round)))
  >>=? fun _ -> return_unit

let bake_using_automaton config state block_stream =
  let cctxt = state.global_state.cctxt in
  first_automaton_event state >>=? fun initial_event ->
  let current_level = state.level_state.latest_proposal.block.shell.level in
  let loop_state =
    Baking_scheduling.create_loop_state
      block_stream
      state.global_state.operation_worker
  in
  let stop_on_next_level_block = function
    | New_proposal proposal ->
        Compare.Int32.(proposal.block.shell.level >= Int32.succ current_level)
    | _ -> false
  in
  Baking_scheduling.automaton_loop
    ~stop_on_event:stop_on_next_level_block
    ~config
    ~on_error:(fun err -> Lwt.return (Error err))
    loop_state
    state
    initial_event
  >>=? function
  | Some (New_proposal proposal) ->
      cctxt#message
        "Block %a (%ld) injected"
        Block_hash.pp
        proposal.block.hash
        proposal.block.shell.level
      >>= fun () -> return_unit
  | _ -> cctxt#error "Baking loop unexpectedly ended"

(* endorse the latest proposal and bake with it *)
let baking_minimal_timestamp state =
  let cctxt = state.global_state.cctxt in
  let latest_proposal = state.level_state.latest_proposal in
  let own_endorsements =
    State_transitions.make_consensus_list state latest_proposal
  in
  let current_mempool =
    Operation_worker.get_current_operations state.global_state.operation_worker
  in
  let endorsements_in_mempool =
    Operation_pool.(
      filter_endorsements (Operation_set.elements current_mempool.consensus))
    |> List.filter_map
         (fun
           ({
              protocol_data =
                {contents = Single (Endorsement consensus_content); _};
              _;
            } :
             Kind.endorsement operation)
         ->
           if
             Round.(consensus_content.round = latest_proposal.block.round)
             && Compare.Int32.(
                  Raw_level.to_int32 consensus_content.level
                  = latest_proposal.block.shell.level)
           then Some consensus_content
           else None)
  in
  let total_voting_power =
    List.fold_left
      (fun endorsements own -> snd own :: endorsements)
      endorsements_in_mempool
      own_endorsements
    |> endorsements_endorsing_power state
  in
  let consensus_threshold =
    state.global_state.constants.parametric.consensus_threshold
  in
  (if Compare.Int.(total_voting_power < consensus_threshold) then
   cctxt#error
     "Delegates do not have enough voting power. Only %d is available while %d \
      is required."
     total_voting_power
     consensus_threshold
  else return_unit)
  >>=? fun () ->
  (match
     Baking_scheduling.first_potential_round_at_next_level
       state
       ~earliest_round:Round.zero
   with
  | None -> cctxt#error "No potential baking slot for the given delegates."
  | Some first_potential_round -> return first_potential_round)
  >>=? fun (minimal_round, delegate) ->
  Baking_actions.sign_endorsements state own_endorsements
  >>=? fun signed_endorsements ->
  let pool =
    Operation_pool.add_operations
      current_mempool
      (List.map snd signed_endorsements)
  in
  let kind = Baking_actions.Fresh pool in
  let block_to_bake : Baking_actions.block_to_bake =
    {
      Baking_actions.predecessor = latest_proposal.block;
      round = minimal_round;
      delegate;
      kind;
    }
  in
  let state_recorder ~new_state =
    Baking_state.may_record_new_state ~previous_state:state ~new_state
  in
  Baking_actions.perform_action
    ~state_recorder
    state
    (Inject_block {block_to_bake; updated_state = state})
  >>=? fun _ ->
  cctxt#message "Injected block at minimal timestamp" >>= fun () -> return_unit

let bake (cctxt : Protocol_client_context.full) ?minimal_fees
    ?minimal_nanotez_per_gas_unit ?minimal_nanotez_per_byte ?force
    ?(minimal_timestamp = false) ?extra_operations ?monitor_node_mempool
    ?context_path delegates =
  let config =
    Baking_configuration.make
      ?minimal_fees
      ?minimal_nanotez_per_gas_unit
      ?minimal_nanotez_per_byte
      ?context_path
      ?force
      ?extra_operations
      ()
  in
  get_current_proposal cctxt >>=? fun (block_stream, current_proposal) ->
  create_state
    cctxt
    ?monitor_node_mempool
    ~synchronize:(not minimal_timestamp)
    ~config
    ~current_proposal
    delegates
  >>=? fun state ->
  if not minimal_timestamp then bake_using_automaton config state block_stream
  else baking_minimal_timestamp state
