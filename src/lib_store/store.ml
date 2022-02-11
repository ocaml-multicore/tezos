(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

open Store_types
open Store_errors

module Shared = struct
  type 'a t = {mutable data : 'a; lock : Lwt_idle_waiter.t}

  let create data = {data; lock = Lwt_idle_waiter.create ()}

  let use {data; lock} f = Lwt_idle_waiter.task lock (fun () -> f data)

  (* Causes a deadlock if [use] or [update_with] is called inside [f] *)
  let locked_use {data; lock} f =
    Lwt_idle_waiter.force_idle lock (fun () -> f data)

  (* Updates the shared data [v] only when a new value is provided by
     the evaluation of [f]. Causes a deadlock if [use] or [locked_use]
     is called inside [f]. *)
  let update_with v f =
    Lwt_idle_waiter.force_idle v.lock (fun () ->
        f v.data >>=? function
        | (Some new_data, res) ->
            v.data <- new_data ;
            return res
        | (None, res) -> return res)
end

type store = {
  store_dir : [`Store_dir] Naming.directory;
  (* Mutability allows a back-reference from chain_store to store: not
     to be modified. *)
  (* Invariant : main_chain_store <> None *)
  mutable main_chain_store : chain_store option;
  context_index : Context.index;
  protocol_store : Protocol_store.t;
  allow_testchains : bool;
  protocol_watcher : Protocol_hash.t Lwt_watcher.input;
  global_block_watcher : (chain_store * block) Lwt_watcher.input;
}

and chain_store = {
  global_store : store;
  chain_id : Chain_id.t;
  chain_dir : [`Chain_dir] Naming.directory;
  chain_config : chain_config;
  block_store : Block_store.t;
  chain_state : chain_state Shared.t;
  (* Genesis is only on-disk: read-only except at creation *)
  genesis_block_data : block Stored_data.t;
  block_watcher : block Lwt_watcher.input;
  block_rpc_directories :
    (chain_store * block) RPC_directory.t Protocol_hash.Map.t
    Protocol_hash.Table.t;
  lockfile : Lwt_unix.file_descr;
}

and chain_state = {
  (* Following fields are not safe to update concurrently and must be
     manipulated carefuly: *)
  current_head_data : block_descriptor Stored_data.t;
  alternate_heads_data : block_descriptor list Stored_data.t;
  cementing_highwatermark_data : int32 option Stored_data.t;
  target_data : block_descriptor option Stored_data.t;
  checkpoint_data : block_descriptor Stored_data.t;
  (* Following fields are safe to update directly *)
  protocol_levels_data :
    Protocol_levels.activation_block Protocol_levels.t Stored_data.t;
  invalid_blocks_data : invalid_block Block_hash.Map.t Stored_data.t;
  forked_chains_data : Block_hash.t Chain_id.Map.t Stored_data.t;
  (* In memory-only: *)
  current_head : Block_repr.t;
  active_testchain : testchain option;
  mempool : Mempool.t;
  live_blocks : Block_hash.Set.t;
  live_operations : Operation_hash.Set.t;
  mutable live_data_cache :
    (Block_hash.t * Operation_hash.Set.t) Ringo.Ring.t option;
  prechecked_blocks : Block_repr.t Block_lru_cache.t;
}

and testchain = {forked_block : Block_hash.t; testchain_store : chain_store}

and block = Block_repr.t

type t = store

let current_head chain_store =
  Shared.use chain_store.chain_state (fun {current_head; _} ->
      Lwt.return current_head)

let caboose chain_store = Block_store.caboose chain_store.block_store

let checkpoint chain_store =
  Shared.use chain_store.chain_state (fun {checkpoint_data; _} ->
      Stored_data.get checkpoint_data)

let target chain_store =
  Shared.use chain_store.chain_state (fun {target_data; _} ->
      Stored_data.get target_data)

let savepoint chain_store = Block_store.savepoint chain_store.block_store

let genesis chain_store = chain_store.chain_config.genesis

let history_mode chain_store = chain_store.chain_config.history_mode

let read_ancestor_hash {block_store; _} ~distance hash =
  Block_store.get_hash block_store (Block (hash, distance))

let read_ancestor_hash_by_level chain_store head level =
  let distance = Int32.(to_int (sub (Block_repr.level head) level)) in
  read_ancestor_hash chain_store ~distance (Block_repr.hash head) >>= function
  | Ok (Some x) -> Lwt.return_some x
  | _ -> Lwt.return_none

(* Will that block be compatible with the current checkpoint and
   target. *)
