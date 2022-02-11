(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs, <contact@nomadic-labs.com>               *)
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
    Component:  Protocol (Gas levels)
    Invocation: dune exec \
                src/proto_alpha/lib_protocol/test/integration/gas/main.exe \
                -- test "^gas levels$"
    Subject:    On gas consumption and exhaustion.
*)

open Protocol
open Raw_context
module S = Saturation_repr

(* This value is supposed to be larger than the block gas level limit
   but not saturated. *)
let opg = max_int / 10000

exception Gas_levels_test_error of string

let err x = Exn (Gas_levels_test_error x)

let succeed x = match x with Ok _ -> true | _ -> false

let failed x = not (succeed x)

let dummy_context () =
  Context.init ~consensus_threshold:0 1 >>=? fun (block, _) ->
  Raw_context.prepare
    ~level:Int32.zero
    ~predecessor_timestamp:Time.Protocol.epoch
    ~timestamp:Time.Protocol.epoch
    (* ~fitness:[] *)
    (block.context : Environment_context.Context.t)
  >|= Environment.wrap_tzresult

let consume_gas_lwt context gas =
  Lwt.return (consume_gas context (S.safe_int gas))
  >|= Environment.wrap_tzresult

let consume_gas_limit_in_block_lwt context gas =
  Lwt.return (consume_gas_limit_in_block context gas)
  >|= Environment.wrap_tzresult

let test_detect_gas_exhaustion_in_fresh_context () =
  dummy_context () >>=? fun context ->
  fail_unless
    (consume_gas context (S.safe_int opg) |> succeed)
    (err "In a fresh context, gas consumption is unlimited.")

(** Create a context with a given block gas level, capped at the
    hard gas limit per block *)
let make_context remaining_block_gas =
  let open Gas_limit_repr in
  dummy_context () >>=? fun context ->
  let hard_limit = Arith.fp (constants context).hard_gas_limit_per_operation in
  let hard_limit_block =
    Arith.fp (constants context).hard_gas_limit_per_block
  in
  let block_gas = Arith.(unsafe_fp (Z.of_int remaining_block_gas)) in
  let rec aux context to_consume =
    (* Because of saturated arithmetic, [to_consume] should never be negative. *)
    assert (Arith.(to_consume >= zero)) ;
    if Arith.(to_consume = zero) then return context
    else if Arith.(to_consume <= hard_limit) then
      consume_gas_limit_in_block_lwt context to_consume
    else
      consume_gas_limit_in_block_lwt context hard_limit >>=? fun context ->
      aux context (Arith.sub to_consume hard_limit)
  in
  aux context Arith.(sub hard_limit_block block_gas)

(** Test operation gas exhaustion. Should pass when remaining gas is 0,
    and fail when it goes over *)
let test_detect_gas_exhaustion_when_operation_gas_hits_zero () =
  let gas_op = 100000 in
  dummy_context () >>=? fun context ->
  set_gas_limit context (Gas_limit_repr.Arith.unsafe_fp (Z.of_int gas_op))
  |> fun context ->
  fail_unless
    (consume_gas context (S.safe_int gas_op) |> succeed)
    (err "Succeed when consuming exactly the remaining operation gas.")
  >>=? fun () ->
  fail_unless
    (consume_gas context (S.safe_int (gas_op + 1)) |> failed)
    (err "Fail when consuming more than the remaining operation gas.")

(** Test block gas exhaustion *)
let test_detect_gas_exhaustion_when_block_gas_hits_zero () =
  let gas k = Gas_limit_repr.Arith.unsafe_fp (Z.of_int k) in
  let remaining_gas = gas 100000 and too_much = gas (100000 + 1) in
  make_context 100000 >>=? fun context ->
  fail_unless
    (consume_gas_limit_in_block context remaining_gas |> succeed)
    (err "Succeed when consuming exactly the remaining block gas.")
  >>=? fun () ->
  fail_unless
    (consume_gas_limit_in_block context too_much |> failed)
    (err "Fail when consuming more than the remaining block gas.")

(** Test invalid gas limit. Should fail when limit is above the hard gas limit per
    operation *)
let test_detect_gas_limit_consumption_above_hard_gas_operation_limit () =
  dummy_context () >>=? fun context ->
  fail_unless
    (consume_gas_limit_in_block
       context
       (Gas_limit_repr.Arith.unsafe_fp (Z.of_int opg))
    |> failed)
    (err
       "Fail when consuming gas above the hard limit per operation in the \
        block.")

(** For a given [context], check if its levels match those given in [block_level] and
    [operation_level] *)
