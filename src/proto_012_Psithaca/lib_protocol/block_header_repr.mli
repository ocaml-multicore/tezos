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

(** Representation of block headers. *)

type contents = {
  payload_hash : Block_payload_hash.t;
  payload_round : Round_repr.t;
  seed_nonce_hash : Nonce_hash.t option;
  proof_of_work_nonce : bytes;
  liquidity_baking_escape_vote : bool;
      (* set by baker to vote in favor of permanently disabling liquidity baking *)
}

type protocol_data = {contents : contents; signature : Signature.t}

type t = {shell : Block_header.shell_header; protocol_data : protocol_data}

type block_header = t

type raw = Block_header.t

type shell_header = Block_header.shell_header

val raw : block_header -> raw

val encoding : block_header Data_encoding.encoding

val raw_encoding : raw Data_encoding.t

val contents_encoding : contents Data_encoding.t

val unsigned_encoding : (Block_header.shell_header * contents) Data_encoding.t

val protocol_data_encoding : protocol_data Data_encoding.encoding

val shell_header_encoding : shell_header Data_encoding.encoding

type block_watermark = Block_header of Chain_id.t

val to_watermark : block_watermark -> Signature.watermark

val of_watermark : Signature.watermark -> block_watermark option

(** The maximum size of block headers in bytes *)
val max_header_length : int

val hash : block_header -> Block_hash.t

val hash_raw : raw -> Block_hash.t

type error +=
  | (* Permanent *)
      Invalid_block_signature of
      Block_hash.t * Signature.Public_key_hash.t
  | (* Permanent *) Invalid_stamp
  | (* Permanent *)
      Invalid_payload_hash of {
      expected : Block_payload_hash.t;
      provided : Block_payload_hash.t;
    }
  | (* Permanent *)
      Locked_round_after_block_round of {
      locked_round : Round_repr.t;
      round : Round_repr.t;
    }
  | (* Permanent *)
      Invalid_payload_round of {
      payload_round : Round_repr.t;
      round : Round_repr.t;
    }
  | (* Permanent *)
      Insufficient_locked_round_evidence of {
      voting_power : int;
      consensus_threshold : int;
    }
  | (* Permanent *) Invalid_commitment of {expected : bool}

(** Checks if the header that would be built from the given components
   is valid for the given difficulty. The signature is not passed as
   it is does not impact the proof-of-work stamp. The stamp is checked
   on the hash of a block header whose signature has been
   zeroed-out. *)
module Proof_of_work : sig
  val check_hash : Block_hash.t -> int64 -> bool

  val check_header_proof_of_work_stamp :
    shell_header -> contents -> int64 -> bool

  val check_proof_of_work_stamp :
    proof_of_work_threshold:int64 -> block_header -> unit tzresult
end

(** [check_timestamp ctxt timestamp round predecessor_timestamp
   predecessor_round] verifies that the block's timestamp and round
   are coherent with the predecessor block's timestamp and
   round. Fails with an error if that is not the case. *)
val check_timestamp :
  Round_repr.Durations.t ->
  timestamp:Time.t ->
  round:Round_repr.t ->
  predecessor_timestamp:Time.t ->
  predecessor_round:Round_repr.t ->
  unit tzresult

val check_signature : t -> Chain_id.t -> Signature.Public_key.t -> unit tzresult

val begin_validate_block_header :
  block_header:t ->
  chain_id:Chain_id.t ->
  predecessor_timestamp:Time.t ->
  predecessor_round:Round_repr.t ->
  fitness:Fitness_repr.t ->
  timestamp:Time.t ->
  delegate_pk:Signature.public_key ->
  round_durations:Round_repr.Durations.t ->
  proof_of_work_threshold:int64 ->
  expected_commitment:bool ->
  unit tzresult

type locked_round_evidence = {
  preendorsement_round : Round_repr.t;
  preendorsement_count : int;
}

type checkable_payload_hash =
  | No_check
  | Expected_payload_hash of Block_payload_hash.t

val finalize_validate_block_header :
  block_header_contents:contents ->
  round:Round_repr.t ->
  fitness:Fitness_repr.t ->
  checkable_payload_hash:checkable_payload_hash ->
  locked_round_evidence:locked_round_evidence option ->
  consensus_threshold:int ->
  unit tzresult
