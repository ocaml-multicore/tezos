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
   Component: cache
   Invocation: dune exec tezt/long_tests/main.exe -- cache
   Subject: Testing the script cache

   Most of the tests need to fill the cache, which takes ~2 minutes on a
   fast machine. This is why this test is in the "long test" category.
   If at some point the cache layout can be set through protocol parameters,
   then we may consider duplicating these tests in the CI too.

*)

(*

   Helpers
   =======

*)

(*

   RPC helpers
   -----------

*)
let get_operations client =
  let* operations = RPC.get_operations client in
  return JSON.(operations |> geti 3 |> geti 0 |> get "contents")

let read_consumed_gas operation =
  JSON.(
    operation |> get "metadata" |> get "operation_result" |> get "consumed_gas"
    |> as_int)

let get_consumed_gas client =
  JSON.(
    let* operations = get_operations client in
    return @@ read_consumed_gas (operations |> geti 0))

let get_consumed_gas_for_block client =
  JSON.(
    let* operations = get_operations client in
    let gas =
      List.fold_left
        (fun gas op -> gas + read_consumed_gas op)
        0
        (operations |> as_list)
    in
    return gas)

let current_head = ["chains"; "main"; "blocks"; "head"]

let get_counter client =
  let* counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client
  in
  return @@ JSON.as_int counter

let get_size client =
  let* size =
    Client.(
      rpc GET (current_head @ ["context"; "cache"; "contracts"; "size"]) client)
  in
  return (JSON.as_int size)

let get_storage ~contract_id client =
  let* storage = RPC.Contracts.get_storage ~contract_id client in
  return
  @@ JSON.(
       List.assoc "args" (as_object storage) |> geti 0 |> fun x ->
       List.assoc "string" (as_object x) |> as_string)

(*

   Setup helpers
   -------------

*)

(** [init1 ~protocol] runs a single node running [protocol], returns
   an associated client. *)
let init1 ~protocol =
  let* node = Node.init [Synchronisation_threshold 0; Connections 0] in
  let* client = Client.init ~endpoint:(Node node) () in
  let* () = Client.activate_protocol ~protocol client in
  let* _ = Node.wait_for_level node 1 in
  Log.info "Activated protocol." ;
  return (node, client)

(** [originate_contract prefix contract] returns a function [originate]
    such that [originate client storage] deploys a new instance of
    [contract] initialized with [storage]. The instance name starts with
    [prefix]. *)
let originate_contract prefix contract =
  let id = ref 0 in
  let fresh () =
    incr id ;
    prefix ^ string_of_int !id
  in
  fun client storage ->
    let* contract_id =
      Client.originate_contract
        ~alias:(fresh ())
        ~amount:Tez.zero
        ~src:"bootstrap1"
        ~prg:contract
        ~init:storage
        ~burn_cap:Tez.(of_int 99999999999999)
        client
    in
    let* () = Client.bake_for client in
    Lwt.return contract_id

(** [originate_str_id_contract client str] bakes a block to originate the
   [str_id] contract with storage [str], and returns its address. *)
let originate_str_id_contract =
  let filename = "file:./tezt/tests/contracts/proto_alpha/large_str_id.tz" in
  let originate = originate_contract "str" filename in
  fun client str ->
    originate client (Printf.sprintf "Pair \"%s\" \"%s\"" str str)

(** [originate_str_id_contracts client n] creates [n] instances of
    [str_id] where the [k-th] instance starts with a storage
    containing [k] "x". *)
let originate_str_id_contracts client n =
  fold n [] @@ fun k contracts ->
  let s = String.make k 'x' in
  let* contract_id = originate_str_id_contract client s in
  return (contract_id :: contracts)

(** [originate_very_small_contract client] bakes a block to originate the
   [very_small] contract with storage [unit], and returns its address. *)
let originate_very_small_contract =
  let filename = "file:./tezt/tests/contracts/proto_alpha/very_small.tz" in
  let originate = originate_contract "very_small" filename in
  fun client -> originate client "Unit"

(** [originate_very_small_contracts client n] creates [n] instances
   of [large_types]. *)
let originate_very_small_contracts client n =
  fold n [] @@ fun _ contracts ->
  let* contract_id = originate_very_small_contract client in
  return (contract_id :: contracts)

