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

open Chain_services

let get_chain_id store =
  let main_chain_store = Store.main_chain_store store in
  function
  | `Main -> Lwt.return (Store.Chain.chain_id main_chain_store)
  | `Test -> (
      Store.Chain.testchain main_chain_store >>= function
      | None -> Lwt.fail Not_found
      | Some testchain ->
          let testchain_store = Store.Chain.testchain_store testchain in
          Lwt.return (Store.Chain.chain_id testchain_store))
  | `Hash chain_id -> Lwt.return chain_id

let get_chain_id_opt store chain =
  Option.catch_s (fun () -> get_chain_id store chain)

let get_chain_store_exn store chain =
  get_chain_id store chain >>= fun chain_id ->
  Store.get_chain_store_opt store chain_id >>= function
  | Some chain_store -> Lwt.return chain_store
  | None -> Lwt.fail Not_found

let get_checkpoint store (chain : Chain_services.chain) =
  get_chain_store_exn store chain >>= fun chain_store ->
  Store.Chain.checkpoint chain_store >>= fun (checkpoint_hash, _) ->
  Lwt.return checkpoint_hash

let predecessors chain_store ignored length head =
  let rec loop acc length block =
    if length <= 0 then return (List.rev acc)
    else
      Store.Block.read_ancestor_hash chain_store ~distance:1 block >>=? function
      | None -> return (List.rev acc)
      | Some pred ->
          if Block_hash.Set.mem block ignored then return (List.rev acc)
          else loop (pred :: acc) (length - 1) pred
  in
  let head_hash = Store.Block.hash head in
  loop [head_hash] (length - 1) head_hash

let list_blocks chain_store ?(length = 1) ?min_date heads =
  (match heads with
  | [] ->
      Store.Chain.known_heads chain_store >>= fun heads ->
      Lwt_list.filter_map_p
        (fun (h, _) -> Store.Block.read_block_opt chain_store h)
        heads
      >>= fun heads ->
      let heads =
        match min_date with
        | None -> heads
        | Some min_date ->
            List.filter
              (fun block ->
                let timestamp = Store.Block.timestamp block in
                Time.Protocol.(min_date <= timestamp))
              heads
      in
      let sorted_heads =
        List.sort
          (fun b1 b2 ->
            let f1 = Store.Block.fitness b1 in
            let f2 = Store.Block.fitness b2 in
            ~-(Fitness.compare f1 f2))
          heads
      in
      Lwt.return (List.map (fun b -> Some b) sorted_heads)
  | _ :: _ as heads -> List.map_p (Store.Block.read_block_opt chain_store) heads)
  >>= fun requested_heads ->
  List.fold_left_es
    (fun (ignored, acc) head ->
      match head with
      | None -> return (ignored, acc)
      | Some block ->
          predecessors chain_store ignored length block >>=? fun predecessors ->
          let ignored =
            List.fold_left
              (fun acc v -> Block_hash.Set.add v acc)
              ignored
              predecessors
          in
          return (ignored, predecessors :: acc))
    (Block_hash.Set.empty, [])
    requested_heads
  >>=? fun (_, blocks) -> return (List.rev blocks)

let rpc_directory validator =
  let dir : Store.chain_store RPC_directory.t ref = ref RPC_directory.empty in
  let register0 s f =
    dir :=
      RPC_directory.register !dir (RPC_service.subst0 s) (fun chain p q ->
          f chain p q)
  in
  let register1 s f =
    dir :=
      RPC_directory.register !dir (RPC_service.subst1 s) (fun (chain, a) p q ->
          f chain a p q)
  in
  let register_dynamic_directory2 ?descr s f =
    dir :=
      RPC_directory.register_dynamic_directory
        !dir
        ?descr
        (RPC_path.subst1 s)
        (fun (chain, a) -> f chain a)
  in
  register0 S.chain_id (fun chain_store () () ->
      return (Store.Chain.chain_id chain_store)) ;
  register0 S.checkpoint (fun chain_store () () ->
      Store.Chain.checkpoint chain_store >>= fun (checkpoint_hash, _) ->
      Store.Block.read_block chain_store checkpoint_hash >>=? fun block ->
      let checkpoint_header = Store.Block.header block in
      Store.Chain.savepoint chain_store >>= fun (_, savepoint_level) ->
      Store.Chain.caboose chain_store >>= fun (_, caboose_level) ->
      let history_mode = Store.Chain.history_mode chain_store in
      return (checkpoint_header, savepoint_level, caboose_level, history_mode)) ;
  register0 S.Levels.checkpoint (fun chain_store () () ->
      Store.Chain.checkpoint chain_store >>= return) ;
  register0 S.Levels.savepoint (fun chain_store () () ->
      Store.Chain.savepoint chain_store >>= return) ;
  register0 S.Levels.caboose (fun chain_store () () ->
      Store.Chain.caboose chain_store >>= return) ;
  register0 S.is_bootstrapped (fun chain_store () () ->
      match Validator.get validator (Store.Chain.chain_id chain_store) with
      | Error _ -> Lwt.fail Not_found
      | Ok chain_validator ->
          return
            Chain_validator.
              (is_bootstrapped chain_validator, sync_status chain_validator)) ;
  register0 S.force_bootstrapped (fun chain_store () b ->
      match Validator.get validator (Store.Chain.chain_id chain_store) with
      | Error _ -> Lwt.fail Not_found
      | Ok chain_validator ->
          Chain_validator.force_bootstrapped chain_validator b >>= return) ;
  (* blocks *)
  register0 S.Blocks.list (fun chain q () ->
      list_blocks chain ?length:q#length ?min_date:q#min_date q#heads) ;
  register_dynamic_directory2
    Block_services.path
    Block_directory.build_rpc_directory ;
  (* invalid_blocks *)
  register0 S.Invalid_blocks.list (fun chain_store () () ->
      let convert (hash, {Store_types.level; errors}) = {hash; level; errors} in
      Store.Block.read_invalid_blocks chain_store >>= fun invalid_blocks_map ->
      let blocks = Block_hash.Map.bindings invalid_blocks_map in
      return (List.map convert blocks)) ;
  register1 S.Invalid_blocks.get (fun chain_store hash () () ->
      Store.Block.read_invalid_block_opt chain_store hash >>= function
      | None -> Lwt.fail Not_found
      | Some {level; errors} -> return {hash; level; errors}) ;
  register1 S.Invalid_blocks.delete (fun chain_store hash () () ->
      Store.Block.unmark_invalid chain_store hash) ;
  !dir

let build_rpc_directory validator =
  let distributed_db = Validator.distributed_db validator in
  let store = Distributed_db.store distributed_db in
  let dir = ref (rpc_directory validator) in
  (* Mempool *)
  let merge d = dir := RPC_directory.merge !dir d in
  merge
    (RPC_directory.map
       (fun chain_store ->
         match Validator.get validator (Store.Chain.chain_id chain_store) with
         | Error _ -> Lwt.fail Not_found
         | Ok chain_validator ->
             Lwt.return (Chain_validator.prevalidator chain_validator))
       Prevalidator.rpc_directory) ;
  RPC_directory.prefix Chain_services.path
  @@ RPC_directory.map (fun ((), chain) -> get_chain_store_exn store chain) !dir