let check_context_levels context block_level operation_level =
  let op_check =
    match gas_level context with
    | Unaccounted -> true
    | Limited {remaining} ->
        Gas_limit_repr.Arith.(unsafe_fp (Z.of_int operation_level) = remaining)
  in
  let block_check =
    Gas_limit_repr.Arith.(
      unsafe_fp (Z.of_int block_level) = block_gas_level context)
  in
  fail_unless
    (op_check || block_check)
    (err "Unexpected block and operation gas levels")
  >>=? fun () ->
  fail_unless op_check (err "Unexpected operation gas level") >>=? fun () ->
  fail_unless block_check (err "Unexpected block gas level")

let monitor remaining_block_gas initial_operation_level consumed_gas () =
  let op_limit =
    Gas_limit_repr.Arith.unsafe_fp (Z.of_int initial_operation_level)
  in
  make_context remaining_block_gas >>=? fun context ->
  consume_gas_limit_in_block_lwt context op_limit >>=? fun context ->
  set_gas_limit context op_limit |> fun context ->
  consume_gas_lwt context consumed_gas >>=? fun context ->
  check_context_levels
    context
    (remaining_block_gas - initial_operation_level)
    (initial_operation_level - consumed_gas)

let test_monitor_gas_level = monitor 1000 100 10

(** Test cas consumption mode switching (limited -> unlimited) *)
let test_set_gas_unlimited () =
  let init_block_gas = 100000 in
  let op_limit_int = 10000 in
  let op_limit = Gas_limit_repr.Arith.unsafe_fp (Z.of_int op_limit_int) in
  make_context init_block_gas >>=? fun context ->
  set_gas_limit context op_limit |> set_gas_unlimited |> fun context ->
  consume_gas_lwt context opg >>=? fun context ->
  check_context_levels context init_block_gas (-1)

(** Test cas consumption mode switching (unlimited -> limited) *)
let test_set_gas_limited () =
  let init_block_gas = 100000 in
  let op_limit_int = 10000 in
  let op_limit = Gas_limit_repr.Arith.unsafe_fp (Z.of_int op_limit_int) in
  let op_gas = 100 in
  make_context init_block_gas >>=? fun context ->
  set_gas_unlimited context |> fun context ->
  set_gas_limit context op_limit |> fun context ->
  consume_gas_lwt context op_gas >>=? fun context ->
  check_context_levels context init_block_gas (op_limit_int - op_gas)

(*** Tests with blocks ***)

let apply_with_gas header ?(operations = []) (pred : Block.t) =
  let open Alpha_context in
  (let open Environment.Error_monad in
  begin_application
    ~chain_id:Chain_id.zero
    ~predecessor_context:pred.context
    ~predecessor_fitness:pred.header.shell.fitness
    ~predecessor_timestamp:pred.header.shell.timestamp
    header
  >>=? fun vstate ->
  List.fold_left_es
    (fun vstate op ->
      apply_operation vstate op >|=? fun (state, _result) -> state)
    vstate
    operations
  >>=? fun vstate ->
  finalize_block vstate (Some header.shell) >|=? fun (validation, result) ->
  (validation.context, result.consumed_gas))
  >|= Environment.wrap_tzresult
  >|=? fun (context, consumed_gas) ->
  let hash = Block_header.hash header in
  ({Block.hash; header; operations; context}, consumed_gas)

let bake_with_gas ?policy ?timestamp ?operation ?operations pred =
  let operations =
    match (operation, operations) with
    | (Some op, Some ops) -> Some (op :: ops)
    | (Some op, None) -> Some [op]
    | (None, Some ops) -> Some ops
    | (None, None) -> None
  in
  Block.Forge.forge_header ?timestamp ?policy ?operations pred
  >>=? fun header ->
  Block.Forge.sign_header header >>=? fun header ->
  apply_with_gas header ?operations pred

let check_consumed_gas consumed expected =
  fail_unless
    Alpha_context.Gas.Arith.(consumed = expected)
    (err
       (Format.asprintf
          "Gas discrepancy: consumed gas : %a | expected : %a\n"
          Alpha_context.Gas.Arith.pp
          consumed
          Alpha_context.Gas.Arith.pp
          expected))

let lazy_unit = Alpha_context.Script.lazy_expr (Expr.from_string "Unit")

let prepare_origination block source script =
  let code = Expr.toplevel_from_string script in
  let script =
    Alpha_context.Script.{code = lazy_expr code; storage = lazy_unit}
  in
  Op.contract_origination (B block) source ~script

let originate_contract block source script =
  prepare_origination block source script >>=? fun (operation, dst) ->
  Block.bake ~operation block >>=? fun block -> return (block, dst)

