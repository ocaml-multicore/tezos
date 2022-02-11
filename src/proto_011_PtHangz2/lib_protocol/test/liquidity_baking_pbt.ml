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
    Component:    pbt for liquidity baking
    Invocation:   [QCHECK_SEED=<seed>] dune exec src/proto_011_PtHangz2/lib_protocol/test/liquidity_baking_pbt.exe
    Subject:      Test liquidity baking contracts using randomly generated inputs.
*)

open Protocol
open Alpha_context
open Test_tez
open Liquidity_baking_machine

(** We use the “machines” provided by the {! Liquidity_baking_machine}
    module.  Because using the [ConcreteMachine] (hence, the {!
    ValidationMachine} too) is slow, we implement the following
    test-suit architecture:

    - One {v QCheck v}-based test is used to validate consistency of
      the {! SymbolicMachine} wrt. the [ConcreteMachine], thanks to
      the {! ValidationMachine}.
    - The rest of the tests use the {! SymbolicMachine} in order to be
      more effective. *)

(** [all_true l] waits for all promises of [l], and returns [true] iff
    they all resolve to [true]. *)
let all_true = List.for_all_ep Fun.id

let extract_qcheck_tzresult : unit tzresult Lwt.t -> bool =
 fun p ->
  match Lwt_main.run p with
  | Ok () -> true
  | Error trace -> QCheck.Test.fail_reportf "@\n%a@." pp_print_trace trace

