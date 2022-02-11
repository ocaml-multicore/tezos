(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Trili Tech, <contact@trili.tech>                       *)
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

module type S = sig
  type 'a t

  type key

  val empty : 'a t

  val size : 'a t -> int

  val find : context -> key -> 'a t -> ('a option * context) tzresult

  val update :
    context ->
    key ->
    (context -> 'a option -> ('a option * context) tzresult) ->
    'a t ->
    ('a t * context) tzresult

  val to_list : context -> 'a t -> ((key * 'a) list * context) tzresult

  val of_list :
    context ->
    merge_overlap:(context -> 'a -> 'a -> ('a * context) tzresult) ->
    (key * 'a) list ->
    ('a t * context) tzresult

  val merge :
    context ->
    merge_overlap:(context -> 'a -> 'a -> ('a * context) tzresult) ->
    'a t ->
    'a t ->
    ('a t * context) tzresult

  val map :
    context ->
    (context -> key -> 'a -> ('b * context) tzresult) ->
    'a t ->
    ('b t * context) tzresult

  val fold :
    context ->
    (context -> 'state -> key -> 'value -> ('state * context) tzresult) ->
    'state ->
    'value t ->
    ('state * context) tzresult
end

module type COMPARABLE = sig
  include Compare.COMPARABLE

  val compare_cost : t -> Gas.cost
end

module Make (C : COMPARABLE) = struct
  module M = Map.Make (C)

  type 'a t = {map : 'a M.t; size : int}

  let empty = {map = M.empty; size = 0}

  let size {size; _} = size

  let find_cost ~key ~size =
    Carbonated_map_costs.find_cost ~compare_key_cost:(C.compare_cost key) ~size

  let update_cost ~key ~size =
    Carbonated_map_costs.update_cost
      ~compare_key_cost:(C.compare_cost key)
      ~size

  let find ctxt key {map; size} =
    Gas.consume ctxt (find_cost ~key ~size) >|? fun ctxt ->
    (M.find key map, ctxt)

  let update ctxt key f {map; size} =
    let find_cost = find_cost ~key ~size in
    let update_cost = update_cost ~key ~size in
    (* Consume gas for looking up the old value *)
    Gas.consume ctxt find_cost >>? fun ctxt ->
    let old_val_opt = M.find key map in
    (* The call to [f] must also account for gas *)
    f ctxt old_val_opt >>? fun (new_val_opt, ctxt) ->
    match (old_val_opt, new_val_opt) with
    | (Some _, Some new_val) ->
        (* Consume gas for adding to the map *)
        Gas.consume ctxt update_cost >|? fun ctxt ->
        ({map = M.add key new_val map; size}, ctxt)
    | (Some _, None) ->
        (* Consume gas for removing from the map *)
        Gas.consume ctxt update_cost >|? fun ctxt ->
        ({map = M.remove key map; size = size - 1}, ctxt)
    | (None, Some new_val) ->
        (* Consume gas for adding to the map *)
        Gas.consume ctxt update_cost >|? fun ctxt ->
        ({map = M.add key new_val map; size = size + 1}, ctxt)
    | (None, None) -> ok ({map; size}, ctxt)

  let to_list ctxt {map; size} =
    Gas.consume ctxt (Carbonated_map_costs.fold_cost ~size) >|? fun ctxt ->
    (M.bindings map, ctxt)

  let add ctxt ~merge_overlap key value {map; size} =
    (* Consume gas for looking up the element *)
    Gas.consume ctxt (find_cost ~key ~size) >>? fun ctxt ->
    (* Consume gas for adding the element *)
    Gas.consume ctxt (update_cost ~key ~size) >>? fun ctxt ->
    match M.find key map with
    | Some old_val ->
        (* Invoking [merge_overlap] must also account for gas *)
        merge_overlap ctxt old_val value >|? fun (new_value, ctxt) ->
        ({map = M.add key new_value map; size}, ctxt)
    | None -> Ok ({map = M.add key value map; size = size + 1}, ctxt)

  let add_key_values_to_map ctxt ~merge_overlap map key_values =
    let accum (map, ctxt) (key, value) =
      add ctxt ~merge_overlap key value map
    in
    (* Gas is paid at each step of the fold. *)
    List.fold_left_e accum (map, ctxt) key_values

  let of_list ctxt ~merge_overlap =
    add_key_values_to_map ctxt ~merge_overlap empty

  let merge ctxt ~merge_overlap map1 {map; size} =
    (* To be on the safe side, pay an upfront gas cost for traversing the
       map. Each step of the fold is accounted for separately.
    *)
    Gas.consume ctxt (Carbonated_map_costs.fold_cost ~size) >>? fun ctxt ->
    M.fold_e
      (fun key value (map, ctxt) -> add ctxt ~merge_overlap key value map)
      map
      (map1, ctxt)

  let fold ctxt f empty {map; size} =
    Gas.consume ctxt (Carbonated_map_costs.fold_cost ~size) >>? fun ctxt ->
    M.fold_e
      (fun key value (acc, ctxt) ->
        (* Invoking [f] must also account for gas. *)
        f ctxt acc key value)
      map
      (empty, ctxt)

  let map ctxt f {map; size} =
    (* We cannot use the standard map function because [f] also meters the gas
       cost at each invocation. *)
    fold
      ctxt
      (fun ctxt map key value ->
        (* Invoking [f] must also account for gas. *)
        f ctxt key value >>? fun (value, ctxt) ->
        (* Consume gas for adding the element. *)
        Gas.consume ctxt (update_cost ~key ~size) >|? fun ctxt ->
        (M.add key value map, ctxt))
      M.empty
      {map; size}
    >|? fun (map, ctxt) -> ({map; size}, ctxt)
end
