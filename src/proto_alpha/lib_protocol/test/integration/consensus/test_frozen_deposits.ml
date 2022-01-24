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
    Component:  Protocol (frozen_deposits)
    Invocation: dune exec \
                src/proto_alpha/lib_protocol/test/integration/consensus/main.exe \
                -- test "^frozen deposits$"
    Subject:    consistency of frozen deposits and the [set_deposits_limit] operation
 *)

open Protocol
open Alpha_context
open Test_tez

let constants =
  {
    Default_parameters.constants_test with
    endorsing_reward_per_slot = Tez.zero;
    baking_reward_bonus_per_slot = Tez.zero;
    baking_reward_fixed_portion = Tez.zero;
    consensus_threshold = 0;
    origination_size = 0;
  }

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

(* Terminology:

- staking balance = full balance + delegated stake; obtained with
   Delegate.staking_balance

- active stake = the amount of tez with which a delegate participates in
   consensus; it must be greater than 1 roll and less or equal the staking
   balance; it is computed in [Delegate_storage.select_distribution_for_cycle]

- frozen deposits = represents frozen_deposits_percentage of the maximum stake during
   preserved_cycles + max_slashing_period cycles; obtained with
   Delegate.current_frozen_deposits

- spendable balance = full balance - frozen deposits; obtained with Contract.balance

- full balance = spendable balance + frozen deposits; obtained with Delegate.full_balance
*)
let test_invariants () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (contract2, _account2)) =
    get_first_2_accounts_contracts contracts
  in
  Context.Delegate.staking_balance (B genesis) account1
  >>=? fun staking_balance ->
  Context.Delegate.full_balance (B genesis) account1 >>=? fun full_balance ->
  Context.Contract.balance (B genesis) contract1 >>=? fun spendable_balance ->
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun frozen_deposits ->
  (* before delegation *)
  Assert.equal_tez ~loc:__LOC__ full_balance staking_balance >>=? fun () ->
  Assert.equal_tez
    ~loc:__LOC__
    full_balance
    Test_tez.(spendable_balance +! frozen_deposits)
  >>=? fun () ->
  (* to see how delegation plays a role, let's delegate to account1;
     N.B. account2 represents a delegate so it cannot delegate to account1; this is
     why we go through new_account as an intermediate *)
  Context.Contract.balance (B genesis) contract2 >>=? fun spendable_balance2 ->
  let new_account = (Account.new_account ()).pkh in
  let new_contract = Contract.implicit_contract new_account in
  (* we first put some money in new_account *)
  Op.transaction (B genesis) contract2 new_contract spendable_balance2
  >>=? fun transfer ->
  Block.bake ~operation:transfer genesis >>=? fun b ->
  Context.Contract.balance (B b) new_contract >>=? fun new_account_balance ->
  Assert.equal_tez ~loc:__LOC__ new_account_balance spendable_balance2
  >>=? fun () ->
  Op.delegation (B b) new_contract (Some account1) >>=? fun delegation ->
  Block.bake ~operation:delegation b >>=? fun b1 ->
  Block.bake_until_n_cycle_end constants.preserved_cycles b1 >>=? fun b2 ->
  Context.Delegate.staking_balance (B b2) account1
  >>=? fun new_staking_balance ->
  Context.Delegate.full_balance (B b2) account1 >>=? fun new_full_balance ->
  Context.Contract.balance (B b2) contract1 >>=? fun new_spendable_balance ->
  Context.Delegate.current_frozen_deposits (B b2) account1
  >>=? fun new_frozen_deposits ->
  (* after delegation, we see the delegated stake reflected in the new staking
     balance of account1 *)
  Assert.equal_tez
    ~loc:__LOC__
    new_staking_balance
    Test_tez.(new_full_balance +! new_account_balance)
  >>=? fun () ->
  Assert.equal_tez
    ~loc:__LOC__
    new_full_balance
    Test_tez.(new_spendable_balance +! new_frozen_deposits)
  >>=? fun () ->
  let expected_new_frozen_deposits =
    Test_tez.(
      (* in this particular example, if we follow the calculation of the active
         stake, it is precisely the new_staking_balance *)
      new_staking_balance /! 100L
      *! Int64.of_int constants.frozen_deposits_percentage)
  in
  Assert.equal_tez ~loc:__LOC__ new_frozen_deposits expected_new_frozen_deposits

