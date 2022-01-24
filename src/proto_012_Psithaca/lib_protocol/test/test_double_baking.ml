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

(** Testing
    -------
    Component:    Protocol (double baking)
    Invocation:   dune exec src/proto_alpha/lib_protocol/test/main.exe -- test "^double baking$"
    Subject:      A double baking evidence operation may be injected when it has
                  been observed that a baker baked two different blocks at the
                  same level and same round.
*)

open Protocol
open Alpha_context

(****************************************************************)
(*                  Utility functions                           *)
(****************************************************************)

let get_hd_hd = function x :: y :: _ -> (x, y) | _ -> assert false

let get_first_different_baker baker bakers =
  WithExceptions.Option.get ~loc:__LOC__
  @@ List.find
       (fun baker' -> Signature.Public_key_hash.( <> ) baker baker')
       bakers

let get_first_different_bakers ctxt =
  Context.get_bakers ctxt >|=? function
  | [] | [_] -> assert false
  | baker_1 :: other_bakers ->
      (baker_1, get_first_different_baker baker_1 other_bakers)

let get_baker_different_from_baker ctxt baker =
  Context.get_bakers
    ~filter:(fun x -> not (Signature.Public_key_hash.equal x.delegate baker))
    ctxt
  >>=? fun bakers ->
  return (WithExceptions.Option.get ~loc:__LOC__ @@ List.hd bakers)

let get_first_different_endorsers ctxt =
  Context.get_endorsers ctxt >|=? fun endorsers -> get_hd_hd endorsers

(** Bake two block at the same level using the same policy (i.e. same
    baker). *)
let block_fork ?policy contracts b =
  let (contract_a, contract_b) = get_hd_hd contracts in
  Op.transaction (B b) contract_a contract_b Alpha_context.Tez.one_cent
  >>=? fun operation ->
  Block.bake ?policy ~operation b >>=? fun blk_a ->
  Block.bake ?policy b >|=? fun blk_b -> (blk_a, blk_b)

let order_block_hashes ~correct_order bh1 bh2 =
  let hash1 = Block_header.hash bh1 in
  let hash2 = Block_header.hash bh2 in
  let c = Block_hash.compare hash1 hash2 in
  if correct_order then if c < 0 then (bh1, bh2) else (bh2, bh1)
  else if c < 0 then (bh2, bh1)
  else (bh1, bh2)

let double_baking ctxt ?(correct_order = true) bh1 bh2 =
  let (bh1, bh2) = order_block_hashes ~correct_order bh1 bh2 in
  Op.double_baking ctxt bh1 bh2

(****************************************************************)
(*                        Tests                                 *)
(****************************************************************)

(** Simple scenario where two blocks are baked by a same baker and
    exposed by a double baking evidence operation. *)
let test_valid_double_baking_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, contracts) ->
  Context.get_constants (B genesis)
  >>=? fun Constants.{parametric = {double_baking_punishment; _}; _} ->
  get_first_different_bakers (B genesis) >>=? fun (baker1, baker2) ->
  block_fork ~policy:(By_account baker1) contracts genesis
  >>=? fun (blk_a, blk_b) ->
  double_baking (B blk_a) blk_a.header blk_b.header |> fun operation ->
  Block.bake ~policy:(By_account baker2) ~operation blk_a >>=? fun blk_final ->
  (* Check that the frozen deposits are slashed *)
  Context.Delegate.current_frozen_deposits (B blk_a) baker1
  >>=? fun frozen_deposits_before ->
  Context.Delegate.current_frozen_deposits (B blk_final) baker1
  >>=? fun frozen_deposits_after ->
  let slashed_amount =
    Test_tez.(frozen_deposits_before -! frozen_deposits_after)
  in
  Assert.equal_tez ~loc:__LOC__ slashed_amount double_baking_punishment
  >>=? fun () ->
  (* Check that the initial frozen deposits has not changed *)
  Context.Delegate.initial_frozen_deposits (B blk_final) baker1
  >>=? fun initial_frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ initial_frozen_deposits frozen_deposits_before

