open Tezos_shell_services
module Directory = Tezos_rpc.RPC_directory
module Chain_services = Tezos_shell_services.Chain_services
module Block_services = Tezos_shell_services.Block_services
module Block_services_alpha = Protocol_client_context.Alpha_block_services

module type Mocked_services_hooks = sig
  type mempool = Mockup.M.Block_services.Mempool.t

  (** The baker and endorser rely on this stream to be notified of new
     blocks. *)
  val monitor_heads : unit -> (Block_hash.t * Block_header.t) RPC_answer.stream

  (** Returns current and next protocol for a block. *)
  val protocols :
    Block_services.block -> Block_services.protocols tzresult Lwt.t

  (** [header] returns the block header of the block associated to the given
     block specification. *)
  val header :
    Block_services.block -> Mockup.M.Block_services.block_header tzresult Lwt.t

  (** [operations] returns all operations included in the block. *)
  val operations :
    Block_services.block ->
    Mockup.M.Block_services.operation list list tzresult Lwt.t

  (** [inject_block_callback] is called when an RPC is performed on
     [Tezos_shell_services.Injection_services.S.block], after checking that
     the block header can be deserialized. *)
  val inject_block :
    Block_hash.t ->
    Block_header.t ->
    Operation.t trace trace ->
    unit tzresult Lwt.t

  (** [inject_operation] is used by the endorser (or the client) to inject
      operations, including endorsements. *)
  val inject_operation : Operation.t -> Operation_hash.t tzresult Lwt.t

  (** [pending_operations] returns the current contents of the mempool. It
     is used by the baker to fetch operations to potentially include in the
     block being baked. These operations might include endorsements. If
     there aren't enough endorsements, the baker waits on
     [monitor_operations]. *)
  val pending_operations : unit -> mempool Lwt.t

  (** Return a stream of list of operations. Used by the baker to wait on
     endorsements. Invariant: the stream becomes empty when the node changes
     head. *)
  val monitor_operations :
    applied:bool ->
    branch_delayed:bool ->
    branch_refused:bool ->
    refused:bool ->
    ((Operation_hash.t * Mockup.M.Protocol.operation) * error trace option) list
    RPC_answer.stream

  (** Lists block hashes from the chain, up to the last checkpoint, sorted
     with decreasing fitness. Without arguments it returns the head of the
     chain. Optional arguments allow to return the list of predecessors of a
     given block or of a set of blocks. *)
  val list_blocks :
    heads:Block_hash.t list ->
    length:int option ->
    min_date:Time.Protocol.t option ->
    Block_hash.t list list tzresult Lwt.t

  (** List the ancestors of the given block which, if referred to as
      the branch in an operation header, are recent enough for that
      operation to be included in the current block. *)
  val live_blocks : Block_services.block -> Block_hash.Set.t tzresult Lwt.t

  (** [rpc_context_callback] is used in the implementations of several
      RPCs (see local_services.ml). It should correspond to the
      rpc_context constructed from the context at the requested block. *)
  val rpc_context_callback :
    Block_services.block -> Environment_context.rpc_context tzresult Lwt.t

  (** Return raw protocol data as a block. *)
  val raw_protocol_data : Block_services.block -> Bytes.t tzresult Lwt.t

  (** Broadcast block manually to nodes [dests] (given by their
     number, starting from 0). If [dests] is not provided, broadcast
     to all nodes. *)
  val broadcast_block :
    ?dests:int list ->
    Block_hash.t ->
    Block_header.t ->
    Operation.t trace trace ->
    unit tzresult Lwt.t

  (** Broadcast operation manually to nodes [dests] (given by their
     number, starting from 0). If [dests] is not provided, broadcast
     to all nodes. *)
  val broadcast_operation :
    ?dests:int list -> Alpha_context.packed_operation -> unit tzresult Lwt.t

  (** Simulate waiting for the node to be bootstrapped. Because the
      simulated node is already bootstrapped, returns the current head
      immediately. *)
  val monitor_bootstrapped :
    unit -> (Block_hash.t * Time.Protocol.t) RPC_answer.stream
end

type hooks = (module Mocked_services_hooks)

