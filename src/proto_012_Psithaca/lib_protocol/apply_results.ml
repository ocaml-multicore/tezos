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

open Alpha_context
open Data_encoding

let error_encoding =
  def
    "error"
    ~description:
      "The full list of RPC errors would be too long to include.\n\
       It is available at RPC `/errors` (GET).\n\
       Errors specific to protocol Alpha have an id that starts with \
       `proto.alpha`."
  @@ splitted
       ~json:
         (conv
            (fun err ->
              Data_encoding.Json.construct Error_monad.error_encoding err)
            (fun json ->
              Data_encoding.Json.destruct Error_monad.error_encoding json)
            json)
       ~binary:Error_monad.error_encoding

let trace_encoding = make_trace_encoding error_encoding

type _ successful_manager_operation_result =
  | Reveal_result : {
      consumed_gas : Gas.Arith.fp;
    }
      -> Kind.reveal successful_manager_operation_result
  | Transaction_result : {
      storage : Script.expr option;
      lazy_storage_diff : Lazy_storage.diffs option;
      balance_updates : Receipt.balance_updates;
      originated_contracts : Contract.t list;
      consumed_gas : Gas.Arith.fp;
      storage_size : Z.t;
      paid_storage_size_diff : Z.t;
      allocated_destination_contract : bool;
    }
      -> Kind.transaction successful_manager_operation_result
  | Origination_result : {
      lazy_storage_diff : Lazy_storage.diffs option;
      balance_updates : Receipt.balance_updates;
      originated_contracts : Contract.t list;
      consumed_gas : Gas.Arith.fp;
      storage_size : Z.t;
      paid_storage_size_diff : Z.t;
    }
      -> Kind.origination successful_manager_operation_result
  | Delegation_result : {
      consumed_gas : Gas.Arith.fp;
    }
      -> Kind.delegation successful_manager_operation_result
  | Register_global_constant_result : {
      balance_updates : Receipt.balance_updates;
      consumed_gas : Gas.Arith.fp;
      size_of_constant : Z.t;
      global_address : Script_expr_hash.t;
    }
      -> Kind.register_global_constant successful_manager_operation_result
  | Set_deposits_limit_result : {
      consumed_gas : Gas.Arith.fp;
    }
      -> Kind.set_deposits_limit successful_manager_operation_result

let migration_origination_result_to_successful_manager_operation_result
    ({
       balance_updates;
       originated_contracts;
       storage_size;
       paid_storage_size_diff;
     } :
      Migration.origination_result) =
  Origination_result
    {
      lazy_storage_diff = None;
      balance_updates;
      originated_contracts;
      consumed_gas = Gas.Arith.zero;
      storage_size;
      paid_storage_size_diff;
    }

type packed_successful_manager_operation_result =
  | Successful_manager_result :
      'kind successful_manager_operation_result
      -> packed_successful_manager_operation_result

let pack_migration_operation_results results =
  List.map
    (fun el ->
      Successful_manager_result
        (migration_origination_result_to_successful_manager_operation_result el))
    results

type 'kind manager_operation_result =
  | Applied of 'kind successful_manager_operation_result
  | Backtracked of
      'kind successful_manager_operation_result * error trace option
  | Failed : 'kind Kind.manager * error trace -> 'kind manager_operation_result
  | Skipped : 'kind Kind.manager -> 'kind manager_operation_result
[@@coq_force_gadt]

type packed_internal_operation_result =
  | Internal_operation_result :
      'kind internal_operation * 'kind manager_operation_result
      -> packed_internal_operation_result

