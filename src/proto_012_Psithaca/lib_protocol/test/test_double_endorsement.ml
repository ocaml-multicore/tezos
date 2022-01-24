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
    Component:    Protocol (double endorsement)
    Invocation:   dune exec src/proto_alpha/lib_protocol/test/main.exe -- test "^double endorsement$"
    Subject:      Double endorsement evidence operation may happen when an
                  endorser endorsed two different blocks on the same level.
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
  | [] -> assert false
  | baker_1 :: other_bakers ->
      (baker_1, get_first_different_baker baker_1 other_bakers)

let get_first_different_endorsers ctxt =
  Context.get_endorsers ctxt >|=? fun endorsers -> get_hd_hd endorsers

let block_fork b =
  get_first_different_bakers (B b) >>=? fun (baker_1, baker_2) ->
  Block.bake ~policy:(By_account baker_1) b >>=? fun blk_a ->
  Block.bake ~policy:(By_account baker_2) b >|=? fun blk_b -> (blk_a, blk_b)

(****************************************************************)
(*                        Tests                                 *)
(****************************************************************)

let get_first_2_accounts_contracts contracts =
  let ((contract1, account1), (contract2, account2)) =
    match contracts with
    | [a1; a2] ->
        ( ( a1,
            Contract.is_implicit a1 |> function
            | None -> assert false
            | Some pkh -> pkh ),
          ( a2,
            Contract.is_implicit a2 |> function
            | None -> assert false
            | Some pkh -> pkh ) )
    | _ -> assert false
  in
  ((contract1, account1), (contract2, account2))

let order_endorsements ~correct_order op1 op2 =
  let oph1 = Operation.hash op1 in
  let oph2 = Operation.hash op2 in
  let c = Operation_hash.compare oph1 oph2 in
  if correct_order then if c < 0 then (op1, op2) else (op2, op1)
  else if c < 0 then (op2, op1)
  else (op1, op2)

let double_endorsement ctxt ?(correct_order = true) op1 op2 =
  let (e1, e2) = order_endorsements ~correct_order op1 op2 in
  Op.double_endorsement ctxt e1 e2

(** This test verifies that when a "cheater" double endorses and
    doesn't have enough tokens to re-freeze of full deposit, we only
    freeze what we can (i.e. the remaining balance) but we check that
    another denunciation will slash 50% of the initial (expected) amount
    of the deposit. *)

(** Simple scenario where two endorsements are made from the same
    delegate and exposed by a double_endorsement operation. Also verify
    that punishment is operated. *)
let test_valid_double_endorsement_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  block_fork genesis >>=? fun (blk_1, blk_2) ->
  (* from blk_1 we bake blk_a and from blk_2 we bake blk_b so that
     the same delegate endorses blk_a and blk_b and these 2 form
     a valid double endorsement evidence;
     - note that we cannot have double endorsement evidence
       at the level of blk_1, blk_2 because both have as parent genesis
       and so the endorsements are identical because the blocks blk_1, blk_2
       are identical. *)
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Context.get_endorser (B blk_a) >>=? fun (delegate, _) ->
  Op.endorsement ~endorsed_block:blk_a (B blk_1) () >>=? fun endorsement_a ->
  Op.endorsement ~endorsed_block:blk_b (B blk_2) () >>=? fun endorsement_b ->
  let operation = double_endorsement (B genesis) endorsement_a endorsement_b in
  Context.get_bakers (B blk_a) >>=? fun bakers ->
  let baker = get_first_different_baker delegate bakers in
  Context.Delegate.full_balance (B blk_a) baker >>=? fun full_balance ->
  Block.bake ~policy:(By_account baker) ~operation blk_a >>=? fun blk_final ->
  (* Check that parts of the frozen deposits are slashed *)
  Context.Delegate.current_frozen_deposits (B blk_a) delegate
  >>=? fun frozen_deposits_before ->
  Context.Delegate.current_frozen_deposits (B blk_final) delegate
  >>=? fun frozen_deposits_after ->
  Context.get_constants (B genesis) >>=? fun csts ->
  let r =
    csts.parametric.ratio_of_frozen_deposits_slashed_per_double_endorsement
  in
  let expected_frozen_deposits_after =
    Test_tez.(
      frozen_deposits_before
      *! Int64.of_int (r.denominator - r.numerator)
      /! Int64.of_int r.denominator)
  in
  Assert.equal_tez
    ~loc:__LOC__
    expected_frozen_deposits_after
    frozen_deposits_after
  >>=? fun () ->
  (* Check that the initial frozen deposits has not changed *)
  Context.Delegate.initial_frozen_deposits (B blk_final) delegate
  >>=? fun initial_frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ initial_frozen_deposits frozen_deposits_before
  >>=? fun () ->
  (* Check that [baker] is rewarded with:
     - baking_reward_fixed_portion for baking and,
     - half of the frozen_deposits for including the evidence *)
  let baking_reward = csts.parametric.baking_reward_fixed_portion in
  let evidence_reward = Test_tez.(frozen_deposits_after /! 2L) in
  let expected_reward = Test_tez.(baking_reward +! evidence_reward) in
  Context.Delegate.full_balance (B blk_final) baker
  >>=? fun full_balance_with_rewards ->
  let real_reward = Test_tez.(full_balance_with_rewards -! full_balance) in
  Assert.equal_tez ~loc:__LOC__ expected_reward real_reward

