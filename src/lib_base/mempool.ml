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

type t = {known_valid : Operation_hash.t list; pending : Operation_hash.Set.t}

type mempool = t

let encoding =
  let open Data_encoding in
  def
    "mempool"
    ~description:
      "A batch of operation. This format is used to gossip operations between \
       peers."
  @@ conv
       (fun {known_valid; pending} -> (known_valid, pending))
       (fun (known_valid, pending) -> {known_valid; pending})
       (obj2
          (req "known_valid" (list Operation_hash.encoding))
          (req "pending" (dynamic_size Operation_hash.Set.encoding)))

let bounded_encoding ?max_operations () =
  match max_operations with
  | None -> encoding
  | Some max_operations ->
      Data_encoding.check_size
        (8 + (max_operations * Operation_hash.size))
        encoding

let empty = {known_valid = []; pending = Operation_hash.Set.empty}

let is_empty {known_valid; pending} =
  known_valid = [] && Operation_hash.Set.is_empty pending

let remove oph {known_valid; pending} =
  {
    known_valid =
      List.filter (fun x -> not (Operation_hash.equal x oph)) known_valid;
    pending = Operation_hash.Set.remove oph pending;
  }

let cons_valid oph t = {t with known_valid = oph :: t.known_valid}

let () = Data_encoding.Registration.register encoding
