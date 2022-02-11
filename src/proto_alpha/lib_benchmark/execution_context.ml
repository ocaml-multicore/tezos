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

open Protocol
open Error_monad

type context = Alpha_context.context * Script_interpreter.step_constants

let initial_balance = 4_000_000_000_000L

let context_init_memory ~rng_state =
  Context.init
    ~rng_state
    ~initial_balances:
      [
        initial_balance;
        initial_balance;
        initial_balance;
        initial_balance;
        initial_balance;
      ]
    5
  >>=? fun (block, accounts) ->
  match accounts with
  | [bs1; bs2; bs3; bs4; bs5] ->
      return (`Mem_block (block, (bs1, bs2, bs3, bs4, bs5)))
  | _ -> assert false

let context_init ~rng_state = context_init_memory ~rng_state

let make ~rng_state =
  context_init_memory ~rng_state >>=? fun context ->
  let amount = Alpha_context.Tez.one in
  let chain_id = Chain_id.zero in
  let now = Alpha_context.Script_timestamp.of_zint Z.zero in
  let level = Alpha_context.Script_int.zero_n in
  let open Script_interpreter in
  (match context with
  | `Mem_block (block, (bs1, bs2, bs3, _, _)) ->
      let source = bs1 in
      let payer = bs2 in
      let self = bs3 in
      let step_constants =
        {
          source;
          payer;
          self;
          amount;
          balance = Alpha_context.Tez.of_mutez_exn initial_balance;
          chain_id;
          now;
          level;
        }
      in
      return (block, step_constants)
  | `Disk_block (block, source) ->
      let step_constants =
        {
          source;
          payer = source;
          self = source;
          amount;
          balance = Alpha_context.Tez.of_mutez_exn initial_balance;
          chain_id;
          now;
          level;
        }
      in
      return (block, step_constants))
  >>=? fun (block, step_constants) ->
  Incremental.begin_construction
    ~timestamp:(Time.Protocol.add block.header.shell.timestamp 30L)
    block
  >>=? fun vs ->
  let ctxt = Incremental.alpha_ctxt vs in
  let ctxt =
    (* Required for eg Create_contract *)
    Protocol.Alpha_context.Origination_nonce.init ctxt Operation_hash.zero
  in
  return (ctxt, step_constants)