(** Say a delegate double-endorses twice and say the 2 evidences are timely
   included. Then the delegate can no longer bake. *)
let test_two_double_endorsement_evidences_leadsto_no_bake () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  block_fork genesis >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Context.get_endorser (B blk_a) >>=? fun (delegate, _) ->
  Op.endorsement ~endorsed_block:blk_a (B blk_1) () >>=? fun endorsement_a ->
  Op.endorsement ~endorsed_block:blk_b (B blk_2) () >>=? fun endorsement_b ->
  let operation = double_endorsement (B genesis) endorsement_a endorsement_b in
  Context.get_bakers (B blk_a) >>=? fun bakers ->
  let baker = get_first_different_baker delegate bakers in
  Context.Delegate.full_balance (B blk_a) baker >>=? fun _full_balance ->
  Block.bake ~policy:(By_account baker) ~operation blk_a
  >>=? fun blk_with_evidence1 ->
  block_fork blk_with_evidence1 >>=? fun (blk_30, blk_40) ->
  Block.bake blk_30 >>=? fun blk_3 ->
  Block.bake blk_40 >>=? fun blk_4 ->
  Op.endorsement ~endorsed_block:blk_3 (B blk_30) () >>=? fun endorsement_3 ->
  Op.endorsement ~endorsed_block:blk_4 (B blk_40) () >>=? fun endorsement_4 ->
  let operation =
    double_endorsement (B blk_with_evidence1) endorsement_3 endorsement_4
  in
  Block.bake ~policy:(By_account baker) ~operation blk_3
  >>=? fun blk_with_evidence2 ->
  (* Check that all the frozen deposits are slashed *)
  Context.Delegate.current_frozen_deposits (B blk_with_evidence2) delegate
  >>=? fun frozen_deposits_after ->
  Assert.equal_tez ~loc:__LOC__ Tez.zero frozen_deposits_after >>=? fun () ->
  Block.bake ~policy:(By_account delegate) blk_with_evidence2 >>= fun b ->
  (* a delegate with 0 frozen deposits cannot bake *)
  Assert.proto_error ~loc:__LOC__ b (function err ->
      let error_info =
        Error_monad.find_info_of_error (Environment.wrap_tzerror err)
      in
      error_info.title = "Zero frozen deposits")

(****************************************************************)
(*  The following test scenarios are supposed to raise errors.  *)
(****************************************************************)

(** Check that an invalid double endorsement operation that exposes a
      valid endorsement fails. *)
let test_invalid_double_endorsement () =
  Context.init ~consensus_threshold:0 10 >>=? fun (genesis, _) ->
  Block.bake genesis >>=? fun b ->
  Op.endorsement ~endorsed_block:b (B genesis) () >>=? fun endorsement ->
  Block.bake ~operation:(Operation.pack endorsement) b >>=? fun b ->
  Op.double_endorsement (B b) endorsement endorsement |> fun operation ->
  Block.bake ~operation b >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Invalid_denunciation Endorsement -> true
      | _ -> false)

(** Check that an double endorsement operation that is invalid due to
   incorrect ordering of the endorsements fails. *)