let test_set_limit balance_percentage () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (_contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  (Context.Delegate.frozen_deposits_limit (B genesis) account1 >>=? function
   | Some _ -> Alcotest.fail "unexpected deposits limit"
   | None -> return_unit)
  >>=? fun () ->
  (* Test deposit consistency before and after first cycle *)
  Context.Delegate.full_balance (B genesis) account1 >>=? fun full_balance ->
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun frozen_deposits ->
  let expected_deposits =
    full_balance *! Int64.of_int constants.frozen_deposits_percentage /! 100L
  in
  Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_deposits >>=? fun () ->
  (* Bake until end of first cycle *)
  Block.bake_until_cycle_end genesis >>=? fun b ->
  Context.Delegate.full_balance (B genesis) account1 >>=? fun full_balance ->
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun frozen_deposits ->
  let expected_deposits =
    full_balance *! Int64.of_int constants.frozen_deposits_percentage /! 100L
  in
  Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_deposits >>=? fun () ->
  (* set deposits limit to balance_percentage out of the balance *)
  let limit =
    Test_tez.(full_balance *! Int64.of_int balance_percentage /! 100L)
  in
  Op.set_deposits_limit (B genesis) contract1 (Some limit) >>=? fun operation ->
  Block.bake ~policy:(By_account account2) ~operation b >>=? fun b ->
  (Context.Delegate.frozen_deposits_limit (B b) account1 >>=? function
   | Some set_limit -> Assert.equal_tez ~loc:__LOC__ set_limit limit
   | None -> Alcotest.fail "unexpected absence of deposits limit")
  >>=? fun () ->
  (* the frozen deposits limit affects the active stake for cycles starting with c +
     preserved_cycles + 1; the new active stake is taken into account when
     computing the frozen deposits for cycle c+1 already, however the user may see
     an update to its frozen deposits at cycle c + preserved_cycles +
     max_slashing_period at the latest (because up to that cycle the frozen
     deposits also depend on the active stake at cycles before cycle c+1). *)
  let expected_number_of_cycles_with_previous_deposit =
    constants.preserved_cycles + constants.max_slashing_period
  in
  Block.bake_until_n_cycle_end
    ~policy:(By_account account2)
    (expected_number_of_cycles_with_previous_deposit - 1)
    b
  >>=? fun b ->
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits ->
  Assert.not_equal_tez ~loc:__LOC__ frozen_deposits Tez.zero >>=? fun () ->
  Block.bake_until_cycle_end ~policy:(By_account account2) b >>=? fun b ->
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits limit

let test_cannot_bake_with_zero_deposits () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (_contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  (* N.B. there is no non-zero frozen deposits value for which one cannot bake:
     even with a small deposit one can still bake, though with a smaller probability
     (because the frozen deposits value impacts the active stake and the active
     stake is the one used to determine baking/endorsing rights. *)
  Op.set_deposits_limit (B genesis) contract1 (Some Tez.zero)
  >>=? fun operation ->
  Block.bake ~policy:(By_account account2) ~operation genesis >>=? fun b ->
  let expected_number_of_cycles_with_previous_deposit =
    constants.preserved_cycles + constants.max_slashing_period - 1
  in
  Block.bake_until_n_cycle_end
    ~policy:(By_account account2)
    expected_number_of_cycles_with_previous_deposit
    b
  >>=? fun b ->
  Block.bake ~policy:(By_account account1) b >>= fun b1 ->
  (* by now, the active stake of account1 is 0 so it no longer has slots, thus it
     cannot be a proposer, thus it cannot bake. Precisely, bake fails because
     get_next_baker_by_account fails with "No slots found" *)
  Assert.error ~loc:__LOC__ b1 (fun _ -> true)

let test_deposits_after_stake_removal () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun initial_frozen_deposits_1 ->
  Context.Delegate.current_frozen_deposits (B genesis) account2
  >>=? fun initial_frozen_deposits_2 ->
  let expected_new_frozen_deposits_2 =
    Test_tez.(initial_frozen_deposits_2 *! 3L /! 2L)
  in
  (* Move half the account1's balance to account2 *)
  Context.Delegate.full_balance (B genesis) account1 >>=? fun full_balance ->
  let half_balance = Test_tez.(full_balance /! 2L) in
  Op.transaction (B genesis) contract1 contract2 half_balance
  >>=? fun operation ->
  Block.bake ~operation genesis >>=? fun b ->
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits_1 ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits_1 initial_frozen_deposits_1
  >>=? fun () ->
  Context.Delegate.current_frozen_deposits (B b) account2
  >>=? fun frozen_deposits_2 ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits_2 initial_frozen_deposits_2
  >>=? fun () ->
  (* Bake a cycle to act account2's new frozen deposits *)
  Block.bake_until_cycle_end b >>=? fun b ->
  let rec loop b n =
    if n = 0 then return b
    else
      Context.Delegate.current_frozen_deposits (B b) account1
      >>=? fun frozen_deposits_1 ->
      (* the frozen_deposits is frozen_deposits_percentage of the maximum active stake
         during the last preserved_cycles + max_slashing_period cycles;
         consequently, though the active stake of account1 has decreased at
         cycle c, this decrease makes the frozen deposits smaller only after
         preserved cycles + max_slashing_period. *)
      Assert.equal_tez ~loc:__LOC__ frozen_deposits_1 initial_frozen_deposits_1
      >>=? fun () ->
      (* the active stake of account2 has increased and this increase affects
         the frozen_deposits from this cycle as it is greater than previous ones. *)
      Context.Delegate.current_frozen_deposits (B b) account2
      >>=? fun frozen_deposits_2 ->
      Assert.equal_tez
        ~loc:__LOC__
        frozen_deposits_2
        expected_new_frozen_deposits_2
      >>=? fun () ->
      Block.bake_until_cycle_end b >>=? fun b -> loop b (pred n)
  in
  (* the frozen deposits for account1 do not change until [preserved cycles +
     max_slashing_period] are baked (-1 because we already baked a cycle) *)
  loop b (constants.preserved_cycles + constants.max_slashing_period - 1)
  >>=? fun b ->
  (* after preserved cycles + max_slashing_period, the frozen_deposits for account1
     reflects the decrease in account1's active stake. *)
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits_1 ->
  Assert.equal_tez
    ~loc:__LOC__
    frozen_deposits_1
    Test_tez.(initial_frozen_deposits_1 /! 2L)
  >>=? fun () ->
  Context.Delegate.current_frozen_deposits (B b) account2
  >>=? fun frozen_deposits_2 ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits_2 expected_new_frozen_deposits_2

let test_unfreeze_deposits_after_deactivation () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (_contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  Context.Delegate.full_balance (B genesis) account1 >>=? fun initial_balance ->
  (* [account1] will not participate (ie bake/endorse); we set the
     expected last cycles at which it is considered active and at
     which it has non-zero deposits *)
  let last_active_cycle =
    1 + (2 * constants.preserved_cycles)
    (* according to [Delegate_storage.set_active] *)
  in
  let last_cycle_with_deposits =
    last_active_cycle + constants.preserved_cycles
    + constants.max_slashing_period
    (* according to [Delegate_storage.freeze_deposits] *)
  in
  let cycles_to_bake = last_cycle_with_deposits + constants.preserved_cycles in
  let rec loop b n =
    if n = 0 then return b
    else
      Block.bake_until_cycle_end ~policy:(By_account account2) b >>=? fun b ->
      Context.Delegate.deactivated (B b) account1 >>=? fun is_deactivated ->
      Context.Delegate.current_frozen_deposits (B b) account1
      >>=? fun frozen_deposits ->
      (* the spendable balance *)
      Context.Contract.balance (B b) contract1 >>=? fun balance ->
      let new_cycle = cycles_to_bake - n + 1 in
      Assert.equal_bool
        ~loc:__LOC__
        is_deactivated
        (new_cycle > last_active_cycle)
      >>=? fun () ->
      Assert.equal_bool
        ~loc:__LOC__
        (new_cycle > last_cycle_with_deposits)
        (* as soon as frozen_deposits are set to zero from a non-zero value v, v is
           returned to the spendable balance of account1; in this particular
           case, the spendable balance [balance] updated with v is precisely the
           initial_balance.*)
        (Tez.(frozen_deposits = zero) && Tez.(balance = initial_balance))
      >>=? fun () -> loop b (pred n)
  in
  loop genesis cycles_to_bake >>=? fun _b -> return_unit

let test_frozen_deposits_with_delegation () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((_contract1, account1), (contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  Context.Delegate.staking_balance (B genesis) account1
  >>=? fun initial_staking_balance ->
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun initial_frozen_deposits ->
  Context.Contract.balance (B genesis) contract2 >>=? fun delegated_amount ->
  let new_account = Account.new_account () in
  let new_contract = Contract.implicit_contract new_account.pkh in
  Op.transaction (B genesis) contract2 new_contract delegated_amount
  >>=? fun transfer ->
  Block.bake ~operation:transfer genesis >>=? fun b ->
  Context.Delegate.staking_balance (B b) account2
  >>=? fun new_staking_balance ->
  let expected_new_staking_balance =
    Test_tez.(initial_staking_balance -! delegated_amount)
  in
  Assert.equal_tez ~loc:__LOC__ new_staking_balance expected_new_staking_balance
  >>=? fun () ->
  Op.delegation (B b) new_contract (Some account1) >>=? fun delegation ->
  Block.bake ~operation:delegation b >>=? fun b ->
  let expected_new_staking_balance =
    Test_tez.(initial_staking_balance +! delegated_amount)
  in
  Context.Delegate.staking_balance (B b) account1
  >>=? fun new_staking_balance ->
  Assert.equal_tez ~loc:__LOC__ new_staking_balance expected_new_staking_balance
  >>=? fun () ->
  (* Bake one cycle to update the frozen deposits *)
  Block.bake_until_cycle_end b >>=? fun b ->
  let expected_new_frozen_deposits =
    Test_tez.(
      initial_frozen_deposits
      +! delegated_amount
         *! Int64.of_int constants.frozen_deposits_percentage
         /! 100L)
  in
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun new_frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ new_frozen_deposits expected_new_frozen_deposits
  >>=? fun () ->
  let cycles_to_bake =
    2 * (constants.preserved_cycles + constants.max_slashing_period)
  in
  let rec loop b n =
    if n = 0 then return b
    else
      Block.bake_until_cycle_end ~policy:(By_account account1) b >>=? fun b ->
      Context.Delegate.current_frozen_deposits (B b) account1
      >>=? fun frozen_deposits ->
      Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_new_frozen_deposits
      >>=? fun () -> loop b (pred n)
  in
  (* Check that frozen deposits do not change for a sufficient period of
     time *)
  loop b cycles_to_bake >>=? fun _b -> return_unit

let test_frozen_deposits_with_overdelegation () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  (* - [account1] and [account2] give their spendable balance to [new_account]
     - [new_account] overdelegates to [account1] *)
  Context.Delegate.staking_balance (B genesis) account1
  >>=? fun initial_staking_balance ->
  Context.Delegate.staking_balance (B genesis) account2
  >>=? fun initial_staking_balance' ->
  Context.Delegate.current_frozen_deposits (B genesis) account1
  >>=? fun initial_frozen_deposits ->
  Context.Contract.balance (B genesis) contract1 >>=? fun amount ->
  Context.Contract.balance (B genesis) contract2 >>=? fun amount' ->
  let new_account = (Account.new_account ()).pkh in
  let new_contract = Contract.implicit_contract new_account in
  Op.transaction (B genesis) contract1 new_contract amount >>=? fun transfer1 ->
  Op.transaction (B genesis) contract2 new_contract amount'
  >>=? fun transfer2 ->
  Block.bake ~operations:[transfer1; transfer2] genesis >>=? fun b ->
  let expected_new_staking_balance =
    Test_tez.(initial_staking_balance -! amount)
  in
  Context.Delegate.staking_balance (B b) account1
  >>=? fun new_staking_balance ->
  Assert.equal_tez ~loc:__LOC__ new_staking_balance expected_new_staking_balance
  >>=? fun () ->
  let expected_new_staking_balance' =
    Test_tez.(initial_staking_balance' -! amount')
  in
  Context.Delegate.staking_balance (B b) account2
  >>=? fun new_staking_balance' ->
  Assert.equal_tez
    ~loc:__LOC__
    new_staking_balance'
    expected_new_staking_balance'
  >>=? fun () ->
  Op.delegation (B b) new_contract (Some account1) >>=? fun delegation ->
  Block.bake ~operation:delegation b >>=? fun b ->
  Context.Delegate.staking_balance (B b) account1
  >>=? fun new_staking_balance ->
  let expected_new_staking_balance =
    Test_tez.(initial_frozen_deposits +! amount +! amount')
  in
  Assert.equal_tez ~loc:__LOC__ new_staking_balance expected_new_staking_balance
  >>=? fun () ->
  (* Finish the cycle to update the frozen deposits *)
  Block.bake_until_cycle_end b >>=? fun b ->
  Context.Delegate.full_balance (B b) account1
  >>=? fun expected_new_frozen_deposits ->
  (* the equality follows from the definition of active stake in
     [Delegate.select_distribution_for_cycle]. *)
  assert (initial_frozen_deposits = expected_new_frozen_deposits) ;
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun new_frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ new_frozen_deposits expected_new_frozen_deposits
  >>=? fun () ->
  let cycles_to_bake =
    2 * (constants.preserved_cycles + constants.max_slashing_period)
  in
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_new_frozen_deposits
  >>=? fun () ->
  let rec loop b n =
    if n = 0 then return b
    else
      Block.bake_until_cycle_end ~policy:(By_account account1) b >>=? fun b ->
      Context.Delegate.current_frozen_deposits (B b) account1
      >>=? fun frozen_deposits ->
      Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_new_frozen_deposits
      >>=? fun () -> loop b (pred n)
  in
  (* Check that frozen deposits do not change for a sufficient period of
     time *)
  loop b cycles_to_bake >>=? fun _b -> return_unit

let test_set_limit_with_overdelegation () =
  let constants = {constants with frozen_deposits_percentage = 10} in
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (contract2, account2)) =
    get_first_2_accounts_contracts contracts
  in
  (* - [account1] and [account2] will give 80% of their balance to
       [new_account]
     - [new_account] will overdelegate to [account1] but [account1] will set
       its frozen deposits limit to 15% of its stake *)
  Context.Delegate.staking_balance (B genesis) account1
  >>=? fun initial_staking_balance ->
  Context.Delegate.staking_balance (B genesis) account2
  >>=? fun initial_staking_balance' ->
  let amount = Test_tez.(initial_staking_balance *! 8L /! 10L) in
  let amount' = Test_tez.(initial_staking_balance' *! 8L /! 10L) in
  let limit = Test_tez.(initial_staking_balance *! 15L /! 100L) in
  let new_account = (Account.new_account ()).pkh in
  let new_contract = Contract.implicit_contract new_account in
  Op.transaction (B genesis) contract1 new_contract amount >>=? fun transfer1 ->
  Op.transaction (B genesis) contract2 new_contract amount'
  >>=? fun transfer2 ->
  Block.bake ~operations:[transfer1; transfer2] genesis >>=? fun b ->
  Op.set_deposits_limit (B b) contract1 (Some limit) >>=? fun set_deposits ->
  Block.bake ~operation:set_deposits b >>=? fun b ->
  let expected_new_staking_balance =
    Test_tez.(initial_staking_balance -! amount)
  in
  Context.Delegate.staking_balance (B b) account1
  >>=? fun new_staking_balance ->
  Assert.equal_tez ~loc:__LOC__ new_staking_balance expected_new_staking_balance
  >>=? fun () ->
  let expected_new_staking_balance' =
    Test_tez.(initial_staking_balance' -! amount')
  in
  Context.Delegate.staking_balance (B b) account2
  >>=? fun new_staking_balance' ->
  Assert.equal_tez
    ~loc:__LOC__
    new_staking_balance'
    expected_new_staking_balance'
  >>=? fun () ->
  Op.delegation (B b) new_contract (Some account1) >>=? fun delegation ->
  Block.bake ~operation:delegation b >>=? fun b ->
  (* Finish the cycle to update the frozen deposits *)
  Block.bake_until_cycle_end b >>=? fun b ->
  let expected_new_frozen_deposits = limit in
  Context.Delegate.current_frozen_deposits (B b) account1
  >>=? fun frozen_deposits ->
  Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_new_frozen_deposits
  >>=? fun () ->
  let cycles_to_bake =
    2 * (constants.preserved_cycles + constants.max_slashing_period)
  in
  let rec loop b n =
    if n = 0 then return b
    else
      Block.bake_until_cycle_end ~policy:(By_account account1) b >>=? fun b ->
      Context.Delegate.current_frozen_deposits (B b) account1
      >>=? fun frozen_deposits ->
      Assert.equal_tez ~loc:__LOC__ frozen_deposits expected_new_frozen_deposits
      >>=? fun () -> loop b (pred n)
  in
  (* Check that frozen deposits do not change for a sufficient period of
     time *)
  loop b cycles_to_bake >>=? fun _b -> return_unit

(** This test fails when [to_cycle] in [Delegate.freeze_deposits] is smaller than
   [new_cycle + preserved_cycles]. *)
let test_error_is_thrown_when_smaller_upper_bound_for_frozen_window () =
  Context.init_with_constants constants 2 >>=? fun (genesis, contracts) ->
  let ((contract1, account1), (contract2, _account2)) =
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
  (* [account2] delegates (through [new_account]) to [account1] its spendable
     balance. The point is to make [account1] have a lot of staking balance so
     that, after [preserved_cycles] when the active stake reflects this increase
     in staking balance, its [maximum_stake_to_be_deposited] is bigger than the frozen
     deposit which is computed on a smaller window because [to_cycle] is smaller
     than [new_cycle + preserved_cycles]. *)
  Context.Contract.balance (B genesis) contract2 >>=? fun delegated_amount ->
  let new_account = Account.new_account () in
  let new_contract = Contract.implicit_contract new_account.pkh in
  Op.transaction (B genesis) contract2 new_contract delegated_amount
  >>=? fun transfer ->
  Block.bake ~operation:transfer genesis >>=? fun b ->
  Op.delegation (B b) new_contract (Some account1) >>=? fun delegation ->
  Block.bake ~operation:delegation b >>=? fun b ->
  Block.bake_until_cycle_end b >>=? fun b ->
  (* After 1 cycle, namely, at cycle 2, [account1] transfers all its spendable
     balance. *)
  Context.Contract.balance (B b) contract1 >>=? fun balance1 ->
  Op.transaction (B b) contract1 contract2 balance1 >>=? fun operation ->
  Block.bake ~operation b >>=? fun b ->
  Block.bake_until_n_cycle_end constants.preserved_cycles b >>=? fun _ ->
  (* By this time, after [preserved_cycles] passed after [account1] has emptied
        its spendable balance, because [account1] had a big staking balance at
        cycle 0, at this cycle it has a big active stake, and so its
        [maximum_stake_to_be_deposited] too is bigger than [frozen_deposits.current_amount],
        so the variable [to_freeze] in [freeze_deposits] is positive.
     Because the spendable balance of [account1] is 0, an error "Underflowing
        subtraction" is raised at the end of the cycle when updating the balance by
        subtracting [to_freeze] in [freeze_deposits].
     Note that by taking [to_cycle] is [new_cycle + preserved_cycles],
        [frozen_deposits.current_amount] can no longer be smaller
        than [maximum_stake_to_be_deposited], that is, the invariant
        maximum_stake_to_be_deposited <= frozen_deposits + balance is preserved.
  *)
  return_unit

let tests =
  Tztest.
    [
      tztest "test invariants" `Quick test_invariants;
      tztest "set deposits limit to 0%" `Quick (test_set_limit 0);
      tztest "set deposits limit to 5%" `Quick (test_set_limit 5);
      tztest
        "cannot bake with zero deposits"
        `Quick
        test_cannot_bake_with_zero_deposits;
      tztest
        "deposits after stake removal"
        `Quick
        test_deposits_after_stake_removal;
      tztest
        "unfreeze deposits after deactivation"
        `Quick
        test_unfreeze_deposits_after_deactivation;
      tztest
        "frozen deposits with delegation"
        `Quick
        test_frozen_deposits_with_delegation;
      tztest
        "test frozen deposits with overdelegation"
        `Quick
        test_frozen_deposits_with_overdelegation;
      tztest
        "test set limit with overdelegation"
        `Quick
        test_set_limit_with_overdelegation;
      tztest
        "test error is thrown when the frozen window is smaller"
        `Quick
        test_error_is_thrown_when_smaller_upper_bound_for_frozen_window;
    ]
