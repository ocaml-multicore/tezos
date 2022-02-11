(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>           *)
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
  | (* `Temporary *)
      Balance_too_low of
      Contract_repr.contract * Tez_repr.t * Tez_repr.t
  | (* `Temporary *)
      Counter_in_the_past of Contract_repr.contract * Z.t * Z.t
  | (* `Branch *)
      Counter_in_the_future of Contract_repr.contract * Z.t * Z.t
  | (* `Temporary *)
      Non_existing_contract of Contract_repr.contract
  | (* `Branch *)
      Empty_implicit_contract of Signature.Public_key_hash.t
  | (* `Branch *)
      Empty_implicit_delegated_contract of
      Signature.Public_key_hash.t
  | (* `Permanent *)
      Inconsistent_public_key of
      Signature.Public_key.t * Signature.Public_key.t
  | (* `Permanent *) Failure of string

let () =
  register_error_kind
    `Temporary
    ~id:"contract.balance_too_low"
    ~title:"Balance too low"
    ~description:"An operation tried to spend more tokens than the contract has"
    ~pp:(fun ppf (c, b, a) ->
      Format.fprintf
        ppf
        "Balance of contract %a too low (%a) to spend %a"
        Contract_repr.pp
        c
        Tez_repr.pp
        b
        Tez_repr.pp
        a)
    Data_encoding.(
      obj3
        (req "contract" Contract_repr.encoding)
        (req "balance" Tez_repr.encoding)
        (req "amount" Tez_repr.encoding))
    (function Balance_too_low (c, b, a) -> Some (c, b, a) | _ -> None)
    (fun (c, b, a) -> Balance_too_low (c, b, a)) ;
  register_error_kind
    `Temporary
    ~id:"contract.counter_in_the_future"
    ~title:"Invalid counter (not yet reached) in a manager operation"
    ~description:"An operation assumed a contract counter in the future"
    ~pp:(fun ppf (contract, exp, found) ->
      Format.fprintf
        ppf
        "Counter %a not yet reached for contract %a (expected %a)"
        Z.pp_print
        found
        Contract_repr.pp
        contract
        Z.pp_print
        exp)
    Data_encoding.(
      obj3
        (req "contract" Contract_repr.encoding)
        (req "expected" z)
        (req "found" z))
    (function Counter_in_the_future (c, x, y) -> Some (c, x, y) | _ -> None)
    (fun (c, x, y) -> Counter_in_the_future (c, x, y)) ;
  register_error_kind
    `Branch
    ~id:"contract.counter_in_the_past"
    ~title:"Invalid counter (already used) in a manager operation"
    ~description:"An operation assumed a contract counter in the past"
    ~pp:(fun ppf (contract, exp, found) ->
      Format.fprintf
        ppf
        "Counter %a already used for contract %a (expected %a)"
        Z.pp_print
        found
        Contract_repr.pp
        contract
        Z.pp_print
        exp)
    Data_encoding.(
      obj3
        (req "contract" Contract_repr.encoding)
        (req "expected" z)
        (req "found" z))
    (function Counter_in_the_past (c, x, y) -> Some (c, x, y) | _ -> None)
    (fun (c, x, y) -> Counter_in_the_past (c, x, y)) ;
  register_error_kind
    `Temporary
    ~id:"contract.non_existing_contract"
    ~title:"Non existing contract"
    ~description:
      "A contract handle is not present in the context (either it never was or \
       it has been destroyed)"
    ~pp:(fun ppf contract ->
      Format.fprintf ppf "Contract %a does not exist" Contract_repr.pp contract)
    Data_encoding.(obj1 (req "contract" Contract_repr.encoding))
    (function Non_existing_contract c -> Some c | _ -> None)
    (fun c -> Non_existing_contract c) ;
  register_error_kind
    `Permanent
    ~id:"contract.manager.inconsistent_public_key"
    ~title:"Inconsistent public key"
    ~description:
      "A provided manager public key is different with the public key stored \
       in the contract"
    ~pp:(fun ppf (eh, ph) ->
      Format.fprintf
        ppf
        "Expected manager public key %s but %s was provided"
        (Signature.Public_key.to_b58check ph)
        (Signature.Public_key.to_b58check eh))
    Data_encoding.(
      obj2
        (req "public_key" Signature.Public_key.encoding)
        (req "expected_public_key" Signature.Public_key.encoding))
    (function Inconsistent_public_key (eh, ph) -> Some (eh, ph) | _ -> None)
    (fun (eh, ph) -> Inconsistent_public_key (eh, ph)) ;
  register_error_kind
    `Permanent
    ~id:"contract.failure"
    ~title:"Contract storage failure"
    ~description:"Unexpected contract storage error"
    ~pp:(fun ppf s -> Format.fprintf ppf "Contract_storage.Failure %S" s)
    Data_encoding.(obj1 (req "message" string))
    (function Failure s -> Some s | _ -> None)
    (fun s -> Failure s) ;
  register_error_kind
    `Branch
    ~id:"implicit.empty_implicit_contract"
    ~title:"Empty implicit contract"
    ~description:
      "No manager operations are allowed on an empty implicit contract."
    ~pp:(fun ppf implicit ->
      Format.fprintf
        ppf
        "Empty implicit contract (%a)"
        Signature.Public_key_hash.pp
        implicit)
    Data_encoding.(obj1 (req "implicit" Signature.Public_key_hash.encoding))
    (function Empty_implicit_contract c -> Some c | _ -> None)
    (fun c -> Empty_implicit_contract c) ;
  register_error_kind
    `Branch
    ~id:"implicit.empty_implicit_delegated_contract"
    ~title:"Empty implicit delegated contract"
    ~description:"Emptying an implicit delegated account is not allowed."
    ~pp:(fun ppf implicit ->
      Format.fprintf
        ppf
        "Emptying implicit delegated contract (%a)"
        Signature.Public_key_hash.pp
        implicit)
    Data_encoding.(obj1 (req "implicit" Signature.Public_key_hash.encoding))
    (function Empty_implicit_delegated_contract c -> Some c | _ -> None)
    (fun c -> Empty_implicit_delegated_contract c)