(** [call_contract contract_id k client] bakes a block with a
    contract call to [contract_id], with [k] as an integer
    parameter, using [client]. It returns the amount of consumed
    gas. *)
let call_contract contract_id k client =
  let* () =
    Client.transfer
      ~amount:Tez.(of_int 100)
      ~burn_cap:Tez.(of_int 999999999)
      ~storage_limit:100000
      ~giver:"bootstrap1"
      ~receiver:contract_id
      ~arg:k
      client
  in
  let* () = Client.bake_for client in
  let* gas = get_consumed_gas client in
  Lwt.return gas

(** [call_contracts calls client] bakes a block with multiple contract
   [calls] using [client]. It returns the amount of consumed gas. *)
let call_contracts calls client =
  let* () =
    Client.multiple_transfers
      ~fee_cap:Tez.(of_int 9999999)
      ~burn_cap:Tez.(of_int 9999999)
      ~giver:"bootstrap1"
      ~json_batch:calls
      client
  in
  let* () = Client.bake_for client in
  let* gas = get_consumed_gas_for_block client in
  Lwt.return gas

(** [make_calls f contracts] *)
let make_calls f contracts =
  "[" ^ String.concat "," (List.map f contracts) ^ "]"

(** [str_id_calls contracts] is a list of calls to [contracts] that
   all are instances of [str_id.tz]. *)
let str_id_calls =
  make_calls (fun contract ->
      Printf.sprintf
        {| { "destination" : "%s", "amount" : "0",
             "arg" : "Left 4", "gas-limit" : "20000" } |}
        contract)

(** [large_types_calls contracts] is a list of calls to [contracts] that
   all are instances of [large_types.tz]. *)
let large_types_calls =
  make_calls (fun contract ->
      Printf.sprintf
        {| { "destination" : "%s", "amount" : "0",
             "arg" : "Unit", "gas-limit" : "1040000" } |}
        contract)

(** [very_small_calls contracts] is a list of calls to [contracts] that
   all are instances of [very_small.tz]. *)
let very_small_calls =
  make_calls (fun contract ->
      Printf.sprintf
        {| { "destination" : "%s", "amount" : "0",
             "arg" : "Unit", "gas-limit" : "1040000" } |}
        contract)

let liquidity_baking_address = "KT1TxqZ8QtKvLu3V3JH7Gx58n7Co8pgtpQU5"

(** [get_cached_contracts client] retrieves the cached scripts, except
    the liquidity baking CPMM script. *)
let get_cached_contracts client =
  let* contracts = RPC.Script_cache.get_cached_contracts client in
  let all =
    JSON.(
      as_list contracts
      |> List.map @@ fun t ->
         as_list t |> function [s; _] -> as_string s | _ -> assert false)
  in
  let all = List.filter (fun c -> c <> liquidity_baking_address) all in
  return all

(** [check label test ~protocol] registers a script cache test in
   Tezt.

   These tests are long because it takes ~2 minutes to fill the
   cache. Following Tezt recommendations, we set the timeout to ten
   times the actual excepted time.

*)
let check ?(tags = []) label test ~protocol ~executors =
  Long_test.register
    ~__FILE__
    ~title:(sf "(%s) Cache: %s" (Protocol.name protocol) label)
    ~tags:(["cache"] @ tags)
    ~timeout:(Minutes 2000)
    ~executors
  @@ test

(*

   Testsuite
   =========

*)

(*

   Testing basic script caching functionality
   ------------------------------------------

    We check that calling the same contract twice results in lower gas
    consumption thanks to the cache.

*)
let check_contract_cache_lowers_gas_consumption ~protocol =
  check "contract cache lowers gas consumption" ~protocol @@ fun () ->
  let* (_, client) = init1 ~protocol in
  let* contract_id = originate_str_id_contract client "" in
  let* gas1 = call_contract contract_id "Left 1" client in
  let* gas2 = call_contract contract_id "Left 1" client in
  return
  @@ Check.((gas2 < gas1) int)
       ~error_msg:"Contract cache should lower the gas consumption"

