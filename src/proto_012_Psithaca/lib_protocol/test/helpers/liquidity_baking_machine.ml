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

open Protocol
open Alpha_context

(** To implement the interface of this module, as described and
    documented in the related MLI file, we rely on the OCaml module
    system. More precisely, most of the implementation of the two
    public machines ([ValidationMachine] and [SymbolicMachine]) is
    derived by means of functors.

    The machines provide two key functions which can be used in a
    test suite:

      - [M.build specs] which allows to construct an initial state of
        a machine [M] that satisfies the properties described by
        [specs] (along with the so-called “environment” of the
        machine)
      - [M.step s env state] (resp. [M.run]) which allows to execute a
        so-called scenario [step] (resp. a sequence of [step]s, {i
        i.e.}, a complete scenario) by the machine [M] from the state
        [state].

     The module is organized as follows:

       1. We introduce the necessary abstractions we later use to
          specify the properties the initial state of a given machine
          needs to satisfy (most notably the [specs] type).
       2. Then, we introduce the [step] type, which describes the
          various actions we can make a machine perform as part of a
          more complete scenario.
       3. We introduce the [MACHINE] module type which lists the
          necessary types and functions we need to derive a machine
          capable of executing scenarios, and the [Machine.Make]
          functor that we can use to derive such a machine
          automatically.
       4. We introduce the [MACHINE_WITH_INIT] module type which is a
          superset of [MACHINE], extended with an [init] function
          (analogous to {! Context.init}) to create an initial, mostly
          blank state, and the [MachineBuilder.Make] functor that we
          can use to derive a machine with a [build] function.
       5. We construct the [ConcreteMachine], that allows to
          asynchronously execute scenarios against the Tezos
          blockchain.
       6. We implement the [AbstractMachine.Make] functor, which we
          can use to construct machines that can simulate the
          execution scenarios completely off-chains, by reimplementing
          the LB features logic in pure OCaml.
       7. We use [AbstractMachine.Make] to create the [SymbolicMachine].
       8. We use the [AbstractMachine.Make] functor in conjuction with
          the [ConcreteMachine] to introduce the [ValidationMachine].

        _
       / \     A warning for developers willing to modify this module:
      / | \    dealing with the subsidy of the Liquidity Baking (LB)
     /  ·  \   feature is probably the main source of complexity and
    /_______\  fragility of this module.

    At several places (marked with a /!\ note), we need to predict the
    xtz pool of the CPMM contract, in order to compute the amount of
    tzBTC token it will provide or request. To make this prediction,
    we need to determine how many blocks have been/will be baked. This
    means that each time we modify the code of the machine functors,
    we will probably have to modify the code marked with /!\ too.

    To reduce the potential to get things wrong, we have introduced
    constants to prevent the use of “magic numbers” (numbers whose
    meaning cannot be guessed only by looking at the formula). The
    value of these constants is not statically checked, so pay extra
    attention before modifying them.

    Ideally, we could probably compute these magic numbers using a
    dedicated machine, whose purpose would be to count the number of
    call to the [bake] function. For the sake of simplicity, we do not
    do it currently. *)

(** The number of blocks baked in order to execute the {!
    AddLiquidity} step. *)
let blocks_per_add_liquidity_step = 2L

(** The number of blocks baked by the [init] function. Since
    Tenderbake, we need to compensate for deposits, so the number is
    no longer constant. It is linear wrt. the number of accounts. *)
let blocks_during_init len = Int64.add 3L len

(** The number of blocks baked by the [mint_tzbtc] functions *)
let blocks_per_mint_tzbtc = 1L

(** A timestamp “far in the future” which should not be exceeded when
    running tests. *)
let far_future = Alpha_context.Script_timestamp.of_zint (Z.of_int 42_000)
(* Hypothesis: the tests start at timestamp 0, and 42000 is
   “big enough.” *)

(* --------------------------------------------------------------------------- *)

(** {1 Miscellaneous Helpers} *)

let is_implicit_exn account =
  match Contract.is_implicit account with Some k -> k | _ -> assert false

module List_helpers = struct
  let rec zip l r =
    match (l, r) with
    | (xl :: rstl, xr :: rstr) -> (xl, xr) :: zip rstl rstr
    | _ -> []

  let nth_exn l n =
    match List.nth l n with
    | Some x -> x
    | _ -> raise (Invalid_argument "nth_exn")

  let assoc_exn c l =
    match List.assoc ~equal:( = ) c l with
    | Some x -> x
    | _ -> raise (Invalid_argument "assoc_exn")
end

(* --------------------------------------------------------------------------- *)

(** {1 Characterizing Initial Machines States} *)

(** In order to run so-called scenarios against our machines, we first
    need to characterize their initial state. *)

type xtz = int64

type tzbtc = int

type liquidity = int

type balances = {xtz : xtz; tzbtc : tzbtc; liquidity : liquidity}

let pp_balances fmt b =
  Format.fprintf
    fmt
    "@[<h>{xtz = %a; tzbtc = %d; liquidity = %d}@]"
    Tez.pp
    (Tez.of_mutez_exn b.xtz)
    b.tzbtc
    b.liquidity

let xtz {xtz; _} = xtz

type specs = {
  cpmm_min_xtz_balance : xtz;
  cpmm_min_tzbtc_balance : tzbtc;
  accounts_balances : balances list;
}

let pp_specs fmt specs =
  Format.(
    fprintf
      fmt
      "@[<v>{@   @[<v>cpmm = {min_xtz = %a; min_tzbtc = %d}@ @[<v 2>accounts = \
       [@ %a@ ]@]@]@ }@]"
      Tez.pp
      (Tez.of_mutez_exn specs.cpmm_min_xtz_balance)
      specs.cpmm_min_tzbtc_balance
      (pp_print_list ~pp_sep:pp_print_space pp_balances)
      specs.accounts_balances)

(* --------------------------------------------------------------------------- *)

(** {1 Scenario [step] }*)

type 'a step =
  | SellTzBTC of {source : 'a; destination : 'a; tzbtc_deposit : tzbtc}
  | BuyTzBTC of {source : 'a; destination : 'a; xtz_deposit : xtz}
  | AddLiquidity of {source : 'a; destination : 'a; xtz_deposit : xtz}
  | RemoveLiquidity of {source : 'a; destination : 'a; lqt_burned : liquidity}