let failwith msg = fail (Failure msg)

module Legacy_big_map_diff = struct
  (*
    Big_map_diff receipt as it was represented in 006 and earlier.
    It is kept here for now for backward compatibility of tools. *)

  type item =
    | Update of {
        big_map : Z.t;
        diff_key : Script_repr.expr;
        diff_key_hash : Script_expr_hash.t;
        diff_value : Script_repr.expr option;
      }
    | Clear of Z.t
    | Copy of {src : Z.t; dst : Z.t}
    | Alloc of {
        big_map : Z.t;
        key_type : Script_repr.expr;
        value_type : Script_repr.expr;
      }

  type t = item list

  let item_encoding =
    let open Data_encoding in
    union
      [
        case
          (Tag 0)
          ~title:"update"
          (obj5
             (req "action" (constant "update"))
             (req "big_map" z)
             (req "key_hash" Script_expr_hash.encoding)
             (req "key" Script_repr.expr_encoding)
             (opt "value" Script_repr.expr_encoding))
          (function
            | Update {big_map; diff_key_hash; diff_key; diff_value} ->
                Some ((), big_map, diff_key_hash, diff_key, diff_value)
            | _ -> None)
          (fun ((), big_map, diff_key_hash, diff_key, diff_value) ->
            Update {big_map; diff_key_hash; diff_key; diff_value});
        case
          (Tag 1)
          ~title:"remove"
          (obj2 (req "action" (constant "remove")) (req "big_map" z))
          (function Clear big_map -> Some ((), big_map) | _ -> None)
          (fun ((), big_map) -> Clear big_map);
        case
          (Tag 2)
          ~title:"copy"
          (obj3
             (req "action" (constant "copy"))
             (req "source_big_map" z)
             (req "destination_big_map" z))
          (function Copy {src; dst} -> Some ((), src, dst) | _ -> None)
          (fun ((), src, dst) -> Copy {src; dst});
        case
          (Tag 3)
          ~title:"alloc"
          (obj4
             (req "action" (constant "alloc"))
             (req "big_map" z)
             (req "key_type" Script_repr.expr_encoding)
             (req "value_type" Script_repr.expr_encoding))
          (function
            | Alloc {big_map; key_type; value_type} ->
                Some ((), big_map, key_type, value_type)
            | _ -> None)
          (fun ((), big_map, key_type, value_type) ->
            Alloc {big_map; key_type; value_type});
      ]

  let encoding = Data_encoding.list item_encoding

  let to_lazy_storage_diff legacy_diffs =
    let rev_head (diffs : (_ * (_, _, _) Lazy_storage_diff.diff) list) =
      match diffs with
      | [] -> []
      | (_, Remove) :: _ -> diffs
      | (id, Update {init; updates}) :: rest ->
          (id, Update {init; updates = List.rev updates}) :: rest
    in
    (* Invariant:
       Updates are collected one by one, in reverse order, on the head diff
       item. So only and exactly the head diff item has its updates reversed.
    *)
    List.fold_left
      (fun (new_diff : (_ * (_, _, _) Lazy_storage_diff.diff) list) item ->
        match item with
        | Clear id -> (id, Lazy_storage_diff.Remove) :: rev_head new_diff
        | Copy {src; dst} ->
            let src =
              Lazy_storage_kind.Big_map.Id
              .of_legacy_USE_ONLY_IN_Legacy_big_map_diff
                src
            in
            (dst, Lazy_storage_diff.Update {init = Copy {src}; updates = []})
            :: rev_head new_diff
        | Alloc {big_map; key_type; value_type} ->
            ( big_map,
              Lazy_storage_diff.(
                Update
                  {
                    init = Alloc Lazy_storage_kind.Big_map.{key_type; value_type};
                    updates = [];
                  }) )
            :: rev_head new_diff
        | Update
            {
              big_map;
              diff_key = key;
              diff_key_hash = key_hash;
              diff_value = value;
            } -> (
            match new_diff with
            | (id, diff) :: rest when Compare.Z.(id = big_map) ->
                let diff =
                  match diff with
                  | Remove -> assert false
                  | Update {init; updates} ->
                      let updates =
                        Lazy_storage_kind.Big_map.{key; key_hash; value}
                        :: updates
                      in
                      Lazy_storage_diff.Update {init; updates}
                in
                (id, diff) :: rest
            | new_diff ->
                let updates =
                  [Lazy_storage_kind.Big_map.{key; key_hash; value}]
                in
                (big_map, Update {init = Existing; updates})
                :: rev_head new_diff))
      []
      legacy_diffs
    |> rev_head
    |> List.rev_map (fun (id, diff) ->
           let id =
             Lazy_storage_kind.Big_map.Id
             .of_legacy_USE_ONLY_IN_Legacy_big_map_diff
               id
           in
           Lazy_storage_diff.make Lazy_storage_kind.Big_map id diff)

  let of_lazy_storage_diff diffs =
    List.fold_left
      (fun legacy_diffs (Lazy_storage_diff.Item (kind, id, diff)) ->
        let diffs =
          match kind with
          | Lazy_storage_kind.Big_map -> (
              let id =
                Lazy_storage_kind.Big_map.Id
                .to_legacy_USE_ONLY_IN_Legacy_big_map_diff
                  id
              in
              match diff with
              | Remove -> [Clear id]
              | Update {init; updates} -> (
                  let updates =
                    List.rev_map
                      (fun {Lazy_storage_kind.Big_map.key; key_hash; value} ->
                        Update
                          {
                            big_map = id;
                            diff_key = key;
                            diff_key_hash = key_hash;
                            diff_value = value;
                          })
                      updates
                  in
                  match init with
                  | Existing -> updates
                  | Copy {src} ->
                      let src =
                        Lazy_storage_kind.Big_map.Id
                        .to_legacy_USE_ONLY_IN_Legacy_big_map_diff
                          src
                      in
                      Copy {src; dst = id} :: updates
                  | Alloc {key_type; value_type} ->
                      Alloc {big_map = id; key_type; value_type} :: updates))
          | _ -> (* Not a Big_map *) []
        in
        diffs :: legacy_diffs)
      []
      diffs
    |> List.rev |> List.flatten
    [@@coq_axiom_with_reason "gadt"]