let locked_is_acceptable_block chain_state (hash, level) =
  Stored_data.get chain_state.checkpoint_data
  >>= fun (_checkpoint_hash, checkpoint_level) ->
  (* The block must be above the checkpoint. *)
  if Compare.Int32.(checkpoint_level >= level) then Lwt.return_false
  else
    (* FIXME? should we read its predecessor at checkpoint level to
       see if it's the same? *)
    Stored_data.get chain_state.target_data
    >|= Option.fold ~none:true ~some:(fun (target_hash, target_level) ->
            if Compare.Int32.(level = target_level) then
              Block_hash.equal hash target_hash
            else true)

let create_lockfile chain_dir =
  protect (fun () ->
      Lwt_unix.openfile
        (Naming.lock_file chain_dir |> Naming.file_path)
        [Unix.O_CREAT; O_RDWR; O_CLOEXEC; O_SYNC]
        0o644
      >>= return)

let lock_for_write lockfile = Lwt_unix.lockf lockfile Unix.F_LOCK 0

let lock_for_read lockfile = Lwt_unix.lockf lockfile Unix.F_RLOCK 0

let unlock lockfile = Lwt_unix.lockf lockfile Unix.F_ULOCK 0

let try_lock_for_write lockfile =
  Lwt.catch
    (fun () ->
      Lwt_unix.lockf lockfile Unix.F_TLOCK 0 >>= fun () -> Lwt.return_true)
    (fun _ -> Lwt.return_false)

let may_unlock lockfile = Unit.catch_s (fun () -> unlock lockfile)

module Block = struct
  type nonrec block = block

  type t = block

  type metadata = Block_repr.metadata = {
    message : string option;
    max_operations_ttl : int;
    last_allowed_fork_level : Int32.t;
    block_metadata : Bytes.t;
    operations_metadata : Bytes.t list list;
  }

  let equal b b' = Block_hash.equal (Block_repr.hash b) (Block_repr.hash b')

  let descriptor blk = Block_repr.descriptor blk

  (* I/O operations *)

  let is_known_valid {block_store; _} hash =
    Block_store.(mem block_store (Block (hash, 0))) >>= function
    | Ok k -> Lwt.return k
    | Error _ ->
        (* should never happen : (0 \in N) *)
        Lwt.return_false

  let locked_is_known_invalid chain_state hash =
    Stored_data.get chain_state.invalid_blocks_data >>= fun invalid_blocks ->
    Lwt.return (Block_hash.Map.mem hash invalid_blocks)

  let is_known_invalid {chain_state; _} hash =
    Shared.use chain_state (fun chain_state ->
        locked_is_known_invalid chain_state hash)

  let is_known_prechecked {chain_state; _} hash =
    Shared.use chain_state (fun {prechecked_blocks; _} ->
        match Block_lru_cache.find_opt prechecked_blocks hash with
        | None -> Lwt.return_false
        | Some t -> (
            t >>= function
            | None -> Lwt.return_false
            | Some _ -> Lwt.return_true))

  let is_known chain_store hash =
    is_known_valid chain_store hash >>= fun is_known ->
    if is_known then Lwt.return_true else is_known_invalid chain_store hash

  let validity chain_store hash =
    is_known chain_store hash >>= function
    | false -> Lwt.return Block_locator.Unknown
    | true -> (
        is_known_invalid chain_store hash >>= function
        | true -> Lwt.return Block_locator.Known_invalid
        | false -> Lwt.return Block_locator.Known_valid)

  let is_genesis chain_store hash =
    let genesis = genesis chain_store in
    Block_hash.equal hash genesis.Genesis.block

  let read_block {block_store; _} ?(distance = 0) hash =
    Block_store.read_block
      ~read_metadata:false
      block_store
      (Block (hash, distance))
    >>=? function
    | None -> fail @@ Block_not_found {hash; distance}
    | Some block -> return block

  let read_block_metadata ?(distance = 0) chain_store hash =
    Block_store.read_block_metadata
      chain_store.block_store
      (Block (hash, distance))

  let read_block_metadata_opt ?distance chain_store hash =
    read_block_metadata ?distance chain_store hash >>= function
    | Ok v -> Lwt.return v
    | Error _ -> Lwt.return_none

  let get_block_metadata_opt chain_store block =
    match Block_repr.metadata block with
    | Some metadata -> Lwt.return_some metadata
    | None -> (
        read_block_metadata_opt chain_store block.hash >>= function
        | Some metadata ->
            (* Put the metadata in cache *)
            block.metadata <- Some metadata ;
            Lwt.return_some metadata
        | None -> Lwt.return_none)

  let get_block_metadata chain_store block =
    get_block_metadata_opt chain_store block >>= function
    | Some metadata -> return metadata
    | None -> fail (Block_metadata_not_found (Block_repr.hash block))

  let read_block_opt chain_store ?(distance = 0) hash =
    read_block chain_store ~distance hash >>= function
    | Ok block -> Lwt.return_some block
    | Error _ -> Lwt.return_none

  let read_predecessor chain_store block =
    read_block chain_store (Block_repr.predecessor block)

  let read_predecessor_opt chain_store block =
    read_predecessor chain_store block >>= function
    | Ok block -> Lwt.return_some block
    | Error _ -> Lwt.return_none

  let read_ancestor_hash chain_store ~distance hash =
    read_ancestor_hash chain_store ~distance hash

  let read_ancestor_hash_opt chain_store ~distance hash =
    read_ancestor_hash chain_store ~distance hash >>= function
    | Ok v -> Lwt.return v
    | Error _ -> Lwt.return_none

  let read_predecessor_of_hash_opt chain_store hash =
    read_ancestor_hash_opt chain_store ~distance:1 hash >>= function
    | Some hash -> read_block_opt chain_store hash
    | None -> Lwt.return_none

  let read_predecessor_of_hash chain_store hash =
    read_predecessor_of_hash_opt chain_store hash >>= function
    | Some b -> return b
    | None -> fail @@ Block_not_found {hash; distance = 0}

  let locked_read_block_by_level chain_store head level =
    let distance = Int32.(to_int (sub (Block_repr.level head) level)) in
    if distance < 0 then
      fail
        (Bad_level
           {
             head_level = Block_repr.level head;
             given_level = Int32.of_int distance;
           })
    else read_block chain_store ~distance (Block_repr.hash head)

  let locked_read_block_by_level_opt chain_store head level =
    locked_read_block_by_level chain_store head level >>= function
    | Error _ -> Lwt.return_none
    | Ok b -> Lwt.return_some b

  let read_block_by_level chain_store level =
    current_head chain_store >>= fun current_head ->
    locked_read_block_by_level chain_store current_head level

  let read_block_by_level_opt chain_store level =
    current_head chain_store >>= fun current_head ->
    locked_read_block_by_level_opt chain_store current_head level

  let read_prechecked_block_opt {chain_state; _} hash =
    Shared.use chain_state (fun {prechecked_blocks; _} ->
        match Block_lru_cache.find_opt prechecked_blocks hash with
        | None -> Lwt.return_none
        | Some t -> t)

  let read_prechecked_block chain_store hash =
    read_prechecked_block_opt chain_store hash >>= function
    | Some b -> return b
    | None -> fail (Block_not_found {hash; distance = 0})

  let store_block chain_store ~block_header ~operations validation_result =
    let {
      Block_validation.validation_store =
        {
          context_hash;
          timestamp = _;
          message;
          max_operations_ttl;
          last_allowed_fork_level;
        };
      block_metadata;
      ops_metadata;
      block_metadata_hash;
      ops_metadata_hashes;
    } =
      validation_result
    in
    let bytes = Block_header.to_bytes block_header in
    let hash = Block_header.hash_raw bytes in
    let operations_length = List.length operations in
    let operation_metadata_length = List.length ops_metadata in
    let validation_passes = block_header.shell.validation_passes in
    fail_unless
      (validation_passes = operations_length)
      (Cannot_store_block
         ( hash,
           Invalid_operations_length
             {validation_passes; operations = operations_length} ))
    >>=? fun () ->
    fail_unless
      (validation_passes = operation_metadata_length)
      (Cannot_store_block
         ( hash,
           Invalid_operations_length
             {validation_passes; operations = operation_metadata_length} ))
    >>=? fun () ->
    fail_unless
      (List.for_all2
         ~when_different_lengths:(`X "unreachable")
         (fun l1 l2 -> Compare.List_lengths.(l1 = l2))
         operations
         ops_metadata
       |> function
       | Ok b -> b
       | _ -> assert false)
      (let to_string l =
         Format.asprintf
           "[%a]"
           (Format.pp_print_list
              ~pp_sep:(fun fmt () -> Format.fprintf fmt "; ")
              (fun ppf l -> Format.fprintf ppf "[%d]" (List.length l)))
           l
       in
       Cannot_store_block
         ( hash,
           Inconsistent_operations_lengths
             {
               operations_lengths = to_string operations;
               operations_data_lengths = to_string ops_metadata;
             } ))
    >>=? fun () ->
    Stored_data.get chain_store.genesis_block_data >>= fun genesis_block ->
    let is_main_chain =
      Chain_id.equal
        chain_store.chain_id
        (WithExceptions.Option.get
           ~loc:__LOC__
           chain_store.global_store.main_chain_store)
          .chain_id
    in
    let genesis_level = Block_repr.level genesis_block in
    (if is_main_chain then
     fail_unless
       Compare.Int32.(last_allowed_fork_level >= genesis_level)
       (Cannot_store_block
          ( hash,
            Invalid_last_allowed_fork_level
              {last_allowed_fork_level; genesis_level} ))
     >>=? fun () -> return last_allowed_fork_level
    else if Compare.Int32.(last_allowed_fork_level < genesis_level) then
      (* Hack: on the testchain, the block's lafl depends on the
         lafl and is not max(genesis_level, expected_lafl) *)
      return genesis_level
    else return last_allowed_fork_level)
    >>=? fun last_allowed_fork_level ->
    is_known_valid chain_store hash >>= function
    | true -> return_none
    | false ->
        (* Safety check: never ever commit a block that is not
           compatible with the current checkpoint/target. *)
        Shared.use chain_store.chain_state (fun chain_state ->
            locked_is_acceptable_block
              chain_state
              (hash, block_header.shell.level)
            >>= fun acceptable_block ->
            locked_is_known_invalid chain_state hash >>= fun known_invalid ->
            Lwt.return (acceptable_block, known_invalid))
        >>= fun (acceptable_block, known_invalid) ->
        fail_unless
          acceptable_block
          (Validation_errors.Checkpoint_error (hash, None))
        >>=? fun () ->
        fail_when
          known_invalid
          Store_errors.(Cannot_store_block (hash, Invalid_block))
        >>=? fun () ->
        fail_unless
          (Context_hash.equal block_header.shell.context context_hash)
          (Validation_errors.Inconsistent_hash
             (context_hash, block_header.shell.context))
        >>=? fun () ->
        let contents =
          {
            Block_repr.header = block_header;
            operations;
            block_metadata_hash;
            operations_metadata_hashes = ops_metadata_hashes;
          }
        in
        let metadata =
          Some
            {
              message;
              max_operations_ttl;
              last_allowed_fork_level;
              block_metadata;
              operations_metadata = ops_metadata;
            }
        in
        let block = {Block_repr.hash; contents; metadata} in
        Block_store.store_block chain_store.block_store block >>=? fun () ->
        Store_events.(emit store_block) (hash, block_header.shell.level)
        >>= fun () ->
        Shared.use chain_store.chain_state (fun {prechecked_blocks; _} ->
            Block_lru_cache.remove prechecked_blocks hash ;
            Lwt.return_unit)
        >>= fun () ->
        Lwt_watcher.notify chain_store.block_watcher block ;
        Lwt_watcher.notify
          chain_store.global_store.global_block_watcher
          (chain_store, block) ;
        return_some block

  let store_prechecked_block chain_store ~hash ~block_header ~operations =
    let operations_length = List.length operations in
    let validation_passes = block_header.Block_header.shell.validation_passes in
    fail_unless
      (validation_passes = operations_length)
      (Cannot_store_block
         ( hash,
           Invalid_operations_length
             {validation_passes; operations = operations_length} ))
    >>=? fun () ->
    let block =
      {
        Block_repr.hash;
        contents =
          {
            header = block_header;
            operations;
            block_metadata_hash = None;
            operations_metadata_hashes = None;
          };
        metadata = None;
      }
    in
    Shared.use chain_store.chain_state (fun {prechecked_blocks; _} ->
        Block_lru_cache.replace prechecked_blocks hash (Lwt.return_some block) ;
        Lwt.return_unit)
    >>= fun () ->
    Store_events.(emit store_prechecked_block) (hash, block_header.shell.level)
    >>= return

  let context_exn chain_store block =
    let context_index = chain_store.global_store.context_index in
    Context.checkout_exn context_index (Block_repr.context block)

  let context_opt chain_store block =
    let context_index = chain_store.global_store.context_index in
    Context.checkout context_index (Block_repr.context block)

  let context chain_store block =
    context_opt chain_store block >>= function
    | Some context -> return context
    | None ->
        fail
          (Cannot_checkout_context
             (Block_repr.hash block, Block_repr.context block))

  let context_exists chain_store block =
    let context_index = chain_store.global_store.context_index in
    Context.exists context_index (Block_repr.context block)

  let testchain_status chain_store block =
    (context_opt chain_store block >>= function
     | Some ctxt -> return ctxt
     | None ->
         fail
           (Cannot_checkout_context
              (Block_repr.hash block, Block_repr.context block)))
    >>=? fun context ->
    Context.get_test_chain context >>= fun status ->
    match status with
    | Running {genesis; _} ->
        Shared.use chain_store.chain_state (fun chain_state ->
            Stored_data.get chain_state.forked_chains_data
            >>= fun forked_chains ->
            let testchain_id = Context.compute_testchain_chain_id genesis in
            let forked_hash_opt =
              Chain_id.Map.find testchain_id forked_chains
            in
            return (status, forked_hash_opt))
    | Forking _ -> return (status, Some (Block_repr.hash block))
    | Not_running -> return (status, None)

  let protocol_hash chain_store block =
    Shared.use chain_store.chain_state (fun chain_state ->
        Stored_data.get chain_state.protocol_levels_data
        >>= fun protocol_levels ->
        let open Protocol_levels in
        let proto_level = Block_repr.proto_level block in
        match find proto_level protocol_levels with
        | Some {protocol; _} -> return protocol
        | None -> fail (Cannot_find_protocol proto_level))

  let protocol_hash_exn chain_store block =
    protocol_hash chain_store block >>= function
    | Ok ph -> Lwt.return ph
    | Error _ -> Lwt.fail Not_found

  (** Operations on invalid blocks *)

  let read_invalid_block_opt {chain_state; _} hash =
    Shared.use chain_state (fun chain_state ->
        Stored_data.get chain_state.invalid_blocks_data
        >>= fun invalid_blocks ->
        Lwt.return (Block_hash.Map.find hash invalid_blocks))

  let read_invalid_blocks {chain_state; _} =
    Shared.use chain_state (fun chain_state ->
        Stored_data.get chain_state.invalid_blocks_data)

  let mark_invalid chain_store hash ~level errors =
    if is_genesis chain_store hash then fail Invalid_genesis_marking
    else
      Shared.use chain_store.chain_state (fun chain_state ->
          Stored_data.update_with
            chain_state.invalid_blocks_data
            (fun invalid_blocks ->
              Lwt.return
                (Block_hash.Map.add hash {level; errors} invalid_blocks)))
      >>=? fun () -> return_unit

  let unmark_invalid {chain_state; _} hash =
    Shared.use chain_state (fun chain_state ->
        Stored_data.update_with
          chain_state.invalid_blocks_data
          (fun invalid_blocks ->
            Lwt.return (Block_hash.Map.remove hash invalid_blocks)))

  (** Accessors *)

  let hash blk = Block_repr.hash blk

  let header blk = Block_repr.header blk

  let operations blk = Block_repr.operations blk

  let shell_header blk = Block_repr.shell_header blk

  let level blk = Block_repr.level blk

  let proto_level blk = Block_repr.proto_level blk

  let predecessor blk = Block_repr.predecessor blk

  let timestamp blk = Block_repr.timestamp blk

  let operations_hash blk = Block_repr.operations_hash blk

  let validation_passes blk = Block_repr.validation_passes blk

  let fitness blk = Block_repr.fitness blk

  let context_hash blk = Block_repr.context blk

  let protocol_data blk = Block_repr.protocol_data blk

  let block_metadata_hash blk = Block_repr.block_metadata_hash blk

  let operations_metadata_hashes blk = Block_repr.operations_metadata_hashes blk

  let operations_metadata_hashes_path block i =
    if i < 0 || (header block).shell.validation_passes <= i then
      invalid_arg "operations_metadata_hashes_path" ;
    Option.map
      (fun ll -> List.nth ll i |> WithExceptions.Option.get ~loc:__LOC__)
      (Block_repr.operations_metadata_hashes block)

  let all_operations_metadata_hash blk =
    (* Special case: for genesis, do not commit operation metadatas *)
    if validation_passes blk = 0 then None
    else
      Option.map
        (fun ll ->
          Operation_metadata_list_list_hash.compute
            (List.map Operation_metadata_list_hash.compute ll))
        (Block_repr.operations_metadata_hashes blk)

  (** Metadata accessors *)

  let message metadata = Block_repr.message metadata

  let max_operations_ttl metadata = Block_repr.max_operations_ttl metadata

  let last_allowed_fork_level metadata =
    Block_repr.last_allowed_fork_level metadata

  let block_metadata metadata = Block_repr.block_metadata metadata

  let operations_metadata metadata = Block_repr.operations_metadata metadata

  let compute_operation_path hashes =
    let list_hashes = List.map Operation_list_hash.compute hashes in
    Operation_list_list_hash.compute_path list_hashes

  let operations_path block i =
    if i < 0 || validation_passes block <= i then invalid_arg "operations_path" ;
    let ops = operations block in
    let hashes = List.(map (map Operation.hash)) ops in
    let path = compute_operation_path hashes in
    (List.nth ops i |> WithExceptions.Option.get ~loc:__LOC__, path i)

  let operations_hashes_path block i =
    if i < 0 || (header block).shell.validation_passes <= i then
      invalid_arg "operations_hashes_path" ;
    let opss = operations block in
    let hashes = List.(map (map Operation.hash)) opss in
    let path = compute_operation_path hashes in
    (List.nth hashes i |> WithExceptions.Option.get ~loc:__LOC__, path i)

  let all_operation_hashes block =
    List.(map (map Operation.hash)) (operations block)
end

module Chain_traversal = struct
  let path chain_store ~from_block ~to_block =
    if not Compare.Int32.(Block.level from_block <= Block.level to_block) then
      invalid_arg "Chain_traversal.path" ;
    let rec loop acc current =
      if Block.equal from_block current then Lwt.return_some acc
      else
        Block.read_predecessor_opt chain_store current >>= function
        | Some pred -> loop (current :: acc) pred
        | None -> Lwt.return_none
    in
    loop [] to_block

  let common_ancestor chain_store b1 b2 =
    let rec loop b1 b2 =
      if Block.equal b1 b2 then Lwt.return_some b1
      else if Compare.Int32.(Block.level b1 <= Block.level b2) then
        Block.read_predecessor_opt chain_store b2 >>= function
        | None -> Lwt.return_none
        | Some b2 -> loop b1 b2
      else
        Block.read_predecessor_opt chain_store b1 >>= function
        | None -> Lwt.return_none
        | Some b1 -> loop b1 b2
    in
    loop b1 b2

  let new_blocks chain_store ~from_block ~to_block =
    common_ancestor chain_store from_block to_block >>= function
    | None -> assert false
    | Some ancestor -> (
        path chain_store ~from_block:ancestor ~to_block >>= function
        | None -> Lwt.return (ancestor, [])
        | Some path -> Lwt.return (ancestor, path))

  let folder chain_store block n f init =
    let rec loop acc block_head n =
      let hashes = Block.all_operation_hashes block_head in
      let acc = f acc (Block.hash block_head, hashes) in
      if n = 0 then Lwt.return acc
      else
        Block.read_predecessor_opt chain_store block_head >>= function
        | None -> Lwt.return acc
        | Some predecessor -> loop acc predecessor (pred n)
    in
    loop init block n

  let live_blocks chain_store block n =
    let fold (bacc, oacc) (head_hash, op_hashes) =
      let bacc = Block_hash.Set.add head_hash bacc in
      let oacc =
        List.fold_left
          (List.fold_left (fun oacc op -> Operation_hash.Set.add op oacc))
          oacc
          op_hashes
      in
      (bacc, oacc)
    in
    let init = (Block_hash.Set.empty, Operation_hash.Set.empty) in
    folder chain_store block n fold init

  let live_blocks_with_ring chain_store block n ring =
    let fold acc (head_hash, op_hashes) =
      let op_hash_set = Operation_hash.Set.(of_list (List.flatten op_hashes)) in
      (head_hash, op_hash_set) :: acc
    in
    folder chain_store block n fold [] >>= fun l ->
    (* Don't revert the list so we can add them in the correct order. *)
    Ringo.Ring.add_list ring l ;
    Lwt.return_unit
end

module Chain = struct
  type nonrec chain_store = chain_store

  type t = chain_store

  type nonrec testchain = testchain

  type block_identifier = Block_services.block

  let global_store {global_store; _} = global_store

  let chain_id chain_store = chain_store.chain_id

  let chain_dir chain_store = chain_store.chain_dir

  let history_mode chain_store = history_mode chain_store

  let set_history_mode chain_store history_mode =
    let chain_config = {chain_store.chain_config with history_mode} in
    Stored_data.write_file
      (Naming.chain_config_file chain_store.chain_dir)
      chain_config

  let genesis chain_store = genesis chain_store

  let genesis_block chain_store = Stored_data.get chain_store.genesis_block_data

  let expiration chain_store = chain_store.chain_config.expiration

  let checkpoint chain_store = checkpoint chain_store

  let target chain_store = target chain_store

  let savepoint chain_store = savepoint chain_store

  let unsafe_set_savepoint chain_store new_savepoint =
    Block_store.write_savepoint chain_store.block_store new_savepoint

  let caboose chain_store = caboose chain_store

  let unsafe_set_caboose chain_store new_caboose =
    Block_store.write_caboose chain_store.block_store new_caboose

  let current_head chain_store = current_head chain_store

  let mempool chain_store =
    Shared.use chain_store.chain_state (fun {mempool; _} -> Lwt.return mempool)

  let block_of_identifier chain_store =
    let not_found () = fail_with_exn Not_found in
    function
    | `Genesis -> genesis_block chain_store >>= return
    | `Head n ->
        current_head chain_store >>= fun current_head ->
        if n < 0 then not_found ()
        else if n = 0 then return current_head
        else Block.read_block chain_store ~distance:n (Block.hash current_head)
    | (`Alias (_, n) | `Hash (_, n)) as b ->
        (match b with
        | `Alias (`Checkpoint, _) -> checkpoint chain_store >|= fst
        | `Alias (`Savepoint, _) -> savepoint chain_store >|= fst
        | `Alias (`Caboose, _) -> caboose chain_store >|= fst
        | `Hash (h, _) -> Lwt.return h)
        >>= fun hash ->
        if n < 0 then
          Block.read_block chain_store hash >>=? fun block ->
          current_head chain_store >>= fun current_head ->
          let head_level = Block.level current_head in
          let block_level = Block.level block in
          let distance =
            Int32.(to_int (sub head_level (sub block_level (of_int n))))
          in
          if distance < 0 then not_found ()
          else Block.read_block chain_store ~distance (Block.hash current_head)
        else Block.read_block chain_store ~distance:n hash
    | `Level i ->
        if Compare.Int32.(i < 0l) then not_found ()
        else Block.read_block_by_level chain_store i

  let block_of_identifier_opt chain_store identifier =
    block_of_identifier chain_store identifier >>= function
    | Ok block -> Lwt.return_some block
    | Error _ -> Lwt.return_none

  let set_mempool chain_store ~head mempool =
    Shared.update_with chain_store.chain_state (fun chain_state ->
        Stored_data.get chain_state.current_head_data
        >>= fun current_head_descr ->
        if Block_hash.equal head (fst current_head_descr) then
          return (Some {chain_state with mempool}, ())
        else return (None, ()))

  let live_blocks chain_store =
    Shared.use chain_store.chain_state (fun {live_blocks; live_operations; _} ->
        Lwt.return (live_blocks, live_operations))

  let locked_compute_live_blocks ?(force = false) ?(update_cache = true)
      chain_store chain_state block metadata =
    let {current_head; live_blocks; live_operations; live_data_cache; _} =
      chain_state
    in
    if Block.equal current_head block && not force then
      Lwt.return (live_blocks, live_operations)
    else
      (* We actually compute max_op_ttl + 1... *)
      let expected_capacity = Block.max_operations_ttl metadata + 1 in
      match live_data_cache with
      | Some live_data_cache
        when update_cache
             && Block_hash.equal
                  (Block.predecessor block)
                  (Block.hash current_head)
             && Ringo.Ring.capacity live_data_cache = expected_capacity -> (
          let most_recent_block = Block.hash block in
          let most_recent_ops =
            Block.all_operation_hashes block
            |> List.flatten |> Operation_hash.Set.of_list
          in
          let new_live_blocks =
            Block_hash.Set.add most_recent_block live_blocks
          in
          let new_live_operations =
            Operation_hash.Set.union most_recent_ops live_operations
          in
          match
            Ringo.Ring.add_and_return_erased
              live_data_cache
              (most_recent_block, most_recent_ops)
          with
          | None -> Lwt.return (new_live_blocks, new_live_operations)
          | Some (last_block, last_ops) ->
              let diffed_new_live_blocks =
                Block_hash.Set.remove last_block new_live_blocks
              in
              let diffed_new_live_operations =
                Operation_hash.Set.diff new_live_operations last_ops
              in
              Lwt.return (diffed_new_live_blocks, diffed_new_live_operations))
      | _ when update_cache ->
          let new_cache = Ringo.Ring.create expected_capacity in
          Chain_traversal.live_blocks_with_ring
            chain_store
            block
            expected_capacity
            new_cache
          >>= fun () ->
          chain_state.live_data_cache <- Some new_cache ;
          let (live_blocks, live_ops) =
            Ringo.Ring.fold
              new_cache
              ~init:(Block_hash.Set.empty, Operation_hash.Set.empty)
              ~f:(fun (bhs, opss) (bh, ops) ->
                (Block_hash.Set.add bh bhs, Operation_hash.Set.union ops opss))
          in
          Lwt.return (live_blocks, live_ops)
      | _ ->
          Chain_traversal.live_blocks chain_store block expected_capacity
          >>= fun (live_blocks, live_ops) -> Lwt.return (live_blocks, live_ops)

  let compute_live_blocks chain_store ~block =
    Shared.use chain_store.chain_state (fun chain_state ->
        Block.get_block_metadata chain_store block >>=? fun metadata ->
        locked_compute_live_blocks
          ~update_cache:false
          chain_store
          chain_state
          block
          metadata
        >>= return)

  let is_ancestor chain_store ~head:(hash, lvl) ~ancestor:(hash', lvl') =
    if Compare.Int32.(lvl' > lvl) then Lwt.return_false
    else if Compare.Int32.(lvl = lvl') then
      Lwt.return (Block_hash.equal hash hash')
    else
      Block.read_ancestor_hash_opt
        chain_store
        hash
        ~distance:Int32.(to_int (sub lvl lvl'))
      >>= function
      | None -> Lwt.return_false
      | Some hash_found -> Lwt.return (Block_hash.equal hash' hash_found)

  let is_in_chain chain_store (hash, level) =
    current_head chain_store >>= fun current_head ->
    is_ancestor
      chain_store
      ~head:Block.(hash current_head, level current_head)
      ~ancestor:(hash, level)

  (* FIXME: this should not be hard-coded *)
  let max_locator_size = 200

  let compute_locator_from_hash chain_store ?(max_size = max_locator_size)
      ?min_level (head_hash, head_header) seed =
    Shared.use chain_store.chain_state (fun chain_state ->
        match min_level with
        | None -> Block_store.caboose chain_store.block_store
        | Some min_level -> (
            Block.locked_read_block_by_level_opt
              chain_store
              chain_state.current_head
              min_level
            >>= function
            | None ->
                (* should not happen *)
                Block_store.caboose chain_store.block_store
            | Some b -> Lwt.return (Block_repr.descriptor b)))
    >>= fun (caboose, _) ->
    let get_predecessor =
      match min_level with
      | None ->
          fun h n -> Block.read_ancestor_hash_opt chain_store h ~distance:n
      | Some min_level -> (
          fun h n ->
            Block.read_block_opt chain_store h ~distance:n >>= function
            | None -> Lwt.return_none
            | Some pred ->
                if Compare.Int32.(Block_repr.level pred < min_level) then
                  Lwt.return_none
                else Lwt.return_some (Block_repr.hash pred))
    in
    Block_locator.compute
      ~get_predecessor
      ~caboose
      ~size:max_size
      head_hash
      head_header
      seed

  let compute_locator chain_store ?(max_size = 200) head seed =
    caboose chain_store >>= fun (caboose, _caboose_level) ->
    Block_locator.compute
      ~get_predecessor:(fun h n ->
        Block.read_ancestor_hash_opt chain_store h ~distance:n)
      ~caboose
      ~size:max_size
      head.Block_repr.hash
      head.Block_repr.contents.header
      seed

  let compute_protocol_locator chain_store ?max_size ~proto_level seed =
    Shared.use chain_store.chain_state (fun chain_state ->
        Stored_data.get chain_state.protocol_levels_data
        >>= fun protocol_levels ->
        match Protocol_levels.find proto_level protocol_levels with
        | None -> Lwt.return_none
        | Some {block; _} -> (
            let block_activation_level = snd block in
            (* proto level's lower bound found, now retrieving the upper bound *)
            let head_proto_level =
              Block_repr.proto_level chain_state.current_head
            in
            if Compare.Int.(proto_level = head_proto_level) then
              Lwt.return_some
                ( block_activation_level,
                  Block_repr.
                    ( hash chain_state.current_head,
                      header chain_state.current_head ) )
            else
              match Protocol_levels.find (succ proto_level) protocol_levels with
              | None -> Lwt.return_none
              | Some {block; _} -> (
                  let next_activation_level = snd block in
                  let last_level_in_protocol =
                    Int32.(pred next_activation_level)
                  in
                  Block.locked_read_block_by_level_opt
                    chain_store
                    chain_state.current_head
                    last_level_in_protocol
                  >>= function
                  | None -> Lwt.return_none
                  | Some pred ->
                      Lwt.return_some
                        ( block_activation_level,
                          Block_repr.(hash pred, header pred) ))))
    >>= function
    | None -> Lwt.return_none
    | Some (block_activation_level, upper_block) ->
        compute_locator_from_hash
          chain_store
          ?max_size
          ~min_level:block_activation_level
          upper_block
          seed
        >>= Lwt.return_some

  (* Hypothesis:
     \forall x. x \in current_head \union alternate_heads | new_head
     is not a predecessor of x *)
  let locked_update_and_trim_alternate_heads chain_store chain_state
      ~new_checkpoint ~new_head =
    Stored_data.get chain_state.current_head_data >>= fun prev_head_descr ->
    Stored_data.get chain_state.alternate_heads_data
    >>= fun prev_alternate_heads ->
    let new_head_descr = Block.descriptor new_head in
    is_ancestor chain_store ~head:new_head_descr ~ancestor:prev_head_descr
    >>= function
    | true ->
        (* If the new head is a successor of prev_head, do nothing
           particular, just trim alternate heads which are anchored
           below the checkpoint. *)
        Lwt_list.filter_s
          (fun alternate_head ->
            is_ancestor
              chain_store
              ~head:alternate_head
              ~ancestor:new_checkpoint)
          prev_alternate_heads
    | false ->
        (* If the new head is not a successor of prev_head. *)
        (* 2 cases:
           - new_head is a new branch => not a successor of any alternate_heads;
           - new_head is a successor of a previous alternate head. *)
        Lwt_list.filter_s
          (fun alternate_head ->
            is_ancestor
              chain_store
              ~head:new_head_descr
              ~ancestor:alternate_head
            >>= function
            | true ->
                (* If the new head is a successor of a former
                   alternate_head, remove it from the alternate heads,
                   it will be updated as the current head *)
                Lwt.return_false
            | false ->
                (* Only retain alternate_heads that are successor of the
                   new_checkpoint *)
                is_ancestor
                  chain_store
                  ~head:alternate_head
                  ~ancestor:new_checkpoint)
          prev_alternate_heads
        >>= fun filtered_alternate_heads ->
        (* Promote prev_head as an alternate head *)
        Lwt.return (prev_head_descr :: filtered_alternate_heads)

  let locked_is_heads_predecessor chain_store chain_state ~new_head =
    Stored_data.get chain_state.current_head_data >>= fun current_head_descr ->
    Stored_data.get chain_state.alternate_heads_data >>= fun alternate_heads ->
    Lwt_list.exists_p
      (fun head -> is_ancestor chain_store ~head ~ancestor:new_head)
      (current_head_descr :: alternate_heads)

  let merge_finalizer chain_store (new_highest_cemented_level : int32) =
    (* Assumed invariant: two merges cannot occur concurrently *)
    (* new_highest_cemented_block should be set, even after a merge 0 *)
    (* Take the lock on the chain_state to avoid concurrent updates *)
    Shared.locked_use chain_store.chain_state (fun chain_state ->
        Stored_data.get chain_state.cementing_highwatermark_data
        >>= fun current_cementing_highwatermark ->
        match current_cementing_highwatermark with
        | None ->
            Stored_data.write
              chain_state.cementing_highwatermark_data
              (Some new_highest_cemented_level)
        | Some current_cementing_highwatermark ->
            if
              Compare.Int32.(
                current_cementing_highwatermark > new_highest_cemented_level)
            then
              (* Invariant error: should not happen but if it does, don't
                   mess anything by modifying the value. *)
              return_unit
            else
              Stored_data.write
                chain_state.cementing_highwatermark_data
                (Some new_highest_cemented_level))

  let may_update_checkpoint_and_target chain_store ~new_head ~new_head_lafl
      ~checkpoint ~target =
    let new_checkpoint =
      if Compare.Int32.(snd new_head_lafl > snd checkpoint) then new_head_lafl
      else checkpoint
    in
    match target with
    | None -> return (new_checkpoint, None)
    | Some target ->
        if Compare.Int32.(snd target < snd new_checkpoint) then assert false
        else if Compare.Int32.(snd target <= snd new_head) then
          is_ancestor chain_store ~head:new_head ~ancestor:target >>= function
          | true -> return (new_checkpoint, None)
          | false ->
              (* Impossible: a block is not acceptable to be stored if
                 it's not compatible with the target *)
              fail Target_mismatch
        else return (new_checkpoint, Some target)

  let locked_determine_cementing_highwatermark chain_store chain_state head_lafl
      =
    Stored_data.get chain_state.cementing_highwatermark_data
    >>= fun cementing_highwatermark ->
    match cementing_highwatermark with
    | Some cementing_highwatermark -> Lwt.return_some cementing_highwatermark
    | None -> (
        (* May result from a store recently imported from a snapshot *)
        let block_store = chain_store.block_store in
        let cemented_store = Block_store.cemented_block_store block_store in
        match
          Cemented_block_store.get_highest_cemented_level cemented_store
        with
        | Some hcb ->
            (* If we have cemented blocks, take the highest cemented level *)
            Lwt.return_some hcb
        | None ->
            (* If we don't, check that the head lafl is > caboose *)
            Block_store.caboose block_store >>= fun (_, caboose_level) ->
            if Compare.Int32.(head_lafl >= caboose_level) then
              Lwt.return_some head_lafl
            else Lwt.return_none)

  let locked_may_update_cementing_highwatermark chain_state
      new_cementing_highwatermark =
    Stored_data.get chain_state.cementing_highwatermark_data >>= function
    | None when new_cementing_highwatermark <> None ->
        Stored_data.write
          chain_state.cementing_highwatermark_data
          new_cementing_highwatermark
    | _ -> return_unit

  let set_head chain_store new_head =
    Shared.update_with chain_store.chain_state (fun chain_state ->
        (* The merge cannot finish until we release the lock on the
           chain state so its status cannot change while this
           function is executed. *)
        (* Also check the status to be extra-safe *)
        Block_store.status chain_store.block_store >>= fun store_status ->
        (match Block_store.get_merge_status chain_store.block_store with
        | Merge_failed errs ->
            (* If the merge has failed, notify in the logs but don't
               trigger any merge. *)
            Store_events.(emit notify_merge_error errs) >>= fun () ->
            (* We mark the merge as on-going to prevent the merge from
               being triggered and to update on-disk values. *)
            return_true
        | Not_running when store_status <> Idle ->
            (* Degenerate case, do the same as the Merge_failed case *)
            Store_events.(emit notify_merge_error []) >>= fun () -> return_true
        | Not_running -> return_false
        | Running -> return_true)
        >>=? fun is_merge_ongoing ->
        let previous_head = chain_state.current_head in
        Stored_data.get chain_state.checkpoint_data >>= fun checkpoint ->
        let new_head_descr = Block.descriptor new_head in
        (* Check that the new_head is consistent with the checkpoint *)
        fail_unless
          Compare.Int32.(Block.level new_head >= snd checkpoint)
          (Invalid_head_switch
             {checkpoint_level = snd checkpoint; given_head = new_head_descr})
        >>=? fun () ->
        (* Check that the new_head is not a predecessor of existing heads *)
        locked_is_heads_predecessor
          chain_store
          chain_state
          ~new_head:new_head_descr
        >>= fun is_heads_predecessor ->
        if is_heads_predecessor then
          (* Do not raise an error: this might be caused by
             intertwined [set_head] calls. *)
          return (None, None)
        else
          (* Check that its predecessor exists and has metadata *)
          let predecessor = Block.predecessor new_head in
          trace
            Bad_head_invariant
            ( Block.read_block chain_store predecessor >>=? fun pred_block ->
              (* check that prededecessor's block metadata are available *)
              Block.get_block_metadata chain_store pred_block
              >>=? fun _pred_head_metadata ->
              Block.get_block_metadata chain_store new_head )
          >>=? fun new_head_metadata ->
          Stored_data.get chain_state.target_data >>= fun target ->
          let new_head_lafl = Block.last_allowed_fork_level new_head_metadata in
          locked_determine_cementing_highwatermark
            chain_store
            chain_state
            new_head_lafl
          >>= fun cementing_highwatermark ->
          (* This write call will initialize the cementing
             highwatermark when it is not yet set or do nothing
             otherwise. *)
          locked_may_update_cementing_highwatermark
            chain_state
            cementing_highwatermark
          >>=? fun () ->
          Block.locked_read_block_by_level_opt
            chain_store
            new_head
            new_head_lafl
          >>= fun lafl_block_opt ->
          (match lafl_block_opt with
          | None ->
              (* This case may occur when importing a rolling
                 snapshot where the lafl block is not known.
                 We may use the checkpoint instead. *)
              return (checkpoint, target)
          | Some lafl_block ->
              may_update_checkpoint_and_target
                chain_store
                ~new_head:new_head_descr
                ~new_head_lafl:(Block.descriptor lafl_block)
                ~checkpoint
                ~target)
          >>=? fun (new_checkpoint, new_target) ->
          let should_merge =
            (* Make sure that the previous merge is completed before
               starting a new merge. If the lock on the chain_state is
               retained, the merge thread will never be able to
               complete. *)
            (not is_merge_ongoing)
            &&
            match cementing_highwatermark with
            | None ->
                (* Do not merge if the cementing highwatermark is not
                   set. *)
                false
            | Some cementing_highwatermark ->
                Compare.Int32.(new_head_lafl > cementing_highwatermark)
          in
          (if should_merge then
           try_lock_for_write chain_store.lockfile >>= function
           | false ->
               (* Delay the merge until the lock is available *)
               return cementing_highwatermark
           | true ->
               (* Lock on lockfile is now taken *)
               let finalizer new_highest_cemented_level =
                 merge_finalizer chain_store new_highest_cemented_level
                 >>=? fun () ->
                 may_unlock chain_store.lockfile >>= fun () -> return_unit
               in
               let on_error errs =
                 (* Release the lockfile *)
                 may_unlock chain_store.lockfile >>= fun () ->
                 Lwt.return (Error errs)
               in
               (* Notes:
                  - The lock will be released when the merge
                    terminates. i.e. in [finalizer] or in
                    [on_error].
                  - The heavy-work of this function is asynchronously
                    done so this call is expected to return quickly. *)
               Block_store.merge_stores
                 chain_store.block_store
                 ~on_error
                 ~finalizer
                 ~history_mode:(history_mode chain_store)
                 ~new_head
                 ~new_head_metadata
                 ~cementing_highwatermark:
                   (WithExceptions.Option.get
                      ~loc:__LOC__
                      cementing_highwatermark)
               >>=? fun () ->
               (* The new memory highwatermark is new_head_lafl, the disk
                  value will be updated after the merge completion. *)
               return (Some new_head_lafl)
          else return cementing_highwatermark)
          >>=? fun new_cementing_highwatermark ->
          (match new_cementing_highwatermark with
          | None -> Lwt.return new_checkpoint
          | Some new_cementing_highwatermark -> (
              if
                Compare.Int32.(
                  snd new_checkpoint >= new_cementing_highwatermark)
              then Lwt.return new_checkpoint
              else
                read_ancestor_hash_by_level
                  chain_store
                  new_head
                  new_cementing_highwatermark
                >>= function
                | None -> Lwt.return new_checkpoint
                | Some h -> Lwt.return (h, new_cementing_highwatermark)))
          >>= fun new_checkpoint ->
          locked_update_and_trim_alternate_heads
            chain_store
            chain_state
            ~new_checkpoint
            ~new_head
          >>= fun new_alternate_heads ->
          (if Compare.Int32.(snd new_checkpoint > snd checkpoint) then
           (* Remove potentially outdated invalid blocks if the
              checkpoint changed *)
           Stored_data.update_with
             chain_state.invalid_blocks_data
             (fun invalid_blocks ->
               Lwt.return
                 (Block_hash.Map.filter
                    (fun _k {level; _} -> level > snd new_checkpoint)
                    invalid_blocks))
          else return_unit)
          >>=? fun () ->
          (* Update values on disk but not the cementing highwatermark
             which will be updated by the merge finalizer. *)
          Stored_data.write chain_state.checkpoint_data new_checkpoint
          >>=? fun () ->
          Prometheus.Gauge.set
            Store_metrics.metrics.checkpoint_level
            (Int32.to_float (snd new_checkpoint)) ;
          Stored_data.write chain_state.current_head_data new_head_descr
          >>=? fun () ->
          Stored_data.write chain_state.alternate_heads_data new_alternate_heads
          >>=? fun () ->
          Prometheus.Gauge.set
            Store_metrics.metrics.alternate_heads_count
            (Int.to_float (List.length new_alternate_heads)) ;
          Stored_data.write chain_state.target_data new_target >>=? fun () ->
          (* Update live_data *)
          locked_compute_live_blocks
            ~update_cache:true
            chain_store
            chain_state
            new_head
            new_head_metadata
          >>= fun (live_blocks, live_operations) ->
          let new_chain_state =
            {
              chain_state with
              live_blocks;
              live_operations;
              current_head = new_head;
            }
          in
          Store_events.(emit set_head) new_head_descr >>= fun () ->
          return (Some new_chain_state, Some previous_head))

  let known_heads chain_store =
    Shared.use
      chain_store.chain_state
      (fun {current_head_data; alternate_heads_data; _} ->
        Stored_data.get current_head_data >>= fun current_head_descr ->
        Stored_data.get alternate_heads_data >>= fun alternate_heads ->
        Lwt.return (current_head_descr :: alternate_heads))

  (* TODO (later) check if that's ok *)
  let locked_is_valid_for_checkpoint chain_store chain_state
      (given_checkpoint_hash, given_checkpoint_level) =
    let current_head = chain_state.current_head in
    Block.get_block_metadata chain_store current_head
    >>=? fun current_head_metadata ->
    let head_lafl = Block.last_allowed_fork_level current_head_metadata in
    if Compare.Int32.(given_checkpoint_level <= head_lafl) then
      (* Cannot set a checkpoint before the current head's last
         allowed fork level *)
      return_false
    else
      Block.is_known_valid chain_store given_checkpoint_hash >>= function
      | false ->
          (* Given checkpoint is in the future: valid *)
          return_true
      | true -> (
          read_ancestor_hash
            chain_store
            ~distance:Int32.(to_int (sub given_checkpoint_level head_lafl))
            given_checkpoint_hash
          >>=? function
          | None ->
              (* The last allowed fork level is unknown, thus different from current head's lafl *)
              return_false
          | Some ancestor -> (
              read_ancestor_hash
                chain_store
                ~distance:
                  Int32.(to_int (sub (Block.level current_head) head_lafl))
                (Block.hash current_head)
              >>=? function
              | None -> fail Missing_last_allowed_fork_level_block
              | Some lafl_hash -> return (Block_hash.equal lafl_hash ancestor)))

  let is_valid_for_checkpoint chain_store given_checkpoint =
    Shared.use chain_store.chain_state (fun chain_state ->
        Block.locked_is_known_invalid chain_state (fst given_checkpoint)
        >>= function
        | true -> return_false
        | false ->
            locked_is_valid_for_checkpoint
              chain_store
              chain_state
              given_checkpoint)

  let best_known_head_for_checkpoint chain_store ~checkpoint =
    let (_, checkpoint_level) = checkpoint in
    current_head chain_store >>= fun current_head ->
    is_valid_for_checkpoint
      chain_store
      (Block.hash current_head, Block.level current_head)
    >>=? fun valid ->
    if valid then return current_head
    else
      let find_valid_predecessor hash =
        Block.read_block chain_store hash >>=? fun block ->
        if Compare.Int32.(Block_repr.level block < checkpoint_level) then
          return block
        else
          (* Read the checkpoint's predecessor *)
          Block.read_block
            chain_store
            hash
            ~distance:
              (1
              + (Int32.to_int
                @@ Int32.sub (Block_repr.level block) checkpoint_level))
      in
      known_heads chain_store >>= fun heads ->
      genesis_block chain_store >>= fun genesis ->
      let best = genesis in
      List.fold_left_es
        (fun best (hash, _level) ->
          find_valid_predecessor hash >>=? fun pred ->
          if Fitness.(Block.fitness pred > Block.fitness best) then return pred
          else return best)
        best
        heads

  let set_target chain_store new_target =
    Block_store.await_merging chain_store.block_store >>= fun () ->
    Shared.use chain_store.chain_state (fun chain_state ->
        Stored_data.get chain_state.checkpoint_data >>= fun checkpoint ->
        if Compare.Int32.(snd checkpoint > snd new_target) then
          is_ancestor chain_store ~head:checkpoint ~ancestor:new_target
          >>= function
          | true -> return_unit
          | false -> fail (Cannot_set_target new_target)
        else
          (* new_target > checkpoint *)
          Block.is_known_valid chain_store (fst new_target) >>= function
          | false -> (
              Block.locked_is_known_invalid chain_state (fst new_target)
              >>= function
              | true -> fail (Cannot_set_target new_target)
              | false ->
                  (* unknown block => new_target > all_heads *)
                  (* Write future-block as target, [set_head] will
                     update it correctly *)
                  Stored_data.write chain_state.target_data (Some new_target)
                  >>=? fun () ->
                  Store_events.(emit set_target) new_target >>= fun () ->
                  return_unit)
          | true ->
              trace
                (Cannot_set_target new_target)
                (* Do not store the target but update the chain data
                   according to the following cases:
                   1. Target is below known heads: filter heads
                      for which new_target is not an ancestor;
                   2. Target is above all heads: filter heads
                      that are not an ancestor of the new_target;
                   3. Target has no head as ancestor:
                      the new_target becomes the head.
                      (Side-note: I think the last case is ok) *)
                ( Stored_data.get chain_state.current_head_data
                >>= fun current_head_descr ->
                  Stored_data.get chain_state.alternate_heads_data
                  >>= fun alternate_heads ->
                  let all_heads = current_head_descr :: alternate_heads in
                  Lwt_list.filter_s
                    (fun block ->
                      is_ancestor chain_store ~head:block ~ancestor:new_target)
                    all_heads
                  >>= fun filtered_heads ->
                  let find_best_head heads =
                    assert (heads <> []) ;
                    let (first_alternate_head, alternate_heads) =
                      ( List.hd heads |> WithExceptions.Option.get ~loc:__LOC__,
                        List.tl heads |> WithExceptions.Option.get ~loc:__LOC__
                      )
                    in
                    Block.read_block chain_store (fst first_alternate_head)
                    >>=? fun first_block ->
                    List.fold_left_es
                      (fun best alternate_head ->
                        Block.read_block chain_store (fst alternate_head)
                        >>=? fun alternate_head ->
                        if
                          Fitness.(
                            Block.fitness best >= Block.fitness alternate_head)
                        then return best
                        else return alternate_head)
                      first_block
                      alternate_heads
                    >>=? fun best_head ->
                    return
                      ( best_head,
                        List.filter
                          (fun (hash, _) ->
                            not (Block_hash.equal (Block.hash best_head) hash))
                          all_heads )
                  in
                  (* Case 1 *)
                  (if filtered_heads <> [] then
                   find_best_head filtered_heads
                   >>=? fun (best_alternate_head, alternate_heads) ->
                   return (best_alternate_head, alternate_heads, new_target)
                  else
                    (* Case 2 *)
                    Lwt_list.filter_s
                      (fun block ->
                        is_ancestor chain_store ~head:new_target ~ancestor:block)
                      all_heads
                    >>= fun filtered_heads ->
                    if filtered_heads <> [] then
                      find_best_head filtered_heads
                      >>=? fun (best_alternate_head, alternate_heads) ->
                      return (best_alternate_head, alternate_heads, new_target)
                    else
                      (* Case 3 *)
                      Block.read_block chain_store (fst new_target)
                      >>=? fun target_block ->
                      return (target_block, [], new_target))
                  >>=? fun ( new_current_head,
                             new_alternate_heads,
                             new_checkpoint ) ->
                  Stored_data.write
                    chain_state.current_head_data
                    (Block_repr.descriptor new_current_head)
                  >>=? fun () ->
                  Stored_data.write
                    chain_state.alternate_heads_data
                    new_alternate_heads
                  >>=? fun () ->
                  Stored_data.write chain_state.checkpoint_data new_checkpoint
                  >>=? fun () ->
                  Stored_data.write chain_state.target_data None >>=? fun () ->
                  return_unit ))

  let is_acceptable_block chain_store block_descr =
    Shared.use chain_store.chain_state (fun chain_state ->
        locked_is_acceptable_block chain_state block_descr)

  (* Create / Load / Close *)

  let create_testchain_genesis_block ~genesis_hash ~genesis_header =
    let header = genesis_header in
    let contents =
      {
        Block_repr.header;
        operations = [];
        block_metadata_hash = None;
        operations_metadata_hashes = None;
      }
    in
    let metadata =
      Some
        {
          Block_repr.message = Some "Genesis";
          max_operations_ttl = 0;
          last_allowed_fork_level = genesis_header.shell.level;
          block_metadata = Bytes.create 0;
          operations_metadata = [];
        }
    in
    {Block_repr.hash = genesis_hash; contents; metadata}

  let create_chain_state ?target ~genesis_block ~genesis_protocol
      ~genesis_commit_info chain_dir =
    let genesis_proto_level = Block_repr.proto_level genesis_block in
    let ((_, genesis_level) as genesis_descr) =
      Block_repr.descriptor genesis_block
    in
    let cementing_highwatermark =
      Option.fold
        ~none:0l
        ~some:(fun metadata -> Block.last_allowed_fork_level metadata)
        (Block_repr.metadata genesis_block)
    in
    Stored_data.init
      (Naming.protocol_levels_file chain_dir)
      ~initial_data:
        Protocol_levels.(
          add
            genesis_proto_level
            {
              block = genesis_descr;
              protocol = genesis_protocol;
              commit_info = genesis_commit_info;
            }
            empty)
    >>=? fun protocol_levels_data ->
    Stored_data.init
      (Naming.current_head_file chain_dir)
      ~initial_data:genesis_descr
    >>=? fun current_head_data ->
    Stored_data.init (Naming.alternate_heads_file chain_dir) ~initial_data:[]
    >>=? fun alternate_heads_data ->
    Stored_data.init
      (Naming.cementing_highwatermark_file chain_dir)
      ~initial_data:(Some cementing_highwatermark)
    >>=? fun cementing_highwatermark_data ->
    Stored_data.init
      (Naming.checkpoint_file chain_dir)
      ~initial_data:(genesis_block.hash, genesis_level)
    >>=? fun checkpoint_data ->
    Stored_data.init (Naming.target_file chain_dir) ~initial_data:target
    >>=? fun target_data ->
    Stored_data.init
      (Naming.invalid_blocks_file chain_dir)
      ~initial_data:Block_hash.Map.empty
    >>=? fun invalid_blocks_data ->
    Stored_data.init
      (Naming.forked_chains_file chain_dir)
      ~initial_data:Chain_id.Map.empty
    >>=? fun forked_chains_data ->
    let current_head = genesis_block in
    let active_testchain = None in
    let mempool = Mempool.empty in
    let live_blocks = Block_hash.Set.singleton genesis_block.hash in
    let live_operations = Operation_hash.Set.empty in
    let live_data_cache = None in
    let prechecked_blocks = Block_lru_cache.create 10 in
    return
      {
        current_head_data;
        alternate_heads_data;
        cementing_highwatermark_data;
        target_data;
        checkpoint_data;
        protocol_levels_data;
        invalid_blocks_data;
        forked_chains_data;
        active_testchain;
        current_head;
        mempool;
        live_blocks;
        live_operations;
        live_data_cache;
        prechecked_blocks;
      }

  (* In some case, when a merge was interrupted, the highest cemented
     block level might be higher than the cementing
     highwatermark. When this case occurs, we trust the cemented store
     and adapt our cementing_highwatermark to it. *)
  let may_update_cementing_highwatermark_data block_store
      cementing_highwatermark_data =
    Stored_data.get cementing_highwatermark_data
    >>= fun cementing_highwatermark ->
    let cemented_store = Block_store.cemented_block_store block_store in
    match
      ( Cemented_block_store.get_highest_cemented_level cemented_store,
        cementing_highwatermark )
    with
    | (None, (Some _ | None)) -> return_unit
    | (Some highest_cemented_level, None) ->
        (* This case only happens after the store has been
           imported from a snapshot. *)
        Stored_data.write
          cementing_highwatermark_data
          (Some highest_cemented_level)
    | (Some highest_cemented_level, Some cementing_highwatermark) ->
        (* Invariant: the cemented blocks are always correct *)
        if Compare.Int32.(highest_cemented_level > cementing_highwatermark) then
          Stored_data.write
            cementing_highwatermark_data
            (Some highest_cemented_level)
        else return_unit

  (* TODO add integrity check to ensure that files are present? *)
  (* Files are expected to be present *)
  let load_chain_state chain_dir block_store =
    Stored_data.load (Naming.protocol_levels_file chain_dir)
    >>=? fun protocol_levels_data ->
    Stored_data.load (Naming.current_head_file chain_dir)
    >>=? fun current_head_data ->
    Stored_data.load (Naming.alternate_heads_file chain_dir)
    >>=? fun alternate_heads_data ->
    Stored_data.load (Naming.cementing_highwatermark_file chain_dir)
    >>=? fun cementing_highwatermark_data ->
    may_update_cementing_highwatermark_data
      block_store
      cementing_highwatermark_data
    >>=? fun () ->
    Stored_data.load (Naming.checkpoint_file chain_dir)
    >>=? fun checkpoint_data ->
    Stored_data.get checkpoint_data >>= fun (_, checkpoint_level) ->
    Prometheus.Gauge.set
      Store_metrics.metrics.checkpoint_level
      (Int32.to_float checkpoint_level) ;
    Stored_data.load (Naming.target_file chain_dir) >>=? fun target_data ->
    Stored_data.load (Naming.invalid_blocks_file chain_dir)
    >>=? fun invalid_blocks_data ->
    Stored_data.load (Naming.forked_chains_file chain_dir)
    >>=? fun forked_chains_data ->
    Stored_data.get current_head_data >>= fun (current_head_hash, _) ->
    Block_store.read_block
      ~read_metadata:true
      block_store
      (Block (current_head_hash, 0))
    >>=? function
    | None -> failwith "load_store: cannot read head"
    | Some current_head ->
        let active_testchain = None in
        let mempool = Mempool.empty in
        let live_blocks = Block_hash.Set.empty in
        let live_operations = Operation_hash.Set.empty in
        let live_data_cache = None in
        let prechecked_blocks = Block_lru_cache.create 10 in
        return
          {
            current_head_data;
            alternate_heads_data;
            cementing_highwatermark_data;
            target_data;
            checkpoint_data;
            protocol_levels_data;
            invalid_blocks_data;
            forked_chains_data;
            current_head;
            active_testchain;
            mempool;
            live_blocks;
            live_operations;
            live_data_cache;
            prechecked_blocks;
          }

  let get_commit_info index header =
    protect
      ~on_error:(fun err ->
        Format.kasprintf
          (fun e -> fail (Missing_commit_info e))
          "%a"
          Error_monad.pp_print_trace
          err)
      (fun () ->
        Context.retrieve_commit_info index header >>=? fun tup ->
        return (Protocol_levels.commit_info_of_tuple tup))

  let get_commit_info_opt index header =
    get_commit_info index header >>= function
    | Ok v -> Lwt.return_some v
    | Error _ -> Lwt.return_none

  let create_chain_store ?block_cache_limit global_store chain_dir ?target
      ~chain_id ?(expiration = None) ?genesis_block ~genesis ~genesis_context
      history_mode =
    (* Chain directory *)
    let genesis_block =
      match genesis_block with
      | None -> Block_repr.create_genesis_block ~genesis genesis_context
      | Some genesis_block -> genesis_block
    in
    (* Block_store.create also stores genesis *)
    Block_store.create ?block_cache_limit chain_dir ~genesis_block
    >>=? fun block_store ->
    let chain_config = {history_mode; genesis; expiration} in
    Stored_data.write_file (Naming.chain_config_file chain_dir) chain_config
    >>=? fun () ->
    get_commit_info_opt global_store.context_index (Block.header genesis_block)
    >>= fun genesis_commit_info ->
    create_chain_state
      chain_dir
      ?target
      ~genesis_block
      ~genesis_protocol:genesis.Genesis.protocol
      ~genesis_commit_info
    >>=? fun chain_state ->
    Stored_data.init
      (Naming.genesis_block_file chain_dir)
      ~initial_data:genesis_block
    >>=? fun genesis_block_data ->
    let chain_state = Shared.create chain_state in
    let block_watcher = Lwt_watcher.create_input () in
    let block_rpc_directories = Protocol_hash.Table.create 7 in
    create_lockfile chain_dir >>=? fun lockfile ->
    let chain_store : chain_store =
      {
        global_store;
        chain_id;
        chain_dir;
        chain_config;
        chain_state;
        genesis_block_data;
        block_store;
        block_watcher;
        block_rpc_directories;
        lockfile;
      }
    in
    return chain_store

  let load_chain_store ?block_cache_limit global_store chain_dir ~chain_id
      ~readonly =
    Stored_data.load (Naming.chain_config_file chain_dir)
    >>=? fun chain_config_data ->
    Stored_data.get chain_config_data >>= fun chain_config ->
    Stored_data.load (Naming.genesis_block_file chain_dir)
    >>=? fun genesis_block_data ->
    Stored_data.get genesis_block_data >>= fun genesis_block ->
    Block_store.load ?block_cache_limit chain_dir ~genesis_block ~readonly
    >>=? fun block_store ->
    load_chain_state chain_dir block_store >>=? fun chain_state ->
    let chain_state = Shared.create chain_state in
    let block_watcher = Lwt_watcher.create_input () in
    let block_rpc_directories = Protocol_hash.Table.create 7 in
    create_lockfile chain_dir >>=? fun lockfile ->
    let chain_store =
      {
        global_store;
        chain_id;
        chain_dir;
        chain_config;
        (* let the state handle the test chain initialization *)
        block_store;
        chain_state;
        genesis_block_data;
        block_watcher;
        block_rpc_directories;
        lockfile;
      }
    in
    (* Also initalize the live blocks *)
    current_head chain_store >>= fun head ->
    Block.get_block_metadata_opt chain_store head >>= function
    | None -> fail Inconsistent_chain_store
    | Some metadata ->
        Shared.update_with chain_state (fun chain_state ->
            locked_compute_live_blocks
              ~force:true
              ~update_cache:true
              chain_store
              chain_state
              head
              metadata
            >>= fun (live_blocks, live_operations) ->
            return
              (Some {chain_state with live_blocks; live_operations}, chain_store))

  (* Recursively closes all test chain stores *)
  let close_chain_store chain_store =
    Lwt_watcher.shutdown_input chain_store.block_watcher ;
    let rec loop = function
      | {block_store; lockfile; chain_state; _} ->
          (* Do not lock the chain_state before closing the block_store,
             it would prevent an eventual merge from finishing *)
          Block_store.close block_store >>= fun () ->
          Shared.locked_use chain_state (fun {active_testchain; _} ->
              (match active_testchain with
              | Some {testchain_store; _} -> loop testchain_store
              | None -> Lwt.return_unit)
              >>= fun () ->
              may_unlock chain_store.lockfile >>= fun () ->
              Lwt_utils_unix.safe_close lockfile >>= fun _ -> Lwt.return_unit)
    in
    loop chain_store

  (* Test chain *)

  let testchain chain_store =
    Shared.use chain_store.chain_state (fun {active_testchain; _} ->
        Lwt.return active_testchain)

  let testchain_forked_block {forked_block; _} = forked_block

  let testchain_store {testchain_store; _} = testchain_store

  let locked_load_testchain chain_store chain_state ~chain_id =
    let {forked_chains_data; active_testchain; _} = chain_state in
    match active_testchain with
    | Some testchain
      when Chain_id.equal chain_id testchain.testchain_store.chain_id ->
        return_some testchain
    | _ -> (
        let chain_dir = chain_store.chain_dir in
        let testchains_dir = Naming.testchains_dir chain_dir in
        let testchain_dir = Naming.chain_dir testchains_dir chain_id in
        Stored_data.get forked_chains_data >>= fun forked_chains ->
        match Chain_id.Map.find chain_id forked_chains with
        | None -> return_none
        | Some forked_block ->
            load_chain_store
              chain_store.global_store
              testchain_dir
              ~chain_id
              ~readonly:false
            >>=? fun testchain_store ->
            let testchain = {forked_block; testchain_store} in
            return_some testchain)

  let fork_testchain chain_store ~testchain_id ~forked_block ~genesis_hash
      ~genesis_header ~test_protocol ~expiration =
    let forked_block_hash = Block.hash forked_block in
    let genesis_hash' = Context.compute_testchain_genesis forked_block_hash in
    assert (Block_hash.equal genesis_hash genesis_hash') ;
    fail_unless
      chain_store.global_store.allow_testchains
      Fork_testchain_not_allowed
    >>=? fun () ->
    Shared.update_with
      chain_store.chain_state
      (fun ({active_testchain; _} as chain_state) ->
        match active_testchain with
        | Some ({testchain_store; forked_block} as testchain) ->
            (* Already forked and active *)
            if Chain_id.equal testchain_store.chain_id testchain_id then (
              assert (Block_hash.equal forked_block forked_block_hash) ;
              return (None, testchain))
            else fail (Cannot_fork_testchain testchain_id)
        | None ->
            let chain_dir = chain_store.chain_dir in
            let testchains_dir = Naming.testchains_dir chain_dir in
            let testchain_dir = Naming.chain_dir testchains_dir testchain_id in
            let testchain_dir_path = Naming.dir_path testchains_dir in
            if
              Sys.file_exists testchain_dir_path
              && Sys.is_directory testchain_dir_path
            then
              locked_load_testchain
                chain_store
                chain_state
                ~chain_id:testchain_id
              >>=? function
              | None -> fail (Cannot_load_testchain testchain_dir_path)
              | Some testchain ->
                  return
                    ( Some {chain_state with active_testchain = Some testchain},
                      testchain )
            else
              (* Inherit history mode *)
              let history_mode = history_mode chain_store in
              let genesis_block =
                create_testchain_genesis_block ~genesis_hash ~genesis_header
              in
              let genesis =
                {
                  Genesis.block = genesis_hash;
                  time = Block.timestamp genesis_block;
                  protocol = test_protocol;
                }
              in
              let genesis_context = Block.context_hash genesis_block in
              create_chain_store
                chain_store.global_store
                testchain_dir
                ~chain_id:testchain_id
                ~expiration:(Some expiration)
                ~genesis_block
                ~genesis
                ~genesis_context
                history_mode
              >>=? fun testchain_store ->
              Stored_data.update_with
                chain_state.forked_chains_data
                (fun forked_chains ->
                  Lwt.return
                    (Chain_id.Map.add
                       testchain_id
                       forked_block_hash
                       forked_chains))
              >>=? fun () ->
              Store_events.(emit fork_testchain)
                ( testchain_id,
                  test_protocol,
                  genesis_hash,
                  Block.descriptor forked_block )
              >>= fun () ->
              let testchain =
                {forked_block = forked_block_hash; testchain_store}
              in
              return
                ( Some {chain_state with active_testchain = Some testchain},
                  testchain ))

  (* Look for chain_store's testchains - does not look recursively *)
  let load_testchain chain_store ~chain_id =
    Shared.locked_use chain_store.chain_state (fun chain_state ->
        locked_load_testchain chain_store chain_state ~chain_id)

  (* TODO (later) Also garbage-collect testchains store/context. *)
  let shutdown_testchain chain_store =
    Shared.update_with
      chain_store.chain_state
      (fun ({active_testchain; _} as chain_state) ->
        match active_testchain with
        | Some testchain ->
            close_chain_store testchain.testchain_store >>= fun () ->
            return (Some {chain_state with active_testchain = None}, ())
        | None -> return (None, ()))

  (* Protocols *)

  let compute_commit_info chain_store block =
    let index = chain_store.global_store.context_index in
    protect
      ~on_error:(fun _ -> return_none)
      (fun () ->
        get_commit_info index block >>=? fun commit_info ->
        return_some commit_info)

  let set_protocol_level chain_store ~protocol_level (block, protocol_hash) =
    Shared.locked_use chain_store.chain_state (fun {protocol_levels_data; _} ->
        compute_commit_info chain_store (Block.header block)
        >>=? fun commit_info_opt ->
        Stored_data.update_with protocol_levels_data (fun protocol_levels ->
            Lwt.return
              Protocol_levels.(
                add
                  protocol_level
                  {
                    block = Block.descriptor block;
                    protocol = protocol_hash;
                    commit_info = commit_info_opt;
                  }
                  protocol_levels))
        >>=? fun () ->
        Store_events.(
          emit
            update_protocol_table
            (protocol_hash, protocol_level, Block.hash block, Block.level block))
        >>= fun () -> return_unit)

  let find_activation_block chain_store ~protocol_level =
    Shared.use chain_store.chain_state (fun {protocol_levels_data; _} ->
        Stored_data.get protocol_levels_data >>= fun protocol_levels ->
        Lwt.return (Protocol_levels.find protocol_level protocol_levels))

  let find_protocol chain_store ~protocol_level =
    find_activation_block chain_store ~protocol_level >>= function
    | None -> Lwt.return_none
    | Some {Protocol_levels.protocol; _} -> Lwt.return_some protocol

  let may_update_protocol_level chain_store ?pred ?protocol_level
      (block, protocol_hash) =
    (match pred with
    | None -> Block.read_predecessor chain_store block
    | Some pred -> return pred)
    >>=? fun pred ->
    let prev_proto_level = Block.proto_level pred in
    let protocol_level =
      Option.value ~default:(Block.proto_level block) protocol_level
    in
    if Compare.Int.(prev_proto_level < protocol_level) then
      find_activation_block chain_store ~protocol_level >>= function
      | Some {block = (bh, _); _} ->
          if Block_hash.(bh <> Block.hash block) then
            set_protocol_level chain_store ~protocol_level (block, protocol_hash)
          else return_unit
      | None ->
          set_protocol_level chain_store ~protocol_level (block, protocol_hash)
    else return_unit

  let may_update_ancestor_protocol_level chain_store ~head =
    let head_proto_level = Block.proto_level head in
    find_activation_block chain_store ~protocol_level:head_proto_level
    >>= function
    | None -> return_unit
    | Some {block; protocol; _} -> (
        savepoint chain_store >>= fun (_, savepoint_level) ->
        if Compare.Int32.(savepoint_level > snd block) then
          (* the block is too far in the past *)
          return_unit
        else
          is_ancestor chain_store ~head:(Block.descriptor head) ~ancestor:block
          >>= function
          | true -> (* nothing to do *) return_unit
          | false -> (
              let distance =
                Int32.(sub (Block.level head) (snd block) |> to_int)
              in
              Block.read_block_opt chain_store ~distance (Block.hash head)
              >>= function
              | None -> return_unit
              | Some ancestor ->
                  may_update_protocol_level chain_store (ancestor, protocol)))

  let all_protocol_levels chain_store =
    Shared.use chain_store.chain_state (fun {protocol_levels_data; _} ->
        Stored_data.get protocol_levels_data)

  let watcher chain_store = Lwt_watcher.create_stream chain_store.block_watcher

  let get_rpc_directory chain_store block =
    Block.read_predecessor_opt chain_store block >>= function
    | None -> Lwt.return_none (* genesis *)
    | Some pred when Block_hash.equal (Block.hash pred) (Block.hash block) ->
        Lwt.return_none (* genesis *)
    | Some pred -> (
        savepoint chain_store >>= fun (_, save_point_level) ->
        (if Compare.Int32.(Block.level pred < save_point_level) then
         find_activation_block
           chain_store
           ~protocol_level:(Block.proto_level pred)
         >>= function
         | Some {Protocol_levels.protocol; _} -> Lwt.return protocol
         | None -> Lwt.fail Not_found
        else Block.protocol_hash_exn chain_store pred)
        >>= fun protocol ->
        match
          Protocol_hash.Table.find chain_store.block_rpc_directories protocol
        with
        | None -> Lwt.return_none
        | Some map ->
            Block.protocol_hash_exn chain_store block >>= fun next_protocol ->
            Lwt.return (Protocol_hash.Map.find next_protocol map))

  let set_rpc_directory chain_store ~protocol_hash ~next_protocol_hash dir =
    let map =
      Option.value
        ~default:Protocol_hash.Map.empty
        (Protocol_hash.Table.find
           chain_store.block_rpc_directories
           protocol_hash)
    in
    Protocol_hash.Table.replace
      chain_store.block_rpc_directories
      protocol_hash
      (Protocol_hash.Map.add next_protocol_hash dir map) ;
    Lwt.return_unit
end

module Protocol = struct
  let all {protocol_store; _} = Protocol_store.all protocol_store

  let store {protocol_store; protocol_watcher; _} protocol_hash protocol =
    Protocol_store.store protocol_store protocol_hash protocol >>= function
    | None -> Lwt.return_none
    | p ->
        Lwt_watcher.notify protocol_watcher protocol_hash ;
        Lwt.return p

  let store_raw {protocol_store; protocol_watcher; _} protocol_hash raw_protocol
      =
    Protocol_store.raw_store protocol_store protocol_hash raw_protocol
    >>= function
    | None -> Lwt.return_none
    | p ->
        Lwt_watcher.notify protocol_watcher protocol_hash ;
        Lwt.return p

  let read {protocol_store; _} protocol_hash =
    Protocol_store.read protocol_store protocol_hash

  let mem {protocol_store; _} protocol_hash =
    Protocol_store.mem protocol_store protocol_hash

  let protocol_watcher {protocol_watcher; _} =
    Lwt_watcher.create_stream protocol_watcher
end

let create_store ?block_cache_limit ~context_index ~chain_id ~genesis
    ~genesis_context ?(history_mode = History_mode.default) ~allow_testchains
    store_dir =
  let store_dir_path = Naming.dir_path store_dir in
  Lwt_utils_unix.create_dir store_dir_path >>= fun () ->
  Protocol_store.init store_dir >>= fun protocol_store ->
  let protocol_watcher = Lwt_watcher.create_input () in
  let global_block_watcher = Lwt_watcher.create_input () in
  let chain_dir = Naming.chain_dir store_dir chain_id in
  let global_store =
    {
      store_dir;
      context_index;
      main_chain_store = None;
      protocol_store;
      allow_testchains;
      protocol_watcher;
      global_block_watcher;
    }
  in
  Chain.create_chain_store
    ?block_cache_limit
    global_store
    chain_dir
    ~chain_id
    ~expiration:None
    ~genesis
    ~genesis_context
    history_mode
  >>=? fun main_chain_store ->
  global_store.main_chain_store <- Some main_chain_store ;
  return global_store

let load_store ?history_mode ?block_cache_limit store_dir ~context_index
    ~genesis ~chain_id ~allow_testchains ~readonly () =
  let chain_dir = Naming.chain_dir store_dir chain_id in
  protect
    (fun () ->
      Consistency.check_consistency chain_dir genesis >>=? fun () ->
      Store_events.(emit store_is_consistent ()) >>= fun () -> return_unit)
    ~on_error:(function
      | err
        when List.exists
               (function Store_errors.Corrupted_store _ -> true | _ -> false)
               err
             || readonly ->
          (* Corrupted_store errors cannot be fixed automatically. The
             store is irremediably corrupted. If the store is in
             readonly, we are not allowed to write in it. *)
          Lwt.return_error err
      | err ->
          Store_events.(emit inconsistent_store err) >>= fun () ->
          Consistency.fix_consistency
            chain_dir
            context_index
            genesis
            ?history_mode
          >>=? fun () ->
          Store_events.(emit store_was_fixed ()) >>= fun () -> return_unit)
  >>=? fun () ->
  Protocol_store.init store_dir >>= fun protocol_store ->
  let protocol_watcher = Lwt_watcher.create_input () in
  let global_block_watcher = Lwt_watcher.create_input () in
  let global_store =
    {
      store_dir;
      context_index;
      main_chain_store = None;
      protocol_store;
      allow_testchains;
      protocol_watcher;
      global_block_watcher;
    }
  in
  Chain.load_chain_store
    ?block_cache_limit
    global_store
    chain_dir
    ~chain_id
    ~readonly
  >>=? fun main_chain_store ->
  let stored_genesis = Chain.genesis main_chain_store in
  fail_unless
    (Block_hash.equal genesis.Genesis.block stored_genesis.block)
    (Inconsistent_genesis {expected = stored_genesis.block; got = genesis.block})
  >>=? fun () ->
  (match history_mode with
  | None -> return main_chain_store
  | Some history_mode ->
      let previous_history_mode = Chain.history_mode main_chain_store in
      fail_unless
        (History_mode.equal history_mode previous_history_mode)
        (Cannot_switch_history_mode
           {previous_mode = previous_history_mode; next_mode = history_mode})
      >>=? fun () -> return main_chain_store)
  >>=? fun main_chain_store ->
  global_store.main_chain_store <- Some main_chain_store ;
  return global_store

let main_chain_store store =
  WithExceptions.Option.get ~loc:__LOC__ store.main_chain_store

let init ?patch_context ?commit_genesis ?history_mode ?(readonly = false)
    ?block_cache_limit ~store_dir ~context_dir ~allow_testchains genesis =
  let store_dir = Naming.store_dir ~dir_path:store_dir in
  let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
  (match commit_genesis with
  | Some commit_genesis ->
      Context.init ~readonly:true ?patch_context context_dir
      >>= fun context_index -> Lwt.return (context_index, commit_genesis)
  | None ->
      Context.init ~readonly ?patch_context context_dir >>= fun context_index ->
      let commit_genesis ~chain_id =
        Context.commit_genesis
          context_index
          ~chain_id
          ~time:genesis.time
          ~protocol:genesis.protocol
      in
      Lwt.return (context_index, commit_genesis))
  >>= fun (context_index, commit_genesis) ->
  let chain_dir = Naming.chain_dir store_dir chain_id in
  let chain_dir_path = Naming.dir_path chain_dir in
  (* FIXME should be checked with the store's consistency check
     (along with load_chain_state checks) *)
  if Sys.file_exists chain_dir_path && Sys.is_directory chain_dir_path then
    load_store
      ?history_mode
      ?block_cache_limit
      store_dir
      ~context_index
      ~genesis
      ~chain_id
      ~allow_testchains
      ~readonly
      ()
  else
    (* Fresh store *)
    commit_genesis ~chain_id >>=? fun genesis_context ->
    create_store
      ?block_cache_limit
      store_dir
      ~context_index
      ~chain_id
      ~genesis
      ~genesis_context
      ?history_mode
      ~allow_testchains

let close_store global_store =
  Lwt_watcher.shutdown_input global_store.protocol_watcher ;
  Lwt_watcher.shutdown_input global_store.global_block_watcher ;
  let main_chain_store =
    WithExceptions.Option.get ~loc:__LOC__ global_store.main_chain_store
  in
  Chain.close_chain_store main_chain_store >>= fun () ->
  Context.close global_store.context_index

let may_switch_history_mode ~store_dir ~context_dir genesis ~new_history_mode =
  let store_dir = Naming.store_dir ~dir_path:store_dir in
  let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
  let chain_dir = Naming.chain_dir store_dir chain_id in
  let chain_dir_path = Naming.dir_path chain_dir in
  if not (Sys.file_exists chain_dir_path && Sys.is_directory chain_dir_path)
  then (* Nothing to do, the store is not set *)
    return_unit
  else
    Context.init ~readonly:false context_dir >>= fun context_index ->
    load_store
      store_dir
      ~context_index
      ~genesis
      ~chain_id
      ~allow_testchains:true
      ~readonly:false
      ()
    >>=? fun store ->
    let chain_store = main_chain_store store in
    Lwt.finalize
      (fun () ->
        let block_store = chain_store.block_store in
        Chain.current_head chain_store >>= fun current_head ->
        let previous_history_mode = Chain.history_mode chain_store in
        if History_mode.equal previous_history_mode new_history_mode then
          return_unit
        else
          let is_valid_switch =
            match (previous_history_mode, new_history_mode) with
            | ((Full n, Full m) | (Rolling n, Rolling m)) when n = m -> false
            | (Archive, Full _)
            | (Archive, Rolling _)
            | (Full _, Full _)
            | (Full _, Rolling _)
            | (Rolling _, Rolling _) ->
                true
            | _ ->
                (* The remaining combinations are invalid switches *)
                false
          in
          fail_unless
            is_valid_switch
            (Cannot_switch_history_mode
               {
                 previous_mode = previous_history_mode;
                 next_mode = new_history_mode;
               })
          >>=? fun () ->
          lock_for_write chain_store.lockfile >>= fun () ->
          Block_store.switch_history_mode
            block_store
            ~current_head
            ~previous_history_mode
            ~new_history_mode
          >>=? fun () ->
          Chain.set_history_mode chain_store new_history_mode >>=? fun () ->
          Store_events.(
            emit switch_history_mode (previous_history_mode, new_history_mode))
          >>= return)
      (fun () -> unlock chain_store.lockfile >>= fun () -> close_store store)

let get_chain_store store chain_id =
  let chain_store = main_chain_store store in
  let rec loop chain_store =
    if Chain_id.equal (Chain.chain_id chain_store) chain_id then
      return chain_store
    else
      Shared.use chain_store.chain_state (fun {active_testchain; _} ->
          match active_testchain with
          | None -> fail (Validation_errors.Unknown_chain chain_id)
          | Some {testchain_store; _} -> loop testchain_store)
  in
  loop chain_store

let get_chain_store_opt store chain_id =
  get_chain_store store chain_id >>= function
  | Ok chain_store -> Lwt.return_some chain_store
  | Error _ -> Lwt.return_none

let all_chain_stores store =
  let chain_store = main_chain_store store in
  let rec loop acc chain_store =
    let acc = chain_store :: acc in
    Shared.use chain_store.chain_state (fun {active_testchain; _} ->
        match active_testchain with
        | None -> Lwt.return acc
        | Some {testchain_store; _} -> loop acc testchain_store)
  in
  loop [] chain_store

let directory store = store.store_dir

let context_index store = store.context_index

let allow_testchains {allow_testchains; _} = allow_testchains

let global_block_watcher {global_block_watcher; _} =
  Lwt_watcher.create_stream global_block_watcher

let option_pp ~default pp fmt = function
  | None -> Format.fprintf fmt "%s" default
  | Some x -> Format.fprintf fmt "%a" pp x

let rec make_pp_chain_store (chain_store : chain_store) =
  let {chain_id; chain_dir; chain_config; chain_state; block_store; _} =
    chain_store
  in
  let chain_config_json =
    Data_encoding.Json.construct chain_config_encoding chain_config
  in
  Shared.locked_use
    chain_state
    (fun
      {
        current_head;
        alternate_heads_data;
        cementing_highwatermark_data;
        target_data;
        checkpoint_data;
        protocol_levels_data;
        invalid_blocks_data;
        forked_chains_data;
        active_testchain;
        _;
      }
    ->
      Stored_data.get alternate_heads_data >>= fun alternate_heads ->
      Stored_data.get cementing_highwatermark_data
      >>= fun cementing_highwatermark ->
      Stored_data.get target_data >>= fun target ->
      Stored_data.get checkpoint_data >>= fun checkpoint ->
      Stored_data.get protocol_levels_data >>= fun protocol_levels ->
      Stored_data.get invalid_blocks_data >>= fun invalid_blocks ->
      Stored_data.get forked_chains_data >>= fun forked_chains ->
      Block_store.savepoint block_store >>= fun savepoint ->
      Block_store.caboose block_store >>= fun caboose ->
      let highest_cemented_level =
        Cemented_block_store.get_highest_cemented_level
          (Block_store.cemented_block_store block_store)
      in
      let lowest_cemented_level =
        Cemented_block_store.get_lowest_cemented_level
          (Block_store.cemented_block_store block_store)
      in
      let exception First of Block_repr.t in
      Lwt.catch
        (fun () ->
          let find_store kind' =
            let floating_stores =
              Block_store.floating_block_stores block_store
            in
            List.find
              (fun floating_store ->
                Floating_block_store.(kind floating_store = kind'))
              floating_stores
            |> WithExceptions.Option.get ~loc:__LOC__
          in
          let ro_store = find_store Floating_block_store.RO in
          Floating_block_store.iter_s
            (fun block -> Lwt.fail (First block))
            ro_store
          >>= fun _ ->
          let rw_store = find_store Floating_block_store.RW in
          Floating_block_store.iter_s
            (fun block -> Lwt.fail (First block))
            rw_store
          >>= fun _ -> assert false)
        (function
          | First b -> Lwt.return b
          | _exn ->
              (* There should always be a block in the floatings stores *)
              assert false)
      >>= fun first_block_in_floating ->
      Lwt.return
        ( current_head,
          alternate_heads,
          cementing_highwatermark,
          target,
          checkpoint,
          caboose,
          savepoint,
          first_block_in_floating,
          Block_store.get_merge_status block_store,
          highest_cemented_level,
          lowest_cemented_level,
          protocol_levels,
          invalid_blocks,
          forked_chains,
          active_testchain ))
  >>= fun ( current_head,
            alternate_heads,
            cementing_highwatermark,
            target,
            checkpoint,
            caboose,
            savepoint,
            first_block_in_floating,
            merge_status,
            highest_cemented_level,
            lowest_cemented_level,
            protocol_levels_data,
            invalid_blocks_data,
            forked_chains_data,
            active_test_chain ) ->
  let pp_protocol_level fmt
      (proto_level, {Protocol_levels.block; protocol; commit_info}) =
    Format.fprintf
      fmt
      "proto level: %d, transition block: %a, protocol: %a, commit info: %a"
      proto_level
      pp_block_descriptor
      block
      Protocol_hash.pp
      protocol
      (option_pp ~default:"n/a" (fun fmt _ -> Format.fprintf fmt "available"))
      commit_info
  in
  let make_pp_test_chain_opt = function
    | None -> Lwt.return (fun fmt () -> Format.fprintf fmt "n/a")
    | Some {testchain_store; _} ->
        make_pp_chain_store testchain_store >>= fun pp ->
        Lwt.return (fun fmt () -> Format.fprintf fmt "@ %a" pp ())
  in
  make_pp_test_chain_opt active_test_chain >>= fun pp_testchain_opt ->
  Lwt.return (fun fmt () ->
      Format.fprintf
        fmt
        "@[<v 2>chain id: %a@ chain directory: %s@ chain config: %a@ current \
         head: %a@ @[<v 2>alternate heads:@ %a@]@ checkpoint: %a@ cementing \
         highwatermark: %a@ savepoint: %a@ caboose: %a@ first block in \
         floating: %a@ interval of cemented blocks: [%a, %a]@ merge status: \
         %a@ target: %a@ @[<v 2>protocol levels:@ %a@]@ @[<v 2>invalid \
         blocks:@ %a@]@ @[<v 2>forked chains:@ %a@]@ @[<v 2>active testchain: \
         %a@]@]"
        Chain_id.pp
        chain_id
        (Naming.dir_path chain_dir)
        Data_encoding.Json.pp
        chain_config_json
        (fun fmt block ->
          let metadata =
            WithExceptions.Option.get ~loc:__LOC__ (Block_repr.metadata block)
          in
          Format.fprintf
            fmt
            "%a (lafl: %ld) (max_op_ttl: %d)"
            pp_block_descriptor
            (Block.descriptor block)
            (Block.last_allowed_fork_level metadata)
            (Block.max_operations_ttl metadata))
        current_head
        (Format.pp_print_list ~pp_sep:Format.pp_print_cut pp_block_descriptor)
        alternate_heads
        pp_block_descriptor
        checkpoint
        (fun fmt opt ->
          option_pp
            ~default:"n/a"
            (fun fmt i -> Format.fprintf fmt "%ld" i)
            fmt
            opt)
        cementing_highwatermark
        pp_block_descriptor
        savepoint
        pp_block_descriptor
        caboose
        pp_block_descriptor
        (Block.descriptor first_block_in_floating)
        (option_pp ~default:"n/a" (fun fmt i -> Format.fprintf fmt "%ld" i))
        lowest_cemented_level
        (option_pp ~default:"n/a" (fun fmt i -> Format.fprintf fmt "%ld" i))
        highest_cemented_level
        Block_store.pp_merge_status
        merge_status
        (option_pp ~default:"n/a" pp_block_descriptor)
        target
        (Format.pp_print_list ~pp_sep:Format.pp_print_cut pp_protocol_level)
        (Protocol_levels.bindings protocol_levels_data)
        (Format.pp_print_list ~pp_sep:Format.pp_print_cut Block_hash.pp)
        (Block_hash.Map.bindings invalid_blocks_data |> List.map fst)
        (Format.pp_print_list
           ~pp_sep:Format.pp_print_cut
           (fun fmt (chain_id, block_hash) ->
             Format.fprintf
               fmt
               "testchain's chain id: %a, forked block: %a"
               Chain_id.pp
               chain_id
               Block_hash.pp
               block_hash))
        (Chain_id.Map.bindings forked_chains_data)
        pp_testchain_opt
        ())

let make_pp_store (store : store) =
  let {store_dir; allow_testchains; main_chain_store; _} = store in
  make_pp_chain_store (WithExceptions.Option.get ~loc:__LOC__ main_chain_store)
  >>= fun pp_testchain_store ->
  Lwt.return (fun fmt () ->
      Format.fprintf
        fmt
        "@[<v 2>Store state:@ store directory: %s@ allow testchains: %b@ @[<v \
         2>main chain:@ %a@]@])"
        (Naming.dir_path store_dir)
        allow_testchains
        pp_testchain_store
        ())

(************ For testing and internal purposes only **************)
module Unsafe = struct
  let repr_of_block b = b

  let block_of_repr b = b

  let get_block_store chain_store = chain_store.block_store

  let set_head chain_store new_head =
    Shared.update_with chain_store.chain_state (fun chain_state ->
        Stored_data.write
          chain_state.current_head_data
          (Block.descriptor new_head)
        >>=? fun () ->
        return (Some {chain_state with current_head = new_head}, ()))

  let set_checkpoint chain_store new_checkpoint =
    Shared.use chain_store.chain_state (fun chain_state ->
        Stored_data.write chain_state.checkpoint_data new_checkpoint
        >>=? fun () -> return_unit)

  let set_cementing_highwatermark chain_store new_cementing_highwatermark =
    Shared.use chain_store.chain_state (fun chain_state ->
        Stored_data.write
          chain_state.cementing_highwatermark_data
          new_cementing_highwatermark
        >>=? fun () -> return_unit)

  let set_history_mode = Chain.set_history_mode

  let set_savepoint chain_store new_savepoint =
    Chain.unsafe_set_savepoint chain_store new_savepoint

  let set_caboose chain_store new_caboose =
    Chain.unsafe_set_caboose chain_store new_caboose

  let set_protocol_level chain_store ~protocol_level (b, ph) =
    Chain.set_protocol_level chain_store ~protocol_level (b, ph)

  let load_testchain = Chain.load_testchain

  let open_for_snapshot_export ~store_dir ~context_dir genesis
      ~(locked_f : chain_store -> 'a tzresult Lwt.t) =
    let store_dir = Naming.store_dir ~dir_path:store_dir in
    let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
    let chain_dir = Naming.chain_dir store_dir chain_id in
    create_lockfile chain_dir >>=? fun lockfile ->
    lock_for_read lockfile >>= fun () ->
    protect
      (fun () ->
        Context.init ~readonly:true context_dir >>= fun context_index ->
        load_store
          store_dir
          ~context_index
          ~genesis
          ~chain_id
          ~allow_testchains:false
          ~readonly:true
          ()
        >>=? fun store ->
        let chain_store = main_chain_store store in
        Lwt.finalize
          (fun () -> locked_f chain_store)
          (fun () -> close_store store))
      ~on_error:(fun errs ->
        may_unlock lockfile >>= fun () -> Lwt.return (Error errs))

  let restore_from_snapshot ?(notify = fun () -> Lwt.return_unit) store_dir
      ~context_index ~genesis ~genesis_context_hash ~floating_blocks_stream
      ~new_head_with_metadata ~protocol_levels ~history_mode =
    let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
    let chain_dir = Naming.chain_dir store_dir chain_id in
    let genesis_block =
      Block_repr.create_genesis_block ~genesis genesis_context_hash
    in
    let real_genesis_hash = Block_header.hash (Block.header genesis_block) in
    let new_head_descr =
      ( Block_repr.hash new_head_with_metadata,
        Block_repr.level new_head_with_metadata )
    in
    (* Write consistent stored data *)
    Stored_data.write_file
      (Naming.protocol_levels_file chain_dir)
      protocol_levels
    >>=? fun () ->
    Stored_data.write_file
      (Naming.current_head_file chain_dir)
      (Block.descriptor new_head_with_metadata)
    >>=? fun () ->
    Stored_data.write_file (Naming.alternate_heads_file chain_dir) []
    >>=? fun () ->
    (* Checkpoint is the new head *)
    Stored_data.write_file (Naming.checkpoint_file chain_dir) new_head_descr
    >>=? fun () ->
    (* Cementing highwatermark is set to None *)
    Stored_data.write_file (Naming.cementing_highwatermark_file chain_dir) None
    >>=? fun () ->
    Stored_data.write_file (Naming.target_file chain_dir) None >>=? fun () ->
    (* Savepoint is the head *)
    Stored_data.write_file (Naming.savepoint_file chain_dir) new_head_descr
    >>=? fun () ->
    (* Depending on the history mode, set the caboose properly *)
    (match history_mode with
    | History_mode.Archive | Full _ ->
        return (Block_repr.hash genesis_block, Block_repr.level genesis_block)
    | Rolling _ -> (
        Lwt_stream.peek floating_blocks_stream >>= function
        | None ->
            (* This should not happen. The floating store of a
               snapshot exported at highest_cemented_block + 1 should
               have a floating store populated with the cemented
               cycle. *)
            assert false
        | Some caboose -> (
            match Block_repr.metadata new_head_with_metadata with
            | None -> assert false
            | Some metadata ->
                if
                  Int32.sub
                    (Block_repr.level new_head_with_metadata)
                    (Int32.of_int metadata.max_operations_ttl)
                  <= 0l
                then return (genesis.block, 0l)
                else return (Block_repr.hash caboose, Block_repr.level caboose))
        ))
    >>=? fun caboose_descr ->
    Stored_data.write_file (Naming.caboose_file chain_dir) caboose_descr
    >>=? fun () ->
    Stored_data.write_file
      (Naming.invalid_blocks_file chain_dir)
      Block_hash.Map.empty
    >>=? fun () ->
    Stored_data.write_file
      (Naming.forked_chains_file chain_dir)
      Chain_id.Map.empty
    >>=? fun () ->
    Stored_data.write_file (Naming.genesis_block_file chain_dir) genesis_block
    >>=? fun () ->
    (* Load the store (containing the cemented if relevant) *)
    Block_store.load chain_dir ~genesis_block ~readonly:false
    >>=? fun block_store ->
    (* Store the floating (in the correct order!) *)
    Lwt_stream.iter_s
      (fun block ->
        Block_store.store_block block_store block >>= fun _ -> notify ())
      floating_blocks_stream
    >>= fun () ->
    (* Store the head *)
    Block_store.store_block block_store new_head_with_metadata >>=? fun () ->
    (* Check correctness of protocol transition blocks *)
    List.iter_es
      (fun ( _,
             {
               Protocol_levels.block = (bh, _);
               protocol;
               commit_info = commit_info_opt;
             } ) ->
        Block_store.read_block block_store ~read_metadata:false (Block (bh, 0))
        >>=? fun block_opt ->
        match (block_opt, commit_info_opt) with
        | (None, _) -> (
            match history_mode with
            | Rolling _ ->
                (* If we are importing a rolling snapshot then allow the
                   absence of block. *)
                return_unit
            | _ ->
                fail_unless
                  (Block_hash.equal real_genesis_hash bh)
                  (Missing_activation_block (bh, protocol, history_mode)))
        | (Some _block, None) -> return_unit
        | (Some block, Some commit_info) ->
            Context.check_protocol_commit_consistency
              context_index
              ~expected_context_hash:(Block.context_hash block)
              ~given_protocol_hash:protocol
              ~author:commit_info.author
              ~message:commit_info.message
              ~timestamp:(Block.timestamp block)
              ~test_chain_status:commit_info.test_chain_status
              ~predecessor_block_metadata_hash:
                commit_info.predecessor_block_metadata_hash
              ~predecessor_ops_metadata_hash:
                commit_info.predecessor_ops_metadata_hash
              ~data_merkle_root:commit_info.data_merkle_root
              ~parents_contexts:commit_info.parents_contexts
            >>= fun is_consistent ->
            fail_unless
              (is_consistent
              || Compare.Int32.(equal (Block_repr.level block) 0l))
              (Inconsistent_protocol_commit_info (Block.hash block, protocol)))
      (Protocol_levels.bindings protocol_levels)
    >>=? fun () ->
    Block_store.close block_store >>= fun () ->
    let chain_config = {history_mode; genesis; expiration = None} in
    Stored_data.write_file (Naming.chain_config_file chain_dir) chain_config
    >>=? fun () -> return_unit
end