(*

   Testing LRU and size limit enforcement
   --------------------------------------

   The next test fills the cache with many instances of the contract
   [str_id.tz] in a sequence of blocks.

   Then, we can observe that:
   - the cache does not grow beyond its limit ;
   - the cache follows an LRU strategy.

*)
let check_full_cache ~protocol =
  check "contract cache does not go beyond its size limit" ~protocol
  @@ fun () ->
  let* (_, client) = init1 ~protocol in
  let s = String.make 1024 'x' in
  let* counter = get_counter client in

  let rec aux contracts previous_size nremoved k counter =
    if k = 0 then Lwt.return_unit
    else
      let* contract_id = originate_str_id_contract client s in
      let contracts = contract_id :: contracts in
      let* _ = call_contract contract_id "Left 4" client in

      let* size = get_size client in
      Log.info "%02d script(s) to be originated, cache size = %08d" k size ;
      let cache_is_full = previous_size = size in
      let nremoved = if cache_is_full then nremoved + 1 else nremoved in

      if k <= 3 && not cache_is_full then Test.fail "Cache should be full now." ;
      let* _ =
        if cache_is_full then (
          Log.info "The cache is full (size = %d | removed = %d)." size nremoved ;
          let* cached_contracts = get_cached_contracts client in
          if drop nremoved (List.rev contracts) <> cached_contracts then
            Test.fail "LRU strategy is not correctly implemented." ;
          return ())
        else return ()
      in
      aux contracts size nremoved (k - 1) (counter + 1)
  in
  aux [] 0 0 80 counter

(*

   Testing size limit enforcement within a block
   ---------------------------------------------

   We check that within a block, it is impossible to violate the cache
   size limit.

   This test is also a stress tests for the cache as we evaluate that
   the actual heap memory consumption of the node stays reasonable (<
   1GB) while the cache is filled with contracts.

*)
let check_block_impact_on_cache ~protocol =
  check "one cannot violate the cache size limit" ~protocol ~tags:["memory"]
  @@ fun () ->
  let* (node, client) = init1 ~protocol in

  let* (Node.Observe memory_consumption) = Node.memory_consumption node in

  (* The following number has been obtained by dichotomy and
     corresponds to the minimal number of instances of the str_id
     contract required to fill the cache. *)
  let ncontracts = 260 in

  let* green_contracts = originate_str_id_contracts client ncontracts in
  Log.info "Green contracts are originated" ;

  let* red_contracts = originate_str_id_contracts client ncontracts in
  Log.info "Red contracts are originated" ;
  let* _ = call_contracts (str_id_calls green_contracts) client in
  let* cached_contracts = get_cached_contracts client in
  let reds =
    List.filter (fun c -> not @@ List.mem c green_contracts) cached_contracts
  in
  if not List.(reds = []) then
    Test.fail "The cache should be full of green contracts." ;
  Log.info "The cache is full with green contracts." ;
  let* () = Client.bake_for client in

  let* gas = call_contracts (str_id_calls red_contracts) client in

  let* cached_contracts = get_cached_contracts client in
  let (greens, reds) =
    List.partition (fun c -> List.mem c green_contracts) cached_contracts
  in
  if List.(exists (fun c -> mem c green_contracts) cached_contracts) then (
    Log.info "Green contracts:\n%s\n" (String.concat "\n  " greens) ;
    Log.info "Red contracts:\n%s\n" (String.concat "\n  " reds) ;
    Test.fail "The green contracts should have been removed from the cache.") ;
  Log.info "It took %d unit of gas to replace the cache entirely." gas ;

  let* () = Client.bake_for client in
  let* size = get_size client in
  Log.info "Cache size after baking: %d\n" size ;

  let* ram_consumption_peak = memory_consumption () in
  match ram_consumption_peak with
  | Some ram_consumption_peak ->
      Log.info "The node had a peak of %d bytes in RAM" ram_consumption_peak ;
      if ram_consumption_peak >= 1024 * 1024 * 1024 then
        Test.fail "The node is consuming too much RAM."
      else return ()
  | None -> return ()