let test_invalid_double_endorsement_variant () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  Block.bake_until_cycle_end genesis >>=? fun b ->
  block_fork b >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Op.endorsement ~endorsed_block:blk_a (B blk_1) () >>=? fun endorsement_a ->
  Op.endorsement ~endorsed_block:blk_b (B blk_2) () >>=? fun endorsement_b ->
  double_endorsement
    (B genesis)
    ~correct_order:false
    endorsement_a
    endorsement_b
  |> fun operation ->
  Block.bake ~operation genesis >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Invalid_denunciation Endorsement -> true
      | _ -> false)

(** Check that a future-cycle double endorsement fails. *)
let test_too_early_double_endorsement_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  Block.bake_until_cycle_end genesis >>=? fun b ->
  block_fork b >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Op.endorsement ~endorsed_block:blk_a (B blk_1) () >>=? fun endorsement_a ->
  Op.endorsement ~endorsed_block:blk_b (B blk_2) () >>=? fun endorsement_b ->
  double_endorsement (B genesis) endorsement_a endorsement_b |> fun operation ->
  Block.bake ~operation genesis >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Too_early_denunciation {kind = Endorsement; _} -> true
      | _ -> false)

(** Check that after [max_slashing_period * blocks_per_cycle + 1], it is not possible
    to create a double_endorsement anymore. *)
let test_too_late_double_endorsement_evidence () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  Context.get_constants (B genesis)
  >>=? fun Constants.
             {parametric = {max_slashing_period; blocks_per_cycle; _}; _} ->
  block_fork genesis >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Op.endorsement ~endorsed_block:blk_a (B blk_1) () >>=? fun endorsement_a ->
  Op.endorsement ~endorsed_block:blk_b (B blk_2) () >>=? fun endorsement_b ->
  Block.bake_n ((max_slashing_period * Int32.to_int blocks_per_cycle) + 1) blk_a
  >>=? fun blk ->
  double_endorsement (B blk) endorsement_a endorsement_b |> fun operation ->
  Block.bake ~operation blk >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Outdated_denunciation {kind = Endorsement; _} -> true
      | _ -> false)

(** Check that an invalid double endorsement evidence that exposes two
    endorsements made by two different endorsers fails. *)
let test_different_delegates () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _) ->
  Block.bake genesis >>=? fun genesis ->
  block_fork genesis >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Context.get_endorser (B blk_a) >>=? fun (endorser_a, a_slots) ->
  get_first_different_endorsers (B blk_b)
  >>=? fun (endorser_b1c, endorser_b2c) ->
  let (endorser_b, b_slots) =
    if Signature.Public_key_hash.( = ) endorser_a endorser_b1c.delegate then
      (endorser_b2c.delegate, endorser_b2c.slots)
    else (endorser_b1c.delegate, endorser_b1c.slots)
  in
  Op.endorsement
    ~delegate:(endorser_a, a_slots)
    ~endorsed_block:blk_a
    (B blk_1)
    ()
  >>=? fun e_a ->
  Op.endorsement
    ~delegate:(endorser_b, b_slots)
    ~endorsed_block:blk_b
    (B blk_2)
    ()
  >>=? fun e_b ->
  Block.bake ~operation:(Operation.pack e_b) blk_b >>=? fun _ ->
  double_endorsement (B blk_b) e_a e_b |> fun operation ->
  Block.bake ~operation blk_b >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Inconsistent_denunciation {kind = Endorsement; _} -> true
      | _ -> false)

(** Check that a double endorsement evidence that exposes a ill-formed
    endorsement fails. *)
let test_wrong_delegate () =
  Context.init ~consensus_threshold:0 2 >>=? fun (genesis, _contracts) ->
  block_fork genesis >>=? fun (blk_1, blk_2) ->
  Block.bake blk_1 >>=? fun blk_a ->
  Block.bake blk_2 >>=? fun blk_b ->
  Context.get_endorser (B blk_a) >>=? fun (endorser_a, a_slots) ->
  Op.endorsement
    ~delegate:(endorser_a, a_slots)
    ~endorsed_block:blk_a
    (B blk_1)
    ()
  >>=? fun endorsement_a ->
  Context.get_endorser_n (B blk_b) 0 >>=? fun (endorser0, slots0) ->
  Context.get_endorser_n (B blk_b) 1 >>=? fun (endorser1, slots1) ->
  let (endorser_b, b_slots) =
    if Signature.Public_key_hash.equal endorser_a endorser0 then
      (endorser1, slots1)
    else (endorser0, slots0)
  in
  Op.endorsement
    ~delegate:(endorser_b, b_slots)
    ~endorsed_block:blk_b
    (B blk_2)
    ()
  >>=? fun endorsement_b ->
  double_endorsement (B blk_b) endorsement_a endorsement_b |> fun operation ->
  Block.bake ~operation blk_b >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Apply.Inconsistent_denunciation {kind = Endorsement; _} -> true
      | _ -> false)

