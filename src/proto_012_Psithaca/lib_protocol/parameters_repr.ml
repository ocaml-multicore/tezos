(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

type bootstrap_account = {
  public_key_hash : Signature.Public_key_hash.t;
  public_key : Signature.Public_key.t option;
  amount : Tez_repr.t;
}

type bootstrap_contract = {
  delegate : Signature.Public_key_hash.t option;
  amount : Tez_repr.t;
  script : Script_repr.t;
}

type t = {
  bootstrap_accounts : bootstrap_account list;
  bootstrap_contracts : bootstrap_contract list;
  commitments : Commitment_repr.t list;
  constants : Constants_repr.parametric;
  security_deposit_ramp_up_cycles : int option;
  no_reward_cycles : int option;
}

let bootstrap_account_encoding =
  let open Data_encoding in
  union
    [
      case
        (Tag 0)
        ~title:"Public_key_known"
        (tup2 Signature.Public_key.encoding Tez_repr.encoding)
        (function
          | {public_key_hash; public_key = Some public_key; amount} ->
              assert (
                Signature.Public_key_hash.equal
                  (Signature.Public_key.hash public_key)
                  public_key_hash) ;
              Some (public_key, amount)
          | {public_key = None; _} -> None)
        (fun (public_key, amount) ->
          {
            public_key = Some public_key;
            public_key_hash = Signature.Public_key.hash public_key;
            amount;
          });
      case
        (Tag 1)
        ~title:"Public_key_unknown"
        (tup2 Signature.Public_key_hash.encoding Tez_repr.encoding)
        (function
          | {public_key_hash; public_key = None; amount} ->
              Some (public_key_hash, amount)
          | {public_key = Some _; _} -> None)
        (fun (public_key_hash, amount) ->
          {public_key = None; public_key_hash; amount});
    ]

let bootstrap_contract_encoding =
  let open Data_encoding in
  conv
    (fun {delegate; amount; script} -> (delegate, amount, script))
    (fun (delegate, amount, script) -> {delegate; amount; script})
    (obj3
       (opt "delegate" Signature.Public_key_hash.encoding)
       (req "amount" Tez_repr.encoding)
       (req "script" Script_repr.encoding))

let encoding =
  let open Data_encoding in
  conv
    (fun {
           bootstrap_accounts;
           bootstrap_contracts;
           commitments;
           constants;
           security_deposit_ramp_up_cycles;
           no_reward_cycles;
         } ->
      ( ( bootstrap_accounts,
          bootstrap_contracts,
          commitments,
          security_deposit_ramp_up_cycles,
          no_reward_cycles ),
        constants ))
    (fun ( ( bootstrap_accounts,
             bootstrap_contracts,
             commitments,
             security_deposit_ramp_up_cycles,
             no_reward_cycles ),
           constants ) ->
      {
        bootstrap_accounts;
        bootstrap_contracts;
        commitments;
        constants;
        security_deposit_ramp_up_cycles;
        no_reward_cycles;
      })
    (merge_objs
       (obj5
          (req "bootstrap_accounts" (list bootstrap_account_encoding))
          (dft "bootstrap_contracts" (list bootstrap_contract_encoding) [])
          (dft "commitments" (list Commitment_repr.encoding) [])
          (opt "security_deposit_ramp_up_cycles" int31)
          (opt "no_reward_cycles" int31))
       Constants_repr.parametric_encoding)

let check_params params = Constants_repr.check_constants params.constants