(*

   Testing proper handling of chain reorganizations
   ------------------------------------------------

   When a reorganization of the chain occurs, the cache must be
   backtracked to match the cache of the chosen head.

   Our testing strategy consists in looking at the evolution of a
   contract storage during a reorganization. Since contract storage is
   in the cache, this is an indirect way to check that the cache is
   consistent with the context.

   The test proceeds as follows:

   1. [divergence] creates two nodes [A] and [B]. One has a cache with
      a contract containing a string [s] while the other has a another
      head with a contract containing a string [u]. Node [B] has the
      longest chain, and thus its head will be chosen.

   2. [reorganize] triggers the resolution of the fork. Node [A] must
      backtrack on its cache.

   3. [check] validates that the contract now contains string [u].

*)
let check_cache_backtracking_during_chain_reorganization ~protocol =
  check "the cache handles chain reorganizations" ~protocol @@ fun () ->
  let* nodeA = Node.init [Synchronisation_threshold 0] in
  let* clientA = Client.init ~endpoint:(Node nodeA) () in
  let* nodeB = Node.init [Synchronisation_threshold 0] in
  let* nodeB_identity = Node.wait_for_identity nodeB in
  let* clientB = Client.init ~endpoint:(Node nodeB) () in
  let* () = Client.Admin.trust_address clientA ~peer:nodeB
  and* () = Client.Admin.trust_address clientB ~peer:nodeA in
  let* () = Client.Admin.connect_address clientA ~peer:nodeB in
  let* () = Client.activate_protocol ~protocol clientA in
  Log.info "Activated protocol" ;
  let* _ = Node.wait_for_level nodeA 1 and* _ = Node.wait_for_level nodeB 1 in
  Log.info "Both nodes are at level 1" ;
  let s = "x" in
  let* contract_id = originate_str_id_contract clientA s in
  let* _ = Node.wait_for_level nodeA 2 and* _ = Node.wait_for_level nodeB 2 in

  let expected_storage client expected_storage =
    let* storage = get_storage ~contract_id client in
    Log.info "storage = %s" storage ;
    if storage <> expected_storage then
      Test.fail "Invalid storage, got %s, expecting %s" storage expected_storage
    else return ()
  in

  let* () = expected_storage clientA "x" in

  Log.info "Both nodes are at level 2" ;

  let divergence () =
    let* () = Client.Admin.kick_peer clientA ~peer:nodeB_identity in

    let* _ = call_contract contract_id "Left 1" clientA in
    let* _ = Node.wait_for_level nodeA 3 in
    Log.info "Node A is at level 3" ;
    (* At this point, [nodeA] has a chain of length 3 with storage xx. *)
    let* () = expected_storage clientA "xx" in

    let* () = Node.wait_for_ready nodeB in
    let* _ = call_contract contract_id "Left 2" clientB in
    let* _ = Node.wait_for_level nodeB 3 in
    Log.info "Node B is at level 3" ;
    let* () = Client.bake_for clientB in
    let* _ = Node.wait_for_level nodeB 4 in
    Log.info "Node B is at level 4" ;
    (* At this point, [nodeB] has a chain of length 4 with storage xxxx. *)
    let* () = expected_storage clientB "xxxx" in
    return ()
  in

  let trigger_reorganization () =
    let* () = Client.Admin.connect_address clientA ~peer:nodeB in
    let* _ = Node.wait_for_level nodeA 4 in
    return ()
  in

  let check () =
    let* () = expected_storage clientA "xxxx" in
    let* _ = call_contract contract_id "Left 1" clientA in
    let* () = Client.bake_for clientA in
    let* () = expected_storage clientA "xxxxxxxx" in
    return ()
  in

  let* () = divergence () in
  let* () = trigger_reorganization () in
  let* () = check () in
  return ()

(*

   Testing efficiency of cache loading
   -----------------------------------

   We check that a node that has a full cache to reload is performing
   reasonably fast. This is important because the baker must be awaken
   sufficiently earlier before it bakes to preheat its cache.

   To that end, we create a node [A] and populate it with a full
   cache. We reboot [A] and measure the time it takes to reload the
   cache.

*)
let check_reloading_efficiency ~protocol body =
  let* (nodeA, clientA) = init1 ~protocol in
  let* _ = body clientA in
  let* () = Client.bake_for clientA in
  Log.info "Contracts are in the cache" ;
  let* size = get_size clientA in
  Log.info "Cache size after baking: %d\n" size ;
  let* cached_contracts = get_cached_contracts clientA in
  let* () = Node.terminate nodeA in
  let start = Unix.gettimeofday () in
  let* () = Node.run nodeA [Synchronisation_threshold 0] in
  let* () = Node.wait_for_ready nodeA in
  let* _ = RPC.is_bootstrapped clientA in
  let* _ = Client.bake_for clientA in
  let stop = Unix.gettimeofday () in
  let* cached_contracts' = get_cached_contracts clientA in
  let duration = stop -. start in
  Log.info "It took %f seconds to load a full cache" duration ;
  if cached_contracts <> cached_contracts' then
    Test.fail "Node A did not reload the cache correctly"
    (*

       A delay of 15 seconds at node starting time seems unacceptable,
       even on a CI runner. Hence, the following condition.

       In practice, we have observed a delay of 6 seconds on low
       performance machines.

    *)
  else if duration > 15. then
    Test.fail "Node A did not reload the cache sufficiently fast"
  else return ()

