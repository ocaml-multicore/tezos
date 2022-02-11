(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
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

let is_inactive ctxt delegate =
  Storage.Contract.Inactive_delegate.mem
    ctxt
    (Contract_repr.implicit_contract delegate)
  >>= fun inactive ->
  if inactive then return inactive
  else
    Storage.Contract.Delegate_desactivation.find
      ctxt
      (Contract_repr.implicit_contract delegate)
    >|=? function
    | Some last_active_cycle ->
        let ({Level_repr.cycle = current_cycle; _} : Level_repr.t) =
          Raw_context.current_level ctxt
        in
        Cycle_repr.(last_active_cycle < current_cycle)
    | None ->
        (* This case is only when called from `set_active`, when creating
             a contract. *)
        false

let grace_period ctxt delegate =
  let contract = Contract_repr.implicit_contract delegate in
  Storage.Contract.Delegate_desactivation.get ctxt contract

let set_inactive = Storage.Contract.Inactive_delegate.add

let set_active ctxt delegate =
  is_inactive ctxt delegate >>=? fun inactive ->
  let current_cycle = (Raw_context.current_level ctxt).cycle in
  let preserved_cycles = Constants_storage.preserved_cycles ctxt in
  (* We allow a number of cycles before a delegate is deactivated as follows:
     - if the delegate is active, we give it at least `1 + preserved_cycles`
     after the current cycle before to be deactivated.
     - if the delegate is new or inactive, we give it additionally
     `preserved_cycles` because the delegate needs this number of cycles to
     receive rights, so `1 + 2 * preserved_cycles` in total. *)
  Storage.Contract.Delegate_desactivation.find
    ctxt
    (Contract_repr.implicit_contract delegate)
  >>=? fun current_last_active_cycle ->
  let last_active_cycle =
    match current_last_active_cycle with
    | None -> Cycle_repr.add current_cycle (1 + (2 * preserved_cycles))
    | Some current_last_active_cycle ->
        let delay =
          if inactive then 1 + (2 * preserved_cycles) else 1 + preserved_cycles
        in
        let updated = Cycle_repr.add current_cycle delay in
        Cycle_repr.max current_last_active_cycle updated
  in
  Storage.Contract.Delegate_desactivation.add
    ctxt
    (Contract_repr.implicit_contract delegate)
    last_active_cycle
  >>= fun ctxt ->
  if not inactive then return (ctxt, inactive)
  else
    Storage.Contract.Inactive_delegate.remove
      ctxt
      (Contract_repr.implicit_contract delegate)
    >>= fun ctxt -> return (ctxt, inactive)