end

let update_script_lazy_storage c = function
  | None -> return (c, Z.zero)
  | Some diffs -> Lazy_storage_diff.apply c diffs

let create_base c ~prepaid_bootstrap_storage
    (* Free space for bootstrap contracts *)
      contract ~balance ~manager ?script () =
  (match Contract_repr.is_implicit contract with
  | None -> return c
  | Some _ ->
      Storage.Contract.Global_counter.get c >>=? fun counter ->
      Storage.Contract.Counter.init c contract counter)
  >>=? fun c ->
  Storage.Contract.Balance.init c contract balance >>=? fun c ->
  (match manager with
  | Some manager ->
      Contract_manager_storage.init c contract (Manager_repr.Hash manager)
  | None -> return c)
  >>=? fun c ->
  match script with
  | Some ({Script_repr.code; storage}, lazy_storage_diff) ->
      Storage.Contract.Code.init c contract code >>=? fun (c, code_size) ->
      Storage.Contract.Storage.init c contract storage
      >>=? fun (c, storage_size) ->
      update_script_lazy_storage c lazy_storage_diff
      >>=? fun (c, lazy_storage_size) ->
      let total_size =
        Z.add
          (Z.add (Z.of_int code_size) (Z.of_int storage_size))
          lazy_storage_size
      in
      assert (Compare.Z.(total_size >= Z.zero)) ;
      let prepaid_bootstrap_storage =
        if prepaid_bootstrap_storage then total_size else Z.zero
      in
      Storage.Contract.Paid_storage_space.init
        c
        contract
        prepaid_bootstrap_storage
      >>=? fun c ->
      Storage.Contract.Used_storage_space.init c contract total_size
  | None -> return c

