(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2019-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

type failure_kind =
  | Nothing_to_reconstruct
  | Context_hash_mismatch of Block_header.t * Context_hash.t * Context_hash.t
  | Cannot_read_block_hash of Block_hash.t
  | Cannot_read_block_level of Int32.t

let failure_kind_encoding =
  let open Data_encoding in
  union
    [
      case
        (Tag 0)
        ~title:"nothing_to_reconstruct"
        empty
        (function Nothing_to_reconstruct -> Some () | _ -> None)
        (fun () -> Nothing_to_reconstruct);
      case
        (Tag 1)
        ~title:"context_hash_mismatch"
        (obj3
           (req "block_header" Block_header.encoding)
           (req "expected" Context_hash.encoding)
           (req "got" Context_hash.encoding))
        (function
          | Context_hash_mismatch (h, e, g) -> Some (h, e, g) | _ -> None)
        (fun (h, e, g) -> Context_hash_mismatch (h, e, g));
      case
        (Tag 2)
        ~title:"cannot_read_block_hash"
        Block_hash.encoding
        (function Cannot_read_block_hash h -> Some h | _ -> None)
        (fun h -> Cannot_read_block_hash h);
      case
        (Tag 3)
        ~title:"cannot_read_block_level"
        int32
        (function Cannot_read_block_level l -> Some l | _ -> None)
        (fun l -> Cannot_read_block_level l);
    ]

let failure_kind_pp ppf = function
  | Nothing_to_reconstruct -> Format.fprintf ppf "nothing to reconstruct"
  | Context_hash_mismatch (h, e, g) ->
      Format.fprintf
        ppf
        "resulting context hash for block %a (level %ld) does not match. \
         Context hash expected %a, got %a"
        Block_hash.pp
        (Block_header.hash h)
        h.shell.level
        Context_hash.pp
        e
        Context_hash.pp
        g
  | Cannot_read_block_hash h ->
      Format.fprintf ppf "Unexpected missing block in store: %a" Block_hash.pp h
  | Cannot_read_block_level l ->
      Format.fprintf ppf "Unexpected missing block in store at level %ld" l

type error += Reconstruction_failure of failure_kind

type error += Cannot_reconstruct of History_mode.t

let () =
  let open Data_encoding in
  register_error_kind
    `Permanent
    ~id:"reconstruction.reconstruction_failure"
    ~title:"Reconstruction failure"
    ~description:"Error while performing storage reconstruction."
    ~pp:(fun ppf reason ->
      Format.fprintf
        ppf
        "The data contained in the storage is not valid. The reconstruction \
         procedure failed: %a."
        failure_kind_pp
        reason)
    (obj1 (req "reason" failure_kind_encoding))
    (function Reconstruction_failure r -> Some r | _ -> None)
    (fun r -> Reconstruction_failure r) ;
  register_error_kind
    `Permanent
    ~id:"reconstruction.cannot_failure"
    ~title:"Cannot reconstruct"
    ~description:"Cannot reconstruct"
    ~pp:(fun ppf hm ->
      Format.fprintf
        ppf
        "Cannot reconstruct storage from %a mode."
        History_mode.pp
        hm)
    (obj1 (req "history_mode " History_mode.encoding))
    (function Cannot_reconstruct hm -> Some hm | _ -> None)
    (fun hm -> Cannot_reconstruct hm)

open Reconstruction_events

(* The status of a metadata. It is:
   - Complete: all the metadata of the corresponding cycle are stored
   - Partial level: the metadata before level are missing
   - Not_stored: no metada are stored *)
type metadata_status = Complete | Partial of Int32.t | Not_stored

(* We assume that :
   - a cemented metadata cycle is partial if, at least, the first
     metadata of the cycle (start_level) is missing.
   - there only exists a contiguous set of empty metadata *)
let cemented_metadata_status cemented_store = function
  | {Cemented_block_store.start_level; end_level; _} -> (
      Cemented_block_store.read_block_metadata cemented_store end_level
      >>=? function
      | None -> return Not_stored
      | Some _ -> (
          Cemented_block_store.read_block_metadata cemented_store start_level
          >>=? function
          | Some _ -> return Complete
          | None ->
              let rec search inf sup =
                if inf >= sup then return (Partial inf)
                else
                  let level = Int32.(add inf (div (sub sup inf) 2l)) in
                  Cemented_block_store.read_block_metadata cemented_store level
                  >>=? function
                  | None -> search (Int32.succ level) sup
                  | Some _ -> search inf (Int32.pred level)
              in
              search (Int32.succ start_level) (Int32.pred end_level)))

let check_context_hash_consistency block_validation_result block_header =
  let expected = block_header.Block_header.shell.context in
  let got = block_validation_result.Block_validation.context_hash in
  fail_unless
    (Context_hash.equal expected got)
    (Reconstruction_failure
       (Context_hash_mismatch (block_header, expected, got)))

(* We assume that the given list is not empty. *)
let compute_block_metadata_hash block_metadata =
  Some (Block_metadata_hash.hash_bytes block_metadata)

(* We assume that the given list is not empty. *)
let compute_operations_metadata_hashes ops_metadata_hashes =
  Some
    (List.map
       (List.map (fun r -> Operation_metadata_hash.hash_bytes [r]))
       ops_metadata_hashes)

let compute_all_operations_metadata_hash block =
  if Block_repr.validation_passes block = 0 then None
  else
    Option.map
      (fun ll ->
        Operation_metadata_list_list_hash.compute
          (List.map Operation_metadata_list_hash.compute ll))
      (Block_repr.operations_metadata_hashes block)

let apply_context context_index chain_id ~user_activated_upgrades
    ~user_activated_protocol_overrides ~predecessor_block_metadata_hash
    ~predecessor_ops_metadata_hash ~predecessor_block block =
  let block_header = Store.Block.header block in
  let operations = Store.Block.operations block in
  let predecessor_block_header = Store.Block.header predecessor_block in
  let context_hash = predecessor_block_header.shell.context in
  (Context.checkout context_index context_hash >>= function
   | Some ctxt -> return ctxt
   | None ->
       fail
         (Store_errors.Cannot_checkout_context
            (Store.Block.hash predecessor_block, context_hash)))
  >>=? fun predecessor_context ->
  let apply_environment =
    {
      Block_validation.max_operations_ttl =
        Int32.to_int (Store.Block.level predecessor_block);
      chain_id;
      predecessor_block_header;
      predecessor_context;
      predecessor_block_metadata_hash;
      predecessor_ops_metadata_hash;
      user_activated_upgrades;
      user_activated_protocol_overrides;
    }
  in
  Block_validation.apply apply_environment block_header operations ~cache:`Lazy
  (* TODO: https://gitlab.com/tezos/tezos/-/issues/1570
     Reuse in-memory caches along reconstruction
     Since the reconstruction follows the history in a linear way, we
     could do a better usage of in-memory caches by reusing them from one
     block to the next one.
  *)
  >>=?
  fun {
        result =
          {Block_validation.validation_store; block_metadata; ops_metadata; _};
        _;
      } ->
  check_context_hash_consistency validation_store block_header >>=? fun () ->
  return
    {
      Store.Block.message = validation_store.message;
      max_operations_ttl = validation_store.max_operations_ttl;
      last_allowed_fork_level = validation_store.last_allowed_fork_level;
      block_metadata;
      operations_metadata = ops_metadata;
    }

(** Returns the protocol environment version of a given protocol level. *)
let protocol_env_of_protocol_level chain_store protocol_level block_hash =
  (Store.Chain.find_protocol chain_store ~protocol_level >>= function
   | Some ph -> return ph
   | None -> fail (Store_errors.Cannot_find_protocol protocol_level))
  >>=? fun protocol_hash ->
  match Registered_protocol.get protocol_hash with
  | None ->
      fail
        (Block_validator_errors.Unavailable_protocol
           {block = block_hash; protocol = protocol_hash})
  | Some (module Proto) -> return Proto.environment_version

(* Restores the block and operations metadata hash of a given block,
   if needed. *)
let restore_block_contents chain_store block_protocol_env ~block_metadata
    ~operations_metadata metadata block =
  let contents =
    if
      Store.Block.is_genesis chain_store (Block_repr.hash block)
      || block_protocol_env = Protocol.V0
    then block.contents
    else
      {
        block.contents with
        block_metadata_hash = compute_block_metadata_hash [block_metadata];
        operations_metadata_hashes =
          compute_operations_metadata_hashes operations_metadata;
      }
  in
  {block with contents; metadata = Some metadata}

let reconstruct_chunk chain_store context_index ~user_activated_upgrades
    ~user_activated_protocol_overrides ~start_level ~end_level =
  let chain_id = Store.Chain.chain_id chain_store in
  let rec loop level acc =
    if level > end_level then return List.(rev acc)
    else
      (Store.Block.read_block_by_level_opt chain_store level >>= function
       | None ->
           failwith
             "Cannot read block in cemented store. The storage is corrupted."
       | Some b -> return b)
      >>=? fun block ->
      (if Store.Block.is_genesis chain_store (Store.Block.hash block) then
       Store.Chain.genesis_block chain_store >>= fun genesis_block ->
       Store.Block.get_block_metadata chain_store genesis_block
      else
        (match acc with
        | [] ->
            (* As the predecessor of the first block of the chunk was
               already reconstructed and stored, we can read it as
               usual. *)
            Store.Block.read_predecessor chain_store block
            >>=? fun predecessor_block ->
            return
              ( predecessor_block,
                Store.Block.block_metadata_hash predecessor_block,
                Store.Block.all_operations_metadata_hash predecessor_block )
        | (pred, _) :: _ ->
            (* While the chunk is being recontsructed, we compute the
               block and operations metadata hash using the predecessor
               stored in chunk being accumulated instead of reading
               it. *)
            let predecessor_block = Store.Unsafe.block_of_repr pred in
            return
              ( predecessor_block,
                Block_repr.block_metadata_hash pred,
                compute_all_operations_metadata_hash pred ))
        >>=? fun ( predecessor_block,
                   predecessor_block_metadata_hash,
                   predecessor_ops_metadata_hash ) ->
        apply_context
          context_index
          chain_id
          ~user_activated_upgrades
          ~user_activated_protocol_overrides
          ~predecessor_block_metadata_hash
          ~predecessor_ops_metadata_hash
          ~predecessor_block
          block)
      >>=? fun metadata ->
      Event.(emit reconstruct_block_success) (Store.Block.descriptor block)
      >>= fun () ->
      protocol_env_of_protocol_level
        chain_store
        (Store.Block.proto_level block)
        (Store.Block.hash block)
      >>=? fun block_protocol_env ->
      let reconstructed_block =
        restore_block_contents
          chain_store
          block_protocol_env
          ~block_metadata:metadata.block_metadata
          ~operations_metadata:metadata.operations_metadata
          metadata
          (Store.Unsafe.repr_of_block block)
      in
      loop (Int32.succ level) ((reconstructed_block, block_protocol_env) :: acc)
  in
  loop start_level []

let store_chunk cemented_store chunk =
  (match List.hd chunk with
  | None -> failwith "Cannot read chunk to cement."
  | Some e -> return e)
  >>=? fun (lower_block, lower_env_version) ->
  (match List.hd (List.rev chunk) with
  | None -> failwith "Cannot read chunk to cement."
  | Some e -> return e)
  >>=? fun (_, higher_env_version) ->
  let block_chunk = List.map fst chunk in
  if lower_env_version = Protocol.V0 && higher_env_version = Protocol.V0 then
    (* No need to rewrite the cemented blocks as the block and
       operation metadata hashes are not expected to be stored, only
       store the metadata. *)
    Cemented_block_store.cement_blocks_metadata cemented_store block_chunk
  else
    (* In case of blocks with expected block and operations metadata
       hash, we check if they are missing to, potentially, restore
       them. *)
    let is_valid level =
      Cemented_block_store.get_cemented_block_by_level
        ~read_metadata:false
        cemented_store
        level
      >>=? function
      | None -> fail (Reconstruction_failure (Cannot_read_block_level level))
      | Some b -> (
          match
            ( Block_repr.block_metadata_hash b,
              Block_repr.operations_metadata_hashes b )
          with
          | (Some _, Some _) -> return_true
          | _ -> return_false)
    in
    is_valid (Block_repr.level lower_block) >>=? fun valid_lower_block ->
    (* If the lower cycle bounds have the block and operations
       metadata hash stored, as expected, we only store the
       metadata. We check only the lower bound as the only case where
       the upper bound may differ is after a snapshot import. In this
       case, the lower bound is enough to determine the validity of
       the cycle as the lower cannot be valid while the upper is
       not. *)
    if valid_lower_block then
      Cemented_block_store.cement_blocks_metadata cemented_store block_chunk
    else
      (* Overwrite the existing cycle to restore the blocks and
         operations metadata hash and store the associated
         metadata. *)
      Cemented_block_store.cement_blocks
        ~check_consistency:false
        cemented_store
        ~write_metadata:true
        block_chunk

let gather_available_metadata chain_store ~start_level ~end_level =
  let rec aux level acc =
    if level > end_level then return acc
    else
      Store.Block.read_block_by_level chain_store level >>=? fun block ->
      Store.Block.get_block_metadata chain_store block >>=? fun metadata ->
      let block_with_metadata =
        {(Store.Unsafe.repr_of_block block) with metadata = Some metadata}
      in
      aux (Int32.succ level) (block_with_metadata :: acc)
  in
  aux start_level []

(* Reconstruct the storage without checking if the context is already
   populated. We assume that committing an existing context is a
   nop. *)
let reconstruct_cemented chain_store context_index ~user_activated_upgrades
    ~user_activated_protocol_overrides ~start_block_level =
  let block_store = Store.Unsafe.get_block_store chain_store in
  let cemented_block_store = Block_store.cemented_block_store block_store in
  let chain_dir = Store.Chain.chain_dir chain_store in
  let cemented_blocks_dir = Naming.cemented_blocks_dir chain_dir in
  (Cemented_block_store.load_table cemented_blocks_dir
   (* Filter the cemented cycles to get the ones to reconstruct *)
   >>=? function
   | None -> return ([], 0)
   | Some cycles ->
       let cycles_to_restore =
         List.filter
           (fun {Cemented_block_store.start_level; end_level; _} ->
             start_level >= start_block_level
             || start_block_level >= start_level
                && start_block_level <= end_level)
           (Array.to_list cycles)
       in
       let first_cycle_index =
         Array.length cycles - List.length cycles_to_restore
       in
       return (cycles_to_restore, first_cycle_index))
  >>=? fun (cemented_cycles, start_cycle_index) ->
  Animation.display_progress
    ~pp_print_step:(fun ppf i ->
      Format.fprintf
        ppf
        "Reconstructing cemented blocks: %i/%d cycles rebuilt"
        (i + start_cycle_index)
        (List.length cemented_cycles + start_cycle_index))
    (fun notify ->
      let rec aux = function
        | [] ->
            (* No cemented to reconstruct *)
            return_unit
        | ({Cemented_block_store.start_level; end_level; _} as file) :: tl -> (
            cemented_metadata_status cemented_block_store file >>=? function
            | Complete ->
                (* Should not happen: we should have stopped or not started *)
                return_unit
            | Partial limit ->
                (* Reconstruct it partially and then stop *)
                (* As the block at level = limit contains metadata the
                   sub chunk stops before. Then, we gather the stored
                   metadata at limit (incl.). *)
                reconstruct_chunk
                  chain_store
                  context_index
                  ~user_activated_upgrades
                  ~user_activated_protocol_overrides
                  ~start_level
                  ~end_level:Int32.(pred limit)
                >>=? fun chunk ->
                gather_available_metadata
                  chain_store
                  ~start_level:limit
                  ~end_level
                >>=? List.map_es (fun br ->
                         protocol_env_of_protocol_level
                           chain_store
                           (Block_repr.proto_level br)
                           (Block_repr.hash br)
                         >>=? fun proto_env_version ->
                         return (br, proto_env_version))
                >>=? fun available_metadata ->
                store_chunk
                  cemented_block_store
                  (List.append chunk available_metadata)
                >>=? fun () ->
                notify () >>= fun () -> return_unit
            | Not_stored ->
                (* Reconstruct it and continue *)
                reconstruct_chunk
                  chain_store
                  context_index
                  ~user_activated_upgrades
                  ~user_activated_protocol_overrides
                  ~start_level
                  ~end_level
                >>=? fun chunk ->
                store_chunk cemented_block_store chunk >>=? fun () ->
                notify () >>= fun () -> aux tl)
      in
      aux cemented_cycles)

let reconstruct_floating chain_store context_index ~user_activated_upgrades
    ~user_activated_protocol_overrides =
  let chain_id = Store.Chain.chain_id chain_store in
  let chain_dir = Store.Chain.chain_dir chain_store in
  let block_store = Store.Unsafe.get_block_store chain_store in
  let cemented_block_store = Block_store.cemented_block_store block_store in
  Floating_block_store.init chain_dir ~readonly:false RO_TMP
  >>= fun new_ro_store ->
  let floating_stores = Block_store.floating_block_stores block_store in
  Animation.display_progress
    ~pp_print_step:(fun ppf i ->
      Format.fprintf ppf "Reconstructing floating blocks: %i" i)
    (fun notify ->
      List.iter_es
        (fun fs ->
          Floating_block_store.iter_with_pred_s
            (fun (block, predecessors) ->
              let level = Block_repr.level block in
              (* If the block is genesis then just retrieve its metadata. *)
              (if Store.Block.is_genesis chain_store (Block_repr.hash block)
              then
               Store.Chain.genesis_block chain_store >>= fun genesis_block ->
               Store.Block.get_block_metadata chain_store genesis_block
              else
                (* It is needed to read the metadata using the
                   cemented_block_store to avoid the cache mechanism which
                   stores blocks without metadata *)
                Cemented_block_store.read_block_metadata
                  (Block_store.cemented_block_store block_store)
                  level
                >>=? function
                | None ->
                    (* When the metadata is not available in the
                       cemented_block_store, it means that the block (in
                       the floating store) was not cemented yet. It is
                       thus needed to recompute its metadata + context
                    *)
                    let block = Store.Unsafe.block_of_repr block in
                    let predecessor_hash = Store.Block.predecessor block in
                    (* We try to read the predecessor in the floating
                       store as a floating store invariant assumes
                       that the predecessor of a block is always
                       stored before. In that case, by the definition
                       of [iter], the predecessor will be available
                       in the [new_ro_store], as already processed. *)
                    (Floating_block_store.read_block
                       new_ro_store
                       predecessor_hash
                     >>= function
                     | Some pb -> return (Store.Unsafe.block_of_repr pb)
                     | None -> (
                         (* If the predecessor was already cemented,
                            read it in the cemented store. It is
                            assumed to be valid as the cemented store
                            was restored previously.*)
                         Cemented_block_store.get_cemented_block_by_hash
                           ~read_metadata:true
                           cemented_block_store
                           predecessor_hash
                         >>=? function
                         | None ->
                             fail
                               (Reconstruction_failure
                                  (Cannot_read_block_hash predecessor_hash))
                         | Some b -> return (Store.Unsafe.block_of_repr b)))
                    >>=? fun predecessor_block ->
                    apply_context
                      context_index
                      chain_id
                      ~user_activated_upgrades
                      ~user_activated_protocol_overrides
                      ~predecessor_block_metadata_hash:
                        (Store.Block.block_metadata_hash predecessor_block)
                      ~predecessor_ops_metadata_hash:
                        (Store.Block.all_operations_metadata_hash
                           predecessor_block)
                      ~predecessor_block
                      block
                    >>=? fun res ->
                    Event.(emit reconstruct_block_success)
                      (Store.Block.descriptor block)
                    >>= fun () -> return res
                | Some m -> return m)
              >>=? fun metadata ->
              protocol_env_of_protocol_level
                chain_store
                (Block_repr.proto_level block)
                (Block_repr.hash block)
              >>=? fun block_protocol_env ->
              let reconstructed_block =
                restore_block_contents
                  chain_store
                  block_protocol_env
                  ~block_metadata:metadata.block_metadata
                  ~operations_metadata:metadata.operations_metadata
                  metadata
                  block
              in
              Floating_block_store.append_block
                new_ro_store
                predecessors
                reconstructed_block
              >>= fun () ->
              notify () >>= fun () -> return_unit)
            fs
          >>=? fun () -> return_unit)
        floating_stores)
  >>=? fun () ->
  Block_store.move_floating_store
    block_store
    ~src:new_ro_store
    ~dst_kind:Floating_block_store.RO
  >>=? fun () ->
  (* Reset the RW to an empty floating_block_store *)
  Floating_block_store.init chain_dir ~readonly:false RW_TMP >>= fun empty_rw ->
  Block_store.move_floating_store
    block_store
    ~src:empty_rw
    ~dst_kind:Floating_block_store.RW

(* Only Full modes with any offset can be reconstructed *)
let check_history_mode_compatibility chain_store savepoint genesis_block =
  match Store.Chain.history_mode chain_store with
  | History_mode.(Full _) ->
      fail_when
        (snd savepoint = Store.Block.level genesis_block)
        (Reconstruction_failure Nothing_to_reconstruct)
  | _ as history_mode -> fail (Cannot_reconstruct history_mode)

let restore_constants chain_store genesis_block head_lafl_block
    ~cementing_highwatermark =
  (* The checkpoint is updated to the last allowed fork level of the
     current head if higher than the cementing
     highwatermark. Otherwise, the checkpoint is assumed to be the
     cementing highwatermark (this may occur after a snapshot
     import). Thus, we ensure that the store invariant
     `cementing_highwatermark <= checkpoint` is maintained. *)
  let head_lafl_descr = Store.Block.descriptor head_lafl_block in
  let checkpoint =
    match cementing_highwatermark with
    | None -> head_lafl_descr
    | Some chw ->
        if snd chw > Store.Block.level head_lafl_block then chw
        else head_lafl_descr
  in
  Store.Unsafe.set_checkpoint chain_store checkpoint >>=? fun () ->
  Store.Unsafe.set_history_mode chain_store History_mode.Archive >>=? fun () ->
  let genesis = Store.Block.descriptor genesis_block in
  Store.Unsafe.set_savepoint chain_store genesis >>=? fun () ->
  Store.Unsafe.set_caboose chain_store genesis

(* Computes at which level the reconstruction should start. If a
   previous reconstruction is left unfinished, the procedure will restart
   at the lowest non cemented cycle. Otherwise, the reconstruction starts
   at the genesis. *)
let compute_start_level chain_store savepoint =
  let chain_dir = Store.Chain.chain_dir chain_store in
  let reconstruct_lockfile = Naming.reconstruction_lock_file chain_dir in
  let reconstruct_lockfile_path = Naming.file_path reconstruct_lockfile in
  if Sys.file_exists reconstruct_lockfile_path then
    let cemented_blocks_dir = Naming.cemented_blocks_dir chain_dir in
    Cemented_block_store.load_table cemented_blocks_dir >>=? function
    | None -> return 0l
    | Some l ->
        let rec aux level = function
          | [] -> return level
          | {Cemented_block_store.start_level; file; _} :: tl ->
              let metadata_file =
                Naming.cemented_blocks_metadata_file
                  (Naming.cemented_blocks_metadata_dir cemented_blocks_dir)
                  file
              in
              if Sys.file_exists (Naming.file_path metadata_file) then
                aux start_level tl
              else return start_level
        in
        aux 0l (Array.to_list l) >>=? fun start_block_level ->
        Store.Block.read_block_by_level chain_store start_block_level
        >>=? fun start_block ->
        Event.(
          emit
            reconstruct_resuming
            (Store.Block.descriptor start_block, savepoint))
        >>= fun () -> return start_block_level
  else Event.(emit reconstruct_start_default savepoint) >>= fun () -> return 0l

(* [locked chain_dir f] locks the [chain_dir] while [f] is
   executing. The aim of this lock is to:
   - avoid the node to be run while the storage reconstruction is
     running,
   - leave the lock file if the reconstruction is interrupted (by any
     exception or if cancelled) acknowledge that a reconstruction must
     be resumed. *)
let locked chain_dir f =
  let reconstruct_lockfile_path =
    Naming.reconstruction_lock_file chain_dir |> Naming.file_path
  in
  Lwt_unix.openfile
    reconstruct_lockfile_path
    [Unix.O_CREAT; O_RDWR; O_CLOEXEC; O_SYNC]
    0o644
  >>= fun file ->
  Lwt_unix.close file >>= fun () ->
  f () >>=? fun res ->
  Lwt_unix.unlink reconstruct_lockfile_path >>= fun () -> return res

let reconstruct ?patch_context ~store_dir ~context_dir genesis
    ~user_activated_upgrades ~user_activated_protocol_overrides =
  (* We need to inhibit the cache to avoid hitting the cache with
     already loaded blocks with missing metadata. *)
  Store.init
    ~block_cache_limit:1
    ?patch_context
    ~store_dir
    ~context_dir
    ~allow_testchains:false
    genesis
  >>=? fun store ->
  protect
    ~on_error:(fun err ->
      Store.close_store store >>= fun () -> Lwt.return (Error err))
    (fun () ->
      let context_index = Store.context_index store in
      let chain_store = Store.main_chain_store store in
      Store.Chain.genesis_block chain_store >>= fun genesis_block ->
      Store.Chain.savepoint chain_store >>= fun savepoint ->
      check_history_mode_compatibility chain_store savepoint genesis_block
      >>=? fun () ->
      compute_start_level chain_store savepoint >>=? fun start_block_level ->
      Event.(emit reconstruct_enum ()) >>= fun () ->
      Store.Chain.current_head chain_store >>= fun current_head ->
      Store.Block.get_block_metadata chain_store current_head
      >>=? fun head_metadata ->
      Store.Block.read_block_by_level
        chain_store
        (Store.Block.last_allowed_fork_level head_metadata)
      >>=? fun head_lafl_block ->
      Stored_data.load
        (Naming.cementing_highwatermark_file
           (Store.Chain.chain_dir chain_store))
      >>=? fun cementing_highwatermark_data ->
      (Stored_data.get cementing_highwatermark_data >>= function
       | None -> return_none
       | Some chw ->
           Store.Block.read_block_by_level chain_store chw
           >|=? Store.Block.descriptor >>=? return_some)
      >>=? fun cementing_highwatermark ->
      let chain_dir = Store.Chain.chain_dir chain_store in
      locked chain_dir (fun () ->
          reconstruct_cemented
            chain_store
            context_index
            ~user_activated_upgrades
            ~user_activated_protocol_overrides
            ~start_block_level
          >>=? fun () ->
          reconstruct_floating
            chain_store
            context_index
            ~user_activated_upgrades
            ~user_activated_protocol_overrides
          >>=? fun () ->
          restore_constants
            chain_store
            genesis_block
            head_lafl_block
            ~cementing_highwatermark)
      >>=? fun () ->
      (* TODO? add a global check *)
      Event.(emit reconstruct_success ()) >>= fun () ->
      Store.close_store store >>= return)