let test_freeze_more_with_low_balance =
  let get_endorsing_slots_for_account ctxt account =
    (* Get the slots of the given account in the given context. *)
    Context.get_endorsers ctxt >>=? function
    | [d1; d2] ->
        return
          (if Signature.Public_key_hash.equal account d1.delegate then d1
          else if Signature.Public_key_hash.equal account d2.delegate then d2
          else assert false)
            .slots
    | _ -> assert false
    (* there are exactly two endorsers for this test. *)
  in
  let double_endorse_and_punish b2 account1 =
    (* Bake a block on top of [b2] that includes a double-endorsement
       denunciation of [account1]. *)
    block_fork b2 >>=? fun (blk_d1, blk_d2) ->
    Block.bake ~policy:(Block.By_account account1) blk_d1 >>=? fun blk_a ->
    Block.bake ~policy:(Block.By_account account1) blk_d2 >>=? fun blk_b ->
    get_endorsing_slots_for_account (B blk_a) account1 >>=? fun slots_a ->
    Op.endorsement
      ~delegate:(account1, slots_a)
      ~endorsed_block:blk_a
      (B blk_d1)
      ()
    >>=? fun end_a ->
    get_endorsing_slots_for_account (B blk_b) account1 >>=? fun slots_b ->
    Op.endorsement
      ~delegate:(account1, slots_b)
      ~endorsed_block:blk_b
      (B blk_d2)
      ()
    >>=? fun end_b ->
    let denunciation = double_endorsement (B b2) end_a end_b in
    Block.bake ~policy:(Excluding [account1]) b2 ~operations:[denunciation]
  in
  let check_unique_endorser b account2 =
    Context.get_endorsers (B b) >>=? function
    | [{delegate; _}] when Signature.Public_key_hash.equal account2 delegate ->
        return_unit
    | _ -> failwith "We are supposed to only have account2 as endorser."
  in
  fun () ->
    let constants =
      {
        Default_parameters.constants_test with
        endorsing_reward_per_slot = Tez.zero;
        baking_reward_bonus_per_slot = Tez.zero;
        baking_reward_fixed_portion = Tez.zero;
        consensus_threshold = 0;
        origination_size = 0;
        preserved_cycles = 5;
        ratio_of_frozen_deposits_slashed_per_double_endorsement =
          (* enforce that ratio is 50% is the test's params. *)
          {numerator = 1; denominator = 2};
      }
    in
    Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
    let ((_contract1, account1), (_contract2, account2)) =
      get_first_2_accounts_contracts contracts
    in
    (* we empty the available balance of [account1]. *)
    Context.Delegate.info (B genesis) account1 >>=? fun info1 ->
    Op.transaction
      (B genesis)
      (Contract.implicit_contract account1)
      (Contract.implicit_contract account2)
      Test_tez.(info1.full_balance -! info1.frozen_deposits)
    >>=? fun op ->
    Block.bake ~policy:(Block.By_account account2) genesis ~operations:[op]
    >>=? fun b2 ->
    Context.Delegate.info (B b2) account1 >>=? fun info2 ->
    (* after block [b2], the spendable balance of [account1] is 0tz. So, given
       that we have the invariant full_balance = spendable balance +
       frozen_deposits, in this particular case, full_balance = frozen_deposits
       for [account1], and the frozen_deposits didn't change since genesis. *)
    Assert.equal_tez ~loc:__LOC__ info2.full_balance info2.frozen_deposits
    >>=? fun () ->
    Assert.equal_tez ~loc:__LOC__ info1.frozen_deposits info2.frozen_deposits
    >>=? fun () ->
    double_endorse_and_punish b2 account1 >>=? fun b3 ->
    (* Denunciation has happened: we check that the full balance of [account1]
       is (still) equal to its deposit. *)
    Context.Delegate.info (B b3) account1 >>=? fun info3 ->
    Assert.equal_tez
      ~loc:__LOC__
      info3.full_balance
      info3.current_frozen_deposits
    >>=? fun () ->
    (* We also check that compared to deposits at block [b2], [account1] lost
       50% of its deposits. *)
    let slash_ratio =
      constants.ratio_of_frozen_deposits_slashed_per_double_endorsement
    in
    let expected_frozen_deposits_after =
      Test_tez.(
        info2.frozen_deposits
        *! Int64.of_int (slash_ratio.denominator - slash_ratio.numerator)
        /! Int64.of_int slash_ratio.denominator)
    in
    Assert.equal_tez
      ~loc:__LOC__
      expected_frozen_deposits_after
      info3.current_frozen_deposits
    >>=? fun () ->
    (* We now bake until end of cycle only with [account2]:
       block of the new cycle are called cX below. *)
    Block.bake_until_cycle_end b3 >>=? fun c1 ->
    double_endorse_and_punish c1 account1 >>=? fun c2 ->
    (* Second denunciation has happened: we check that the full balance of
       [account1] reflects the slashing of 50% of the original deposit. Its
       current deposits are thus 0tz. *)
    Context.Delegate.info (B c2) account1 >>=? fun info4 ->
    Assert.equal_tez ~loc:__LOC__ info4.full_balance Tez.zero >>=? fun () ->
    Assert.equal_tez ~loc:__LOC__ info4.current_frozen_deposits Tez.zero
    >>=? fun () ->
    Block.bake c2 ~policy:(By_account account1) >>= fun c3 ->
    (* Once the deposits dropped to 0, the baker cannot bake anymore *)
    Assert.proto_error_with_info ~loc:__LOC__ c3 "Zero frozen deposits"
    >>=? fun () ->
    (* We bake [2 * preserved_cycles] additional cycles only with [account2].
       Because [account1] does not bake during this period, it loses its rights.
    *)
    Block.bake_until_n_cycle_end
      ~policy:(By_account account2)
      (2 * constants.preserved_cycles)
      c2
    >>=? fun d1 ->
    Context.Delegate.info (B d1) account1 >>=? fun info5 ->
    (* [account1] is only deactivated after 1 + [2 * preserved_cycles] (see
       [Delegate_activation_storage.set_active] since the last time it was
       active, that is, since the first cycle. Thus the cycle at which
       [account1] is deactivated is 2 + [2 * preserved_cycles] from genesis. *)
    Assert.equal_bool ~loc:__LOC__ info5.deactivated false >>=? fun () ->
    (* account1 is still active, but has no rights. *)
    check_unique_endorser d1 account2 >>=? fun () ->
    Block.bake_until_cycle_end ~policy:(By_account account2) d1 >>=? fun e1 ->
    (* account1 has no rights and furthermore is no longer active. *)
    check_unique_endorser e1 account2 >>=? fun () ->
    Context.Delegate.info (B e1) account1 >>=? fun info6 ->
    Assert.equal_bool ~loc:__LOC__ info6.deactivated true

let tests =
  [
    Tztest.tztest
      "valid double endorsement evidence"
      `Quick
      test_valid_double_endorsement_evidence;
    Tztest.tztest
      "2 valid double endorsement evidences lead to not being able to bake"
      `Quick
      test_two_double_endorsement_evidences_leadsto_no_bake;
    Tztest.tztest
      "invalid double endorsement evidence"
      `Quick
      test_invalid_double_endorsement;
    Tztest.tztest
      "another invalid double endorsement evidence"
      `Quick
      test_invalid_double_endorsement_variant;
    Tztest.tztest
      "too early double endorsement evidence"
      `Quick
      test_too_early_double_endorsement_evidence;
    Tztest.tztest
      "too late double endorsement evidence"
      `Quick
      test_too_late_double_endorsement_evidence;
    Tztest.tztest "different delegates" `Quick test_different_delegates;
    Tztest.tztest "wrong delegate" `Quick test_wrong_delegate;
    Tztest.tztest
      "freeze available balance after slashing"
      `Quick
      test_freeze_more_with_low_balance;
  ]