(** Test that the payload producer of the block containing a double
   baking evidence (and not the block producer, if different) receives
   the reward. *)
let test_payload_producer_gets_evidence_rewards () =
  Context.init ~consensus_threshold:0 10 >>=? fun (genesis, contracts) ->
  Context.get_constants (B genesis)
  >>=? fun Constants.
             {
               parametric =
                 {double_baking_punishment; baking_reward_fixed_portion; _};
               _;
             } ->
  get_first_different_bakers (B genesis) >>=? fun (baker1, baker2) ->
  block_fork ~policy:(By_account baker1) contracts genesis >>=? fun (b1, b2) ->
  double_baking (B b1) b1.header b2.header |> fun db_evidence ->
  Block.bake ~policy:(By_account baker2) ~operation:db_evidence b1
  >>=? fun b_with_evidence ->
  Context.get_endorsers (B b_with_evidence) >>=? fun endorsers ->
  List.map_es
    (function
      | {Plugin.RPC.Validators.delegate; slots; _} -> return (delegate, slots))
    endorsers
  >>=? fun preendorsers ->
  List.map_ep
    (fun endorser ->
      Op.preendorsement
        ~delegate:endorser
        ~endorsed_block:b_with_evidence
        (B b1)
        ()
      >|=? Operation.pack)
    preendorsers
  >>=? fun preendos ->
  Block.bake
    ~payload_round:(Some Round.zero)
    ~locked_round:(Some Round.zero)
    ~policy:(By_account baker1)
    ~operations:(db_evidence :: preendos)
    b1
  >>=? fun b' ->
  (* the frozen deposits of the double-signer [baker1] are slashed *)
  Context.Delegate.current_frozen_deposits (B b1) baker1
  >>=? fun frozen_deposits_before ->
  Context.Delegate.current_frozen_deposits (B b') baker1
  >>=? fun frozen_deposits_after ->
  let slashed_amount =
    Test_tez.(frozen_deposits_before -! frozen_deposits_after)
  in
  Assert.equal_tez ~loc:__LOC__ slashed_amount double_baking_punishment
  >>=? fun () ->
  (* [baker2] included the double baking evidence in [b_with_evidence]
     and so it receives the reward for the evidence included in [b']
     (besides the reward for proposing the payload). *)
  Context.Delegate.full_balance (B b1) baker2 >>=? fun full_balance ->
  let evidence_reward = Test_tez.(slashed_amount /! 2L) in
  let expected_reward =
    Test_tez.(baking_reward_fixed_portion +! evidence_reward)
  in
  Context.Delegate.full_balance (B b') baker2
  >>=? fun full_balance_with_rewards ->
  let real_reward = Test_tez.(full_balance_with_rewards -! full_balance) in
  Assert.equal_tez ~loc:__LOC__ expected_reward real_reward >>=? fun () ->
  (* [baker1] did not produce the payload, it does not receive the reward for the
     evidence *)
  Context.Delegate.full_balance (B b1) baker1 >>=? fun full_balance_at_b1 ->
  Context.Delegate.full_balance (B b') baker1 >>=? fun full_balance_at_b' ->
  Assert.equal_tez
    ~loc:__LOC__
    full_balance_at_b'
    Test_tez.(full_balance_at_b1 -! double_baking_punishment)

(****************************************************************)
(*  The following test scenarios are supposed to raise errors.  *)
(****************************************************************)

(** Check that a double baking operation fails if it exposes the same two
    blocks. *)
let test_same_blocks () =
  Context.init 2 >>=? fun (b, _contracts) ->
  Block.bake b >>=? fun ba ->
  double_baking (B ba) ba.header ba.header |> fun operation ->
  Block.bake ~operation ba >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Invalid_double_baking_evidence _ -> true
      | _ -> false)
  >>=? fun () -> return_unit

(** Check that an double baking operation that is invalid due to
   incorrect ordering of the block headers fails. *)
let test_incorrect_order () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, contracts) ->
  block_fork ~policy:(By_round 0) contracts genesis >>=? fun (blk_a, blk_b) ->
  double_baking (B genesis) ~correct_order:false blk_a.header blk_b.header
  |> fun operation ->
  Block.bake ~operation genesis >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Invalid_double_baking_evidence _ -> true
      | _ -> false)

(** Check that a double baking operation exposing two blocks with
    different levels fails. *)
let test_different_levels () =
  Context.init ~consensus_threshold:0 2 >>=? fun (b, contracts) ->
  block_fork ~policy:(By_round 0) contracts b >>=? fun (blk_a, blk_b) ->
  Block.bake blk_b >>=? fun blk_b_2 ->
  double_baking (B blk_a) blk_a.header blk_b_2.header |> fun operation ->
  Block.bake ~operation blk_a >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Invalid_double_baking_evidence _ -> true
      | _ -> false)

