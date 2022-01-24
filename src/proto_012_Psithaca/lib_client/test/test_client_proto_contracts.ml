(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** Testing
    -------
    Component:    Client
    Invocation:   dune exec src/proto_alpha/lib_client/test/test_client_proto_contracts.exe
    Subject:      Unit tests for Client_proto_contracts
*)

(** [mock_wallet entities] is a mock of the
    [Tezos_client_base.Client_context.wallet] class that only
    implements the [load] method. This methods returns a key-value
    association as given by the json string [entities] that should have
    the form: ["[{"name": "alias", "value": "key" }, <...>]"]. *)
class mock_wallet (entities : string) : Tezos_client_base.Client_context.wallet
  =
  object
    method load_passwords = None

    method read_file _path = failwith "mock_wallet:read_file"

    method get_base_dir = assert false

    method with_lock : type a. (unit -> a Lwt.t) -> a Lwt.t = fun _f -> _f ()

    method load : type a.
        string -> default:a -> a Data_encoding.encoding -> a tzresult Lwt.t =
      fun _alias_name ~default:_default _encoding ->
        let json = (Ezjsonm.from_string entities :> Data_encoding.json) in
        return @@ Data_encoding.Json.destruct _encoding json

    method write : type a.
        string -> a -> a Data_encoding.encoding -> unit tzresult Lwt.t =
      fun _alias_name _list _encoding -> failwith "mock_wallet:write"
  end

(**
   Test.
   Tests different lookups of
   [Client_proto_contracts.ContractAlias.find_destination].
*)
let test_find_destination _ =
  let bootstrap1 = "tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx" in
  let wallet_json =
    Format.asprintf {| [{"name": "test_alias", "value": "%s" }] |} bootstrap1
  in
  let w = new mock_wallet wallet_json in
  let test msg key exp_source =
    Client_proto_contracts.ContractAlias.find_destination w key
    >>=? fun (_, contract) ->
    Client_proto_contracts.RawContractAlias.to_source contract
    >>=? fun source ->
    (* Alcotest equality assertion *)
    Alcotest.(check string msg source exp_source) ;
    return_unit
  in
  test "Expected alias:test_alias = bootstrap1" "alias:test_alias" bootstrap1
  >>=? fun () ->
  test "Expected key:test_alias = bootstrap1" "key:test_alias" bootstrap1
  >>=? fun () ->
  test "Expected bootstrap1 = bootstrap1" bootstrap1 bootstrap1 >>=? fun () ->
  test "Expected test_alias bootstrap1" "test_alias" bootstrap1

let () =
  Alcotest_lwt.run
    "tezos-lib-client-proto-contracts"
    [
      ( "client_proto_contracts",
        [Tztest.tztest "test_find_destination" `Quick test_find_destination] );
    ]
  |> Lwt_main.run