let rec run_and_check check scenarios env state =
  match scenarios with
  | step :: rst ->
      let state' = SymbolicMachine.step step env state in
      assert (check state state') ;
      run_and_check check rst env state'
  | [] -> state

let one_balance_decreases c env state state' =
  let xtz = SymbolicMachine.get_xtz_balance c state in
  let tzbtc = SymbolicMachine.get_tzbtc_balance c env state in
  let lqt = SymbolicMachine.get_liquidity_balance c env state in
  let xtz' = SymbolicMachine.get_xtz_balance c state' in
  let tzbtc' = SymbolicMachine.get_tzbtc_balance c env state' in
  let lqt' = SymbolicMachine.get_liquidity_balance c env state' in
  xtz' < xtz || tzbtc' < tzbtc || lqt' < lqt
  || (xtz' = xtz && tzbtc' = tzbtc && lqt' = lqt)

let get_float_balances env state =
  let xtz =
    Int64.to_float @@ SymbolicMachine.get_xtz_balance env.cpmm_contract state
  in
  let tzbtc =
    Int.to_float
    @@ SymbolicMachine.get_tzbtc_balance env.cpmm_contract env state
  in
  let lqt =
    Int.to_float @@ SymbolicMachine.get_cpmm_total_liquidity env state
  in
  (xtz, tzbtc, lqt)

(** [is_remove_liquidity_consistent env state state'] returns [true]
    iff, when the liquidity pool decreased in [state'], then the
    fraction of tzbtc and xtz returned to the liquidity provider is
    lesser or equal than the fraction of lqt burnt. *)
let is_remove_liquidity_consistent env state state' =
  let (xtz, tzbtc, lqt) = get_float_balances env state in
  let (xtz', tzbtc', lqt') = get_float_balances env state' in
  if lqt' < lqt then
    let flqt = (lqt -. lqt') /. lqt in
    let fxtz = (xtz -. xtz') /. xtz in
    let ftzbtc = (tzbtc -. tzbtc') /. tzbtc in
    fxtz <= flqt && ftzbtc <= flqt
  else true

(** [is_share_price_increasing env state state'] returns [true] iff
    the product of supplies (tzbtc, and xtz) increases.

    See https://blog.nomadic-labs.com/progress-report-on-the-verification-of-liquidity-baking-smart-contracts.html#evolution-of-the-product-of-supplies *)
let is_share_price_increasing env state state' =
  let (xtz, tzbtc, lqt) = get_float_balances env state in
  let (xtz', tzbtc', lqt') = get_float_balances env state' in
  xtz *. tzbtc /. (lqt *. lqt) <= xtz' *. tzbtc' /. (lqt' *. lqt')

(** [positive_pools env state] returns [true] iff the three pools of
    the CPMM (as identified in [env]) are strictly positive in
    [state]. *)
let positive_pools env state =
  let xtz = SymbolicMachine.get_xtz_balance env.cpmm_contract state in
  let tzbtc = SymbolicMachine.get_tzbtc_balance env.cpmm_contract env state in
  let lqt = SymbolicMachine.get_cpmm_total_liquidity env state in
  0L < xtz && 0 < tzbtc && 0 < lqt

(** [validate_xtz_balance c env (blk, state)] returns [true] iff the
    tez balance for the contract [c] is the same in [blk] and in
    [state]. *)
let validate_xtz_balance :
    Contract.t -> ValidationMachine.t -> bool tzresult Lwt.t =
 fun contract state ->
  ValidationMachine.Symbolic.get_xtz_balance contract state >>=? fun expected ->
  ValidationMachine.Concrete.get_xtz_balance contract state >>=? fun amount ->
  return (amount = expected)

(** [validate_tzbtc_balance c env (blk, state)] returns [true] iff the
    tzbtc balance for the contract [c] is the same in [blk] and in
    [state]. *)
let validate_tzbtc_balance :
    Contract.t -> Contract.t env -> ValidationMachine.t -> bool tzresult Lwt.t =
 fun contract env state ->
  ValidationMachine.Symbolic.get_tzbtc_balance contract env state
  >>=? fun expected ->
  ValidationMachine.Concrete.get_tzbtc_balance contract env state
  >>=? fun amount -> return (expected = amount)

(** [validate_liquidity_balance c env (blk, state)] returns [true] if
    the contract [c] holds the same amount of liquidity in [blk] and
    [state]. *)
let validate_liquidity_balance :
    Contract.t -> Contract.t env -> ValidationMachine.t -> bool tzresult Lwt.t =
 fun contract env state ->
  ValidationMachine.Symbolic.get_liquidity_balance contract env state
  >>=? fun expected ->
  ValidationMachine.Concrete.get_liquidity_balance contract env state
  >>=? fun amount -> return (expected = amount)

(** [validate_balances c env (blk, state)] returns true iff the
    contract [c] holds the same amount of tez, tzbtc and liquidity in
    [blk] and [state]. *)
let validate_balances :
    Contract.t -> Contract.t env -> ValidationMachine.t -> bool tzresult Lwt.t =
 fun contract env combined_state ->
  all_true
    [
      validate_xtz_balance contract combined_state;
      validate_tzbtc_balance contract env combined_state;
      validate_liquidity_balance contract env combined_state;
    ]

(** [validate_cpmm_total_liquidity env state] returns true iff the
    CPMM has distributed the same amount of liquidity tokens in its
    concrete and symbolic parts of [state]. *)
let validate_cpmm_total_liquidity env state =
  ValidationMachine.Concrete.get_cpmm_total_liquidity env state
  >>=? fun concrete_cpmm_total_liquidity ->
  ValidationMachine.Symbolic.get_cpmm_total_liquidity env state
  >>=? fun ghost_cpmm_total_liquidity ->
  return (concrete_cpmm_total_liquidity = ghost_cpmm_total_liquidity)

(** [validate_consistency env (blk, state)] checks if the accounts in
    [env] (the CPMM and the implicit accounts) share the same balances
    in [blk] and [state]. *)
let validate_consistency :
    Contract.t env -> ValidationMachine.t -> bool tzresult Lwt.t =
 (* We do not try to validate the xtz balance of [holder] in this
    function.  Indeed, they are hard to predict due to allocation
    fees, and security deposits. *)
 fun env state ->
  all_true
    (validate_cpmm_total_liquidity env state
     ::
     validate_balances env.cpmm_contract env state
     ::
     List.map
       (fun account -> validate_balances account env state)
       env.implicit_accounts)

(** [validate_storage env blk] returns [true] iff the storage of the
    CPMM contract is consistent wrt. to its actual balances (tez,
    tzbtc, and liquidity). *)
let validate_storage :
    Contract.t env -> ConcreteMachine.t -> bool tzresult Lwt.t =
 fun env blk ->
  Cpmm_repr.Storage.get (B blk) ~contract:env.cpmm_contract
  >>=? fun cpmm_storage ->
  all_true
    [
      (* 1. Check the CPMM's [xtzPool] is equal to the actual CPMM balance *)
      ( ConcreteMachine.get_xtz_balance env.cpmm_contract blk
      >>=? fun cpmm_xtz -> return (cpmm_xtz = Tez.to_mutez cpmm_storage.xtzPool)
      );
      (* 2. Check the CPMM’s [lqtTotal] is correct wrt. liquidity contract *)
      ( Lqt_fa12_repr.Storage.get (B blk) ~contract:env.liquidity_contract
      >>=? fun liquidity_storage ->
        return (cpmm_storage.lqtTotal = liquidity_storage.totalSupply) );
      (* 3. Check the CPMM’s [tokenPool] is correct *)
      ( ConcreteMachine.get_tzbtc_balance env.cpmm_contract env blk
      >>=? fun cpmm_tzbtc ->
        return (Z.to_int cpmm_storage.tokenPool = cpmm_tzbtc) );
    ]

(** [machine_validation_tests] is a list of asynchronous tests aiming
    at asserting the correctness and consistencies of the machines
    themselves. *)
let machine_validation_tests =
  [
    QCheck.Test.make
      ~count:10
      ~name:"Concrete/Symbolic Consistency"
      (Liquidity_baking_generator.arb_scenario 1_000_000 1_000_000 10)
      (fun (specs, scenario) ->
        extract_qcheck_tzresult
          (let invariant = validate_consistency in
           ValidationMachine.build ~invariant specs >>=? fun (state, env) ->
           ValidationMachine.run ~invariant scenario env state >>=? fun _ ->
           return_unit));
    QCheck.Test.make
      ~count:10
      ~name:"Storage consistency"
      (Liquidity_baking_generator.arb_scenario 1_000_000 1_000_000 10)
      (fun (specs, scenario) ->
        extract_qcheck_tzresult
          (let invariant = validate_storage in
           ConcreteMachine.build ~invariant specs >>=? fun (state, env) ->
           ConcreteMachine.run ~invariant scenario env state >>=? fun _ ->
           return_unit));
    QCheck.Test.make
      ~count:100_000
      ~name:"Positive pools"
      (Liquidity_baking_generator.arb_scenario 1_000_000 1_000_000 50)
      (fun (specs, scenario) ->
        extract_qcheck_tzresult
          (let invariant = positive_pools in
           let (state, env) = SymbolicMachine.build ~invariant specs in
           let _ = SymbolicMachine.run ~invariant scenario env state in
           return_unit));
  ]

(** [economic_tests] is a list of asynchronous tests aiming at
    asserting the good economic properties of the Liquidity Baking
    feature. *)
let economic_tests =
  [
    QCheck.Test.make
      ~count:100_000
      ~name:"No global gain"
      (Liquidity_baking_generator.arb_adversary_scenario 1_000_000 1_000_000 50)
      (fun (specs, attacker, scenario) ->
        let (state, env) = SymbolicMachine.build ~subsidy:0L specs in
        let _ =
          run_and_check (one_balance_decreases attacker env) scenario env state
        in
        true);
    QCheck.Test.make
      ~count:100_000
      ~name:"Remove liquidities is consistent"
      (Liquidity_baking_generator.arb_scenario 1_000_000 1_000_000 50)
      (fun (specs, scenario) ->
        let (state, env) = SymbolicMachine.build ~subsidy:0L specs in
        let _ =
          run_and_check (is_remove_liquidity_consistent env) scenario env state
        in
        true);
    QCheck.Test.make
      ~count:100_000
      ~name:"Share price only increases"
      (Liquidity_baking_generator.arb_scenario 1_000_000 1_000_000 50)
      (fun (specs, scenario) ->
        let (state, env) = SymbolicMachine.build ~subsidy:0L specs in
        let _ =
          run_and_check (is_share_price_increasing env) scenario env state
        in
        true);
  ]

let _ =
  let open Lib_test.Qcheck_helpers in
  Alcotest.run
    "Liquidity baking PBT"
    [
      ("Machines Cross-Validation", qcheck_wrap machine_validation_tests);
      ("Economic Properties", qcheck_wrap economic_tests);
    ]
