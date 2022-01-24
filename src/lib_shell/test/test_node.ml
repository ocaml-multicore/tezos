(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs. <contact@nomadic-labs.com>               *)
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
    Component:    Shell (Node)
    Invocation:   dune exec src/lib_shell/test/test_shell.exe \
                  -- test '^test node$'
    Dependencies: src/lib_shell/test/shell_test_helpers.ml
    Subject:      Unit tests for node. Currently only tests that
                  events are emitted.
*)

let section = Some (Internal_event.Section.make_sanitized ["node"])

let filter = Some section

let init_config (* (f : 'a -> unit -> unit Lwt.t) *) f test_dir switch () :
    unit Lwt.t =
  let sandbox_parameters : Data_encoding.json = `Null in
  let config : Node.config =
    {
      genesis = Shell_test_helpers.genesis;
      chain_name = Distributed_db_version.Name.zero;
      sandboxed_chain_name = Distributed_db_version.Name.zero;
      user_activated_upgrades = [];
      user_activated_protocol_overrides = [];
      data_dir = test_dir;
      store_root = test_dir;
      context_root = test_dir;
      protocol_root = test_dir;
      patch_context = None;
      p2p = None;
      target = None;
      disable_mempool = false;
      enable_testchain = true;
    }
  in
  f sandbox_parameters config switch ()

let default_p2p : P2p.config =
  {
    listening_port = None;
    listening_addr = Some (P2p_addr.of_string_exn "[::]");
    advertised_port = None;
    discovery_port = None;
    discovery_addr = Some Ipaddr.V4.any;
    trusted_points = [];
    peers_file = "";
    private_mode = true;
    identity = P2p_identity.generate_with_pow_target_0 ();
    proof_of_work_target = Crypto_box.default_pow_target;
    trust_discovered_peers = false;
    reconnection_config = P2p_point_state.Info.default_reconnection_config;
  }

let default_p2p_limits : P2p.limits =
  {
    connection_timeout = Time.System.Span.of_seconds_exn 10.;
    authentication_timeout = Time.System.Span.of_seconds_exn 5.;
    greylist_timeout = Time.System.Span.of_seconds_exn 86400. (* one day *);
    maintenance_idle_time =
      Time.System.Span.of_seconds_exn 120. (* two minutes *);
    min_connections = 10;
    expected_connections = 50;
    max_connections = 100;
    backlog = 20;
    max_incoming_connections = 20;
    max_download_speed = None;
    max_upload_speed = None;
    read_buffer_size = 1 lsl 14;
    read_queue_size = None;
    write_queue_size = None;
    incoming_app_message_queue_size = None;
    incoming_message_queue_size = None;
    outgoing_message_queue_size = None;
    max_known_points = Some (400, 300);
    max_known_peer_ids = Some (400, 300);
    swap_linger = Time.System.Span.of_seconds_exn 30.;
    binary_chunks_size = None;
    peer_greylist_size = 1023;
    ip_greylist_size_in_kilobytes = 256;
    ip_greylist_cleanup_delay = Ptime.Span.of_int_s 3600;
  }

let default_p2p = Some (default_p2p, default_p2p_limits)

let wrap f _switch () =
  Tztest.with_empty_mock_sink (fun _ ->
      Lwt_utils_unix.with_tempdir "tezos_test_" (fun test_dir ->
          init_config f test_dir _switch ()))

(** Start tests *)

let ( >>=?? ) m f =
  m >>= function
  | Ok v -> f v
  | Error error ->
      Format.printf "Error:\n   %a\n" pp_print_trace error ;
      Format.print_flush () ;
      Lwt.return_unit

(** Node creation in sandbox. Expects one event with status
    [p2p_layer_disabled]. *)
let node_sandbox_initialization_events sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:true
    ~sandbox_parameters
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    config
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  let evs = Mock_sink.get_events ?filter () in
  Alcotest.(check int) "should have one event" 1 (List.length evs) ;
  Mock_sink.Pattern.(
    assert_event
      {
        level = Some Internal_event.Notice;
        section = Some section;
        name = "shell-node";
      })
    (WithExceptions.Option.get ~loc:__LOC__ @@ List.nth evs 0) ;
  (* End tests *)
  Node.shutdown n

(** Node creation. Expects two events with statuses
    [bootstrapping] and [p2p_maintain_started]. *)
let node_initialization_events _sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:false
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    {config with p2p = default_p2p}
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  let evs = Mock_sink.get_events ?filter () in
  Alcotest.(check int) "should have two events" 2 (List.length evs) ;
  Mock_sink.Pattern.(
    assert_event
      {
        level = Some Internal_event.Notice;
        section = Some section;
        name = "shell-node";
      })
    (WithExceptions.Option.get ~loc:__LOC__ @@ List.nth evs 0) ;
  Mock_sink.Pattern.(
    assert_event
      {
        level = Some Internal_event.Notice;
        section = Some section;
        name = "shell-node";
      })
    (WithExceptions.Option.get ~loc:__LOC__ @@ List.nth evs 1) ;
  (* End tests *)
  Node.shutdown n

let node_store_known_protocol_events _sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:false
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    {config with p2p = default_p2p}
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  Mock_sink.(
    assert_has_event
      "Should have a store_protocol_incorrect_hash event"
      ?filter
      Pattern.
        {
          level = Some Internal_event.Info;
          section = Some section;
          name = "store_protocol_incorrect_hash";
        }) ;
  (* END tests *)
  Node.shutdown n

let tests =
  [
    Alcotest_lwt.test_case
      "node_sandbox_initialization_events"
      `Quick
      (wrap node_sandbox_initialization_events);
    Alcotest_lwt.test_case
      "node_initialization_events"
      `Quick
      (wrap node_initialization_events);
  ]
