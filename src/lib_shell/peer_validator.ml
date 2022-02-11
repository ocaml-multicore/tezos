(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2018-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

(* FIXME ignore/postpone fetching/validating of block in the future... *)

open Peer_validator_worker_state

module Name = struct
  type t = Chain_id.t * P2p_peer.Id.t

  let encoding = Data_encoding.tup2 Chain_id.encoding P2p_peer.Id.encoding

  let base = ["validator"; "peer"]

  let pp ppf (chain, peer) =
    Format.fprintf ppf "%a:%a" Chain_id.pp_short chain P2p_peer.Id.pp_short peer

  let equal (c1, p1) (c2, p2) = Chain_id.equal c1 c2 && P2p_peer.Id.equal p1 p2
end

module Request = struct
  include Request

  type _ t =
    | New_head : Block_hash.t * Block_header.t -> unit t
    | New_branch : Block_hash.t * Block_locator.t * Block_locator.seed -> unit t

  let view (type a) (req : a t) : view =
    match req with
    | New_head (hash, _) -> New_head hash
    | New_branch (hash, locator, seed) ->
        (* the seed is associated to each locator
           w.r.t. the peer_id of the sender *)
        New_branch (hash, Block_locator.estimated_length seed locator)
end

type limits = {
  new_head_request_timeout : Time.System.Span.t;
  block_header_timeout : Time.System.Span.t;
  block_operations_timeout : Time.System.Span.t;
  protocol_timeout : Time.System.Span.t;
}

module Types = struct
  type parameters = {
    chain_db : Distributed_db.chain_db;
    block_validator : Block_validator.t;
    (* callback to chain_validator *)
    notify_new_block : Store.Block.t -> unit;
    notify_termination : unit -> unit;
    limits : limits;
  }

  type state = {
    peer_id : P2p_peer.Id.t;
    parameters : parameters;
    mutable pipeline : Bootstrap_pipeline.t option;
    mutable last_validated_head : Block_header.t;
    mutable last_advertised_head : Block_header.t;
  }

  let pipeline_length = function
    | None -> Bootstrap_pipeline.length_zero
    | Some p -> Bootstrap_pipeline.length p
end

module Logger =
  Worker_logger.Make (Event) (Request)
    (struct
      let worker_name = "node_peer_validator"
    end)

module Worker = Worker.Make (Name) (Event) (Request) (Types) (Logger)
open Types

type t = Worker.dropbox Worker.t

let bootstrap_new_branch w head unknown_prefix =
  let pv = Worker.state w in
  let sender_id = Distributed_db.my_peer_id pv.parameters.chain_db in
  (* sender and receiver are inverted here because they are from
     the point of view of the node sending the locator *)
  let seed = {Block_locator.sender_id = pv.peer_id; receiver_id = sender_id} in
  let len = Block_locator.estimated_length seed unknown_prefix in
  Worker.log_event
    w
    (Validating_new_branch {peer = pv.peer_id; nb_blocks = len})
  >>= fun () ->
  let pipeline =
    Bootstrap_pipeline.create
      ~notify_new_block:pv.parameters.notify_new_block
      ~block_header_timeout:pv.parameters.limits.block_header_timeout
      ~block_operations_timeout:pv.parameters.limits.block_operations_timeout
      pv.parameters.block_validator
      pv.peer_id
      pv.parameters.chain_db
      unknown_prefix
  in
  pv.pipeline <- Some pipeline ;
  Worker.protect
    w
    ~on_error:(fun error ->
      (* if the peer_validator is killed, let's cancel the pipeline *)
      pv.pipeline <- None ;
      Bootstrap_pipeline.cancel pipeline >>= fun () -> Lwt.return_error error)
    (fun () -> Bootstrap_pipeline.wait pipeline)
  >>=? fun () ->
  pv.pipeline <- None ;
  Worker.log_event
    w
    (New_branch_validated {peer = pv.peer_id; hash = Block_header.hash head})
  >>= fun () -> return_unit

let only_if_fitness_increases w distant_header hash cont =
  let pv = Worker.state w in
  let chain_store = Distributed_db.chain_store pv.parameters.chain_db in
  Store.Block.is_known_valid chain_store hash >>= fun known_valid ->
  if known_valid then (
    pv.last_validated_head <- distant_header ;
    return_unit)
  else
    Store.Chain.current_head chain_store >>= fun current_head ->
    if
      Fitness.compare
        distant_header.Block_header.shell.fitness
        (Store.Block.fitness current_head)
      <= 0
    then (
      Worker.log_event w (Ignoring_head {peer = pv.peer_id; hash}) >>= fun () ->
      (* Don't download a branch that cannot beat the current head. *)
      let meta =
        Distributed_db.get_peer_metadata pv.parameters.chain_db pv.peer_id
      in
      Peer_metadata.incr meta Old_heads ;
      return_unit)
    else cont ()

let validate_new_head w hash (header : Block_header.t) =
  let pv = Worker.state w in
  let block_received = {Event.peer = pv.peer_id; hash} in
  Worker.log_event w (Fetching_operations_for_head block_received) >>= fun () ->
  List.map_ep
    (fun i ->
      Worker.protect w (fun () ->
          Distributed_db.Operations.fetch
            ~timeout:pv.parameters.limits.block_operations_timeout
            pv.parameters.chain_db
            ~peer:pv.peer_id
            (hash, i)
            header.shell.operations_hash))
    (0 -- (header.shell.validation_passes - 1))
  >>=? fun operations ->
  (* We redo a check for the fitness here because while waiting for the
     operations, a new head better than this block might be validated. *)
  only_if_fitness_increases w header hash @@ fun () ->
  Worker.log_event w (Requesting_new_head_validation block_received)
  >>= fun () ->
  Block_validator.validate
    ~notify_new_block:pv.parameters.notify_new_block
    ~precheck_and_notify:true
    pv.parameters.block_validator
    pv.parameters.chain_db
    hash
    header
    operations
  >>= function
  | Invalid errs ->
      (* This will convert into a kickban when treated by [on_error] --
         or, at least, by a worker termination which will close the
         connection. *)
      Lwt.return_error errs
  | Invalid_after_precheck _errs ->
      Worker.log_event w (Ignoring_prechecked_invalid_block block_received)
      >>= fun () ->
      (* We do not kickban the peer if the block received was
         successfully prechecked but invalid -- this means that he
         could have propagated a precheckable block before terminating
         its validation *)
      return_unit
  | Valid ->
      Worker.log_event w (New_head_validation_end block_received) >>= fun () ->
      let meta =
        Distributed_db.get_peer_metadata pv.parameters.chain_db pv.peer_id
      in
      Peer_metadata.incr meta Valid_blocks ;
      return_unit

let assert_acceptable_head w hash (header : Block_header.t) =
  let pv = Worker.state w in
  let chain_store = Distributed_db.chain_store pv.parameters.chain_db in
  Store.Chain.is_acceptable_block chain_store (hash, header.shell.level)
  >>= fun acceptable ->
  fail_unless
    acceptable
    (Validation_errors.Checkpoint_error (hash, Some pv.peer_id))

let may_validate_new_head w hash (header : Block_header.t) =
  let pv = Worker.state w in
  let chain_store = Distributed_db.chain_store pv.parameters.chain_db in
  Store.Block.is_known_valid chain_store hash >>= fun valid_block ->
  Store.Block.is_known_invalid chain_store hash >>= fun invalid_block ->
  Store.Block.is_known_valid chain_store header.shell.predecessor
  >>= fun valid_predecessor ->
  Store.Block.is_known_invalid chain_store header.shell.predecessor
  >>= fun invalid_predecessor ->
  let block_received = {Event.peer = pv.peer_id; hash} in
  if valid_block then
    Worker.log_event w (Ignoring_previously_validated_block block_received)
    >>= fun () -> return_unit
  else if invalid_block then
    Worker.log_event w (Ignoring_invalid_block block_received) >>= fun () ->
    fail Validation_errors.Known_invalid
  else if invalid_predecessor then
    Worker.log_event w (Ignoring_invalid_block block_received) >>= fun () ->
    Distributed_db.commit_invalid_block
      pv.parameters.chain_db
      hash
      header
      [Validation_errors.Known_invalid]
    >>=? fun _ -> fail Validation_errors.Known_invalid
  else if not valid_predecessor then (
    Worker.log_event w (Missing_new_head_predecessor block_received)
    >>= fun () ->
    Distributed_db.Request.current_branch
      pv.parameters.chain_db
      ~peer:pv.peer_id
      () ;
    return_unit)
  else
    only_if_fitness_increases w header hash @@ fun () ->
    assert_acceptable_head w hash header >>=? fun () ->
    validate_new_head w hash header

let may_validate_new_branch w distant_hash locator =
  (* Make sure this is still ok w.r.t @phink fix *)
  let pv = Worker.state w in
  let (distant_header, _) = (locator : Block_locator.t :> Block_header.t * _) in
  only_if_fitness_increases w distant_header distant_hash @@ fun () ->
  assert_acceptable_head w distant_hash distant_header >>=? fun () ->
  let chain_store = Distributed_db.chain_store pv.parameters.chain_db in
  (* TODO: should we consider level as well ? Rolling could have
     difficulties boostrapping. *)
  let block_received = {Event.peer = pv.peer_id; hash = distant_hash} in
  Block_locator.unknown_prefix
    ~is_known:(Store.Block.validity chain_store)
    locator
  >>= function
  | (Known_valid, prefix_locator) ->
      let (_, history) =
        (prefix_locator : Block_locator.t :> Block_header.t * _)
      in
      if history <> [] then bootstrap_new_branch w distant_header prefix_locator
      else return_unit
  | (Unknown, _) ->
      (* May happen when:
         - A locator from another chain is received;
         - A rolling peer is too far ahead;
         - In rolling mode when the step is too wide. *)
      Worker.log_event
        w
        (Ignoring_branch_without_common_ancestor block_received)
      >>= fun () -> fail Validation_errors.Unknown_ancestor
  | (Known_invalid, _) ->
      Worker.log_event w (Ignoring_branch_with_invalid_locator block_received)
      >>= fun () ->
      fail (Validation_errors.Invalid_locator (pv.peer_id, locator))

let on_no_request w =
  let pv = Worker.state w in
  let timespan =
    Ptime.Span.to_float_s pv.parameters.limits.new_head_request_timeout
  in
  Worker.log_event w (No_new_head_from_peer {peer = pv.peer_id; timespan})
  >>= fun () ->
  Distributed_db.Request.current_head pv.parameters.chain_db ~peer:pv.peer_id () ;
  return_unit

let on_request (type a) w (req : a Request.t) : a tzresult Lwt.t =
  let pv = Worker.state w in
  match req with
  | Request.New_head (hash, header) ->
      Worker.log_event w (Processing_new_head {peer = pv.peer_id; hash})
      >>= fun () -> may_validate_new_head w hash header
  | Request.New_branch (hash, locator, _seed) ->
      (* TODO penalize empty locator... ?? *)
      Worker.log_event w (Processing_new_branch {peer = pv.peer_id; hash})
      >>= fun () -> may_validate_new_branch w hash locator

let on_completion w r _ st =
  Worker.log_event w (Event.Request (Request.view r, st, None)) >>= fun () ->
  Lwt.return_unit

let on_error w r st err =
  let pv = Worker.state w in
  match err with
  | ( Validation_errors.Invalid_locator _
    | Block_validator_errors.Invalid_block _ )
    :: _ ->
      Distributed_db.greylist pv.parameters.chain_db pv.peer_id >>= fun () ->
      Worker.log_event
        w
        (Terminating_worker
           {peer = pv.peer_id; reason = "invalid data received: kickban"})
      >>= fun () ->
      Worker.trigger_shutdown w ;
      Worker.log_event w (Event.Request (r, st, Some err)) >>= fun () ->
      Lwt.return_error err
  | Block_validator_errors.System_error _ :: _ ->
      Worker.log_event w (Event.Request (r, st, Some err)) >>= fun () ->
      return_unit
  | Block_validator_errors.Unavailable_protocol {protocol; _} :: _ -> (
      Block_validator.fetch_and_compile_protocol
        pv.parameters.block_validator
        ~peer:pv.peer_id
        ~timeout:pv.parameters.limits.protocol_timeout
        protocol
      >>= function
      | Ok _ ->
          Distributed_db.Request.current_head
            pv.parameters.chain_db
            ~peer:pv.peer_id
            () ;
          return_unit
      | Error _ ->
          (* TODO: punish *)
          Worker.log_event
            w
            (Terminating_worker
               {
                 peer = pv.peer_id;
                 reason =
                   Format.asprintf
                     "missing protocol: %a"
                     Protocol_hash.pp
                     protocol;
               })
          >>= fun () ->
          Worker.log_event w (Event.Request (r, st, Some err)) >>= fun () ->
          Lwt.return_error err)
  | (Validation_errors.Unknown_ancestor | Validation_errors.Too_short_locator _)
    :: _ ->
      Worker.log_event
        w
        (Terminating_worker
           {
             peer = pv.peer_id;
             reason =
               Format.asprintf "unknown ancestor or too short locator: kick";
           })
      >>= fun () ->
      Worker.trigger_shutdown w ;
      Worker.log_event w (Event.Request (r, st, Some err)) >>= fun () ->
      return_unit
  | Distributed_db.Operations.Canceled _ :: _ -> (
      (* Given two nodes A and B (remote). This may happen if A
         prechecks a block, sends it to B. B prechecks a block, sends
         it to A. A tries to fetch operations of the block to B, in
         the meantime, A validates the block and cancels the fetching.
      *)
      match r with
      | New_head hash -> (
          let chain_store = Distributed_db.chain_store pv.parameters.chain_db in
          Store.Block.is_known_valid chain_store hash >>= function
          | true -> return_unit
          | false -> Lwt.return_error err)
      | _ -> Lwt.return_error err)
  | _ ->
      Worker.log_event w (Event.Request (r, st, Some err)) >>= fun () ->
      Lwt.return_error err

let on_close w =
  let pv = Worker.state w in
  Distributed_db.disconnect pv.parameters.chain_db pv.peer_id >>= fun () ->
  pv.parameters.notify_termination () ;
  Lwt.return_unit

let on_launch _ name parameters =
  let chain_store = Distributed_db.chain_store parameters.chain_db in
  Store.Chain.genesis_block chain_store >>= fun genesis ->
  (* TODO : why do we have genesis and not current_head here ?? *)
  let rec pv =
    {
      peer_id = snd name;
      parameters = {parameters with notify_new_block};
      pipeline = None;
      last_validated_head = Store.Block.header genesis;
      last_advertised_head = Store.Block.header genesis;
    }
  and notify_new_block block =
    pv.last_validated_head <- Store.Block.header block ;
    parameters.notify_new_block block
  in
  return pv

let table =
  let merge w (Worker.Any_request neu) old =
    let pv = Worker.state w in
    match neu with
    | Request.New_branch (_, locator, _) ->
        let (header, _) = (locator : Block_locator.t :> _ * _) in
        pv.last_advertised_head <- header ;
        Some (Worker.Any_request neu)
    | Request.New_head (_, header) -> (
        pv.last_advertised_head <- header ;
        (* TODO penalize decreasing fitness *)
        match old with
        | Some (Worker.Any_request (Request.New_branch _) as old) ->
            Some old (* ignore *)
        | Some (Worker.Any_request (Request.New_head _)) ->
            Some (Any_request neu)
        | None -> Some (Any_request neu))
  in
  Worker.create_table (Dropbox {merge})

let create ?(notify_new_block = fun _ -> ()) ?(notify_termination = fun _ -> ())
    limits block_validator chain_db peer_id =
  let name =
    (Store.Chain.chain_id (Distributed_db.chain_store chain_db), peer_id)
  in
  let parameters =
    {chain_db; notify_termination; block_validator; notify_new_block; limits}
  in
  let module Handlers = struct
    type self = t

    let on_launch = on_launch

    let on_request = on_request

    let on_close = on_close

    let on_error = on_error

    let on_completion = on_completion

    let on_no_request = on_no_request
  end in
  Worker.launch
    table
    ~timeout:limits.new_head_request_timeout
    name
    parameters
    (module Handlers)

let notify_branch w locator =
  let (header, _) = (locator : Block_locator.t :> _ * _) in
  let hash = Block_header.hash header in
  let pv = Worker.state w in
  let sender_id = Distributed_db.my_peer_id pv.parameters.chain_db in
  (* sender and receiver are inverted here because they are from
     the point of view of the node sending the locator *)
  let seed = {Block_locator.sender_id = pv.peer_id; receiver_id = sender_id} in
  Worker.Dropbox.put_request w (New_branch (hash, locator, seed))

let notify_head w header =
  let hash = Block_header.hash header in
  Worker.Dropbox.put_request w (New_head (hash, header))

let shutdown w = Worker.shutdown w

let peer_id w =
  let pv = Worker.state w in
  pv.peer_id

let status = Worker.status

let information = Worker.information

let running_workers () = Worker.list table

let current_request t = Worker.current_request t

let pipeline_length w =
  let state = Worker.state w in
  Types.pipeline_length state.pipeline
