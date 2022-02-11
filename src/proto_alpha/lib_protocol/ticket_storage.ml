(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Trili Tech, <contact@trili.tech>                       *)
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

type error +=
  | Negative_ticket_balance of {key : Ticket_hash_repr.t; balance : Z.t}

let () =
  let open Data_encoding in
  register_error_kind
    `Permanent
    ~id:"Negative_ticket_balance"
    ~title:"Negative ticket balance"
    ~description:"Attempted to set a negative ticket balance value"
    ~pp:(fun ppf (key, balance) ->
      Format.fprintf
        ppf
        "Attempted to set negative ticket balance value '%a' for key %a."
        Z.pp_print
        balance
        Ticket_hash_repr.pp
        key)
    (obj2 (req "key" Ticket_hash_repr.encoding) (req "balance" Data_encoding.z))
    (function
      | Negative_ticket_balance {key; balance} -> Some (key, balance)
      | _ -> None)
    (fun (key, balance) -> Negative_ticket_balance {key; balance})

let get_balance ctxt key =
  Storage.Ticket_balance.Table.find ctxt key >|=? fun (ctxt, res) -> (res, ctxt)

let set_balance ctxt key balance =
  let cost_of_key = Z.of_int 65 in
  fail_when
    Compare.Z.(balance < Z.zero)
    (Negative_ticket_balance {key; balance})
  >>=? fun () ->
  if Compare.Z.(balance = Z.zero) then
    Storage.Ticket_balance.Table.remove ctxt key
    >|=? fun (ctxt, freed, existed) ->
    (* If we remove an existing entry, then we return the freed size for
       both the key and the value. *)
    let freed =
      if existed then Z.neg @@ Z.add cost_of_key (Z.of_int freed) else Z.zero
    in
    (freed, ctxt)
  else
    Storage.Ticket_balance.Table.add ctxt key balance
    >|=? fun (ctxt, size_diff, existed) ->
    let size_diff =
      let z_diff = Z.of_int size_diff in
      (* For a new entry we also charge the space for storing the key *)
      if existed then z_diff else Z.add cost_of_key z_diff
    in
    (size_diff, ctxt)

let adjust_balance ctxt key ~delta =
  get_balance ctxt key >>=? fun (res, ctxt) ->
  let old_balance = Option.value ~default:Z.zero res in
  set_balance ctxt key (Z.add old_balance delta)