module Make (Hooks : Mocked_services_hooks) = struct
  let monitor_heads =
    Directory.gen_register1
      Directory.empty
      Monitor_services.S.heads
      (fun _chain _next_protocol () ->
        RPC_answer.return_stream (Hooks.monitor_heads ()))

  let monitor_bootstrapped =
    Directory.gen_register0
      Directory.empty
      Monitor_services.S.bootstrapped
      (fun () () -> RPC_answer.return_stream (Hooks.monitor_bootstrapped ()))

  let protocols =
    let path =
      let open Tezos_rpc.RPC_path in
      prefix Block_services.chain_path Block_services.path
    in
    let service =
      Tezos_rpc.RPC_service.prefix path Block_services.Empty.S.protocols
    in
    Directory.register Directory.empty service (fun (_, block) () () ->
        Hooks.protocols block)

  let header =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Mockup.M.Block_services.S.header
         (fun (((), _chain), block) _ _ -> Hooks.header block)

  let operations =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Mockup.M.Block_services.S.Operations.operations
         (fun (((), _chain), block) () () -> Hooks.operations block)

  let hash =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Block_services.Empty.S.hash
         (fun (((), _chain), block) () () ->
           Hooks.header block >>=? fun x -> return x.hash)

  let shell_header =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Mockup.M.Block_services.S.Header.shell_header
         (fun (((), _chain), block) _ _ ->
           Hooks.header block >>=? fun x -> return x.shell)

  let chain chain_id =
    Directory.prefix
      Chain_services.path
      (Directory.register
         Directory.empty
         Chain_services.S.chain_id
         (fun _chain () () -> return chain_id))

  let inject_block =
    Directory.register
      Directory.empty
      Injection_services.S.block
      (fun () _chain (bytes, operations) ->
        match Block_header.of_bytes bytes with
        | None -> failwith "faked_services.inject_block: can't deserialize"
        | Some block_header ->
            let block_hash = Block_hash.hash_bytes [bytes] in
            Hooks.inject_block block_hash block_header operations >>=? fun () ->
            return block_hash)

  let inject_operation =
    Directory.register
      Directory.empty
      Injection_services.S.operation
      (fun () _chain bytes ->
        match Data_encoding.Binary.of_bytes_opt Operation.encoding bytes with
        | None -> failwith "faked_services.inject_operation: can't deserialize"
        | Some operation -> Hooks.inject_operation operation)

  let broadcast_block =
    Directory.register
      Directory.empty
      Broadcast_services.S.block
      (fun () dests (block_header, operations) ->
        let bytes = Block_header.to_bytes block_header in
        let block_hash = Block_hash.hash_bytes [bytes] in
        let dests = match dests#dests with [] -> None | dests -> Some dests in
        Hooks.broadcast_block ?dests block_hash block_header operations)

  let broadcast_operation =
    Directory.register
      Directory.empty
      Broadcast_services.S.operation
      (fun () dests operation ->
        let dests = match dests#dests with [] -> None | dests -> Some dests in
        Hooks.broadcast_operation ?dests operation)

  let pending_operations =
    Directory.gen_register
      Directory.empty
      (Mockup.M.Block_services.S.Mempool.pending_operations
      @@ Block_services.mempool_path Block_services.chain_path)
      (fun ((), _chain) _params () ->
        Hooks.pending_operations () >>= fun mempool ->
        Mockup.M.Block_services.Mempool.pending_operations_version_dispatcher
          ~version:1
          mempool)

  let monitor_operations =
    Directory.gen_register
      Directory.empty
      (Block_services_alpha.S.Mempool.monitor_operations
      @@ Block_services.mempool_path Block_services.chain_path)
      (fun ((), _chain) flags () ->
        let stream =
          Hooks.monitor_operations
            ~applied:flags#applied
            ~branch_delayed:flags#branch_delayed
            ~branch_refused:flags#branch_refused
            ~refused:flags#refused
        in
        RPC_answer.return_stream stream)

  let list_blocks =
    Directory.prefix
      Chain_services.path
      (Directory.register
         Directory.empty
         Chain_services.S.Blocks.list
         (fun ((), _chain) flags () ->
           Hooks.list_blocks
             ~heads:flags#heads
             ~length:flags#length
             ~min_date:flags#min_date))

  let live_blocks =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Block_services.Empty.S.live_blocks
         (fun (_, block) _ () -> Hooks.live_blocks block)

  let raw_protocol_data =
    Directory.prefix
      (Tezos_rpc.RPC_path.prefix Chain_services.path Block_services.path)
    @@ Directory.register
         Directory.empty
         Block_services.Empty.S.Header.raw_protocol_data
         (fun (_, block) () () -> Hooks.raw_protocol_data block)

  let shell_directory chain_id =
    let merge = Directory.merge in
    Directory.empty |> merge monitor_heads |> merge protocols |> merge header
    |> merge operations |> merge hash |> merge shell_header
    |> merge (chain chain_id)
    |> merge inject_block |> merge inject_operation |> merge monitor_operations
    |> merge list_blocks |> merge live_blocks |> merge raw_protocol_data
    |> merge broadcast_block |> merge broadcast_operation
    |> merge monitor_bootstrapped

  let directory chain_id =
    let proto_directory =
      Directory.prefix
        Chain_services.path
        (Directory.prefix
           Block_services.path
           (Directory.map
              (fun (((), _chain), block) ->
                Hooks.rpc_context_callback block >>= function
                | Error _ -> assert false
                | Ok rpc_context -> Lwt.return rpc_context)
              Mockup.M.directory))
    in
    let base = Directory.merge (shell_directory chain_id) proto_directory in
    RPC_directory.register_describe_directory_service
      base
      RPC_service.description_service
end