let raw_originate c ~prepaid_bootstrap_storage contract ~script =
  create_base
    c
    ~prepaid_bootstrap_storage
    contract
    ~balance:Tez_repr.zero
    ~manager:None
    ~script
    ()

let create_implicit c manager ~balance =
  create_base
    c
    ~prepaid_bootstrap_storage:false
    (Contract_repr.implicit_contract manager)
    ~balance
    ~manager:(Some manager)
    ?script:None
    ()

let delete c contract =
  match Contract_repr.is_implicit contract with
  | None ->
      (* For non implicit contract Big_map should be cleared *)
      failwith "Non implicit contracts cannot be removed"
  | Some _ ->
      Contract_delegate_storage.remove c contract >>=? fun c ->
      Storage.Contract.Balance.remove_existing c contract >>=? fun c ->
      Contract_manager_storage.remove_existing c contract >>=? fun c ->
      Storage.Contract.Counter.remove_existing c contract >>=? fun c ->
      Storage.Contract.Code.remove c contract >>=? fun (c, _, _) ->
      Storage.Contract.Storage.remove c contract >>=? fun (c, _, _) ->
      Storage.Contract.Paid_storage_space.remove c contract >>= fun c ->
      Storage.Contract.Used_storage_space.remove c contract >|= ok

let allocated c contract =
  Storage.Contract.Balance.find c contract >>=? function
  | None -> return_false
  | Some _ -> return_true

let exists c contract =
  match Contract_repr.is_implicit contract with
  | Some _ -> return_true
  | None -> allocated c contract

let must_exist c contract =
  exists c contract >>=? function
  | true -> return_unit
  | false -> fail (Non_existing_contract contract)

let must_be_allocated c contract =
  allocated c contract >>=? function
  | true -> return_unit
  | false -> (
      match Contract_repr.is_implicit contract with
      | Some pkh -> fail (Empty_implicit_contract pkh)
      | None -> fail (Non_existing_contract contract))

let list c = Storage.Contract.list c

let fresh_contract_from_current_nonce c =
  Raw_context.increment_origination_nonce c >|? fun (c, nonce) ->
  (c, Contract_repr.originated_contract nonce)

let originated_from_current_nonce ~since:ctxt_since ~until:ctxt_until =
  Raw_context.get_origination_nonce ctxt_since >>?= fun since ->
  Raw_context.get_origination_nonce ctxt_until >>?= fun until ->
  List.filter_es
    (fun contract -> exists ctxt_until contract)
    (Contract_repr.originated_contracts ~since ~until)

let check_counter_increment c manager counter =
  let contract = Contract_repr.implicit_contract manager in
  Storage.Contract.Counter.get c contract >>=? fun contract_counter ->
  let expected = Z.succ contract_counter in
  if Compare.Z.(expected = counter) then return_unit
  else if Compare.Z.(expected > counter) then
    fail (Counter_in_the_past (contract, expected, counter))
  else fail (Counter_in_the_future (contract, expected, counter))

let increment_counter c manager =
  let contract = Contract_repr.implicit_contract manager in
  Storage.Contract.Global_counter.get c >>=? fun global_counter ->
  Storage.Contract.Global_counter.update c (Z.succ global_counter) >>=? fun c ->
  Storage.Contract.Counter.get c contract >>=? fun contract_counter ->
  Storage.Contract.Counter.update c contract (Z.succ contract_counter)

let get_script_code c contract = Storage.Contract.Code.find c contract

let get_script c contract =
  Storage.Contract.Code.find c contract >>=? fun (c, code) ->
  Storage.Contract.Storage.find c contract >>=? fun (c, storage) ->
  match (code, storage) with
  | (None, None) -> return (c, None)
  | (Some code, Some storage) -> return (c, Some {Script_repr.code; storage})
  | (None, Some _) | (Some _, None) -> failwith "get_script"

let get_storage ctxt contract =
  Storage.Contract.Storage.find ctxt contract >>=? function
  | (ctxt, None) -> return (ctxt, None)
  | (ctxt, Some storage) ->
      Raw_context.consume_gas ctxt (Script_repr.force_decode_cost storage)
      >>?= fun ctxt ->
      Script_repr.force_decode storage >>?= fun storage ->
      return (ctxt, Some storage)