let init_block to_originate =
  Context.init ~consensus_threshold:0 1 >>=? fun (block, contracts) ->
  let src = WithExceptions.Option.get ~loc:__LOC__ @@ List.hd contracts in
  (*** originate contracts ***)
  let rec full_originate block originated = function
    | [] -> return (block, List.rev originated)
    | h :: t ->
        originate_contract block src h >>=? fun (block, ct) ->
        full_originate block (ct :: originated) t
  in
  full_originate block [] to_originate >>=? fun (block, originated) ->
  return (block, src, originated)

let nil_contract =
  "parameter unit;\n\
   storage unit;\n\
   code {\n\
  \       DROP;\n\
  \       UNIT; NIL operation; PAIR\n\
  \     }\n"

let fail_contract = "parameter unit; storage unit; code { FAIL }"

let loop_contract =
  "parameter unit;\n\
   storage unit;\n\
   code {\n\
  \       DROP;\n\
  \       PUSH bool True;\n\
  \       LOOP {\n\
  \              PUSH string \"GASGASGAS\";\n\
  \              PACK;\n\
  \              SHA3;\n\
  \              DROP;\n\
  \              PUSH bool True\n\
  \            };\n\
  \       UNIT; NIL operation; PAIR\n\
  \     }\n"

let block_with_one_origination contract =
  init_block [contract] >>=? fun (block, src, originated) ->
  match originated with [dst] -> return (block, src, dst) | _ -> assert false

let full_block () =
  init_block [nil_contract; fail_contract; loop_contract]
  >>=? fun (block, src, originated) ->
  let (dst_nil, dst_fail, dst_loop) =
    match originated with [c1; c2; c3] -> (c1, c2, c3) | _ -> assert false
  in
  return (block, src, dst_nil, dst_fail, dst_loop)

(** Combine a list of operations into an operation list. Also returns
    the sum of their gas limits.*)
let combine_operations_with_gas ?counter block src list_dst =
  let rec make_op_list full_gas op_list = function
    | [] -> return (full_gas, List.rev op_list)
    | (dst, gas_limit) :: t ->
        Op.transaction ~gas_limit (B block) src dst Alpha_context.Tez.zero
        >>=? fun op ->
        make_op_list
          (Alpha_context.Gas.Arith.add full_gas gas_limit)
          (op :: op_list)
          t
  in
  make_op_list Alpha_context.Gas.Arith.zero [] list_dst
  >>=? fun (full_gas, op_list) ->
  Op.combine_operations ?counter ~source:src (B block) op_list
  >>=? fun operation -> return (operation, full_gas)

(** Applies [combine_operations_with_gas] to lists in a list, then bake a block
    with this list of operations. Also returns the sum of all gas limits *)
let bake_operations_with_gas ?counter block src list_list_dst =
  let counter = Option.value ~default:Z.zero counter in
  let rec make_list full_gas op_list counter = function
    | [] -> return (full_gas, List.rev op_list)
    | list_dst :: t ->
        let n = Z.of_int (List.length list_dst) in
        combine_operations_with_gas ~counter block src list_dst
        >>=? fun (op, gas) ->
        make_list
          (Alpha_context.Gas.Arith.add full_gas gas)
          (op :: op_list)
          (Z.add counter n)
          t
  in
  make_list Alpha_context.Gas.Arith.zero [] counter list_list_dst
  >>=? fun (gas_limit_total, operations) ->
  bake_with_gas ~operations block >>=? fun (block, consumed_gas) ->
  return (block, consumed_gas, gas_limit_total)

let basic_gas_sampler () =
  Alpha_context.Gas.Arith.integral_of_int_exn (100 + Random.int 900)

let generic_test_block_one_origination contract gas_sampler structure =
  block_with_one_origination contract >>=? fun (block, src, dst) ->
  let lld = List.map (List.map (fun _ -> (dst, gas_sampler ()))) structure in
  bake_operations_with_gas ~counter:Z.one block src lld
  >>=? fun (_block, consumed_gas, gas_limit_total) ->
  check_consumed_gas consumed_gas gas_limit_total

let make_batch_test_block_one_origination name contract gas_sampler =
  let test = generic_test_block_one_origination contract gas_sampler in
  let test_one_operation () = test [[()]] in
  let test_one_operation_list () = test [[(); (); ()]] in
  let test_many_single_operations () = test [[()]; [()]; [()]] in
  let test_mixed_operations () = test [[(); ()]; [()]; [(); (); ()]] in
  let app_n = List.map (fun (x, y) -> (x ^ " with contract " ^ name, y)) in
  app_n
    [
      ("Test bake one operation", test_one_operation);
      ("Test bake one operation list", test_one_operation_list);
      ("Test multiple single operations", test_many_single_operations);
      ("Test both lists and single operations", test_mixed_operations);
    ]