let pp_step pp_contract fmt = function
  | SellTzBTC p ->
      Format.(
        fprintf
          fmt
          "@[<h>SellTzBTC(%a, %dtz₿, %a)@]"
          pp_contract
          p.source
          p.tzbtc_deposit
          pp_contract
          p.destination)
  | BuyTzBTC p ->
      Format.(
        fprintf
          fmt
          "@[<h>BuyTzBTC(%a, %aꜩ, %a)@]"
          pp_contract
          p.source
          Tez.pp
          (Tez.of_mutez_exn p.xtz_deposit)
          pp_contract
          p.destination)
  | AddLiquidity p ->
      Format.(
        fprintf
          fmt
          "@[<h>AddLiquidity(%a, %aꜩ, %a)@]"
          pp_contract
          p.source
          Tez.pp
          (Tez.of_mutez_exn p.xtz_deposit)
          pp_contract
          p.destination)
  | RemoveLiquidity p ->
      Format.(
        fprintf
          fmt
          "@[<h>RemoveLiquidity(%a, %d lqt, %a)@]"
          pp_contract
          p.source
          p.lqt_burned
          pp_contract
          p.destination)

type contract_id =
  | Cpmm
  | Holder
  | TzBTC
  | TzBTCAdmin
  | Liquidity
  | LiquidityAdmin
  | ImplicitAccount of int

let contract_id_to_string = function
  | Holder -> "holder"
  | Cpmm -> "cpmm"
  | TzBTC -> "tzbtc"
  | TzBTCAdmin -> "tzbtc_admin"
  | Liquidity -> "lqt"
  | LiquidityAdmin -> "lqt_admin"
  | ImplicitAccount i -> Format.sprintf "#%d" i

let pp_contract_id fmt c = Format.(fprintf fmt "[%s]" (contract_id_to_string c))

(* --------------------------------------------------------------------------- *)

(** {1 Machines} *)

(** {2 Machine Environment} *)

type 'a env = {
  cpmm_contract : 'a;
  tzbtc_contract : 'a;
  tzbtc_admin : 'a;
  liquidity_contract : 'a;
  liquidity_admin : 'a;
  implicit_accounts : 'a list;
  holder : 'a;
  subsidy : xtz;
}

let refine_contract env = function
  | Cpmm -> env.cpmm_contract
  | TzBTC -> env.tzbtc_contract
  | TzBTCAdmin -> env.tzbtc_admin
  | Liquidity -> env.liquidity_contract
  | LiquidityAdmin -> env.liquidity_admin
  | Holder -> env.holder
  | ImplicitAccount i -> List_helpers.nth_exn env.implicit_accounts i

let refine_step env step =
  match step with
  | SellTzBTC p ->
      SellTzBTC
        {
          p with
          source = refine_contract env p.source;
          destination = refine_contract env p.destination;
        }
  | BuyTzBTC p ->
      BuyTzBTC
        {
          p with
          source = refine_contract env p.source;
          destination = refine_contract env p.destination;
        }
  | AddLiquidity p ->
      AddLiquidity
        {
          p with
          source = refine_contract env p.source;
          destination = refine_contract env p.destination;
        }
  | RemoveLiquidity p ->
      RemoveLiquidity
        {
          p with
          source = refine_contract env p.source;
          destination = refine_contract env p.destination;
        }

(** {2 Machine Module Type} *)

