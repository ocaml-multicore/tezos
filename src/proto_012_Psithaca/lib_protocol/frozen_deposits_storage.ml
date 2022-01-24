(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
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

let init ctxt delegate =
  Storage.Contract.Frozen_deposits.init
    ctxt
    (Contract_repr.implicit_contract delegate)
    {initial_amount = Tez_repr.zero; current_amount = Tez_repr.zero}

let allocated = Storage.Contract.Frozen_deposits.mem

let get = Storage.Contract.Frozen_deposits.get

let find = Storage.Contract.Frozen_deposits.find

let update_balance ctxt delegate f amount =
  let delegate_contract = Contract_repr.implicit_contract delegate in
  Storage.Contract.Frozen_deposits.get ctxt delegate_contract
  >>=? fun frozen_deposits ->
  f frozen_deposits.current_amount amount >>?= fun new_amount ->
  Storage.Contract.Frozen_deposits.update
    ctxt
    delegate_contract
    {frozen_deposits with current_amount = new_amount}

let credit_only_call_from_token ctxt delegate amount =
  update_balance ctxt delegate Tez_repr.( +? ) amount

let spend_only_call_from_token ctxt delegate amount =
  update_balance ctxt delegate Tez_repr.( -? ) amount

let update_deposits_cap ctxt delegate_contract deposits_cap =
  Storage.Contract.Frozen_deposits.get ctxt delegate_contract
  >>=? fun frozen_deposits ->
  Storage.Contract.Frozen_deposits.update
    ctxt
    delegate_contract
    {frozen_deposits with initial_amount = deposits_cap}
  >|=? fun ctxt -> (ctxt, frozen_deposits.current_amount)