let get_counter c manager =
  let contract = Contract_repr.implicit_contract manager in
  Storage.Contract.Counter.find c contract >>=? function
  | None -> (
      match Contract_repr.is_implicit contract with
      | Some _ -> Storage.Contract.Global_counter.get c
      | None -> failwith "get_counter")
  | Some v -> return v

let get_balance c contract =
  Storage.Contract.Balance.find c contract >>=? function
  | None -> (
      match Contract_repr.is_implicit contract with
      | Some _ -> return Tez_repr.zero
      | None -> failwith "get_balance")
  | Some v -> return v

let get_balance_carbonated c contract =
  (* Reading an int64 from /contracts/index/<hash>/balance *)
  Raw_context.consume_gas
    c
    (Storage_costs.read_access ~path_length:4 ~read_bytes:8)
  >>?= fun c ->
  get_balance c contract >>=? fun balance -> return (c, balance)

let update_script_storage c contract storage lazy_storage_diff =
  let storage = Script_repr.lazy_expr storage in
  update_script_lazy_storage c lazy_storage_diff
  >>=? fun (c, lazy_storage_size_diff) ->
  Storage.Contract.Storage.update c contract storage >>=? fun (c, size_diff) ->
  Storage.Contract.Used_storage_space.get c contract >>=? fun previous_size ->
  let new_size =
    Z.add previous_size (Z.add lazy_storage_size_diff (Z.of_int size_diff))
  in
  Storage.Contract.Used_storage_space.update c contract new_size

let spend_only_call_from_token c contract amount =
  Storage.Contract.Balance.find c contract >>=? fun balance ->
  let balance = Option.value balance ~default:Tez_repr.zero in
  match Tez_repr.(balance -? amount) with
  | Error _ -> fail (Balance_too_low (contract, balance, amount))
  | Ok new_balance -> (
      Storage.Contract.Balance.update c contract new_balance >>=? fun c ->
      Contract_delegate_storage.remove_contract_stake c contract amount
      >>=? fun c ->
      if Tez_repr.(new_balance > Tez_repr.zero) then return c
      else
        match Contract_repr.is_implicit contract with
        | None -> return c (* Never delete originated contracts *)
        | Some pkh -> (
            Contract_delegate_storage.find c contract >>=? function
            | Some pkh' ->
                if Signature.Public_key_hash.equal pkh pkh' then return c
                else
                  (* Delegated implicit accounts cannot be emptied *)
                  fail (Empty_implicit_delegated_contract pkh)
            | None ->
                (* Delete empty implicit contract *)
                delete c contract))

(* [Tez_repr.(amount <> zero)] is a precondition of this function. It ensures that
   no entry associating a null balance to an implicit contract exists in the map
   [Storage.Contract.Balance]. *)
let credit_only_call_from_token c contract amount =
  Storage.Contract.Balance.find c contract >>=? function
  | None -> (
      match Contract_repr.is_implicit contract with
      | None -> fail (Non_existing_contract contract)
      | Some manager -> create_implicit c manager ~balance:amount)
  | Some balance ->
      Tez_repr.(amount +? balance) >>?= fun balance ->
      Storage.Contract.Balance.update c contract balance >>=? fun c ->
      Contract_delegate_storage.add_contract_stake c contract amount

let init c =
  Storage.Contract.Global_counter.init c Z.zero >>=? fun c ->
  Lazy_storage_diff.init c

let used_storage_space c contract =
  Storage.Contract.Used_storage_space.find c contract
  >|=? Option.value ~default:Z.zero

let paid_storage_space c contract =
  Storage.Contract.Paid_storage_space.find c contract
  >|=? Option.value ~default:Z.zero

let set_paid_storage_space_and_return_fees_to_pay c contract new_storage_space =
  Storage.Contract.Paid_storage_space.get c contract
  >>=? fun already_paid_space ->
  if Compare.Z.(already_paid_space >= new_storage_space) then return (Z.zero, c)
  else
    let to_pay = Z.sub new_storage_space already_paid_space in
    Storage.Contract.Paid_storage_space.update c contract new_storage_space
    >|=? fun c -> (to_pay, c)

let update_balance ctxt contract f amount =
  Storage.Contract.Balance.get ctxt contract >>=? fun balance ->
  f balance amount >>?= fun new_balance ->
  Storage.Contract.Balance.update ctxt contract new_balance

let increase_balance_only_call_from_token ctxt contract amount =
  update_balance ctxt contract Tez_repr.( +? ) amount

let decrease_balance_only_call_from_token ctxt contract amount =
  update_balance ctxt contract Tez_repr.( -? ) amount