module type MACHINE = sig
  type 'a m

  type contract

  type t

  type operation

  val pp_contract : Format.formatter -> contract -> unit

  val ( >>= ) : 'a m -> ('a -> 'b m) -> 'b m

  val fold_m : ('a -> 'b -> 'a m) -> 'a -> 'b list -> 'a m

  val pure : 'a -> 'a m

  val get_balances : contract -> contract env -> t -> balances m

  val get_xtz_balance : contract -> t -> xtz m

  val get_tzbtc_balance : contract -> contract env -> t -> tzbtc m

  val get_liquidity_balance : contract -> contract env -> t -> liquidity m

  val get_cpmm_total_liquidity : contract env -> t -> liquidity m

  val bake :
    invariant:(contract env -> t -> bool m) ->
    baker:contract ->
    operation list ->
    contract env ->
    t ->
    t m

  val transaction : src:contract -> contract -> xtz -> t -> operation m

  val token_to_xtz :
    src:contract -> contract -> tzbtc -> contract env -> t -> operation m

  val xtz_to_token :
    src:contract -> contract -> xtz -> contract env -> t -> operation m

  (* [mint_or_burn_tzbtc contract amount env state] will construct an
     operation to credit or remove [amount] tzbtc tokens to [contract] *)
  val mint_or_burn_tzbtc :
    contract -> liquidity -> contract env -> t -> operation m

  (** [approve_tzbtc contract amount env state] will construct an
      operation to authorize the CPMM contract to spend [amount] tzbtc
      on behalf of [contract] *)
  val approve_tzbtc : contract -> tzbtc -> contract env -> t -> operation m

  val add_liquidity :
    src:contract -> contract -> xtz -> tzbtc -> contract env -> t -> operation m

  val remove_liquidity :
    src:contract -> contract -> liquidity -> contract env -> t -> operation m

  val reveal : Account.t -> t -> operation m
end

(** {2 Tezos Constants} *)

let default_subsidy =
  let open Tezos_protocol_012_Psithaca_parameters in
  Tez.to_mutez @@ Default_parameters.constants_test.liquidity_baking_subsidy

let security_deposit = 640_000_000L

(* When calling [Context.init] with a list of initial balances, the
   sum of these balances should be equal to this constant. *)
let total_xtz = 32_000_000_000_000L

let tzbtc_admin_account : Account.t =
  {
    pkh =
      Signature.Public_key_hash.of_b58check_exn
        "tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx";
    pk =
      Signature.Public_key.of_b58check_exn
        "edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav";
    sk =
      Signature.Secret_key.of_b58check_exn
        "edsk3gUfUPyBSfrS9CCgmCiQsTCHGkviBDusMxDJstFtojtc1zcpsh";
  }

let cpmm_initial_balance = {xtz = 100L; tzbtc = 1; liquidity = 0}

let cpmm_initial_liquidity_supply = 100

(** {2 Machine Functor} *)

module Machine = struct
  module Make (S : MACHINE) = struct
    open S

    let mint_tzbtc destination ~invariant amount env state =
      mint_or_burn_tzbtc destination amount env state >>= fun op ->
      bake ~invariant ~baker:env.holder [op] env state

    let add_liquidity ~invariant src dst xtz_deposit tzbtc_deposit env state =
      approve_tzbtc src tzbtc_deposit env state >>= fun lqt_op ->
      bake ~invariant ~baker:env.holder [lqt_op] env state >>= fun state ->
      add_liquidity ~src dst xtz_deposit tzbtc_deposit env state
      >>= fun cpmm_op -> bake ~invariant ~baker:env.holder [cpmm_op] env state

    let remove_liquidity ~invariant src dst lqt_burned env state =
      remove_liquidity ~src dst lqt_burned env state >>= fun cpmm_op ->
      bake ~invariant ~baker:env.holder [cpmm_op] env state

    let sell_tzbtc ~invariant src dst tzbtc_deposit env state =
      approve_tzbtc src tzbtc_deposit env state >>= fun tzbtc_op ->
      bake ~invariant ~baker:env.holder [tzbtc_op] env state >>= fun state ->
      token_to_xtz ~src dst tzbtc_deposit env state >>= fun cpmm_op ->
      bake ~invariant ~baker:env.holder [cpmm_op] env state

    let buy_tzbtc ~invariant src dst xtz_deposit env state =
      xtz_to_token ~src dst xtz_deposit env state >>= fun cpmm_op ->
      bake ~invariant ~baker:env.holder [cpmm_op] env state

    let check_state_satisfies_specs (env : S.contract env) (state : S.t)
        (specs : specs) =
      let implicit_accounts_targets =
        List_helpers.zip env.implicit_accounts specs.accounts_balances
      in
      fold_m
        (fun _ acc ->
          let expected = List_helpers.assoc_exn acc implicit_accounts_targets in
          get_balances acc env state >>= fun amount ->
          assert (expected = amount) ;
          pure ())
        ()
        env.implicit_accounts
      >>= fun _ ->
      get_tzbtc_balance env.cpmm_contract env state
      >>= fun cpmm_tzbtc_balance ->
      assert (specs.cpmm_min_tzbtc_balance <= cpmm_tzbtc_balance) ;
      get_xtz_balance env.cpmm_contract state >>= fun current_cpmm_xtz ->
      assert (
        Int64.(to_int specs.cpmm_min_xtz_balance <= to_int @@ current_cpmm_xtz)) ;
      pure ()

    (** [predict_required_tzbtc_deposit xtz_deposit env state]
        predicts the tzbtc deposit which will be required by the CPMM
        contract for a deposit of [xtz_deposit].

        This function is used by the machines to make the according
        call to the [approve] entrypoint of the TzBTC contract. *)
    let predict_required_tzbtc_deposit xtz_deposit env state =
      get_xtz_balance env.cpmm_contract state >>= fun xtzPool ->
      (* /!\ We need to take into accounts the number of blocks baked
             to actually call the [add_liquidity] entry point of the
             CPMM. *)
      let xtzPool =
        Tez.of_mutez_exn
          Int64.(add xtzPool (mul blocks_per_add_liquidity_step env.subsidy))
      in
      get_tzbtc_balance env.cpmm_contract env state >>= fun tokenPool ->
      let tokenPool = Z.of_int tokenPool in
      get_cpmm_total_liquidity env state >>= fun lqtTotal ->
      let lqtTotal = Z.of_int lqtTotal in
      let amount = Tez.of_mutez_exn xtz_deposit in
      let (_, tokens_deposited) =
        Cpmm_logic.Simulate_raw.addLiquidity
          ~tokenPool
          ~xtzPool
          ~lqtTotal
          ~amount
      in
      pure (Z.to_int tokens_deposited)

    let step ?(invariant = fun _ _ -> pure true) s env state =
      match s with
      | SellTzBTC {source; destination; tzbtc_deposit} ->
          sell_tzbtc ~invariant source destination tzbtc_deposit env state
      | BuyTzBTC {source; destination; xtz_deposit} ->
          buy_tzbtc ~invariant source destination xtz_deposit env state
      | AddLiquidity {source; destination; xtz_deposit} ->
          predict_required_tzbtc_deposit xtz_deposit env state
          >>= fun tzbtc_deposit ->
          add_liquidity
            ~invariant
            source
            destination
            xtz_deposit
            tzbtc_deposit
            env
            state
      | RemoveLiquidity {source; destination; lqt_burned} ->
          remove_liquidity ~invariant source destination lqt_burned env state

    let run ?(invariant = fun _ _ -> pure true) scenario env state =
      fold_m
        (fun state s -> step ~invariant (refine_step env s) env state)
        state
        scenario
  end
end

let initial_xtz_repartition accounts_balances =
  let distributed_xtz = List.fold_left Int64.add 0L accounts_balances in
  let bootstrap1_xtz = Int64.sub total_xtz distributed_xtz in
  let initial_balances = bootstrap1_xtz :: accounts_balances in
  let n = List.length initial_balances in
  (n, initial_balances)

(* --------------------------------------------------------------------------- *)

(** {1 Machines with a [build] Function} *)

module type MACHINE_WITH_INIT = sig
  include MACHINE

  (** [init balances] will create an “initial” state wherein the
      [balances] have been distributed to [n] implicit contracts ([n]
      being the size of the [balances] list).  This function also
      creates a [holder] implicit account which has the rest of the
      xtz liquidity (the test framework forces the sum of xtz balances
      to be equal to [total_xtz]).  [init] also accepts an optional
      argument [subsidy] to modify the default value of the subsidy
      minted by the protocol in favor of the CPMM. *)
  val init :
    invariant:(contract env -> t -> bool m) ->
    ?subsidy:xtz ->
    xtz list ->
    (t * contract env) m
end

(** [initial_xtz_pool] balances predicts the value of the CPMM’s xtz
    pool just before we start using the [add_liquidity] entrypoint to
    provide to each implicit accounts the necessary liquidity
    tokens. *)
let initial_xtz_pool balances subsidy =
  (* /!\ In addition to the initial CPMM balances, we need to take
         into account the subsidies of each block baked before this
         point, which currently consist in:

           - One call to the [init] function
           - One call to the [mint_tzbtc] function per implicit
             accounts

         If the [build] function changes, this functions needs to be
         updated accordingly. *)
  let len = Int64.of_int (List.length balances) in
  Int64.(
    add
      cpmm_initial_balance.xtz
      (mul
         (add (blocks_during_init len) (mul blocks_per_mint_tzbtc len))
         subsidy))

(** [predict_initial_balances xtz_pool tzbtc_pool lqt_total balances]
    evaluates the extra xtz and tzbtc tokens to add to each balance of
    the list [balances] so that the related implicit accounts can call
    the [add_liquidity] entrypoint in order to have the required
    liquidity token.

    For instance, for a balance [b] such that [b.liquidity = 10], we
    compute [xtz_etra] and [tzbtc_extra] so that the implicit account
    will be able to buy [10] liquidity tokens, and replace [b] with
    [{b with xtz = b.xtz + xtz_extra; tzbtc = b.tzbtc + tzbtc_extra}]
    in the returned list.

    The implementation of this function is made more complex than it
    should due to the mechanism of subsidy of LB. In particular, it is
    depends on the number of block baked to buy liquidities. *)
let predict_initial_balances balances subsidy =
  let open Z in
  let subsidy_z = of_int64 subsidy in
  (* Due to the roundness of [Z.( / )], it is not straightforward to
     find the inverse of the equation used to compute the number of
     liquidity tokens bought with the [add_liquidity] entrypoint. To
     find the suitable number of xtz to propose in order to buy
     [liquidity_target], we naively search for the correct
     solution. We compute a [xtz_candidate] by ignoring the roundness
     of [Z.( / )], then increment it until it works. *)
  let find_xtz_extra xtz_pool lqt_total liquidity_target =
    let rec aux xtz_candidate =
      let liquidity_z = xtz_candidate * lqt_total / xtz_pool in
      if liquidity_z = liquidity_target then xtz_candidate
      else aux (xtz_candidate + Z.one)
    in
    let xtz_extra_candidate = liquidity_target * xtz_pool / lqt_total in
    aux xtz_extra_candidate
  in
  let rec predict_initial_balances xtz_pool tzbtc_pool lqt_total = function
    | {xtz; tzbtc; liquidity} :: rst ->
        (* balance inputs *)
        (* /!\ We compute two blocks per [add_liquidity] entrypoint,
               hence the two subsidies *)
        let xtz_pool =
          xtz_pool + (Z.of_int64 blocks_per_add_liquidity_step * subsidy_z)
        in
        let xtz_z = of_int64 xtz in
        let tzbtc_z = of_int tzbtc in
        let liquidity_z = of_int liquidity in
        (* compute extra for being able to buy liquidity tokens *)
        let xtz_extra = find_xtz_extra xtz_pool lqt_total liquidity_z in
        let tzbtc_extra = cdiv (xtz_extra * tzbtc_pool) xtz_pool in
        (* compute new balances *)
        let xtz = to_int64 (xtz_z + xtz_extra) in
        let tzbtc = to_int (tzbtc_z + tzbtc_extra) in
        let liquidity = to_int liquidity_z in
        (* new pools *)
        let xtz_pool' = xtz_pool + xtz_extra in
        let tzbtc_pool' = tzbtc_pool + tzbtc_extra in
        let lqt_total' = lqt_total + liquidity_z in
        (* recursion time *)
        {xtz; tzbtc; liquidity}
        :: predict_initial_balances xtz_pool' tzbtc_pool' lqt_total' rst
    | [] -> []
  in
  predict_initial_balances
    (of_int64 @@ initial_xtz_pool balances subsidy)
    (of_int cpmm_initial_balance.tzbtc)
    (of_int cpmm_initial_liquidity_supply)
    balances

module MachineBuilder = struct
  module Make (S : MACHINE_WITH_INIT) = struct
    open S
    include Machine.Make (S)

    let build :
        ?invariant:(S.contract env -> S.t -> bool m) ->
        ?subsidy:xtz ->
        specs ->
        (S.t * S.contract env) m =
     fun ?(invariant = fun _ _ -> pure true)
         ?(subsidy = default_subsidy)
         ({cpmm_min_xtz_balance; accounts_balances; cpmm_min_tzbtc_balance} as
         specs) ->
      let accounts_balances_with_extra =
        predict_initial_balances accounts_balances subsidy
      in
      let xtz_balances_with_extra = List.map xtz accounts_balances_with_extra in
      (* 1. Create an initial context *)
      init ~invariant ~subsidy xtz_balances_with_extra >>= fun (state, env) ->
      invariant env state >>= fun cond ->
      assert cond ;
      (* 2. Provide the initial tzBTC liquidities to implicit accounts *)
      let accounts =
        List_helpers.zip
          env.implicit_accounts
          (List_helpers.zip accounts_balances accounts_balances_with_extra)
      in
      fold_m
        (fun state (address, (_, balances)) ->
          mint_tzbtc ~invariant address balances.tzbtc env state)
        state
        accounts
      >>= fun state ->
      (* 3. Make implicit accounts buy liquidities *)
      fold_m
        (fun state (address, (target_balances, balances_with_extra)) ->
          let xtz = Int64.sub balances_with_extra.xtz target_balances.xtz in
          let tzbtc = balances_with_extra.tzbtc - target_balances.tzbtc in
          add_liquidity ~invariant address address xtz tzbtc env state)
        state
        accounts
      >>= fun state ->
      (* 4. Provide any missing tzbtc tokens to [cpmm_contract], if necessary *)
      get_tzbtc_balance env.cpmm_contract env state
      >>= fun current_cpmm_tzbtc_balance ->
      let tzbtc_missing = cpmm_min_tzbtc_balance - current_cpmm_tzbtc_balance in
      (if 0 < tzbtc_missing then
       (* 4.1. Provide the tokens to the [bootstrap1] account, as a
          temporary holder for CPMM missing tzBTC balance *)
       mint_tzbtc ~invariant env.holder tzbtc_missing env state >>= fun state ->
       (* 4.1. Make [bootstrap1] buy some xtz against the appropriate
          amount of tzbtc *)
       sell_tzbtc ~invariant env.holder env.holder tzbtc_missing env state
      else pure state)
      >>= fun state ->
      (* 5. Provide any missing xtz tokens to [cpmm_contract], if necessary *)
      get_xtz_balance env.cpmm_contract state
      >>= fun current_cpmm_xtz_balance ->
      let xtz_missing =
        Int64.sub cpmm_min_xtz_balance current_cpmm_xtz_balance
      in
      (if 0L < xtz_missing then
       transaction ~src:env.holder env.cpmm_contract xtz_missing state
       >>= fun op -> bake ~invariant ~baker:env.holder [op] env state
      else pure state)
      >>= fun state ->
      check_state_satisfies_specs env state specs >>= fun _ -> pure (state, env)
  end
end

(* --------------------------------------------------------------------------- *)

module ConcreteBaseMachine :
  MACHINE_WITH_INIT
    with type 'a m = 'a tzresult Lwt.t
     and type contract = Contract.t
     and type t = Block.t = struct
  type 'a m = 'a tzresult Lwt.t

  type contract = Contract.t

  type operation = packed_operation

  type t = Block.t

  let pp_contract = Contract.pp

  let ( >>= ) = ( >>=? )

  let fold_m = Environment.List.fold_left_es

  let pure = Error_monad.return

  let get_xtz_balance contract blk =
    Context.Contract.balance (B blk) contract >>= fun x ->
    pure @@ Tez.to_mutez x

  let get_tzbtc_balance contract env blk =
    Lqt_fa12_repr.Storage.getBalance_opt
      (B blk)
      ~contract:env.tzbtc_contract
      (contract, "default")
    >>=? fun mamount ->
    pure (Option.value (Option.map Z.to_int mamount) ~default:0)

  let get_liquidity_balance contract env blk =
    Lqt_fa12_repr.Storage.getBalance_opt
      (B blk)
      ~contract:env.liquidity_contract
      (contract, "default")
    >>=? fun mamount ->
    pure (Option.value (Option.map Z.to_int mamount) ~default:0)

  let get_cpmm_total_liquidity env blk =
    Cpmm_repr.Storage.get (B blk) ~contract:env.cpmm_contract
    >>=? fun cpmm_storage -> pure @@ Z.to_int cpmm_storage.lqtTotal

  let get_balances contract env blk =
    get_xtz_balance contract blk >>= fun xtz ->
    get_tzbtc_balance contract env blk >>= fun tzbtc ->
    get_liquidity_balance contract env blk >>= fun liquidity ->
    pure {xtz; tzbtc; liquidity}

  let bake ~invariant ~baker ops env blk =
    Incremental.begin_construction
      ~policy:(Block.By_account (is_implicit_exn baker))
      blk
    >>= fun incr ->
    fold_m Incremental.add_operation incr ops >>= fun incr ->
    Incremental.finalize_block incr >>= fun blk ->
    invariant env blk >>= fun cond ->
    assert cond ;
    return blk

  let reveal (account : Account.t) blk = Op.revelation (B blk) account.pk

  let transaction ~src dst amount blk =
    Op.transaction (B blk) src dst (Tez.of_mutez_exn amount)

  let token_to_xtz ~src dst tzbtc_deposit env blk =
    Cpmm_repr.transaction
      (B blk)
      ~src
      ~contract:env.cpmm_contract
      (Cpmm_repr.Parameter.TokenToXtz
         {
           to_ = dst;
           minXtzBought = Tez.zero;
           tokensSold = Z.of_int tzbtc_deposit;
           deadline = far_future;
         })

  let xtz_to_token ~src dst amount env blk =
    Cpmm_repr.transaction
      (B blk)
      ~src
      ~contract:env.cpmm_contract
      (Cpmm_repr.Parameter.XtzToToken
         {to_ = dst; minTokensBought = Z.zero; deadline = far_future})
      ~amount:(Tez.of_mutez_exn amount)

  let approve_tzbtc src tzbtc env blk =
    let maxTokensDeposited = Z.of_int tzbtc in
    Lqt_fa12_repr.transaction
      (B blk)
      ~src
      ~contract:env.tzbtc_contract
      (Lqt_fa12_repr.Parameter.Approve
         {spender = env.cpmm_contract; value = maxTokensDeposited})

  let mint_or_burn_tzbtc target amount env blk =
    let quantity = Z.of_int amount in
    let ctxt = Context.B blk in
    Lqt_fa12_repr.transaction
      ctxt
      ~src:env.tzbtc_admin
      ~contract:env.tzbtc_contract
      (Lqt_fa12_repr.Parameter.mintOrBurn {target; quantity})

  let add_liquidity ~src dst xtz_deposit tzbtc_deposit env blk =
    let amount = Tez.of_mutez_exn xtz_deposit in
    let maxTokensDeposited = Z.of_int tzbtc_deposit in
    Cpmm_repr.transaction
      (B blk)
      ~src
      ~contract:env.cpmm_contract
      ~amount
      (Cpmm_repr.Parameter.AddLiquidity
         {
           owner = dst;
           maxTokensDeposited;
           minLqtMinted = Z.zero;
           deadline = far_future;
         })

  let remove_liquidity ~src dst lqt_burned env blk =
    let lqtBurned = Z.of_int lqt_burned in
    Cpmm_repr.transaction
      (B blk)
      ~src
      ~contract:env.cpmm_contract
      (Cpmm_repr.Parameter.RemoveLiquidity
         {
           to_ = dst;
           lqtBurned;
           minXtzWithdrawn = Tez.zero;
           minTokensWithdrawn = Z.zero;
           deadline = far_future;
         })

  let reveal_tzbtc_admin ~invariant env state =
    Account.add_account tzbtc_admin_account ;
    transaction ~src:env.holder env.tzbtc_admin 1L state >>= fun op1 ->
    bake ~invariant ~baker:env.holder [op1] env state >>= fun state ->
    reveal tzbtc_admin_account state >>= fun op2 ->
    bake ~invariant ~baker:env.holder [op2] env state

  let init ~invariant ?subsidy accounts_balances =
    let liquidity_baking_subsidy = Option.map Tez.of_mutez_exn subsidy in
    let (n, initial_balances) = initial_xtz_repartition accounts_balances in
    Context.init
      n
      ~consensus_threshold:0
      ~initial_balances
      ~cost_per_byte:Tez.zero
      ~endorsing_reward_per_slot:Tez.zero
      ~baking_reward_bonus_per_slot:Tez.zero
      ~baking_reward_fixed_portion:Tez.zero
      ~origination_size:0
      ~blocks_per_cycle:10_000l
      ?liquidity_baking_subsidy
    >>= function
    | (blk, holder :: accounts) ->
        let ctxt = Context.B blk in
        Context.get_liquidity_baking_cpmm_address ctxt >>= fun cpmm_contract ->
        Context.Contract.storage ctxt cpmm_contract >>= fun storage ->
        let storage = Cpmm_repr.Storage.of_expr_exn (Micheline.root storage) in
        let tzbtc_contract = storage.tokenAddress in
        let liquidity_contract = storage.lqtAddress in
        Context.Contract.storage ctxt tzbtc_contract >>= fun storage ->
        let storage =
          Lqt_fa12_repr.Storage.of_expr_exn (Micheline.root storage)
        in
        let tzbtc_admin = storage.admin in
        Context.Contract.storage ctxt liquidity_contract >>= fun storage ->
        let storage =
          Lqt_fa12_repr.Storage.of_expr_exn (Micheline.root storage)
        in
        let liquidity_admin = storage.admin in
        Context.get_liquidity_baking_subsidy (B blk) >>=? fun subsidy ->
        let env =
          {
            cpmm_contract;
            tzbtc_contract;
            tzbtc_admin;
            liquidity_contract;
            liquidity_admin;
            implicit_accounts = accounts;
            holder;
            subsidy = Tez.to_mutez subsidy;
          }
        in
        reveal_tzbtc_admin ~invariant:(fun _ _ -> pure true) env blk
        >>= fun blk ->
        mint_or_burn_tzbtc env.cpmm_contract cpmm_initial_balance.tzbtc env blk
        >>= fun op ->
        bake ~invariant:(fun _ _ -> pure true) ~baker:env.holder [op] env blk
        >>= fun blk ->
        (* Since Tenderbake, we need to compensate for potential deposits
           related to the consensus. *)
        List.fold_left_i_es
          (fun idx blk contract ->
            match List.nth accounts_balances idx with
            | Some target ->
                get_xtz_balance contract blk >>=? fun balance ->
                let delta = Int64.(sub target balance) in
                if Compare.Int64.(0L = delta) then
                  (* We need to be able to determine the number of
                     blocks baked in the init function (to predict the
                     CPMM balance). So even when there is no delta to
                     compensate with, we bake an empty block. *)
                  bake
                    ~invariant:(fun _ _ -> pure true)
                    ~baker:env.holder
                    []
                    env
                    blk
                else if Compare.Int64.(0L < delta) then
                  transaction ~src:env.holder contract delta blk >>= fun op ->
                  bake
                    ~invariant:(fun _ _ -> pure true)
                    ~baker:env.holder
                    [op]
                    env
                    blk
                else assert false
            | None -> assert false)
          blk
          accounts
        >>=? fun blk ->
        (* We did not check the invariant before, because the CPMM
           contract was in an inconsistent state. More precisely, it
           was supposed to hold tzbtc tokens, while in practice it was
           not. This was solved by the last call to [bake]. *)
        invariant env blk >>= fun cond ->
        assert cond ;
        pure (blk, env)
    | _ -> assert false
end

module ConcreteMachine = struct
  include ConcreteBaseMachine
  include Machine.Make (ConcreteBaseMachine)
  include MachineBuilder.Make (ConcreteBaseMachine)
end

(* --------------------------------------------------------------------------- *)

(** {1 Abstract Machines} *)

type 'a state = {
  cpmm_total_liquidity : liquidity;
  accounts_balances : ('a * balances) list;
}

let refine_state env state =
  {
    cpmm_total_liquidity = state.cpmm_total_liquidity;
    accounts_balances =
      List.map
        (fun (c, b) -> (refine_contract env c, b))
        state.accounts_balances;
  }

let update_balances account f state =
  match List.assoc ~equal:( = ) account state.accounts_balances with
  | Some b ->
      {
        state with
        accounts_balances =
          (account, f b)
          :: List.remove_assoc ~equal:( = ) account state.accounts_balances;
      }
  | _ -> assert false

let update_xtz_balance account f =
  update_balances account (fun b -> {b with xtz = f b.xtz})

let update_tzbtc_balance account f =
  update_balances account (fun b -> {b with tzbtc = f b.tzbtc})

let update_liquidity_balance account f =
  update_balances account (fun b -> {b with liquidity = f b.liquidity})

let transfer_xtz_balance src dest d st =
  update_xtz_balance src (fun b -> Int64.sub b d) st
  |> update_xtz_balance dest (fun b -> Int64.add b d)

let transfer_tzbtc_balance src dest d st =
  update_tzbtc_balance src (fun b -> b - d) st
  |> update_tzbtc_balance dest (fun b -> d + b)

module AbstractMachine = struct
  module type C = sig
    type t

    val pp : Format.formatter -> t -> unit
  end

  module Make (C : C) :
    MACHINE with type 'a m = 'a and type contract = C.t and type t = C.t state =
  struct
    type 'a m = 'a

    type contract = C.t

    type t = C.t state

    type operation = t -> t

    let pp_contract = C.pp

    let ( >>= ) x f = f x

    let pure = Fun.id

    let fold_m = List.fold_left

    let get_balances account state =
      match List.assoc ~equal:( = ) account state.accounts_balances with
      | Some x -> x
      | _ -> assert false

    let get_xtz_balance account state = (get_balances account state).xtz

    let get_tzbtc_balance account _env state =
      (get_balances account state).tzbtc

    let get_liquidity_balance account _env state =
      (get_balances account state).liquidity

    let get_balances account _env state = get_balances account state

    let get_cpmm_total_liquidity _env state = state.cpmm_total_liquidity

    let reveal _pk _state state = state

    let transaction ~src dst amount _ state =
      transfer_xtz_balance src dst amount state

    let xtz_bought tzbtc env state =
      let xtzPool =
        Tez.of_mutez_exn @@ get_xtz_balance env.cpmm_contract state
      in
      let tokenPool =
        Z.of_int @@ get_tzbtc_balance env.cpmm_contract env state
      in
      let tokensSold = Z.of_int tzbtc in
      let (xtz_bought, xtz_net_bought) =
        Cpmm_logic.Simulate_raw.tokenToXtz ~xtzPool ~tokenPool ~tokensSold
      in
      (Z.to_int64 xtz_net_bought, Tez.to_mutez xtz_bought)

    let token_to_xtz ~src dst amount env _ state =
      let (xtz_bought, xtz_net_bought) = xtz_bought amount env state in
      state
      |> transfer_tzbtc_balance src env.cpmm_contract amount
      |> update_xtz_balance env.cpmm_contract (fun b -> Int64.sub b xtz_bought)
      |> update_xtz_balance dst (Int64.add xtz_net_bought)

    let tzbtc_bought env state amount =
      let xtzPool =
        Tez.of_mutez_exn @@ get_xtz_balance env.cpmm_contract state
      in
      let tokenPool =
        Z.of_int @@ get_tzbtc_balance env.cpmm_contract env state
      in
      let amount = Tez.of_mutez_exn amount in
      let (tzbtc_bought, xtz_earnt) =
        Cpmm_logic.Simulate_raw.xtzToToken ~xtzPool ~tokenPool ~amount
      in
      (Z.to_int tzbtc_bought, Z.to_int64 xtz_earnt)

    let xtz_to_token ~src dst amount env _ state =
      let (tzbtc_bought, xtz_earnt) = tzbtc_bought env state amount in
      update_xtz_balance src (fun b -> Int64.sub b amount) state
      |> update_xtz_balance env.cpmm_contract (Int64.add xtz_earnt)
      |> transfer_tzbtc_balance env.cpmm_contract dst tzbtc_bought

    let mint_or_burn_tzbtc target amount _ _ =
      update_tzbtc_balance target (( + ) amount)

    let approve_tzbtc _contract _amount _env _state = Fun.id

    let add_liquidity ~src dst xtz_deposit _tzbtc_deposit env _ state =
      let xtzPool =
        Tez.of_mutez_exn (get_xtz_balance env.cpmm_contract state)
      in
      let tokenPool =
        Z.of_int (get_tzbtc_balance env.cpmm_contract env state)
      in
      let lqtTotal = Z.of_int state.cpmm_total_liquidity in
      let amount = Tez.of_mutez_exn xtz_deposit in
      let (lqt_minted, tokens_deposited) =
        Cpmm_logic.Simulate_raw.addLiquidity
          ~tokenPool
          ~xtzPool
          ~lqtTotal
          ~amount
      in
      let lqt_minted = Z.to_int lqt_minted in
      let tokens_deposited = Z.to_int tokens_deposited in
      let state =
        transfer_xtz_balance src env.cpmm_contract xtz_deposit state
        |> transfer_tzbtc_balance src env.cpmm_contract tokens_deposited
        |> update_liquidity_balance dst (( + ) lqt_minted)
      in
      {
        state with
        cpmm_total_liquidity = state.cpmm_total_liquidity + lqt_minted;
      }

    let remove_liquidity ~src dst lqt_burned env _ state =
      let xtzPool =
        Tez.of_mutez_exn (get_xtz_balance env.cpmm_contract state)
      in
      let tokenPool =
        Z.of_int (get_tzbtc_balance env.cpmm_contract env state)
      in
      let lqtTotal = Z.of_int state.cpmm_total_liquidity in
      let lqtBurned = Z.of_int lqt_burned in
      let (xtz_withdrawn, tokens_withdrawn) =
        Cpmm_logic.Simulate_raw.removeLiquidity
          ~tokenPool
          ~xtzPool
          ~lqtTotal
          ~lqtBurned
      in
      let xtz_withdrawn = Tez.to_mutez xtz_withdrawn in
      let tokens_withdrawn = Z.to_int tokens_withdrawn in
      let state =
        update_xtz_balance dst (fun b -> Int64.add b xtz_withdrawn) state
        |> update_tzbtc_balance dst (( + ) tokens_withdrawn)
        |> update_liquidity_balance src (fun b -> b - lqt_burned)
        |> update_xtz_balance env.cpmm_contract (fun b ->
               Int64.sub b xtz_withdrawn)
        |> update_tzbtc_balance env.cpmm_contract (fun b ->
               b - tokens_withdrawn)
      in
      {
        state with
        cpmm_total_liquidity = state.cpmm_total_liquidity - lqt_burned;
      }

    (* Ideally, we should also deal with the release of security
       deposit, but since our tests are not long enough for this to
       happen, we omit this aspect of the simulation. *)
    let bake ~invariant ~baker operations env state =
      let state =
        update_xtz_balance env.cpmm_contract (Int64.add env.subsidy) state
        |> (fun state -> List.fold_left ( |> ) state operations)
        |> update_xtz_balance baker (fun b -> Int64.sub b security_deposit)
      in
      assert (invariant env state) ;
      state
  end
end

(* --------------------------------------------------------------------------- *)

(** {1 Symbolic Machine} *)

module SymbolicBaseMachine :
  MACHINE_WITH_INIT
    with type 'a m = 'a
     and type contract = contract_id
     and type t = contract_id state = struct
  include AbstractMachine.Make (struct
    type t = contract_id

    let pp = pp_contract_id
  end)

  let init ~invariant:_ ?(subsidy = default_subsidy) accounts_balances =
    let (_, initial_balances) = initial_xtz_repartition accounts_balances in
    let len = Int64.of_int (List.length accounts_balances) in
    match initial_balances with
    | holder_xtz :: accounts ->
        let xtz_cpmm =
          Int64.(
            add cpmm_initial_balance.xtz (mul (blocks_during_init len) subsidy))
        in
        ( {
            cpmm_total_liquidity = cpmm_initial_liquidity_supply;
            accounts_balances =
              (Cpmm, {cpmm_initial_balance with xtz = xtz_cpmm})
              ::
              (Holder, {xtz = holder_xtz; tzbtc = 0; liquidity = 0})
              ::
              (TzBTCAdmin, {xtz = 0L; tzbtc = 0; liquidity = 0})
              ::
              List.mapi
                (fun i xtz ->
                  (ImplicitAccount i, {xtz; tzbtc = 0; liquidity = 0}))
                accounts;
          },
          {
            cpmm_contract = Cpmm;
            tzbtc_contract = TzBTC;
            tzbtc_admin = TzBTCAdmin;
            liquidity_contract = Liquidity;
            liquidity_admin = LiquidityAdmin;
            implicit_accounts =
              List.mapi (fun i _ -> ImplicitAccount i) accounts;
            holder = Holder;
            subsidy;
          } )
    | [] -> assert false
end

module SymbolicMachine = struct
  include SymbolicBaseMachine
  include Machine.Make (SymbolicBaseMachine)
  include MachineBuilder.Make (SymbolicBaseMachine)
end

(* --------------------------------------------------------------------------- *)

(** {1 Validation Machine} *)

module ValidationBaseMachine :
  MACHINE_WITH_INIT
    with type 'a m = 'a ConcreteBaseMachine.m
     and type t = ConcreteBaseMachine.t * Contract.t state
     and type contract = Contract.t = struct
  module GhostMachine = AbstractMachine.Make (struct
    type t = Contract.t

    let pp = Contract.pp
  end)

  type 'a m = 'a ConcreteBaseMachine.m

  type t = ConcreteBaseMachine.t * GhostMachine.t

  type contract = Contract.t

  type operation = ConcreteBaseMachine.operation * GhostMachine.operation

  let pp_contract = Contract.pp

  let ( >>= ) = ConcreteBaseMachine.( >>= )

  let fold_m = ConcreteBaseMachine.fold_m

  let pure = ConcreteBaseMachine.pure

  let get_balances contract env (_, state) =
    pure (GhostMachine.get_balances contract env state)

  let get_xtz_balance contract (_, state) =
    pure (GhostMachine.get_xtz_balance contract state)

  let get_tzbtc_balance contract env (_, state) =
    pure (GhostMachine.get_tzbtc_balance contract env state)

  let get_liquidity_balance contract env (_, state) =
    pure (GhostMachine.get_liquidity_balance contract env state)

  let get_cpmm_total_liquidity env (_, state) =
    pure (GhostMachine.get_cpmm_total_liquidity env state)

  let bake ~invariant ~baker ops env (blk, state) =
    let cops = List.map fst ops in
    let rops = List.map snd ops in
    ConcreteBaseMachine.(
      bake ~invariant:(fun _ _ -> pure true) ~baker cops env blk)
    >>= fun blk ->
    let state =
      GhostMachine.bake ~invariant:(fun _ _ -> true) ~baker rops env state
    in
    invariant env (blk, state) >>= fun cond ->
    assert cond ;
    pure (blk, state)

  let transaction ~src dst xtz (blk, state) =
    ConcreteBaseMachine.transaction ~src dst xtz blk >>= fun cop ->
    pure (cop, GhostMachine.transaction ~src dst xtz state)

  let token_to_xtz ~src dst tzbtc env (blk, state) =
    ConcreteBaseMachine.token_to_xtz ~src dst tzbtc env blk >>= fun cop ->
    pure (cop, GhostMachine.token_to_xtz ~src dst tzbtc env state)

  let xtz_to_token ~src dst xtz env (blk, state) =
    ConcreteBaseMachine.xtz_to_token ~src dst xtz env blk >>= fun cop ->
    pure (cop, GhostMachine.xtz_to_token ~src dst xtz env state)

  let mint_or_burn_tzbtc dst tzbtc env (blk, state) =
    ConcreteBaseMachine.mint_or_burn_tzbtc dst tzbtc env blk >>= fun cop ->
    pure (cop, GhostMachine.mint_or_burn_tzbtc dst tzbtc env state)

  let approve_tzbtc dst tzbtc env (blk, state) =
    ConcreteBaseMachine.approve_tzbtc dst tzbtc env blk >>= fun cop ->
    pure (cop, GhostMachine.approve_tzbtc dst tzbtc env state)

  let add_liquidity ~src dst xtz_deposit tzbtc_deposit env (blk, state) =
    ConcreteBaseMachine.add_liquidity ~src dst xtz_deposit tzbtc_deposit env blk
    >>= fun cop ->
    pure
      ( cop,
        GhostMachine.add_liquidity ~src dst xtz_deposit tzbtc_deposit env state
      )

  let remove_liquidity ~src dst lqt_burned env (blk, state) =
    ConcreteBaseMachine.remove_liquidity ~src dst lqt_burned env blk
    >>= fun cop ->
    pure (cop, GhostMachine.remove_liquidity ~src dst lqt_burned env state)

  let reveal account (blk, state) =
    ConcreteBaseMachine.reveal account blk >>= fun cop ->
    pure (cop, GhostMachine.reveal account state)

  let init ~invariant ?subsidy balances =
    ConcreteBaseMachine.init
      ~invariant:(fun _ _ -> return true)
      ?subsidy
      balances
    >>= fun (blk, env) ->
    let (state, _) =
      SymbolicBaseMachine.init ~invariant:(fun _ _ -> true) ?subsidy balances
    in
    let state = refine_state env state in
    invariant env (blk, state) >>= fun cond ->
    assert cond ;
    pure ((blk, state), env)
end

module ValidationMachine = struct
  include ValidationBaseMachine
  include Machine.Make (ValidationBaseMachine)
  include MachineBuilder.Make (ValidationBaseMachine)

  module Symbolic = struct
    let get_xtz_balance = get_xtz_balance

    let get_tzbtc_balance = get_tzbtc_balance

    let get_liquidity_balance = get_liquidity_balance

    let get_cpmm_total_liquidity = get_cpmm_total_liquidity
  end

  module Concrete = struct
    let get_xtz_balance contract (blk, _) =
      ConcreteMachine.get_xtz_balance contract blk

    let get_tzbtc_balance contract env (blk, _) =
      ConcreteMachine.get_tzbtc_balance contract env blk

    let get_liquidity_balance contract env (blk, _) =
      ConcreteMachine.get_liquidity_balance contract env blk

    let get_cpmm_total_liquidity env (blk, _) =
      ConcreteMachine.get_cpmm_total_liquidity env blk
  end
end
