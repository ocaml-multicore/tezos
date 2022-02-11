(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

type error +=
  | (* `Permanent *) No_deletion of Signature.Public_key_hash.t
  | (* `Temporary *) Active_delegate
  | (* `Temporary *) Current_delegate
  | (* `Permanent *) Empty_delegate_account of Signature.Public_key_hash.t
  | (* `Permanent *) Unregistered_delegate of Signature.Public_key_hash.t
  | (* `Permanent *) Unassigned_validation_slot_for_level of Level_repr.t * int
  | (* `Permanent *)
      Cannot_find_active_stake of {
      cycle : Cycle_repr.t;
      delegate : Signature.Public_key_hash.t;
    }
  | (* `Temporary *) Not_registered of Signature.Public_key_hash.t

let () =
  register_error_kind
    `Permanent
    ~id:"delegate.no_deletion"
    ~title:"Forbidden delegate deletion"
    ~description:"Tried to unregister a delegate"
    ~pp:(fun ppf delegate ->
      Format.fprintf
        ppf
        "Delegate deletion is forbidden (%a)"
        Signature.Public_key_hash.pp
        delegate)
    Data_encoding.(obj1 (req "delegate" Signature.Public_key_hash.encoding))
    (function No_deletion c -> Some c | _ -> None)
    (fun c -> No_deletion c) ;
  register_error_kind
    `Temporary
    ~id:"delegate.already_active"
    ~title:"Delegate already active"
    ~description:"Useless delegate reactivation"
    ~pp:(fun ppf () ->
      Format.fprintf ppf "The delegate is still active, no need to refresh it")
    Data_encoding.empty
    (function Active_delegate -> Some () | _ -> None)
    (fun () -> Active_delegate) ;
  register_error_kind
    `Temporary
    ~id:"delegate.unchanged"
    ~title:"Unchanged delegated"
    ~description:"Contract already delegated to the given delegate"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "The contract is already delegated to the same delegate")
    Data_encoding.empty
    (function Current_delegate -> Some () | _ -> None)
    (fun () -> Current_delegate) ;
  register_error_kind
    `Permanent
    ~id:"delegate.empty_delegate_account"
    ~title:"Empty delegate account"
    ~description:"Cannot register a delegate when its implicit account is empty"
    ~pp:(fun ppf delegate ->
      Format.fprintf
        ppf
        "Delegate registration is forbidden when the delegate\n\
        \           implicit account is empty (%a)"
        Signature.Public_key_hash.pp
        delegate)
    Data_encoding.(obj1 (req "delegate" Signature.Public_key_hash.encoding))
    (function Empty_delegate_account c -> Some c | _ -> None)
    (fun c -> Empty_delegate_account c) ;
  (* Unregistered delegate *)
  register_error_kind
    `Permanent
    ~id:"contract.manager.unregistered_delegate"
    ~title:"Unregistered delegate"
    ~description:"A contract cannot be delegated to an unregistered delegate"
    ~pp:(fun ppf k ->
      Format.fprintf
        ppf
        "The provided public key (with hash %a) is not registered as valid \
         delegate key."
        Signature.Public_key_hash.pp
        k)
    Data_encoding.(obj1 (req "hash" Signature.Public_key_hash.encoding))
    (function Unregistered_delegate k -> Some k | _ -> None)
    (fun k -> Unregistered_delegate k) ;
  (* Unassigned_validation_slot_for_level *)
  register_error_kind
    `Permanent
    ~id:"delegate.unassigned_validation_slot_for_level"
    ~title:"Unassigned validation slot for level"
    ~description:
      "The validation slot for the given level is not assigned. Nobody payed \
       for that slot, or the level is either in the past or too far in the \
       future (further than the validatiors_selection_offset constant)"
    ~pp:(fun ppf (l, slot) ->
      Format.fprintf
        ppf
        "The validation slot %i for the level %a is not assigned. Nobody payed \
         for that slot, or the level is either in the past or too far in the \
         future (further than the validatiors_selection_offset constant)"
        slot
        Level_repr.pp
        l)
    Data_encoding.(obj2 (req "level" Level_repr.encoding) (req "slot" int31))
    (function
      | Unassigned_validation_slot_for_level (l, s) -> Some (l, s) | _ -> None)
    (fun (l, s) -> Unassigned_validation_slot_for_level (l, s)) ;
  register_error_kind
    `Permanent
    ~id:"delegate.cannot_find_active_stake"
    ~title:"Cannot find active stake"
    ~description:
      "The active stake of a delegate cannot be found for the given cycle."
    ~pp:(fun ppf (cycle, delegate) ->
      Format.fprintf
        ppf
        "The active stake of the delegate %a cannot be found for the cycle %a."
        Cycle_repr.pp
        cycle
        Signature.Public_key_hash.pp
        delegate)
    Data_encoding.(
      obj2
        (req "cycle" Cycle_repr.encoding)
        (req "delegate" Signature.Public_key_hash.encoding))
    (function
      | Cannot_find_active_stake {cycle; delegate} -> Some (cycle, delegate)
      | _ -> None)
    (fun (cycle, delegate) -> Cannot_find_active_stake {cycle; delegate}) ;
  register_error_kind
    `Temporary
    ~id:"delegate.not_registered"
    ~title:"Not a registered delegate"
    ~description:
      "The provided public key hash is not the address of a registered \
       delegate."
    ~pp:(fun ppf pkh ->
      Format.fprintf
        ppf
        "The provided public key hash (%a) is not the address of a registered \
         delegate. If you own this account and want to register it as a \
         delegate, use a delegation operation to delegate the account to \
         itself."
        Signature.Public_key_hash.pp
        pkh)
    Data_encoding.(obj1 (req "pkh" Signature.Public_key_hash.encoding))
    (function Not_registered pkh -> Some pkh | _ -> None)
    (fun pkh -> Not_registered pkh)

let set_inactive ctxt delegate =
  let delegate_contract = Contract_repr.implicit_contract delegate in
  Delegate_activation_storage.set_inactive ctxt delegate_contract
  >>= fun ctxt ->
  Stake_storage.deactivate_only_call_from_delegate_storage ctxt delegate >|= ok

let set_active ctxt delegate =
  Delegate_activation_storage.set_active ctxt delegate
  >>=? fun (ctxt, inactive) ->
  if not inactive then return ctxt
  else Stake_storage.activate_only_call_from_delegate_storage ctxt delegate

let staking_balance ctxt delegate =
  Contract_delegate_storage.registered ctxt delegate >>=? fun is_registered ->
  if is_registered then Stake_storage.get_staking_balance ctxt delegate
  else return Tez_repr.zero

let pubkey ctxt delegate =
  Contract_manager_storage.get_manager_key
    ctxt
    delegate
    ~error:(Unregistered_delegate delegate)

let init ctxt contract delegate =
  Contract_manager_storage.is_manager_key_revealed ctxt delegate
  >>=? fun known_delegate ->
  error_unless known_delegate (Unregistered_delegate delegate) >>?= fun () ->
  Contract_delegate_storage.registered ctxt delegate >>=? fun is_registered ->
  error_unless is_registered (Unregistered_delegate delegate) >>?= fun () ->
  Contract_delegate_storage.init ctxt contract delegate

let set c contract delegate =
  match delegate with
  | None -> (
      match Contract_repr.is_implicit contract with
      | Some pkh ->
          (* check if contract is a registered delegate *)
          Contract_delegate_storage.registered c pkh >>=? fun is_registered ->
          if is_registered then fail (No_deletion pkh)
          else Contract_delegate_storage.delete c contract
      | None -> Contract_delegate_storage.delete c contract)
  | Some delegate ->
      Contract_manager_storage.is_manager_key_revealed c delegate
      >>=? fun known_delegate ->
      Contract_delegate_storage.registered c delegate
      >>=? fun registered_delegate ->
      let self_delegation =
        match Contract_repr.is_implicit contract with
        | Some pkh -> Signature.Public_key_hash.equal pkh delegate
        | None -> false
      in
      if (not known_delegate) || not (registered_delegate || self_delegation)
      then fail (Unregistered_delegate delegate)
      else
        (Contract_delegate_storage.find c contract >>=? function
         | Some current_delegate
           when Signature.Public_key_hash.equal delegate current_delegate ->
             if self_delegation then
               Delegate_activation_storage.is_inactive c delegate >>=? function
               | true -> return_unit
               | false -> fail Active_delegate
             else fail Current_delegate
         | None | Some _ -> return_unit)
        >>=? fun () ->
        (* check if contract is a registered delegate *)
        (match Contract_repr.is_implicit contract with
        | Some pkh ->
            Contract_delegate_storage.registered c pkh >>=? fun is_registered ->
            (* allow self-delegation to re-activate *)
            if (not self_delegation) && is_registered then
              fail (No_deletion pkh)
            else return_unit
        | None -> return_unit)
        >>=? fun () ->
        Storage.Contract.Balance.mem c contract >>= fun exists ->
        error_when
          (self_delegation && not exists)
          (Empty_delegate_account delegate)
        >>?= fun () ->
        Contract_delegate_storage.set c contract delegate >>=? fun c ->
        if self_delegation then
          Storage.Delegates.add c delegate >>= fun c -> set_active c delegate
        else return c

let frozen_deposits_limit ctxt delegate =
  Storage.Contract.Frozen_deposits_limit.find
    ctxt
    (Contract_repr.implicit_contract delegate)

let set_frozen_deposits_limit ctxt delegate limit =
  Storage.Contract.Frozen_deposits_limit.add_or_remove
    ctxt
    (Contract_repr.implicit_contract delegate)
    limit

let update_activity ctxt last_cycle =
  let preserved = Constants_storage.preserved_cycles ctxt in
  match Cycle_repr.sub last_cycle preserved with
  | None -> return (ctxt, [])
  | Some _unfrozen_cycle ->
      Stake_storage.fold_on_active_delegates_with_rolls
        ctxt
        ~order:`Sorted
        ~init:(Ok (ctxt, []))
        ~f:(fun delegate () acc ->
          acc >>?= fun (ctxt, deactivated) ->
          Delegate_activation_storage.grace_period ctxt delegate
          >>=? fun cycle ->
          if Cycle_repr.(cycle <= last_cycle) then
            set_inactive ctxt delegate >|=? fun ctxt ->
            (ctxt, delegate :: deactivated)
          else return (ctxt, deactivated))
      >|=? fun (ctxt, deactivated) -> (ctxt, deactivated)

let expected_slots_for_given_active_stake ctxt ~total_active_stake ~active_stake
    =
  let blocks_per_cycle =
    Int32.to_int (Constants_storage.blocks_per_cycle ctxt)
  in
  let consensus_committee_size =
    Constants_storage.consensus_committee_size ctxt
  in
  let number_of_endorsements_per_cycle =
    blocks_per_cycle * consensus_committee_size
  in
  return
    (Z.to_int
       (Z.div
          (Z.mul
             (Z.of_int64 (Tez_repr.to_mutez active_stake))
             (Z.of_int number_of_endorsements_per_cycle))
          (Z.of_int64 (Tez_repr.to_mutez total_active_stake))))

let delegate_participated_enough ctxt delegate =
  Storage.Contract.Missed_endorsements.find ctxt delegate >>=? function
  | None -> return_true
  | Some missed_endorsements ->
      return Compare.Int.(missed_endorsements.remaining_slots >= 0)

let delegate_has_revealed_nonces delegate unrevelead_nonces_set =
  not (Signature.Public_key_hash.Set.mem delegate unrevelead_nonces_set)

let distribute_endorsing_rewards ctxt last_cycle unrevealed_nonces =
  let endorsing_reward_per_slot =
    Constants_storage.endorsing_reward_per_slot ctxt
  in
  let unrevealed_nonces_set =
    List.fold_left
      (fun set {Storage.Seed.nonce_hash = _; delegate} ->
        Signature.Public_key_hash.Set.add delegate set)
      Signature.Public_key_hash.Set.empty
      unrevealed_nonces
  in
  Stake_storage.get_total_active_stake ctxt last_cycle
  >>=? fun total_active_stake ->
  Stake_storage.get_selected_distribution ctxt last_cycle >>=? fun delegates ->
  List.fold_left_es
    (fun (ctxt, balance_updates) (delegate, active_stake) ->
      let delegate_contract = Contract_repr.implicit_contract delegate in
      delegate_participated_enough ctxt delegate_contract
      >>=? fun sufficient_participation ->
      let has_revealed_nonces =
        delegate_has_revealed_nonces delegate unrevealed_nonces_set
      in
      expected_slots_for_given_active_stake
        ctxt
        ~total_active_stake
        ~active_stake
      >>=? fun expected_slots ->
      let rewards = Tez_repr.mul_exn endorsing_reward_per_slot expected_slots in
      (if sufficient_participation && has_revealed_nonces then
       (* Sufficient participation: we pay the rewards *)
       Token.transfer
         ctxt
         `Endorsing_rewards
         (`Contract delegate_contract)
         rewards
       >|=? fun (ctxt, payed_rewards_receipts) ->
       (ctxt, payed_rewards_receipts @ balance_updates)
      else
        (* Insufficient participation or unrevealed nonce: no rewards *)
        Token.transfer
          ctxt
          `Endorsing_rewards
          (`Lost_endorsing_rewards
            (delegate, not sufficient_participation, not has_revealed_nonces))
          rewards
        >|=? fun (ctxt, payed_rewards_receipts) ->
        (ctxt, payed_rewards_receipts @ balance_updates))
      >>=? fun (ctxt, balance_updates) ->
      Storage.Contract.Missed_endorsements.remove ctxt delegate_contract
      >>= fun ctxt -> return (ctxt, balance_updates))
    (ctxt, [])
    delegates

let clear_outdated_slashed_deposits ctxt ~new_cycle =
  let max_slashable_period = Constants_storage.max_slashing_period ctxt in
  match Cycle_repr.(sub new_cycle max_slashable_period) with
  | None -> Lwt.return ctxt
  | Some outdated_cycle -> Storage.Slashed_deposits.clear (ctxt, outdated_cycle)

(* Return a map from delegates (with active stake at some cycle
   in the cycle window [from_cycle, to_cycle]) to the maximum
   of the stake to be deposited for each such cycle (which is just the
   [frozen_deposits_percentage] of the active stake at that cycle). Also
   return the delegates that have fallen out of the sliding window. *)
let max_frozen_deposits_and_delegates_to_remove ctxt ~from_cycle ~to_cycle =
  let frozen_deposits_percentage =
    Constants_storage.frozen_deposits_percentage ctxt
  in
  let cycles = Cycle_repr.(from_cycle ---> to_cycle) in
  (match Cycle_repr.pred from_cycle with
  | None -> return Signature.Public_key_hash.Set.empty
  | Some cleared_cycle -> (
      Stake_storage.find_selected_distribution ctxt cleared_cycle
      >|=? fun cleared_cycle_delegates ->
      match cleared_cycle_delegates with
      | None -> Signature.Public_key_hash.Set.empty
      | Some delegates ->
          List.fold_left
            (fun set (d, _) -> Signature.Public_key_hash.Set.add d set)
            Signature.Public_key_hash.Set.empty
            delegates))
  >>=? fun cleared_cycle_delegates ->
  List.fold_left_es
    (fun (maxima, delegates_to_remove) (cycle : Cycle_repr.t) ->
      Stake_storage.get_selected_distribution ctxt cycle
      >|=? fun active_stakes ->
      List.fold_left
        (fun (maxima, delegates_to_remove) (delegate, stake) ->
          let stake_to_be_deposited =
            Tez_repr.(div_exn (mul_exn stake frozen_deposits_percentage) 100)
          in
          let maxima =
            Signature.Public_key_hash.Map.update
              delegate
              (function
                | None -> Some stake_to_be_deposited
                | Some maximum ->
                    Some (Tez_repr.max maximum stake_to_be_deposited))
              maxima
          in
          let delegates_to_remove =
            Signature.Public_key_hash.Set.remove delegate delegates_to_remove
          in
          (maxima, delegates_to_remove))
        (maxima, delegates_to_remove)
        active_stakes)
    (Signature.Public_key_hash.Map.empty, cleared_cycle_delegates)
    cycles

let freeze_deposits ?(origin = Receipt_repr.Block_application) ctxt ~new_cycle
    ~balance_updates =
  let max_slashable_period = Constants_storage.max_slashing_period ctxt in
  (* We want to be able to slash for at most [max_slashable_period] *)
  (match Cycle_repr.(sub new_cycle (max_slashable_period - 1)) with
  | None ->
      Storage.Tenderbake.First_level.get ctxt
      >>=? fun first_level_of_tenderbake ->
      let cycle_eras = Raw_context.cycle_eras ctxt in
      let level = Level_repr.from_raw ~cycle_eras first_level_of_tenderbake in
      return level.cycle
  | Some cycle -> return cycle)
  >>=? fun from_cycle ->
  let preserved_cycles = Constants_storage.preserved_cycles ctxt in
  let to_cycle = Cycle_repr.(add new_cycle preserved_cycles) in
  max_frozen_deposits_and_delegates_to_remove ctxt ~from_cycle ~to_cycle
  >>=? fun (maxima, delegates_to_remove) ->
  Signature.Public_key_hash.Map.fold_es
    (fun delegate maximum_stake_to_be_deposited (ctxt, balance_updates) ->
      (* Here we make sure to preserve the following invariant :
         maximum_stake_to_be_deposited <= frozen_deposits + balance
         See select_distribution_for_cycle *)
      let delegate_contract = Contract_repr.implicit_contract delegate in
      Frozen_deposits_storage.update_deposits_cap
        ctxt
        delegate_contract
        maximum_stake_to_be_deposited
      >>=? fun (ctxt, current_amount) ->
      if Tez_repr.(current_amount > maximum_stake_to_be_deposited) then
        Tez_repr.(current_amount -? maximum_stake_to_be_deposited)
        >>?= fun to_reimburse ->
        Token.transfer
          ~origin
          ctxt
          (`Frozen_deposits delegate)
          (`Delegate_balance delegate)
          to_reimburse
        >|=? fun (ctxt, bupds) -> (ctxt, bupds @ balance_updates)
      else if Tez_repr.(current_amount < maximum_stake_to_be_deposited) then
        Tez_repr.(maximum_stake_to_be_deposited -? current_amount)
        >>?= fun desired_to_freeze ->
        Storage.Contract.Balance.get ctxt delegate_contract >>=? fun balance ->
        (* In case the delegate hasn't been slashed in this cycle,
           the following invariant holds:
           maximum_stake_to_be_deposited <= frozen_deposits + balance
           See select_distribution_for_cycle

           If the delegate has been slashed during the cycle, the invariant
           above doesn't necessarily hold. In this case, we freeze the max
           we can for the delegate. *)
        let to_freeze = Tez_repr.(min balance desired_to_freeze) in
        Token.transfer
          ~origin
          ctxt
          (`Delegate_balance delegate)
          (`Frozen_deposits delegate)
          to_freeze
        >|=? fun (ctxt, bupds) -> (ctxt, bupds @ balance_updates)
      else return (ctxt, balance_updates))
    maxima
    (ctxt, balance_updates)
  >>=? fun (ctxt, balance_updates) ->
  (* Unfreeze deposits (that is, set them to zero) for delegates that
     were previously in the relevant window (and therefore had some
     frozen deposits) but are not in the new window; because that means
     that such a delegate had no active stake in the relevant cycles,
     and therefore it should have no frozen deposits. *)
  Signature.Public_key_hash.Set.fold_es
    (fun delegate (ctxt, balance_updates) ->
      let delegate_contract = Contract_repr.implicit_contract delegate in
      Frozen_deposits_storage.get ctxt delegate_contract
      >>=? fun frozen_deposits ->
      if Tez_repr.(frozen_deposits.current_amount > zero) then
        Frozen_deposits_storage.update_deposits_cap
          ctxt
          delegate_contract
          Tez_repr.zero
        >>=? fun (ctxt, (_current_amount : Tez_repr.t)) ->
        Token.transfer
          ~origin
          ctxt
          (`Frozen_deposits delegate)
          (`Delegate_balance delegate)
          frozen_deposits.current_amount
        >|=? fun (ctxt, bupds) -> (ctxt, bupds @ balance_updates)
      else return (ctxt, balance_updates))
    delegates_to_remove
    (ctxt, balance_updates)

let freeze_deposits_do_not_call_except_for_migration =
  freeze_deposits ~origin:Protocol_migration

let cycle_end ctxt last_cycle unrevealed_nonces =
  let new_cycle = Cycle_repr.add last_cycle 1 in
  Stake_storage.select_new_distribution_at_cycle_end ctxt ~new_cycle pubkey
  >>=? fun ctxt ->
  clear_outdated_slashed_deposits ctxt ~new_cycle >>= fun ctxt ->
  distribute_endorsing_rewards ctxt last_cycle unrevealed_nonces
  >>=? fun (ctxt, balance_updates) ->
  freeze_deposits ctxt ~new_cycle ~balance_updates
  >>=? fun (ctxt, balance_updates) ->
  Stake_storage.clear_at_cycle_end ctxt ~new_cycle >>=? fun ctxt ->
  update_activity ctxt last_cycle >>=? fun (ctxt, deactivated_delagates) ->
  return (ctxt, balance_updates, deactivated_delagates)

let balance ctxt delegate =
  let contract = Contract_repr.implicit_contract delegate in
  Storage.Contract.Balance.get ctxt contract

let frozen_deposits ctxt delegate =
  Frozen_deposits_storage.get ctxt (Contract_repr.implicit_contract delegate)

let full_balance ctxt delegate =
  frozen_deposits ctxt delegate >>=? fun frozen_deposits ->
  balance ctxt delegate >>=? fun balance ->
  Lwt.return Tez_repr.(frozen_deposits.current_amount +? balance)

let deactivated = Delegate_activation_storage.is_inactive

let delegated_balance ctxt delegate =
  staking_balance ctxt delegate >>=? fun staking_balance ->
  balance ctxt delegate >>=? fun balance ->
  frozen_deposits ctxt delegate >>=? fun frozen_deposits ->
  Tez_repr.(balance +? frozen_deposits.current_amount)
  >>?= fun self_staking_balance ->
  Lwt.return Tez_repr.(staking_balance -? self_staking_balance)

let fold = Storage.Delegates.fold

let list = Storage.Delegates.elements

(* The fact that this succeeds iff [registered ctxt pkh] returns true is an
   invariant of the [set] function. *)
let check_delegate ctxt pkh =
  Storage.Delegates.mem ctxt pkh >>= function
  | true -> return_unit
  | false -> fail (Not_registered pkh)

module Random = struct
  (* [init_random_state] initialize a random sequence drawing state
     that's unique for a given (seed, level, index) triple. Elements
     from this sequence are drawn using [take_int64], updating the
     state for the next draw. The initial state is the Blake2b hash of
     the three randomness sources, and an offset set to zero
     (indicating that zero bits of randomness have been
     consumed). When drawing random elements, bits are extracted from
     the state until exhaustion (256 bits), at which point the state
     is rehashed and the offset reset to 0. *)

  let init_random_state seed level index =
    ( Raw_hashes.blake2b
        (Data_encoding.Binary.to_bytes_exn
           Data_encoding.(tup3 Seed_repr.seed_encoding int32 int32)
           (seed, level.Level_repr.cycle_position, Int32.of_int index)),
      0 )

  let take_int64 bound state =
    let drop_if_over =
      (* This function draws random values in [0-(bound-1)] by drawing
         in [0-(2^63-1)] (64-bit) and computing the value modulo
         [bound]. For the application of [mod bound] to preserve
         uniformity, the input space must be of the form
         [0-(n*bound-1)]. We enforce this by rejecting 64-bit samples
         above this limit (in which case, we draw a new 64-sample from
         the sequence and try again). *)
      Int64.sub Int64.max_int (Int64.rem Int64.max_int bound)
    in
    let rec loop (bytes, n) =
      let consumed_bytes = 8 in
      let state_size = Bytes.length bytes in
      if Compare.Int.(n > state_size - consumed_bytes) then
        loop (Raw_hashes.blake2b bytes, 0)
      else
        let r = Int64.abs (TzEndian.get_int64 bytes n) in
        if Compare.Int64.(r >= drop_if_over) then
          loop (bytes, n + consumed_bytes)
        else
          let v = Int64.rem r bound in
          (v, (bytes, n + consumed_bytes))
    in
    loop state

  let owner c (level : Level_repr.t) offset =
    (* TODO: https://gitlab.com/tezos/tezos/-/issues/2084
       compute sampler at stake distribution snapshot instead of lazily. *)
    let cycle = level.Level_repr.cycle in
    (match Raw_context.sampler_for_cycle c cycle with
    | Error `Sampler_not_set ->
        Seed_storage.for_cycle c cycle >>=? fun seed ->
        Stake_storage.Delegate_sampler_state.get c cycle >>=? fun state ->
        let (c, seed, state) =
          match Raw_context.set_sampler_for_cycle c cycle (seed, state) with
          | Error `Sampler_already_set -> assert false
          | Ok c -> (c, seed, state)
        in
        return (c, seed, state)
    | Ok (seed, state) -> return (c, seed, state))
    >>=? fun (c, seed, state) ->
    let sample ~int_bound ~mass_bound =
      let state = init_random_state seed level offset in
      let (i, state) = take_int64 (Int64.of_int int_bound) state in
      let (elt, _) = take_int64 mass_bound state in
      (Int64.to_int i, elt)
    in
    let (pk, pkh) = Sampler.sample state sample in
    return (c, (pk, pkh))
end

let slot_owner c level slot = Random.owner c level (Slot_repr.to_int slot)

let baking_rights_owner c (level : Level_repr.t) ~round =
  Round_repr.to_int round >>?= fun round ->
  let consensus_committee_size = Constants_storage.consensus_committee_size c in
  Slot_repr.of_int (round mod consensus_committee_size) >>?= fun slot ->
  slot_owner c level slot >>=? fun (ctxt, pk) -> return (ctxt, slot, pk)

let already_slashed_for_double_endorsing ctxt delegate (level : Level_repr.t) =
  Storage.Slashed_deposits.find (ctxt, level.cycle) (level.level, delegate)
  >>=? function
  | None -> return_false
  | Some slashed -> return slashed.for_double_endorsing

let already_slashed_for_double_baking ctxt delegate (level : Level_repr.t) =
  Storage.Slashed_deposits.find (ctxt, level.cycle) (level.level, delegate)
  >>=? function
  | None -> return_false
  | Some slashed -> return slashed.for_double_baking

let punish_double_endorsing ctxt delegate (level : Level_repr.t) =
  let delegate_contract = Contract_repr.implicit_contract delegate in
  Frozen_deposits_storage.get ctxt delegate_contract >>=? fun frozen_deposits ->
  let slashing_ratio : Constants_repr.ratio =
    Constants_storage.ratio_of_frozen_deposits_slashed_per_double_endorsement
      ctxt
  in
  let punish_value =
    Tez_repr.(
      div_exn
        (mul_exn frozen_deposits.initial_amount slashing_ratio.numerator)
        slashing_ratio.denominator)
  in
  let amount_to_burn =
    Tez_repr.(min frozen_deposits.current_amount punish_value)
  in
  Token.transfer
    ctxt
    (`Frozen_deposits delegate)
    `Double_signing_punishments
    amount_to_burn
  >>=? fun (ctxt, balance_updates) ->
  Stake_storage.remove_stake ctxt delegate amount_to_burn >>=? fun ctxt ->
  Storage.Slashed_deposits.find (ctxt, level.cycle) (level.level, delegate)
  >>=? fun slashed ->
  let slashed : Storage.slashed_level =
    match slashed with
    | None -> {for_double_endorsing = true; for_double_baking = false}
    | Some slashed ->
        assert (Compare.Bool.(slashed.for_double_endorsing = false)) ;
        {slashed with for_double_endorsing = true}
  in
  Storage.Slashed_deposits.add
    (ctxt, level.cycle)
    (level.level, delegate)
    slashed
  >>= fun ctxt -> return (ctxt, amount_to_burn, balance_updates)

let punish_double_baking ctxt delegate (level : Level_repr.t) =
  let delegate_contract = Contract_repr.implicit_contract delegate in
  Frozen_deposits_storage.get ctxt delegate_contract >>=? fun frozen_deposits ->
  let slashing_for_one_block =
    Constants_storage.double_baking_punishment ctxt
  in
  let amount_to_burn =
    Tez_repr.(min frozen_deposits.current_amount slashing_for_one_block)
  in
  Token.transfer
    ctxt
    (`Frozen_deposits delegate)
    `Double_signing_punishments
    amount_to_burn
  >>=? fun (ctxt, balance_updates) ->
  Stake_storage.remove_stake ctxt delegate amount_to_burn >>=? fun ctxt ->
  Storage.Slashed_deposits.find (ctxt, level.cycle) (level.level, delegate)
  >>=? fun slashed ->
  let slashed : Storage.slashed_level =
    match slashed with
    | None -> {for_double_endorsing = false; for_double_baking = true}
    | Some slashed ->
        assert (Compare.Bool.(slashed.for_double_baking = false)) ;
        {slashed with for_double_baking = true}
  in
  Storage.Slashed_deposits.add
    (ctxt, level.cycle)
    (level.level, delegate)
    slashed
  >>= fun ctxt -> return (ctxt, amount_to_burn, balance_updates)

type level_participation = Participated | Didn't_participate

(* Note that the participation for the last block of a cycle is
   recorded in the next cycle. *)
let record_endorsing_participation ctxt ~delegate ~participation
    ~endorsing_power =
  match participation with
  | Participated -> set_active ctxt delegate
  | Didn't_participate -> (
      let contract = Contract_repr.implicit_contract delegate in
      Storage.Contract.Missed_endorsements.find ctxt contract >>=? function
      | Some {remaining_slots; missed_levels} ->
          let remaining_slots = remaining_slots - endorsing_power in
          Storage.Contract.Missed_endorsements.update
            ctxt
            contract
            {remaining_slots; missed_levels = missed_levels + 1}
      | None -> (
          let level = Level_storage.current ctxt in
          Raw_context.stake_distribution_for_current_cycle ctxt
          >>?= fun stake_distribution ->
          match
            Signature.Public_key_hash.Map.find delegate stake_distribution
          with
          | None ->
              (* This happens when the block is the first one in a
                 cycle, and therefore the endorsements are for the last
                 block of the previous cycle, and when the delegate does
                 not have an active stake at the current cycle; in this
                 case its participation is simply ignored. *)
              assert (Compare.Int32.(level.cycle_position = 0l)) ;
              return ctxt
          | Some active_stake ->
              Stake_storage.get_total_active_stake ctxt level.cycle
              >>=? fun total_active_stake ->
              expected_slots_for_given_active_stake
                ctxt
                ~total_active_stake
                ~active_stake
              >>=? fun expected_slots ->
              let Constants_repr.{numerator; denominator} =
                Constants_storage.minimal_participation_ratio ctxt
              in
              let minimal_activity = expected_slots * numerator / denominator in
              let maximal_inactivity = expected_slots - minimal_activity in
              let remaining_slots = maximal_inactivity - endorsing_power in
              Storage.Contract.Missed_endorsements.init
                ctxt
                contract
                {remaining_slots; missed_levels = 1}))

let record_baking_activity_and_pay_rewards_and_fees ctxt ~payload_producer
    ~block_producer ~baking_reward ~reward_bonus =
  set_active ctxt payload_producer >>=? fun ctxt ->
  (if not (Signature.Public_key_hash.equal payload_producer block_producer) then
   set_active ctxt block_producer
  else return ctxt)
  >>=? fun ctxt ->
  let pay_payload_producer ctxt delegate =
    let contract = Contract_repr.implicit_contract delegate in
    Token.balance ctxt `Block_fees >>=? fun block_fees ->
    Token.transfer_n
      ctxt
      [(`Block_fees, block_fees); (`Baking_rewards, baking_reward)]
      (`Contract contract)
  in
  let pay_block_producer ctxt delegate bonus =
    let contract = Contract_repr.implicit_contract delegate in
    Token.transfer ctxt `Baking_bonuses (`Contract contract) bonus
  in
  pay_payload_producer ctxt payload_producer
  >>=? fun (ctxt, balance_updates_payload_producer) ->
  (match reward_bonus with
  | Some bonus -> pay_block_producer ctxt block_producer bonus
  | None -> return (ctxt, []))
  >>=? fun (ctxt, balance_updates_block_producer) ->
  return
    (ctxt, balance_updates_payload_producer @ balance_updates_block_producer)

type participation_info = {
  expected_cycle_activity : int;
  minimal_cycle_activity : int;
  missed_slots : int;
  missed_levels : int;
  remaining_allowed_missed_slots : int;
  expected_endorsing_rewards : Tez_repr.t;
}

(* Inefficient, only for RPC *)
let delegate_participation_info ctxt delegate =
  let level = Level_storage.current ctxt in
  Stake_storage.get_selected_distribution ctxt level.cycle
  >>=? fun stake_distribution ->
  match
    List.assoc_opt
      ~equal:Signature.Public_key_hash.equal
      delegate
      stake_distribution
  with
  | None ->
      (* delegate does not have an active stake at the current cycle *)
      return
        {
          expected_cycle_activity = 0;
          minimal_cycle_activity = 0;
          missed_slots = 0;
          missed_levels = 0;
          remaining_allowed_missed_slots = 0;
          expected_endorsing_rewards = Tez_repr.zero;
        }
  | Some active_stake ->
      Stake_storage.get_total_active_stake ctxt level.cycle
      >>=? fun total_active_stake ->
      expected_slots_for_given_active_stake
        ctxt
        ~total_active_stake
        ~active_stake
      >>=? fun expected_cycle_activity ->
      let Constants_repr.{numerator; denominator} =
        Constants_storage.minimal_participation_ratio ctxt
      in
      let endorsing_reward_per_slot =
        Constants_storage.endorsing_reward_per_slot ctxt
      in
      let minimal_cycle_activity =
        expected_cycle_activity * numerator / denominator
      in
      let maximal_cycle_inactivity =
        expected_cycle_activity - minimal_cycle_activity
      in
      let expected_endorsing_rewards =
        Tez_repr.mul_exn endorsing_reward_per_slot expected_cycle_activity
      in
      let contract = Contract_repr.implicit_contract delegate in
      Storage.Contract.Missed_endorsements.find ctxt contract
      >>=? fun missed_endorsements ->
      let (missed_slots, missed_levels, remaining_allowed_missed_slots) =
        match missed_endorsements with
        | None -> (0, 0, maximal_cycle_inactivity)
        | Some {remaining_slots; missed_levels} ->
            ( maximal_cycle_inactivity - remaining_slots,
              missed_levels,
              Compare.Int.max 0 remaining_slots )
      in
      let expected_endorsing_rewards =
        match missed_endorsements with
        | Some r when Compare.Int.(r.remaining_slots < 0) -> Tez_repr.zero
        | _ -> expected_endorsing_rewards
      in
      return
        {
          expected_cycle_activity;
          minimal_cycle_activity;
          missed_slots;
          missed_levels;
          remaining_allowed_missed_slots;
          expected_endorsing_rewards;
        }
