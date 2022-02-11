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

type error += Failed_to_hash_node

let () =
  register_error_kind
    `Branch
    ~id:"Failed_to_hash_node"
    ~title:"Failed to hash node"
    ~description:"Failed to hash node for a key in the ticket-balance table"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Failed to hash node for a key in the ticket-balance table")
    Data_encoding.empty
    (function Failed_to_hash_node -> Some () | _ -> None)
    (fun () -> Failed_to_hash_node)

include Script_expr_hash

let hash_bytes_cost bytes =
  let module S = Saturation_repr in
  let ( + ) = S.add in
  let v0 = S.safe_int @@ Bytes.length bytes in
  let ( lsr ) = S.shift_right in
  S.safe_int 200 + (v0 + (v0 lsr 2)) |> Gas_limit_repr.atomic_step_cost

let hash_of_node ctxt node =
  Raw_context.consume_gas ctxt (Script_repr.strip_locations_cost node)
  >>? fun ctxt ->
  let node = Micheline.strip_locations node in
  match Data_encoding.Binary.to_bytes_opt Script_repr.expr_encoding node with
  | Some bytes ->
      Raw_context.consume_gas ctxt (hash_bytes_cost bytes) >|? fun ctxt ->
      (Script_expr_hash.hash_bytes [bytes], ctxt)
  | None -> error Failed_to_hash_node

(** TODO: https://gitlab.com/tezos/tezos/-/issues/2345
    Remove [Raw_context.t] argument.
    The fact that [make] takes a [Raw_context.t] value as its argument
    is unconventional for a [*_repr] module. [ctxt] is only used to do
    gas accounting, and this function could be refactored to use the
    [Gas_monad] framework, but it requires to adapt it to be
    compatible with [Raw_context]. *)
let make ctxt ~ticketer ~typ ~contents ~owner =
  hash_of_node ctxt
  @@ Micheline.Seq (Micheline.dummy_location, [ticketer; typ; contents; owner])

module Index = Script_expr_hash
