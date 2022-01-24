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
   Component:    Mempool
   Invocation:   dune exec tezt/tests/main.exe -- --file mempool.ml
   Subject:      .
*)

(* FIXME: https://gitlab.com/tezos/tezos/-/issues/1657

   Some refactorisation is needed. All new tests should be in the Revamped
   module (which will be erased once we have rewrote all the Legacy tests. *)

module Mempool = Tezt_tezos.Mempool

module Revamped = struct
  let log_step counter msg =
    let color = Log.Color.(bold ++ FG.blue) in
    let prefix = "step" ^ string_of_int counter in
    Log.info ~color ~prefix msg

  (* We override the default [bake_for] comment to wait on the next level
     incremented after the new block. If [wait_for_flush] is set we wait on
     a [flush] event from the mempool because the [set_head] event used by the
     default [bake_for] functions happens before a flush of the mempool.
     For mempool tests, we generally prefer to ensure that a [flush] did
     happen than a [set_head].

     Optionally, we can decide whether the block should be baked
     without taking the operations of the mempool.

     This function returns the level of the client after the bake. *)
  let bake_for ?keys ?(wait_for_flush = false) ~empty ~protocol node client =
    let flush_waiter =
      if wait_for_flush then Node.wait_for_request ~request:`Flush node
      else unit
    in
    let* level = Client.level client in
    let* () =
      if empty then
        let* empty_mempool_file = Client.empty_mempool_file () in
        Client.bake_for
          ~mempool:empty_mempool_file
          ~ignore_node_mempool:true
          ~protocol
          ?keys
          client
      else Client.bake_for ?keys client
    in
    let* () = flush_waiter in
    Node.wait_for_level node (level + 1)

  (** Calls RPC [POST /chains/main/mempool/filter] from [client], with [data]
      formatted from string [config_str]. If [log] is [true], also logs this
      string. *)
  let set_filter ?(log = false) config_str client =
    let* res =
      RPC.post_mempool_filter ~data:(Ezjsonm.from_string config_str) client
    in
    if log then Log.info "Updated filter config with: %s." config_str ;
    return res

  (* Wait for the [operation_to_reclassify] event from the prevalidator and
     return the number of operations that were set to be reclassified. *)
  let wait_for_operations_not_flushed_event node =
    let filter json = JSON.(json |> as_int_opt) in
    Node.wait_for node "operations_to_reclassify.v0" filter

  (* Wait for the [banned_operation_encountered] event from the
     prevalidator and yield if the operation hash is the same as
     [oph]. *)
  let wait_for_banned_operation_injection node oph =
    let filter json =
      match
        JSON.
          (json |-> "origin" |> as_string_opt, json |-> "oph" |> as_string_opt)
      with
      | (Some "injected", Some h) when String.equal h oph -> Some ()
      | _ -> None
    in
    Node.wait_for node "banned_operation_encountered.v0" filter

  (* [synchronize_mempool client node] calls the [request_operations] RPC from
     the [client] to retrieve mempool from its peers and waits for a [notify]
     event on the [node] (debug events must be enabled). *)
  let synchronize_mempool client node =
    let mempool_notify_waiter = Node.wait_for_request ~request:`Notify node in
    let* _ = RPC.mempool_request_operations client in
    mempool_notify_waiter

  let check_mempool ?(applied = []) ?(branch_delayed = [])
      ?(branch_refused = []) ?(refused = []) ?(outdated = [])
      ?(unprocessed = []) client =
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      Mempool.
        {
          applied;
          branch_delayed;
          branch_refused;
          refused;
          outdated;
          unprocessed;
        }
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"Expected mempool %L, got %R") ;
    unit

  (** {2 Tests } *)

  (** This test injects some transfer operations and checks that the mempool does
    not lose any operation after a flush even if it contains more than
    operations_batch_size operations. *)
  let flush_mempool =
    let operations_batch_size = 5 in
    let number_of_operations = operations_batch_size * 2 in
    let nb_additional_bootstrap_accounts = number_of_operations in
    Protocol.register_test
      ~__FILE__
      ~title:"Flush mempool"
      ~tags:["mempool"; "flush"]
    @@ fun protocol ->
    log_step
      1
      "Initialize a node with 'operations_batch_size=%d' and %d more bootstrap \
       accounts."
      operations_batch_size
      (number_of_operations - 5) ;
    let node = Node.create [Connections 0; Synchronisation_threshold 0] in
    let* () = Node.config_init node [] in
    Node.Config_file.(update node (set_prevalidator ~operations_batch_size)) ;
    let* () = Node.run node [] in
    let* () = Node.wait_for_ready node in
    let* client = Client.init ~endpoint:(Node node) () in
    let* additional_bootstrap_accounts =
      Lwt_list.map_s
        (fun i ->
          let alias = sf "bootstrap%d" i in
          let* key = Client.gen_and_show_keys ~alias client in
          return (key, None))
        (range
           (Constant.default_bootstrap_count + 1)
           (Constant.default_bootstrap_count + nb_additional_bootstrap_accounts))
    in
    let* parameter_file =
      Protocol.write_parameter_file
        ~additional_bootstrap_accounts
        ~base:(Either.right (protocol, None))
        []
    in
    let* () = Client.activate_protocol ~parameter_file ~protocol client in
    let* _ = Node.wait_for_level node 1 in

    log_step 2 "Inject %d transfer operations." number_of_operations ;
    let* _ =
      Tezos_base__TzPervasives.List.iter_s
        (fun ((key : Account.key), _) ->
          Client.transfer
            ~amount:(Tez.of_int 1)
            ~giver:key.alias
            ~receiver:Constant.bootstrap1.alias
            client)
        additional_bootstrap_accounts
    in

    log_step 3 "Check operations are all classified as 'Applied'." ;
    let* mempool = RPC.get_mempool client in
    let error_msg =
      "some operations not classified as 'applied: expected length %R, got %L"
    in
    Check.((List.length mempool.applied = number_of_operations) int ~error_msg) ;

    log_step 4 "Bake a block with an empty mempool." ;
    let* _ = bake_for ~wait_for_flush:true ~empty:true ~protocol node client in
    let* mempool_after_empty_block = RPC.get_mempool client in

    log_step 5 "Check that we did not lose any operation." ;
    let error_msg =
      "operations were lost after the flush: expected %L, got %R"
    in
    Check.((mempool = mempool_after_empty_block) Mempool.typ ~error_msg) ;

    log_step 6 "Inject endorsement operations." ;
    let* () = Client.endorse_for client ~protocol ~force:true in
    let* mempool_with_endorsement = RPC.get_mempool client in

    log_step 7 "Check endorsement is applied." ;
    let mempool_diff =
      Mempool.symmetric_diff mempool_after_empty_block mempool_with_endorsement
    in
    (* [mempool_diff] should contain only the applied endorsement. *)
    let mempool_expected =
      let open Mempool in
      try {empty with applied = [List.hd mempool_diff.applied]}
      with Not_found -> {empty with applied = ["<applied field was empty>"]}
    in
    let error_msg = "endorsement is not applied: expected %L, got %R" in
    Check.((mempool_expected = mempool_diff) Mempool.typ ~error_msg) ;

    log_step 8 "Bake with an empty mempool twice." ;
    let* () =
      repeat 2 (fun () ->
          let* _ =
            bake_for ~wait_for_flush:true ~protocol ~empty:true node client
          in
          unit)
    in
    let* last_mempool = RPC.get_mempool client in

    log_step 9 "Check endorsement is classified 'Outdated'." ;
    let error_msg = "one applied operation was lost: expected %L, got %R" in
    Check.((mempool_with_endorsement = last_mempool) Mempool.typ ~error_msg) ;
    let error_msg =
      "endorsement is not classified as 'outdated': length expected %L, got %R"
    in
    Check.(
      (List.compare_length_with last_mempool.outdated 1 = 0) int ~error_msg) ;
    unit

  (** This test tries to check that a branch_refused operation is not
      reclassified in the mempool after a head increment, but is reclassified
      after a branch switch. *)
  let recycling_branch_refused =
    Protocol.register_test
      ~__FILE__
      ~title:
        "Ensure that branch_refused operation is not recycled when we \
         increment our head"
      ~tags:["mempool"; "recycle"; "branch_refused"]
    @@ fun protocol ->
    log_step 1 "Connect and initialise two nodes." ;
    let* node1 =
      Node.init
        ~event_sections_levels:[("prevalidator", `Debug)]
        [Synchronisation_threshold 0; Private_mode]
    and* node2 = Node.init [Synchronisation_threshold 0; Private_mode] in
    let* client1 = Client.init ~endpoint:(Node node1) ()
    and* client2 = Client.init ~endpoint:(Node node2) () in
    let* () = Client.Admin.trust_address client1 ~peer:node2
    and* () = Client.Admin.trust_address client2 ~peer:node1 in
    let* () = Client.Admin.connect_address client1 ~peer:node2 in
    let* () = Client.activate_protocol ~protocol client1 in
    let* _ = Node.wait_for_level node1 1 and* _ = Node.wait_for_level node2 1 in

    log_step 2 "Inject a transfer operation on node1." ;
    let* (`OpHash oph) =
      Operation.inject_transfer
        ~wait_for_injection:node1
        ~amount:1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client1
    in
    Log.info "%s injected on node1." oph ;

    log_step 3 "Check that the operation %s is classified as 'Applied'." oph ;
    let* mempool_after_injection = RPC.get_mempool client1 in
    let expected_mempool_after_injection =
      Mempool.{empty with applied = [oph]}
    in
    let error_msg =
      "expected mempool from node1 after injection was %L got %R"
    in
    Check.(
      (expected_mempool_after_injection = mempool_after_injection)
        Mempool.classified_typ
        ~error_msg) ;

    log_step
      4
      "Bake a block that includes %s and wait node2 to be synchronised."
      oph ;
    let* level =
      bake_for
        ~keys:[Constant.bootstrap4.public_key_hash]
        ~empty:false
        ~protocol
        node1
        client1
    in
    let* _ = Node.wait_for_level node2 level in

    log_step 5 "Disconnect nodes." ;
    let* node2_identity = Node.wait_for_identity node2 in
    let* () = Client.Admin.kick_peer ~peer:node2_identity client1 in

    log_step
      6
      "Force inject a transfer with the same counter and the same source as %s \
       on node1."
      oph ;
    let* counter =
      RPC.Contracts.get_counter
        ~contract_id:Constant.bootstrap1.public_key_hash
        client1
    in
    let counter = JSON.as_int counter in
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node1
        ~force:true
        ~counter
        ~amount:2
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client1
    in
    Log.info "%s injected on node1." oph2 ;

    log_step 7 "Check that the operation %s is branch_refused." oph2 ;
    let* mempool_after_second_injection = RPC.get_mempool client1 in
    let expected_mempool_after_second_injection =
      let open Mempool in
      {empty with branch_refused = [oph2]}
    in
    let error_msg =
      "expected mempool from node1 after injection was %L got %R"
    in
    Check.(
      (expected_mempool_after_second_injection = mempool_after_second_injection)
        Mempool.classified_typ
        ~error_msg) ;

    log_step 8 "Bake on node1 (head increment)." ;
    let bake_waiter1 = wait_for_operations_not_flushed_event node1 in
    let* () =
      Client.bake_for ~keys:[Constant.bootstrap4.public_key_hash] client1
    in
    let* pending = bake_waiter1 in

    log_step 9 "Checks that %s is not reclassified." oph2 ;
    let error_msg =
      "no operation should have been reclassified on head increment got %L \
       operations"
    in
    Check.((pending = 0) int ~error_msg) ;

    log_step
      10
      "Check that %s is still branch_refused after head increment."
      oph2 ;
    let* mempool_after_head_increment = RPC.get_mempool client1 in
    let error_msg =
      "expected mempool from node1 after head increment was %L got %R"
    in
    Check.(
      (expected_mempool_after_second_injection = mempool_after_head_increment)
        Mempool.classified_typ
        ~error_msg) ;

    log_step
      11
      "Bake on node2 to force higher fitness and to force a switch of head \
       when node2 will reconnect with node1." ;
    let* () =
      repeat 4 (fun () ->
          let* _ = bake_for ~empty:false ~protocol node2 client2 in
          unit)
    in

    log_step 12 "Reconnect node1 and node2." ;
    let bake_waiter1 = wait_for_operations_not_flushed_event node1 in
    let* () = Client.Admin.connect_address client1 ~peer:node2 in

    (* TODO: this test should be adapt once the [bake for] command will have
       an option to not automatically add an endorsement to a block that is
       being bake. Only one operation will be reclassified after that. *)
    log_step
      13
      "Check that %s is set to be reclassified on new branch as well as the \
       endorsement from the head increment on node1."
      oph2 ;
    let* pending = bake_waiter1 in
    let error_msg =
      "two operations should be reclassified on new branch got %L operations"
    in
    Check.((pending = 2) int ~error_msg) ;

    log_step
      14
      "Check that the mempool of node1 still contains %s as branch_refused \
       operation and that the endorsement from the head increment block is now \
       outdated."
      oph2 ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool =
      let open Mempool in
      let outdated =
        try [List.hd mempool.outdated]
        with Not_found -> ["<outdated field was empty>"]
      in
      {empty with branch_refused = [oph2]; outdated}
    in
    let error_msg = "expected mempool from node1 was %L got %R" in
    Check.((expected_mempool = mempool) Mempool.classified_typ ~error_msg) ;
    unit

  (** This test bans an operation and checks that a branch_delayed operation
      is classified again. *)
  let ban_operation_branch_delayed_reevaluated =
    Protocol.register_test
      ~__FILE__
      ~title:"ban_operation_branch_delayed_reevaluated"
      ~tags:["mempool"; "ban"; "branch_delayed"]
    @@ fun protocol ->
    log_step 1 "Initialize a node and a client." ;
    let* (node, client) = Client.init_with_protocol ~protocol `Client () in

    log_step 2 "Forge and inject an operation on the node." ;
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~amount:1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      3
      "Check that the operation %s is applied in the node's mempool."
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool = {Mempool.empty with applied = [oph1]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 4 "Forge and inject an operation with the same manager." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~force:true
        ~amount:2
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      5
      "Check that the operation %s is branch_delayed in the node's mempool."
      oph2 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool = {expected_mempool with branch_delayed = [oph2]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 6 "Ban the operation %s." oph1 ;
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client in

    log_step 7 "Check that the node's mempool contains %s as applied." oph2 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool = {Mempool.empty with applied = [oph2]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;
    unit

  (** This test checks the one operation per manager per block restriction on
      injection.
      We inject two operations with the same manager and check that the second
      one is classified as branch_delayed at post_filtering since the pre-filter
      is not run at injection. Only the first operation is sent to a second
      node that bake a block. The second operation is then reclassified. *)
  let one_operation_per_manager_per_block_restriction_injection =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_injection"
      ~tags:["mempool"; "manager_restriction"; "injection"]
    @@ fun protocol ->
    log_step 1 "Initialize two nodes and connect them." ;
    let* (node1, client1) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in
    let* (node2, client2) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in
    let* () = Client.Admin.connect_address ~peer:node2 client1 in

    log_step 2 "Forge and inject an operation on node1." ;
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client1
    in

    log_step
      3
      "Forge and inject an operation on node1 with the same source but \
       different destination." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~force:true
        ~wait_for_injection:node1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap3
        client1
    in

    log_step
      4
      "Ensure that the first operation is applied and that the second is \
       branch_delayed on node1." ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool =
      {Mempool.empty with applied = [oph1]; branch_delayed = [oph2]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"node1 mempool expected to be %L, got %R") ;

    log_step
      5
      "Ensure that the first operation is applied on node2 and that no other \
       operation is in the mempool." ;
    let* mempool = RPC.get_mempool client2 in
    let expected_mempool = {Mempool.empty with applied = [oph1]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"node2 mempool expected to be %L, got %R") ;

    log_step 6 "Bake a block on node2." ;
    let* _ = bake_for ~empty:false ~protocol node1 client2 in

    log_step
      7
      "Check that the second operation has not been baked because it was not \
       propagated to node2. And check that it is now branch_refused in node1 \
       because it used the same counter as the applied operation." ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool = {Mempool.empty with branch_refused = [oph2]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"node1 mempool expected to be %L, got %R") ;
    unit

  (** This test checks the one operation per manager per block restriction on
      propagation.
      We inject two operations with the same manager (and same counter) on two
      differents nodes.
      The first operation is propagated to a third node and classified as
      applied. Then the second operation is propagated to the third node we
      check that the second operation is classified as branch_delayed *)
  let one_operation_per_manager_per_block_restriction_propagation =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_propagation"
      ~tags:["mempool"; "manager_restriction"; "propagation"]
    @@ fun protocol ->
    log_step 1 "Initialize three nodes with the protocol." ;
    let* (node1, client1) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0; Private_mode]
        ~protocol
        `Client
        ()
    in
    let* (node2, client2) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0; Private_mode]
        ~protocol
        `Client
        ()
    in
    let* (node3, client3) =
      Client.init_with_protocol
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in

    log_step 2 "Forge and inject an operation on node1." ;
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client1
    in

    log_step
      3
      "Forge and inject an operation on node2 with the same manager and \
       counter but a different destination." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node2
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap3
        client2
    in

    log_step
      4
      "Propagate %s from node1 to node3 and check that it is classified as \
       applied."
      oph1 ;
    let* () = Client.Admin.trust_address client3 ~peer:node1
    and* () = Client.Admin.trust_address client1 ~peer:node3 in
    let* () = Client.Admin.connect_address ~peer:node1 client3 in
    let* () = synchronize_mempool client3 node3 in
    let* mempool_first_injection = RPC.get_mempool client3 in
    let expected_mempool_first_injection =
      {Mempool.empty with applied = [oph1]}
    in
    Check.(
      (expected_mempool_first_injection = mempool_first_injection)
        Mempool.classified_typ
        ~error_msg:"node3 mempool expected to be %L, got %R") ;

    log_step
      5
      "Propagate %s from node2 to node3 and check that it is classified as \
       branch_delayed."
      oph2 ;
    let* () = Client.Admin.trust_address client3 ~peer:node2
    and* () = Client.Admin.trust_address client2 ~peer:node3 in
    let* () = Client.Admin.connect_address ~peer:node2 client3 in
    let* () = synchronize_mempool client3 node3 in
    let* mempool_second_injection = RPC.get_mempool client3 in
    let expected_mempool_second_injection =
      {expected_mempool_first_injection with branch_delayed = [oph2]}
    in
    Check.(
      (expected_mempool_second_injection = mempool_second_injection)
        Mempool.classified_typ
        ~error_msg:"node3 mempool expected to be %L, got %R") ;
    unit

  (** This test checks that one operation per manager per block is not enabled
      if precheck is disabled. *)
  let one_operation_per_manager_per_block_disable_precheck =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_disable_precheck"
      ~tags:["mempool"; "manager_restriction"; "disable_precheck"]
    @@ fun protocol ->
    log_step
      1
      "Initialize a node, with the precheck of operation disable and a client." ;
    let* (node, client) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0; Disable_operations_precheck]
        ~protocol
        `Client
        ()
    in

    log_step 2 "Forge and inject an operation on the node." ;
    let* counter =
      RPC.Contracts.get_counter
        ~contract_id:Constant.bootstrap1.public_key_hash
        client
    in
    let counter = JSON.as_int counter in
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~counter:(counter + 1)
        ~amount:1
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      3
      "Check that the operation %s is applied in the node's mempool."
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool = {Mempool.empty with applied = [oph1]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step
      4
      "Forge and force inject an operation with the same manager that should \
       fail because the counter was not incremented." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~counter:(counter + 1)
        ~force:true
        ~amount:2
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      5
      "Check that the operation %s is applied and that %s is branch_refused in \
       the node's mempool."
      oph1
      oph2 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph1]; branch_refused = [oph2]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step
      6
      "Forge and inject an operation with the same manager with incremented \
       counter." ;
    let* (`OpHash oph3) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~counter:(counter + 2)
        ~amount:2
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      7
      "Check that the operations %s and %s are applied and that %s is \
       branch_refused in the node's mempool."
      oph1
      oph3
      oph2 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph1; oph3]; branch_refused = [oph2]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;
    unit

  (** This test checks that an operation branch_delayed is still branch_delayed
      after a flush either because of the one operation per manager per block or
      the previous reason it was branch_delayed for. *)
  let one_operation_per_manager_per_block_flush =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_flush"
      ~tags:["mempool"; "manager_restriction"; "flush"]
    @@ fun protocol ->
    log_step 1 "Initialize a node and a client." ;
    let* (node, client) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in

    log_step 2 "Force inject a transfer with a counter in the futur." ;
    let* counter =
      RPC.Contracts.get_counter
        ~contract_id:Constant.bootstrap1.public_key_hash
        client
    in
    let counter = JSON.as_int counter in
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~force:true
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        ~counter:(counter + 2)
        client
    in

    log_step 3 "Inject a transfer with a correct counter." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        ~counter:(counter + 1)
        client
    in

    log_step
      4
      "Inject a transfer with a correct counter but different destination." ;
    (* with force to avoid failure *)
    let* (`OpHash oph3) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap3
        ~counter:(counter + 1)
        ~force:true
        client
    in

    log_step
      5
      "Check that the mempool contains %s as applied and %s as branch_delayed."
      oph2
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph2]; branch_delayed = [oph1; oph3]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 6 "Flush the mempool." ;
    let* _ = bake_for ~wait_for_flush:true ~empty:true ~protocol node client in

    log_step
      7
      "Check that the mempool still contains %s as branch_delayed after the \
       flush."
      oph1 ;
    let* mempool = RPC.get_mempool client in
    Check.(
      (List.mem oph1 mempool.branch_delayed = true)
        bool
        ~error_msg:(sf "%s should be in branch_delayed" oph1)) ;

    log_step
      8
      "Check that if %s is applied then %s is branch_delayed or the other way \
       around."
      oph2
      oph3 ;
    let* mempool = RPC.get_mempool client in
    Check.(
      (((List.mem oph2 mempool.branch_delayed && List.mem oph3 mempool.applied)
       || (List.mem oph3 mempool.branch_delayed && List.mem oph2 mempool.applied)
       )
      = true)
        bool
        ~error_msg:
          (sf
             "applied should contain either %s or %s and branch_delayed should \
              contain the other one"
             oph2
             oph3)) ;
    unit

  (** This test checks that if we inject an operation from the same source,
      and with the same counter, injection will fail if ~force is false
      because the operation will not be applied/prechecked. *)
  let one_operation_per_manager_per_block_inject_not_applied =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_inject_1M"
      ~tags:["mempool"; "manager_restriction"; "inject"]
    @@ fun protocol ->
    log_step 1 "Initialize a node and a client." ;
    let* (node, client) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in
    let* counter =
      RPC.Contracts.get_counter
        ~contract_id:Constant.bootstrap1.public_key_hash
        client
    in
    let counter = JSON.as_int counter in

    log_step 2 "Inject a transfer with a correct counter." ;
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        ~counter:(counter + 1)
        client
    in
    log_step
      3
      "Attempt to inject a transfer with a correct counter but different \
       destination (~force: %b)."
      false ;

    let* op2 =
      Operation.mk_transfer
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap3
        ~counter:(counter + 1)
        client
    in
    let* branch = Operation.get_injection_branch client in
    let* (`Hex op_str_hex as op_hex) =
      Operation.forge_operation ~protocol ~branch ~batch:[op2] client
    in
    let (`Hex signature) =
      Operation.sign_manager_op_hex ~signer:Constant.bootstrap2 op_hex
    in
    let signed_op = op_str_hex ^ signature in
    let p = RPC.spawn_inject_operation ~data:(`String signed_op) client in

    log_step 4 "Check that injection failed as expected." ;
    let injection_error_rex =
      rex
        ~opts:[`Dotall]
        "Fatal error:\n  Command failed: Error while applying operation.*:"
    in
    let* () = Process.check_error ~msg:injection_error_rex p in

    log_step
      5
      "Check that the mempool contains %s as applied and no op as \
       branch_delayed."
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph1]; branch_delayed = []}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;
    unit

  (** This test checks that an operation applied is not reclassified and stays
      applied after the ban of a branch_delayed operation. *)
  let one_operation_per_manager_per_block_ban =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_ban"
      ~tags:["mempool"; "manager_restriction"; "ban"]
    @@ fun protocol ->
    log_step 1 "Initialize a node and a client." ;
    let* (node, client) =
      Client.init_with_protocol
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in

    log_step 2 "Force inject a transfer with a counter in the futur." ;
    let* counter =
      RPC.Contracts.get_counter
        ~contract_id:Constant.bootstrap1.public_key_hash
        client
    in
    let counter = JSON.as_int counter in
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~force:true
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        ~counter:(counter + 2)
        client
    in

    log_step 3 "Inject a transfer with a correct counter." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        ~counter:(counter + 1)
        client
    in

    log_step
      4
      "Check that the mempool contains %s as applied and %s as branch_delayed."
      oph2
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph2]; branch_delayed = [oph1]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 5 "Ban the operation %s." oph1 ;
    let to_reclassified = ref false in
    let _ =
      Node.wait_for node "operations_to_reclassify.v0" (fun _ ->
          to_reclassified := true ;
          Some ())
    in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client in

    log_step
      6
      "Check that the mempool contains %s as applied and that %s is not in the \
       mempool anymore."
      oph2
      oph1 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool = {Mempool.empty with applied = [oph2]} in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 7 "Check that no flush have been triggered after the ban." ;
    Check.(
      (!to_reclassified = false)
        bool
        ~error_msg:"a flush have been triggered after the ban") ;
    unit

  (* This test checks that on a ban of an applied operation the flush respect
     the 1M invariant. *)
  let one_operation_per_manager_per_block_flush_on_ban =
    Protocol.register_test
      ~__FILE__
      ~title:"Manager_restriction_flush_on_ban"
      ~tags:["mempool"; "manager_restriction"; "flush"; "ban"]
    @@ fun protocol ->
    log_step 1 "Initialize a node and a client." ;
    let* (node, client) =
      Client.init_with_protocol
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0]
        ~protocol
        `Client
        ()
    in
    log_step 2 "Inject a transfer." ;
    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap2
        ~dest:Constant.bootstrap2
        client
    in

    log_step 3 "Inject a transfer with a different source." ;
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in

    log_step
      4
      "Inject a transfer with the same source but different destination. This \
       operation should be classified as branch_delayed with the 1M \
       restriction." ;
    (* with force to avoid failure *)
    let* (`OpHash oph3) =
      Operation.inject_transfer
        ~force:true
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap3
        client
    in

    log_step
      5
      "Check that the mempool contains %s and %s as applied, %s as \
       branch_delayed."
      oph1
      oph2
      oph3 ;
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      {Mempool.empty with applied = [oph1; oph2]; branch_delayed = [oph3]}
    in
    Check.(
      (expected_mempool = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 5 "Ban the operation %s." oph1 ;
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client in

    log_step
      6
      "Check that %s is not in the mempool anymore and that one operation is \
       applied and the other is branch_delayed between %s and %s."
      oph1
      oph2
      oph3 ;
    let* mempool = RPC.get_mempool client in
    Check.(
      (List.length mempool.applied = 1)
        int
        ~error_msg:"applied mempool should contain only one operation, got %L") ;
    Check.(
      (List.length mempool.branch_delayed = 1)
        int
        ~error_msg:
          "branch_delayed mempool should contain only one operation, got %L") ;
    unit

  let max_refused_operations ~protocol classification =
    let max_refused_operations = 1 in
    let source1 = Constant.bootstrap1 in
    let source2 = Constant.bootstrap2 in
    let dest = Constant.bootstrap3 in
    let string_of_classification =
      match classification with
      | `Branch_delayed -> "branch_delayed"
      | `Branch_refused -> "branch_refused"
      | `Refused -> "refused"
    in
    let operation_fees_from_classification = function
      | `Branch_delayed | `Branch_refused -> None
      | `Refused -> Some 0
      (* fees_too_low *)
    in
    let counter_shift_from_classification counter = function
      | `Branch_delayed -> Some (counter + 2)
      (* counter in the future *)
      | `Branch_refused -> Some counter
      (* counter in the past *)
      | `Refused -> None
    in
    log_step
      1
      "Initialize a node with 'max_refused_operations=%d'."
      max_refused_operations ;
    let node = Node.create [Connections 0; Synchronisation_threshold 0] in
    let* () = Node.config_init node [] in
    Node.Config_file.(update node (set_prevalidator ~max_refused_operations)) ;
    let* () = Node.run node [] in
    let* () = Node.wait_for_ready node in
    let* client = Client.init ~endpoint:(Node node) () in
    let* () = Client.activate_protocol ~protocol client in
    let* _ = Node.wait_for_level node 1 in

    log_step
      2
      "Forge and inject operations. Then, bake to increment the counter of \
       boostrap1 and bootstrap2 in the context" ;
    let* _ =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:source1
        ~dest
        ~amount:1
        client
    in
    let* _ =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:source2
        ~dest
        ~amount:1
        client
    in
    let* _ = bake_for ~wait_for_flush:true ~empty:false ~protocol node client in

    log_step 3 "Forge and force inject an operation." ;
    let* counter =
      RPC.Contracts.get_counter ~contract_id:source1.public_key_hash client
    in
    let counter =
      counter_shift_from_classification (JSON.as_int counter) classification
    in
    let fee = operation_fees_from_classification classification in

    let* (`OpHash oph1) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~force:true
        ~source:source1
        ~dest
        ?counter
        ?fee
        client
    in

    log_step
      3
      "Flush the mempool and check that %s is classified as %s."
      oph1
      string_of_classification ;
    let* _ = bake_for ~empty:true ~protocol ~wait_for_flush:true node client in
    let* mempool = RPC.get_mempool client in
    let expected_mempool =
      match classification with
      | `Branch_delayed -> {Mempool.empty with branch_delayed = [oph1]}
      | `Branch_refused -> {Mempool.empty with branch_refused = [oph1]}
      | `Refused -> {Mempool.empty with refused = [oph1]}
    in
    Check.(
      (mempool = expected_mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 4 "Forge and force inject an operation." ;
    let* counter =
      RPC.Contracts.get_counter ~contract_id:source2.public_key_hash client
    in
    let counter =
      counter_shift_from_classification (JSON.as_int counter) classification
    in
    let fee = operation_fees_from_classification classification in
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~force:true
        ~source:source2
        ~dest
        ?counter
        ?fee
        client
    in

    log_step
      5
      "Flush the mempool to classify %s as %s and check that the mempool \
       contains only one operation %s."
      oph2
      string_of_classification
      string_of_classification ;
    let* _ = bake_for ~empty:true ~protocol ~wait_for_flush:true node client in
    let* mempool = RPC.get_mempool client in
    let (mempool_classification, mempool_without_classification) =
      match classification with
      | `Branch_delayed ->
          (mempool.branch_delayed, {Mempool.empty with branch_delayed = []})
      | `Branch_refused ->
          (mempool.branch_refused, {Mempool.empty with branch_refused = []})
      | `Refused -> (mempool.refused, {Mempool.empty with refused = []})
    in
    Check.(
      (max_refused_operations = List.length mempool_classification)
        int
        ~error_msg:"number of operation in mempool expected to be %L, got %R") ;
    Check.(
      (Mempool.empty = mempool_without_classification)
        Mempool.classified_typ
        ~error_msg:"the rest of the mempool should be empty got %R") ;
    unit

  (** This test checks max_refused_operations for branch_delayed
     classification. *)
  let max_refused_operations_branch_delayed =
    Protocol.register_test
      ~__FILE__
      ~title:"Max refused operations branch_delayed"
      ~tags:["mempool"; "refused"; "max"; "branch_delayed"]
    @@ fun protocol -> max_refused_operations ~protocol `Branch_delayed

  (** This test checks max_refused_operations for branch_refused
     classification. *)
  let max_refused_operations_branch_refused =
    Protocol.register_test
      ~__FILE__
      ~title:"Max refused operations branch_refused"
      ~tags:["mempool"; "refused"; "max"; "branch_refused"]
    @@ fun protocol -> max_refused_operations ~protocol `Branch_refused

  (** This test checks max_refused_operations for refused classification. *)
  let max_refused_operations_refused =
    Protocol.register_test
      ~__FILE__
      ~title:"Max refused operations refused"
      ~tags:["mempool"; "refused"; "max"]
    @@ fun protocol -> max_refused_operations ~protocol `Refused

  (** This test checks max_refused_operations for outdated classification. *)
  let max_refused_operations_outdated =
    let max_refused_operations = 1 in
    Protocol.register_test
      ~__FILE__
      ~title:"Max refused operations outdated"
      ~tags:["mempool"; "refused"; "max"; "outdated"]
    @@ fun protocol ->
    log_step
      1
      "Initialize a node with 'max_refused_operations=%d'."
      max_refused_operations ;
    let node = Node.create [Connections 0; Synchronisation_threshold 0] in
    let* () = Node.config_init node [] in
    Node.Config_file.(update node (set_prevalidator ~max_refused_operations)) ;
    let* () = Node.run node [] in
    let* () = Node.wait_for_ready node in
    let* client = Client.init ~endpoint:(Node node) () in
    let* () = Client.activate_protocol ~protocol client in
    let* _ = Node.wait_for_level node 1 in

    log_step 2 "Bake an empty block to be able to endorse it." ;
    let* _ = bake_for ~empty:true ~protocol ~wait_for_flush:true node client in

    log_step 3 "Endorse with bootstrap1." ;
    let* _ =
      Client.endorse_for
        ~protocol
        ~key:[Constant.bootstrap1.alias]
        ~force:true
        client
    in

    log_step 3 "Endorse with bootstrap2." ;
    let* _ =
      Client.endorse_for
        ~protocol
        ~key:[Constant.bootstrap2.alias]
        ~force:true
        client
    in

    log_step 4 "Check that both endorsements are in the applied mempool." ;
    let* mempool = RPC.get_mempool client in
    Check.(
      (2 = List.length mempool.applied)
        int
        ~error_msg:
          "number of mempool applied operations expected to be %L, got %R") ;

    log_step 5 "Bake two empty block to force endorsements to be outdated." ;
    let* _ = bake_for ~empty:true ~protocol ~wait_for_flush:true node client in
    let* _ = bake_for ~empty:true ~protocol ~wait_for_flush:true node client in

    log_step 4 "Check that only one endorsement is in the outdated mempool." ;
    let* mempool = RPC.get_mempool client in
    Check.(
      (max_refused_operations = List.length mempool.outdated)
        int
        ~error_msg:
          "number of mempool outdated operations expected to be %L, got %R") ;
    Check.(
      (Mempool.empty = {mempool with outdated = []})
        Mempool.classified_typ
        ~error_msg:"the rest of the mempool should be empty got %R") ;
    unit

  (* We check ban operations cannot be propagated and stay banned
     after a flush. *)
  let ban_operation =
    Protocol.register_test
      ~__FILE__
      ~title:"mempool ban operation"
      ~tags:["mempool"; "node"; "ban"]
    @@ fun protocol ->
    log_step
      1
      "Node 1 activates the protocol and Node 2 catches up with Node 1." ;
    let* (node1, client1) =
      Client.init_with_node
        ~nodes_args:[Synchronisation_threshold 0; Connections 1]
        `Client
        ()
    in
    let* (node2, client2) =
      Client.init_with_node
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0; Connections 2]
        `Client
        ()
    in
    let* () = Client.Admin.connect_address client1 ~peer:node2 in
    let* () = Client.activate_protocol ~protocol client1 in
    let* _ = Node.wait_for_level node1 1 and* _ = Node.wait_for_level node2 1 in

    log_step 2 "Injection of two operations (transfers)." ;
    let notify_in_node2 = Node.wait_for_request ~request:`Notify node2 in
    let inject_op1 node client =
      Operation.inject_transfer
        ~wait_for_injection:node
        ~source:Constant.bootstrap1
        ~dest:Constant.bootstrap2
        client
    in
    let* (`OpHash oph1) = inject_op1 node1 client1 in
    let* () = notify_in_node2 in
    let notify_in_node2 = Node.wait_for_request ~request:`Notify node2 in
    let* (`OpHash oph2) =
      Operation.inject_transfer
        ~wait_for_injection:node1
        ~source:Constant.bootstrap3
        ~dest:Constant.bootstrap5
        client1
    in
    let* () = notify_in_node2 in
    let* () = check_mempool ~applied:[oph2; oph1] client2 in

    log_step 3 "Ban %s on node 2." oph1 ;
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client2 in
    let* () = check_mempool ~applied:[oph2] client2 in

    log_step 4 "Try to reinject the banned operation in Node 2." ;
    let* _ = inject_op1 node2 client2 in
    let* () = check_mempool ~applied:[oph2] client2 in

    log_step 5 "Add node3 connected only to node2." ;
    let* (node3, client3) =
      Client.init_with_node
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0; Connections 1]
        `Client
        ()
    in
    let* () = Client.Admin.connect_address client3 ~peer:node2 in
    let* _ = Node.wait_for_level node3 1 in

    log_step 6 "Check %s is not in node3's mempool." oph1 ;
    let* () = synchronize_mempool client3 node3 in
    let* () = check_mempool ~applied:[oph2] client2 in

    log_step
      7
      "Bake and check %s was not included and is not in node2's mempool either."
      oph1 ;
    let baking = Node.wait_for_request ~request:`Flush node2 in
    let* () = Client.bake_for client2 in
    let* _ = baking in
    (* empty mempool *)
    let* () = check_mempool client2 in
    let* ops = RPC.get_operations client2 in
    let open JSON in
    let ops_list = ops |=> 3 |> as_list in
    let res =
      List.exists (fun e -> e |-> "hash" |> as_string = oph1) ops_list
    in
    Check.((res = false) bool ~error_msg:(sf "%s was found in block" oph1)) ;
    unit

  (* Check that we can reinject and reclassify an operation that was
     ban and then unbanned.*)
  let unban_operation_and_reinject =
    Protocol.register_test
      ~__FILE__
      ~title:"mempool unban operation and reinject"
      ~tags:["mempool"; "node"; "ban"; "reinject"]
    @@ fun protocol ->
    log_step 1 "Start a single node and activate the protocol." ;
    let* (node1, client1) =
      Client.init_with_node
        ~nodes_args:[Synchronisation_threshold 0; Connections 0]
        `Client
        ()
    in
    let inject_op ~wait op =
      let source =
        match op with
        | `A -> Constant.bootstrap1
        | `B -> Constant.bootstrap2
        | `C -> Constant.bootstrap3
      in
      let dest = Constant.bootstrap5 in
      let wait_for_injection = if wait then Some node1 else None in
      Operation.inject_transfer ?wait_for_injection ~source ~dest client1
    in
    let* () = Client.activate_protocol ~protocol client1 in
    let* _ = Node.wait_for_level node1 1 in

    log_step 2 "Inject two transfers op1 and op2." ;
    let* (`OpHash oph1) = inject_op ~wait:true `A in
    let* (`OpHash oph2) = inject_op ~wait:true `B in
    let* () = check_mempool ~applied:[oph1; oph2] client1 in

    log_step 3 "Ban op1 and ensure the operation is not in the mempool." ;
    (* We ban twice to check banning an operation is idempotent. *)
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client1 in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client1 in
    let* () = check_mempool ~applied:[oph2] client1 in

    log_step 4 "Inject op3." ;
    let* (`OpHash oph3) = inject_op ~wait:true `C in
    let* () = check_mempool ~applied:[oph3; oph2] client1 in

    log_step 5 "Ban op2 and op1 again." ;
    let* _ = RPC.mempool_ban_operation ~data:(`String oph2) client1 in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client1 in
    let* () = check_mempool ~applied:[oph3] client1 in

    log_step 6 "Check that reinjecting op1 fails." ;
    let wait_reinject_op1_banned =
      wait_for_banned_operation_injection node1 oph1
    in
    let _ = inject_op ~wait:false `A in
    let* () = wait_reinject_op1_banned in
    let* () = check_mempool ~applied:[oph3] client1 in

    log_step 7 "Unban op1, successfully reinject op1." ;
    let* _ = RPC.mempool_unban_operation ~data:(`String oph1) client1 in
    let* _ = inject_op ~wait:true `A in
    let* () = check_mempool ~applied:[oph3; oph1] client1 in

    log_step 8 "Check that reinjecting op2 still fails." ;
    let wait_reinject_op2_banned =
      wait_for_banned_operation_injection node1 oph2
    in
    let _ = inject_op ~wait:false `B in
    let* () = wait_reinject_op2_banned in

    log_step 9 "Unban op2, successfully reinject op2." ;
    let* _ = RPC.mempool_unban_operation ~data:(`String oph2) client1 in

    let* _ = inject_op ~wait:true `B in
    let* () = check_mempool ~applied:[oph3; oph2; oph1] client1 in

    log_step 10 "Ban op1 again, check that reinjecting it fails." ;
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client1 in

    let wait_reinject_op1_banned_again =
      wait_for_banned_operation_injection node1 oph1
    in
    let _ = inject_op ~wait:false `A in
    let* () = wait_reinject_op1_banned_again in
    let* () = check_mempool ~applied:[oph3; oph2] client1 in

    log_step 11 "Try unban op3 and op2 check that nothing changes." ;
    let* _ = RPC.mempool_unban_operation ~data:(`String oph3) client1 in
    let* _ = RPC.mempool_unban_operation ~data:(`String oph2) client1 in
    check_mempool ~applied:[oph3; oph2] client1

  (* This tests ban operations and then use the `unban_all` RPC on
     those operation. We check those operations are then propagated if
     we synchronise the mempools. *)
  let unban_all_operations =
    Protocol.register_test
      ~__FILE__
      ~title:"mempool unban all operations"
      ~tags:["mempool"; "node"; "ban"]
    @@ fun protocol ->
    log_step 1 "Start two nodes, connect them, activate the protocol." ;
    let* (node1, client1) =
      Client.init_with_node
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0; Connections 1]
        `Client
        ()
    in
    let* (node2, client2) =
      Client.init_with_node
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~nodes_args:[Synchronisation_threshold 0; Connections 1]
        `Client
        ()
    in
    let* () = Client.Admin.connect_address client1 ~peer:node2 in
    let* () = Client.activate_protocol ~protocol client1 in
    let* _ = Node.wait_for_level node1 1 and* _ = Node.wait_for_level node2 1 in

    log_step 2 "Inject four transfer operations" ;
    let inject_op ~wait op client =
      let source =
        match op with
        | `A -> Constant.bootstrap1
        | `B -> Constant.bootstrap2
        | `C -> Constant.bootstrap3
        | `D -> Constant.bootstrap4
      in
      let node =
        Client.get_mode client |> Client.mode_to_endpoint |> function
        | Some (Node node) -> node
        | _ -> assert false
      in
      let dest = Constant.bootstrap5 in
      let wait_for_injection = if wait then Some node else None in
      Operation.inject_transfer ?wait_for_injection ~source ~dest client
    in
    let* (`OpHash oph1) = inject_op ~wait:true `A client1 in
    let* (`OpHash oph2) = inject_op ~wait:true `B client1 in
    let* (`OpHash oph3) = inject_op ~wait:true `C client2 in
    let* (`OpHash oph4) = inject_op ~wait:true `D client2 in

    log_step 3 "Ban the first three of these operations." ;
    let* () = check_mempool ~applied:[oph4; oph3; oph2; oph1] client1 in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph1) client1 in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph2) client1 in
    let* _ = RPC.mempool_ban_operation ~data:(`String oph3) client1 in
    let* () = check_mempool ~applied:[oph4] client1 in

    log_step 4 "Unban all operations." ;
    (* We expect to receive three operations are the synchronisation. *)
    let wait1 = Node.wait_for_request ~request:`Arrived node1
    and wait2 = Node.wait_for_request ~request:`Arrived node1
    and wait3 = Node.wait_for_request ~request:`Arrived node1 in
    let* _ = RPC.mempool_unban_all_operations client1 in
    let* () = synchronize_mempool client1 node1 in
    let* () = wait1 and* () = wait2 and* () = wait3 in

    Log.info "Step 5: Check that node 1 contains the right applied operations." ;
    let* () = check_mempool ~applied:[oph4; oph3; oph2; oph1] client1 in
    check_mempool ~applied:[oph4; oph3; oph2; oph1] client2

  let test_prefiltered_limit =
    Protocol.register_test
      ~__FILE__
      ~title:"Test prefiltered limits of mempool"
      ~tags:["mempool"; "gc"; "limit"]
    @@ fun protocol ->
    log_step 0 "Connect and initialise two nodes." ;
    (* We configure the filter with a limit of 4, in order to easily be able to
       inject more with our 5 bootstrap accounts *)
    let max_prechecked_manager_operations = 4 in
    (* Control fees and gas limits to easily influence weight (i.e. ratio) *)
    let fee = 1000 in
    let gas_limit = 1500 in
    let* node1 =
      Node.init
        ~event_sections_levels:[("prevalidator", `Debug)]
        [Synchronisation_threshold 0; Private_mode]
    and* node2 = Node.init [Synchronisation_threshold 0; Private_mode] in
    let* client1 = Client.init ~endpoint:(Node node1) ()
    and* client2 = Client.init ~endpoint:(Node node2) () in
    let* () = Client.Admin.trust_address client1 ~peer:node2
    and* () = Client.Admin.trust_address client2 ~peer:node1 in
    let* () = Client.Admin.connect_address client1 ~peer:node2 in
    let* () = Client.activate_protocol ~protocol client1 in
    let* _ = Node.wait_for_level node1 1 and* _ = Node.wait_for_level node2 1 in

    log_step
      1
      "Update the nodes filter to allow only %d prechecked manager operations."
      max_prechecked_manager_operations ;
    let* _ =
      set_filter
        ~log:true
        (sf
           {|{ "max_prechecked_manager_operations" : %d }|}
           max_prechecked_manager_operations)
        client1
    and* _ =
      set_filter
        ~log:true
        (sf
           {|{ "max_prechecked_manager_operations" : %d }|}
           max_prechecked_manager_operations)
        client2
    in

    log_step
      2
      "Inject max_prechecked_manager_operations %d operations."
      max_prechecked_manager_operations ;
    let* ops =
      Lwt.all
      @@ List.mapi
           (fun i source ->
             let* (`OpHash oph) =
               Operation.inject_transfer
                 ~source
                 ~dest:Constant.bootstrap2
                 ~wait_for_injection:node1
                 ~amount:1
                 ~fee:(fee + i)
                 ~gas_limit
                 client1
             in
             return oph)
           Constant.[bootstrap1; bootstrap2; bootstrap3; bootstrap4]
    in

    log_step 3 "Check these operations are applied in mempool." ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool0 = {Mempool.empty with applied = ops} in
    Check.(
      (expected_mempool0 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step
      4
      "The client should report when the mempool is full and not enough fees \
       are provided." ;
    let transfer_should_fail =
      Client.spawn_transfer
        ~giver:Constant.bootstrap5.alias
        ~receiver:Constant.bootstrap2.alias
        ~amount:(Tez.of_int 55)
        ~fee:(Tez.of_mutez_int fee)
        ~gas_limit
        client1
    in
    let* std_err =
      Process.check_and_read_stderr ~expect_failure:true transfer_should_fail
    in
    (match std_err =~* rex "Increase operation fees to at least (.*)tz" with
    | None ->
        Test.fail
          ~__LOC__
          "The client should fail when the mempool is full and not enough fees \
           are provided."
    | Some required ->
        Check.(
          (required = "0.001001")
            string
            ~error_msg:"The required fees are %L but expected %R")) ;

    log_step 5 "Inject an extra operation with same fees (but mempool is full)." ;
    let* (`OpHash oph5) =
      Operation.inject_transfer
        ~force:true
        ~source:Constant.bootstrap5
        ~dest:Constant.bootstrap2
        ~wait_for_injection:node1
        ~amount:1
        ~fee
        ~gas_limit
        client1
    in

    log_step 6 "Check that this extra operation is branch_delayed." ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool1 = {expected_mempool0 with branch_delayed = [oph5]} in
    Check.(
      (expected_mempool1 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step
      7
      "Check that the new operation is not propagated as part of a mempool." ;
    let* mempool = RPC.get_mempool client2 in
    Check.(
      (expected_mempool0 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 8 "Inject an extra operation with more fees for same gas." ;
    let* (`OpHash oph6) =
      Operation.inject_transfer
        ~source:Constant.bootstrap5
        ~dest:Constant.bootstrap2
        ~wait_for_injection:node1
        ~amount:1
        ~fee:(fee + 5)
        ~gas_limit
        client1
    in

    log_step
      9
      "Check that this extra operation is applied and replaces one with lower \
       fees." ;
    let* mempool = RPC.get_mempool client1 in
    let (removed_oph, kept_ops) =
      match expected_mempool1.applied with
      | [] -> assert false
      | removed :: applied -> (removed, applied)
    in
    let expected_mempool2 =
      {
        expected_mempool1 with
        applied = oph6 :: kept_ops;
        branch_delayed = removed_oph :: expected_mempool1.branch_delayed;
      }
    in
    Check.(
      (expected_mempool2 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 10 "Check that this new operation is propagated." ;
    let* mempool = RPC.get_mempool client2 in
    let expected_mempool3 =
      {
        expected_mempool2 with
        branch_delayed = [removed_oph] (* The other one was never propagated *);
      }
    in
    Check.(
      (expected_mempool3 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;

    log_step 11 "Check reclassification after flush." ;
    let* _level =
      bake_for
        ~keys:[Constant.bootstrap1.public_key_hash]
        ~empty:true
        ~protocol
        node1
        client1
    in
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool4 =
      {
        expected_mempool2 with
        (* oph6 is reconsidered before oph5 (more fees), which has same
           manager/counter *)
        applied = oph6 :: kept_ops;
        branch_delayed = [removed_oph; oph5];
      }
    in
    Check.(
      (expected_mempool4 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;
    let* _level =
      bake_for
        ~keys:[Constant.bootstrap1.public_key_hash]
        ~empty:false
        ~protocol
        node1
        client1
    in

    log_step 12 "Check mempool after flush." ;
    let* mempool = RPC.get_mempool client1 in
    let expected_mempool5 = {Mempool.empty with branch_refused = [oph5]} in
    Check.(
      (expected_mempool5 = mempool)
        Mempool.classified_typ
        ~error_msg:"mempool expected to be %L, got %R") ;
    unit
end

let check_operation_is_in_applied_mempool ops oph =
  let open JSON in
  let ops_list = as_list (ops |-> "applied") in
  let res =
    List.exists (fun e -> e |-> "hash" |> as_string = as_string oph) ops_list
  in
  if not res then
    Test.fail "Operation %s was not found in the mempool" (JSON.encode oph)

type mempool_count = {
  applied : int;
  branch_delayed : int;
  branch_refused : int;
  refused : int;
  outdated : int;
  unprocessed : int;
  total : int;
}

let count_mempool mempool =
  let open JSON in
  let applied = as_list (mempool |-> "applied") |> List.length in
  let branch_delayed = as_list (mempool |-> "branch_delayed") |> List.length in
  let branch_refused = as_list (mempool |-> "branch_refused") |> List.length in
  let refused = as_list (mempool |-> "refused") |> List.length in
  let outdated = as_list (mempool |-> "outdated") |> List.length in
  let unprocessed = as_list (mempool |-> "unprocessed") |> List.length in
  let total =
    applied + branch_delayed + branch_refused + refused + outdated + unprocessed
  in
  {
    applied;
    branch_delayed;
    branch_refused;
    refused;
    outdated;
    unprocessed;
    total;
  }

let pp_mempool_count fmt
    {
      applied;
      branch_delayed;
      branch_refused;
      refused;
      outdated;
      unprocessed;
      total;
    } =
  Format.fprintf
    fmt
    "total: %d - applied: %d, branch_delayed: %d, branch_refused: %d, refused: \
     %d, outdated: %d, unprocessed: %d"
    total
    applied
    branch_delayed
    branch_refused
    refused
    outdated
    unprocessed

(** Matches events which contain an injection request.
   For example:

  {[
    { "event": {
       "request": {
         "request": "inject",
         "operation": {
           "branch": "BL2FDpiSbzxkXpefiSRCpBHGhZ1kDpEUzWswSCABvGKr3hF6xre",
           "data": "6c0002298c03ed7d454a101eb7022bc95f7e5f41ac78940a0280bd3f00e8070000e7670f32038107a59a2b9cfefae36ea21f5aa63c00cf958f834a8d89a88068d7da1209db3c8dc6f5a0c88fb7df0fc8b910f5e100c1179e0862993fd2abadcc47eb4710ad41b68603983559b5fb68bb98499aa1800d"
         }
       },
       "status": {
         "pushed": "2021-05-03T17:16:03.826-00:00",
         "treated": 3.0033e-05,
         "completed": 0.00190934
       }
     },
     "level": "notice"
   }
  ]}
 *)
let wait_for_injection node =
  let filter json =
    match JSON.(json |-> "view" |-> "request" |> as_string_opt) with
    | Some s when s = "inject" -> Some s
    | Some _ | None -> None
  in
  let* _ = Node.wait_for node "request_completed_notice.v0" filter in
  return ()

(** Matches events which contain an flush request.
   For example:

  {[
    { "event": {
       "request": {
         "request": "flush",
         "block": "BLTv3VhCAVzMVxbXhTRqGf6M7oyxeeH2eBzdf9onbD9ULyFgo7d"
       },
       "status": {
         "pushed": "2021-04-26T16:00:50.859-00:00",
         "treated": 4.5676e-05,
         "completed": 0.01316594
       }
     },
     "level": "notice"
    }
  ]}
*)
let wait_for_flush node =
  let filter json =
    match JSON.(json |-> "view" |-> "request" |> as_string_opt) with
    | Some s when s = "flush" -> Some s
    | Some _ | None -> None
  in
  let* _ = Node.wait_for node "request_completed_notice.v0" filter in
  return ()

let operation_json ~fee ~gas_limit ~source ~destination ~counter =
  Format.sprintf
    {|{
             "kind": "transaction",
             "source": "%s",
             "fee": "%d",
             "counter": "%d",
             "gas_limit": "%d",
             "storage_limit": "0",
             "amount": "1000",
             "destination": "%s"}|}
    source
    fee
    counter
    gas_limit
    destination

let operation_json_branch ~branch operations_json =
  Format.sprintf
    {|{"branch": "%s",
           "contents": [%s]}|}
    branch
    operations_json

let forge_operation ~branch ~fee ~gas_limit ~source ~destination ~counter
    ~client =
  let op_json = operation_json ~fee ~gas_limit ~source ~destination ~counter in
  let op_json_branch = operation_json_branch ~branch op_json in
  let* op_hex =
    RPC.post_forge_operations ~data:(Ezjsonm.from_string op_json_branch) client
  in
  return (`Hex (JSON.as_string op_hex))

let inject_operation ~client (`Hex op_str_hex) (`Hex signature) =
  let signed_op = op_str_hex ^ signature in
  RPC.inject_operation ~data:(`String signed_op) client

let forge_and_inject_operation ~branch ~fee ~gas_limit ~source ~destination
    ~counter ~signer ~client =
  let* op_str_hex =
    forge_operation
      ~branch
      ~fee
      ~gas_limit
      ~source
      ~destination
      ~counter
      ~client
  in
  let signature = Operation.sign_manager_op_hex ~signer op_str_hex in
  inject_operation ~client op_str_hex signature

let forge_and_inject_n_operations ~branch ~fee ~gas_limit ~source ~destination
    ~counter ~signer ~client ~node n =
  let rec loop ((oph_list, counter) as acc) = function
    | 0 -> return acc
    | n ->
        let transfer_1 = wait_for_injection node in
        let* oph =
          forge_and_inject_operation
            ~branch
            ~fee
            ~gas_limit
            ~source
            ~destination
            ~counter
            ~signer
            ~client
        in
        let* () = transfer_1 in
        let oph_list = oph :: oph_list in
        loop (oph_list, counter + 1) (pred n)
  in
  loop ([], counter + 1) n

(** Bakes with an empty mempool to force synchronisation between nodes. *)
let bake_empty_block ?endpoint ~protocol client =
  let* mempool = Client.empty_mempool_file () in
  Client.bake_for ~protocol ?endpoint ~mempool client

(** [bake_empty_mempool_and_wait_for_flush client node] bakes for [client]
    with an empty mempool, then waits for a [flush] event on [node] (which
    will usually be the node corresponding to [client], but could be any
    node with a connection path to it). *)
let _bake_empty_block_and_wait_for_flush ?(log = false) ~protocol client node =
  let waiter = wait_for_flush node in
  let* () = bake_empty_block ~protocol client in
  if log then
    Log.info "Baked for %s with an empty mempool." (Client.name client) ;
  waiter

(* TODO: add a test than ensure that we cannot have more than 1000
   branch delayed/branch refused/refused *)

let forge_run_and_inject_n_batched_operation n ~branch ~fee ~gas_limit ~source
    ~destination ~counter ~signer ~client =
  let ops_json =
    String.concat ", "
    @@ List.map
         (fun counter ->
           operation_json ~fee ~gas_limit ~source ~destination ~counter)
         (range (counter + 1) (counter + n))
  in
  let op_json_branch = operation_json_branch ~branch ops_json in
  let* op_hex =
    RPC.post_forge_operations ~data:(Ezjsonm.from_string op_json_branch) client
  in
  let op_str_hex = JSON.as_string op_hex in
  let signature =
    Operation.sign_manager_op_bytes ~signer (Hex.to_bytes (`Hex op_str_hex))
  in
  let* _run =
    let* chain_id = RPC.get_chain_id client in
    let op_runnable =
      Format.asprintf
        {|{ "operation":
            {"branch": "%s",
             "contents": [ %s ],
             "signature": "%a" },
            "chain_id": %s }|}
        branch
        ops_json
        Tezos_crypto.Signature.pp
        signature
        (JSON.encode chain_id)
    in
    RPC.post_run_operation ~data:(Ezjsonm.from_string op_runnable) client
  in
  let (`Hex signature) = Tezos_crypto.Signature.to_hex signature in
  let signed_op = op_str_hex ^ signature in
  RPC.inject_operation ~data:(`String signed_op) client

let check_batch_operations_are_in_applied_mempool ops oph n =
  let open JSON in
  let ops_list = as_list (ops |-> "applied") in
  let res =
    List.exists
      (fun e ->
        let contents = as_list (e |-> "contents") in
        let h = as_string (e |-> "hash") in
        List.compare_length_with contents n = 0 && h = as_string oph)
      ops_list
  in
  if not res then
    Test.fail
      "Batch Operation %s was not found in the mempool or it does not contain \
       %d operations"
      (JSON.encode oph)
      n

(** This test tries to run manually forged operations before injecting them

   Scenario:

   + Node 1 activates a protocol

   + Retrieve the counter and the branch for bootstrap1

   + Forge, run and inject <n> operations in the node

   + Check that the batch is correctly injected
 *)
let run_batched_operation =
  Protocol.register_test
    ~__FILE__
    ~title:"Run batched operations before injecting them"
    ~tags:["forge"; "mempool"; "batch"; "run_operation"]
  @@ fun protocol ->
  (* Step 1 *)
  (* A Node is started and we activate the protocol and wait for the node to be synced *)
  let* node_1 = Node.init [Synchronisation_threshold 0] in
  let* client_1 = Client.init ~endpoint:(Node node_1) () in
  let* () = Client.activate_protocol ~protocol client_1 in
  Log.info "Activated protocol." ;
  let* _ = Node.wait_for_level node_1 1 in
  Log.info "Node is at level %d." 1 ;
  (* Step 2 *)
  (* Get the counter and the current branch *)
  let* counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client_1
  in
  let counter = JSON.as_int counter in
  let* branch = RPC.get_branch client_1 in
  let branch = JSON.as_string branch in
  (* Step 3 *)
  (* Forge operations, run and inject them *)
  let number_of_transactions = 3 in
  let* oph =
    forge_run_and_inject_n_batched_operation
      number_of_transactions
      ~branch
      ~fee:1000 (* Minimal fees to successfully apply the transfer *)
      ~gas_limit:1040 (* Minimal gas to successfully apply the transfer *)
      ~source:Constant.bootstrap2.public_key_hash
      ~destination:Constant.bootstrap1.public_key_hash
      ~counter
      ~signer:Constant.bootstrap2
      ~client:client_1
  in
  Log.info "Operations forged, signed, run and injected" ;
  (* Step 4 *)
  (* Check that the batch is correctly injected *)
  let* mempool_after_batch = RPC.get_mempool_pending_operations client_1 in
  check_batch_operations_are_in_applied_mempool
    mempool_after_batch
    oph
    number_of_transactions ;
  Log.info
    "%d operations are applied as a batch in the mempool"
    number_of_transactions ;
  unit

let check_if_op_is_in_mempool client ~classification oph =
  let* ops = RPC.get_mempool_pending_operations ~version:"1" client in
  let open JSON in
  let search_in ops c =
    List.exists
      (fun op -> get "hash" op |> as_string = oph)
      (ops |-> c |> as_list)
  in
  match classification with
  | Some c ->
      let res = search_in ops c in
      if not res then Test.fail "%s not found in %s" oph c else unit
  | None ->
      let res =
        List.exists
          (fun c -> search_in ops c)
          ["applied"; "branch_refused"; "branch_delayed"; "refused"; "outdated"]
      in
      if res then Test.fail "%s found in mempool" oph else unit

let get_endorsement_has_bytes ~protocol client =
  let* mempool = RPC.get_mempool_pending_operations client in
  let open JSON in
  let ops_list = as_list (mempool |-> "applied") in
  let op =
    match ops_list with
    | [op] -> op
    | _ ->
        Test.fail
          "Applied field of mempool should contain one and only one operation"
  in
  let hash = JSON.get "hash" op |> as_string in
  let shell =
    let branch = JSON.as_string (JSON.get "branch" op) in
    match Data_encoding.Json.from_string (sf {|{"branch":"%s"}|} branch) with
    | Ok b ->
        Data_encoding.Json.destruct Tezos_base.Operation.shell_header_encoding b
    | Error e -> Test.fail "Data_encoding branch from %s error %s" branch e
  in
  let contents =
    match JSON.as_list (JSON.get "contents" op) with
    | [content] -> content
    | _ -> Test.fail "Contents should countain only one element"
  in
  let slot =
    let slot_elt = JSON.get "slot" contents |> JSON.as_int in
    match Data_encoding.Json.from_string (sf {|%d|} slot_elt) with
    | Ok e ->
        Data_encoding.Json.destruct
          Tezos_protocol_alpha.Protocol.Slot_repr.encoding
          e
    | Error _ -> Test.fail "foo"
  in

  let get_signature op =
    let signature = JSON.get "signature" op |> JSON.as_string in
    match Data_encoding.Json.from_string (sf {|"%s"|} signature) with
    | Ok s -> Data_encoding.Json.destruct Tezos_crypto.Signature.encoding s
    | Error e ->
        Test.fail
          "Data_encoding signature from string %s : error %s"
          signature
          e
  in
  let wrapped_bytes =
    match protocol with
    | Protocol.Ithaca | Protocol.Alpha ->
        let signature = get_signature op in
        let kind = JSON.get "kind" contents |> JSON.as_string in
        if not (kind = "endorsement") then
          Test.fail "Operation kind should be endorsement, got %s" kind ;
        let level =
          Tezos_protocol_alpha.Protocol.Raw_level_repr.of_int32_exn
            (Int32.of_int (JSON.get "level" contents |> JSON.as_int))
        in
        let round =
          let round = JSON.get "round" contents |> JSON.as_int in
          match
            Tezos_protocol_alpha.Protocol.Round_repr.of_int32
              (Int32.of_int round)
          with
          | Ok round -> round
          | Error _ ->
              Test.fail
                "Could not create a round with %d (from the mempool result) "
                round
        in
        let block_payload_hash =
          let block_payload_hash =
            JSON.get "block_payload_hash" contents |> JSON.as_string
          in
          Tezos_protocol_alpha.Protocol.Block_payload_hash.of_b58check_exn
            block_payload_hash
        in
        let wrapped =
          Tezos_protocol_alpha.Protocol.Operation_repr.
            {
              shell;
              protocol_data =
                Operation_data
                  {
                    contents =
                      Single
                        (Endorsement {slot; round; level; block_payload_hash});
                    signature = Some signature;
                  };
            }
        in
        Data_encoding.Binary.to_bytes_exn
          Tezos_protocol_alpha.Protocol.Operation_repr.encoding
          wrapped
    | Protocol.Hangzhou ->
        let endorsement = JSON.get "endorsement" contents in
        let signature = get_signature endorsement in
        let level =
          Tezos_protocol_010_PtGRANAD.Protocol.Raw_level_repr.of_int32_exn
            (Int32.of_int
               (JSON.get "operations" endorsement
               |> JSON.get "level" |> JSON.as_int))
        in
        let wrapped =
          Tezos_protocol_010_PtGRANAD.Protocol.Operation_repr.
            {
              shell;
              protocol_data =
                Operation_data
                  {
                    contents =
                      Single
                        (Endorsement_with_slot
                           {
                             endorsement =
                               {
                                 shell;
                                 protocol_data =
                                   {
                                     contents =
                                       Single
                                         (Tezos_protocol_010_PtGRANAD.Protocol
                                          .Operation_repr
                                          .Endorsement
                                            {level});
                                     signature = Some signature;
                                   };
                               };
                             slot =
                               Tezos_protocol_alpha.Protocol.Slot_repr.to_int
                                 slot;
                           });
                    signature = None;
                  };
            }
        in
        Data_encoding.Binary.to_bytes_exn
          Tezos_protocol_010_PtGRANAD.Protocol.Operation_repr.encoding
          wrapped
  in
  Lwt.return (wrapped_bytes, hash)

let wait_for_synch node =
  let filter json =
    match JSON.(json |-> "view" |-> "request" |> as_string_opt) with
    | Some s when s = "notify" -> Some s
    | Some _ | None -> None
  in
  let* _ = Node.wait_for node "request_completed_debug.v0" filter in
  return ()

let mempool_synchronisation client node =
  let waiter = wait_for_synch node in
  let* _ = RPC.mempool_request_operations client in
  waiter

(** This test checks that future endorsement are still propagated when
    the head is  incremented *)
let propagation_future_endorsement =
  let step1_msg =
    "Step 1: 3 nodes are initialised, chain connected and the protocol is \
     activated."
  in
  let step2_msg = "Step 2: disconnect the nodes" in
  let step3_msg = "Step 3: bake one block on node_1" in
  let step4_msg = "Step 4: Endorsement on node_1 injected" in
  let step5_msg =
    "Step 5: recover hash endorsement and bytes representing the endorsement"
  in
  let step6_msg =
    "Step 6: ban the endorsement on node_1 to ensure it will not be propagated \
     from this node"
  in
  let step7_msg = "Step 7: Endorsement has been inject on node_2" in
  let step8_msg =
    "Step 8: Reconnect node_2 and node_3 and synchronise their mempool"
  in
  let step9_msg =
    "Step 9: ensure that endorsement is in node_2 mempool and classified as \
     branch_delayed"
  in
  let step10_msg =
    "Step 10: ensure that endorsement is not in node_3 mempool"
  in
  let step11_msg = "Step 11: Reconnect node_1 and node_2, new head on node_2" in
  let step12_msg =
    "Step 12: Synchronise mempool on node_2 and check that endorsement is now \
     applied"
  in
  let step13_msg =
    "Step 13: Synchronise mempool on node_3 and check that endorsement has \
     been propagated"
  in
  Protocol.register_test
    ~__FILE__
    ~title:"Ensure that future endorsement are propagated"
    ~tags:["endorsement"; "mempool"; "branch_delayed"]
  @@ fun protocol ->
  let* node_1 = Node.init [Synchronisation_threshold 0; Private_mode]
  and* node_2 =
    Node.init
      ~event_sections_levels:[("prevalidator", `Debug)]
      [Synchronisation_threshold 0; Private_mode]
  and* node_3 =
    Node.init
      ~event_sections_levels:[("prevalidator", `Debug)]
      [Synchronisation_threshold 0; Private_mode]
  in
  let* client_1 = Client.init ~endpoint:(Node node_1) ()
  and* client_2 = Client.init ~endpoint:(Node node_2) ()
  and* client_3 = Client.init ~endpoint:(Node node_3) () in
  let* () = Client.Admin.trust_address client_1 ~peer:node_2
  and* () = Client.Admin.trust_address client_2 ~peer:node_1
  and* () = Client.Admin.trust_address client_2 ~peer:node_3
  and* () = Client.Admin.trust_address client_3 ~peer:node_2 in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2
  and* () = Client.Admin.connect_address client_2 ~peer:node_3 in
  let* () = Client.activate_protocol ~protocol client_1 in
  let* _ = Node.wait_for_level node_1 1
  and* _ = Node.wait_for_level node_2 1
  and* _ = Node.wait_for_level node_3 1 in
  Log.info "%s" step1_msg ;
  let* node_1_id = Node.wait_for_identity node_1
  and* node_2_id = Node.wait_for_identity node_2
  and* node_3_id = Node.wait_for_identity node_3 in
  let* () = Client.Admin.kick_peer client_1 ~peer:node_2_id
  and* () = Client.Admin.kick_peer client_2 ~peer:node_1_id
  and* () = Client.Admin.kick_peer client_2 ~peer:node_3_id
  and* () = Client.Admin.kick_peer client_3 ~peer:node_2_id in
  Log.info "%s" step2_msg ;
  let* () = Node_event_level.bake_wait_log node_1 client_1 in
  Log.info "%s" step3_msg ;
  let endorser_waiter = wait_for_injection node_1 in
  let* () = Client.endorse_for client_1 ~force:true ~protocol in
  let* () = endorser_waiter in
  Log.info "%s" step4_msg ;
  let* (bytes, hash) = get_endorsement_has_bytes ~protocol client_1 in
  Log.info "%s" step5_msg ;
  let* _ = RPC.mempool_ban_operation ~data:(`String hash) client_1 in
  Log.info "%s" step6_msg ;
  let (`Hex bytes) = Hex.of_bytes bytes in
  let injection_waiter = wait_for_injection node_2 in
  let* _ = RPC.private_inject_operation ~data:(`String bytes) client_2 in
  let* () = injection_waiter in
  Log.info "%s" step7_msg ;
  let* () = Client.Admin.trust_address client_2 ~peer:node_3
  and* () = Client.Admin.trust_address client_3 ~peer:node_2 in
  let* () = Client.Admin.connect_address client_2 ~peer:node_3 in
  let* _ = mempool_synchronisation client_3 node_3 in
  Log.info "%s" step8_msg ;
  let* _ =
    check_if_op_is_in_mempool
      client_2
      ~classification:(Some "branch_delayed")
      hash
  in
  Log.info "%s" step9_msg ;
  let* _ = check_if_op_is_in_mempool client_3 ~classification:None hash in
  Log.info "%s" step10_msg ;
  let* () = Client.Admin.trust_address client_1 ~peer:node_2
  and* () = Client.Admin.trust_address client_2 ~peer:node_1 in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2 in
  Log.info "%s" step11_msg ;
  let* _ = mempool_synchronisation client_2 node_2 in
  let* _ =
    check_if_op_is_in_mempool client_2 ~classification:(Some "applied") hash
  in
  Log.info "%s" step12_msg ;
  let* _ = mempool_synchronisation client_3 node_3 in
  let* _ =
    check_if_op_is_in_mempool client_3 ~classification:(Some "applied") hash
  in
  Log.info "%s" step13_msg ;
  unit

let check_empty_operation__ddb ddb =
  let open JSON in
  let op_db_length = as_int (ddb |-> "operation_db" |-> "table_length") in
  if op_db_length > 0 then
    Test.fail
      "Operation Ddb should be empty, contains : %d elements"
      op_db_length

(** This test checks that pre-filtered operations are cleaned from the ddb

   Scenario:

   + 3 Nodes are chained connected and activate a protocol

   + Get the counter and the current branch

   + Forge operation, inject it and check injection on node_1
     This operation is pre-filtered on node_2

   + Bake 1 block

   + Get client_2 ddb and check that it contains no operation
*)
let forge_pre_filtered_operation =
  Protocol.register_test
    ~__FILE__
    ~title:"Forge pre-filtered operation and check mempool"
    ~tags:["forge"; "mempool"; "pre_filtered"]
  @@ fun protocol ->
  (* Step 1 *)
  (* Two Nodes are started and we activate the protocol and wait the nodes to be synced *)
  let* node_1 = Node.init [Synchronisation_threshold 0; Private_mode]
  and* node_2 = Node.init [Synchronisation_threshold 0; Private_mode] in
  let* client_1 = Client.init ~endpoint:(Node node_1) ()
  and* client_2 = Client.init ~endpoint:(Node node_2) () in
  let* () = Client.Admin.trust_address client_1 ~peer:node_2
  and* () = Client.Admin.trust_address client_2 ~peer:node_1 in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2 in
  let* () = Client.activate_protocol ~protocol client_1 in
  Log.info "Activated protocol." ;
  let* _ = Node.wait_for_level node_1 1 and* _ = Node.wait_for_level node_2 1 in
  Log.info "All nodes are at level %d." 1 ;
  (* Step 2 *)
  (* Get the counter and the current branch *)
  let* base_counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client_1
  in
  let counter = JSON.as_int base_counter in
  let* branch = RPC.get_branch client_1 in
  (* Step 3 *)
  (* Forge operation, inject it and check injection *)
  let* _op =
    forge_and_inject_operation
      ~branch:(JSON.as_string branch)
      ~fee:1
      ~gas_limit:1040000
      ~source:Constant.bootstrap1.public_key_hash
      ~destination:Constant.bootstrap2.public_key_hash
      ~counter:(counter + 1)
      ~signer:Constant.bootstrap1
      ~client:client_1
  in
  Log.info "Op forged and injected" ;
  (* Step 4 *)
  (* Bake 1 block *)
  let* () = Client.bake_for client_2 in
  (* Step 5 *)
  (* Get client_2 ddb and check that it contains no operation *)
  let* ddb2 = RPC.get_ddb client_2 in
  check_empty_operation__ddb ddb2 ;
  Log.info "Operation Ddb of client_2 does not contain any operation" ;
  unit

(** Matches events which contain a failed fetch.
   For example:

  {[
    {  "event": {
           "operation_not_fetched": "onuvmuCS5NqtJG65BJWqH44bzwiXLw4tVpfNqRQvkgorv5LoejA"
       },
       "level": "debug"
    }
  ]}
*)
let wait_for_failed_fetch node =
  Node.wait_for node "operation_not_fetched.v0" (fun _ -> Some ())

let set_config_operations_timeout node timeout =
  let chain_validator_config =
    let open JSON in
    Node.Config_file.read node |-> "shell" |-> "chain_validator"
  in
  let updated_shell_config =
    JSON.annotate
      ~origin:"shell"
      (Ezjsonm.from_string
         (Format.asprintf
            {|{"prevalidator": { "operations_request_timeout" : %f },
            "peer_validator" : { "new_head_request_timeout" : 5 },
            "chain_validator": %s}|}
            timeout
            (JSON.encode chain_validator_config)))
  in
  Node.Config_file.update node (JSON.put ("shell", updated_shell_config))

(** This test checks that failed fetched operations can be refetched successfully

   Scenario:

   + initialise two nodes and activate the protocol. The second node is initialise with specific configuration

   + Get the counter and the current branch

   + Forge operation and inject it in node_1, checks that the fetch fail in node_2

   + Ensure that the injected operation is in node_1 mempool

   + Ensure that the mempool of node_2 is empty

   + Inject the previous operation in node_2

   + Ensure that the operation is injected in node_2 mempool
*)
let refetch_failed_operation =
  Protocol.register_test
    ~__FILE__
    ~title:"Fetch failed operation"
    ~tags:["fetch"; "mempool"]
  @@ fun protocol ->
  (* Step 1 *)
  (* initialise both nodes and activate protocol
     node_2 uses specific configuration to force timeout in fetching *)
  let* node_1 = Node.init [Synchronisation_threshold 0; Private_mode] in
  let node_2 = Node.create [Synchronisation_threshold 0; Private_mode] in
  let* () = Node.config_init node_2 [] in
  (* Set a low operations_request_timeout to force timeout at fetching *)
  set_config_operations_timeout node_2 0.00001 ;
  (* Run the node with the new config.
     event_level is set to debug to catch fetching event at this level *)
  let* () =
    Node.run ~event_sections_levels:[("prevalidator", `Debug)] node_2 []
  in
  let* client_1 = Client.init ~endpoint:(Node node_1) ()
  and* client_2 = Client.init ~endpoint:(Node node_2) () in
  let* () = Client.Admin.trust_address client_1 ~peer:node_2
  and* () = Client.Admin.trust_address client_2 ~peer:node_1 in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2 in
  let* () = Client.activate_protocol ~protocol client_1 in
  Log.info "Activated protocol." ;
  let* _ = Node.wait_for_level node_1 1 and* _ = Node.wait_for_level node_2 1 in
  Log.info "All nodes are at level %d." 1 ;
  (* Step 2 *)
  (* get counter and branches *)
  let* counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client_1
  in
  let counter = JSON.as_int counter in
  let* branch = RPC.get_branch client_1 in
  let branch = JSON.as_string branch in
  (* Step 3 *)
  (* Forge operation and inject it in node_1, checks that the fetch fail in node_2 *)
  let* op_str_hex =
    forge_operation
      ~branch
      ~fee:1000 (* Minimal fees to successfully apply the transfer *)
      ~gas_limit:1040 (* Minimal gas to successfully apply the transfer *)
      ~source:Constant.bootstrap1.public_key_hash
      ~destination:Constant.bootstrap2.public_key_hash
      ~counter:(counter + 1)
      ~client:client_1
  in
  let signature =
    Operation.sign_manager_op_hex ~signer:Constant.bootstrap1 op_str_hex
  in
  let failed_fetching_waiter = wait_for_failed_fetch node_2 in
  let* oph = inject_operation ~client:client_1 op_str_hex signature in
  let* () = failed_fetching_waiter in
  (* Step 4 *)
  (* Ensure that the injected operation is in node_1 mempool *)
  let* mempool_node_1 = RPC.get_mempool_pending_operations client_1 in
  check_operation_is_in_applied_mempool mempool_node_1 oph ;
  (* Step 5 *)
  (* Ensure that the mempool of node_2 is empty *)
  let* mempool_count_after_failed_fetch =
    RPC.get_mempool_pending_operations client_2
  in
  let count_failed_fetching = count_mempool mempool_count_after_failed_fetch in
  if count_failed_fetching.total <> 0 then
    Test.fail "The mempool of node 2 should be empty" ;
  (* Step 6 *)
  (* Inject the previous operation in node_2 *)
  let* oph2 = inject_operation ~client:client_2 op_str_hex signature in
  if oph <> oph2 then
    Test.fail
      "The operation injected in node_2 should be the same as the one injected \
       in node_1" ;
  (* Step 7 *)
  (* Ensure that the operation is injected in node_2 mempool *)
  let* mempool_inject_on_node_2 = RPC.get_mempool_pending_operations client_2 in
  check_operation_is_in_applied_mempool mempool_inject_on_node_2 oph ;
  unit

let check_op_removed client op =
  let* pending_ops = RPC.get_mempool_pending_operations client in
  let open JSON in
  let ops_list = pending_ops |-> "applied" |> as_list in
  let res = List.exists (fun e -> e |-> "hash" |> as_string = op) ops_list in
  if res then Test.fail "%s found after removal" op ;
  unit

(** Bakes with an empty mempool to force synchronisation between nodes. *)
let bake_empty_block ?endpoint ?protocol client =
  let* mempool = Client.empty_mempool_file () in
  Client.bake_for ?protocol ?endpoint ~mempool ~ignore_node_mempool:true client

(** [bake_empty_block_and_wait_for_flush client node] bakes for [client]
    with an empty mempool, then waits for a [flush] event on [node] (which
    will usually be the node corresponding to [client], but could be any
    node with a connection path to it). *)
let bake_empty_block_and_wait_for_flush ~protocol ?(log = false) client node =
  let waiter = wait_for_flush node in
  let* () = bake_empty_block ~protocol client in
  if log then
    Log.info "Baked for %s with an empty mempool." (Client.name client) ;
  waiter

(* for functions [transfer_and_wait_for_injection], [wait_for_arrival],
   and [get_applied_operation_hash_list] *)
open Node_event_level

(** Injects a transfer operation from [client] and waits for an operation
    to arrive from the network on [node] (which should not be the node
    associated to [client], but there should be a connection path between
    them).
    Note: the event for operation arrival has level "debug", so [node]
    needs to have event level set to "debug" for it to exist. Otherwise,
    this function will block. *)
let transfer_and_wait_for_arrival node client amount_int giver_key receiver_key
    =
  let wait_for = wait_for_arrival node in
  let* () =
    Client.transfer
      ~amount:(Tez.of_int amount_int)
      ~giver:Account.(giver_key.alias)
      ~receiver:Account.(receiver_key.alias)
      client
  in
  let* () = wait_for in
  unit

(** Gets the list of hashes of the mempool's applied operations,
    displays it, and returns it. *)
let get_and_log_applied client =
  let* ophs = get_applied_operation_hash_list client in
  Log.info "Applied operations in mempool:" ;
  List.iter (Log.info "- %s") ophs ;
  return ophs

(** Boolean indicating whether two lists of operation hashes (strings)
   are equal (returns [false] if they have different lengths, instead
   of raising [invalid_arg] as using [List.for_all2] directly would
   do). We use a naive way to check both lists are equal because
   1. performances for small lists does not matter and 2. the mempool
   does not specify how operations previously applied will be applied
   again after banning one operation. *)
let oph_list_equal l1 l2 =
  Int.equal (List.compare_lengths l1 l2) 0
  && List.for_all (fun x -> List.mem x l2) l1
  && List.for_all (fun x -> List.mem x l1) l2

(** Gets the list of hashes of the mempool's applied operations,
    and asserts that it is equal to the given list [expected_ophs]. *)
let check_applied_ophs_is client expected_ophs =
  let* ophs = get_applied_operation_hash_list client in
  if oph_list_equal ophs expected_ophs then (
    Log.info "Checking applied operations in mempool:" ;
    List.iter (Log.info "- %s") ophs ;
    unit)
  else (
    Log.info "Expected applied operations:" ;
    List.iter (Log.info "- %s") expected_ophs ;
    Log.info "Actual applied operations:" ;
    List.iter (Log.info "- %s") ophs ;
    Test.fail
      "Wrong list of applied operations in mempool (use --info to see expected \
       and actual lists).")

(** Test.

    Aim: check that, when banning an operation that was applied in the
    mempool, the other applied operations are correctly reapplied (in
    the same order).

    Scenario:
    - Step 1: Start two nodes, connect them, activate the protocol.
    - Step 2: Inject five operations (transfers from five different sources,
      injected by both nodes in alternance).
    - Step 3: Ban one of these operations from node_1 (arbitrarily, the third
      in the list of applied operations in the mempool of node_1).
    - Step 4: Check that applied operations in node_1 are still applied

    Note: the chosen operations are commutative, so that none of them
    becomes branch_delayed instead of applied when one of them is banned.
*)
let ban_operation_and_check_applied =
  Protocol.register_test
    ~__FILE__
    ~title:"mempool ban operation and check applied"
    ~tags:["mempool"; "node"]
  @@ fun protocol ->
  Log.info "Step 1: Start two nodes, connect them, activate the protocol." ;
  let* node_1 =
    Node.init
      ~event_sections_levels:
        [("prevalidator", `Debug)] (* to witness operation arrival events *)
      [Synchronisation_threshold 0; Connections 1]
  and* node_2 = Node.init [Synchronisation_threshold 0; Connections 1] in
  let* client_1 = Client.init ~endpoint:Client.(Node node_1) ()
  and* client_2 = Client.init ~endpoint:Client.(Node node_2) () in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2 in
  let* () = Client.activate_protocol ~protocol client_1 in
  let* _ = Node.wait_for_level node_1 1 and* _ = Node.wait_for_level node_2 1 in
  Log.info "Both nodes are at level 1." ;
  Log.info
    "Step 2: Inject five operations (transfers from five different sources, \
     injected by both nodes in alternance)." ;
  let* () =
    transfer_and_wait_for_injection
      node_1
      client_1
      1
      Constant.bootstrap1
      Constant.bootstrap5
  in
  let* () =
    transfer_and_wait_for_arrival
      node_1
      client_2
      2
      Constant.bootstrap2
      Constant.bootstrap5
  in
  let* () =
    transfer_and_wait_for_injection
      node_1
      client_1
      3
      Constant.bootstrap3
      Constant.bootstrap5
  in
  let* () =
    transfer_and_wait_for_arrival
      node_1
      client_2
      4
      Constant.bootstrap4
      Constant.bootstrap5
  in
  let* () =
    transfer_and_wait_for_injection
      node_1
      client_1
      5
      Constant.bootstrap5
      Constant.bootstrap1
  in
  Log.info
    "Step 3: Ban one of these operations from node_1 (arbitrarily, the third \
     in the list of applied operations in the mempool of node_1)." ;
  let* applied_ophs = get_and_log_applied client_1 in
  if not (Int.equal (List.compare_length_with applied_ophs 5) 0) then
    (* This could theoretically happen: we wait for each transfer to
       be present in the mempool as "pending", but not to be classified
       as "applied". In practice, this does not seem to be a problem. *)
    Test.fail
      "Found only %d applied operations in node_1, expected 5."
      (List.length applied_ophs) ;
  let oph_to_ban = List.nth applied_ophs 2 in
  Log.info "Operation to ban: %s" oph_to_ban ;
  let* _ = RPC.mempool_ban_operation ~data:(`String oph_to_ban) client_1 in
  Log.info "Operation %s is now banned." oph_to_ban ;
  Log.info "Step 4: Check that applied operations in node_1 are still applied." ;
  let expected_reapplied_ophs =
    List.filter (fun oph -> not (String.equal oph_to_ban oph)) applied_ophs
  in
  let* () = check_applied_ophs_is client_1 expected_reapplied_ophs in
  unit

(** Waits for an event in [node] signaling the arrival in the mempool
    of an operation of hash [ophash].
    Note: this event has level "debug", so the node needs to have event
    level set to "debug" for such an event to exist. *)
let wait_for_arrival_of_ophash ophash node =
  let filter json =
    let open JSON in
    match
      ( json |-> "view" |-> "request" |> as_string_opt,
        json |-> "view" |-> "operation_hash" |> as_string_opt )
    with
    | (Some "arrived", Some s) when String.equal s ophash ->
        Log.info "Witnessed arrival of operation %s." ophash ;
        Some ()
    | _ -> None
  in
  Node.wait_for node "request_completed_debug.v0" filter

(** [set_filter_no_fee_requirement client] sets all fields [minimal_*]
    to 0 in the filter configuration of [client]'s mempool. *)
let set_filter_no_fee_requirement =
  Revamped.set_filter
    {|{ "minimal_fees": "0", "minimal_nanotez_per_gas_unit": [ "0", "1" ], "minimal_nanotez_per_byte": [ "0", "1" ] }|}

(** Checks that arguments [applied] and [refused] are the number of operations
    in the mempool of [client] with the corresponding classification,
    that both sets of operations are disjoint, and that there is no
    [branch_delayed], [branch_refused], or [unprocessed] operation.
    If [log] is [true], also logs the hash and fee of all applied
    and refused operations. *)
let check_mempool_ops ?(log = false) client ~applied ~refused =
  let name = Client.name client in
  let log_op =
    if log then fun classification hash fee ->
      Log.info
        ~color:Log.Color.FG.yellow
        ~prefix:(name ^ ", " ^ classification)
        "%s (fee: %d)"
        hash
        fee
    else fun _ _ _ -> ()
  in
  let* ops = RPC.get_mempool_pending_operations client in
  let open JSON in
  (* get (and log) applied operations *)
  let applied_ophs =
    let classification = "applied" in
    List.map
      (fun op ->
        let oph = get_hash op in
        log_op classification oph (op |-> "contents" |=> 0 |-> "fee" |> as_int) ;
        oph)
      (ops |-> classification |> as_list)
  in
  (* get (and log) refused operations *)
  let refused_ophs =
    let classification = "refused" in
    List.map
      (fun op ->
        match op |> as_list with
        | [oph; descr] ->
            let oph = as_string oph in
            log_op
              classification
              oph
              (descr |-> "contents" |=> 0 |-> "fee" |> as_int) ;
            oph
        | _ ->
            Test.fail
              "Unexpected JSON structure for refused operation in %s's mempool."
              name)
      (ops |-> classification |> as_list)
  in
  (* various checks about applied and refused operations *)
  Check.(
    (List.compare_length_with applied_ophs applied = 0)
      int
      ~error_msg:(name ^ ": found %L applied operation(s), expected %R.")) ;
  Check.(
    (List.compare_length_with refused_ophs refused = 0)
      int
      ~error_msg:(name ^ ": found %L refused operation(s), expected %R.")) ;
  List.iter
    (fun oph ->
      if List.mem oph refused_ophs then
        Test.fail "%s: operation %s is both applied and refused" name oph)
    applied_ophs ;
  (* check that other classifications are empty *)
  List.iter
    (fun classification ->
      match ops |-> classification |> as_list with
      | [] -> ()
      | _ ->
          Test.fail
            "%s: unexpectedly found %s operation(s): %s"
            name
            classification
            (ops |-> classification |> encode))
    ["outdated"; "branch_refused"; "branch_delayed"; "unprocessed"] ;
  unit

(** Waits for [node] to receive a notification from a peer of a mempool
    containing exactly [n_ops] valid operations. *)
let wait_for_notify_n_valid_ops node n_ops =
  Node.wait_for node "node_prevalidator.v0" (fun event ->
      let open JSON in
      let view = event |=> 1 |-> "request_view" in
      match view |-> "request" |> as_string_opt with
      | Some "notify" ->
          let valid_ophs = view |-> "mempool" |-> "known_valid" |> as_list in
          if Int.equal (List.compare_length_with valid_ophs n_ops) 0 then
            Some ()
          else None
      | _ -> None)

(** Checks that the last block of [client] contains exactly
    [n_manager_ops] manager operations (which includes the transfer
    operations). *)
let check_n_manager_ops_in_block ?(log = false) client n_manager_ops =
  let* baked_ops = RPC.get_operations client in
  let baked_manager_ops = JSON.(baked_ops |=> 3 |> as_list) in
  Check.(
    (List.compare_length_with baked_manager_ops n_manager_ops = 0)
      int
      ~error_msg:
        "The baked block contains %L manager operation(s), expected %R.") ;
  if log then
    Log.info "The baked block contains %d manager operation(s)." n_manager_ops ;
  unit

let iter2_p f l1 l2 = Lwt.join (List.map2 f l1 l2)

(** Test.

    Aim: test that a refused operation is not reclassified even though
    it would now be valid.

    Scenario:
    - Step 1: Start two nodes, connect them, and activate the protocol.
    - Step 2: In [node2]'s mempool filter configuration, set all fields
      [minimal_*] to 0, so that [node2] accepts operations with any fee.
    - Step 3: Inject two operations (transfers) in [node2] with respective
      fees 1000 and 10 mutez. Check that both operations are [applied] in
      [node2]'s mempool.
    - Step 4: Bake with an empty mempool for [node1] to force synchronization
      with [node2]. Check that the mempool of [node1] has one applied and one
      refused operation. Indeed, [node1] has the default filter config with
      [minimal_fees] at 100 mutez.
    - Step 5: In [node1]'s mempool filter configuration, set all fields
      [minimal_*] to 0. Inject a new operation with fee 5 in [node2], then
      bake with an empty mempool. Check that [node1] contains two applied
      operations (the ones with fee 1000 and 5) and one refused operation.
      Indeed, the operation with fee 10 would now be valid, but it has already
      been refused so it must not be revalidated.
    - Step 6: Bake for [node1] (normally, i.e. without enforcing a given
      mempool). Check that the baked block contains exactly one manager
      operation (the category containing transfer operations). Indeed, the
      filter used to determine which operations are included in the block does
      not share its configuration with the mempool's filter, so only the
      operation of fee 1000 is included. Check that [node1] contains one
      applied operation (fee 5) and one refused operation (fee 10), and that
      [node2] contains two applied operations. *)
let test_do_not_reclassify =
  Protocol.register_test
    ~__FILE__
    ~title:"mempool do not reclassify"
    ~tags:["mempool"; "node"; "filter"; "refused"; "applied"]
  @@ fun protocol ->
  let step_color = Log.Color.BG.blue in
  Log.info
    ~color:step_color
    "Step 1: Start two nodes, connect them, and activate the protocol." ;
  let* node1 =
    Node.init
      ~event_sections_levels:[("prevalidator", `Debug)]
      [Synchronisation_threshold 0; Connections 1]
  and* node2 = Node.init [Synchronisation_threshold 0; Connections 1] in
  let* client1 = Client.init ~endpoint:Client.(Node node1) ()
  and* client2 = Client.init ~endpoint:Client.(Node node2) () in
  let* () = Client.Admin.connect_address client1 ~peer:node2
  and* () = Client.activate_protocol ~protocol client1 in
  let proto_activation_level = 1 in
  let* _ = Node.wait_for_level node1 proto_activation_level
  and* _ = Node.wait_for_level node2 proto_activation_level in
  Log.info "Both nodes are at level %d." proto_activation_level ;
  Log.info
    ~color:step_color
    "Step 2: In [node2]'s mempool filter configuration, set all fields \
     [minimal_*] to 0, so that [node2] accepts operations with any fee." ;
  let* _ = set_filter_no_fee_requirement client2 in
  Log.info "Node2 filter config: all [minimal_*] set to 0." ;
  Log.info
    ~color:step_color
    "Step 3: Inject two operations (transfers) in [node2] with respective fees \
     1000 and 10 mutez. Check that both operations are [applied] in [node2]'s \
     mempool." ;
  let waiter_arrival_node1 = wait_for_arrival node1 in
  let inject_transfer from_key ~fee =
    let waiter = wait_for_injection node2 in
    let _ =
      Client.transfer
        ~wait:"0"
        ~amount:(Tez.of_int 1)
        ~giver:from_key.Account.alias
        ~receiver:Constant.bootstrap5.alias
        ~fee:(Tez.of_mutez_int fee)
        client2
    in
    waiter
  in
  let bootstraps = Constant.[bootstrap1; bootstrap2] in
  let fees = [1000; 10] in
  let* () = iter2_p (fun key fee -> inject_transfer key ~fee) bootstraps fees in
  Log.info
    "Injected transfers in node2 with fees: %s."
    (String.concat "; " (List.map Int.to_string fees)) ;
  let* () = check_mempool_ops ~log:true client2 ~applied:2 ~refused:0 in
  Log.info
    ~color:step_color
    "Step 4: Bake with an empty mempool for [node1] to force synchronization \
     with [node2]. Check that the mempool of [node1] has one applied and one \
     refused operation. Indeed, [node1] has the default filter config with \
     [minimal_fees] at 100 mutez." ;
  let* () =
    bake_empty_block_and_wait_for_flush ~protocol ~log:true client1 node1
  in
  let* () = waiter_arrival_node1 in
  let* () = check_mempool_ops ~log:true client1 ~applied:1 ~refused:1 in
  Log.info
    ~color:step_color
    "Step 5: In [node1]'s mempool filter configuration, set all fields \
     [minimal_*] to 0. Inject a new operation with fee 5 in [node2], then bake \
     with an empty mempool. Check that [node1] contains two applied operations \
     (the ones with fee 1000 and 5) and one refused operation. Indeed, the \
     operation with fee 10 would now be valid, but it has already been refused \
     so it must not be revalidated." ;
  let* _ = set_filter_no_fee_requirement client1 in
  let* () = inject_transfer Constant.bootstrap3 ~fee:5 in
  let waiter_notify_3_valid_ops = wait_for_notify_n_valid_ops node1 3 in
  let* () =
    bake_empty_block_and_wait_for_flush ~protocol ~log:true client1 node1
  in
  (* Wait for [node1] to receive a mempool containing 3 operations (the
     number of [applied] operations in [node2]), among which will figure
     the operation with fee 10 that has already been [refused] in [node1]. *)
  let* () = waiter_notify_3_valid_ops in
  let* () = check_mempool_ops ~log:true client1 ~applied:2 ~refused:1 in
  Log.info
    ~color:step_color
    "Step 6: Bake for [node1] (normally, i.e. without enforcing a given \
     mempool). Check that the baked block contains exactly one manager \
     operation (the category containing transfer operations). Indeed, the \
     filter used to determine which operations are included in the block does \
     not share its configuration with the mempool's filter, so only the \
     operation of fee 1000 is included. Check that [node1] contains one \
     applied operation (fee 5) and one refused operation (fee 10), and that \
     [node2] contains 2 applied operations." ;
  let* () = bake_wait_log ~protocol node1 client1 in
  let* () = check_n_manager_ops_in_block ~log:true client1 1 in
  let* () = check_mempool_ops ~log:true client1 ~applied:1 ~refused:1 in
  let* () = check_mempool_ops ~log:true client2 ~applied:2 ~refused:0 in
  unit

let get_refused_operation_hash_list_v0 mempool =
  List.map
    (fun op -> JSON.(op |=> 0 |> as_string))
    JSON.(mempool |-> "refused" |> as_list)

let get_refused_operation_hash_list_v1 mempool =
  List.map get_hash JSON.(mempool |-> "refused" |> as_list)

(** This test tries to check the format of different versions of
    pending_operations RPC.

   Scenario:

   + Node 1 activates a protocol

   + Inject operation on node_1 with low fees

   + Bake empty block to classify operation as refused

   + Get the hash of the operation using different versions of pending_operation RPC
     and check that they are the same *)
let test_pending_operation_version =
  Protocol.register_test
    ~__FILE__
    ~title:"pending operation version"
    ~tags:["mempool"; "pending_operations"; "version"]
  @@ fun protocol ->
  let open Lwt in
  (* Step 1 *)
  (* Initialise one node *)
  let* node_1 =
    Node.init
      ~event_sections_levels:[("prevalidator", `Debug)]
      [Synchronisation_threshold 0; Private_mode]
  in
  let* client_1 = Client.init ~endpoint:(Node node_1) () in
  let* () = Client.activate_protocol ~protocol client_1 in
  Log.info "Activated protocol." ;
  let* _ = Node.wait_for_level node_1 1 in
  (* Step 2 *)
  (* Inject refused operation *)
  let* branch = RPC.get_branch client_1 >|= JSON.as_string in
  let* _ =
    forge_and_inject_operation
      ~branch
      ~fee:10
      ~gas_limit:1040
      ~source:Constant.bootstrap1.public_key_hash
      ~destination:Constant.bootstrap2.public_key_hash
      ~counter:1
      ~signer:Constant.bootstrap1
      ~client:client_1
  in
  (* Step 3 *)
  (* Bake empty block to force operation to be classify as refused *)
  let dummy_baking = wait_for_flush node_1 in
  let* () = bake_empty_block ~protocol client_1 in
  let* () = dummy_baking in
  (* Step 4 *)
  (* Get pending operations using different version of the RPC and check  *)
  let* mempool_v0 = RPC.get_mempool_pending_operations client_1 in
  let* mempool_v1 = RPC.get_mempool_pending_operations ~version:"1" client_1 in
  let ophs_refused_v0 = get_refused_operation_hash_list_v0 mempool_v0 in
  let ophs_refused_v1 = get_refused_operation_hash_list_v1 mempool_v1 in
  try
    if not (List.for_all2 String.equal ophs_refused_v0 ophs_refused_v1) then
      Format.kasprintf
        (Test.fail "%s")
        "Refused operation hash list should have the same elements. Got : %a \
         (version 1) and %a (version 2)"
        (Format.pp_print_list (fun ppf oph -> Format.fprintf ppf "%s" oph))
        ophs_refused_v0
        (Format.pp_print_list (fun ppf oph -> Format.fprintf ppf "%s" oph))
        ophs_refused_v1 ;
    unit
  with Invalid_argument _ ->
    Format.kasprintf
      (Test.fail "%s")
      "Refused operation hash list should have the same number of elements. \
       Got : %d (version 1) and %d (version 2)"
      (List.length ophs_refused_v0)
      (List.length ophs_refused_v1)

(** This test tries to check that invalid operation can be injected on a local
    node with private/injection/operation RPC *)
let force_operation_injection =
  let step1_msg =
    "Step 1: Create one node with specific configuration that mimic a node \
     with secure ACL policy"
  in
  let step2_msg =
    "Step 2: Initialize a second node, connect both node and activate the \
     protocol"
  in
  let step3_msg = "Step 3: Get the counter and the current branch" in
  let step4_msg = "Step 4: Forge and sign operation with incorrect counter" in
  let step5_msg =
    "Step 5: Inject the operation on the secure node, and check for error \
     because the operation was refused"
  in
  let step6_msg =
    "Step 6: Force injection of operation on the secure node, and check for \
     error because we don't have the right to use this rpc"
  in
  let step7_msg =
    "Step 7: Inject operation on the local node, and check for error because \
     the operation was refused"
  in
  let step8_msg = "Step 8: Force injection of operation on local node" in
  Protocol.register_test
    ~__FILE__
    ~title:"force invalid operation injection"
    ~tags:["force"; "mempool"]
  @@ fun protocol ->
  Log.info "%s" step1_msg ;
  let node1 = Node.create [] in
  let* () = Node.config_init node1 [] in
  let address =
    Node.rpc_host node1 ^ ":" ^ string_of_int (Node.rpc_port node1)
  in
  let acl =
    JSON.annotate ~origin:"whitelist"
    @@ `A
         [
           `O
             [
               ("address", `String address);
               ( "whitelist",
                 `A
                   [
                     (* We do not add all RPC allowed in secure mode,
                        only the ones that are useful for this test. *)
                     `String "POST /injection/operation";
                     `String "GET /chains/*/blocks/*/protocols";
                     `String "GET /describe/**";
                   ] );
             ];
         ]
  in
  Node.Config_file.update node1 (JSON.update "rpc" (JSON.put ("acl", acl))) ;
  let* () = Node.identity_generate node1 in
  let* () = Node.run node1 [Synchronisation_threshold 0] in
  let* () = Node.wait_for_ready node1 in
  Log.info "%s" step2_msg ;
  let* node2 = Node.init [Synchronisation_threshold 0] in
  let* client1 = Client.init ~endpoint:Client.(Node node1) ()
  and* client2 = Client.init ~endpoint:Client.(Node node2) () in
  let* () = Client.Admin.connect_address client2 ~peer:node1
  and* () = Client.activate_protocol ~protocol client2 in
  let proto_activation_level = 1 in
  let* _ = Node.wait_for_level node1 proto_activation_level
  and* _ = Node.wait_for_level node2 proto_activation_level in
  Log.info "Both nodes are at level %d." proto_activation_level ;
  let open Lwt in
  Log.info "%s" step3_msg ;
  let* counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client2
    >|= JSON.as_int
  in
  let* branch = RPC.get_branch client2 >|= JSON.as_string in
  Log.info "%s" step4_msg ;
  let* (`Hex op_str_hex as op_hex) =
    forge_operation
      ~branch
      ~fee:1000 (* Minimal fees to successfully apply the transfer *)
      ~gas_limit:1040 (* Minimal gas to successfully apply the transfer *)
      ~source:Constant.bootstrap2.public_key_hash
      ~destination:Constant.bootstrap1.public_key_hash
      ~counter (* Invalid counter *)
      ~client:client2
  in
  let (`Hex signature) =
    Operation.sign_manager_op_hex ~signer:Constant.bootstrap2 op_hex
  in
  let signed_op = op_str_hex ^ signature in
  Log.info "%s" step5_msg ;
  let p = RPC.spawn_inject_operation ~data:(`String signed_op) client1 in
  let injection_error_rex =
    rex
      ~opts:[`Dotall]
      "Fatal error:\n  Command failed: Error while applying operation.*:"
  in
  let* () = Process.check_error ~msg:injection_error_rex p in
  Log.info "%s" step6_msg ;
  let p =
    RPC.spawn_private_inject_operation ~data:(`String signed_op) client1
  in
  let access_error_rex =
    rex ~opts:[`Dotall] "Fatal error:\n  .HTTP 403. Access denied to: .*"
  in
  let* () = Process.check_error ~msg:access_error_rex p in
  Log.info "%s" step7_msg ;
  let p = RPC.spawn_inject_operation ~data:(`String signed_op) client2 in
  let* () = Process.check_error ~msg:injection_error_rex p in
  Log.info "%s" step8_msg ;
  let* _ = RPC.private_inject_operation ~data:(`String signed_op) client2 in
  unit

(** This test tries to inject an operation with an old known branch *)
let injecting_old_operation_fails =
  let step1 = "Initialize node and activate protocol" in
  let step2 = "Recover counter and branch" in
  let step3 = "Bake max_op_ttl block" in
  let step4 = "Forge an operation with the old branch" in
  let step5 = "Inject the operation and wait for failure" in
  let log_step = Log.info "Step %d: %s" in
  let max_operations_ttl = 1 in
  Protocol.register_test
    ~__FILE__
    ~title:"Injecting old operation fails"
    ~tags:["mempool"; "injection"]
  @@ fun protocol ->
  let open Lwt in
  log_step 1 step1 ;
  let* node =
    Node.init [Synchronisation_threshold 0; Private_mode; Connections 0]
  in
  let* client = Client.init ~endpoint:(Node node) () in
  let* parameter_file =
    Protocol.write_parameter_file
      ~base:(Either.Right (protocol, None))
      [
        ( ["max_operations_time_to_live"],
          Some (string_of_int max_operations_ttl) );
      ]
  in
  let* () = Client.activate_protocol ~protocol ~parameter_file client in
  let* _ = Node.wait_for_level node 1 in
  log_step 2 step2 ;
  let* counter =
    RPC.Contracts.get_counter
      ~contract_id:Constant.bootstrap1.public_key_hash
      client
    >|= JSON.as_int
  in
  let* branch = RPC.get_branch client >|= JSON.as_string in
  log_step 3 step3 ;
  (* To avoid off-by-one mistakes *)
  let blocks_to_bake = 2 in
  let* () =
    repeat (max_operations_ttl + blocks_to_bake) (fun () ->
        Client.bake_for client)
  in
  (* + 1 for the activation block *)
  let* _ = Node.wait_for_level node (max_operations_ttl + blocks_to_bake + 1) in
  log_step 4 step4 ;
  let* (`Hex op_str_hex as op_hex) =
    forge_operation
      ~branch
      ~fee:1000
      ~gas_limit:1040
      ~source:Constant.bootstrap1.public_key_hash
      ~destination:Constant.bootstrap3.public_key_hash
      ~counter:(counter + 1)
      ~client
  in
  let (`Hex signature) =
    Operation.sign_manager_op_hex ~signer:Constant.bootstrap1 op_hex
  in
  log_step 5 step5 ;
  let process =
    RPC.spawn_inject_operation ~data:(`String (op_str_hex ^ signature)) client
  in
  let injection_error_rex =
    rex
      ~opts:[`Dotall]
      "Fatal error:\n\
      \  Command failed: Operation .* is branched on a block .* which is too \
       old"
  in
  Process.check_error ~msg:injection_error_rex process

(** Mempool filter configuration. *)
module Filter_config = struct
  type t = {
    minimal_fees : int option;
    minimal_nanotez_per_gas_unit : (int * int) option;
    minimal_nanotez_per_byte : (int * int) option;
    allow_script_failure : bool option;
  }

  let eq_int_pair (f1, s1) (f2, s2) = Int.equal f1 f2 && Int.equal s1 s2

  let equal
      {
        minimal_fees = mf1;
        minimal_nanotez_per_gas_unit = mng1;
        minimal_nanotez_per_byte = mnb1;
        allow_script_failure = asf1;
      }
      {
        minimal_fees = mf2;
        minimal_nanotez_per_gas_unit = mng2;
        minimal_nanotez_per_byte = mnb2;
        allow_script_failure = asf2;
      } =
    Option.equal Int.equal mf1 mf2
    && Option.equal eq_int_pair mng1 mng2
    && Option.equal eq_int_pair mnb1 mnb2
    && Option.equal Bool.equal asf1 asf2

  let pp fmt
      {
        minimal_fees = mf;
        minimal_nanotez_per_gas_unit = mng;
        minimal_nanotez_per_byte = mnb;
        allow_script_failure = asf;
      } =
    [
      Option.map (sf {|"minimal_fees": "%d"|}) mf;
      Option.map
        (fun (n1, n2) ->
          sf {|"minimal_nanotez_per_gas_unit": [ "%d", "%d" ]|} n1 n2)
        mng;
      Option.map
        (fun (n1, n2) ->
          sf {|"minimal_nanotez_per_byte": [ "%d", "%d" ]|} n1 n2)
        mnb;
      Option.map (sf {|"allow_script_failure": %b|}) asf;
    ]
    |> List.map Option.to_list |> List.flatten |> String.concat ", "
    |> Format.fprintf fmt {|{ %s }|}

  let show : t -> string = Format.asprintf "%a" pp

  let check_equal expected actual =
    Check.(
      (expected = actual)
        (equalable pp equal)
        ~error_msg:"Wrong filter configuration: %R.@.Expected: %L.")

  (** Returns the filter configuration corresponding to [json]. If any field
      of {!filter_config} is missing from [json], it is set to the default
      value (i.e. the corresponding value in {!default_config}. *)
  let of_json json =
    let open JSON in
    let as_int_pair_opt t =
      match as_list_opt t with
      | Some [x; y] -> Some (as_int x, as_int y)
      (* A missing field is interpreted as [`Null], from which [as_list_opt]
         produces [Some []]. *)
      | Some [] -> None
      | Some _ | None ->
          Test.fail
            "Constructing a filter_config from json: %s. Expected a list of \
             length 2, found: %s."
            (encode json)
            (encode t)
    in
    {
      minimal_fees = json |-> "minimal_fees" |> as_int_opt;
      minimal_nanotez_per_gas_unit =
        json |-> "minimal_nanotez_per_gas_unit" |> as_int_pair_opt;
      minimal_nanotez_per_byte =
        json |-> "minimal_nanotez_per_byte" |> as_int_pair_opt;
      allow_script_failure = json |-> "allow_script_failure" |> as_bool_opt;
    }

  (** Default filter configuration for protocol alpha
      (in proto_alpha/lib_plugin/plugin.ml). *)

  let default_minimal_fees = 100

  let default_minimal_nanotez_per_gas_unit = (100, 1)

  let default_minimal_nanotez_per_byte = (1000, 1)

  let default_allow_script_failure = true

  let default =
    {
      minimal_fees = Some default_minimal_fees;
      minimal_nanotez_per_gas_unit = Some default_minimal_nanotez_per_gas_unit;
      minimal_nanotez_per_byte = Some default_minimal_nanotez_per_byte;
      allow_script_failure = Some default_allow_script_failure;
    }

  (** Returns a copy of the given filter config, where missing fields
      (i.e. containing [None]) have been set to their default value. *)
  let fill_with_default
      {
        minimal_fees = mf;
        minimal_nanotez_per_gas_unit = mng;
        minimal_nanotez_per_byte = mnb;
        allow_script_failure = asf;
      } =
    Option.
      {
        minimal_fees = Some (value mf ~default:default_minimal_fees);
        minimal_nanotez_per_gas_unit =
          Some (value mng ~default:default_minimal_nanotez_per_gas_unit);
        minimal_nanotez_per_byte =
          Some (value mnb ~default:default_minimal_nanotez_per_byte);
        allow_script_failure =
          Some (value asf ~default:default_allow_script_failure);
      }

  (** Returns a copy of the given filter config, where fields equal
      to their default value have been removed (i.e. set to [None]). *)
  let clear_default
      {
        minimal_fees = mf;
        minimal_nanotez_per_gas_unit = mng;
        minimal_nanotez_per_byte = mnb;
        allow_script_failure = asf;
      } =
    let clear_if_default eq_fun default = function
      | Some x when eq_fun default x -> None
      | x -> x
    in
    {
      minimal_fees = clear_if_default Int.equal default_minimal_fees mf;
      minimal_nanotez_per_gas_unit =
        clear_if_default eq_int_pair default_minimal_nanotez_per_gas_unit mng;
      minimal_nanotez_per_byte =
        clear_if_default eq_int_pair default_minimal_nanotez_per_byte mnb;
      allow_script_failure =
        clear_if_default Bool.equal default_allow_script_failure asf;
    }

  (** Checks that RPC [GET /chains/main/mempool/filter] returns the
      appropriate result for [expected_config], testing all possibilities
      for optional argument [include_default] (omitted/[true]/[false]). *)
  let check_RPC_GET_all_variations ?(log = false) expected_config client =
    let expected_full = fill_with_default expected_config in
    let* json = RPC.get_mempool_filter client in
    check_equal expected_full (of_json json) ;
    let* json = RPC.get_mempool_filter ~include_default:true client in
    check_equal expected_full (of_json json) ;
    let expected_partial = clear_default expected_config in
    let* json = RPC.get_mempool_filter ~include_default:false client in
    check_equal expected_partial (of_json json) ;
    if log then
      Log.info
        "GET /chains/main/mempool/filter returned expected configurations \
         (respectively including/excluding default fields): %s and %s."
        (show expected_full)
        (show expected_partial) ;
    unit
end

(* Probably to be replaced during upcoming mempool tests refactoring *)
let init_single_node_and_activate_protocol
    ?(arguments = Node.[Synchronisation_threshold 0; Connections 0])
    ?event_sections_levels protocol =
  let* node = Node.init ?event_sections_levels arguments in
  let* client = Client.init ~endpoint:Client.(Node node) () in
  let* () = Client.activate_protocol ~protocol client in
  let proto_activation_level = 1 in
  let* _ = Node.wait_for_level node proto_activation_level in
  return (node, client)

(* Probably to be replaced during upcoming mempool tests refactoring *)
let init_two_connected_nodes_and_activate_protocol ?event_sections_levels1
    ?event_sections_levels2 protocol =
  let arguments = Node.[Synchronisation_threshold 0; Connections 1] in
  let* node1 = Node.init ?event_sections_levels:event_sections_levels1 arguments
  and* node2 =
    Node.init ?event_sections_levels:event_sections_levels2 arguments
  in
  let* client1 = Client.init ~endpoint:Client.(Node node1) ()
  and* client2 = Client.init ~endpoint:Client.(Node node2) () in
  let* () = Client.Admin.connect_address client1 ~peer:node2
  and* () = Client.activate_protocol ~protocol client1 in
  let proto_activation_level = 1 in
  let* _ = Node.wait_for_level node1 proto_activation_level
  and* _ = Node.wait_for_level node2 proto_activation_level in
  return (node1, client1, node2, client2)

(* TMP: to be replaced in !3418 *)
let log_step n msg = Log.info ~color:Log.Color.BG.blue "Step %d: %s" n msg

(** Aim: test RPCs [GET|POST /chains/<chain>/mempool/filter]. *)
let test_get_post_mempool_filter =
  let title = "get post mempool filter" in
  let tags = ["mempool"; "node"; "filter"] in
  let step1_msg = "Start a single node and activate the protocol." in
  let step2_msg =
    "Call RPC [GET /chains/main/mempool/filter], check that we obtain the \
     default configuration (the full configuration when the query parameter \
     [include_default] is either absent or set to [true], or an empty \
     configuration if [include_default] is [false])."
  in
  let step3_msg =
    "Call RPC [POST /chains/main/mempool/filter] for various configurations. \
     Each time, call [GET /chains/main/mempool/filter] with optional parameter \
     include_default omitted/[true]/[false] and check that we obtain the right \
     configuration."
  in
  let step4_msg =
    "Step 4: Post invalid config modifications, check that config is unchanged \
     and event [invalid_mempool_filter_configuration] is witnessed."
  in
  let step5_msg =
    "Step 5: Set the filter to {} and check that this restored the default \
     config. Indeed, fields that are not provided are set to their default \
     value."
  in
  Protocol.register_test ~__FILE__ ~title ~tags @@ fun protocol ->
  let open Filter_config in
  log_step 1 step1_msg ;
  let* (node1, client1) =
    (* We need event level [debug] for event
       [invalid_mempool_filter_configuration]. *)
    init_single_node_and_activate_protocol
      ~event_sections_levels:[("prevalidator", `Debug)]
      protocol
  in
  log_step 2 step2_msg ;
  let* () = check_RPC_GET_all_variations ~log:true default client1 in
  log_step 3 step3_msg ;
  let set_config_and_check msg config =
    Log.info "%s" msg ;
    let* output = Revamped.set_filter ~log:true (show config) client1 in
    check_equal (fill_with_default config) (of_json output) ;
    check_RPC_GET_all_variations ~log:true config client1
  in
  let* () =
    set_config_and_check
      "Config1: not all fields provided (missing fields should be set to \
       default)."
      {
        minimal_fees = Some 25;
        minimal_nanotez_per_gas_unit = None;
        minimal_nanotez_per_byte = Some (1050, 1);
        allow_script_failure = Some false;
      }
  in
  let* () =
    set_config_and_check
      "Config2: all fields provided and distinct from default."
      {
        minimal_fees = Some 1;
        minimal_nanotez_per_gas_unit = Some (2, 3);
        minimal_nanotez_per_byte = Some (4, 5);
        allow_script_failure = Some false;
      }
  in
  let config3 =
    {
      minimal_fees = None;
      minimal_nanotez_per_gas_unit = Some default_minimal_nanotez_per_gas_unit;
      minimal_nanotez_per_byte = Some (4, 2);
      allow_script_failure = Some default_allow_script_failure;
    }
  in
  let* () =
    set_config_and_check
      "Config3: some of the provided fields equal to default."
      config3
  in
  log_step 4 step4_msg ;
  let config3_full = fill_with_default config3 in
  let test_invalid_config invalid_config_str =
    let waiter =
      Node.wait_for
        node1
        (* This event has level [debug]. *)
        "invalid_mempool_filter_configuration.v0"
        (Fun.const (Some ()))
    in
    let* output = Revamped.set_filter invalid_config_str client1 in
    check_equal config3_full (of_json output) ;
    let* () = waiter in
    let* output = RPC.get_mempool_filter client1 in
    check_equal config3_full (of_json output) ;
    Log.info "Tested invalid config: %s." invalid_config_str ;
    unit
  in
  let* () =
    Tezos_base__TzPervasives.List.iter_s
      test_invalid_config
      [
        {|{ "minimal_fees": "100", "minimal_nanotez_per_byte": [ "1050", "1" ], "allow_script_failure": false, "invalid_field_name": 0 }|};
        {|{ "minimal_fees": true}|};
        {|{ "minimal_nanotez_per_gas_unit": [ "100" ]}|};
        {|{ "minimal_nanotez_per_gas_unit": [ "100", "1", "10" ]}|};
      ]
  in
  log_step 5 step5_msg ;
  let* output = Revamped.set_filter ~log:true "{}" client1 in
  check_equal default (of_json output) ;
  check_RPC_GET_all_variations ~log:true default client1

(** Similar to [Node_event_level.transfer_and_wait_for_injection] but more general.
    Should be merged with it during upcoming mempool tests refactoring. *)
let inject_transfer ?(amount = 1) ?(giver_key = Constant.bootstrap1)
    ?(receiver_key = Constant.bootstrap5) ?fee ?(wait_for = wait_for_injection)
    ?node client =
  let waiter = match node with None -> unit | Some node -> wait_for node in
  let _ =
    Client.transfer
      ~wait:"0"
      ~amount:(Tez.of_int amount)
      ~giver:giver_key.Account.alias
      ~receiver:receiver_key.Account.alias
      ?fee:(Option.map Tez.of_mutez_int fee)
      client
  in
  waiter

(** Gets the fee of an operation from the json representing the operation. *)
let get_fee op = JSON.(op |-> "contents" |=> 0 |-> "fee" |> as_int)

let check_unordered_int_list_equal expected actual ~error_msg =
  let unordered_int_list_equal l1 l2 =
    let sort = List.sort Int.compare in
    List.equal Int.equal (sort l1) (sort l2)
  in
  Check.(
    (expected = actual)
      (equalable
         Format.(
           pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "; ") pp_print_int)
         unordered_int_list_equal)
      ~error_msg)

(** Checks that in the mempool of [client], [applied] is the list of
    respective fees of the applied operations (the order of the list
    is not required to be right), and [refused] is the list of respective
    fees of the refused operations. Also logs the hash and fee of all
    these operations. Moreover, check that there is no branch_delayed,
    branch_refused, or unprocessed operation. *)
let check_mempool_ops_fees ~(applied : int list) ~(refused : int list) client =
  let client_name = Client.name client in
  let* ops = RPC.get_mempool_pending_operations ~version:"1" client in
  let check_fees classification expected =
    let classification_ops = JSON.(ops |-> classification |> as_list) in
    let actual =
      List.map
        (fun op ->
          let fee = get_fee op in
          Log.info
            ~color:Log.Color.FG.yellow
            ~prefix:(client_name ^ ", " ^ classification)
            "%s (fee: %d)"
            (get_hash op)
            fee ;
          fee)
        classification_ops
    in
    check_unordered_int_list_equal
      expected
      actual
      ~error_msg:
        (sf
           "In the mempool of %s, %s operations should have respective fees: \
            [%s] but found: [%s]."
           client_name
           classification
           "%L"
           "%R")
  in
  check_fees "applied" applied ;
  check_fees "refused" refused ;
  (* Check that other classifications are empty *)
  List.iter
    (fun classification ->
      match JSON.(ops |-> classification |> as_list) with
      | [] -> ()
      | _ ->
          Test.fail
            "Unexpectedly found %s operation(s) in the mempool of %s:\n%s"
            classification
            client_name
            (JSON.encode ops))
    ["branch_refused"; "branch_delayed"; "unprocessed"] ;
  unit

(** Aim: test that when we modify the filter configuration of the mempool
    using the RPC [POST /chains/<chain>/mempool/filter], this correctly
    impacts the classification of the operations that arrive from a peer. *)
let test_mempool_filter_operation_arrival =
  let title = "mempool filter arrival" in
  let tags = ["mempool"; "node"; "filter"; "refused"; "applied"] in
  let show_fees fees = String.concat "; " (List.map Int.to_string fees) in
  let step1 = "Start two nodes, connect them, and activate the protocol." in
  let step2 =
    "In [node2]'s mempool filter configuration, set all fields [minimal_*] to \
     0, so that [node2] accepts operations with any fee."
  in
  let fee1 = 1000 and fee2 = 101 in
  let feesA = [fee1; fee2] in
  let appliedA2 = feesA in
  let step3 =
    sf
      "Inject two operations (transfers) in [node2] with respective fees (in \
       mutez): %s. Check that both operations are [applied] in [node2]'s \
       mempool."
      (show_fees feesA)
  in
  let appliedA1 = [fee1] and refusedA1 = [fee2] in
  let step4 =
    sf
      "Bake with an empty mempool for [node1] to force synchronization with \
       [node2]. Check that in the mempool of [node1], the operation with fee \
       %d is applied and the one with fee %d is refused. Indeed, [node1] has \
       the default filter config: (minimal fees (mutez): 100, minimal nanotez \
       per gas unit: 100, minimal nanotez per byte: 1000). Moreover, the fee \
       must overcome the SUM of minimal fees, minimal nanotez per gas unit \
       multiplied by the operation's gas, and minimal nanotez per byte \
       multiplied by the operation's size; therefore the operation with fee %d \
       does not qualify."
      fee1
      fee2
      fee2
  in
  let fee3 = 100 and fee4 = 99 in
  let feesB = [fee3; fee4] in
  let appliedB1 = fee3 :: appliedA1 and refusedB1 = fee4 :: refusedA1 in
  let step5 =
    sf
      "Set [minimal_nanotez_per_gas_unit] and [minimal_nanotez_per_byte] to 0 \
       in [node1]. Inject new operations in [node2] with respective fees: %s. \
       Bake again with an empty mempool. Check the operations in the mempool \
       of [node1]: the operation with fee %d should be [applied], while the \
       one with fee %d should be [refused]. Note that the operation with fee \
       %d would now be valid, but it has already been [refused] and cannot be \
       revalidated."
      (show_fees feesB)
      fee3
      fee4
      fee2
  in
  let applied_after_bake_2 = [fee2; fee3; fee4] in
  let step6 =
    sf
      "Bake for [node2] normally (without enforcing a given mempool). Note \
       that the filter used to determine which operations are included in the \
       block does not share its configuration with the mempool's filter, so \
       only the operation with fee %d is included. This will allow us to reuse \
       [bootstrap1] (the author of this operation) to issue a new transfer. \
       Check that [node2] has three [applied] operations left with fees: %s."
      fee1
      (show_fees applied_after_bake_2)
  in
  let fee5 = 10 and fee6 = 0 in
  let feesC = [fee5; fee6] in
  let appliedC2 = applied_after_bake_2 @ feesC in
  let appliedC1 = [fee5; fee3] and refusedC1 = fee6 :: refusedB1 in
  let step7 =
    sf
      "Set [minimal_fees] to 10 in the mempool filter configuration of \
       [node1], while keeping [minimal_nanotez_per_gas_unit] and \
       [minimal_nanotez_per_byte] at 0. Inject operations with fees: %s in \
       [node2], and check that all operations are [applied] in [node2]. Bake \
       again with on empty mempool, and check the operations in [node1]."
      (show_fees feesC)
  in
  Protocol.register_test ~__FILE__ ~title ~tags @@ fun protocol ->
  log_step 1 step1 ;
  let* (node1, client1, node2, client2) =
    init_two_connected_nodes_and_activate_protocol
    (* Need event level [debug] to receive operation arrival events in [node1]. *)
      ~event_sections_levels1:[("prevalidator", `Debug)]
      protocol
  in
  log_step 2 step2 ;
  let* _ = set_filter_no_fee_requirement client2 in
  log_step 3 step3 ;
  let inject_transfers ?receiver_key giver_keys fees =
    iter2_p
      (fun giver_key fee ->
        inject_transfer ?receiver_key ~giver_key ~fee ~node:node2 client2)
      giver_keys
      fees
  in
  let waiter_arrival_node1 = wait_for_arrival node1 in
  let* () = inject_transfers Constant.[bootstrap1; bootstrap2] feesA in
  let* () = check_mempool_ops_fees ~applied:appliedA2 ~refused:[] client2 in
  log_step 4 step4 ;
  let* () =
    bake_empty_block_and_wait_for_flush ~protocol ~log:true client1 node1
  in
  let* () = waiter_arrival_node1 in
  let* () =
    check_mempool_ops_fees ~applied:appliedA1 ~refused:refusedA1 client1
  in
  log_step 5 step5 ;
  let* _ =
    Revamped.set_filter
      ~log:true
      {|{ "minimal_nanotez_per_gas_unit": [ "0", "1" ], "minimal_nanotez_per_byte": [ "0", "1" ] }|}
      client1
  in
  let waiterB = wait_for_arrival node1 in
  let* () = inject_transfers Constant.[bootstrap3; bootstrap4] feesB in
  let* () =
    bake_empty_block_and_wait_for_flush ~protocol ~log:true client1 node1
  in
  let* () = waiterB in
  let* () =
    check_mempool_ops_fees ~applied:appliedB1 ~refused:refusedB1 client1
  in
  log_step 6 step6 ;
  let* () = bake_wait_log node2 client2 in
  let* () =
    check_mempool_ops_fees ~applied:applied_after_bake_2 ~refused:[] client2
  in
  log_step 7 step7 ;
  let* _ =
    Revamped.set_filter
      {|{ "minimal_fees": "10", "minimal_nanotez_per_gas_unit": [ "0", "1" ], "minimal_nanotez_per_byte": [ "0", "1" ] }|}
      client1
  in
  let waiterC = wait_for_arrival node1 in
  let* () =
    inject_transfers
      ~receiver_key:Constant.bootstrap2
      Constant.[bootstrap5; bootstrap1]
      feesC
  in
  let* () = check_mempool_ops_fees ~applied:appliedC2 ~refused:[] client2 in
  let* () =
    bake_empty_block_and_wait_for_flush ~protocol ~log:true client1 node1
  in
  let* () = waiterC in
  check_mempool_ops_fees ~applied:appliedC1 ~refused:refusedC1 client1

let test_request_operations_peer =
  let step1_msg = "Step 1: Connect and initialise two nodes " in
  let step2_msg = "Step 2: Disconnect nodes " in
  let step3_msg = "Step 3: Inject an operation " in
  let step4_msg =
    "Step 4: Reconnect nodes, request operations and witness arrival of \
     operation previously injected "
  in
  Protocol.register_test
    ~__FILE__
    ~title:"Test request_operations rpc"
    ~tags:["mempool"; "request_operations"]
  @@ fun protocol ->
  Log.info "%s" step1_msg ;
  let init_node () =
    Node.init
      ~event_sections_levels:[("prevalidator", `Debug)]
      [Synchronisation_threshold 0; Private_mode]
  in
  let* node_1 = init_node () and* node_2 = init_node () in
  let* client_1 = Client.init ~endpoint:(Node node_1) ()
  and* client_2 = Client.init ~endpoint:(Node node_2) () in
  let* () = Client.Admin.trust_address client_1 ~peer:node_2
  and* () = Client.Admin.trust_address client_2 ~peer:node_1 in
  let* () = Client.Admin.connect_address client_1 ~peer:node_2 in
  let* () = Client.activate_protocol ~protocol client_1 in
  Log.info "Activated protocol." ;
  let* _ = Node.wait_for_level node_1 1 and* _ = Node.wait_for_level node_2 1 in
  Log.info "%s" step2_msg ;
  let* node2_identity = Node.wait_for_identity node_2 in
  let* () = Client.Admin.kick_peer ~peer:node2_identity client_1 in
  Log.info "%s" step3_msg ;
  let transfer_1 = wait_for_injection node_1 in
  let _ =
    Client.transfer
      ~wait:"0"
      ~amount:(Tez.of_int 1)
      ~giver:Constant.bootstrap1.alias
      ~receiver:Constant.bootstrap2.alias
      ~counter:1
      client_1
  in
  let* _ = transfer_1 in
  let* oph =
    let* ophs = get_applied_operation_hash_list client_1 in
    match ophs with
    | [oph] -> return oph
    | _ -> Test.fail "Applied mempool should contain exactly one operation"
  in
  Log.info "%s" step4_msg ;
  let wait_mempool = wait_for_arrival_of_ophash oph node_2 in
  let* () = Client.Admin.connect_address ~peer:node_1 client_2 in
  let* node1_identity = Node.wait_for_identity node_1 in
  let* _ = RPC.mempool_request_operations ~peer:node1_identity client_2 in
  let* () = wait_mempool in
  unit

let register ~protocols =
  Revamped.flush_mempool ~protocols ;
  Revamped.recycling_branch_refused ~protocols ;
  Revamped.ban_operation_branch_delayed_reevaluated ~protocols ;
  Revamped.one_operation_per_manager_per_block_restriction_injection ~protocols ;
  Revamped.one_operation_per_manager_per_block_restriction_propagation
    ~protocols ;
  Revamped.one_operation_per_manager_per_block_disable_precheck ~protocols ;
  Revamped.one_operation_per_manager_per_block_flush ~protocols ;
  Revamped.one_operation_per_manager_per_block_ban ~protocols ;
  Revamped.one_operation_per_manager_per_block_flush_on_ban ~protocols ;
  Revamped.one_operation_per_manager_per_block_inject_not_applied ~protocols ;
  Revamped.max_refused_operations_branch_delayed ~protocols ;
  Revamped.max_refused_operations_branch_refused ~protocols ;
  Revamped.max_refused_operations_refused ~protocols ;
  Revamped.max_refused_operations_outdated ~protocols ;
  Revamped.ban_operation ~protocols ;
  Revamped.unban_operation_and_reinject ~protocols ;
  Revamped.unban_all_operations ~protocols ;
  Revamped.test_prefiltered_limit ~protocols ;
  run_batched_operation ~protocols ;
  propagation_future_endorsement ~protocols ;
  forge_pre_filtered_operation ~protocols ;
  refetch_failed_operation ~protocols ;
  ban_operation_and_check_applied ~protocols ;
  test_do_not_reclassify ~protocols ;
  test_pending_operation_version ~protocols ;
  force_operation_injection ~protocols ;
  injecting_old_operation_fails ~protocols ;
  test_get_post_mempool_filter ~protocols ;
  test_mempool_filter_operation_arrival ~protocols ;
  test_request_operations_peer ~protocols
