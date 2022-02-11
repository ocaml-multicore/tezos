(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Alpha_context

val list :
  'a #RPC_context.simple ->
  'a ->
  ?active:bool ->
  ?inactive:bool ->
  unit ->
  Signature.Public_key_hash.t list shell_tzresult Lwt.t

type info = {
  full_balance : Tez.t;  (** Balance + Frozen balance *)
  current_frozen_deposits : Tez.t;
  frozen_deposits : Tez.t;
  staking_balance : Tez.t;
  frozen_deposits_limit : Tez.t option;
  delegated_contracts : Contract.t list;
  delegated_balance : Tez.t;
  deactivated : bool;
  grace_period : Cycle.t;
  voting_power : int32;
}

val info_encoding : info Data_encoding.t

val info :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  info shell_tzresult Lwt.t

val full_balance :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t shell_tzresult Lwt.t

val current_frozen_deposits :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t shell_tzresult Lwt.t

val frozen_deposits :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t shell_tzresult Lwt.t

val staking_balance :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t shell_tzresult Lwt.t

val frozen_deposits_limit :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t option shell_tzresult Lwt.t

val delegated_contracts :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Contract.t list shell_tzresult Lwt.t

val delegated_balance :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Tez.t shell_tzresult Lwt.t

val deactivated :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  bool shell_tzresult Lwt.t

val grace_period :
  'a #RPC_context.simple ->
  'a ->
  Signature.Public_key_hash.t ->
  Cycle.t shell_tzresult Lwt.t

val voting_power :
  'a #RPC_context.simple -> 'a -> public_key_hash -> int32 shell_tzresult Lwt.t

val participation :
  'a #RPC_context.simple ->
  'a ->
  public_key_hash ->
  Delegate.participation_info shell_tzresult Lwt.t

val register : unit -> unit