(** Tests the consumption of all gas in a block, should pass *)
let test_consume_exactly_all_block_gas () =
  block_with_one_origination nil_contract >>=? fun (block, src, dst) ->
  (* assumptions:
     hard gas limit per operation = 1040000
     hard gas limit per block = 5200000
  *)
  let lld =
    List.map
      (fun _ -> [(dst, Alpha_context.Gas.Arith.integral_of_int_exn 1040000)])
      [1; 1; 1; 1; 1]
  in
  bake_operations_with_gas ~counter:Z.one block src lld >>=? fun _ -> return ()

(** Tests the consumption of more than the block gas level with many single
    operations, should fail *)
let test_malformed_block_max_limit_reached () =
  block_with_one_origination nil_contract >>=? fun (block, src, dst) ->
  (* assumptions:
     hard gas limit per operation = 1040000
     hard gas limit per block = 5200000
  *)
  let lld =
    [(dst, Alpha_context.Gas.Arith.integral_of_int_exn 1)]
    ::
    List.map
      (fun _ -> [(dst, Alpha_context.Gas.Arith.integral_of_int_exn 1040000)])
      [1; 1; 1; 1; 1]
  in
  bake_operations_with_gas ~counter:Z.one block src lld >>= function
  | Error _ -> return_unit
  | Ok _ ->
      fail
        (err
           "Invalid block: sum of operation gas limits exceeds hard gas limit \
            per block")

(** Tests the consumption of more than the block gas level with one big
    operation list, should fail *)
let test_malformed_block_max_limit_reached' () =
  block_with_one_origination nil_contract >>=? fun (block, src, dst) ->
  (* assumptions:
     hard gas limit per operation = 1040000
     hard gas limit per block = 5200000
  *)
  let lld =
    [
      (dst, Alpha_context.Gas.Arith.integral_of_int_exn 1)
      ::
      List.map
        (fun _ -> (dst, Alpha_context.Gas.Arith.integral_of_int_exn 1040000))
        [1; 1; 1; 1; 1];
    ]
  in
  bake_operations_with_gas ~counter:Z.one block src lld >>= function
  | Error _ -> return_unit
  | Ok _ ->
      fail
        (err
           "Invalid block: sum of gas limits in operation list exceeds hard \
            gas limit per block")

let test_block_mixed_operations () =
  full_block () >>=? fun (block, src, dst_nil, dst_fail, dst_loop) ->
  let l = [[dst_nil]; [dst_nil; dst_fail; dst_nil]; [dst_loop]; [dst_nil]] in
  let lld = List.map (List.map (fun x -> (x, basic_gas_sampler ()))) l in
  bake_operations_with_gas ~counter:(Z.of_int 3) block src lld
  >>=? fun (_block, consumed_gas, gas_limit_total) ->
  check_consumed_gas consumed_gas gas_limit_total

let quick (what, how) = Tztest.tztest what `Quick how

let tests =
  List.map
    quick
    ([
       ( "Detect gas exhaustion in fresh context",
         test_detect_gas_exhaustion_in_fresh_context );
       ( "Detect gas exhaustion when operation gas as hits zero",
         test_detect_gas_exhaustion_when_operation_gas_hits_zero );
       ( "Detect gas exhaustion when block gas as hits zero",
         test_detect_gas_exhaustion_when_block_gas_hits_zero );
       ( "Detect gas limit consumption when it is above the hard gas operation \
          limit",
         test_detect_gas_limit_consumption_above_hard_gas_operation_limit );
       ( "Each new operation impacts block gas level, each gas consumption \
          impacts operation gas level",
         test_monitor_gas_level );
       ( "Switches operation gas consumption from limited to unlimited",
         test_set_gas_unlimited );
       ( "Switches operation gas consumption from unlimited to limited",
         test_set_gas_limited );
       ( "Accepts a block that consumes all of its gas",
         test_consume_exactly_all_block_gas );
       ( "Detect when the sum of all operation gas limits exceeds the hard gas \
          limit per block",
         test_malformed_block_max_limit_reached );
       ( "Detect when gas limit of operation list exceeds the hard gas limit \
          per block",
         test_malformed_block_max_limit_reached' );
       ( "Test the gas consumption of various operations",
         test_block_mixed_operations );
     ]
    @ make_batch_test_block_one_origination "nil" nil_contract basic_gas_sampler
    @ make_batch_test_block_one_origination
        "fail"
        fail_contract
        basic_gas_sampler
    @ make_batch_test_block_one_origination
        "infinite loop"
        loop_contract
        basic_gas_sampler)
