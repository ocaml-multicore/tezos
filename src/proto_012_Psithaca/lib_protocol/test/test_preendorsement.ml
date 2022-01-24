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

(** Testing
    -------
    Component:  Protocol (preendorsement)
    Invocation: dune exec src/proto_alpha/lib_protocol/test/main.exe -- test "^preendorsement$"
*)

open Protocol
open Alpha_context

(****************************************************************)
(*                    Utility functions                         *)
(****************************************************************)

let init_genesis ?policy () =
  Context.init ~consensus_threshold:0 5 >>=? fun (genesis, _) ->
  Block.bake ?policy genesis >>=? fun b -> return (genesis, b)

(****************************************************************)
(*                      Tests                                   *)
(****************************************************************)

(** Consensus operation for future level : apply a preendorsement with a level in the future *)
let test_consensus_operation_preendorsement_for_future_level () =
  init_genesis () >>=? fun (genesis, pred) ->
  let raw_level = Raw_level.of_int32 (Int32.of_int 10) in
  let level = match raw_level with Ok l -> l | Error _ -> assert false in
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~level
    ~error_title:"Consensus operation for future level"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, None)
    ()

(** Consensus operation for old level : apply a preendorsement with a level in the past *)
let test_consensus_operation_preendorsement_for_old_level () =
  init_genesis () >>=? fun (genesis, pred) ->
  let raw_level = Raw_level.of_int32 (Int32.of_int 0) in
  let level = match raw_level with Ok l -> l | Error _ -> assert false in
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~level
    ~error_title:"Consensus operation for old level"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, None)
    ()

(** Consensus operation for future round : apply a preendorsement with a round in the future *)
let test_consensus_operation_preendorsement_for_future_round () =
  init_genesis () >>=? fun (genesis, pred) ->
  Environment.wrap_tzresult (Round.of_int 21) >>?= fun round ->
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~round
    ~error_title:"Consensus operation for future round"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, None)
    ()

(** Consensus operation for old round : apply a preendorsement with a round in the past *)
let test_consensus_operation_preendorsement_for_old_round () =
  init_genesis ~policy:(By_round 10) () >>=? fun (genesis, pred) ->
  Environment.wrap_tzresult (Round.of_int 0) >>?= fun round ->
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~round
    ~error_title:"Consensus operation for old round"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, None)
    ()

(** Consensus operation on competing proposal : apply a preendorsement on a competing proposal *)
let test_consensus_operation_preendorsement_on_competing_proposal () =
  init_genesis () >>=? fun (genesis, pred) ->
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~block_payload_hash:Block_payload_hash.zero
    ~error_title:"Consensus operation on competing proposal"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, None)
    ()

(** Unexpected preendorsements in block : apply a preendorsement with an incorrect round *)
let test_unexpected_preendorsements_in_blocks () =
  init_genesis () >>=? fun (genesis, pred) ->
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~error_title:"unexpected preendorsement in block"
    ~context:(Context.B genesis)
    ()

(** Round too high : apply a preendorsement with a too high round *)
let test_too_high_round () =
  init_genesis () >>=? fun (genesis, pred) ->
  let raw_level = Raw_level.of_int32 (Int32.of_int 2) in
  let level = match raw_level with Ok l -> l | Error _ -> assert false in
  Environment.wrap_tzresult (Round.of_int 1) >>?= fun round ->
  Consensus_helpers.test_consensus_operation
    ~loc:__LOC__
    ~is_preendorsement:true
    ~endorsed_block:pred
    ~round
    ~level
    ~error_title:"preendorsement round too high"
    ~context:(Context.B genesis)
    ~construction_mode:(pred, Some pred.header.protocol_data)
    ()

(** Duplicate preendorsement : apply a preendorsement that has already been applied. *)
let test_duplicate_preendorsement () =
  init_genesis () >>=? fun (genesis, _) ->
  Block.bake genesis >>=? fun b ->
  Incremental.begin_construction ~mempool_mode:true b >>=? fun inc ->
  Op.preendorsement ~endorsed_block:b (B genesis) () >>=? fun operation ->
  let operation = Operation.pack operation in
  Incremental.add_operation inc operation >>=? fun inc ->
  Op.preendorsement ~endorsed_block:b (B genesis) () >>=? fun operation ->
  let operation = Operation.pack operation in
  Incremental.add_operation inc operation >>= fun res ->
  Assert.proto_error_with_info
    ~loc:__LOC__
    res
    "double inclusion of consensus operation"

(** Preendorsement for next level *)
let test_preendorsement_for_next_level () =
  init_genesis () >>=? fun (genesis, _) ->
  Consensus_helpers.test_consensus_op_for_next
    ~genesis
    ~kind:`Preendorsement
    ~next:`Level

(** Preendorsement for next round *)
let test_preendorsement_for_next_round () =
  init_genesis () >>=? fun (genesis, _) ->
  Consensus_helpers.test_consensus_op_for_next
    ~genesis
    ~kind:`Preendorsement
    ~next:`Round

let tests =
  let module AppMode = Test_preendorsement_functor.BakeWithMode (struct
    let name = "AppMode"

    let baking_mode = Block.Application
  end) in
  let module ConstrMode = Test_preendorsement_functor.BakeWithMode (struct
    let name = "ConstrMode"

    let baking_mode = Block.Baking
  end) in
  AppMode.tests @ ConstrMode.tests
  @ [
      Tztest.tztest
        "Preendorsement for future level"
        `Quick
        test_consensus_operation_preendorsement_for_future_level;
      Tztest.tztest
        "Preendorsement for old level"
        `Quick
        test_consensus_operation_preendorsement_for_old_level;
      Tztest.tztest
        "Preendorsement for future round"
        `Quick
        test_consensus_operation_preendorsement_for_future_round;
      Tztest.tztest
        "Preendorsement for old round"
        `Quick
        test_consensus_operation_preendorsement_for_old_round;
      Tztest.tztest
        "Preendorsement on competing proposal"
        `Quick
        test_consensus_operation_preendorsement_on_competing_proposal;
      Tztest.tztest
        "Unexpected preendorsements in blocks"
        `Quick
        test_unexpected_preendorsements_in_blocks;
      Tztest.tztest "Preendorsements round too high" `Quick test_too_high_round;
      Tztest.tztest
        "Duplicate preendorsement"
        `Quick
        test_duplicate_preendorsement;
      Tztest.tztest
        "Preendorsement for next level"
        `Quick
        test_preendorsement_for_next_level;
      Tztest.tztest
        "Preendorsement for next round"
        `Quick
        test_preendorsement_for_next_round;
    ]