module Manager_result = struct
  type 'kind case =
    | MCase : {
        op_case : 'kind Operation.Encoding.Manager_operations.case;
        encoding : 'a Data_encoding.t;
        kind : 'kind Kind.manager;
        iselect :
          packed_internal_operation_result ->
          ('kind internal_operation * 'kind manager_operation_result) option;
        select :
          packed_successful_manager_operation_result ->
          'kind successful_manager_operation_result option;
        proj : 'kind successful_manager_operation_result -> 'a;
        inj : 'a -> 'kind successful_manager_operation_result;
        t : 'kind manager_operation_result Data_encoding.t;
      }
        -> 'kind case

  let make ~op_case ~encoding ~kind ~iselect ~select ~proj ~inj =
    let (Operation.Encoding.Manager_operations.MCase {name; _}) = op_case in
    let t =
      def (Format.asprintf "operation.alpha.operation_result.%s" name)
      @@ union
           ~tag_size:`Uint8
           [
             case
               (Tag 0)
               ~title:"Applied"
               (merge_objs (obj1 (req "status" (constant "applied"))) encoding)
               (fun o ->
                 match o with
                 | Skipped _ | Failed _ | Backtracked _ -> None
                 | Applied o -> (
                     match select (Successful_manager_result o) with
                     | None -> None
                     | Some o -> Some ((), proj o)))
               (fun ((), x) -> Applied (inj x));
             case
               (Tag 1)
               ~title:"Failed"
               (obj2
                  (req "status" (constant "failed"))
                  (req "errors" trace_encoding))
               (function Failed (_, errs) -> Some ((), errs) | _ -> None)
               (fun ((), errs) -> Failed (kind, errs));
             case
               (Tag 2)
               ~title:"Skipped"
               (obj1 (req "status" (constant "skipped")))
               (function Skipped _ -> Some () | _ -> None)
               (fun () -> Skipped kind);
             case
               (Tag 3)
               ~title:"Backtracked"
               (merge_objs
                  (obj2
                     (req "status" (constant "backtracked"))
                     (opt "errors" trace_encoding))
                  encoding)
               (fun o ->
                 match o with
                 | Skipped _ | Failed _ | Applied _ -> None
                 | Backtracked (o, errs) -> (
                     match select (Successful_manager_result o) with
                     | None -> None
                     | Some o -> Some (((), errs), proj o)))
               (fun (((), errs), x) -> Backtracked (inj x, errs));
           ]
    in
    MCase {op_case; encoding; kind; iselect; select; proj; inj; t}

  let[@coq_axiom_with_reason "gadt"] reveal_case =
    make
      ~op_case:Operation.Encoding.Manager_operations.reveal_case
      ~encoding:
        Data_encoding.(
          obj2
            (dft "consumed_gas" Gas.Arith.n_integral_encoding Gas.Arith.zero)
            (dft "consumed_milligas" Gas.Arith.n_fp_encoding Gas.Arith.zero))
      ~iselect:(function
        | Internal_operation_result (({operation = Reveal _; _} as op), res) ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Reveal_result _ as op) -> Some op
        | _ -> None)
      ~kind:Kind.Reveal_manager_kind
      ~proj:(function
        | Reveal_result {consumed_gas} ->
            (Gas.Arith.ceil consumed_gas, consumed_gas))
      ~inj:(fun (consumed_gas, consumed_milligas) ->
        assert (Gas.Arith.(equal (ceil consumed_milligas) consumed_gas)) ;
        Reveal_result {consumed_gas = consumed_milligas})

  let[@coq_axiom_with_reason "gadt"] transaction_case =
    make
      ~op_case:Operation.Encoding.Manager_operations.transaction_case
      ~encoding:
        (obj10
           (opt "storage" Script.expr_encoding)
           (opt
              (* The field [big_map_diff] is deprecated since 008, use [lazy_storage_diff] instead.
                 It is kept here for a transitional period, for tools like indexers to update. *)
              (* TODO: https://gitlab.com/tezos/tezos/-/issues/1948
                 Remove it in 009 or later. *)
              "big_map_diff"
              Lazy_storage.legacy_big_map_diff_encoding)
           (dft "balance_updates" Receipt.balance_updates_encoding [])
           (dft "originated_contracts" (list Contract.encoding) [])
           (dft "consumed_gas" Gas.Arith.n_integral_encoding Gas.Arith.zero)
           (dft "consumed_milligas" Gas.Arith.n_fp_encoding Gas.Arith.zero)
           (dft "storage_size" z Z.zero)
           (dft "paid_storage_size_diff" z Z.zero)
           (dft "allocated_destination_contract" bool false)
           (opt "lazy_storage_diff" Lazy_storage.encoding))
      ~iselect:(function
        | Internal_operation_result (({operation = Transaction _; _} as op), res)
          ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Transaction_result _ as op) -> Some op
        | _ -> None)
      ~kind:Kind.Transaction_manager_kind
      ~proj:(function
        | Transaction_result
            {
              storage;
              lazy_storage_diff;
              balance_updates;
              originated_contracts;
              consumed_gas;
              storage_size;
              paid_storage_size_diff;
              allocated_destination_contract;
            } ->
            ( storage,
              lazy_storage_diff,
              balance_updates,
              originated_contracts,
              Gas.Arith.ceil consumed_gas,
              consumed_gas,
              storage_size,
              paid_storage_size_diff,
              allocated_destination_contract,
              lazy_storage_diff ))
      ~inj:
        (fun ( storage,
               legacy_lazy_storage_diff,
               balance_updates,
               originated_contracts,
               consumed_gas,
               consumed_milligas,
               storage_size,
               paid_storage_size_diff,
               allocated_destination_contract,
               lazy_storage_diff ) ->
        assert (Gas.Arith.(equal (ceil consumed_milligas) consumed_gas)) ;
        let lazy_storage_diff =
          Option.either lazy_storage_diff legacy_lazy_storage_diff
        in
        Transaction_result
          {
            storage;
            lazy_storage_diff;
            balance_updates;
            originated_contracts;
            consumed_gas = consumed_milligas;
            storage_size;
            paid_storage_size_diff;
            allocated_destination_contract;
          })

  let[@coq_axiom_with_reason "gadt"] origination_case =
    make
      ~op_case:Operation.Encoding.Manager_operations.origination_case
      ~encoding:
        (obj8
           (opt
              (* The field [big_map_diff] is deprecated since 008, use [lazy_storage_diff] instead.
                 It is kept here for a transitional period, for tools like indexers to update. *)
              (* TODO: https://gitlab.com/tezos/tezos/-/issues/1948
                 Remove it in 009 or later. *)
              "big_map_diff"
              Lazy_storage.legacy_big_map_diff_encoding)
           (dft "balance_updates" Receipt.balance_updates_encoding [])
           (dft "originated_contracts" (list Contract.encoding) [])
           (dft "consumed_gas" Gas.Arith.n_integral_encoding Gas.Arith.zero)
           (dft "consumed_milligas" Gas.Arith.n_fp_encoding Gas.Arith.zero)
           (dft "storage_size" z Z.zero)
           (dft "paid_storage_size_diff" z Z.zero)
           (opt "lazy_storage_diff" Lazy_storage.encoding))
      ~iselect:(function
        | Internal_operation_result (({operation = Origination _; _} as op), res)
          ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Origination_result _ as op) -> Some op
        | _ -> None)
      ~proj:(function
        | Origination_result
            {
              lazy_storage_diff;
              balance_updates;
              originated_contracts;
              consumed_gas;
              storage_size;
              paid_storage_size_diff;
            } ->
            ( lazy_storage_diff,
              balance_updates,
              originated_contracts,
              Gas.Arith.ceil consumed_gas,
              consumed_gas,
              storage_size,
              paid_storage_size_diff,
              lazy_storage_diff ))
      ~kind:Kind.Origination_manager_kind
      ~inj:
        (fun ( legacy_lazy_storage_diff,
               balance_updates,
               originated_contracts,
               consumed_gas,
               consumed_milligas,
               storage_size,
               paid_storage_size_diff,
               lazy_storage_diff ) ->
        assert (Gas.Arith.(equal (ceil consumed_milligas) consumed_gas)) ;
        let lazy_storage_diff =
          Option.either lazy_storage_diff legacy_lazy_storage_diff
        in
        Origination_result
          {
            lazy_storage_diff;
            balance_updates;
            originated_contracts;
            consumed_gas = consumed_milligas;
            storage_size;
            paid_storage_size_diff;
          })

  let[@coq_axiom_with_reason "gadt"] register_global_constant_case =
    make
      ~op_case:
        Operation.Encoding.Manager_operations.register_global_constant_case
      ~encoding:
        (obj4
           (req "balance_updates" Receipt.balance_updates_encoding)
           (req "consumed_gas" Gas.Arith.n_integral_encoding)
           (req "storage_size" z)
           (req "global_address" Script_expr_hash.encoding))
      ~iselect:(function
        | Internal_operation_result
            (({operation = Register_global_constant _; _} as op), res) ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Register_global_constant_result _ as op) ->
            Some op
        | _ -> None)
      ~proj:(function
        | Register_global_constant_result
            {balance_updates; consumed_gas; size_of_constant; global_address} ->
            (balance_updates, consumed_gas, size_of_constant, global_address))
      ~kind:Kind.Register_global_constant_manager_kind
      ~inj:
        (fun (balance_updates, consumed_gas, size_of_constant, global_address) ->
        Register_global_constant_result
          {balance_updates; consumed_gas; size_of_constant; global_address})

  let delegation_case =
    make
      ~op_case:Operation.Encoding.Manager_operations.delegation_case
      ~encoding:
        Data_encoding.(
          obj2
            (dft "consumed_gas" Gas.Arith.n_integral_encoding Gas.Arith.zero)
            (dft "consumed_milligas" Gas.Arith.n_fp_encoding Gas.Arith.zero))
      ~iselect:(function
        | Internal_operation_result (({operation = Delegation _; _} as op), res)
          ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Delegation_result _ as op) -> Some op
        | _ -> None)
      ~kind:Kind.Delegation_manager_kind
      ~proj:(function[@coq_match_with_default]
        | Delegation_result {consumed_gas} ->
            (Gas.Arith.ceil consumed_gas, consumed_gas))
      ~inj:(fun (consumed_gas, consumed_milligas) ->
        assert (Gas.Arith.(equal (ceil consumed_milligas) consumed_gas)) ;
        Delegation_result {consumed_gas = consumed_milligas})

  let set_deposits_limit_case =
    make
      ~op_case:Operation.Encoding.Manager_operations.set_deposits_limit_case
      ~encoding:
        Data_encoding.(
          obj2
            (dft "consumed_gas" Gas.Arith.n_integral_encoding Gas.Arith.zero)
            (dft "consumed_milligas" Gas.Arith.n_fp_encoding Gas.Arith.zero))
      ~iselect:(function
        | Internal_operation_result
            (({operation = Set_deposits_limit _; _} as op), res) ->
            Some (op, res)
        | _ -> None)
      ~select:(function
        | Successful_manager_result (Set_deposits_limit_result _ as op) ->
            Some op
        | _ -> None)
      ~kind:Kind.Set_deposits_limit_manager_kind
      ~proj:(function
        | Set_deposits_limit_result {consumed_gas} ->
            (Gas.Arith.ceil consumed_gas, consumed_gas))
      ~inj:(fun (consumed_gas, consumed_milligas) ->
        assert (Gas.Arith.(equal (ceil consumed_milligas) consumed_gas)) ;
        Set_deposits_limit_result {consumed_gas = consumed_milligas})
end

let internal_operation_result_encoding :
    packed_internal_operation_result Data_encoding.t =
  let make (type kind)
      (Manager_result.MCase res_case : kind Manager_result.case) =
    let (Operation.Encoding.Manager_operations.MCase op_case) =
      res_case.op_case
    in
    case
      (Tag op_case.tag)
      ~title:op_case.name
      (merge_objs
         (obj3
            (req "kind" (constant op_case.name))
            (req "source" Contract.encoding)
            (req "nonce" uint16))
         (merge_objs op_case.encoding (obj1 (req "result" res_case.t))))
      (fun op ->
        match res_case.iselect op with
        | Some (op, res) ->
            Some (((), op.source, op.nonce), (op_case.proj op.operation, res))
        | None -> None)
      (fun (((), source, nonce), (op, res)) ->
        let op = {source; operation = op_case.inj op; nonce} in
        Internal_operation_result (op, res))
  in
  def "operation.alpha.internal_operation_result"
  @@ union
       [
         make Manager_result.reveal_case;
         make Manager_result.transaction_case;
         make Manager_result.origination_case;
         make Manager_result.delegation_case;
         make Manager_result.register_global_constant_case;
         make Manager_result.set_deposits_limit_case;
       ]

let successful_manager_operation_result_encoding :
    packed_successful_manager_operation_result Data_encoding.t =
  let make (type kind)
      (Manager_result.MCase res_case : kind Manager_result.case) =
    let (Operation.Encoding.Manager_operations.MCase op_case) =
      res_case.op_case
    in
    case
      (Tag op_case.tag)
      ~title:op_case.name
      (merge_objs (obj1 (req "kind" (constant op_case.name))) res_case.encoding)
      (fun res ->
        match res_case.select res with
        | Some res -> Some ((), res_case.proj res)
        | None -> None)
      (fun ((), res) -> Successful_manager_result (res_case.inj res))
  in
  def "operation.alpha.successful_manager_operation_result"
  @@ union
       [
         make Manager_result.reveal_case;
         make Manager_result.transaction_case;
         make Manager_result.origination_case;
         make Manager_result.delegation_case;
         make Manager_result.set_deposits_limit_case;
       ]

type 'kind contents_result =
  | Preendorsement_result : {
      balance_updates : Receipt.balance_updates;
      delegate : Signature.Public_key_hash.t;
      preendorsement_power : int;
    }
      -> Kind.preendorsement contents_result
  | Endorsement_result : {
      balance_updates : Receipt.balance_updates;
      delegate : Signature.Public_key_hash.t;
      endorsement_power : int;
    }
      -> Kind.endorsement contents_result
  | Seed_nonce_revelation_result :
      Receipt.balance_updates
      -> Kind.seed_nonce_revelation contents_result
  | Double_endorsement_evidence_result :
      Receipt.balance_updates
      -> Kind.double_endorsement_evidence contents_result
  | Double_preendorsement_evidence_result :
      Receipt.balance_updates
      -> Kind.double_preendorsement_evidence contents_result
  | Double_baking_evidence_result :
      Receipt.balance_updates
      -> Kind.double_baking_evidence contents_result
  | Activate_account_result :
      Receipt.balance_updates
      -> Kind.activate_account contents_result
  | Proposals_result : Kind.proposals contents_result
  | Ballot_result : Kind.ballot contents_result
  | Manager_operation_result : {
      balance_updates : Receipt.balance_updates;
      operation_result : 'kind manager_operation_result;
      internal_operation_results : packed_internal_operation_result list;
    }
      -> 'kind Kind.manager contents_result

type packed_contents_result =
  | Contents_result : 'kind contents_result -> packed_contents_result

type packed_contents_and_result =
  | Contents_and_result :
      'kind Operation.contents * 'kind contents_result
      -> packed_contents_and_result

type ('a, 'b) eq = Eq : ('a, 'a) eq [@@coq_force_gadt]

let equal_manager_kind :
    type a b. a Kind.manager -> b Kind.manager -> (a, b) eq option =
 fun ka kb ->
  match (ka, kb) with
  | (Kind.Reveal_manager_kind, Kind.Reveal_manager_kind) -> Some Eq
  | (Kind.Reveal_manager_kind, _) -> None
  | (Kind.Transaction_manager_kind, Kind.Transaction_manager_kind) -> Some Eq
  | (Kind.Transaction_manager_kind, _) -> None
  | (Kind.Origination_manager_kind, Kind.Origination_manager_kind) -> Some Eq
  | (Kind.Origination_manager_kind, _) -> None
  | (Kind.Delegation_manager_kind, Kind.Delegation_manager_kind) -> Some Eq
  | (Kind.Delegation_manager_kind, _) -> None
  | ( Kind.Register_global_constant_manager_kind,
      Kind.Register_global_constant_manager_kind ) ->
      Some Eq
  | (Kind.Register_global_constant_manager_kind, _) -> None
  | (Kind.Set_deposits_limit_manager_kind, Kind.Set_deposits_limit_manager_kind)
    ->
      Some Eq
  | (Kind.Set_deposits_limit_manager_kind, _) -> None

module Encoding = struct
  type 'kind case =
    | Case : {
        op_case : 'kind Operation.Encoding.case;
        encoding : 'a Data_encoding.t;
        select : packed_contents_result -> 'kind contents_result option;
        mselect :
          packed_contents_and_result ->
          ('kind contents * 'kind contents_result) option;
        proj : 'kind contents_result -> 'a;
        inj : 'a -> 'kind contents_result;
      }
        -> 'kind case

  let tagged_case tag name args proj inj =
    let open Data_encoding in
    case
      tag
      ~title:(String.capitalize_ascii name)
      (merge_objs (obj1 (req "kind" (constant name))) args)
      (fun x -> match proj x with None -> None | Some x -> Some ((), x))
      (fun ((), x) -> inj x)

  let[@coq_axiom_with_reason "gadt"] preendorsement_case =
    Case
      {
        op_case = Operation.Encoding.preendorsement_case;
        encoding =
          obj3
            (req "balance_updates" Receipt.balance_updates_encoding)
            (req "delegate" Signature.Public_key_hash.encoding)
            (req "preendorsement_power" int31);
        select =
          (function
          | Contents_result (Preendorsement_result _ as op) -> Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Preendorsement _ as op), res) -> Some (op, res)
          | _ -> None);
        proj =
          (function
          | Preendorsement_result
              {balance_updates; delegate; preendorsement_power} ->
              (balance_updates, delegate, preendorsement_power));
        inj =
          (fun (balance_updates, delegate, preendorsement_power) ->
            Preendorsement_result
              {balance_updates; delegate; preendorsement_power});
      }

  let[@coq_axiom_with_reason "gadt"] endorsement_case =
    Case
      {
        op_case = Operation.Encoding.endorsement_case;
        encoding =
          obj3
            (req "balance_updates" Receipt.balance_updates_encoding)
            (req "delegate" Signature.Public_key_hash.encoding)
            (req "endorsement_power" int31);
        select =
          (function
          | Contents_result (Endorsement_result _ as op) -> Some op | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Endorsement _ as op), res) -> Some (op, res)
          | _ -> None);
        proj =
          (function
          | Endorsement_result {balance_updates; delegate; endorsement_power} ->
              (balance_updates, delegate, endorsement_power));
        inj =
          (fun (balance_updates, delegate, endorsement_power) ->
            Endorsement_result {balance_updates; delegate; endorsement_power});
      }

  let[@coq_axiom_with_reason "gadt"] seed_nonce_revelation_case =
    Case
      {
        op_case = Operation.Encoding.seed_nonce_revelation_case;
        encoding = obj1 (req "balance_updates" Receipt.balance_updates_encoding);
        select =
          (function
          | Contents_result (Seed_nonce_revelation_result _ as op) -> Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Seed_nonce_revelation _ as op), res) ->
              Some (op, res)
          | _ -> None);
        proj = (fun (Seed_nonce_revelation_result bus) -> bus);
        inj = (fun bus -> Seed_nonce_revelation_result bus);
      }

  let[@coq_axiom_with_reason "gadt"] double_endorsement_evidence_case =
    Case
      {
        op_case = Operation.Encoding.double_endorsement_evidence_case;
        encoding = obj1 (req "balance_updates" Receipt.balance_updates_encoding);
        select =
          (function
          | Contents_result (Double_endorsement_evidence_result _ as op) ->
              Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Double_endorsement_evidence _ as op), res) ->
              Some (op, res)
          | _ -> None);
        proj = (fun (Double_endorsement_evidence_result bus) -> bus);
        inj = (fun bus -> Double_endorsement_evidence_result bus);
      }

  let[@coq_axiom_with_reason "gadt"] double_preendorsement_evidence_case =
    Case
      {
        op_case = Operation.Encoding.double_preendorsement_evidence_case;
        encoding = obj1 (req "balance_updates" Receipt.balance_updates_encoding);
        select =
          (function
          | Contents_result (Double_preendorsement_evidence_result _ as op) ->
              Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Double_preendorsement_evidence _ as op), res)
            ->
              Some (op, res)
          | _ -> None);
        proj = (fun (Double_preendorsement_evidence_result bus) -> bus);
        inj = (fun bus -> Double_preendorsement_evidence_result bus);
      }

  let[@coq_axiom_with_reason "gadt"] double_baking_evidence_case =
    Case
      {
        op_case = Operation.Encoding.double_baking_evidence_case;
        encoding = obj1 (req "balance_updates" Receipt.balance_updates_encoding);
        select =
          (function
          | Contents_result (Double_baking_evidence_result _ as op) -> Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Double_baking_evidence _ as op), res) ->
              Some (op, res)
          | _ -> None);
        proj = (fun (Double_baking_evidence_result bus) -> bus);
        inj = (fun bus -> Double_baking_evidence_result bus);
      }

  let[@coq_axiom_with_reason "gadt"] activate_account_case =
    Case
      {
        op_case = Operation.Encoding.activate_account_case;
        encoding = obj1 (req "balance_updates" Receipt.balance_updates_encoding);
        select =
          (function
          | Contents_result (Activate_account_result _ as op) -> Some op
          | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Activate_account _ as op), res) ->
              Some (op, res)
          | _ -> None);
        proj = (fun (Activate_account_result bus) -> bus);
        inj = (fun bus -> Activate_account_result bus);
      }

  let[@coq_axiom_with_reason "gadt"] proposals_case =
    Case
      {
        op_case = Operation.Encoding.proposals_case;
        encoding = Data_encoding.empty;
        select =
          (function
          | Contents_result (Proposals_result as op) -> Some op | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Proposals _ as op), res) -> Some (op, res)
          | _ -> None);
        proj = (fun Proposals_result -> ());
        inj = (fun () -> Proposals_result);
      }

  let[@coq_axiom_with_reason "gadt"] ballot_case =
    Case
      {
        op_case = Operation.Encoding.ballot_case;
        encoding = Data_encoding.empty;
        select =
          (function
          | Contents_result (Ballot_result as op) -> Some op | _ -> None);
        mselect =
          (function
          | Contents_and_result ((Ballot _ as op), res) -> Some (op, res)
          | _ -> None);
        proj = (fun Ballot_result -> ());
        inj = (fun () -> Ballot_result);
      }

  let[@coq_axiom_with_reason "gadt"] make_manager_case (type kind)
      (Operation.Encoding.Case op_case :
        kind Kind.manager Operation.Encoding.case)
      (Manager_result.MCase res_case : kind Manager_result.case) mselect =
    Case
      {
        op_case = Operation.Encoding.Case op_case;
        encoding =
          obj3
            (req "balance_updates" Receipt.balance_updates_encoding)
            (req "operation_result" res_case.t)
            (dft
               "internal_operation_results"
               (list internal_operation_result_encoding)
               []);
        select =
          (function
          | Contents_result
              (Manager_operation_result
                ({operation_result = Applied res; _} as op)) -> (
              match res_case.select (Successful_manager_result res) with
              | Some res ->
                  Some
                    (Manager_operation_result
                       {op with operation_result = Applied res})
              | None -> None)
          | Contents_result
              (Manager_operation_result
                ({operation_result = Backtracked (res, errs); _} as op)) -> (
              match res_case.select (Successful_manager_result res) with
              | Some res ->
                  Some
                    (Manager_operation_result
                       {op with operation_result = Backtracked (res, errs)})
              | None -> None)
          | Contents_result
              (Manager_operation_result
                ({operation_result = Skipped kind; _} as op)) -> (
              match equal_manager_kind kind res_case.kind with
              | None -> None
              | Some Eq ->
                  Some
                    (Manager_operation_result
                       {op with operation_result = Skipped kind}))
          | Contents_result
              (Manager_operation_result
                ({operation_result = Failed (kind, errs); _} as op)) -> (
              match equal_manager_kind kind res_case.kind with
              | None -> None
              | Some Eq ->
                  Some
                    (Manager_operation_result
                       {op with operation_result = Failed (kind, errs)}))
          | Contents_result (Preendorsement_result _) -> None
          | Contents_result (Endorsement_result _) -> None
          | Contents_result Ballot_result -> None
          | Contents_result (Seed_nonce_revelation_result _) -> None
          | Contents_result (Double_endorsement_evidence_result _) -> None
          | Contents_result (Double_preendorsement_evidence_result _) -> None
          | Contents_result (Double_baking_evidence_result _) -> None
          | Contents_result (Activate_account_result _) -> None
          | Contents_result Proposals_result -> None);
        mselect;
        proj =
          (fun (Manager_operation_result
                 {
                   balance_updates = bus;
                   operation_result = r;
                   internal_operation_results = rs;
                 }) ->
            (bus, r, rs));
        inj =
          (fun (bus, r, rs) ->
            Manager_operation_result
              {
                balance_updates = bus;
                operation_result = r;
                internal_operation_results = rs;
              });
      }

  let[@coq_axiom_with_reason "gadt"] reveal_case =
    make_manager_case
      Operation.Encoding.reveal_case
      Manager_result.reveal_case
      (function
        | Contents_and_result
            ((Manager_operation {operation = Reveal _; _} as op), res) ->
            Some (op, res)
        | _ -> None)

  let[@coq_axiom_with_reason "gadt"] transaction_case =
    make_manager_case
      Operation.Encoding.transaction_case
      Manager_result.transaction_case
      (function
        | Contents_and_result
            ((Manager_operation {operation = Transaction _; _} as op), res) ->
            Some (op, res)
        | _ -> None)

  let[@coq_axiom_with_reason "gadt"] origination_case =
    make_manager_case
      Operation.Encoding.origination_case
      Manager_result.origination_case
      (function
        | Contents_and_result
            ((Manager_operation {operation = Origination _; _} as op), res) ->
            Some (op, res)
        | _ -> None)

  let[@coq_axiom_with_reason "gadt"] delegation_case =
    make_manager_case
      Operation.Encoding.delegation_case
      Manager_result.delegation_case
      (function
        | Contents_and_result
            ((Manager_operation {operation = Delegation _; _} as op), res) ->
            Some (op, res)
        | _ -> None)

  let[@coq_axiom_with_reason "gadt"] register_global_constant_case =
    make_manager_case
      Operation.Encoding.register_global_constant_case
      Manager_result.register_global_constant_case
      (function
        | Contents_and_result
            ( (Manager_operation {operation = Register_global_constant _; _} as
              op),
              res ) ->
            Some (op, res)
        | _ -> None)

  let[@coq_axiom_with_reason "gadt"] set_deposits_limit_case =
    make_manager_case
      Operation.Encoding.set_deposits_limit_case
      Manager_result.set_deposits_limit_case
      (function
        | Contents_and_result
            ( (Manager_operation {operation = Set_deposits_limit _; _} as op),
              res ) ->
            Some (op, res)
        | _ -> None)
end

let contents_result_encoding =
  let open Encoding in
  let make
      (Case
        {
          op_case = Operation.Encoding.Case {tag; name; _};
          encoding;
          mselect = _;
          select;
          proj;
          inj;
        }) =
    let proj x = match select x with None -> None | Some x -> Some (proj x) in
    let inj x = Contents_result (inj x) in
    tagged_case (Tag tag) name encoding proj inj
  in
  def "operation.alpha.contents_result"
  @@ union
       [
         make seed_nonce_revelation_case;
         make endorsement_case;
         make preendorsement_case;
         make double_preendorsement_evidence_case;
         make double_endorsement_evidence_case;
         make double_baking_evidence_case;
         make activate_account_case;
         make proposals_case;
         make ballot_case;
         make reveal_case;
         make transaction_case;
         make origination_case;
         make delegation_case;
         make register_global_constant_case;
         make set_deposits_limit_case;
       ]

let contents_and_result_encoding =
  let open Encoding in
  let make
      (Case
        {
          op_case = Operation.Encoding.Case {tag; name; encoding; proj; inj; _};
          mselect;
          encoding = meta_encoding;
          proj = meta_proj;
          inj = meta_inj;
          _;
        }) =
    let proj c =
      match mselect c with
      | Some (op, res) -> Some (proj op, meta_proj res)
      | _ -> None
    in
    let inj (op, res) = Contents_and_result (inj op, meta_inj res) in
    let encoding = merge_objs encoding (obj1 (req "metadata" meta_encoding)) in
    tagged_case (Tag tag) name encoding proj inj
  in
  def "operation.alpha.operation_contents_and_result"
  @@ union
       [
         make seed_nonce_revelation_case;
         make endorsement_case;
         make preendorsement_case;
         make double_preendorsement_evidence_case;
         make double_endorsement_evidence_case;
         make double_baking_evidence_case;
         make activate_account_case;
         make proposals_case;
         make ballot_case;
         make reveal_case;
         make transaction_case;
         make origination_case;
         make delegation_case;
         make register_global_constant_case;
         make set_deposits_limit_case;
       ]

type 'kind contents_result_list =
  | Single_result : 'kind contents_result -> 'kind contents_result_list
  | Cons_result :
      'kind Kind.manager contents_result
      * 'rest Kind.manager contents_result_list
      -> ('kind * 'rest) Kind.manager contents_result_list

type packed_contents_result_list =
  | Contents_result_list :
      'kind contents_result_list
      -> packed_contents_result_list

let contents_result_list_encoding =
  let rec to_list = function
    | Contents_result_list (Single_result o) -> [Contents_result o]
    | Contents_result_list (Cons_result (o, os)) ->
        Contents_result o :: to_list (Contents_result_list os)
  in
  let rec of_list = function
    | [] -> Error "cannot decode empty operation result"
    | [Contents_result o] -> Ok (Contents_result_list (Single_result o))
    | Contents_result o :: os -> (
        of_list os >>? fun (Contents_result_list os) ->
        match (o, os) with
        | ( Manager_operation_result _,
            Single_result (Manager_operation_result _) ) ->
            Ok (Contents_result_list (Cons_result (o, os)))
        | (Manager_operation_result _, Cons_result _) ->
            Ok (Contents_result_list (Cons_result (o, os)))
        | _ -> Error "cannot decode ill-formed operation result")
  in
  def "operation.alpha.contents_list_result"
  @@ conv_with_guard to_list of_list (list contents_result_encoding)

type 'kind contents_and_result_list =
  | Single_and_result :
      'kind Alpha_context.contents * 'kind contents_result
      -> 'kind contents_and_result_list
  | Cons_and_result :
      'kind Kind.manager Alpha_context.contents
      * 'kind Kind.manager contents_result
      * 'rest Kind.manager contents_and_result_list
      -> ('kind * 'rest) Kind.manager contents_and_result_list

type packed_contents_and_result_list =
  | Contents_and_result_list :
      'kind contents_and_result_list
      -> packed_contents_and_result_list

let contents_and_result_list_encoding =
  let rec to_list = function
    | Contents_and_result_list (Single_and_result (op, res)) ->
        [Contents_and_result (op, res)]
    | Contents_and_result_list (Cons_and_result (op, res, rest)) ->
        Contents_and_result (op, res) :: to_list (Contents_and_result_list rest)
  in
  let rec of_list = function
    | [] -> Error "cannot decode empty combined operation result"
    | [Contents_and_result (op, res)] ->
        Ok (Contents_and_result_list (Single_and_result (op, res)))
    | Contents_and_result (op, res) :: rest -> (
        of_list rest >>? fun (Contents_and_result_list rest) ->
        match (op, rest) with
        | (Manager_operation _, Single_and_result (Manager_operation _, _)) ->
            Ok (Contents_and_result_list (Cons_and_result (op, res, rest)))
        | (Manager_operation _, Cons_and_result (_, _, _)) ->
            Ok (Contents_and_result_list (Cons_and_result (op, res, rest)))
        | _ -> Error "cannot decode ill-formed combined operation result")
  in
  conv_with_guard to_list of_list (Variable.list contents_and_result_encoding)

type 'kind operation_metadata = {contents : 'kind contents_result_list}

type packed_operation_metadata =
  | Operation_metadata : 'kind operation_metadata -> packed_operation_metadata
  | No_operation_metadata : packed_operation_metadata

let operation_metadata_encoding =
  def "operation.alpha.result"
  @@ union
       [
         case
           (Tag 0)
           ~title:"Operation_metadata"
           contents_result_list_encoding
           (function
             | Operation_metadata {contents} ->
                 Some (Contents_result_list contents)
             | _ -> None)
           (fun (Contents_result_list contents) ->
             Operation_metadata {contents});
         case
           (Tag 1)
           ~title:"No_operation_metadata"
           empty
           (function No_operation_metadata -> Some () | _ -> None)
           (fun () -> No_operation_metadata);
       ]

let kind_equal :
    type kind kind2.
    kind contents -> kind2 contents_result -> (kind, kind2) eq option =
 fun op res ->
  match (op, res) with
  | (Endorsement _, Endorsement_result _) -> Some Eq
  | (Endorsement _, _) -> None
  | (Preendorsement _, Preendorsement_result _) -> Some Eq
  | (Preendorsement _, _) -> None
  | (Seed_nonce_revelation _, Seed_nonce_revelation_result _) -> Some Eq
  | (Seed_nonce_revelation _, _) -> None
  | (Double_preendorsement_evidence _, Double_preendorsement_evidence_result _)
    ->
      Some Eq
  | (Double_preendorsement_evidence _, _) -> None
  | (Double_endorsement_evidence _, Double_endorsement_evidence_result _) ->
      Some Eq
  | (Double_endorsement_evidence _, _) -> None
  | (Double_baking_evidence _, Double_baking_evidence_result _) -> Some Eq
  | (Double_baking_evidence _, _) -> None
  | (Activate_account _, Activate_account_result _) -> Some Eq
  | (Activate_account _, _) -> None
  | (Proposals _, Proposals_result) -> Some Eq
  | (Proposals _, _) -> None
  | (Ballot _, Ballot_result) -> Some Eq
  | (Ballot _, _) -> None
  | (Failing_noop _, _) ->
      (* the Failing_noop operation always fails and can't have result *)
      None
  | ( Manager_operation {operation = Reveal _; _},
      Manager_operation_result {operation_result = Applied (Reveal_result _); _}
    ) ->
      Some Eq
  | ( Manager_operation {operation = Reveal _; _},
      Manager_operation_result
        {operation_result = Backtracked (Reveal_result _, _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Reveal _; _},
      Manager_operation_result
        {
          operation_result = Failed (Alpha_context.Kind.Reveal_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Reveal _; _},
      Manager_operation_result
        {operation_result = Skipped Alpha_context.Kind.Reveal_manager_kind; _}
    ) ->
      Some Eq
  | (Manager_operation {operation = Reveal _; _}, _) -> None
  | ( Manager_operation {operation = Transaction _; _},
      Manager_operation_result
        {operation_result = Applied (Transaction_result _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Transaction _; _},
      Manager_operation_result
        {operation_result = Backtracked (Transaction_result _, _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Transaction _; _},
      Manager_operation_result
        {
          operation_result =
            Failed (Alpha_context.Kind.Transaction_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Transaction _; _},
      Manager_operation_result
        {
          operation_result = Skipped Alpha_context.Kind.Transaction_manager_kind;
          _;
        } ) ->
      Some Eq
  | (Manager_operation {operation = Transaction _; _}, _) -> None
  | ( Manager_operation {operation = Origination _; _},
      Manager_operation_result
        {operation_result = Applied (Origination_result _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Origination _; _},
      Manager_operation_result
        {operation_result = Backtracked (Origination_result _, _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Origination _; _},
      Manager_operation_result
        {
          operation_result =
            Failed (Alpha_context.Kind.Origination_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Origination _; _},
      Manager_operation_result
        {
          operation_result = Skipped Alpha_context.Kind.Origination_manager_kind;
          _;
        } ) ->
      Some Eq
  | (Manager_operation {operation = Origination _; _}, _) -> None
  | ( Manager_operation {operation = Delegation _; _},
      Manager_operation_result
        {operation_result = Applied (Delegation_result _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Delegation _; _},
      Manager_operation_result
        {operation_result = Backtracked (Delegation_result _, _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Delegation _; _},
      Manager_operation_result
        {
          operation_result =
            Failed (Alpha_context.Kind.Delegation_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Delegation _; _},
      Manager_operation_result
        {
          operation_result = Skipped Alpha_context.Kind.Delegation_manager_kind;
          _;
        } ) ->
      Some Eq
  | (Manager_operation {operation = Delegation _; _}, _) -> None
  | ( Manager_operation {operation = Register_global_constant _; _},
      Manager_operation_result
        {operation_result = Applied (Register_global_constant_result _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Register_global_constant _; _},
      Manager_operation_result
        {
          operation_result = Backtracked (Register_global_constant_result _, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Register_global_constant _; _},
      Manager_operation_result
        {
          operation_result =
            Failed (Alpha_context.Kind.Register_global_constant_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Register_global_constant _; _},
      Manager_operation_result
        {
          operation_result =
            Skipped Alpha_context.Kind.Register_global_constant_manager_kind;
          _;
        } ) ->
      Some Eq
  | (Manager_operation {operation = Register_global_constant _; _}, _) -> None
  | ( Manager_operation {operation = Set_deposits_limit _; _},
      Manager_operation_result
        {operation_result = Applied (Set_deposits_limit_result _); _} ) ->
      Some Eq
  | ( Manager_operation {operation = Set_deposits_limit _; _},
      Manager_operation_result
        {operation_result = Backtracked (Set_deposits_limit_result _, _); _} )
    ->
      Some Eq
  | ( Manager_operation {operation = Set_deposits_limit _; _},
      Manager_operation_result
        {
          operation_result =
            Failed (Alpha_context.Kind.Set_deposits_limit_manager_kind, _);
          _;
        } ) ->
      Some Eq
  | ( Manager_operation {operation = Set_deposits_limit _; _},
      Manager_operation_result
        {
          operation_result =
            Skipped Alpha_context.Kind.Set_deposits_limit_manager_kind;
          _;
        } ) ->
      Some Eq
  | (Manager_operation {operation = Set_deposits_limit _; _}, _) -> None

let rec kind_equal_list :
    type kind kind2.
    kind contents_list -> kind2 contents_result_list -> (kind, kind2) eq option
    =
 fun contents res ->
  match (contents, res) with
  | (Single op, Single_result res) -> (
      match kind_equal op res with None -> None | Some Eq -> Some Eq)
  | (Cons (op, ops), Cons_result (res, ress)) -> (
      match kind_equal op res with
      | None -> None
      | Some Eq -> (
          match kind_equal_list ops ress with
          | None -> None
          | Some Eq -> Some Eq))
  | _ -> None

let[@coq_axiom_with_reason "gadt"] rec pack_contents_list :
    type kind.
    kind contents_list ->
    kind contents_result_list ->
    kind contents_and_result_list =
 fun contents res ->
  match (contents, res) with
  | (Single op, Single_result res) -> Single_and_result (op, res)
  | (Cons (op, ops), Cons_result (res, ress)) ->
      Cons_and_result (op, res, pack_contents_list ops ress)
  | ( Single (Manager_operation _),
      Cons_result (Manager_operation_result _, Single_result _) ) ->
      .
  | ( Cons (_, _),
      Single_result (Manager_operation_result {operation_result = Failed _; _})
    ) ->
      .
  | ( Cons (_, _),
      Single_result (Manager_operation_result {operation_result = Skipped _; _})
    ) ->
      .
  | ( Cons (_, _),
      Single_result (Manager_operation_result {operation_result = Applied _; _})
    ) ->
      .
  | ( Cons (_, _),
      Single_result
        (Manager_operation_result {operation_result = Backtracked _; _}) ) ->
      .
  | (Single _, Cons_result _) -> .

let rec unpack_contents_list :
    type kind.
    kind contents_and_result_list ->
    kind contents_list * kind contents_result_list = function
  | Single_and_result (op, res) -> (Single op, Single_result res)
  | Cons_and_result (op, res, rest) ->
      let (ops, ress) = unpack_contents_list rest in
      (Cons (op, ops), Cons_result (res, ress))

let rec to_list = function
  | Contents_result_list (Single_result o) -> [Contents_result o]
  | Contents_result_list (Cons_result (o, os)) ->
      Contents_result o :: to_list (Contents_result_list os)

let operation_data_and_metadata_encoding =
  def "operation.alpha.operation_with_metadata"
  @@ union
       [
         case
           (Tag 0)
           ~title:"Operation_with_metadata"
           (obj2
              (req "contents" (dynamic_size contents_and_result_list_encoding))
              (opt "signature" Signature.encoding))
           (function
             | (Operation_data _, No_operation_metadata) -> None
             | (Operation_data op, Operation_metadata res) -> (
                 match kind_equal_list op.contents res.contents with
                 | None ->
                     Pervasives.failwith
                       "cannot decode inconsistent combined operation result"
                 | Some Eq ->
                     Some
                       ( Contents_and_result_list
                           (pack_contents_list op.contents res.contents),
                         op.signature )))
           (fun (Contents_and_result_list contents, signature) ->
             let (op_contents, res_contents) = unpack_contents_list contents in
             ( Operation_data {contents = op_contents; signature},
               Operation_metadata {contents = res_contents} ));
         case
           (Tag 1)
           ~title:"Operation_without_metadata"
           (obj2
              (req "contents" (dynamic_size Operation.contents_list_encoding))
              (opt "signature" Signature.encoding))
           (function
             | (Operation_data op, No_operation_metadata) ->
                 Some (Contents_list op.contents, op.signature)
             | (Operation_data _, Operation_metadata _) -> None)
           (fun (Contents_list contents, signature) ->
             (Operation_data {contents; signature}, No_operation_metadata));
       ]

type block_metadata = {
  proposer : Signature.Public_key_hash.t;
  baker : Signature.Public_key_hash.t;
  level_info : Level.t;
  voting_period_info : Voting_period.info;
  nonce_hash : Nonce_hash.t option;
  consumed_gas : Gas.Arith.fp;
  deactivated : Signature.Public_key_hash.t list;
  balance_updates : Receipt.balance_updates;
  liquidity_baking_escape_ema : Liquidity_baking.escape_ema;
  implicit_operations_results : packed_successful_manager_operation_result list;
}

let block_metadata_encoding =
  let open Data_encoding in
  def "block_header.alpha.metadata"
  @@ conv
       (fun {
              proposer;
              baker;
              level_info;
              voting_period_info;
              nonce_hash;
              consumed_gas;
              deactivated;
              balance_updates;
              liquidity_baking_escape_ema;
              implicit_operations_results;
            } ->
         ( proposer,
           baker,
           level_info,
           voting_period_info,
           nonce_hash,
           consumed_gas,
           deactivated,
           balance_updates,
           liquidity_baking_escape_ema,
           implicit_operations_results ))
       (fun ( proposer,
              baker,
              level_info,
              voting_period_info,
              nonce_hash,
              consumed_gas,
              deactivated,
              balance_updates,
              liquidity_baking_escape_ema,
              implicit_operations_results ) ->
         {
           proposer;
           baker;
           level_info;
           voting_period_info;
           nonce_hash;
           consumed_gas;
           deactivated;
           balance_updates;
           liquidity_baking_escape_ema;
           implicit_operations_results;
         })
       (obj10
          (req "proposer" Signature.Public_key_hash.encoding)
          (req "baker" Signature.Public_key_hash.encoding)
          (req "level_info" Level.encoding)
          (req "voting_period_info" Voting_period.info_encoding)
          (req "nonce_hash" (option Nonce_hash.encoding))
          (req "consumed_gas" Gas.Arith.n_fp_encoding)
          (req "deactivated" (list Signature.Public_key_hash.encoding))
          (req "balance_updates" Receipt.balance_updates_encoding)
          (req "liquidity_baking_escape_ema" int32)
          (req
             "implicit_operations_results"
             (list successful_manager_operation_result_encoding)))

type precheck_result = {
  consumed_gas : Gas.Arith.fp;
  balance_updates : Receipt.balance_updates;
}

type 'kind prechecked_contents = {
  contents : 'kind contents;
  result : precheck_result;
}

type _ prechecked_contents_list =
  | PrecheckedSingle :
      'kind prechecked_contents
      -> 'kind prechecked_contents_list
  | PrecheckedCons :
      'kind Kind.manager prechecked_contents
      * 'rest Kind.manager prechecked_contents_list
      -> ('kind * 'rest) Kind.manager prechecked_contents_list
