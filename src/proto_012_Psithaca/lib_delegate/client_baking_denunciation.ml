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
open Protocol_client_context
open Client_baking_blocks
module Events = Delegate_events.Denunciator

module HLevel = Hashtbl.Make (struct
  type t = Chain_id.t * Raw_level.t * Round.t

  let equal (c, l, r) (c', l', r') =
    Chain_id.equal c c' && Raw_level.equal l l' && Round.equal r r'

  let hash (c, lvl, r) = Hashtbl.hash (c, lvl, r)
end)

(* Blocks are associated to the delegates who baked them *)
module Delegate_Map = Map.Make (Signature.Public_key_hash)

(* (pre)endorsements are associated to the slot they are injected
   with; we rely on the fact that there is a unique canonical slot
   identifying a (pre)endorser. *)
module Slot_Map = Slot.Map

(* type of operations stream, as returned by monitor_operations RPC *)
type ops_stream =
  ((Operation_hash.t * packed_operation) * error trace option) list Lwt_stream.t

type 'a state = {
  (* Endorsements seen so far *)
  endorsements_table : Kind.endorsement operation Slot_Map.t HLevel.t;
  (* Preendorsements seen so far *)
  preendorsements_table : Kind.preendorsement operation Slot_Map.t HLevel.t;
  (* Blocks received so far *)
  blocks_table : Block_hash.t Delegate_Map.t HLevel.t;
  (* Maximum delta of level to register *)
  preserved_levels : int;
  (* Highest level seen in a block *)
  mutable highest_level_encountered : Raw_level.t;
  (* This constant allows to set at which frequency (expressed in blocks levels)
     the tables above are cleaned. Cleaning the table means removing information
     stored about old levels up to
     'highest_level_encountered - preserved_levels'.
  *)
  clean_frequency : int;
  (* the decreasing cleaning countdown for the next cleaning *)
  mutable cleaning_countdown : int;
  (* stream of all valid blocks *)
  blocks_stream : (block_info, 'a) result Lwt_stream.t;
  (* operations stream. Reset on new heads flush *)
  mutable ops_stream : ops_stream;
  (* operatons stream stopper. Used when a q new *)
  mutable ops_stream_stopper : unit -> unit;
}

let create_state ~preserved_levels blocks_stream ops_stream ops_stream_stopper =
  let clean_frequency = max 1 (preserved_levels / 10) in
  Lwt.return
    {
      endorsements_table = HLevel.create preserved_levels;
      preendorsements_table = HLevel.create preserved_levels;
      blocks_table = HLevel.create preserved_levels;
      preserved_levels;
      highest_level_encountered = Raw_level.root (* 0l *);
      clean_frequency;
      cleaning_countdown = clean_frequency;
      blocks_stream;
      ops_stream;
      ops_stream_stopper;
    }

(* We choose a previous offset (5 blocks from head) to ensure that the
   injected operation is branched from a valid
   predecessor. Denunciation operations can be emitted when the
   consensus is under attack and may occur so you want to inject the
   operation from a block which is considered "final". *)
let get_block_offset level =
  match Raw_level.of_int32 5l with
  | Ok min_level ->
      let offset = Raw_level.diff level min_level in
      if Compare.Int32.(offset >= 0l) then Lwt.return (`Head 5)
      else
        (* offset < 0l *)
        let negative_offset = Int32.to_int offset in
        (* We cannot inject at at level 0 : this is the genesis
           level. We inject starting from level 1 thus the '- 1'. *)
        Lwt.return (`Head (5 + negative_offset - 1))
  | Error errs ->
      Events.(emit invalid_level_conversion) (Environment.wrap_tztrace errs)
      >>= fun () -> Lwt.return (`Head 0)

let get_payload_hash (type kind) (op_kind : kind consensus_operation_type)
    (op : kind Operation.t) =
  match (op_kind, op.protocol_data.contents) with
  | (Preendorsement, Single (Preendorsement consensus_content))
  | (Endorsement, Single (Endorsement consensus_content)) ->
      consensus_content.block_payload_hash
  | _ -> .

let double_consensus_op_evidence (type kind) :
    kind consensus_operation_type ->
    #Protocol_client_context.full ->
    'a ->
    branch:Block_hash.t ->
    op1:kind Alpha_context.operation ->
    op2:kind Alpha_context.operation ->
    unit ->
    bytes Environment.Error_monad.shell_tzresult Lwt.t = function
  | Endorsement -> Plugin.RPC.Forge.double_endorsement_evidence
  | Preendorsement -> Plugin.RPC.Forge.double_preendorsement_evidence

let process_consensus_op (type kind) cctxt
    (op_kind : kind consensus_operation_type) (new_op : kind Operation.t)
    chain_id level round slot ops_table =
  let map =
    Option.value ~default:Slot_Map.empty
    @@ HLevel.find ops_table (chain_id, level, round)
  in
  (* If a previous endorsement made by this pkh (the slot determines the pkh)
     is found for the same level we inject a double_(pre)endorsement *)
  match Slot_Map.find slot map with
  | None ->
      return
      @@ HLevel.add
           ops_table
           (chain_id, level, round)
           (Slot_Map.add slot new_op map)
  | Some existing_op
    when Block_payload_hash.(
           get_payload_hash op_kind existing_op
           <> get_payload_hash op_kind new_op) ->
      (* same level and round, and different payload hash for this slot *)
      let (new_op_hash, existing_op_hash) =
        (Operation.hash new_op, Operation.hash existing_op)
      in
      let (op1, op2) =
        if Operation_hash.(new_op_hash < existing_op_hash) then
          (new_op, existing_op)
        else (existing_op, new_op)
      in
      get_block_offset level >>= fun block ->
      let chain = `Hash chain_id in
      Alpha_block_services.hash cctxt ~chain ~block () >>=? fun block_hash ->
      double_consensus_op_evidence
        op_kind
        cctxt
        (`Hash chain_id, block)
        ~branch:block_hash
        ~op1
        ~op2
        ()
      >>=? fun bytes ->
      let bytes = Signature.concat bytes Signature.zero in
      let (double_op_detected, double_op_denounced) =
        Events.(
          match op_kind with
          | Endorsement ->
              (double_endorsement_detected, double_endorsement_denounced)
          | Preendorsement ->
              (double_preendorsement_detected, double_preendorsement_denounced))
      in
      Events.(emit double_op_detected) (new_op_hash, existing_op_hash)
      >>= fun () ->
      HLevel.replace
        ops_table
        (chain_id, level, round)
        (Slot_Map.add slot new_op map) ;
      Shell_services.Injection.operation cctxt ~chain bytes >>=? fun op_hash ->
      Events.(emit double_op_denounced) (op_hash, bytes) >>= fun () ->
      return_unit
  | _ -> return_unit

let process_operations (cctxt : #Protocol_client_context.full) state
    (endorsements : 'a list) ~packed_op chain_id =
  List.iter_es
    (fun op ->
      let {shell; protocol_data; _} = packed_op op in
      match protocol_data with
      | Operation_data
          ({contents = Single (Preendorsement {round; slot; level; _}); _} as
          protocol_data) ->
          let new_preendorsement : Kind.preendorsement Alpha_context.operation =
            {shell; protocol_data}
          in
          process_consensus_op
            cctxt
            Preendorsement
            new_preendorsement
            chain_id
            level
            round
            slot
            state.preendorsements_table
      | Operation_data
          ({contents = Single (Endorsement {round; slot; level; _}); _} as
          protocol_data) ->
          let new_endorsement : Kind.endorsement Alpha_context.operation =
            {shell; protocol_data}
          in
          process_consensus_op
            cctxt
            Endorsement
            new_endorsement
            chain_id
            level
            round
            slot
            state.endorsements_table
      | _ ->
          (* not a consensus operation *)
          return_unit)
    endorsements

let context_block_header cctxt ~chain b_hash =
  Alpha_block_services.header cctxt ~chain ~block:(`Hash (b_hash, 0)) ()
  >>=? fun ({shell; protocol_data; _} : Alpha_block_services.block_header) ->
  return {Alpha_context.Block_header.shell; protocol_data}

let process_block (cctxt : #Protocol_client_context.full) state
    (header : Alpha_block_services.block_info) =
  match header with
  | {hash; metadata = None; _} ->
      Events.(emit unexpected_pruned_block) hash >>= fun () -> return_unit
  | {
   Alpha_block_services.chain_id;
   hash = new_hash;
   metadata = Some {protocol_data = {baker; level_info = {level; _}; _}; _};
   header = {shell = {fitness; _}; _};
   _;
  } -> (
      let fitness = Fitness.from_raw fitness in
      Lwt.return
        (match fitness with
        | Ok fitness -> Ok (Fitness.round fitness)
        | Error errs -> Error (Environment.wrap_tztrace errs))
      >>=? fun round ->
      let chain = `Hash chain_id in
      let map =
        Option.value ~default:Delegate_Map.empty
        @@ HLevel.find state.blocks_table (chain_id, level, round)
      in
      match Delegate_Map.find baker map with
      | None ->
          return
          @@ HLevel.add
               state.blocks_table
               (chain_id, level, round)
               (Delegate_Map.add baker new_hash map)
      | Some existing_hash when Block_hash.(existing_hash = new_hash) ->
          (* This case should never happen *)
          Events.(emit double_baking_but_not) () >>= fun () ->
          return
          @@ HLevel.replace
               state.blocks_table
               (chain_id, level, round)
               (Delegate_Map.add baker new_hash map)
      | Some existing_hash ->
          (* If a previous block made by this pkh is found for
             the same (level, round) we inject a double_baking_evidence *)
          context_block_header cctxt ~chain existing_hash >>=? fun bh1 ->
          context_block_header cctxt ~chain new_hash >>=? fun bh2 ->
          let hash1 = Block_header.hash bh1 in
          let hash2 = Block_header.hash bh2 in
          let (bh1, bh2) =
            if Block_hash.(hash1 < hash2) then (bh1, bh2) else (bh2, bh1)
          in
          (* If the blocks are on different chains then skip it *)
          get_block_offset level >>= fun block ->
          Alpha_block_services.hash cctxt ~chain ~block ()
          >>=? fun block_hash ->
          Plugin.RPC.Forge.double_baking_evidence
            cctxt
            (chain, block)
            ~branch:block_hash
            ~bh1
            ~bh2
            ()
          >>=? fun bytes ->
          let bytes = Signature.concat bytes Signature.zero in
          Events.(emit double_baking_detected) () >>= fun () ->
          Shell_services.Injection.operation cctxt ~chain bytes
          >>=? fun op_hash ->
          Events.(emit double_baking_denounced) (op_hash, bytes) >>= fun () ->
          return
          @@ HLevel.replace
               state.blocks_table
               (chain_id, level, round)
               (Delegate_Map.add baker new_hash map))

(* Remove levels that are lower than the
   [highest_level_encountered] minus [preserved_levels] *)
let cleanup_old_operations state =
  state.cleaning_countdown <- state.cleaning_countdown - 1 ;
  if state.cleaning_countdown < 0 then (
    (* It's time to remove old levels *)
    state.cleaning_countdown <- state.clean_frequency ;
    let highest_level_encountered =
      Int32.to_int (Raw_level.to_int32 state.highest_level_encountered)
    in
    let diff = highest_level_encountered - state.preserved_levels in
    let threshold =
      if diff < 0 then Raw_level.root
      else
        Raw_level.of_int32 (Int32.of_int diff) |> function
        | Ok threshold -> threshold
        | Error _ -> Raw_level.root
    in
    let filter hmap =
      HLevel.filter_map_inplace
        (fun (_, level, _) x ->
          if Raw_level.(level < threshold) then None else Some x)
        hmap
    in
    filter state.preendorsements_table ;
    filter state.endorsements_table ;
    filter state.blocks_table)

(* Each new block is processed :
   - Checking that every baker injected only once at this level
   - Checking that every (pre)endorser operated only once at this level
*)
let process_new_block (cctxt : #Protocol_client_context.full) state
    {hash; chain_id; level; protocol; next_protocol; _} =
  if Protocol_hash.(protocol <> next_protocol) then
    Events.(emit protocol_change_detected) () >>= fun () -> return_unit
  else
    Events.(emit accuser_saw_block) (level, hash) >>= fun () ->
    let chain = `Hash chain_id in
    let block = `Hash (hash, 0) in
    state.highest_level_encountered <-
      Raw_level.max level state.highest_level_encountered ;
    (* Processing blocks *)
    (Alpha_block_services.info cctxt ~chain ~block () >>= function
     | Ok block_info -> process_block cctxt state block_info
     | Error errs ->
         Events.(emit fetch_operations_error) (hash, errs) >>= fun () ->
         return_unit)
    >>=? fun () ->
    (* Processing (pre)endorsements in the block *)
    (Alpha_block_services.Operations.operations cctxt ~chain ~block ()
     >>= function
     | Ok (consensus_ops :: _) ->
         let packed_op {Alpha_block_services.shell; protocol_data; _} =
           {shell; protocol_data}
         in
         process_operations cctxt state consensus_ops ~packed_op chain_id
     | Ok [] ->
         (* should not happen, unless the semantics of
            Alpha_block_services.Operations.operations (which is supposed to
            return a list of 4 elements changes. In which case, this code
            should be adapted). *)
         assert false
     | Error errs ->
         Events.(emit fetch_operations_error) (hash, errs) >>= fun () ->
         return_unit)
    >>=? fun () ->
    cleanup_old_operations state ;
    return_unit

let process_new_block cctxt state bi =
  process_new_block cctxt state bi >>= function
  | Ok () -> Events.(emit accuser_processed_block) bi.hash >>= return
  | Error errs -> Events.(emit accuser_block_error) (bi.hash, errs) >>= return

module B_Events = Delegate_events.Baking_scheduling

let rec wait_for_first_block ~name stream =
  Lwt_stream.get stream >>= function
  | None | Some (Error _) ->
      B_Events.(emit cannot_fetch_event) name >>= fun () ->
      (* NOTE: this is not a tight loop because of Lwt_stream.get *)
      wait_for_first_block ~name stream
  | Some (Ok bi) -> Lwt.return bi

let log_errors_and_continue ~name p =
  p >>= function
  | Ok () -> Lwt.return_unit
  | Error errs -> B_Events.(emit daemon_error) (name, errs)

let start_ops_monitor cctxt =
  Alpha_block_services.Mempool.monitor_operations
    cctxt
    ~chain:cctxt#chain
    ~applied:true
    ~branch_delayed:true
    ~branch_refused:true
    ~refused:true
    ()

let create (cctxt : #Protocol_client_context.full) ?canceler ~preserved_levels
    valid_blocks_stream =
  B_Events.(emit daemon_setup) name >>= fun () ->
  start_ops_monitor cctxt >>=? fun (ops_stream, ops_stream_stopper) ->
  create_state
    ~preserved_levels
    valid_blocks_stream
    ops_stream
    ops_stream_stopper
  >>= fun state ->
  Option.iter
    (fun canceler ->
      Lwt_canceler.on_cancel canceler (fun () ->
          state.ops_stream_stopper () ;
          Lwt.return_unit))
    canceler ;
  wait_for_first_block ~name state.blocks_stream >>= fun _first_event ->
  let last_get_block = ref None in
  let get_block () =
    match !last_get_block with
    | None ->
        let t = Lwt_stream.get state.blocks_stream in
        last_get_block := Some t ;
        t
    | Some t -> t
  in
  let last_get_ops = ref None in
  let get_ops () =
    match !last_get_ops with
    | None ->
        let t = Lwt_stream.get state.ops_stream in
        last_get_ops := Some t ;
        t
    | Some t -> t
  in
  Chain_services.chain_id cctxt () >>=? fun chain_id ->
  (* main loop *)
  let rec worker_loop () =
    Lwt.choose
      [
        (Lwt_exit.clean_up_starts >|= fun _ -> `Termination);
        (get_block () >|= fun e -> `Block e);
        (get_ops () >|= fun e -> `Operations e);
      ]
    >>= function
    (* event matching *)
    | `Termination -> return_unit
    | `Block (None | Some (Error _)) ->
        (* exit when the node is unavailable *)
        last_get_block := None ;
        B_Events.(emit daemon_connection_lost) name >>= fun () ->
        fail Baking_errors.Node_connection_lost
    | `Block (Some (Ok bi)) ->
        last_get_block := None ;
        log_errors_and_continue ~name @@ process_new_block cctxt state bi
        >>= fun () -> worker_loop ()
    | `Operations None ->
        (* restart a new operations monitor stream *)
        last_get_ops := None ;
        state.ops_stream_stopper () ;
        start_ops_monitor cctxt >>=? fun (ops_stream, ops_stream_stopper) ->
        state.ops_stream <- ops_stream ;
        state.ops_stream_stopper <- ops_stream_stopper ;
        worker_loop ()
    | `Operations (Some ops) ->
        last_get_ops := None ;
        log_errors_and_continue ~name
        @@ process_operations
             cctxt
             state
             ops
             ~packed_op:(fun ((_h, op), _errl) -> op)
             chain_id
        >>= fun () -> worker_loop ()
  in
  B_Events.(emit daemon_start) name >>= fun () -> worker_loop ()