(** Check that a double baking operation exposing two yet-to-be-baked
    blocks fails. *)
let test_too_early_double_baking_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, contracts) ->
  Block.bake_until_cycle_end genesis >>=? fun b ->
  block_fork ~policy:(By_round 0) contracts b >>=? fun (blk_a, blk_b) ->
  double_baking (B b) blk_a.header blk_b.header |> fun operation ->
  Block.bake ~operation genesis >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Too_early_denunciation {kind = Block; _} -> true
      | _ -> false)

(** Check that after [max_slashing_period * blocks_per_cycle + 1] blocks -- corresponding to 2 cycles
   --, it is not possible to create a double baking operation anymore. *)
let test_too_late_double_baking_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (b, contracts) ->
  Context.get_constants (B b)
  >>=? fun Constants.{parametric = {max_slashing_period; _}; _} ->
  block_fork ~policy:(By_round 0) contracts b >>=? fun (blk_a, blk_b) ->
  Block.bake_until_n_cycle_end max_slashing_period blk_a >>=? fun blk ->
  double_baking (B blk) blk_a.header blk_b.header |> fun operation ->
  Block.bake ~operation blk >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Outdated_denunciation {kind = Block; _} -> true
      | _ -> false)

(** Check that before [max_slashing_period * blocks_per_cycle] blocks
   -- corresponding to 2 cycles --, it is still possible to create a
   double baking operation. *)
let test_just_in_time_double_baking_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (b, contracts) ->
  Context.get_constants (B b)
  >>=? fun Constants.{parametric = {blocks_per_cycle; _}; _} ->
  block_fork ~policy:(By_round 0) contracts b >>=? fun (blk_a, blk_b) ->
  Block.bake_until_cycle_end blk_a >>=? fun blk ->
  Block.bake_n Int32.(sub blocks_per_cycle 2l |> to_int) blk >>=? fun blk ->
  let operation = double_baking (B blk) blk_a.header blk_b.header in
  (* We include the denuncation in the previous to last block of the
     cycle. *)
  Block.bake ~operation blk >>=? fun _ -> return_unit

(** Check that an invalid double baking evidence that exposes two
    block baking with same level made by different bakers fails. *)
let test_different_delegates () =
  Context.init 2 >>=? fun (b, _) ->
  get_first_different_bakers (B b) >>=? fun (baker_1, baker_2) ->
  Block.bake ~policy:(By_account baker_1) b >>=? fun blk_a ->
  Block.bake ~policy:(By_account baker_2) b >>=? fun blk_b ->
  double_baking (B blk_a) blk_a.header blk_b.header |> fun operation ->
  Block.bake ~operation blk_a >>= fun e ->
  Assert.proto_error ~loc:__LOC__ e (function
      | Apply.Invalid_double_baking_evidence _ -> true
      | _ -> false)

