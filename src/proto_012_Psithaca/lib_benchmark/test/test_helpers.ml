(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
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

open Tezos_error_monad.Error_monad

let rng_state = Random.State.make [|42; 987897; 54120|]

let print_script_expr fmtr (expr : Protocol.Script_repr.expr) =
  Micheline_printer.print_expr
    fmtr
    (Micheline_printer.printable
       Protocol.Michelson_v1_primitives.string_of_prim
       expr)

let print_script_expr_list fmtr (exprs : Protocol.Script_repr.expr list) =
  Format.pp_print_list
    ~pp_sep:(fun fmtr () -> Format.fprintf fmtr " :: ")
    print_script_expr
    fmtr
    exprs

let typecheck_by_tezos =
  let context_init_memory ~rng_state =
    Context.init
      ~rng_state
      ~initial_balances:
        [
          4_000_000_000_000L;
          4_000_000_000_000L;
          4_000_000_000_000L;
          4_000_000_000_000L;
          4_000_000_000_000L;
        ]
      5
    >>=? fun (block, _accounts) ->
    Incremental.begin_construction
      ~timestamp:(Tezos_base.Time.Protocol.add block.header.shell.timestamp 30L)
      block
    >>=? fun vs ->
    let ctxt = Incremental.alpha_ctxt vs in
    (* Required for eg Create_contract *)
    return
    @@ Protocol.Alpha_context.Contract.init_origination_nonce
         ctxt
         Tezos_crypto.Operation_hash.zero
  in
  fun bef node ->
    Stdlib.Result.get_ok
      (Lwt_main.run
         ( context_init_memory ~rng_state >>=? fun ctxt ->
           let (Protocol.Script_ir_translator.Ex_stack_ty bef) =
             Type_helpers.michelson_type_list_to_ex_stack_ty bef ctxt
           in
           Protocol.Script_ir_translator.parse_instr
             Protocol.Script_ir_translator.Lambda
             ctxt
             ~legacy:false
             (Micheline.root node)
             bef
           >|= Protocol.Environment.wrap_tzresult
           >>=? fun _ -> return_unit ))