(*

   Fill the cache with as many entries as possible to check the
   efficiency of domain loading.

*)
let check_cache_reloading_is_not_too_slow ~protocol =
  let tags = ["reload"; "performance"] in
  check "a node reloads a full cache sufficiently fast" ~protocol ~tags
  @@ fun () ->
  check_reloading_efficiency ~protocol @@ fun client ->
  repeat 1000 @@ fun () ->
  let ncontracts = 5 in
  let* contracts = originate_very_small_contracts client ncontracts in
  let* () = Client.bake_for client in
  let* _ = call_contracts (very_small_calls contracts) client in
  return ()

(*

   The simulation correctly takes the cache into account.

*)
let check_simulation_takes_cache_into_account ~protocol =
  check "operation simulation takes cache into account" ~protocol @@ fun () ->
  let* (_, client) = init1 ~protocol in
  let* contract_id = originate_very_small_contract client in
  let* chain_id = RPC.get_chain_id client in
  let data block counter =
    Ezjsonm.value_from_string
    @@ Printf.sprintf
         {| { "operation" :
    { "branch": "%s",
      "contents": [
        { "kind": "transaction",
          "source": "%s",
          "fee": "1",
          "counter": "%d",
          "gas_limit": "800000",
          "storage_limit": "60000",
          "amount": "1",
          "destination": "%s",
        "parameters": {
          "entrypoint": "default",
          "value": { "prim" : "Unit" }
         }
        } ],
      "signature": "edsigtXomBKi5CTRf5cjATJWSyaRvhfYNHqSUGrn4SdbYRcGwQrUGjzEfQDTuqHhuA8b2d8NarZjz8TRf65WkpQmo423BtomS8Q"
    }, "chain_id" : "%s" } |}
         (JSON.as_string block)
         Constant.bootstrap1.public_key_hash
         counter
         contract_id
         (JSON.as_string chain_id)
  in
  let* () = Client.bake_for client in
  let gas_from_simulation counter =
    let* block = RPC.get_branch ~offset:0 client in
    let data = data block counter in
    let* result = RPC.post_run_operation client ~data in
    return (read_consumed_gas JSON.(get "contents" result |> geti 0))
  in
  let check simulation_gas real_gas =
    if simulation_gas <> real_gas then
      Test.fail
        "The simulation has a wrong gas consumption. Predicted %d, got %d."
        simulation_gas
        real_gas
  in
  let* gas_no_cache = gas_from_simulation 2 in
  Log.info "no cache: %d" gas_no_cache ;
  let* real_gas_consumption = call_contract contract_id "Unit" client in
  Log.info "real gas consumption with no cache: %d" real_gas_consumption ;
  check gas_no_cache real_gas_consumption ;
  let* () = Client.bake_for client in
  let* gas_with_cache = gas_from_simulation 3 in
  Log.info "with cache: %d" gas_with_cache ;
  let* real_gas_consumption = call_contract contract_id "Unit" client in
  Log.info "real gas consumption with cache: %d" real_gas_consumption ;
  check gas_with_cache real_gas_consumption ;
  return ()

(*

   Main entrypoints
   ----------------

*)
let register ~executors () =
  let protocol = Protocol.Alpha in
  check_contract_cache_lowers_gas_consumption ~protocol ~executors ;
  check_full_cache ~protocol ~executors ;
  check_block_impact_on_cache ~protocol ~executors ;
  check_cache_backtracking_during_chain_reorganization ~protocol ~executors ;
  check_cache_reloading_is_not_too_slow ~protocol ~executors ;
  check_simulation_takes_cache_into_account ~protocol ~executors
