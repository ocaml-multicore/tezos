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

(** This is the Michelson interpreter.

    This module offers a way to execute either a Michelson script or a
    Michelson instruction.

    Implementation details are documented in the .ml file.

*)

open Alpha_context
open Script_typed_ir

type error += Reject of Script.location * Script.expr * execution_trace option

type error += Overflow of Script.location * execution_trace option

type error += Runtime_contract_error of Contract.t

type error += Bad_contract_parameter of Contract.t (* `Permanent *)

type error += Cannot_serialize_failure

type error += Cannot_serialize_storage

type error += Michelson_too_many_recursive_calls

type execution_result = {
  ctxt : context;
  storage : Script.expr;
  lazy_storage_diff : Lazy_storage.diffs option;
  operations : packed_internal_operation list;
}

type step_constants = Script_typed_ir.step_constants = {
  source : Contract.t;
  payer : Contract.t;
  self : Contract.t;
  amount : Tez.t;
  balance : Tez.t;
  chain_id : Chain_id.t;
  now : Script_timestamp.t;
  level : Script_int.n Script_int.num;
}

val step :
  logger option ->
  context ->
  Script_typed_ir.step_constants ->
  ('a, 's, 'r, 'f) Script_typed_ir.kdescr ->
  'a ->
  's ->
  ('r * 'f * context) tzresult Lwt.t

(** [execute ?logger ctxt ~cached_script mode step_constant ~script
   ~entrypoint ~parameter ~internal] interprets the [script]'s
   [entrypoint] for a given [parameter].

   This will update the local storage of the contract
   [step_constants.self]. Other pieces of contextual information
   ([source], [payer], [amount], and [chaind_id]) are also passed in
   [step_constant].

   [internal] is [true] if and only if the execution happens within an
   internal operation.

   [mode] is the unparsing mode, as declared by
   {!Script_ir_translator}.

   [cached_script] is the cached elaboration of [script], that is the
   well typed abstract syntax tree produced by the type elaboration of
   [script] during a previous execution and stored in the in-memory
   cache.

*)
val execute :
  ?logger:logger ->
  Alpha_context.t ->
  cached_script:Script_ir_translator.ex_script option ->
  Script_ir_translator.unparsing_mode ->
  step_constants ->
  script:Script.t ->
  entrypoint:Entrypoint.t ->
  parameter:Script.expr ->
  internal:bool ->
  (execution_result * (Script_ir_translator.ex_script * int)) tzresult Lwt.t

(** [kstep logger ctxt step_constants kinstr accu stack] interprets the
    script represented by [kinstr] under the context [ctxt]. This will
    turn a stack whose topmost element is [accu] and remaining elements
    [stack] into a new accumulator and a new stack. This function also
    returns an updated context. If [logger] is given, [kstep] calls back
    its functions at specific points of the execution. The execution is
    parameterized by some [step_constants]. *)
val kstep :
  logger option ->
  context ->
  step_constants ->
  ('a, 's, 'r, 'f) Script_typed_ir.kinstr ->
  'a ->
  's ->
  ('r * 'f * context) tzresult Lwt.t

(** Internal interpretation loop
    ============================

    The following types and the following functions are exposed
    in the interface to allow the inference of a gas model in
    snoop.

    Strictly speaking, they should not be considered as part of
    the interface since they expose implementation details that
    may change in the future.

*)

module Internals : sig
  (** Internally, the interpretation loop uses a local gas counter. *)
  type local_gas_counter = int

  (** During the evaluation, the gas level in the context is outdated.
      See comments in the implementation file for more details. *)
  type outdated_context = OutDatedContext of context [@@unboxed]

  (** [next logger (ctxt, step_constants) local_gas_counter ks accu
      stack] is an internal function which interprets the continuation
      [ks] to execute the interpreter on the current A-stack. *)
  val next :
    logger option ->
    outdated_context * step_constants ->
    local_gas_counter ->
    ('a, 's, 'r, 'f) continuation ->
    'a ->
    's ->
    ('r * 'f * outdated_context * local_gas_counter) tzresult Lwt.t

  val step :
    outdated_context * step_constants ->
    local_gas_counter ->
    ('a, 's, 'r, 'f) Script_typed_ir.kinstr ->
    'a ->
    's ->
    ('r * 'f * outdated_context * local_gas_counter) tzresult Lwt.t
end
