(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2021-2022 Nomadic Labs <contact@nomadic-labs.com>           *)
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

(* Overview:

This mli is organized into roughly three parts:

1. A set of new types prefixed with "ex_"
Michelson is encoded in a GADT that preserves certain properties about its
type system. If you haven't read about GADT's, check out the relevant section
in the Tezos docs:
https://tezos.gitlab.io/developer/gadt.html#generalized-algebraic-data-types-gadts 

The idea is that type representing a Michelson type, ['a ty], is parameterized
by a type 'a. But that 'a can't be just _any_ type; it must be valid according
to the definition of ['a ty]. Thus, if I give you a value of type ['a ty],
all you know is that "there exists some 'a such that 'a ty exists". You must be
careful not to accidentally quantify 'a universally, that is "for all 'a,
'a ty exists", otherwise you'll get an annoying error about 'a trying to escape
it's scope. We do this by hiding 'a in an existential type. This is what
ex_comparable_ty, ex_ty, ex_stack_ty, etc. do.

2. A set of functions dealing with high-level Michelson types: 
This module also provides functions for interacting with the list, map,
set, and big_map Michelson types. 

3. A set of functions for parsing and typechecking Michelson.
Finally, and what you likely came for, the module provides many functions prefixed
with "parse_" that convert untyped Micheline (which is essentially S-expressions
with a few primitive atom types) into the GADT encoding well-typed Michelson. Likewise
there is a number of functions prefixed "unparse_" that do the reverse. These functions
consume gas, and thus are parameterized by an [Alpha_context.t].

The variety of functions reflects the variety of things one might want to parse,
from [parse_data] for arbitrary Micheline expressions to [parse_contract] for
well-formed Michelson contracts.
*)

(** {1 Michelson Existential Witness types} *)
open Alpha_context

open Script_tc_errors

type ('ta, 'tb) eq = Eq : ('same, 'same) eq

type ex_comparable_ty =
  | Ex_comparable_ty : 'a Script_typed_ir.comparable_ty -> ex_comparable_ty

type ex_ty = Ex_ty : 'a Script_typed_ir.ty -> ex_ty

type ex_stack_ty =
  | Ex_stack_ty : ('a, 's) Script_typed_ir.stack_ty -> ex_stack_ty

type ex_script = Ex_script : ('a, 'b) Script_typed_ir.script -> ex_script

type toplevel = {
  code_field : Script.node;
  arg_type : Script.node;
  storage_type : Script.node;
  views : Script_typed_ir.view Script_typed_ir.SMap.t;
  root_name : Script_ir_annot.field_annot option;
}

type ('arg, 'storage) code = {
  code :
    ( ('arg, 'storage) Script_typed_ir.pair,
      ( Script_typed_ir.operation Script_typed_ir.boxed_list,
        'storage )
      Script_typed_ir.pair )
    Script_typed_ir.lambda;
  arg_type : 'arg Script_typed_ir.ty;
  storage_type : 'storage Script_typed_ir.ty;
  views : Script_typed_ir.view Script_typed_ir.SMap.t;
  root_name : Script_ir_annot.field_annot option;
  code_size : Cache_memory_helpers.sint;
      (** This is an over-approximation of the value size in memory, in
         bytes, of the contract's static part, that is its source
         code. This includes the code of the contract as well as the code
         of the views. The storage size is not taken into account by this
         field as it has a dynamic size. *)
}

type ex_code = Ex_code : ('a, 'c) code -> ex_code

type 'storage ex_view =
  | Ex_view :
      ('input * 'storage, 'output) Script_typed_ir.lambda
      -> 'storage ex_view

type ('a, 's, 'b, 'u) cinstr = {
  apply :
    'r 'f.
    ('a, 's) Script_typed_ir.kinfo ->
    ('b, 'u, 'r, 'f) Script_typed_ir.kinstr ->
    ('a, 's, 'r, 'f) Script_typed_ir.kinstr;
}

type ('a, 's, 'b, 'u) descr = {
  loc : Script.location;
  bef : ('a, 's) Script_typed_ir.stack_ty;
  aft : ('b, 'u) Script_typed_ir.stack_ty;
  instr : ('a, 's, 'b, 'u) cinstr;
}

type tc_context = Script_tc_context.t

type ('a, 's) judgement =
  | Typed : ('a, 's, 'b, 'u) descr -> ('a, 's) judgement
  | Failed : {
      descr : 'b 'u. ('b, 'u) Script_typed_ir.stack_ty -> ('a, 's, 'b, 'u) descr;
    }
      -> ('a, 's) judgement

val close_descr :
  ('a, 'b, 'c, 'd) descr -> ('a, 'b, 'c, 'd) Script_typed_ir.kdescr

(** Flag that drives unparsing of typed values to nodes.
    - [Optimized_legacy] must be kept backward-compatible in order to compute
      valid hashes (of big map keys).
    - [Optimized] may be used as long as the result can be read by parse_data.
    - [Readable] produces with [string] values instead of [bytes] when feasible.
*)
type unparsing_mode = Optimized | Readable | Optimized_legacy

(* ---- Lists, Sets and Maps ----------------------------------------------- *)

(** {2 High-level Michelson Data Types} *)
type type_logger =
  Script.location -> Script.expr list -> Script.expr list -> unit

(** Create an empty big_map *)
val empty_big_map :
  'a Script_typed_ir.comparable_ty ->
  'b Script_typed_ir.ty ->
  ('a, 'b) Script_typed_ir.big_map

val big_map_mem :
  context ->
  'key ->
  ('key, 'value) Script_typed_ir.big_map ->
  (bool * context) tzresult Lwt.t

val big_map_get :
  context ->
  'key ->
  ('key, 'value) Script_typed_ir.big_map ->
  ('value option * context) tzresult Lwt.t

(** Update a big map. See {!big_map_get_and_update} for details. *)
val big_map_update :
  context ->
  'key ->
  'value option ->
  ('key, 'value) Script_typed_ir.big_map ->
  (('key, 'value) Script_typed_ir.big_map * context) tzresult Lwt.t

(** Update a big map, returning the old value of the given key and the new map.

    This does {i not} modify the underlying storage, only the diff table.
 *)
val big_map_get_and_update :
  context ->
  'key ->
  'value option ->
  ('key, 'value) Script_typed_ir.big_map ->
  (('value option * ('key, 'value) Script_typed_ir.big_map) * context) tzresult
  Lwt.t

val ty_eq :
  context ->
  Script.location ->
  'ta Script_typed_ir.ty ->
  'tb Script_typed_ir.ty ->
  (('ta Script_typed_ir.ty, 'tb Script_typed_ir.ty) eq * context) tzresult

val merge_types :
  legacy:bool ->
  error_details:'error_trace error_details ->
  Script.location ->
  'a Script_typed_ir.ty ->
  'b Script_typed_ir.ty ->
  ( ('a Script_typed_ir.ty, 'b Script_typed_ir.ty) eq * 'a Script_typed_ir.ty,
    'error_trace )
  Gas_monad.t

(** {3 Parsing and Typechecking Michelson} *)
val parse_comparable_data :
  ?type_logger:type_logger ->
  context ->
  'a Script_typed_ir.comparable_ty ->
  Script.node ->
  ('a * context) tzresult Lwt.t

val parse_data :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  allow_forged:bool ->
  'a Script_typed_ir.ty ->
  Script.node ->
  ('a * context) tzresult Lwt.t

val unparse_data :
  context ->
  unparsing_mode ->
  'a Script_typed_ir.ty ->
  'a ->
  (Script.node * context) tzresult Lwt.t

val unparse_comparable_data :
  loc:'loc ->
  context ->
  unparsing_mode ->
  'a Script_typed_ir.comparable_ty ->
  'a ->
  ('loc Script.michelson_node * context) tzresult Lwt.t

val unparse_code :
  context ->
  unparsing_mode ->
  Script.node ->
  (Script.node * context) tzresult Lwt.t

val parse_instr :
  ?type_logger:type_logger ->
  tc_context ->
  context ->
  legacy:bool ->
  Script.node ->
  ('a, 's) Script_typed_ir.stack_ty ->
  (('a, 's) judgement * context) tzresult Lwt.t

(**
  [parse_ty] specialized for the right-hand side part of a big map type, i.e.
  the `value` in `big_map key value`.
*)
val parse_big_map_value_ty :
  context -> legacy:bool -> Script.node -> (ex_ty * context) tzresult

val parse_packable_ty :
  context -> legacy:bool -> Script.node -> (ex_ty * context) tzresult

val parse_parameter_ty :
  context -> legacy:bool -> Script.node -> (ex_ty * context) tzresult

val parse_comparable_ty :
  context -> Script.node -> (ex_comparable_ty * context) tzresult

val parse_view_input_ty :
  context ->
  stack_depth:int ->
  legacy:bool ->
  Script.node ->
  (ex_ty * context) tzresult

val parse_view_output_ty :
  context ->
  stack_depth:int ->
  legacy:bool ->
  Script.node ->
  (ex_ty * context) tzresult

val parse_view_returning :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  'storage Script_typed_ir.ty ->
  Script_typed_ir.view ->
  ('storage ex_view * context) tzresult Lwt.t

val typecheck_views :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  'storage Script_typed_ir.ty ->
  Script_typed_ir.view Script_typed_ir.SMap.t ->
  context tzresult Lwt.t

(**
  [parse_ty] allowing big_map values, operations, contract and tickets.
*)
val parse_any_ty :
  context -> legacy:bool -> Script.node -> (ex_ty * context) tzresult

(** We expose [parse_ty] for convenience to external tools. Please use
    specialized versions such as [parse_packable_ty], [parse_parameter_ty],
    [parse_comparable_ty], or [parse_big_map_value_ty] if possible. *)
val parse_ty :
  context ->
  legacy:bool ->
  allow_lazy_storage:bool ->
  allow_operation:bool ->
  allow_contract:bool ->
  allow_ticket:bool ->
  Script.node ->
  (ex_ty * context) tzresult

val unparse_ty :
  loc:'loc ->
  context ->
  'a Script_typed_ir.ty ->
  ('loc Script.michelson_node * context) tzresult

val unparse_comparable_ty :
  loc:'loc ->
  context ->
  'a Script_typed_ir.comparable_ty ->
  ('loc Script.michelson_node * context) tzresult

val ty_of_comparable_ty :
  'a Script_typed_ir.comparable_ty -> 'a Script_typed_ir.ty

val parse_toplevel :
  context -> legacy:bool -> Script.expr -> (toplevel * context) tzresult Lwt.t

val add_field_annot :
  Script_ir_annot.field_annot option ->
  ('loc, 'prim) Micheline.node ->
  ('loc, 'prim) Micheline.node

(** High-level function to typecheck a Michelson script. This function is not
    used for validating operations but only for the [typecheck_code] RPC.

    If [show_types] is set to [true], details of the typechecking are returned
    in the [type_map], otherwise the returned [type_map] is empty. *)
val typecheck_code :
  legacy:bool ->
  show_types:bool ->
  context ->
  Script.expr ->
  (type_map * context) tzresult Lwt.t

val serialize_ty_for_error : 'a Script_typed_ir.ty -> Script.expr

val parse_code :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  code:Script.lazy_expr ->
  (ex_code * context) tzresult Lwt.t

val parse_storage :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  allow_forged:bool ->
  'storage Script_typed_ir.ty ->
  storage:Script.lazy_expr ->
  ('storage * context) tzresult Lwt.t

(** Combines [parse_code] and [parse_storage] *)
val parse_script :
  ?type_logger:type_logger ->
  context ->
  legacy:bool ->
  allow_forged_in_storage:bool ->
  Script.t ->
  (ex_script * context) tzresult Lwt.t

(* Gas accounting may not be perfect in this function, as it is only called by RPCs. *)
val unparse_script :
  context ->
  unparsing_mode ->
  ('a, 'b) Script_typed_ir.script ->
  (Script.t * context) tzresult Lwt.t

val parse_contract :
  legacy:bool ->
  context ->
  Script.location ->
  'a Script_typed_ir.ty ->
  Contract.t ->
  entrypoint:Entrypoint.t ->
  (context * 'a Script_typed_ir.typed_contract) tzresult Lwt.t

val parse_contract_for_script :
  context ->
  Script.location ->
  'a Script_typed_ir.ty ->
  Contract.t ->
  entrypoint:Entrypoint.t ->
  (context * 'a Script_typed_ir.typed_contract option) tzresult Lwt.t

val find_entrypoint :
  error_details:'error_trace error_details ->
  't Script_typed_ir.ty ->
  root_name:Script_ir_annot.field_annot option ->
  Entrypoint.t ->
  ((Script.node -> Script.node) * ex_ty, 'error_trace) result

val list_entrypoints :
  't Script_typed_ir.ty ->
  context ->
  root_name:Script_ir_annot.field_annot option ->
  (Michelson_v1_primitives.prim list list
  * (Michelson_v1_primitives.prim list * Script.unlocated_michelson_node)
    Entrypoint.Map.t)
  tzresult

val pack_data :
  context -> 'a Script_typed_ir.ty -> 'a -> (bytes * context) tzresult Lwt.t

val hash_comparable_data :
  context ->
  'a Script_typed_ir.comparable_ty ->
  'a ->
  (Script_expr_hash.t * context) tzresult Lwt.t

val hash_data :
  context ->
  'a Script_typed_ir.ty ->
  'a ->
  (Script_expr_hash.t * context) tzresult Lwt.t

type lazy_storage_ids

val no_lazy_storage_id : lazy_storage_ids

(** Traverse the given type, producing a {!lazy_storage_ids} for
    use with {!extract_lazy_storage_diff}.
 *)
val collect_lazy_storage :
  context ->
  'a Script_typed_ir.ty ->
  'a ->
  (lazy_storage_ids * context) tzresult

val list_of_big_map_ids : lazy_storage_ids -> Big_map.Id.t list

(** Produce a lazy storage diff, containing in-memory writes to
    lazy data structures such as big_maps yet to be committed.

    The resulting diff can be committed to the underlying storage
    (context) using [Lazy_storage_diff.apply].

 @param to_duplicate
    Lazy data structure reference produced via {!collect_lazy_storage}
    that can not be reused. Typically collected via traversing
    the parameters to a smart contract.
 @param to_update
    Lazy data structure reference produced via {!collect_lazy_storage}
    that can be reused. Typically collected via traversing the previous
    storage of a smart contract.
 *)
val extract_lazy_storage_diff :
  context ->
  unparsing_mode ->
  temporary:bool ->
  to_duplicate:lazy_storage_ids ->
  to_update:lazy_storage_ids ->
  'a Script_typed_ir.ty ->
  'a ->
  ('a * Lazy_storage.diffs option * context) tzresult Lwt.t

(* return [None] if none or more than one found *)
val get_single_sapling_state :
  context ->
  'a Script_typed_ir.ty ->
  'a ->
  (Sapling.Id.t option * context) tzresult

(** [script_size script] returns an overapproximation of the size of
    the in-memory representation of [script] as well as the cost
    associated to computing that overapproximation. *)
val script_size : ex_script -> int * Gas_limit_repr.cost
