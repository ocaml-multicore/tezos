(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2018-2021 Nomadic Labs. <contact@nomadic-labs.com>          *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

open Block_validator_errors
open Validation_errors

module Event = struct
  include Internal_event.Simple

  let inherited_inconsistent_cache =
    declare_1
      ~section:["block"; "validation"]
      ~name:"block_validation_inconsistent_cache"
      ~msg:"applied block {hash} with an inconsistent cache: reloading cache"
      ~level:Warning
      ~pp1:Block_hash.pp
      ("hash", Block_hash.encoding)
end

type validation_store = {
  context_hash : Context_hash.t;
  timestamp : Time.Protocol.t;
  message : string option;
  max_operations_ttl : int;
  last_allowed_fork_level : Int32.t;
}

let validation_store_encoding =
  let open Data_encoding in
  conv
    (fun {
           context_hash;
           timestamp;
           message;
           max_operations_ttl;
           last_allowed_fork_level;
         } ->
      ( context_hash,
        timestamp,
        message,
        max_operations_ttl,
        last_allowed_fork_level ))
    (fun ( context_hash,
           timestamp,
           message,
           max_operations_ttl,
           last_allowed_fork_level ) ->
      {
        context_hash;
        timestamp;
        message;
        max_operations_ttl;
        last_allowed_fork_level;
      })
    (obj5
       (req "context_hash" Context_hash.encoding)
       (req "timestamp" Time.Protocol.encoding)
       (req "message" (option string))
       (req "max_operations_ttl" int31)
       (req "last_allowed_fork_level" int32))

type result = {
  validation_store : validation_store;
  block_metadata : Bytes.t;
  ops_metadata : Bytes.t list list;
  block_metadata_hash : Block_metadata_hash.t option;
  ops_metadata_hashes : Operation_metadata_hash.t list list option;
}

type apply_result = {result : result; cache : Environment_context.Context.cache}

let check_proto_environment_version_increasing block_hash before after =
  if Protocol.compare_version before after <= 0 then Result.return_unit
  else
    error
      (invalid_block
         block_hash
         (Invalid_protocol_environment_transition (before, after)))

let update_testchain_status ctxt ~predecessor_hash timestamp =
  let open Lwt_syntax in
  let* tc = Context.get_test_chain ctxt in
  match tc with
  | Not_running -> Lwt.return ctxt
  | Running {expiration; _} ->
      if Time.Protocol.(expiration <= timestamp) then
        Context.add_test_chain ctxt Not_running
      else Lwt.return ctxt
  | Forking {protocol; expiration} ->
      let genesis = Context.compute_testchain_genesis predecessor_hash in
      let chain_id = Chain_id.of_block_hash genesis in
      (* legacy semantics *)
      Context.add_test_chain
        ctxt
        (Running {chain_id; genesis; protocol; expiration})

let init_test_chain ctxt forked_header =
  let open Lwt_tzresult_syntax in
  let*! tc = Context.get_test_chain ctxt in
  match tc with
  | Not_running | Running _ -> assert false
  | Forking {protocol; _} ->
      let* (module Proto_test) =
        match Registered_protocol.get protocol with
        | Some proto -> return proto
        | None -> fail (Missing_test_protocol protocol)
      in
      let test_ctxt = Shell_context.wrap_disk_context ctxt in
      let*! () =
        Validation_events.(emit new_protocol_initialisation protocol)
      in
      Proto_test.set_log_message_consumer
        (Protocol_logging.make_log_message_consumer ()) ;
      let* {context = test_ctxt; _} =
        Proto_test.init test_ctxt forked_header.Block_header.shell
      in
      let test_ctxt = Shell_context.unwrap_disk_context test_ctxt in
      let*! test_ctxt = Context.add_test_chain test_ctxt Not_running in
      let*! test_ctxt = Context.add_protocol test_ctxt protocol in
      Lwt_result.ok @@ Context.commit_test_chain_genesis test_ctxt forked_header

let result_encoding =
  let open Data_encoding in
  conv
    (fun {
           validation_store;
           block_metadata;
           ops_metadata;
           block_metadata_hash;
           ops_metadata_hashes;
         } ->
      ( validation_store,
        block_metadata,
        ops_metadata,
        block_metadata_hash,
        ops_metadata_hashes ))
    (fun ( validation_store,
           block_metadata,
           ops_metadata,
           block_metadata_hash,
           ops_metadata_hashes ) ->
      {
        validation_store;
        block_metadata;
        ops_metadata;
        block_metadata_hash;
        ops_metadata_hashes;
      })
    (obj5
       (req "validation_store" validation_store_encoding)
       (req "block_metadata" bytes)
       (req "ops_metadata" (list (list bytes)))
       (opt "block_metadata_hash" Block_metadata_hash.encoding)
       (opt
          "ops_metadata_hashes"
          (list @@ list @@ Operation_metadata_hash.encoding)))

let preapply_result_encoding :
    (Block_header.shell_header * error Preapply_result.t list) Data_encoding.t =
  let open Data_encoding in
  obj2
    (req "shell_header" Block_header.shell_header_encoding)
    (req
       "preapplied_operations_result"
       (list (Preapply_result.encoding RPC_error.encoding)))

let may_force_protocol_upgrade ~user_activated_upgrades ~level
    (validation_result : Tezos_protocol_environment.validation_result) =
  let open Lwt_syntax in
  match
    Block_header.get_forced_protocol_upgrade ~user_activated_upgrades ~level
  with
  | None -> return validation_result
  | Some hash ->
      let* context =
        Environment_context.Context.set_protocol validation_result.context hash
      in
      return {validation_result with context}

(** Applies user activated updates based either on block level or on
    voted protocols *)
let may_patch_protocol ~user_activated_upgrades
    ~user_activated_protocol_overrides ~level
    (validation_result : Tezos_protocol_environment.validation_result) =
  let open Lwt_syntax in
  let context = Shell_context.unwrap_disk_context validation_result.context in
  let* protocol = Context.get_protocol context in
  match
    Block_header.get_voted_protocol_overrides
      ~user_activated_protocol_overrides
      protocol
  with
  | None ->
      may_force_protocol_upgrade
        ~user_activated_upgrades
        ~level
        validation_result
  | Some replacement_protocol ->
      let* context =
        Environment_context.Context.set_protocol
          validation_result.context
          replacement_protocol
      in
      return {validation_result with context}

module Make (Proto : Registered_protocol.T) = struct
  type 'operation_data preapplied_operation = {
    hash : Operation_hash.t;
    raw : Operation.t;
    protocol_data : 'operation_data;
  }

  type preapply_state = {
    state : Proto.validation_state;
    applied :
      (Proto.operation_data preapplied_operation * Proto.operation_receipt) list;
    live_blocks : Block_hash.Set.t;
    live_operations : Operation_hash.Set.t;
  }

  type preapply_result =
    | Applied of preapply_state * Proto.operation_receipt
    | Branch_delayed of error list
    | Branch_refused of error list
    | Refused of error list
    | Outdated

  let check_block_header ~(predecessor_block_header : Block_header.t) hash
      (block_header : Block_header.t) =
    let open Lwt_tzresult_syntax in
    let* () =
      fail_unless
        (Int32.succ predecessor_block_header.shell.level
        = block_header.shell.level)
        (invalid_block hash
        @@ Invalid_level
             {
               expected = Int32.succ predecessor_block_header.shell.level;
               found = block_header.shell.level;
             })
    in
    let* () =
      fail_unless
        Time.Protocol.(
          predecessor_block_header.shell.timestamp
          < block_header.shell.timestamp)
        (invalid_block hash Non_increasing_timestamp)
    in
    let* () =
      fail_unless
        Fitness.(
          predecessor_block_header.shell.fitness < block_header.shell.fitness)
        (invalid_block hash Non_increasing_fitness)
    in
    let* () =
      fail_unless
        Compare.List_length_with.(
          Proto.validation_passes = block_header.shell.validation_passes)
        (invalid_block
           hash
           (Unexpected_number_of_validation_passes
              block_header.shell.validation_passes))
    in
    return_unit

  let parse_block_header block_hash (block_header : Block_header.t) =
    match
      Data_encoding.Binary.of_bytes_opt
        Proto.block_header_data_encoding
        block_header.protocol_data
    with
    | None -> fail (invalid_block block_hash Cannot_parse_block_header)
    | Some protocol_data ->
        return
          ({shell = block_header.shell; protocol_data} : Proto.block_header)

  let check_one_operation_quota block_hash pass ops quota =
    let open Lwt_tzresult_syntax in
    let* () =
      fail_unless
        (match quota.Tezos_protocol_environment.max_op with
        | None -> true
        | Some max -> Compare.List_length_with.(ops <= max))
        (let max = Option.value ~default:~-1 quota.max_op in
         invalid_block
           block_hash
           (Too_many_operations {pass; found = List.length ops; max}))
    in
    List.iter_ep
      (fun op ->
        let size = Data_encoding.Binary.length Operation.encoding op in
        fail_unless
          (size <= Proto.max_operation_data_length)
          (invalid_block
             block_hash
             (Oversized_operation
                {
                  operation = Operation.hash op;
                  size;
                  max = Proto.max_operation_data_length;
                })))
      ops

  let check_operation_quota block_hash operations =
    let combined =
      match
        List.combine
          ~when_different_lengths:()
          operations
          Proto.validation_passes
      with
      | Ok combined -> combined
      | Error () ->
          raise (Invalid_argument "Block_validation.check_operation_quota")
    in
    List.iteri_ep
      (fun i (ops, quota) ->
        (* passes are 1-based, iteri is 0-based *)
        let pass = i + 1 in
        check_one_operation_quota block_hash pass ops quota)
      combined

  let parse_operations block_hash operations =
    let invalid_block = invalid_block block_hash in
    List.mapi_es
      (fun pass ->
        List.map_es (fun op ->
            let op_hash = Operation.hash op in
            match
              Data_encoding.Binary.of_bytes_opt
                Proto.operation_data_encoding
                op.Operation.proto
            with
            | None -> fail (invalid_block (Cannot_parse_operation op_hash))
            | Some protocol_data ->
                let open Lwt_tzresult_syntax in
                let op = {Proto.shell = op.shell; protocol_data} in
                let allowed_pass = Proto.acceptable_passes op in
                let* () =
                  fail_unless
                    (List.mem ~equal:Int.equal pass allowed_pass)
                    (invalid_block
                       (Unallowed_pass {operation = op_hash; pass; allowed_pass}))
                in
                return op))
      operations

  let apply ?cached_result chain_id ~cache ~user_activated_upgrades
      ~user_activated_protocol_overrides ~max_operations_ttl
      ~(predecessor_block_header : Block_header.t)
      ~predecessor_block_metadata_hash ~predecessor_ops_metadata_hash
      ~predecessor_context ~(block_header : Block_header.t) operations =
    let open Lwt_tzresult_syntax in
    let block_hash = Block_header.hash block_header in
    match cached_result with
    | Some (({result; _} as cached_result), context)
      when Context_hash.equal
             result.validation_store.context_hash
             block_header.shell.context
           && Time.Protocol.equal
                result.validation_store.timestamp
                block_header.shell.timestamp ->
        let*! () = Validation_events.(emit using_preapply_result block_hash) in
        let*! context_hash =
          Context.commit
            ~time:block_header.shell.timestamp
            ?message:result.validation_store.message
            context
        in
        assert (
          Context_hash.equal context_hash result.validation_store.context_hash) ;
        return cached_result
    | Some _ | None ->
        let invalid_block = invalid_block block_hash in
        let* () =
          check_block_header ~predecessor_block_header block_hash block_header
        in
        let* block_header = parse_block_header block_hash block_header in
        let* () = check_operation_quota block_hash operations in
        let predecessor_hash = Block_header.hash predecessor_block_header in
        let*! context =
          update_testchain_status
            predecessor_context
            ~predecessor_hash
            block_header.shell.timestamp
        in
        let* operations = parse_operations block_hash operations in
        let*! context =
          match predecessor_block_metadata_hash with
          | None -> Lwt.return context
          | Some hash ->
              Context.add_predecessor_block_metadata_hash context hash
        in
        let*! context =
          match predecessor_ops_metadata_hash with
          | None -> Lwt.return context
          | Some hash -> Context.add_predecessor_ops_metadata_hash context hash
        in
        let context = Shell_context.wrap_disk_context context in
        let* (validation_result, block_data, ops_metadata) =
          let*! r =
            let* state =
              Proto.begin_application
                ~chain_id
                ~predecessor_context:context
                ~predecessor_timestamp:predecessor_block_header.shell.timestamp
                ~predecessor_fitness:predecessor_block_header.shell.fitness
                block_header
                ~cache
            in
            let* (state, ops_metadata) =
              List.fold_left_es
                (fun (state, acc) ops ->
                  let* (state, ops_metadata) =
                    List.fold_left_es
                      (fun (state, acc) op ->
                        let* (state, op_metadata) =
                          Proto.apply_operation state op
                        in
                        return (state, op_metadata :: acc))
                      (state, [])
                      ops
                  in
                  return (state, List.rev ops_metadata :: acc))
                (state, [])
                operations
            in
            let ops_metadata = List.rev ops_metadata in
            let* (validation_result, block_data) =
              Proto.finalize_block state (Some block_header.shell)
            in
            return (validation_result, block_data, ops_metadata)
          in
          match r with
          | Error err -> fail (invalid_block (Economic_protocol_error err))
          | Ok o -> return o
        in
        let*! validation_result =
          may_patch_protocol
            ~user_activated_upgrades
            ~user_activated_protocol_overrides
            ~level:block_header.shell.level
            validation_result
        in
        let context =
          Shell_context.unwrap_disk_context validation_result.context
        in
        let*! new_protocol = Context.get_protocol context in
        let expected_proto_level =
          if Protocol_hash.equal new_protocol Proto.hash then
            predecessor_block_header.shell.proto_level
          else (predecessor_block_header.shell.proto_level + 1) mod 256
        in
        let* () =
          fail_when
            (block_header.shell.proto_level <> expected_proto_level)
            (invalid_block
               (Invalid_proto_level
                  {
                    found = block_header.shell.proto_level;
                    expected = expected_proto_level;
                  }))
        in
        let* () =
          fail_when
            Fitness.(validation_result.fitness <> block_header.shell.fitness)
            (invalid_block
               (Invalid_fitness
                  {
                    expected = block_header.shell.fitness;
                    found = validation_result.fitness;
                  }))
        in
        let* (validation_result, new_protocol_env_version) =
          if Protocol_hash.equal new_protocol Proto.hash then
            return (validation_result, Proto.environment_version)
          else
            match Registered_protocol.get new_protocol with
            | None ->
                fail
                  (Unavailable_protocol
                     {block = block_hash; protocol = new_protocol})
            | Some (module NewProto) ->
                let*? () =
                  check_proto_environment_version_increasing
                    block_hash
                    Proto.environment_version
                    NewProto.environment_version
                in
                let*! () =
                  Validation_events.(
                    emit new_protocol_initialisation new_protocol)
                in
                NewProto.set_log_message_consumer
                  (Protocol_logging.make_log_message_consumer ()) ;
                let* validation_result =
                  NewProto.init validation_result.context block_header.shell
                in
                return (validation_result, NewProto.environment_version)
        in
        let max_operations_ttl =
          max
            0
            (min (max_operations_ttl + 1) validation_result.max_operations_ttl)
        in
        let validation_result = {validation_result with max_operations_ttl} in
        let block_metadata =
          Data_encoding.Binary.to_bytes_exn
            Proto.block_header_metadata_encoding
            block_data
        in
        let* ops_metadata =
          try
            return
              (List.map
                 (List.map (fun receipt ->
                      (* Check that the metadata are
                         serializable/deserializable *)
                      let bytes =
                        Data_encoding.Binary.to_bytes_exn
                          Proto.operation_receipt_encoding
                          receipt
                      in
                      let _ =
                        Data_encoding.Binary.of_bytes_exn
                          Proto.operation_receipt_encoding
                          bytes
                      in
                      bytes))
                 ops_metadata)
          with exn ->
            trace
              Validation_errors.Cannot_serialize_operation_metadata
              (fail (Exn exn))
        in
        let (Context {cache; _}) = validation_result.context in
        let context =
          Shell_context.unwrap_disk_context validation_result.context
        in
        let*! (ops_metadata_hashes, block_metadata_hash) =
          match new_protocol_env_version with
          | Protocol.V0 -> Lwt.return (None, None)
          | Protocol.(V1 | V2 | V3 | V4 | V5) ->
              Lwt.return
                ( Some
                    (List.map
                       (List.map (fun r ->
                            Operation_metadata_hash.hash_bytes [r]))
                       ops_metadata),
                  Some (Block_metadata_hash.hash_bytes [block_metadata]) )
        in
        let*! context_hash =
          Context.commit
            ~time:block_header.shell.timestamp
            ?message:validation_result.message
            context
        in
        let* () =
          fail_unless
            (Context_hash.equal context_hash block_header.shell.context)
            (Validation_errors.Inconsistent_hash
               (context_hash, block_header.shell.context))
        in
        let validation_store =
          {
            context_hash;
            timestamp = block_header.shell.timestamp;
            message = validation_result.message;
            max_operations_ttl = validation_result.max_operations_ttl;
            last_allowed_fork_level = validation_result.last_allowed_fork_level;
          }
        in
        return
          {
            result =
              {
                validation_store;
                block_metadata;
                ops_metadata;
                block_metadata_hash;
                ops_metadata_hashes;
              };
            cache;
          }

  let preapply_operation pv op =
    let open Lwt_syntax in
    if Operation_hash.Set.mem op.hash pv.live_operations then return Outdated
    else
      let+ r =
        protect (fun () ->
            Proto.apply_operation
              pv.state
              {shell = op.raw.shell; protocol_data = op.protocol_data})
      in
      match r with
      | Ok (state, receipt) -> (
          let pv =
            {
              state;
              applied = (op, receipt) :: pv.applied;
              live_blocks = pv.live_blocks;
              live_operations =
                Operation_hash.Set.add op.hash pv.live_operations;
            }
          in
          match
            Data_encoding.Binary.(
              of_bytes_exn
                Proto.operation_receipt_encoding
                (to_bytes_exn Proto.operation_receipt_encoding receipt))
          with
          | receipt -> Applied (pv, receipt)
          | exception exn ->
              Refused
                [Validation_errors.Cannot_serialize_operation_metadata; Exn exn]
          )
      | Error trace -> (
          match classify_trace trace with
          | Branch -> Branch_refused trace
          | Permanent -> Refused trace
          | Temporary -> Branch_delayed trace
          | Outdated -> Outdated)

  (** Doesn't depend on heavy [Registered_protocol.T] for testability. *)
  let safe_binary_of_bytes (encoding : 'a Data_encoding.t) (bytes : bytes) :
      'a tzresult =
    match Data_encoding.Binary.of_bytes_opt encoding bytes with
    | None -> error Parse_error
    | Some protocol_data -> ok protocol_data

  let parse_unsafe (proto : bytes) : Proto.operation_data tzresult =
    safe_binary_of_bytes Proto.operation_data_encoding proto

  let parse (raw : Operation.t) =
    let open Tzresult_syntax in
    let hash = Operation.hash raw in
    let size = Data_encoding.Binary.length Operation.encoding raw in
    if size > Proto.max_operation_data_length then
      fail (Oversized_operation {size; max = Proto.max_operation_data_length})
    else
      let* protocol_data = parse_unsafe raw.proto in
      return {hash; raw; protocol_data}

  let preapply ~chain_id ~cache ~user_activated_upgrades
      ~user_activated_protocol_overrides ~protocol_data ~live_blocks
      ~live_operations ~timestamp ~predecessor_context
      ~(predecessor_shell_header : Block_header.shell_header) ~predecessor_hash
      ~predecessor_max_operations_ttl ~predecessor_block_metadata_hash
      ~predecessor_ops_metadata_hash ~operations =
    let open Lwt_tzresult_syntax in
    let context = predecessor_context in
    let*! context =
      update_testchain_status context ~predecessor_hash timestamp
    in
    let should_metadata_be_present =
      (* Block and operation metadata hashes may not be set on the
         testchain genesis block and activation block, even when they
         are using environment V1, they contain no operations. *)
      let is_from_genesis = predecessor_shell_header.validation_passes = 0 in
      Protocol.(
        match Proto.environment_version with
        | V0 -> false
        | V1 | V2 | V3 | V4 | V5 -> true)
      && not is_from_genesis
    in
    let* context =
      match predecessor_block_metadata_hash with
      | None ->
          if should_metadata_be_present then
            fail (Missing_block_metadata_hash predecessor_hash)
          else return context
      | Some hash ->
          Lwt_result.ok
          @@ Context.add_predecessor_block_metadata_hash context hash
    in
    let* context =
      match predecessor_ops_metadata_hash with
      | None ->
          if should_metadata_be_present then
            fail (Missing_operation_metadata_hashes predecessor_hash)
          else return context
      | Some hash ->
          Lwt_result.ok
          @@ Context.add_predecessor_ops_metadata_hash context hash
    in
    let wrapped_context = Shell_context.wrap_disk_context context in
    let* state =
      Proto.begin_construction
        ~chain_id
        ~predecessor_context:wrapped_context
        ~predecessor_timestamp:predecessor_shell_header.Block_header.timestamp
        ~predecessor_fitness:predecessor_shell_header.Block_header.fitness
        ~predecessor_level:predecessor_shell_header.level
        ~predecessor:predecessor_hash
        ~timestamp
        ~protocol_data
        ~cache
        ()
    in
    let preapply_state = {state; applied = []; live_blocks; live_operations} in
    let apply_operation_with_preapply_result preapp t receipts op =
      let open Preapply_result in
      let*! r = preapply_operation t op in
      match r with
      | Applied (t, receipt) ->
          let applied = (op.hash, op.raw) :: preapp.applied in
          Lwt.return ({preapp with applied}, t, receipt :: receipts)
      | Branch_delayed errors ->
          let branch_delayed =
            Operation_hash.Map.add
              op.hash
              (op.raw, errors)
              preapp.branch_delayed
          in
          Lwt.return ({preapp with branch_delayed}, t, receipts)
      | Branch_refused errors ->
          let branch_refused =
            Operation_hash.Map.add
              op.hash
              (op.raw, errors)
              preapp.branch_refused
          in
          Lwt.return ({preapp with branch_refused}, t, receipts)
      | Refused errors ->
          let refused =
            Operation_hash.Map.add op.hash (op.raw, errors) preapp.refused
          in
          Lwt.return ({preapp with refused}, t, receipts)
      | Outdated -> Lwt.return (preapp, t, receipts)
    in
    let*! ( validation_passes,
            validation_result_list_rev,
            receipts_rev,
            validation_state ) =
      List.fold_left_s
        (fun ( acc_validation_passes,
               acc_validation_result_rev,
               receipts,
               acc_validation_state )
             operations ->
          let*! (new_validation_result, new_validation_state, rev_receipts) =
            List.fold_left_s
              (fun (acc_validation_result, acc_validation_state, receipts) op ->
                match parse op with
                | Error _ ->
                    (* FIXME: https://gitlab.com/tezos/tezos/-/issues/1721  *)
                    Lwt.return
                      (acc_validation_result, acc_validation_state, receipts)
                | Ok op ->
                    apply_operation_with_preapply_result
                      acc_validation_result
                      acc_validation_state
                      receipts
                      op)
              (Preapply_result.empty, acc_validation_state, [])
              operations
          in
          (* Applied operations are reverted ; revert to the initial ordering *)
          let new_validation_result =
            {
              new_validation_result with
              applied = List.rev new_validation_result.applied;
            }
          in
          Lwt.return
            ( acc_validation_passes + 1,
              new_validation_result :: acc_validation_result_rev,
              List.rev rev_receipts :: receipts,
              new_validation_state ))
        (0, [], [], preapply_state)
        operations
    in
    let validation_result_list = List.rev validation_result_list_rev in
    let applied_ops_metadata = List.rev receipts_rev in
    let preapply_state = validation_state in
    let operations_hash =
      Operation_list_list_hash.compute
        (List.rev_map
           (fun r ->
             Operation_list_hash.compute
               (List.map fst r.Preapply_result.applied))
           validation_result_list_rev)
    in
    let level = Int32.succ predecessor_shell_header.level in
    let shell_header : Block_header.shell_header =
      {
        level;
        proto_level = predecessor_shell_header.proto_level;
        predecessor = predecessor_hash;
        timestamp;
        validation_passes;
        operations_hash;
        context = Context_hash.zero (* place holder *);
        fitness = [];
      }
    in
    let* (validation_result, block_header_metadata) =
      Proto.finalize_block preapply_state.state (Some shell_header)
    in
    let*! validation_result =
      may_patch_protocol
        ~user_activated_upgrades
        ~user_activated_protocol_overrides
        ~level
        validation_result
    in
    let*! protocol =
      Environment_context.Context.get_protocol validation_result.context
    in
    let proto_level =
      if Protocol_hash.equal protocol Proto.hash then
        predecessor_shell_header.proto_level
      else (predecessor_shell_header.proto_level + 1) mod 256
    in
    let shell_header : Block_header.shell_header =
      {shell_header with proto_level; fitness = validation_result.fitness}
    in
    let* (validation_result, cache, new_protocol_env_version) =
      if Protocol_hash.equal protocol Proto.hash then
        let (Environment_context.Context.Context {cache; _}) =
          validation_result.context
        in
        return (validation_result, cache, Proto.environment_version)
      else
        match Registered_protocol.get protocol with
        | None ->
            fail
              (Block_validator_errors.Unavailable_protocol
                 {block = predecessor_hash; protocol})
        | Some (module NewProto) ->
            let*? () =
              check_proto_environment_version_increasing
                Block_hash.zero
                Proto.environment_version
                NewProto.environment_version
            in
            NewProto.set_log_message_consumer
              (Protocol_logging.make_log_message_consumer ()) ;
            let* validation_result =
              NewProto.init validation_result.context shell_header
            in
            let (Environment_context.Context.Context {cache; _}) =
              validation_result.context
            in
            let*! () =
              Validation_events.(emit new_protocol_initialisation NewProto.hash)
            in
            return (validation_result, cache, NewProto.environment_version)
    in
    let context = Shell_context.unwrap_disk_context validation_result.context in
    let context_hash =
      Context.hash ?message:validation_result.message ~time:timestamp context
    in
    let preapply_result =
      ({shell_header with context = context_hash}, validation_result_list)
    in
    let block_metadata =
      Data_encoding.Binary.to_bytes_exn
        Proto.block_header_metadata_encoding
        block_header_metadata
    in
    let* ops_metadata =
      try
        return
          (List.map
             (List.map (fun receipt ->
                  (* Check that the metadata are
                     serializable/deserializable *)
                  let bytes =
                    Data_encoding.Binary.to_bytes_exn
                      Proto.operation_receipt_encoding
                      receipt
                  in
                  let _ =
                    Data_encoding.Binary.of_bytes_exn
                      Proto.operation_receipt_encoding
                      bytes
                  in
                  bytes))
             applied_ops_metadata)
      with exn ->
        trace
          Validation_errors.Cannot_serialize_operation_metadata
          (fail (Exn exn))
    in
    let*! (ops_metadata_hashes, block_metadata_hash) =
      match new_protocol_env_version with
      | Protocol.V0 -> Lwt.return (None, None)
      | Protocol.(V1 | V2 | V3 | V4 | V5) ->
          Lwt.return
            ( Some
                (List.map
                   (List.map (fun r -> Operation_metadata_hash.hash_bytes [r]))
                   ops_metadata),
              Some (Block_metadata_hash.hash_bytes [block_metadata]) )
    in
    let max_operations_ttl =
      max
        0
        (min
           (predecessor_max_operations_ttl + 1)
           validation_result.max_operations_ttl)
    in
    let result =
      let validation_store =
        {
          context_hash;
          timestamp;
          message = validation_result.message;
          max_operations_ttl;
          last_allowed_fork_level = validation_result.last_allowed_fork_level;
        }
      in
      let result =
        {
          validation_store;
          block_metadata;
          ops_metadata;
          block_metadata_hash;
          ops_metadata_hashes;
        }
      in
      {result; cache}
    in
    return (preapply_result, (result, context))

  let precheck block_hash chain_id ~(predecessor_block_header : Block_header.t)
      ~predecessor_block_hash ~predecessor_context ~cache
      ~(block_header : Block_header.t) operations =
    let open Lwt_tzresult_syntax in
    let* () =
      check_block_header ~predecessor_block_header block_hash block_header
    in
    let* block_header = parse_block_header block_hash block_header in
    let* () = check_operation_quota block_hash operations in
    let*! context =
      update_testchain_status
        predecessor_context
        ~predecessor_hash:predecessor_block_hash
        block_header.shell.timestamp
    in
    let* operations = parse_operations block_hash operations in
    let context = Shell_context.wrap_disk_context context in
    let* state =
      Proto.begin_partial_application
        ~chain_id
        ~ancestor_context:context
        ~predecessor:predecessor_block_header
        ~predecessor_hash:predecessor_block_hash
        ~cache
        block_header
    in
    let* state =
      List.fold_left_es
        (fun state ops ->
          List.fold_left_es
            (fun state op ->
              let* (state, _op_metadata) = Proto.apply_operation state op in
              return state)
            state
            ops)
        state
        operations
    in
    let* (_validation_result, _block_data) = Proto.finalize_block state None in
    return_unit

  let precheck chain_id ~(predecessor_block_header : Block_header.t)
      ~predecessor_block_hash ~predecessor_context ~cache
      ~(block_header : Block_header.t) operations =
    let open Lwt_syntax in
    let block_hash = Block_header.hash block_header in
    let* r =
      precheck
        block_hash
        chain_id
        ~predecessor_block_header
        ~predecessor_block_hash
        ~predecessor_context
        ~cache
        ~block_header
        operations
    in
    match r with
    | Error err ->
        Error_monad.fail
          (invalid_block block_hash (Economic_protocol_error err))
    | Ok () -> return_ok_unit
end

let assert_no_duplicate_operations block_hash live_operations operations =
  let exception Duplicate of block_error in
  try
    ok
      (List.fold_left
         (List.fold_left (fun live_operations op ->
              let oph = Operation.hash op in
              if Operation_hash.Set.mem oph live_operations then
                raise (Duplicate (Replayed_operation oph))
              else Operation_hash.Set.add oph live_operations))
         live_operations
         operations)
  with Duplicate err -> error (invalid_block block_hash err)

let assert_operation_liveness block_hash live_blocks operations =
  let exception Outdated of block_error in
  try
    ok
      (List.iter
         (List.iter (fun op ->
              if not (Block_hash.Set.mem op.Operation.shell.branch live_blocks)
              then
                let error =
                  Outdated_operation
                    {
                      operation = Operation.hash op;
                      originating_block = op.shell.branch;
                    }
                in
                raise (Outdated error)))
         operations)
  with Outdated err -> error (invalid_block block_hash err)

(* Maybe this function should be moved somewhere else since it used
   once by [Block_validator_process] *)
let check_liveness ~live_blocks ~live_operations block_hash operations =
  let open Result_syntax in
  let* (_ : Operation_hash.Set.t) =
    assert_no_duplicate_operations block_hash live_operations operations
  in
  assert_operation_liveness block_hash live_blocks operations

type apply_environment = {
  max_operations_ttl : int;
  chain_id : Chain_id.t;
  predecessor_block_header : Block_header.t;
  predecessor_context : Context.t;
  predecessor_block_metadata_hash : Block_metadata_hash.t option;
  predecessor_ops_metadata_hash : Operation_metadata_list_list_hash.t option;
  user_activated_upgrades : User_activated.upgrades;
  user_activated_protocol_overrides : User_activated.protocol_overrides;
}

let apply ?cached_result
    {
      chain_id;
      user_activated_upgrades;
      user_activated_protocol_overrides;
      max_operations_ttl;
      predecessor_block_header;
      predecessor_block_metadata_hash;
      predecessor_ops_metadata_hash;
      predecessor_context;
    } ~cache block_hash block_header operations =
  let open Lwt_tzresult_syntax in
  let*! pred_protocol_hash = Context.get_protocol predecessor_context in
  let* (module Proto) =
    match Registered_protocol.get pred_protocol_hash with
    | None ->
        fail
          (Unavailable_protocol
             {block = block_hash; protocol = pred_protocol_hash})
    | Some p -> return p
  in
  let module Block_validation = Make (Proto) in
  Block_validation.apply
    ?cached_result
    chain_id
    ~user_activated_upgrades
    ~user_activated_protocol_overrides
    ~max_operations_ttl
    ~predecessor_block_header
    ~predecessor_block_metadata_hash
    ~predecessor_ops_metadata_hash
    ~predecessor_context
    ~cache
    ~block_header
    operations

let apply ?cached_result c ~cache block_header operations =
  let open Lwt_tzresult_syntax in
  let block_hash = Block_header.hash block_header in
  let*! r =
    (* The cache might be inconsistent with the context. By forcing
       the reloading of the cache, we restore the consistency. *)
    let*! r =
      apply ?cached_result c ~cache block_hash block_header operations
    in
    match r with
    | Error (Validation_errors.Inconsistent_hash _ :: _) ->
        let*! protocol_hash = Context.get_protocol c.predecessor_context in
        let hanghzhou_hash =
          Protocol_hash.of_b58check_exn
            "PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx"
        in
        if protocol_hash = hanghzhou_hash then (
          Environment_context.Context
          .reset_cache_cache_hangzhou_issue_do_not_use_except_if_you_know_what_you_are_doing
            () ;
          Lwt.return r)
        else
          let*! () = Event.(emit inherited_inconsistent_cache) block_hash in
          apply
            ?cached_result
            c
            ~cache:`Force_load
            block_hash
            block_header
            operations
    | (Ok _ | Error _) as res -> Lwt.return res
  in
  match r with
  | Error (Exn (Unix.Unix_error (errno, fn, msg)) :: _) ->
      Error_monad.fail
        (System_error {errno = Unix.error_message errno; fn; msg})
  | (Ok _ | Error _) as res -> Lwt.return res

let precheck ~chain_id ~predecessor_block_header ~predecessor_block_hash
    ~predecessor_context ~cache block_header operations =
  let open Lwt_tzresult_syntax in
  let block_hash = Block_header.hash block_header in
  let*! pred_protocol_hash = Context.get_protocol predecessor_context in
  let* (module Proto) =
    match Registered_protocol.get pred_protocol_hash with
    | None ->
        fail
          (Unavailable_protocol
             {block = block_hash; protocol = pred_protocol_hash})
    | Some p -> return p
  in
  let module Block_validation = Make (Proto) in
  Block_validation.precheck
    chain_id
    ~predecessor_block_header
    ~predecessor_block_hash
    ~predecessor_context
    ~cache
    ~block_header
    operations

let preapply ~chain_id ~user_activated_upgrades
    ~user_activated_protocol_overrides ~timestamp ~protocol_data ~live_blocks
    ~live_operations ~predecessor_context ~predecessor_shell_header
    ~predecessor_hash ~predecessor_max_operations_ttl
    ~predecessor_block_metadata_hash ~predecessor_ops_metadata_hash operations =
  let open Lwt_tzresult_syntax in
  let*! protocol = Context.get_protocol predecessor_context in
  let* (module Proto) =
    match Registered_protocol.get protocol with
    | None ->
        (* FIXME: https://gitlab.com/tezos/tezos/-/issues/1718 *)
        (* This should not happen: it should be handled in the validator. *)
        failwith
          "Prevalidation: missing protocol '%a' for the current block."
          Protocol_hash.pp_short
          protocol
    | Some protocol -> return protocol
  in
  (* The cache might be inconsistent with the context. By forcing the
     reloading of the cache, we restore the consistency. *)
  let module Block_validation = Make (Proto) in
  let* protocol_data =
    match
      Data_encoding.Binary.of_bytes_opt
        Proto.block_header_data_encoding
        protocol_data
    with
    | None -> failwith "Invalid block header"
    | Some protocol_data -> return protocol_data
  in
  Block_validation.preapply
    ~chain_id
    ~cache:`Force_load
    ~user_activated_upgrades
    ~user_activated_protocol_overrides
    ~protocol_data
    ~live_blocks
    ~live_operations
    ~timestamp
    ~predecessor_context
    ~predecessor_shell_header
    ~predecessor_hash
    ~predecessor_max_operations_ttl
    ~predecessor_block_metadata_hash
    ~predecessor_ops_metadata_hash
    ~operations

let preapply ~chain_id ~user_activated_upgrades
    ~user_activated_protocol_overrides ~timestamp ~protocol_data ~live_blocks
    ~live_operations ~predecessor_context ~predecessor_shell_header
    ~predecessor_hash ~predecessor_max_operations_ttl
    ~predecessor_block_metadata_hash ~predecessor_ops_metadata_hash operations =
  let open Lwt_syntax in
  let* r =
    preapply
      ~chain_id
      ~user_activated_upgrades
      ~user_activated_protocol_overrides
      ~timestamp
      ~protocol_data
      ~live_blocks
      ~live_operations
      ~predecessor_context
      ~predecessor_shell_header
      ~predecessor_hash
      ~predecessor_max_operations_ttl
      ~predecessor_block_metadata_hash
      ~predecessor_ops_metadata_hash
      operations
  in
  match r with
  | Error (Exn (Unix.Unix_error (errno, fn, msg)) :: _) ->
      Error_monad.fail
        (System_error {errno = Unix.error_message errno; fn; msg})
  | (Ok _ | Error _) as res -> Lwt.return res
