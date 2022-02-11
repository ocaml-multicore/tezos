(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

(** Manages all the voting related storage in Storage.Vote.  *)

(** Records a protocol proposal with the delegate that proposed it. *)
val record_proposal :
  Raw_context.t ->
  Protocol_hash.t ->
  Signature.Public_key_hash.t ->
  Raw_context.t tzresult Lwt.t

val recorded_proposal_count_for_delegate :
  Raw_context.t -> Signature.Public_key_hash.t -> int tzresult Lwt.t

(** Computes for each proposal how many delegates proposed it. *)
val get_proposals : Raw_context.t -> int32 Protocol_hash.Map.t tzresult Lwt.t

val clear_proposals : Raw_context.t -> Raw_context.t Lwt.t

(** Counts of the votes *)
type ballots = {yay : int32; nay : int32; pass : int32}

val ballots_encoding : ballots Data_encoding.t

val has_recorded_ballot :
  Raw_context.t -> Signature.Public_key_hash.t -> bool Lwt.t

(** Records a vote for a delegate, returns a {!Storage_error Existing_key} if
    the vote was already registered *)
val record_ballot :
  Raw_context.t ->
  Signature.Public_key_hash.t ->
  Vote_repr.ballot ->
  Raw_context.t tzresult Lwt.t

(** Computes the sum of the current ballots weighted by stake. *)
val get_ballots : Raw_context.t -> ballots tzresult Lwt.t

val get_ballot_list :
  Raw_context.t -> (Signature.Public_key_hash.t * Vote_repr.ballot) list Lwt.t

val clear_ballots : Raw_context.t -> Raw_context.t Lwt.t

val listings_encoding :
  (Signature.Public_key_hash.t * int32) list Data_encoding.t

(** Populates [!Storage.Vote.Listings] using the currently existing rolls and
    sets Listings_size. Delegates without rolls are not included in the listing. *)
val update_listings : Raw_context.t -> Raw_context.t tzresult Lwt.t

(** Returns the sum of all rolls of all delegates. *)
val listing_size : Raw_context.t -> int32 tzresult Lwt.t

(** Verifies the presence of a delegate in the listing. *)
val in_listings : Raw_context.t -> Signature.Public_key_hash.t -> bool Lwt.t

val get_listings :
  Raw_context.t -> (Signature.Public_key_hash.t * int32) list Lwt.t

val get_voting_power_free :
  Raw_context.t -> Signature.public_key_hash -> int32 tzresult Lwt.t

val get_voting_power :
  Raw_context.t ->
  Signature.public_key_hash ->
  (Raw_context.t * int32) tzresult Lwt.t

val get_total_voting_power_free : Raw_context.t -> int32 tzresult Lwt.t

val get_total_voting_power :
  Raw_context.t -> (Raw_context.t * int32) tzresult Lwt.t

val get_current_quorum : Raw_context.t -> int32 tzresult Lwt.t

val get_participation_ema : Raw_context.t -> int32 tzresult Lwt.t

val set_participation_ema :
  Raw_context.t -> int32 -> Raw_context.t tzresult Lwt.t

val get_current_proposal : Raw_context.t -> Protocol_hash.t tzresult Lwt.t

val find_current_proposal :
  Raw_context.t -> Protocol_hash.t option tzresult Lwt.t

val init_current_proposal :
  Raw_context.t -> Protocol_hash.t -> Raw_context.t tzresult Lwt.t

val clear_current_proposal : Raw_context.t -> Raw_context.t tzresult Lwt.t

(** Sets the initial quorum to 80% and period kind to proposal. *)
val init :
  Raw_context.t -> start_position:Int32.t -> Raw_context.t tzresult Lwt.t
