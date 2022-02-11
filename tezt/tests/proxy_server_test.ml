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

(* Testing
   -------
   Component: Proxy server
   Invocation: dune exec tezt/tests/main.exe -- --file proxy_server_test.ml
   Subject: Test the proxy server: [big_map_get] is aimed at testing the
            big map RPC and comparing performances with a node. Other
            tests test the proxy server alone.
   Dependencies: tezt/tests/proxy.ml
  *)

(** Creates a client that uses a [tezos-proxy-server] as its endpoint. Also
    returns the node backing the proxy server, and the proxy server itself. *)
let init ?nodes_args ?parameter_file ~protocol () =
  let* (node, client) =
    Client.init_with_protocol ?nodes_args ?parameter_file `Client ~protocol ()
  in
  let* () = Client.bake_for client in
  let* proxy_server = Proxy_server.init node in
  Client.set_mode (Client (Some (Proxy_server proxy_server), None)) client ;
  return (node, proxy_server, client)

(* An event handler that checks that the 'split_key' heuristic of the
   proxy mode is correctly implemented. In this case, the test
   is that the proxy server requests the content of the context
   [/big_maps/index/4] as soon a it receives a request for a *longer* path
   such as [big_maps/index/4/contents/HASH/len]. If not, the proxy
   server will perform multiple requests of the form [/big_maps/index/4/...]
   in a sequence, and this handler will fail, because it checks
   that normalized requests occur only once. To see this in action,
   execute this test in a terminal with TEZOS_LOG set as follows:

   export TEZOS_LOG="*proxy_rpc*->debug; proxy_getter->debug; proxy_services->debug"

   and look for log lines like these ones:

   [proxy_server1] proxy_getter: Cache miss (get):
   [proxy_server1] proxy_getter:   (big_maps/index/4/contents/cdd4c905017896384895ed1bedc894abb078d002aff3b5c4f213b30ca884a2b8/len)
   [proxy_server1] proxy_getter: split_key heuristic triggers, getting big_maps/index/4/contents instead of
   [proxy_server1] proxy_getter:   big_maps/index/4/contents/cdd4c905017896384895ed1bedc894abb078d002aff3b5c4f213b30ca884a2b8/len

   Note that this handler cannot be attached to all proxy server tests,
   because it only works in tests
   in which the proxy server doesn't discard data attached to
   symbolic block identifiers (like head). If the proxy discards data,
   then it will do multiple times the same request, which breaks the
   property checked by this handler. *)
let heuristic_event_handler () : Proxy_server.event -> unit =
  let seens = ref String_set.empty in
  let event_to_path json =
    let fail = Test.fail "Unexpected JSON within %s (%d)" (JSON.encode json) in
    match JSON.unannotate json with
    | `A sub ->
        List.map (function `String segment -> segment | _ -> fail 1) sub
    | _ -> fail 2
  in
  fun event ->
    (* kind=true: because we are interested in "Get" events,
       see [Proxy_getter] *)
    if event.name = "cache_miss.v0" && JSON.(event.value |-> "kind" |> as_bool)
    then
      let segments = event_to_path JSON.(event.value |-> "key") in
      let normalized = Proxy.normalize segments |> String.concat "/" in
      if String_set.mem normalized !seens then
        Test.fail
          "Request of the form %s/... done twice. Last request is %s"
          normalized
        @@ String.concat "/" segments
      else seens := String_set.add normalized !seens

(** [readonly_client] only performs reads to the node's storage, while
    [client] has full access *)
let big_map_get ?(big_map_size = 10) ?nb_gets ~protocol mode () =
  Log.info "Test advanced originated contract" ;
  let* parameter_file =
    Protocol.write_parameter_file
      ~base:(Either.right (protocol, None))
      [(["hard_storage_limit_per_operation"], Some "\"99999999\"")]
  in
  let* (node, client) =
    Client.init_with_protocol ~parameter_file ~protocol `Client ()
  in
  let* (endpoint : Client.endpoint option) =
    match mode with
    | `Node -> return None
    | `Proxy_server ->
        (* When checking the split_key heuristic with {!heuristic_event_handler},
           we don't want data to be discarded. Hence we keep data for
           60 seconds. Any duration longer than the test duration is fine. As
           this test takes approximately 10 seconds,
           using 60 seconds here is safe. *)
        let approximate_test_duration = 10 in
        let sym_block_caching_time = 6 * approximate_test_duration in
        let args =
          Proxy_server.[Symbolic_block_caching_time sym_block_caching_time]
        in
        let* () = Client.bake_for client in
        (* We want Debug level events, for [heuristic_event_handler]
           to work properly *)
        let* proxy_server = Proxy_server.init ~args ~event_level:`Debug node in
        Proxy_server.on_event proxy_server @@ heuristic_event_handler () ;
        return @@ Some (Client.Proxy_server proxy_server)
  in
  let nb_gets = Option.value ~default:big_map_size nb_gets in
  let entries : (string * int) list =
    List.init big_map_size (fun i -> (Format.sprintf "\"%04i\"" i, i))
  in
  let entries_s =
    List.map (fun (k, v) -> sf "Elt %s %s " k @@ Int.to_string v) entries
  in
  let init = "{" ^ String.concat ";" entries_s ^ "}" in
  let* contract_id =
    Client.originate_contract
      ~alias:"originated_contract_advanced"
      ~amount:Tez.zero
      ~src:"bootstrap1"
      ~prg:"file:./tezt/tests/contracts/proto_alpha/big_map_perf.tz"
      ~init
      ~burn_cap:Tez.(of_int 9999999)
      client
  in
  let* () = Client.bake_for client in
  let* mockup_client = Client.init_mockup ~protocol () in
  let* _ = RPC.Contracts.get_script ?endpoint ~contract_id client in
  let* _ = RPC.Contracts.get_storage ?endpoint ~contract_id client in
  let* indices_exprs =
    let compute_index_expr index =
      let* key_value_list =
        Client.hash_data ~data:index ~typ:"string" mockup_client
      in
      let key = "Script-expression-ID-Hash" in
      match List.assoc_opt key key_value_list with
      | None -> Test.fail "%s MUST be there" key
      | Some res -> Lwt.return res
    in
    let get_index_expr index =
      match String_map.find_opt index Proxy_server_test_data.key_to_expr with
      | None ->
          Log.warn
            "Need to compute expr of key %s: prefer to put this in \
             Proxy_server_test_data"
            index ;
          compute_index_expr index
      | Some res -> Lwt.return res
    in
    Lwt_list.map_s get_index_expr @@ (Base.take nb_gets entries |> List.map fst)
  in
  let get_one_value key_hash =
    let* _ =
      RPC.Big_maps.get
        ?endpoint
        ~id:
          (* This big_map id can be found in origination response
             e.g. "New map(4) of type (big_map string nat)".
             In this dumb test we know it is always 4. *)
          "4"
        ~key_hash
        client
    in
    Lwt.return_unit
  in
  Lwt_list.iter_s get_one_value indices_exprs

let test_equivalence =
  let open Proxy.Location in
  let alt_mode = Vanilla_proxy_server in
  Protocol.register_test
    ~__FILE__
    ~title:"(Vanilla, proxy_server endpoint) Compare RPC get"
    ~tags:(compare_tags alt_mode)
  @@ fun protocol ->
  let* (node, _, alternative) = init ~protocol () in
  let vanilla = Client.create ~endpoint:(Node node) () in
  let clients = {vanilla; alternative} in
  let tz_log = [("alpha.proxy_rpc", "debug"); ("proxy_getter", "debug")] in
  check_equivalence ~tz_log alt_mode clients

let register ~protocols =
  let register mode =
    let mode_tag =
      match mode with `Node -> "node" | `Proxy_server -> "proxy_server"
    in
    Protocol.register_test
      ~__FILE__
      ~title:(sf "big_map_perf (%s)" mode_tag)
      ~tags:["bigmapperf"; mode_tag]
      (fun protocol -> big_map_get ~protocol mode ())
      ~protocols
  in
  register `Node ;
  register `Proxy_server ;
  test_equivalence ~protocols