(** This test is supposed to mimic that a block cannot be baked by one baker and
    signed by another. The way it tries to show this is by using a
    Double_baking_evidence operation:
    - say [baker_1] bakes block blk_a so blk_a has a header with baker_1's
    signature
    - say we create an artificial [header_b] for a block b' with timestamp [ts]
    at the same level as [blk_a], and the header is created such that it says that
    b' is baked by the same [baker_1] and signed by [baker_2]
    - because [header_b] says that b' is baked by [baker_0], b' has the same
    round as [blk_a], which together with the fact that b' and [blk_a] have the
    same level, means that double_baking is valid: we have [blk_a] and b' at the
    same level and round, but with different timestamps and signed by different
    bakers.
    This test fails with an error stating that block is signed by the wrong
    baker. *)
let test_wrong_signer () =
  let header_custom_signer baker baker_2 timestamp b =
    Block.Forge.forge_header ~policy:(By_account baker) ~timestamp b
    >>=? fun header ->
    Block.Forge.set_baker baker_2 header |> Block.Forge.sign_header
  in
  Context.init 2 >>=? fun (b, _) ->
  get_first_different_bakers (B b) >>=? fun (baker_1, baker_2) ->
  Block.bake ~policy:(By_account baker_1) b >>=? fun blk_a ->
  let ts = Timestamp.of_seconds_string (Int64.to_string 10L) in
  match ts with
  | None -> assert false
  | Some ts ->
      header_custom_signer baker_1 baker_2 ts b >>=? fun header_b ->
      double_baking (B blk_a) blk_a.header header_b |> fun operation ->
      Block.bake ~operation blk_a >>= fun e ->
      Assert.proto_error ~loc:__LOC__ e (function
          | Block_header.Invalid_block_signature _ -> true
          | _ -> false)

(** an evidence can only be accepted once (this also means that the
   same evidence doesn't lead to slashing the offender twice) *)
let test_double_evidence () =
  Context.init ~consensus_threshold:0 3 >>=? fun (blk, contracts) ->
  block_fork contracts blk >>=? fun (blk_a, blk_b) ->
  Block.bake_until_cycle_end blk_a >>=? fun blk ->
  double_baking (B blk) blk_a.header blk_b.header |> fun evidence ->
  Block.bake ~operation:evidence blk >>=? fun blk ->
  double_baking (B blk) blk_b.header blk_a.header |> fun evidence ->
  Block.bake ~operation:evidence blk >>= fun e ->
  Assert.proto_error ~loc:__LOC__ e (function err ->
      let error_info =
        Error_monad.find_info_of_error (Environment.wrap_tzerror err)
      in
      error_info.title = "Unrequired denunciation")

let tests =
  [
    Tztest.tztest
      "valid double baking evidence"
      `Quick
      test_valid_double_baking_evidence;
    Tztest.tztest
      "payload producer receives the rewards for double baking evidence"
      `Quick
      test_payload_producer_gets_evidence_rewards;
    (* Should fail*)
    Tztest.tztest "same blocks" `Quick test_same_blocks;
    Tztest.tztest "incorrect order" `Quick test_incorrect_order;
    Tztest.tztest "different levels" `Quick test_different_levels;
    Tztest.tztest
      "too early double baking evidence"
      `Quick
      test_too_early_double_baking_evidence;
    Tztest.tztest
      "too late double baking evidence"
      `Quick
      test_too_late_double_baking_evidence;
    Tztest.tztest
      "just in time double baking evidence"
      `Quick
      test_just_in_time_double_baking_evidence;
    Tztest.tztest "different delegates" `Quick test_different_delegates;
    Tztest.tztest "wrong delegate" `Quick test_wrong_signer;
    Tztest.tztest
      "reject double injection of an evidence"
      `Quick
      test_double_evidence;
  ]
