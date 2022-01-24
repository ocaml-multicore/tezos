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

(** Tezos Protocol Implementation - Protocol Signature Instance

    This module is the  entrypoint to the protocol for shells and other
    embedders.  This signature is an instance of
    {{!Tezos_protocol_environment_sigs.V3.T.Updater.PROTOCOL} the
    [Updater.PROTOCOL] signature} from the
    {{:https://tezos.gitlab.io/shell/the_big_picture.html#the-economic-protocol-environment-and-compiler}
    Protocol Environment}.

    Each Protocol depends on a version of the Protocol Environment. For the
    currently developed protocol, this is normally the latest version.  You can
    see {{!Tezos_protocol_environment_sigs} the full list of versions here}.

    For details on how Protocol and Environment interact, see
    {{:https://tezos.gitlab.io/shell/the_big_picture.html} this overview}.
 *)

type validation_mode =
  | Application of {
      block_header : Alpha_context.Block_header.t;
      fitness : Alpha_context.Fitness.t;
      payload_producer : Alpha_context.public_key_hash;
      block_producer : Alpha_context.public_key_hash;
      predecessor_round : Alpha_context.Round.t;
      predecessor_level : Alpha_context.Level.t;
    }
  | Partial_application of {
      block_header : Alpha_context.Block_header.t;
      fitness : Alpha_context.Fitness.t;
      payload_producer : Alpha_context.public_key_hash;
      block_producer : Alpha_context.public_key_hash;
      predecessor_level : Alpha_context.Level.t;
      predecessor_round : Alpha_context.Round.t;
    }
  (* Mempool only *)
  | Partial_construction of {
      predecessor : Block_hash.t;
      predecessor_fitness : Fitness.t;
      predecessor_level : Alpha_context.Level.t;
      predecessor_round : Alpha_context.Round.t;
    }
  (* Baker only *)
  | Full_construction of {
      predecessor : Block_hash.t;
      payload_producer : Alpha_context.public_key_hash;
      block_producer : Alpha_context.public_key_hash;
      protocol_data_contents : Alpha_context.Block_header.contents;
      level : Int32.t;
      round : Alpha_context.Round.t;
      predecessor_level : Alpha_context.Level.t;
      predecessor_round : Alpha_context.Round.t;
    }

type validation_state = {
  mode : validation_mode;
  chain_id : Chain_id.t;
  ctxt : Alpha_context.t;
  op_count : int;
  migration_balance_updates : Alpha_context.Receipt.balance_updates;
  liquidity_baking_escape_ema : Int32.t;
  implicit_operations_results :
    Apply_results.packed_successful_manager_operation_result list;
}

type operation_data = Alpha_context.packed_protocol_data

type operation = Alpha_context.packed_operation = {
  shell : Operation.shell_header;
  protocol_data : operation_data;
}

val init_cache : Context.t -> Context.t Lwt.t

(** [check_manager_signature validation_state op raw_operation]
    The function starts by retrieving the public key hash [pkh] of the manager
    operation. In case the operation is batched, the function also checks that
    the sources are all the same.
    Once the [pkh] is retrieved, the function looks for its associated public
    key. For that, the manager operation is inspected to check if it contains
    a public key revelation. If not, the public key is searched in the context.

    @return [Error Invalid_signature] if the signature check fails
    @return [Error Unrevealed_manager_key] if the manager has not yet been
    revealed
    @return [Error Failure "get_manager_key"] if the key is not found in the
    context
    @return [Error Inconsistent_sources] if the operations in a batch are not
    from the same manager *)
val check_manager_signature :
  validation_state ->
  'b Alpha_context.Kind.manager Alpha_context.contents_list ->
  'a Alpha_context.operation ->
  unit tzresult Lwt.t

(** [precheck_manager validation_state op] returns [()] if the manager operation
    [op] is solveable, returns an error otherwise. An operation is solveable if
    it is well-formed and can pay the fees to be included in a block with either
    a success or a failure status.
    This function uses [Apply.precheck_manager_contents_list] but discard the
    context and balance update *)
val precheck_manager :
  validation_state ->
  'a Alpha_context.Kind.manager Alpha_context.contents_list ->
  unit tzresult Lwt.t

include
  Updater.PROTOCOL
    with type block_header_data = Alpha_context.Block_header.protocol_data
     and type block_header_metadata = Apply_results.block_metadata
     and type block_header = Alpha_context.Block_header.t
     and type operation_data := operation_data
     and type operation_receipt = Apply_results.packed_operation_metadata
     and type operation := operation
     and type validation_state := validation_state
