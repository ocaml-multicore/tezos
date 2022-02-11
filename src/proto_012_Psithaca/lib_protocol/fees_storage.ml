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

type error += Cannot_pay_storage_fee (* `Temporary *)

type error += Operation_quota_exceeded (* `Temporary *)

type error += Storage_limit_too_high (* `Permanent *)

let () =
  let open Data_encoding in
  register_error_kind
    `Temporary
    ~id:"contract.cannot_pay_storage_fee"
    ~title:"Cannot pay storage fee"
    ~description:"The storage fee is higher than the contract balance"
    ~pp:(fun ppf () -> Format.fprintf ppf "Cannot pay storage storage fee")
    Data_encoding.empty
    (function Cannot_pay_storage_fee -> Some () | _ -> None)
    (fun () -> Cannot_pay_storage_fee) ;
  register_error_kind
    `Temporary
    ~id:"storage_exhausted.operation"
    ~title:"Storage quota exceeded for the operation"
    ~description:
      "A script or one of its callee wrote more bytes than the operation said \
       it would"
    Data_encoding.empty
    (function Operation_quota_exceeded -> Some () | _ -> None)
    (fun () -> Operation_quota_exceeded) ;
  register_error_kind
    `Permanent
    ~id:"storage_limit_too_high"
    ~title:"Storage limit out of protocol hard bounds"
    ~description:"A transaction tried to exceed the hard limit on storage"
    empty
    (function Storage_limit_too_high -> Some () | _ -> None)
    (fun () -> Storage_limit_too_high)

let record_global_constant_storage_space context size =
  (* Following the precedent of big_map, a key in the
     global table of constants costs 65 bytes (see
     [Lazy_storage_diff.Big_map.bytes_size_for_big_map_key])*)
  let cost_of_key = Z.of_int 65 in
  let to_be_paid = Z.add size cost_of_key in
  (context, to_be_paid)

let record_paid_storage_space c contract =
  Contract_storage.used_storage_space c contract >>=? fun size ->
  Contract_storage.set_paid_storage_space_and_return_fees_to_pay c contract size
  >>=? fun (to_be_paid, c) -> return (c, size, to_be_paid)

let source_must_exist c src =
  match src with
  | `Contract src -> Contract_storage.must_exist c src
  | _ -> return_unit

let burn_storage_fees ?(origin = Receipt_repr.Block_application) c
    ~storage_limit ~payer consumed =
  let remaining = Z.sub storage_limit consumed in
  if Compare.Z.(remaining < Z.zero) then fail Operation_quota_exceeded
  else
    let cost_per_byte = Constants_storage.cost_per_byte c in
    Tez_repr.(cost_per_byte *? Z.to_int64 consumed) >>?= fun to_burn ->
    (* Burning the fees... *)
    if Tez_repr.(to_burn = Tez_repr.zero) then
      (* If the payer was deleted by transferring all its balance, and no space
         was used, burning zero would fail *)
      return (c, remaining, [])
    else
      trace
        Cannot_pay_storage_fee
        ( source_must_exist c payer >>=? fun () ->
          Token.transfer ~origin c payer `Storage_fees to_burn
          >>=? fun (ctxt, balance_updates) ->
          return (ctxt, remaining, balance_updates) )

let burn_origination_fees ?(origin = Receipt_repr.Block_application) c
    ~storage_limit ~payer =
  let origination_size = Constants_storage.origination_size c in
  burn_storage_fees ~origin c ~storage_limit ~payer (Z.of_int origination_size)

let check_storage_limit c ~storage_limit =
  if
    Compare.Z.(
      storage_limit > (Raw_context.constants c).hard_storage_limit_per_operation)
    || Compare.Z.(storage_limit < Z.zero)
  then error Storage_limit_too_high
  else Result.return_unit
