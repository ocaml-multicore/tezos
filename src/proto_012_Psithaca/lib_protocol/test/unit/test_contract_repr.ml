(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
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

(** Testing
    -------
    Component:    Contract_repr
    Invocation:   dune exec ./src/proto_alpha/lib_protocol/test/unit/main.exe -- test Contract_repr 
    Dependencies: contract_hash.ml
    Subject:      To test the modules (including the top-level)
                  in contract_repr.ml as individual units, particularly
                  failure cases. Superficial goal: increase coverage percentage.
*)
open Protocol

open Tztest

(*

  TODO: Remove dependence on contract_hash.ml and mock it

 *)

module Test_contract_repr = struct
  (** Assert if [is_implicit] correctly returns the implicit contract *)
  open Contract_repr

  let dummy_operation_hash =
    Operation_hash.of_bytes_exn
      (Bytes.of_string "test-operation-hash-of-length-32")

  let dummy_origination_nonce = initial_origination_nonce dummy_operation_hash

  let dummy_contract_hash =
    (* WARNING: Uses Contract_repr itself, which is yet to be tested. This happened because Contract_hash wasn't mocked *)
    let data =
      Data_encoding.Binary.to_bytes_exn
        Contract_repr.origination_nonce_encoding
        dummy_origination_nonce
    in
    Contract_hash.hash_bytes [data]

  let dummy_implicit_contract = implicit_contract Signature.Public_key_hash.zero

  let dummy_originated_contract = originated_contract @@ dummy_origination_nonce

  let test_implicit () =
    match is_implicit dummy_implicit_contract with
    | Some _ -> return_unit
    | None ->
        failwith
          "must have returned the public key hash of implicit contract. \n\
          \           Instead, returned None"

  (** Check if [is_implicit] catches a non-implicit (originated) contract and returns None *)
  let test_not_implicit () =
    match is_implicit dummy_originated_contract with
    | None -> return_unit
    | Some _ -> failwith "must have returned the None. Instead, returned Some _"

  let test_originated () =
    match is_originated dummy_originated_contract with
    | Some _ -> return_unit
    | None ->
        failwith
          "must have returned the origination nonce correctly. Instead \
           returned None."

  let test_not_originated () =
    match is_originated dummy_implicit_contract with
    | None -> return_unit
    | Some _ -> failwith "must have returned the None. Instead, returned Some _"

  let test_to_b58check_implicit () =
    Assert.equal
      ~loc:__LOC__
      String.equal
      "%s should have been equal to %"
      Format.pp_print_string
      (to_b58check dummy_implicit_contract)
      Signature.Public_key_hash.(to_b58check zero)

  let test_to_b58check_originated () =
    Assert.equal
      ~loc:__LOC__
      String.equal
      "%s should have been equal to %"
      Format.pp_print_string
      (to_b58check dummy_originated_contract)
      Contract_hash.(to_b58check @@ dummy_contract_hash)

  let test_originated_contracts_basic () =
    let since = dummy_origination_nonce in
    let rec incr_n_times nonce = function
      | 0 -> nonce
      | n -> incr_n_times (Contract_repr.incr_origination_nonce nonce) (n - 1)
    in
    let until = incr_n_times since 5 in
    let contracts = originated_contracts ~since ~until in
    Assert.equal_int ~loc:__LOC__ (List.length contracts) 5
end

let tests =
  [
    tztest
      "Contract_repr.is_implicit: must correctly identify a valid implicit \
       contract"
      `Quick
      Test_contract_repr.test_implicit;
    tztest
      "Contract_repr.is_implicit: must correctly return None for a originated \
       contract"
      `Quick
      Test_contract_repr.test_not_implicit;
    tztest
      "Contract_repr.is_originated: must correctly return operation hash of \
       the originated contract"
      `Quick
      Test_contract_repr.test_originated;
    tztest
      "Contract_repr.is_originated: must correctly return None for an implicit \
       contract contract"
      `Quick
      Test_contract_repr.test_not_originated;
    tztest
      "Contract_repr.to_b58check: must correctly stringify, b58check encoded, \
       an implicit contract"
      `Quick
      Test_contract_repr.test_to_b58check_implicit;
    tztest
      "Contract_repr.originated_contract: must correctly create an originated \
       contract"
      `Quick
      Test_contract_repr.test_originated_contracts_basic;
    tztest
      "Contract_repr.to_b58check: must correctly stringify, b58check encoded, \
       an originated contract"
      `Quick
      Test_contract_repr.test_to_b58check_originated;
  ]
