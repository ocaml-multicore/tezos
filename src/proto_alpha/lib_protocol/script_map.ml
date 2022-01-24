(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

open Alpha_context
open Script_typed_ir

let make x = Map_tag x

let get_module (Map_tag x) = x

let key_ty : type a b. (a, b) map -> a comparable_ty =
 fun (Map_tag (module Box)) -> Box.key_ty

let empty : type a b. a comparable_ty -> (a, b) map =
 fun ty ->
  let module OPS = Map.Make (struct
    type t = a

    let compare = Script_comparable.compare_comparable ty
  end) in
  Map_tag
    (module struct
      type key = a

      type value = b

      let key_ty = ty

      module OPS = struct
        type value = b

        include OPS

        type nonrec t = value t
      end

      let boxed = OPS.empty

      let size = 0
    end)

let get : type key value. key -> (key, value) map -> value option =
 fun k (Map_tag (module Box)) -> Box.OPS.find k Box.boxed

let update : type a b. a -> b option -> (a, b) map -> (a, b) map =
 fun k v (Map_tag (module Box)) ->
  let (boxed, size) =
    let contains =
      match Box.OPS.find k Box.boxed with None -> false | _ -> true
    in
    match v with
    | Some v -> (Box.OPS.add k v Box.boxed, Box.size + if contains then 0 else 1)
    | None -> (Box.OPS.remove k Box.boxed, Box.size - if contains then 1 else 0)
  in
  Map_tag
    (module struct
      type key = a

      type value = b

      let key_ty = Box.key_ty

      module OPS = Box.OPS

      let boxed = boxed

      let size = size
    end)

let mem : type key value. key -> (key, value) map -> bool =
 fun k (Map_tag (module Box)) ->
  match Box.OPS.find k Box.boxed with None -> false | _ -> true

let fold :
    type key value acc.
    (key -> value -> acc -> acc) -> (key, value) map -> acc -> acc =
 fun f (Map_tag (module Box)) -> Box.OPS.fold f Box.boxed

let size : type key value. (key, value) map -> Script_int.n Script_int.num =
 fun (Map_tag (module Box)) -> Script_int.(abs (of_int Box.size))
