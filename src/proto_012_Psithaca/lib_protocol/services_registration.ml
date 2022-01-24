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

open Alpha_context

type rpc_context = {
  block_hash : Block_hash.t;
  block_header : Block_header.shell_header;
  context : Alpha_context.t;
}

let rpc_init ({block_hash; block_header; context} : Updater.rpc_context) =
  let level = block_header.level in
  let timestamp = block_header.timestamp in
  Alpha_context.prepare
    ~level
    ~predecessor_timestamp:timestamp
    ~timestamp
    context
  >|=? fun (context, _, _) -> {block_hash; block_header; context}

let rpc_services =
  ref (RPC_directory.empty : Updater.rpc_context RPC_directory.t)

let register0_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.register ~chunked !rpc_services s (fun ctxt q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt q i)

let register0 ~chunked s f =
  register0_fullctxt ~chunked s (fun {context; _} -> f context)

let register0_noctxt ~chunked s f =
  rpc_services :=
    RPC_directory.register ~chunked !rpc_services s (fun _ q i -> f q i)

let register1_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.register ~chunked !rpc_services s (fun (ctxt, arg) q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt arg q i)

let register1 ~chunked s f =
  register1_fullctxt ~chunked s (fun {context; _} x -> f context x)

let register2_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.register
      ~chunked
      !rpc_services
      s
      (fun ((ctxt, arg1), arg2) q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt arg1 arg2 q i)

let register2 ~chunked s f =
  register2_fullctxt ~chunked s (fun {context; _} a1 a2 q i ->
      f context a1 a2 q i)

let opt_register0_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.opt_register ~chunked !rpc_services s (fun ctxt q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt q i)

let opt_register0 ~chunked s f =
  opt_register0_fullctxt ~chunked s (fun {context; _} -> f context)

let opt_register1_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.opt_register ~chunked !rpc_services s (fun (ctxt, arg) q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt arg q i)

let opt_register1 ~chunked s f =
  opt_register1_fullctxt ~chunked s (fun {context; _} x -> f context x)

let opt_register2_fullctxt ~chunked s f =
  rpc_services :=
    RPC_directory.opt_register
      ~chunked
      !rpc_services
      s
      (fun ((ctxt, arg1), arg2) q i ->
        rpc_init ctxt >>=? fun ctxt -> f ctxt arg1 arg2 q i)

let opt_register2 ~chunked s f =
  opt_register2_fullctxt ~chunked s (fun {context; _} a1 a2 q i ->
      f context a1 a2 q i)

let get_rpc_services () =
  let p =
    RPC_directory.map
      (fun c ->
        rpc_init c >|= function
        | Error t ->
            raise (Failure (Format.asprintf "%a" Error_monad.pp_trace t))
        | Ok c -> c.context)
      (Storage_description.build_directory Alpha_context.description)
  in
  RPC_directory.register_dynamic_directory
    !rpc_services
    RPC_path.(open_root / "context" / "raw" / "json")
    (fun _ -> Lwt.return p)
