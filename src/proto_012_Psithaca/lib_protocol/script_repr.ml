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

type location = Micheline.canonical_location

let location_encoding = Micheline.canonical_location_encoding

type annot = Micheline.annot

type expr = Michelson_v1_primitives.prim Micheline.canonical

type lazy_expr = expr Data_encoding.lazy_t

type 'location michelson_node =
  ('location, Michelson_v1_primitives.prim) Micheline.node

type unlocated_michelson_node = unit michelson_node

type node = location michelson_node

let expr_encoding =
  Micheline.canonical_encoding
    ~variant:"michelson_v1"
    Michelson_v1_primitives.prim_encoding

type error += Lazy_script_decode (* `Permanent *)

let () =
  register_error_kind
    `Permanent
    ~id:"invalid_binary_format"
    ~title:"Invalid binary format"
    ~description:
      "Could not deserialize some piece of data from its binary representation"
    Data_encoding.empty
    (function Lazy_script_decode -> Some () | _ -> None)
    (fun () -> Lazy_script_decode)

let lazy_expr_encoding = Data_encoding.lazy_encoding expr_encoding

let lazy_expr expr = Data_encoding.make_lazy expr_encoding expr

type t = {code : lazy_expr; storage : lazy_expr}

let encoding =
  let open Data_encoding in
  def "scripted.contracts"
  @@ conv
       (fun {code; storage} -> (code, storage))
       (fun (code, storage) -> {code; storage})
       (obj2 (req "code" lazy_expr_encoding) (req "storage" lazy_expr_encoding))

module S = Saturation_repr

module Micheline_size = struct
  type t = {
    nodes : S.may_saturate S.t;
    string_bytes : S.may_saturate S.t;
    z_bytes : S.may_saturate S.t;
  }

  let make ~nodes ~string_bytes ~z_bytes = {nodes; string_bytes; z_bytes}

  let zero = {nodes = S.zero; string_bytes = S.zero; z_bytes = S.zero}

  let add_int acc n =
    let numbits = Z.numbits n in
    let z_bytes =
      S.safe_int ((numbits + 7) / 8)
      (* Compute the number of bytes in a Z.t *)
    in
    {
      nodes = S.succ acc.nodes;
      string_bytes = acc.string_bytes;
      z_bytes = S.add acc.z_bytes z_bytes;
    }

  let add_string acc n =
    let string_bytes = S.safe_int (String.length n) in
    {
      nodes = S.succ acc.nodes;
      string_bytes = S.add acc.string_bytes string_bytes;
      z_bytes = acc.z_bytes;
    }

  let add_bytes acc n =
    let string_bytes = S.safe_int (Bytes.length n) in
    {
      nodes = S.succ acc.nodes;
      string_bytes = S.add acc.string_bytes string_bytes;
      z_bytes = acc.z_bytes;
    }

  let add_node s = {s with nodes = S.succ s.nodes}

  (* We model annotations as Seqs of Strings *)
  let of_annots acc annots =
    List.fold_left (fun acc s -> add_string acc s) acc annots

  let[@coq_struct "nodes"] rec of_nodes acc nodes more_nodes =
    let open Micheline in
    match nodes with
    | [] -> (
        match more_nodes with
        | [] -> acc
        | nodes :: more_nodes ->
            (of_nodes [@ocaml.tailcall]) acc nodes more_nodes)
    | Int (_, n) :: nodes ->
        let acc = add_int acc n in
        (of_nodes [@ocaml.tailcall]) acc nodes more_nodes
    | String (_, s) :: nodes ->
        let acc = add_string acc s in
        (of_nodes [@ocaml.tailcall]) acc nodes more_nodes
    | Bytes (_, s) :: nodes ->
        let acc = add_bytes acc s in
        (of_nodes [@ocaml.tailcall]) acc nodes more_nodes
    | Prim (_, _, args, annots) :: nodes ->
        let acc = add_node acc in
        let acc = of_annots acc annots in
        (of_nodes [@ocaml.tailcall]) acc args (nodes :: more_nodes)
    | Seq (_, args) :: nodes ->
        let acc = add_node acc in
        (of_nodes [@ocaml.tailcall]) acc args (nodes :: more_nodes)

  let of_node node = of_nodes zero [node] []

  let dot_product s1 s2 =
    S.add
      (S.mul s1.nodes s2.nodes)
      (S.add
         (S.mul s1.string_bytes s2.string_bytes)
         (S.mul s1.z_bytes s2.z_bytes))
end

(* Costs pertaining to deserialization of Micheline values (bytes to Micheline).
   The costs are given in atomic steps (see [Gas_limit_repr]). *)
module Micheline_decoding = struct
  (* Cost vector allowing to compute decoding costs as a function of the
     size of the Micheline term *)
  let micheline_size_dependent_cost =
    let traversal_cost = S.safe_int 60 in
    let string_per_byte_cost = S.safe_int 10 in
    let z_per_byte_cost = S.safe_int 10 in
    Micheline_size.make
      ~nodes:traversal_cost
      ~string_bytes:string_per_byte_cost
      ~z_bytes:z_per_byte_cost

  let bytes_dependent_cost = S.safe_int 20
end

(* Costs pertaining to serialization of Micheline values (Micheline to bytes)
   The costs are given in atomic steps (see [Gas_limit_repr]). *)
module Micheline_encoding = struct
  (* Cost vector allowing to compute encoding cost as a function of the
     size of the Micheline term *)
  let micheline_size_dependent_cost =
    let traversal_cost = S.safe_int 100 in
    let string_per_byte_cost = S.safe_int 10 in
    let z_per_byte_cost = S.safe_int 25 in
    Micheline_size.make
      ~nodes:traversal_cost
      ~string_bytes:string_per_byte_cost
      ~z_bytes:z_per_byte_cost

  let bytes_dependent_cost = S.safe_int 33
end

let expr_size expr = Micheline_size.of_node (Micheline.root expr)

(* Compute the cost of serializing a term of given [size]. *)
let serialization_cost size =
  Gas_limit_repr.atomic_step_cost
  @@ Micheline_size.dot_product
       size
       Micheline_encoding.micheline_size_dependent_cost

(* Compute the cost of deserializing a term of given [size]. *)
let deserialization_cost size =
  Gas_limit_repr.atomic_step_cost
  @@ Micheline_size.dot_product
       size
       Micheline_decoding.micheline_size_dependent_cost

(* Estimate the cost of deserializing a term encoded in [bytes_len] bytes. *)
let deserialization_cost_estimated_from_bytes bytes_len =
  Gas_limit_repr.atomic_step_cost
  @@ S.mul Micheline_decoding.bytes_dependent_cost (S.safe_int bytes_len)

(* Estimate the cost of serializing a term from its encoded form,
   having [bytes_len] bytes. *)
let serialization_cost_estimated_from_bytes bytes_len =
  Gas_limit_repr.atomic_step_cost
  @@ S.mul Micheline_encoding.bytes_dependent_cost (S.safe_int bytes_len)

(* Cost of running [strip_locations] on a term with [size] nodes.
   Note that [strip_locations] will reallocate a fresh Micheline tree.
   This only depends on the total number of nodes (not the size of
   the leaves). *)
let cost_micheline_strip_locations size =
  Gas_limit_repr.atomic_step_cost @@ S.mul (S.safe_int size) (S.safe_int 51)

(* TODO: https://gitlab.com/tezos/tezos/-/issues/2049
   Plugin benchmarked gas.
   Replace this definition, copied from [cost_michelines_strip_locations].
*)
(* Cost of running [strip_annotations] on a term with [size] nodes.
   Note that [strip_annotations] will reallocate a fresh Micheline tree.
   This only depends on the total number of nodes (not the size of
   the leaves). *)
let cost_micheline_strip_annotations size =
  Gas_limit_repr.atomic_step_cost @@ S.mul (S.safe_int size) (S.safe_int 51)

(* This is currently used to estimate the cost of serializing an operation. *)
let bytes_node_cost s = serialization_cost_estimated_from_bytes (Bytes.length s)

let deserialized_cost expr =
  Gas_limit_repr.atomic_step_cost @@ deserialization_cost (expr_size expr)

let serialized_cost bytes =
  let cost =
    let size = Bytes.length bytes in
    S.add (serialization_cost_estimated_from_bytes size)
    @@ (* N_IConcat_bytes_pair inlined here *)
    S.add (S.safe_int 65) (S.shift_right (S.safe_int size) 4)
  in
  Gas_limit_repr.atomic_step_cost cost

let force_decode_cost lexpr =
  Data_encoding.apply_lazy
    ~fun_value:(fun _ -> Gas_limit_repr.free)
    ~fun_bytes:(fun b ->
      deserialization_cost_estimated_from_bytes (Bytes.length b))
    ~fun_combine:(fun _ _ -> Gas_limit_repr.free)
    lexpr

let stable_force_decode_cost lexpr =
  let has_bytes =
    Data_encoding.apply_lazy
      ~fun_value:(fun v -> `Only_value v)
      ~fun_bytes:(fun b -> `Has_bytes b)
      ~fun_combine:(fun _v b ->
        (* When the lazy_expr contains both a deserialized version
           and a serialized one, we compute the cost from the
           serialized version because its is cheaper to do. *)
        b)
      lexpr
  in
  match has_bytes with
  | `Has_bytes b -> deserialization_cost_estimated_from_bytes (Bytes.length b)
  | `Only_value v ->
      (* This code path should not be reached in theory because values that are
         decoded should have been encoded before.
         Here we use Data_encoding.Binary.length, which yields the same results
         as serializing the value and taking the size, without the need to
         encode (in particular, less allocations).
      *)
      deserialization_cost_estimated_from_bytes
        (Data_encoding.Binary.length expr_encoding v)

let force_decode lexpr =
  match Data_encoding.force_decode lexpr with
  | Some v -> ok v
  | None -> error Lazy_script_decode

let force_bytes_cost expr =
  (* Estimating the cost directly from the bytes would be cheaper, but
           using [serialized_cost] is more accurate. *)
  Data_encoding.apply_lazy
    ~fun_value:(fun v -> serialization_cost (expr_size v))
    ~fun_bytes:(fun _ -> Gas_limit_repr.free)
    ~fun_combine:(fun _ _ -> Gas_limit_repr.free)
    expr

let force_bytes expr =
  Error_monad.catch_f
    (fun () -> Data_encoding.force_bytes expr)
    (fun _ -> Lazy_script_decode)

let unit =
  Micheline.strip_locations (Prim (0, Michelson_v1_primitives.D_Unit, [], []))

let unit_parameter = lazy_expr unit

let is_unit_parameter =
  let unit_bytes = Data_encoding.force_bytes unit_parameter in
  Data_encoding.apply_lazy
    ~fun_value:(fun v ->
      match Micheline.root v with
      | Prim (_, Michelson_v1_primitives.D_Unit, [], []) -> true
      | _ -> false)
    ~fun_bytes:(fun b -> Compare.Bytes.equal b unit_bytes)
    ~fun_combine:(fun res _ -> res)

let[@coq_struct "node"] rec strip_annotations node =
  let open Micheline in
  match node with
  | (Int (_, _) | String (_, _) | Bytes (_, _)) as leaf -> leaf
  | Prim (loc, name, args, _) ->
      Prim (loc, name, List.map strip_annotations args, [])
  | Seq (loc, args) -> Seq (loc, List.map strip_annotations args)

let rec micheline_fold_aux node f acc k =
  match node with
  | Micheline.Int (_, _) -> k (f acc node)
  | Micheline.String (_, _) -> k (f acc node)
  | Micheline.Bytes (_, _) -> k (f acc node)
  | Micheline.Prim (_, _, subterms, _) ->
      micheline_fold_nodes subterms f (f acc node) k
  | Micheline.Seq (_, subterms) ->
      micheline_fold_nodes subterms f (f acc node) k

and[@coq_mutual_as_notation] [@coq_struct "subterms"] micheline_fold_nodes
    subterms f acc k =
  match subterms with
  | [] -> k acc
  | node :: nodes ->
      micheline_fold_nodes nodes f acc @@ fun acc ->
      micheline_fold_aux node f acc k

let fold node init f = micheline_fold_aux node f init (fun x -> x)

let micheline_nodes node = fold node 0 @@ fun n _ -> n + 1

let strip_locations_cost node =
  let nodes = micheline_nodes node in
  cost_micheline_strip_locations nodes

let strip_annotations_cost node =
  let nodes = micheline_nodes node in
  cost_micheline_strip_annotations nodes
