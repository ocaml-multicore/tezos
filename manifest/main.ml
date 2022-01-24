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

open Manifest

(* EXTERNAL LIBS *)

let alcotest = external_lib "alcotest" [At_least "1.5.0"]

let alcotest_lwt = external_lib "alcotest-lwt" [At_least "1.5.0"]

let astring = external_lib "astring" []

let bigstring = external_lib "bigstring" []

let bigstringaf = external_lib "bigstringaf" [At_least "0.2.0"]

let bisect_ppx = opam_only "bisect_ppx" [At_least "2.7.0"]

let bls12_381 = external_lib "bls12-381" [At_least "1.1.0"; Less_than "1.2.0"]

let bls12_381_legacy = external_lib "bls12-381-legacy" []

let bls12_381_unix = external_lib "bls12-381-unix" []

let camlzip = external_lib "camlzip" [Exactly "1.10"]

let caqti = external_lib "caqti" []

let caqti_lwt = external_lib "caqti-lwt" []

let caqti_driver_postgresql = external_lib "caqti-driver-postgresql" []

let cmdliner = external_lib "cmdliner" []

let cohttp_lwt_unix = external_lib "cohttp-lwt-unix" [At_least "2.2.0"]

let compiler_libs_common = external_lib "compiler-libs.common" [] ~opam:""

let compiler_libs_optcomp = external_lib "compiler-libs.optcomp" [] ~opam:""

let compiler_libs_toplevel = external_lib "compiler-libs.toplevel" [] ~opam:""

let conf_libev = opam_only "conf-libev" []

let conf_rust = opam_only "conf-rust" []

let coq_of_ocaml = opam_only "coq-of-ocaml" [Exactly "2.5.0"]

let ctypes = external_lib "ctypes" [At_least "0.18.0"]

let ctypes_stubs = external_sublib ctypes "ctypes.stubs"

let data_encoding =
  external_lib "data-encoding" [At_least "0.4"; Less_than "0.5"]

let digestif = external_lib "digestif" [At_least "0.7.3"]

let digestif_c = external_sublib digestif "digestif.c"

let dynlink = external_lib "dynlink" [] ~opam:""

let ezjsonm = external_lib "ezjsonm" [At_least "1.1.0"]

let fmt = external_lib "fmt" [At_least "0.8.7"]

let fmt_cli = external_sublib fmt "fmt.cli"

let fmt_tty = external_sublib fmt "fmt.tty"

let hacl_star = external_lib "hacl-star" [At_least "0.4.2"; Less_than "0.5"]

let hacl_star_raw = external_lib "hacl-star-raw" []

let hacl_x25519 = external_lib "hacl_x25519" []

let hex = external_lib "hex" [At_least "1.3.0"]

let index = external_lib "index" [At_least "1.3.0"]

let integers = external_lib "integers" []

let ipaddr = external_lib "ipaddr" [At_least "5.0.0"; Less_than "6.0.0"]

let ipaddr_unix = external_sublib ipaddr "ipaddr.unix"

let irmin = external_lib "irmin" [At_least "2.10.0"; Less_than "2.11.0"]

let irmin_pack =
  external_lib "irmin-pack" [At_least "2.10.0"; Less_than "2.11.0"]

let irmin_pack_mem = external_sublib irmin_pack "irmin-pack.mem"

let js_of_ocaml = external_lib "js_of_ocaml" []

let json_data_encoding = external_lib "json-data-encoding" []

let logs = external_lib "logs" []

let logs_fmt = external_sublib logs "logs.fmt"

let lwt = external_lib "lwt" [At_least "5.4.0"]

let lwt_canceler = external_lib "lwt-canceler" [At_least "0.3"; Less_than "0.4"]

let lwt_exit = external_lib "lwt-exit" []

let lwt_log = external_lib "lwt_log" []

let lwt_log_core = external_sublib lwt_log "lwt_log.core"

let lwt_unix = external_sublib lwt "lwt.unix"

let lwt_watcher = external_lib "lwt-watcher" [Exactly "0.1"]

let mtime = external_lib "mtime" [At_least "1.0.0"]

let mtime_clock_os = external_sublib mtime "mtime.clock.os"

let ocaml_migrate_parsetree = external_lib "ocaml-migrate-parsetree" []

let ocamlformat = opam_only "ocamlformat" [Exactly "0.18.0"]

let ocamlgraph = external_lib "ocamlgraph" []

let ocplib_endian = external_lib "ocplib-endian" []

let ocplib_endian_bigstring =
  external_sublib ocplib_endian "ocplib-endian.bigstring"

let ocplib_ocamlres =
  external_lib ~opam:"ocp-ocamlres" "ocplib-ocamlres" [At_least "0.4"]

let parsexp = external_lib "parsexp" []

let ppx_blob = external_lib "ppx_blob" []

let ppx_inline_test = external_lib "ppx_inline_test" []

let ptime = external_lib "ptime" [At_least "0.8.4"]

let ptime_clock_os = external_sublib ptime "ptime.clock.os"

let pure_splitmix = external_lib "pure-splitmix" [Exactly "0.2"]

let prbnmcn_stats = external_lib "prbnmcn-stats" [Exactly "0.0.2"]

let prometheus = external_lib "prometheus" []

let prometheus_app = external_lib "prometheus-app" []

let prometheus_app_unix = external_sublib prometheus_app "prometheus-app.unix"

let pyml = external_lib "pyml" []

let qcheck_alcotest = external_lib "qcheck-alcotest" [At_least "0.15"]

let qcheck_core = external_lib "qcheck-core" []

let re = external_lib "re" [At_least "1.7.2"]

let re_str = external_sublib re "re.str"

let resto_version = Opam.[At_least "0.6"; Less_than "0.7"]

let resto = external_lib "resto" resto_version

let resto_acl = external_lib "resto-acl" resto_version

let resto_cohttp = external_lib "resto-cohttp" resto_version

let resto_cohttp_client = external_lib "resto-cohttp-client" resto_version

let resto_cohttp_self_serving_client =
  external_lib "resto-cohttp-self-serving-client" resto_version

let resto_cohttp_server = external_lib "resto-cohttp-server" resto_version

let resto_directory = external_lib "resto-directory" resto_version

let ringo = external_lib "ringo" [Exactly "0.7"]

let ringo_lwt = external_lib "ringo-lwt" [Exactly "0.7"]

let secp256k1_internal = external_lib "secp256k1-internal" []

let str = external_lib "str" ~opam:"" []

let tar = external_lib "tar" []

let tar_unix = external_lib "tar-unix" [Exactly "1.1.0"]

let tezos_rust_lib = opam_only "tezos-rust-libs" [Exactly "1.1"]

let tls = external_lib "tls" [At_least "0.10"]

let unix = external_lib ~opam:"base-unix" "unix" []

let uri = external_lib "uri" []

let utop = external_lib "utop" [At_least "2.8"]

let uutf = external_lib "uutf" []

let vector = external_lib "vector" []

(* The signature of the [Z] module has changed in 1.12. *)
let zarith = external_lib "zarith" [At_least "1.12"; Less_than "1.13"]

let zarith_stubs_js = external_lib "zarith_stubs_js" []

(* VENDORED LIBS *)

let benchmark_utils = vendored_lib "benchmark-utils"

let flextesa = vendored_lib "flextesa"

let ledgerwallet_tezos = vendored_lib "ledgerwallet-tezos"

let pyml_plot = vendored_lib "pyml-plot"

(* PACKAGES THAT ARE NOT IMPLEMENTED YET *)

(* For now we declare them as external packages just so that we can depend on them,
   but their dune and .opam files are not yet generated. *)
let todo ?opam name = external_lib ?opam name []

let todo_sub lib sub = external_sublib lib sub

let tezos_alpha_test_helpers = todo "tezos-alpha-test-helpers"

let tezos_protocol_alpha_parameters = todo "tezos-protocol-alpha-parameters"

let tezos_benchmarks_proto_alpha = todo "tezos-benchmarks-proto-alpha"

(* PROTOCOL PACKAGES *)

module Protocol : sig
  type t

  val number : t -> int option

  (** Name without the number, e.g. "alpha" or "PsDELPH1". *)
  val name : t -> string

  val main : t -> target

  val embedded : t -> target

  (** [embedded] does not fail, it's just that the optional version
      composes better with [all_optionally]. *)
  val embedded_opt : t -> target option

  val client : t -> target option

  val client_exn : t -> target

  val client_commands_registration : t -> target option

  val baking_commands_registration : t -> target option

  val plugin : t -> target option

  val plugin_exn : t -> target

  val plugin_registerer : t -> target option

  val genesis : t

  val demo_noops : t

  val alpha : t

  (** List of active protocols. *)
  val active : t list

  (** Get packages to link.

      This takes a function that selects packages from a protocol.
      For instance, the node wants the embedded protocol and the plugin registerer,
      while the client wants the client commands etc.

      The result is the list of all such packages that exist.
      All of them are optional dependencies. *)
  val all_optionally : (t -> target option) list -> target list
end = struct
  type t = {
    number : int option;
    name : string;
    main : target;
    embedded : target;
    client : target option;
    client_commands : target option;
    client_commands_registration : target option;
    baking_commands_registration : target option;
    plugin : target option;
    plugin_registerer : target option;
  }

  let make ?number ?client ?client_commands ?client_commands_registration
      ?baking_commands_registration ?plugin ?plugin_registerer ~name ~main
      ~embedded () =
    {
      number;
      name;
      main;
      embedded;
      client;
      client_commands;
      client_commands_registration;
      baking_commands_registration;
      plugin;
      plugin_registerer;
    }

  let all_rev : t list ref = ref []

  (* Add to the [Protocol.add] list used to link in the node, client, etc.
     Returns the protocol for easier composability. *)
  let register protocol =
    all_rev := protocol :: !all_rev ;
    protocol

  let mandatory what {main; _} = function
    | None ->
        failwith
          ("protocol " ^ name_for_errors main ^ " has no " ^ what ^ " package")
    | Some x -> x

  let number p = p.number

  let name p = p.name

  let main p = p.main

  let embedded p = p.embedded

  let embedded_opt p = Some p.embedded

  let client p = p.client

  let client_exn p = mandatory "client" p p.client

  let client_commands_registration p = p.client_commands_registration

  let baking_commands_registration p = p.baking_commands_registration

  let plugin p = p.plugin

  let plugin_exn p = mandatory "plugin" p p.plugin

  let plugin_registerer p = p.plugin_registerer

  let genesis =
    register
    @@ make
         ~name:"genesis"
         ~main:(todo "tezos-protocol-genesis")
         ~embedded:(todo "tezos-embedded-protocol-genesis")
         ~client:(todo "tezos-client-genesis")
         ()

  let _genesis_carthagenet =
    register
    @@ make
         ~name:"genesis-carthagenet"
         ~main:(todo "tezos-protocol-genesis-carthagenet")
         ~embedded:(todo "tezos-embedded-protocol-genesis-carthagenet")
         ~client:(todo "tezos-client-genesis-carthagenet")
         ()

  let demo_noops =
    register
    @@ make
         ~name:"demo-noops"
         ~main:(todo "tezos-protocol-demo-noops")
         ~embedded:(todo "tezos-embedded-protocol-demo-noops")
         ()

  let _demo_counter =
    register
    @@ make
         ~name:"demo-counter"
         ~main:(todo "tezos-protocol-demo-counter")
         ~embedded:(todo "tezos-embedded-protocol-demo-counter")
         ~client:(todo "tezos-client-demo-counter")
         ()

  let _000_Ps9mPmXa =
    register
    @@ make
         ~number:000
         ~name:"Ps9mPmXa"
         ~main:(todo "tezos-protocol-000-Ps9mPmXa")
         ~embedded:(todo "tezos-embedded-protocol-000-Ps9mPmXa")
         ~client:(todo "tezos-client-000-Ps9mPmXa")
         ()

  let _001_PtCJ7pwo =
    let client_commands = todo "tezos-client-001-PtCJ7pwo-commands" in
    register
    @@ make
         ~number:001
         ~name:"PtCJ7pwo"
         ~main:(todo "tezos-protocol-001-PtCJ7pwo")
         ~embedded:(todo "tezos-embedded-protocol-001-PtCJ7pwo")
         ~client:(todo "tezos-client-001-PtCJ7pwo")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-001-PtCJ7pwo-commands.registration")
         ()

  let _002_PsYLVpVv =
    let client_commands = todo "tezos-client-002-PsYLVpVv-commands" in
    register
    @@ make
         ~number:002
         ~name:"PsYLVpVv"
         ~main:(todo "tezos-protocol-002-PsYLVpVv")
         ~embedded:(todo "tezos-embedded-protocol-002-PsYLVpVv")
         ~client:(todo "tezos-client-002-PsYLVpVv")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-002-PsYLVpVv-commands.registration")
         ()

  let _003_PsddFKi3 =
    let client_commands = todo "tezos-client-003-PsddFKi3-commands" in
    register
    @@ make
         ~number:003
         ~name:"PsddFKi3"
         ~main:(todo "tezos-protocol-003-PsddFKi3")
         ~embedded:(todo "tezos-embedded-protocol-003-PsddFKi3")
         ~client:(todo "tezos-client-003-PsddFKi3")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-003-PsddFKi3-commands.registration")
         ()

  let _004_Pt24m4xi =
    let client_commands = todo "tezos-client-004-Pt24m4xi-commands" in
    register
    @@ make
         ~number:004
         ~name:"Pt24m4xi"
         ~main:(todo "tezos-protocol-004-Pt24m4xi")
         ~embedded:(todo "tezos-embedded-protocol-004-Pt24m4xi")
         ~client:(todo "tezos-client-004-Pt24m4xi")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-004-Pt24m4xi-commands.registration")
         ()

  let _005_PsBABY5H =
    register
    @@ make
         ~number:005
         ~name:"PsBABY5H"
         ~main:(todo "tezos-protocol-005-PsBABY5H")
         ~embedded:(todo "tezos-embedded-protocol-005-PsBABY5H")
         ()

  let _005_PsBabyM1 =
    let client_commands = todo "tezos-client-005-PsBabyM1-commands" in
    register
    @@ make
         ~number:005
         ~name:"PsBabyM1"
         ~main:(todo "tezos-protocol-005-PsBabyM1")
         ~embedded:(todo "tezos-embedded-protocol-005-PsBabyM1")
         ~client:(todo "tezos-client-005-PsBabyM1")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-005-PsBabyM1-commands.registration")
         ()

  let _006_PsCARTHA =
    let client_commands = todo "tezos-client-006-PsCARTHA-commands" in
    register
    @@ make
         ~number:006
         ~name:"PsCARTHA"
         ~main:(todo "tezos-protocol-006-PsCARTHA")
         ~embedded:(todo "tezos-embedded-protocol-006-PsCARTHA")
         ~client:(todo "tezos-client-006-PsCARTHA")
         ~client_commands
         ~client_commands_registration:
           (todo_sub
              client_commands
              "tezos-client-006-PsCARTHA-commands.registration")
         ()

  (* Starting from 007, all protocols follow the current conventions. *)

  (* Note the -registration instead of .registration, compared to previous protocols:
     the client command registration library is in a separate opam package. *)

  let make_modern ?number name =
    let full_name =
      match number with
      | None -> name
      | Some number -> Printf.sprintf "%03d-%s" number name
    in
    let todo x = Printf.ksprintf todo x in
    let todo_sub parent x = Printf.ksprintf (todo_sub parent) x in
    let baking_commands = todo "tezos-baking-%s-commands" full_name in
    make
      ?number
      ~name
      ~main:(todo "tezos-protocol-%s" full_name)
      ~embedded:(todo "tezos-embedded-protocol-%s" full_name)
      ~client:(todo "tezos-client-%s" full_name)
      ~client_commands:(todo "tezos-client-%s-commands" full_name)
      ~client_commands_registration:
        (todo "tezos-client-%s-commands-registration" full_name)
      ~baking_commands_registration:
        (todo_sub
           baking_commands
           "tezos-baking-%s-commands.registration"
           full_name)
      ~plugin:(todo "tezos-protocol-plugin-%s" full_name)
      ~plugin_registerer:(todo "tezos-protocol-plugin-%s-registerer" full_name)
      ()

  let active ?number name = register @@ make_modern ?number name

  let frozen ?number name =
    let p = make_modern ?number name in
    register {p with baking_commands_registration = None}

  let overridden ?number name =
    let p = make_modern ?number name in
    register
      {
        p with
        client = None;
        client_commands = None;
        client_commands_registration = None;
        baking_commands_registration = None;
        plugin = None;
        plugin_registerer = None;
      }

  let _007_PsDELPH1 = frozen ~number:007 "PsDELPH1"

  let _008_PtEdoTez = overridden ~number:008 "PtEdoTez"

  let _008_PtEdo2Zk = frozen ~number:008 "PtEdo2Zk"

  let _009_PsFLoren = frozen ~number:009 "PsFLoren"

  let _010_PtGRANAD = frozen ~number:010 "PtGRANAD"

  let _011_PtHangz2 = active ~number:011 "PtHangz2"

  let _012_Psithaca = active ~number:012 "Psithaca"

  let alpha = active "alpha"

  let all = List.rev !all_rev

  let active = List.filter (fun p -> p.baking_commands_registration <> None) all

  let all_optionally (get_packages : (t -> target option) list) =
    let get_all_packages_for_protocol_package_type
        (get_package : t -> target option) =
      List.map (fun protocol -> Option.to_list (get_package protocol)) all
      |> List.flatten
    in
    List.map get_all_packages_for_protocol_package_type get_packages
    |> List.flatten |> List.map optional
end

(* INTERNAL LIBS *)

let tezos_test_helpers =
  public_lib
    "tezos-test-helpers"
    ~path:"src/lib_test"
    ~internal_name:"lib_test"
    ~synopsis:"Tezos-agnostic test helpers"
    ~deps:[uri; fmt; qcheck_alcotest; alcotest; lwt; pure_splitmix]
    ~js_of_ocaml:[]
    ~ocaml:[At_least "4.08"]
    ~linkall:true
    ~dune:
      Dune.
        [
          (* This rule is necessary for `make lint-tests-pkg`, without it dune
             complains that the alias is empty. *)
          alias_rule "runtest_js" ~action:(S "progn");
        ]

let tezos_stdlib =
  public_lib
    "tezos-stdlib"
    ~path:"src/lib_stdlib"
    ~synopsis:"Tezos: yet-another local-extension of the OCaml standard library"
    ~deps:[hex; zarith; zarith_stubs_js; lwt]
    ~ocaml:[At_least "4.08"]
    ~js_of_ocaml:[]
    ~inline_tests:true
    ~preprocess:[PPS ppx_inline_test]

let _tezos_stdlib_tests =
  tests
    [
      "test_bits";
      "test_tzList";
      "test_bounded_heap";
      "test_tzString";
      "test_fallbackArray";
      "test_functionalArray";
    ]
    ~path:"src/lib_stdlib/test"
    ~opam:"src/lib_stdlib/tezos-stdlib"
    ~modes:[Native; JS]
    ~deps:
      [tezos_stdlib; alcotest; bigstring; tezos_test_helpers; qcheck_alcotest]
    ~opens:["Tezos_stdlib"]
    ~dune:
      Dune.
        [
          runtest_js ~package:"tezos-stdlib" ~name:"test_bits";
          runtest_js ~package:"tezos-stdlib" ~name:"test_tzList";
          runtest_js ~package:"tezos-stdlib" ~name:"test_bounded_heap";
          runtest_js ~package:"tezos-stdlib" ~name:"test_tzString";
          runtest_js ~package:"tezos-stdlib" ~name:"test_fallbackArray";
          runtest_js ~package:"tezos-stdlib" ~name:"test_functionalArray";
        ]

let _tezos_stdlib_unix_tests =
  tests
    ["test_lwt_pipe"; "test_circular_buffer"; "test_circular_buffer_fuzzy"]
    ~path:"src/lib_stdlib/test-unix"
    ~opam:"src/lib_stdlib/tezos-stdlib"
    ~deps:
      [
        tezos_stdlib;
        alcotest;
        alcotest_lwt;
        lwt_log;
        bigstring;
        lwt_unix;
        tezos_test_helpers;
        qcheck_alcotest;
      ]
    ~opens:["Tezos_stdlib"]

let tezos_lwt_result_stdlib_bare_functor_outputs =
  public_lib
    "tezos-lwt-result-stdlib.bare.functor-outputs"
    ~path:"src/lib_lwt_result_stdlib/bare/functor_outputs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"bare_functor_outputs"
    ~js_of_ocaml:[]
    ~deps:[lwt]

let tezos_lwt_result_stdlib_bare_sigs =
  public_lib
    "tezos-lwt-result-stdlib.bare.sigs"
    ~path:"src/lib_lwt_result_stdlib/bare/sigs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"bare_sigs"
    ~js_of_ocaml:[]
    ~deps:[lwt; tezos_lwt_result_stdlib_bare_functor_outputs]

let tezos_lwt_result_stdlib_bare_structs =
  public_lib
    "tezos-lwt-result-stdlib.bare.structs"
    ~path:"src/lib_lwt_result_stdlib/bare/structs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"bare_structs"
    ~js_of_ocaml:[]
    ~deps:[lwt; tezos_lwt_result_stdlib_bare_sigs]

let tezos_lwt_result_stdlib_traced_functor_outputs =
  public_lib
    "tezos-lwt-result-stdlib.traced.functor-outputs"
    ~path:"src/lib_lwt_result_stdlib/traced/functor_outputs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"traced_functor_outputs"
    ~js_of_ocaml:[]
    ~deps:[lwt; tezos_lwt_result_stdlib_bare_sigs]

let tezos_lwt_result_stdlib_traced_sigs =
  public_lib
    "tezos-lwt-result-stdlib.traced.sigs"
    ~path:"src/lib_lwt_result_stdlib/traced/sigs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"traced_sigs"
    ~js_of_ocaml:[]
    ~deps:
      [
        lwt;
        tezos_lwt_result_stdlib_bare_sigs;
        tezos_lwt_result_stdlib_bare_structs;
        tezos_lwt_result_stdlib_traced_functor_outputs;
      ]

let tezos_lwt_result_stdlib_traced_structs =
  public_lib
    "tezos-lwt-result-stdlib.traced.structs"
    ~path:"src/lib_lwt_result_stdlib/traced/structs"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"traced_structs"
    ~js_of_ocaml:[]
    ~deps:
      [
        lwt;
        tezos_lwt_result_stdlib_traced_sigs;
        tezos_lwt_result_stdlib_bare_structs;
      ]

let tezos_lwt_result_stdlib =
  public_lib
    "tezos-lwt-result-stdlib"
    ~path:"src/lib_lwt_result_stdlib"
    ~synopsis:"Tezos: error-aware stdlib replacement"
    ~ocaml:[At_least "4.12"]
    ~js_of_ocaml:[]
    ~deps:
      [
        lwt;
        tezos_lwt_result_stdlib_bare_sigs;
        tezos_lwt_result_stdlib_bare_structs;
        tezos_lwt_result_stdlib_traced_sigs;
        tezos_lwt_result_stdlib_traced_structs;
      ]

let tezos_lwt_result_stdlib_examples_traces =
  public_lib
    "tezos-lwt-result-stdlib.examples.traces"
    ~path:"src/lib_lwt_result_stdlib/examples/traces"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~internal_name:"traces"
    ~deps:
      [
        lwt;
        tezos_lwt_result_stdlib_bare_structs;
        tezos_lwt_result_stdlib_traced_sigs;
      ]

let _tezos_lwt_result_stdlib_tests =
  tests
    [
      "test_hashtbl";
      "test_list_basic";
      "test_seq_basic";
      "test_generic";
      "test_fuzzing_seq";
      "test_fuzzing_list";
      "test_fuzzing_set";
      "test_fuzzing_seq_tiered";
      "test_fuzzing_option";
    ]
    ~path:"src/lib_lwt_result_stdlib/test"
    ~opam:"src/lib_lwt_result_stdlib/tezos-lwt-result-stdlib"
    ~deps:
      [
        tezos_lwt_result_stdlib;
        tezos_lwt_result_stdlib_examples_traces;
        lwt_unix;
        alcotest_lwt;
        qcheck_alcotest;
        tezos_test_helpers;
      ]
    ~opens:["Tezos_lwt_result_stdlib"]

let tezos_error_monad =
  public_lib
    "tezos-error-monad"
    ~path:"src/lib_error_monad"
    ~synopsis:"Tezos: error monad"
    ~ocaml:[At_least "4.07"]
    ~deps:
      [tezos_stdlib; data_encoding; lwt_canceler; lwt; tezos_lwt_result_stdlib]
    ~js_of_ocaml:[]
    ~opens:["Tezos_stdlib"; "Data_encoding"]

(* NOTE: tezos_*_glue are virtual packages;
   either the unix or js implementation must be installed. *)
let tezos_hacl_glue =
  public_lib
    "tezos-hacl-glue"
    ~path:"src/lib_hacl_glue/virtual"
    ~synopsis:"Tezos: thin layer of glue around hacl-star (virtual package)"
    ~ocaml:[At_least "4.08"]
    ~virtual_modules:["hacl"]

let tezos_hacl_glue_unix =
  public_lib
    "tezos-hacl-glue-unix"
    ~path:"src/lib_hacl_glue/unix"
    ~synopsis:"Tezos: thin layer of glue around hacl-star (unix implementation)"
    ~implements:tezos_hacl_glue
    ~deps:[hacl_star; hacl_star_raw]
    ~conflicts:[hacl_x25519]

let _tezos_hacl_glue_unix_tests =
  tests
    ["test_hacl"; "test_prop_hacl_hash"; "test_prop_signature_pk"]
    ~path:"src/lib_hacl_glue/unix/test"
    ~opam:"src/lib_hacl_glue/unix/tezos-hacl-glue-unix"
    ~deps:
      [
        tezos_stdlib;
        tezos_error_monad;
        zarith;
        zarith_stubs_js;
        tezos_hacl_glue;
        tezos_hacl_glue_unix;
        data_encoding;
        qcheck_alcotest;
        tezos_test_helpers;
      ]
    ~modes:[Native]
    ~js_of_ocaml:[]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_error_monad.TzLwtreslib";
        "Data_encoding";
        "Tezos_hacl_glue";
      ]

let hacl_star_raw_empty =
  public_lib
    "hacl-star-raw-empty"
    ~path:"src/lib_hacl_glue/js/src"
    ~opam:"src/lib_hacl_glue/js/hacl-star-raw-empty"
    ~synopsis:"Tezos: thin layer of glue around hacl-star (javascript version)"
    ~modules:[]
    ~foreign_stubs:{language = C; flags = []; names = ["hacl_star"]}

let tezos_hacl_glue_js =
  public_lib
    "tezos-hacl-glue-js"
    ~path:"src/lib_hacl_glue/js/src"
    ~opam:"src/lib_hacl_glue/js/tezos-hacl-glue-js"
    ~synopsis:"Tezos: thin layer of glue around hacl-star (javascript version)"
    ~implements:tezos_hacl_glue
    ~deps:[hacl_star_raw_empty]
    ~js_of_ocaml:[[S "javascript_files"; S "hacl_stubs.js"]]
    ~opam_only_deps:
      [(* Build dependency for users of the library. *) js_of_ocaml]
    ~modules:["hacl"]

(* We use virtual libraries, and want to compile the same test with
   unix and js. In order to do this, we copy tests from the unix
   directory and change the library providing the implementation of
   the virtual lib (tezos-hacl-glue-js) *)
let _tezos_hacl_glue_js_tests_1 =
  test_exes
    ["test_hacl"; "test_prop_signature_pk"]
    ~path:"src/lib_hacl_glue/js/test"
    ~opam:"src/lib_hacl_glue/js/tezos-hacl-glue-js"
    ~modes:[JS]
    ~deps:
      [
        tezos_stdlib;
        tezos_error_monad;
        zarith;
        zarith_stubs_js;
        tezos_hacl_glue;
        tezos_hacl_glue_js;
        data_encoding;
        qcheck_alcotest;
        tezos_test_helpers;
      ]
    ~all_modules_except:["test"]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_error_monad.TzLwtreslib";
        "Data_encoding";
        "Tezos_hacl_glue";
      ]

let _tezos_hacl_glue_js_tests_2 =
  test_exe
    "test"
    ~path:"src/lib_hacl_glue/js/test"
    ~opam:"src/lib_hacl_glue/js/tezos-hacl-glue-js"
    ~modes:[JS]
    ~deps:[tezos_hacl_glue_js]
    ~modules:["test"]
    ~dune:
      (let open Dune in
      let copy file =
        [
          S "rule";
          [
            S "action";
            [S "copy"; S ("../../unix/test/" ^ file); S (file ^ ".from-unix")];
          ];
        ]
      in
      let diff file =
        alias_rule
          "runtest_js"
          ~action:[S "diff"; S file; S (file ^ ".from-unix")]
      in
      let runtest hacl =
        alias_rule
          "runtest_js"
          ~package:"tezos-hacl-glue-js"
          ~deps:["../.npmrc"; "../package.json"; "../package-lock.json"]
          ~action:
            [
              S "progn";
              [S "run"; S "npm"; S "install"; S "hacl-wasm"];
              [
                S "run";
                S "%{dep:../../../tooling/node_wrapper.exe}";
                S "--hacl";
                S ("%{dep:./" ^ hacl ^ ".bc.js}");
              ];
            ]
      in
      [
        copy "test_hacl.ml";
        copy "vectors_p256.ml";
        copy "test_prop_signature_pk.ml";
        diff "test_hacl.ml";
        diff "vectors_p256.ml";
        diff "test_prop_signature_pk.ml";
        runtest "test";
        runtest "test_hacl";
        runtest "test_prop_signature_pk";
      ])

let _tezos_error_monad_tests =
  test
    "test_registration"
    ~path:"src/lib_error_monad/test"
    ~opam:"src/lib_error_monad/tezos-error-monad"
    ~modes:[Native; JS]
    ~deps:[tezos_error_monad; data_encoding; alcotest]
    ~opens:["Tezos_error_monad"]
    ~dune:
      Dune.
        [
          (* Idea: we could automatically generate this from the fact that
             ~modes contains JS *)
          runtest_js ~package:"tezos-error-monad" ~name:"test_registration";
        ]

let tezos_rpc =
  public_lib
    "tezos-rpc"
    ~path:"src/lib_rpc"
    ~synopsis:
      "Tezos: library of auto-documented RPCs (service and hierarchy \
       descriptions)"
    ~deps:[data_encoding; tezos_error_monad; resto; resto_directory]
    ~opens:["Data_encoding"; "Tezos_error_monad"]

let tezos_crypto =
  public_lib
    "tezos-crypto"
    ~path:"src/lib_crypto"
    ~synopsis:
      "Tezos: library with all the cryptographic primitives used by Tezos"
    ~deps:
      [
        data_encoding;
        tezos_lwt_result_stdlib;
        lwt;
        tezos_hacl_glue;
        secp256k1_internal;
        tezos_error_monad;
        tezos_rpc;
        tezos_stdlib;
        ringo;
        zarith;
        zarith_stubs_js;
      ]
    ~opens:
      [
        "Tezos_stdlib";
        "Data_encoding";
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
        "Tezos_rpc";
      ]

let _tezos_crypto_tests =
  tests
    ["test_run"; "test_prop_signature"]
    ~path:"src/lib_crypto/test"
    ~opam:"src/lib_crypto/tezos-crypto"
    ~deps:
      [
        tezos_crypto;
        tezos_stdlib;
        zarith;
        zarith_stubs_js;
        tezos_hacl_glue_unix;
        data_encoding;
        alcotest;
        alcotest_lwt;
        lwt_unix;
        qcheck_alcotest;
        tezos_test_helpers;
      ]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_crypto";
        "Tezos_error_monad.TzLwtreslib";
        "Data_encoding";
      ]

let tezos_event_logging =
  public_lib
    "tezos-event-logging"
    ~path:"src/lib_event_logging"
    ~synopsis:"Tezos event logging library"
    ~deps:
      [
        tezos_stdlib;
        data_encoding;
        tezos_error_monad;
        tezos_lwt_result_stdlib;
        lwt_log_core;
      ]
    ~js_of_ocaml:[]
    ~opens:
      [
        "Tezos_stdlib";
        "Data_encoding";
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
      ]

let tezos_event_logging_test_helpers =
  public_lib
    "tezos-event-logging-test-helpers"
    ~path:"src/lib_event_logging/test_helpers"
    ~synopsis:"Tezos: test helpers for the event logging library"
    ~deps:
      [
        tezos_stdlib;
        tezos_lwt_result_stdlib;
        data_encoding;
        tezos_error_monad;
        tezos_event_logging;
        tezos_test_helpers;
        alcotest;
      ]
    ~js_of_ocaml:[]
    ~linkall:true
    ~opens:
      [
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
        "Tezos_event_logging";
      ]
    ~bisect_ppx:false

let tezos_stdlib_unix =
  public_lib
    "tezos-stdlib-unix"
    ~path:"src/lib_stdlib_unix"
    ~synopsis:
      "Tezos: yet-another local-extension of the OCaml standard library \
       (unix-specific fragment)"
    ~deps:
      [
        unix;
        data_encoding;
        tezos_error_monad;
        tezos_lwt_result_stdlib;
        tezos_event_logging;
        tezos_stdlib;
        lwt_unix;
        ipaddr_unix;
        re;
        ezjsonm;
        ptime;
        ptime_clock_os;
        mtime;
        mtime_clock_os;
        lwt_log;
        conf_libev;
      ]
    ~opens:
      [
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
        "Tezos_event_logging";
        "Tezos_stdlib";
        "Data_encoding";
      ]

let tezos_clic =
  public_lib
    "tezos-clic"
    ~path:"src/lib_clic"
    ~synopsis:
      "Tezos: library of auto-documented command-line-parsing combinators"
    ~deps:[tezos_stdlib; lwt; re; tezos_error_monad; tezos_lwt_result_stdlib]
    ~opens:
      ["Tezos_stdlib"; "Tezos_error_monad"; "Tezos_error_monad.TzLwtreslib"]

let tezos_clic_unix =
  public_lib
    "tezos-clic.unix"
    ~path:"src/lib_clic/unix"
    ~opam:"src/lib_clic/tezos-clic"
    ~deps:
      [
        tezos_clic; tezos_stdlib_unix; tezos_error_monad; tezos_lwt_result_stdlib;
      ]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_clic";
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
      ]

let _tezos_clic_tests =
  test
    "test_clic"
    ~path:"src/lib_clic/test"
    ~opam:"src/lib_clic/tezos-clic"
    ~deps:[tezos_clic; alcotest_lwt]
    ~opens:["Tezos_stdlib"; "Tezos_clic"]

let tezos_micheline =
  public_lib
    "tezos-micheline"
    ~path:"src/lib_micheline"
    ~synopsis:"Tezos: internal AST and parser for the Michelson language"
    ~deps:
      [
        uutf;
        zarith;
        zarith_stubs_js;
        tezos_stdlib;
        tezos_error_monad;
        data_encoding;
      ]
    ~js_of_ocaml:[]
    ~opens:["Tezos_stdlib"; "Tezos_error_monad"; "Data_encoding"]
    ~inline_tests:true
    ~preprocess:[PPS ppx_inline_test]

let _tezos_micheline_tests =
  tests
    ["test_parser"; "test_diff"]
    ~path:"src/lib_micheline/test"
    ~opam:"src/lib_micheline/tezos-micheline"
    ~modes:[Native; JS]
    ~deps:[tezos_micheline; alcotest]
    ~opens:["Tezos_micheline"]
    ~dune:
      Dune.
        [
          runtest_js ~package:"tezos-micheline" ~name:"test_parser";
          runtest_js ~package:"tezos-micheline" ~name:"test_diff";
        ]

let tezos_base =
  public_lib
    "tezos-base"
    ~path:"src/lib_base"
    ~synopsis:"Tezos: meta-package and pervasive type definitions for Tezos"
    ~deps:
      [
        tezos_stdlib;
        tezos_crypto;
        data_encoding;
        tezos_error_monad;
        tezos_event_logging;
        tezos_rpc;
        tezos_clic;
        tezos_micheline;
        ptime;
        ezjsonm;
        lwt;
        ipaddr;
      ]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_crypto";
        "Data_encoding";
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
        "Tezos_rpc";
        "Tezos_clic";
        "Tezos_micheline";
        "Tezos_event_logging";
      ]
    ~dune:Dune.[ocamllex "point_parser"]

(* tezos-crypto depends on the tezos glue packages that
   are dune virtual packages and require an implementation.
   tezos-base.unix is used in many executables as a proxy to
   force linking of the unix implementation of the tezos crypto libraries. *)
let tezos_base_unix =
  public_lib
    "tezos-base.unix"
    ~path:"src/lib_base/unix"
    ~opam:"src/lib_base/tezos-base"
    ~deps:
      [
        data_encoding;
        tezos_crypto;
        bls12_381_unix;
        tezos_hacl_glue_unix (* unix implementation of hacl *);
        tezos_base;
        tezos_stdlib;
        tezos_stdlib_unix;
        tezos_error_monad;
      ]
    ~opens:
      [
        "Tezos_error_monad";
        "Tezos_crypto";
        "Tezos_base";
        "Tezos_stdlib";
        "Tezos_stdlib_unix";
        "Data_encoding";
      ]

let lib_base_tests ?dep_files names =
  tests
    names
    ~path:"src/lib_base/test"
    ~opam:"src/lib_base/tezos-base"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        data_encoding;
        qcheck_alcotest;
        tezos_test_helpers;
      ]
    ?dep_files
    ~opens:["Tezos_base"; "Tezos_error_monad"]
    ~modules:names

let _tezos_base_tests_1 = lib_base_tests ["test_time"; "test_protocol"]

let _tezos_base_tests_2 =
  lib_base_tests ["test_p2p_addr"] ~dep_files:["points.ok"; "points.ko"]

let _tezos_base_unix_tests =
  test
    "test_unix_error"
    ~path:"src/lib_base/unix/test"
    ~opam:"src/lib_base/tezos-base"
    ~deps:[tezos_base_unix; data_encoding; tezos_test_helpers; qcheck_alcotest]
    ~opens:["Tezos_base"; "Tezos_base_unix"; "Tezos_error_monad"]

let tezos_base_test_helpers =
  public_lib
    "tezos-base-test-helpers"
    ~path:"src/lib_base/test_helpers"
    ~synopsis:"Tezos: Tezos base test helpers"
    ~deps:
      [
        tezos_base;
        tezos_stdlib_unix;
        tezos_event_logging_test_helpers;
        tezos_test_helpers;
        alcotest;
        alcotest_lwt;
        qcheck_alcotest;
      ]
    ~linkall:true
    ~opens:["Tezos_base__TzPervasives"]
    ~bisect_ppx:false

let tezos_version =
  public_lib
    "tezos-version"
    ~path:"src/lib_version"
    ~synopsis:"Tezos: version information generated from Git"
    ~deps:[tezos_base]
    ~opens:["Tezos_base__TzPervasives"]
    ~dune:
      Dune.
        [
          (* Ensures the hash updates whenever a source file is modified. *)
          [
            S "rule";
            [S "targets"; S "generated_git_info.ml"];
            [S "deps"; [S "universe"]; [S ":script"; S "get-git-info.mlt"]];
            [
              S "action";
              [
                S "with-stdout-to";
                S "%{targets}";
                [S "run"; S "%{ocaml}"; S "unix.cma"; S "%{script}"];
              ];
            ];
          ];
        ]

let tezos_p2p_services =
  public_lib
    "tezos-p2p-services"
    ~path:"src/lib_p2p_services"
    ~synopsis:"Tezos: descriptions of RPCs exported by `tezos-p2p`"
    ~deps:[tezos_base]
    ~opens:["Tezos_base__TzPervasives"]
    ~linkall:true

let tezos_workers =
  public_lib
    "tezos-workers"
    ~path:"src/lib_workers"
    ~synopsis:"Tezos: worker library"
    ~deps:[tezos_base; tezos_stdlib_unix; ringo]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base"; "Tezos_stdlib_unix"]

let tezos_shell_services =
  public_lib
    "tezos-shell-services"
    ~path:"src/lib_shell_services"
    ~synopsis:"Tezos: descriptions of RPCs exported by `tezos-shell`"
    ~deps:
      [
        tezos_base;
        tezos_workers;
        tezos_stdlib_unix;
        tezos_p2p_services;
        tezos_version;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base";
        "Tezos_p2p_services";
        "Tezos_version";
      ]
    ~linkall:true

let _tezos_shell_services_tests =
  test
    "test"
    ~path:"src/lib_shell_services/test"
    ~opam:"src/lib_shell_services/tezos-shell-services"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_shell_services;
        alcotest_lwt;
      ]
    ~opens:
      ["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"; "Tezos_shell_services"]

let tezos_shell_services_test_helpers =
  public_lib
    "tezos-shell-services-test-helpers"
    ~path:"src/lib_shell_services/test_helpers"
    ~synopsis:"Tezos: Tezos shell_services test helpers"
    ~deps:[tezos_base; tezos_shell_services; tezos_test_helpers; qcheck_core]
    ~bisect_ppx:false
    ~opens:["Tezos_base__TzPervasives"]
    ~linkall:true

let _tezos_shell_service_test_helpers_tests =
  test
    "test_block_services"
    ~path:"src/lib_shell_services/test_helpers/test"
    ~opam:
      "src/lib_shell_services/test_helpers/tezos-shell-services-test-helpers"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_test_helpers;
        tezos_shell_services;
        tezos_shell_services_test_helpers;
        qcheck_alcotest;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"]

let tezos_tooling =
  public_lib
    "tezos-tooling"
    ~path:"src/tooling"
    ~synopsis:"Tezos: tooling for the project"
    ~modules:[]
    ~dune:
      Dune.
        [
          [
            S "install";
            [S "package"; S "tezos-tooling"];
            [S "section"; S "libexec"];
            [S "files"; [S "lint.sh"; S "as"; S "lint.sh"]];
          ];
        ]

let _tezos_tooling_js_inline_tests =
  test_exe
    "run_js_inline_tests"
    ~path:"src/tooling"
    ~opam:"src/tooling/tezos-tooling"
    ~modules:["run_js_inline_tests"]
    ~deps:[parsexp; unix]

let tezos_p2p =
  public_lib
    "tezos-p2p"
    ~path:"src/lib_p2p"
    ~synopsis:"Tezos: library for a pool of P2P connections"
    ~deps:
      [
        lwt_watcher;
        lwt_canceler;
        ringo;
        tezos_base;
        tezos_base_unix;
        tezos_stdlib;
        tezos_stdlib_unix;
        tezos_p2p_services;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base_unix";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
        "Tezos_p2p_services";
      ]

let _tezos_p2p_tests =
  test_exes
    [
      "test_p2p_socket";
      "test_p2p_pool";
      "test_p2p_io_scheduler";
      "test_p2p_peerset";
      "test_p2p_buffer_reader";
      "test_p2p_banned_peers";
      "test_p2p_node";
      (* Deactivated because it fails on CI (but not locally) *)
      (* See https://gitlab.com/tezos/tezos/-/issues/1184 *)
      (* "test_p2p_logging"; *)
      "test_p2p_connect_handler";
    ]
    ~path:"src/lib_p2p/test"
    ~opam:"src/lib_p2p/tezos-p2p"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_p2p;
        tezos_p2p_services;
        tezos_test_helpers;
        tezos_base_test_helpers;
        tezos_event_logging_test_helpers;
        alcotest_lwt;
        astring;
      ]
    ~opam_only_deps:[tezos_tooling]
    ~linkall:true
    ~preprocess:[PPS_args (bisect_ppx, ["--bisect-sigterm"])]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
        "Tezos_p2p";
        "Tezos_base_test_helpers";
        "Tezos_event_logging_test_helpers";
        "Tezos_p2p_services";
      ]
    ~dune:
      Dune.
        [
          alias_rule
            "runtest_p2p_socket"
            ~locks:"/ports/49152-65535"
            ~action:(run_exe "test_p2p_socket" []);
          alias_rule
            "runtest_p2p_pool"
            ~locks:"/ports/49152-65535"
            ~action:
              (run_exe "test_p2p_pool" ["--clients"; "10"; "--repeat"; "5"]);
          alias_rule
            "runtest_p2p_io_scheduler"
            ~locks:"/ports/49152-65535"
            ~action:
              (run_exe
                 "test_p2p_io_scheduler"
                 [
                   "--delay";
                   "5";
                   "--clients";
                   "8";
                   "--max-upload-speed";
                   "262144";
                   (* 1 << 18 = 256kB *)
                   "--max-download-speed";
                   "1048576";
                   (* 1 << 20 = 1MB *)
                 ]);
          alias_rule
            "runtest_p2p_socket_ipv4"
            ~locks:"/ports/49152-65535"
            ~action:(run_exe "test_p2p_socket" ["--addr"; "::ffff:127.0.0.1"]);
          alias_rule
            "runtest_p2p_pool_ipv4"
            ~locks:"/ports/49152-65535"
            ~action:
              (run_exe
                 "test_p2p_pool"
                 [
                   "--clients";
                   "10";
                   "--repeat";
                   "5";
                   "--addr";
                   "::ffff:127.0.0.1";
                 ]);
          alias_rule
            "runtest_p2p_io_scheduler_ipv4"
            ~locks:"/ports/49152-65535"
            ~action:
              (run_exe
                 "test_p2p_io_scheduler"
                 [
                   "--delay";
                   "5";
                   "--clients";
                   "8";
                   "--max-upload-speed";
                   "262144";
                   (* 1 << 18 = 256kB *)
                   "--max-download-speed";
                   "1048576";
                   (* 1 << 20 = 1MB *)
                   "--addr";
                   "::ffff:127.0.0.1";
                 ]);
          alias_rule
            "runtest_p2p_peerset"
            ~action:(run_exe "test_p2p_peerset" []);
          alias_rule
            "runtest_p2p_buffer_reader"
            ~action:(run_exe "test_p2p_buffer_reader" []);
          alias_rule
            "runtest_p2p_banned_peers"
            ~action:(run_exe "test_p2p_banned_peers" []);
          alias_rule
            "runtest_p2p_node"
            ~locks:"/ports/49152-65535"
            ~action:(run_exe "test_p2p_node" []);
          alias_rule
            "runtest_p2p_connect_handler"
            ~action:(run_exe "test_p2p_connect_handler" []);
          alias_rule
            "runtest"
            ~package:"tezos-p2p"
            ~alias_deps:
              [
                "runtest_p2p_socket_ipv4";
                "runtest_p2p_pool_ipv4";
                "runtest_p2p_io_scheduler_ipv4";
                "runtest_p2p_peerset";
                "runtest_p2p_buffer_reader";
                "runtest_p2p_banned_peers";
                "runtest_p2p_node";
                "runtest_p2p_connect_handler";
              ];
        ]

let tezos_context_sigs =
  public_lib
    "tezos-context.sigs"
    ~path:"src/lib_context/sigs"
    ~opam:"src/lib_context/tezos-context"
    ~deps:[tezos_base]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib"]

let tezos_context_encoding =
  public_lib
    "tezos-context.encoding"
    ~path:"src/lib_context/encoding"
    ~opam:"src/lib_context/tezos-context"
    ~deps:[tezos_base; irmin; irmin_pack]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib"]

let tezos_context_helpers =
  public_lib
    "tezos-context.helpers"
    ~path:"src/lib_context/helpers"
    ~opam:"src/lib_context/tezos-context"
    ~deps:
      [
        tezos_base; tezos_context_encoding; tezos_context_sigs; irmin; irmin_pack;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib"]

let tezos_context_memory =
  public_lib
    "tezos-context.memory"
    ~path:"src/lib_context/memory"
    ~opam:"src/lib_context/tezos-context"
    ~deps:
      [
        tezos_base;
        irmin_pack_mem;
        tezos_context_sigs;
        tezos_context_encoding;
        tezos_context_helpers;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib"]

let tezos_context =
  public_lib
    "tezos-context"
    ~path:"src/lib_context"
    ~synopsis:"Tezos: on-disk context abstraction for `tezos-node`"
    ~deps:
      [
        tezos_base;
        bigstringaf;
        tezos_shell_services;
        fmt;
        logs_fmt;
        digestif_c;
        irmin;
        irmin_pack;
        tezos_stdlib_unix;
        tezos_context_sigs;
        tezos_context_helpers;
        tezos_context_encoding;
      ]
    ~opens:
      [
        "Tezos_shell_services";
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
      ]

let _tezos_context_tests =
  test
    "test"
    ~path:"src/lib_context/test"
    ~opam:"src/lib_context/tezos-context"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_context;
        tezos_stdlib_unix;
        alcotest_lwt;
        vector;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_context"; "Tezos_stdlib_unix"]

let _tezos_context_memory_tests =
  test
    "test"
    ~path:"src/lib_context/memory/test"
    ~opam:"src/lib_context/tezos-context"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_context;
        tezos_context_memory;
        tezos_stdlib_unix;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"]

(* This binding assumes that librustzcash.a is installed in the system default
   directories or in: $OPAM_SWITCH_PREFIX/lib *)
let tezos_sapling =
  public_lib
    "tezos-sapling"
    ~path:"src/lib_sapling"
    ~synopsis:"OCaml library for the Sapling protocol, using librustzcash"
    ~deps:
      [
        conf_rust;
        integers;
        ctypes;
        ctypes_stubs;
        data_encoding;
        tezos_crypto;
        tezos_stdlib;
        tezos_error_monad;
        tezos_rust_lib;
        tezos_lwt_result_stdlib;
      ]
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_crypto";
        "Tezos_error_monad";
        "Tezos_error_monad.TzLwtreslib";
      ]
    ~foreign_stubs:
      {
        language = C;
        flags =
          [":standard"; "-I%{env:OPAM_SWITCH_PREFIX=}/lib/tezos-rust-libs"];
        names = ["rustzcash_ctypes_c_stubs"];
      }
    ~c_library_flags:
      [
        "-L%{env:OPAM_SWITCH_PREFIX=}/lib/tezos-rust-libs";
        "-lrustzcash";
        "-lpthread";
      ]
    ~dune:
      Dune.
        [
          [
            S "copy_files";
            S
              "bindings/{rustzcash_ctypes_c_stubs.c,rustzcash_ctypes_stubs.ml,rustzcash_ctypes_bindings.ml}";
          ];
        ]

let _tezos_sapling_tests =
  tests
    ["test_rustzcash"; "test_keys"; "test_merkle"; "test_roots"; "test_sapling"]
    ~path:"src/lib_sapling/test"
    ~opam:"src/lib_sapling/tezos-sapling"
    ~dep_files:["vectors.csv"; "vectors-zip32.csv"]
    ~deps:
      [
        tezos_sapling;
        str;
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_base_test_helpers;
        alcotest_lwt;
      ]
    ~opens:
      [
        "Tezos_sapling";
        "Tezos_crypto";
        "Tezos_stdlib";
        "Data_encoding";
        "Tezos_base_test_helpers";
      ]
    ~dune:
      Dune.
        [
          [
            S "env";
            [S "dev"; [S "flags"; [S ":standard"; S "-warn-error"; S "-A"]]];
          ];
        ]

let _rustzcash_ctypes_gen =
  private_exe
    "rustzcash_ctypes_gen"
    ~path:"src/lib_sapling/bindings"
    ~opam:"src/lib_sapling/tezos-sapling"
    ~bisect_ppx:false
    ~deps:[ctypes_stubs; ctypes]
    ~modules:["rustzcash_ctypes_gen"; "rustzcash_ctypes_bindings"]
    ~dune:
      Dune.
        [
          [
            S "rule";
            [
              S "targets";
              S "rustzcash_ctypes_stubs.ml";
              S "rustzcash_ctypes_c_stubs.c";
            ];
            [S "deps"; [S ":gen"; S "./rustzcash_ctypes_gen.exe"]];
            [S "action"; run "%{gen}" ["%{targets}"]];
          ];
        ]

let tezos_protocol_environment_packer =
  public_lib
    "tezos-protocol-environment-packer"
    ~path:"src/lib_protocol_environment/s_packer"
    ~opam:"src/lib_protocol_environment/tezos-protocol-environment-packer"
    ~ocaml:[At_least "4.03"]
    ~synopsis:"Tezos: sigs/structs packer for economic protocol environment"
    ~modules:[]

let tezos_protocol_environment_sigs =
  public_lib
    "tezos-protocol-environment-sigs"
    ~path:"src/lib_protocol_environment/sigs"
    ~opam:"src/lib_protocol_environment/tezos-protocol-environment-sigs"
    ~ocaml:[At_least "4.12"]
    ~synopsis:"Tezos: restricted typing environment for the economic protocols"
    ~opam_only_deps:
      [
        (* Build dependency but not for the (library) itself,
           it's from one of the .inc files. *)
        tezos_protocol_environment_packer;
      ]
    ~nopervasives:true
    ~modules:["V0"; "V1"; "V2"; "V3"; "V4"; "V5"]
    ~dune:
      Dune.
        [
          include_ "v0.dune.inc";
          include_ "v1.dune.inc";
          include_ "v2.dune.inc";
          include_ "v3.dune.inc";
          include_ "v4.dune.inc";
          include_ "v5.dune.inc";
        ]

let tezos_protocol_environment_structs =
  public_lib
    "tezos-protocol-environment-structs"
    ~path:"src/lib_protocol_environment/structs"
    ~opam:"src/lib_protocol_environment/tezos-protocol-environment-structs"
    ~synopsis:"Tezos: restricted typing environment for the economic protocols"
    ~deps:
      [
        tezos_stdlib;
        tezos_crypto;
        tezos_lwt_result_stdlib;
        data_encoding;
        bls12_381_legacy;
      ]
    ~opam_only_deps:
      [
        (* Build dependency but not for the (library) itself,
           it's from one of the .inc files. *)
        tezos_protocol_environment_packer;
      ]
    ~modules:["V0"; "V1"; "V2"; "V3"; "V4"; "V5"]
    ~dune:
      Dune.
        [
          include_ "v0.dune.inc";
          include_ "v1.dune.inc";
          include_ "v2.dune.inc";
          include_ "v3.dune.inc";
          include_ "v4.dune.inc";
          include_ "v5.dune.inc";
        ]

let tezos_protocol_environment =
  public_lib
    "tezos-protocol-environment"
    ~path:"src/lib_protocol_environment"
    ~synopsis:
      "Tezos: custom economic-protocols environment implementation for \
       `tezos-client` and testing"
    ~deps:
      [
        zarith;
        zarith_stubs_js;
        bls12_381;
        tezos_base;
        tezos_sapling;
        tezos_protocol_environment_sigs;
        tezos_protocol_environment_structs;
        tezos_micheline;
        tezos_context_memory;
        tezos_event_logging;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_micheline"]
    ~wrapped:false
    ~modules:
      [
        "Tezos_protocol_environment";
        "Environment_V0";
        "Environment_V1";
        "Environment_V2";
        "Environment_V3";
        "Environment_V4";
        "Environment_V5";
        "Environment_cache";
        "Environment_context";
        "Environment_context_intf";
        "Environment_protocol_T";
        "Environment_protocol_T_V0";
        "Environment_protocol_T_V3";
        "Environment_protocol_T_test";
        "Dummy_context";
        "Memory_context";
        "Proxy_context";
      ]

let _tezos_protocol_environment_tests =
  tests
    ["test"; "test_mem_context_array_theory"; "test_cache"]
    ~path:"src/lib_protocol_environment/test"
    ~opam:"src/lib_protocol_environment/tezos-protocol-environment"
    ~deps:
      [
        bls12_381_unix;
        tezos_base_unix;
        tezos_protocol_environment;
        alcotest_lwt;
        tezos_test_helpers;
        qcheck_alcotest;
        lwt_unix;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_protocol_environment"]

let tezos_shell_context =
  public_lib
    "tezos-shell-context"
    ~path:"src/lib_protocol_environment"
    ~synopsis:
      "Tezos: economic-protocols environment implementation for `tezos-node`"
    ~deps:[tezos_base; tezos_protocol_environment; tezos_context]
    ~modules:["Shell_context"]

let tezos_protocol_compiler_registerer =
  public_lib
    "tezos-protocol-compiler.registerer"
    ~path:"src/lib_protocol_compiler"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~internal_name:"tezos_protocol_registerer"
    ~deps:[tezos_base; tezos_protocol_environment_sigs]
    ~opens:["Tezos_base__TzPervasives"]
    ~modules:["Registerer"]
    ~opaque:true
    ~dune:
      [
        [
          S "rule";
          [S "targets"; S "embedded_cmis.ml"];
          [
            S "action";
            [
              S "run";
              G
                [
                  S "%{bin:ocp-ocamlres}";
                  S "-format";
                  S "ocaml";
                  S "-o";
                  S "%{targets}";
                ];
              S "%{lib:stdlib:camlinternalFormatBasics.cmi}";
              S
                "%{dep:.tezos_protocol_registerer.objs/byte/tezos_protocol_registerer__Registerer.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V0.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V1.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V2.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V3.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V4.cmi}";
              S
                "%{lib:tezos-protocol-environment-sigs:tezos_protocol_environment_sigs__V5.cmi}";
            ];
          ];
        ];
      ]

let tezos_protocol_compiler_lib =
  public_lib
    "tezos-protocol-compiler"
    ~path:"src/lib_protocol_compiler"
    ~synopsis:"Tezos: economic-protocol compiler"
    ~ocaml:
      [
        (* Should be in sync with scripts/version.sh *)
        At_least "4.12.0";
        Less_than "4.13";
      ]
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_version;
        tezos_protocol_environment_sigs;
        tezos_stdlib_unix;
        compiler_libs_common;
        lwt_unix;
        ocplib_ocamlres;
        unix;
      ]
    ~opam_only_deps:[tezos_protocol_environment]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base_unix"; "Tezos_stdlib_unix"]
    ~modules:["Embedded_cmis"; "Packer"; "Compiler"]

let tezos_protocol_compiler_native =
  public_lib
    "tezos-protocol-compiler.native"
    ~path:"src/lib_protocol_compiler"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~deps:[tezos_base; tezos_protocol_compiler_lib; compiler_libs_optcomp]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_protocol_compiler"]
    ~modules:["Native"]
    ~dune:
      [
        [
          S "install";
          [S "section"; S "libexec"];
          [
            S "files";
            S "dune_protocol.v0";
            S "dune_protocol.v1";
            S "dune_protocol.template.v0";
            S "dune_protocol.template.v1";
            S "final_protocol_versions";
          ];
        ];
      ]

let tezos_protocol_updater =
  public_lib
    "tezos-protocol-updater"
    ~path:"src/lib_protocol_updater"
    ~synopsis:"Tezos: economic-protocol dynamic loading for `tezos-node`"
    ~deps:
      [
        tezos_base;
        tezos_stdlib_unix;
        tezos_micheline;
        tezos_shell_services;
        tezos_protocol_environment;
        tezos_shell_context;
        tezos_protocol_compiler_registerer;
        tezos_protocol_compiler_native;
        tezos_context;
        lwt_exit;
        dynlink;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_micheline";
        "Tezos_shell_services";
        "Tezos_context";
      ]

let tezos_validation =
  public_lib
    "tezos-validation"
    ~path:"src/lib_validation"
    ~synopsis:"Tezos: library for blocks validation"
    ~deps:
      [
        tezos_base;
        tezos_context;
        tezos_shell_context;
        tezos_shell_services;
        tezos_protocol_updater;
        tezos_stdlib_unix;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_context";
        "Tezos_shell_context";
        "Tezos_shell_services";
        "Tezos_protocol_updater";
        "Tezos_stdlib_unix";
      ]

let tezos_store =
  public_lib
    "tezos-store"
    ~path:"src/lib_store"
    ~synopsis:"Tezos: store for `tezos-node`"
    ~deps:
      [
        tezos_base;
        tezos_shell_services;
        index;
        irmin_pack;
        tezos_stdlib_unix;
        tezos_context;
        tezos_validation;
        tezos_protocol_updater;
        lwt_watcher;
        ringo_lwt;
        camlzip;
        tar;
        tar_unix;
        prometheus;
      ]
    ~opens:
      [
        "Tezos_shell_services";
        "Tezos_base";
        "Tezos_base__TzPervasives";
        "Tezos_context";
        "Tezos_validation";
        "Tezos_protocol_updater";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
      ]

let _tezos_store_tests =
  test_exes
    ["test"]
    ~path:"src/lib_store/test"
    ~opam:"src/lib_store/tezos-store"
    ~deps:
      [
        tezos_base;
        tezos_store;
        tezos_stdlib_unix;
        Protocol.(embedded demo_noops);
        Protocol.(embedded genesis);
        Protocol.(embedded alpha);
        tezos_protocol_alpha_parameters;
        Protocol.(plugin_exn alpha);
        tezos_validation;
        alcotest_lwt;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_store";
        "Tezos_shell_services";
        "Tezos_stdlib_unix";
        "Tezos_validation";
        "Tezos_protocol_alpha_parameters";
        "Tezos_protocol_plugin_alpha";
      ]
    ~dune:
      Dune.
        [
          alias_rule
            "runtest_store"
            ~action:(setenv "SLOW_TEST" "false" @@ run_exe "test" []);
        ]

let tezos_requester =
  public_lib
    "tezos-requester"
    ~path:"src/lib_requester"
    ~synopsis:"Tezos: generic resource fetching service"
    ~deps:[tezos_base; tezos_stdlib_unix; lwt_watcher]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"]

let _tezos_requester_tests =
  tests
    ["test_requester"; "test_fuzzing_requester"]
    ~path:"src/lib_requester/test"
    ~opam:"src/lib_requester/tezos-requester"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_test_helpers;
        tezos_base_test_helpers;
        tezos_stdlib_unix;
        tezos_requester;
        alcotest_lwt;
        qcheck_alcotest;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base_test_helpers";
        "Tezos_stdlib";
        "Tezos_requester";
      ]

let tezos_shell =
  public_lib
    "tezos-shell"
    ~path:"src/lib_shell"
    ~synopsis:
      "Tezos: core of `tezos-node` (gossip, validation scheduling, mempool, \
       ...)"
    ~deps:
      [
        lwt_watcher;
        lwt_canceler;
        tezos_base;
        tezos_version;
        tezos_context;
        tezos_store;
        tezos_shell_context;
        tezos_p2p;
        tezos_stdlib_unix;
        tezos_shell_services;
        tezos_p2p_services;
        tezos_protocol_updater;
        tezos_requester;
        tezos_workers;
        tezos_validation;
        lwt_exit;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base";
        "Tezos_context";
        "Tezos_store";
        "Tezos_shell_context";
        "Tezos_p2p";
        "Tezos_stdlib_unix";
        "Tezos_shell_services";
        "Tezos_p2p_services";
        "Tezos_protocol_updater";
        "Tezos_requester";
        "Tezos_workers";
        "Tezos_validation";
        "Tezos_version";
      ]

let _tezos_shell_tests =
  tests
    [
      "test_shell";
      "test_locator";
      "test_synchronisation_heuristic_fuzzy";
      "test_prevalidation";
      "test_prevalidation_t";
      "test_prevalidator_classification";
      "test_prevalidator_classification_operations";
      "test_prevalidator_pending_operations";
    ]
    ~path:"src/lib_shell/test"
    ~opam:"src/lib_shell/tezos-shell"
    ~deps:
      [
        tezos_base;
        tezos_base_test_helpers;
        tezos_store;
        tezos_context;
        tezos_shell_context;
        tezos_p2p;
        tezos_p2p_services;
        tezos_protocol_updater;
        tezos_requester;
        tezos_shell;
        tezos_shell_services;
        Protocol.(embedded demo_noops);
        tezos_stdlib_unix;
        tezos_validation;
        tezos_event_logging_test_helpers;
        tezos_test_helpers;
        alcotest_lwt;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base_test_helpers";
        "Tezos_store";
        "Tezos_context";
        "Tezos_shell_context";
        "Tezos_protocol_updater";
        "Tezos_p2p";
        "Tezos_p2p_services";
        "Tezos_shell";
        "Tezos_shell_services";
        "Tezos_stdlib_unix";
        "Tezos_validation";
        "Tezos_event_logging_test_helpers";
      ]
    ~dune:
      Dune.
        [
          alias_rule
            "runtest_locator_bench"
            ~package:"tezos-shell"
            ~action:(run_exe "test_locator" ["--bench"]);
        ]

let _tezos_shell_benchs =
  tests
    ["bench_simple"; "bench_tool"]
    ~path:"src/lib_shell/bench"
    ~opam:"src/lib_shell/tezos-shell"
    ~deps:
      [
        tezos_base;
        tezos_shell;
        tezos_alpha_test_helpers;
        Protocol.(plugin_exn alpha);
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_shell";
        "Tezos_protocol_alpha";
        "Tezos_protocol_plugin_alpha";
        "Tezos_protocol_alpha_parameters";
        "Tezos_alpha_test_helpers";
      ]

let tezos_rpc_http =
  public_lib
    "tezos-rpc-http"
    ~path:"src/lib_rpc_http"
    ~synopsis:"Tezos: library of auto-documented RPCs (http server and client)"
    ~deps:[tezos_base; resto_cohttp]
    ~opens:["Tezos_base__TzPervasives"]
    ~modules:["RPC_client_errors"; "media_type"]

let tezos_rpc_http_client =
  public_lib
    "tezos-rpc-http-client"
    ~path:"src/lib_rpc_http"
    ~synopsis:"Tezos: library of auto-documented RPCs (http client)"
    ~deps:[tezos_base; resto_cohttp_client; tezos_rpc_http]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_rpc_http"]
    ~modules:["RPC_client"]

let tezos_rpc_http_client_unix =
  public_lib
    "tezos-rpc-http-client-unix"
    ~path:"src/lib_rpc_http"
    ~synopsis:"Tezos: unix implementation of the RPC client"
    ~deps:
      [
        tezos_stdlib_unix;
        tezos_base;
        cohttp_lwt_unix;
        resto_cohttp_client;
        tezos_rpc_http_client;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_rpc_http_client"]
    ~modules:["RPC_client_unix"]

let tezos_rpc_http_server =
  public_lib
    "tezos-rpc-http-server"
    ~path:"src/lib_rpc_http"
    ~synopsis:"Tezos: library of auto-documented RPCs (http server)"
    ~deps:
      [
        tezos_base;
        tezos_stdlib_unix;
        resto_cohttp_server;
        resto_acl;
        tezos_rpc_http;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_rpc";
        "Tezos_rpc_http";
      ]
    ~modules:["RPC_server"; "RPC_logging"]
    ~private_modules:["RPC_logging"]

let _tezos_rpc_http_server_tests =
  test
    "test_rpc_http"
    ~path:"src/lib_rpc_http/test"
    ~opam:"src/lib_rpc_http/tezos-rpc-http-server"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_rpc_http_server;
        tezos_base_test_helpers;
        tezos_test_helpers;
        qcheck_alcotest;
        alcotest_lwt;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib";
        "Lib_test";
        "Tezos_base_test_helpers";
        "Tezos_rpc_http_server";
      ]

let tezos_validator_lib =
  public_lib
    "tezos-validator"
    ~path:"src/bin_validation"
    ~synopsis:
      "Tezos: `tezos-validator` binary for external validation of blocks"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_context;
        tezos_stdlib_unix;
        tezos_protocol_environment;
        tezos_protocol_updater;
        tezos_shell;
        tezos_shell_context;
        tezos_validation;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_context";
        "Tezos_stdlib_unix";
        "Tezos_shell";
        "Tezos_shell_services";
        "Tezos_validation";
        "Tezos_protocol_updater";
        "Tezos_shell_context";
      ]

let tezos_client_base =
  public_lib
    "tezos-client-base"
    ~path:"src/lib_client_base"
    ~synopsis:"Tezos: common helpers for `tezos-client`"
    ~deps:[tezos_base; tezos_shell_services; tezos_sapling; tezos_rpc]
    ~modules:[":standard"; "bip39_english"]
    ~linkall:true
    ~opens:["Tezos_base__TzPervasives"; "Tezos_rpc"; "Tezos_shell_services"]
    ~dune:
      Dune.
        [
          [
            S "rule";
            [S "targets"; S "bip39_english.ml"];
            [
              S "deps";
              [S ":exe"; S "gen/bip39_generator.exe"];
              S "gen/bip39_english.txt";
            ];
            [S "action"; [S "run"; S "%{exe}"; S "%{targets}"]];
          ];
        ]

let _tezos_client_base_tests =
  tests
    ["bip39_tests"; "pbkdf_tests"]
    ~path:"src/lib_client_base/test"
    ~opam:"src/lib_client_base/tezos-client-base"
    ~deps:[tezos_base; tezos_base_unix; tezos_client_base; alcotest]
    ~opens:["Tezos_client_base"]

let _bip39_generator =
  private_exe
    "bip39_generator"
    ~path:"src/lib_client_base/gen"
    ~opam:"src/lib_client_base/tezos-client-base"
    ~bisect_ppx:false

let tezos_signer_services =
  public_lib
    "tezos-signer-services"
    ~path:"src/lib_signer_services"
    ~synopsis:"Tezos: descriptions of RPCs exported by `tezos-signer`"
    ~deps:[tezos_base; tezos_client_base; tezos_rpc]
    ~linkall:true
    ~opens:["Tezos_base__TzPervasives"; "Tezos_rpc"; "Tezos_client_base"]

let tezos_signer_backends =
  public_lib
    "tezos-signer-backends"
    ~path:"src/lib_signer_backends"
    ~synopsis:"Tezos: remote-signature backends for `tezos-client`"
    ~deps:
      [
        tezos_base;
        tezos_stdlib;
        tezos_client_base;
        tezos_rpc_http_client;
        tezos_signer_services;
        tezos_shell_services;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib";
        "Tezos_client_base";
        "Tezos_rpc_http";
        "Tezos_rpc_http_client";
        "Tezos_signer_services";
        "Tezos_shell_services";
      ]

let _tezos_signer_backends_tests =
  test
    "test_encrypted"
    ~path:"src/lib_signer_backends/test"
    ~opam:"src/lib_signer_backends/tezos-signer-backends"
    ~deps:[tezos_base; tezos_base_unix; tezos_signer_backends; alcotest_lwt]
    ~opens:
      [
        "Tezos_error_monad";
        "Tezos_stdlib";
        "Tezos_error_monad.TzLwtreslib";
        "Tezos_crypto";
        "Tezos_client_base";
        "Tezos_signer_backends";
      ]

let tezos_signer_backends_unix =
  public_lib
    "tezos-signer-backends.unix"
    ~path:"src/lib_signer_backends/unix"
    ~opam:"src/lib_signer_backends/tezos-signer-backends"
    ~deps:
      [
        ocplib_endian_bigstring;
        fmt;
        tezos_signer_backends;
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_rpc_http_client_unix;
        select
          ~package:ledgerwallet_tezos
          ~source_if_present:"ledger.available.ml"
          ~source_if_absent:"ledger.none.ml"
          ~target:"ledger.ml";
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
        "Tezos_client_base";
        "Tezos_rpc_http";
        "Tezos_rpc_http_client";
        "Tezos_rpc_http_client_unix";
        "Tezos_signer_services";
        "Tezos_signer_backends";
        "Tezos_shell_services";
      ]

let _tezos_signer_backends_unix_tests =
  test
    "test_crouching"
    ~path:"src/lib_signer_backends/unix/test"
    ~opam:"src/lib_signer_backends/tezos-signer-backends"
    ~deps:[tezos_signer_backends_unix; alcotest_lwt]
    ~opens:
      [
        "Tezos_error_monad";
        "Tezos_stdlib";
        "Tezos_crypto";
        "Tezos_client_base";
        "Tezos_signer_backends_unix";
      ]

let tezos_client_commands =
  public_lib
    "tezos-client-commands"
    ~path:"src/lib_client_commands"
    ~synopsis:"Tezos: protocol agnostic commands for `tezos-client`"
    ~deps:
      [
        tezos_base;
        tezos_client_base;
        tezos_clic_unix;
        tezos_rpc;
        tezos_shell_services;
        tezos_p2p_services;
        tezos_stdlib_unix;
        tezos_signer_backends;
        data_encoding;
      ]
    ~linkall:true
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_rpc";
        "Tezos_clic_unix";
        "Tezos_client_base";
        "Tezos_shell_services";
        "Tezos_p2p_services";
        "Data_encoding";
      ]

let tezos_mockup_registration =
  public_lib
    "tezos-mockup-registration"
    ~path:"src/lib_mockup"
    ~synopsis:"Tezos: protocol registration for the mockup mode"
    ~deps:
      [
        tezos_base;
        tezos_client_base;
        tezos_shell_services;
        tezos_protocol_environment;
      ]
    ~opens:["Tezos_base__TzPervasives"]
    ~modules:["registration"; "registration_intf"; "mockup_args"]

let tezos_mockup_proxy =
  public_lib
    "tezos-mockup-proxy"
    ~path:"src/lib_mockup_proxy"
    ~synopsis:"Tezos: local RPCs"
    ~deps:
      [
        tezos_base;
        tezos_client_base;
        tezos_protocol_environment;
        tezos_rpc_http;
        resto_cohttp_self_serving_client;
        tezos_rpc_http_client;
        tezos_shell_services;
      ]
    ~opens:["Tezos_base__TzPervasives"]

(* Depends on tezos_p2p to register the relevant RPCs. *)
let tezos_mockup =
  public_lib
    "tezos-mockup"
    ~path:"src/lib_mockup"
    ~synopsis:"Tezos: library of auto-documented RPCs (mockup mode)"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_client_base;
        tezos_mockup_proxy;
        resto_cohttp_self_serving_client;
        tezos_rpc;
        tezos_p2p_services;
        tezos_p2p;
        tezos_protocol_environment;
        tezos_stdlib_unix;
        tezos_rpc_http;
        tezos_rpc_http_client;
        tezos_mockup_registration;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_mockup_registration"]
    ~modules:
      [
        "files";
        "local_services";
        "persistence";
        "persistence_intf";
        "RPC_client";
        "migration";
      ]

let tezos_mockup_commands =
  public_lib
    "tezos-mockup-commands"
    ~path:"src/lib_mockup"
    ~synopsis:"Tezos: library of auto-documented RPCs (commands)"
    ~deps:
      [
        tezos_base;
        tezos_client_commands;
        tezos_client_base;
        tezos_mockup;
        tezos_mockup_registration;
      ]
    ~opens:
      ["Tezos_base__TzPervasives"; "Tezos_mockup"; "Tezos_mockup_registration"]
    ~modules:["mockup_wallet"; "mockup_commands"]

let _tezos_mockup_tests =
  tests
    ["test_mockup_args"; "test_fuzzing_mockup_args"; "test_persistence"]
    ~path:"src/lib_mockup/test"
    ~opam:"src/lib_mockup/tezos-mockup"
    ~deps:
      [
        tezos_base_test_helpers;
        tezos_mockup;
        tezos_mockup_registration;
        tezos_client_base;
        qcheck_alcotest;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base_test_helpers"]

let tezos_proxy =
  public_lib
    "tezos-proxy"
    ~path:"src/lib_proxy"
    ~synopsis:"Tezos: proxy"
    ~deps:
      [
        ringo_lwt;
        tezos_base;
        tezos_clic;
        tezos_client_base;
        tezos_mockup_proxy;
        tezos_protocol_environment;
        tezos_rpc;
        tezos_shell_services;
        tezos_context;
      ]
    ~opens:["Tezos_base__TzPervasives"]

let _tezos_proxy_tests =
  tests
    [
      "test_proxy";
      "test_fuzzing_proxy_getter";
      "test_light";
      "test_fuzzing_light";
    ]
    ~path:"src/lib_proxy/test"
    ~opam:"src/lib_proxy/tezos-proxy"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_proxy;
        tezos_base_test_helpers;
        tezos_test_helpers;
        tezos_shell_services_test_helpers;
        qcheck_alcotest;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base_test_helpers"]

let tezos_proxy_server_config =
  public_lib
    "tezos-proxy-server-config"
    ~path:"src/lib_proxy_server_config"
    ~synopsis:"Tezos: proxy server configuration"
    ~deps:[tezos_base; tezos_stdlib_unix]
    ~opens:["Tezos_base__TzPervasives"]

let _tezos_proxy_server_config_tests =
  test
    "test_proxy_server_config"
    ~path:"src/lib_proxy_server_config/test"
    ~opam:"src/lib_proxy_server_config/tezos-proxy-server-config"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_proxy_server_config;
        tezos_test_helpers;
        qcheck_alcotest;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"]

let tezos_client_base_unix =
  public_lib
    "tezos-client-base-unix"
    ~path:"src/lib_client_base_unix"
    ~synopsis:
      "Tezos: common helpers for `tezos-client` (unix-specific fragment)"
    ~deps:
      [
        tezos_base;
        tezos_client_base;
        tezos_client_commands;
        tezos_stdlib_unix;
        tezos_rpc_http_client_unix;
        tezos_mockup;
        tezos_mockup_registration;
        tezos_mockup_commands;
        tezos_proxy;
        tezos_signer_backends_unix;
        tezos_shell_services;
        lwt_exit;
      ]
    ~linkall:true
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_rpc_http";
        "Tezos_rpc_http_client_unix";
        "Tezos_shell_services";
        "Tezos_stdlib_unix";
        "Tezos_client_base";
        "Tezos_client_commands";
        "Tezos_mockup_commands";
      ]

let _tezos_client_base_unix_tests =
  test
    "test_mockup_wallet"
    ~path:"src/lib_client_base_unix/test"
    ~opam:"src/lib_client_base_unix/tezos-client-base-unix"
    ~deps:
      [
        tezos_mockup_commands;
        tezos_client_base_unix;
        tezos_base_test_helpers;
        alcotest;
        alcotest_lwt;
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base_test_helpers"]

(* Depends on pyml-plop because of Matrix module... pyml-plot should be split further. *)
let tezos_benchmark =
  public_lib
    "tezos-benchmark"
    ~path:"src/lib_benchmark"
    ~synopsis:
      "Tezos: library for writing benchmarks and performing simple parameter \
       inference"
    ~deps:
      [
        tezos_base;
        tezos_stdlib_unix;
        tezos_micheline;
        tezos_clic;
        data_encoding;
        prbnmcn_stats;
        benchmark_utils;
        pyml_plot;
        ocaml_migrate_parsetree;
        opam_only "hashcons" [];
      ]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"]

let tezos_benchmark_examples =
  public_lib
    "tezos-benchmark-examples"
    ~path:"src/lib_benchmark/example"
    ~opam:"src/lib_benchmark/tezos-benchmark-examples"
    ~synopsis:"Tezos: examples for lib-benchmarks"
    ~deps:[tezos_base; tezos_stdlib_unix; tezos_crypto; tezos_benchmark]
    ~opens:["Tezos_base__TzPervasives"]

let _tezos_benchmark_tests =
  test
    "main_ci"
    ~path:"src/lib_benchmark/test"
    ~opam:"src/lib_benchmark/tezos-benchmark-tests"
    ~synopsis:"Tezos: tests for lib-benchmarks"
    ~deps:
      [
        alcotest_lwt;
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_micheline;
        tezos_crypto;
        tezos_benchmark;
        tezos_benchmark_examples;
      ]
    ~opens:["Tezos_base__TzPervasives"]

(* unused lib? *)
let tezos_micheline_rewriting =
  public_lib
    "tezos-micheline-rewriting"
    ~path:"src/lib_benchmark/lib_micheline_rewriting"
    ~synopsis:"Tezos: library for rewriting Micheline expressions"
    ~deps:
      [
        zarith; zarith_stubs_js; tezos_stdlib; tezos_error_monad; tezos_micheline;
      ]
    ~opens:["Tezos_stdlib"; "Tezos_error_monad"; "Tezos_micheline"]

let _tezos_micheline_rewriting_tests =
  test
    "test_rewriting"
    ~path:"src/lib_benchmark/lib_micheline_rewriting/test"
    ~opam:"src/lib_benchmark/lib_micheline_rewriting/tezos-micheline-rewriting"
    ~deps:
      [
        tezos_micheline;
        tezos_micheline_rewriting;
        Protocol.(main alpha);
        tezos_error_monad;
        Protocol.(client_exn alpha);
        alcotest_lwt;
      ]
    ~opens:["Tezos_micheline"]

let tezos_shell_benchmarks =
  public_lib
    "tezos-shell-benchmarks"
    ~path:"src/lib_shell_benchmarks"
    ~synopsis:"Tezos: shell benchmarks"
    ~deps:
      [
        tezos_base;
        tezos_benchmark;
        tezos_context;
        tezos_shell_context;
        tezos_micheline;
      ]
    ~linkall:true
    ~opens:
      [
        "Tezos_stdlib";
        "Tezos_base";
        "Tezos_base__TzPervasives";
        "Tezos_error_monad";
        "Tezos_benchmark";
        "Tezos_crypto";
      ]

let tezt =
  public_lib
    "tezt"
    ~path:"tezt/lib"
    ~synopsis:"Framework for integration tests with external processes"
    ~ocaml:[At_least "4.08"]
    ~bisect_ppx:false
    ~deps:[re; lwt_unix; ezjsonm]

let tezt_tezos =
  public_lib
    "tezt-tezos"
    ~path:"tezt/lib_tezos"
    ~synopsis:"Tezos test framework based on Tezt"
    ~bisect_ppx:false
    ~deps:[tezt; hex; tezos_base; tezos_base_unix]
    ~opens:["Tezt"; "Tezt.Base"]

let tezos_openapi =
  public_lib
    "tezos-openapi"
    ~path:"src/lib_openapi"
    ~synopsis:
      "Tezos: a library for querying RPCs and converting into the OpenAPI \
       format"
    ~deps:[ezjsonm; json_data_encoding; tezt]

(* INTERNAL EXES *)

(* Not released, so no ~opam. *)
let _node_wrapper =
  private_exe
    "node_wrapper"
    ~path:"src/tooling"
    ~opam:""
    ~deps:[unix]
    ~modules:["node_wrapper"]
    ~bisect_ppx:false

let _tezos_protocol_compiler_bin =
  public_exe
    "tezos-protocol-compiler"
    ~path:"src/lib_protocol_compiler/bin"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~internal_name:"main_native"
    ~modes:[Native]
    ~deps:[tezos_protocol_compiler_native]
    ~linkall:true
    ~modules:["Main_native"]

let _tezos_protocol_compiler_tezos_protocol_packer =
  public_exe
    "tezos-protocol-compiler.tezos-protocol-packer"
    ~path:"src/lib_protocol_compiler/bin"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~internal_name:"main_packer"
    ~deps:[tezos_base; tezos_protocol_compiler_lib; tezos_stdlib_unix]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_stdlib_unix";
        "Tezos_protocol_compiler";
      ]
    ~modules:["Main_packer"]

let _tezos_embedded_protocol_packer =
  public_exe
    "tezos-embedded-protocol-packer"
    ~path:"src/lib_protocol_compiler/bin"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~internal_name:"main_embedded_packer"
    ~modes:[Native]
    ~deps:[tezos_base; tezos_base_unix; tezos_stdlib_unix]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base_unix"; "Tezos_stdlib_unix"]
    ~linkall:true
    ~modules:["Main_embedded_packer"]

let _s_packer =
  private_exe
    "s_packer"
    ~path:"src/lib_protocol_environment/s_packer"
    ~opam:"src/lib_protocol_environment/tezos-protocol-environment-packer"
    ~bisect_ppx:false
    ~dune:
      Dune.
        [
          [
            S "install";
            [S "section"; S "libexec"];
            [S "package"; S "tezos-protocol-environment-packer"];
            [S "files"; [S "s_packer.exe"; S "as"; S "s_packer"]];
          ];
        ]

let _replace =
  private_exe
    "replace"
    ~path:"src/lib_protocol_compiler/bin"
    ~opam:"src/lib_protocol_compiler/tezos-protocol-compiler"
    ~deps:[tezos_base; tezos_base_unix; tezos_stdlib_unix; re_str]
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"]
    ~modules:["Replace"]
    ~static:true
    ~dune:
      [
        [
          S "install";
          [S "section"; S "libexec"];
          [S "files"; [S "replace.exe"; S "as"; S "replace"]];
        ];
      ]

let _tezos_validator_bin =
  public_exe
    "tezos-validator"
    ~path:"src/bin_validation/bin"
    ~opam:"src/bin_validation/tezos-validator"
    ~internal_name:"main_validator"
    ~deps:[tezos_validator_lib]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_context";
        "Tezos_stdlib_unix";
        "Tezos_shell";
        "Tezos_shell_services";
        "Tezos_validation";
        "Tezos_protocol_updater";
        "Tezos_validator";
      ]
    ~linkall:true

let _tezos_node =
  public_exe
    "tezos-node"
    ~path:"src/bin_node"
    ~internal_name:"main"
    ~synopsis:"Tezos: `tezos-node` binary"
    ~deps:
      ([
         tezos_base;
         tezos_base_unix;
         tezos_version;
         tezos_stdlib_unix;
         tezos_shell_services;
         tezos_workers;
         tezos_rpc_http_server;
         tezos_p2p;
         tezos_shell;
         tezos_store;
         tezos_context;
         tezos_validator_lib;
         tezos_shell_context;
         tezos_protocol_updater;
         cmdliner;
         fmt_cli;
         fmt_tty;
         tls;
         prometheus_app_unix;
         lwt_exit;
       ]
      @ Protocol.all_optionally
          [Protocol.embedded_opt; Protocol.plugin_registerer])
    ~linkall:true
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_base";
        "Tezos_stdlib_unix";
        "Tezos_shell_services";
        "Tezos_rpc_http";
        "Tezos_rpc_http_server";
        "Tezos_p2p";
        "Tezos_shell";
        "Tezos_store";
        "Tezos_context";
        "Tezos_validator";
        "Tezos_shell_context";
        "Tezos_workers";
        "Tezos_protocol_updater";
      ]
    ~dune:
      Dune.
        [
          [
            S "install";
            [S "package"; S "tezos-node"];
            [S "section"; S "bin"];
            [
              S "files";
              [S "tezos-sandboxed-node.sh"; S "as"; S "tezos-sandboxed-node.sh"];
            ];
          ];
        ]

let _tezos_client =
  public_exes
    ["tezos-client"; "tezos-admin-client"]
    ~path:"src/bin_client"
    ~internal_names:["main_client"; "main_admin"]
    ~opam:"src/bin_client/tezos-client"
    ~synopsis:"Tezos: `tezos-client` binary"
    ~deps:
      ([
         tezos_base;
         tezos_base_unix;
         tezos_rpc_http_client;
         tezos_shell_services;
         tezos_client_base;
         tezos_client_commands;
         tezos_mockup_commands;
         tezos_proxy;
         tezos_stdlib_unix;
         tezos_client_base_unix;
         tezos_signer_backends_unix;
       ]
      @ Protocol.all_optionally
          [
            (fun protocol ->
              match Protocol.client_commands_registration protocol with
              | None -> Protocol.client protocol
              | x -> x);
            Protocol.baking_commands_registration;
            Protocol.plugin;
          ])
    ~linkall:true
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_rpc_http_client";
        "Tezos_stdlib_unix";
        "Tezos_shell_services";
        "Tezos_client_base";
        "Tezos_client_commands";
        "Tezos_mockup_commands";
        "Tezos_client_base_unix";
      ]
    ~dune:
      Dune.
        [
          [
            S "install";
            [S "package"; S "tezos-client"];
            [S "section"; S "bin"];
            [
              S "files";
              [
                S "tezos-init-sandboxed-client.sh";
                S "as";
                S "tezos-init-sandboxed-client.sh";
              ];
            ];
          ];
        ]

let _tezos_codec =
  public_exe
    "tezos-codec"
    ~path:"src/bin_codec"
    ~internal_name:"codec"
    ~synopsis:"Tezos: `tezos-codec` binary to encode and decode values"
    ~deps:
      ([
         data_encoding;
         tezos_base;
         tezos_stdlib_unix;
         tezos_event_logging;
         tezos_client_base;
         tezos_client_base_unix;
         tezos_clic;
         tezos_signer_services;
       ]
      @ Protocol.all_optionally
      @@ [
           (fun protocol ->
             let link =
               protocol == Protocol.alpha
               ||
               match Protocol.number protocol with
               | Some number when number >= 005 -> true
               | _ -> false
             in
             if link then Protocol.client protocol else None);
         ])
    ~linkall:true
    ~opens:
      [
        "Data_encoding";
        "Tezos_base__TzPervasives";
        "Tezos_client_base_unix";
        "Tezos_client_base";
        "Tezos_clic";
        "Tezos_stdlib_unix";
        "Tezos_event_logging";
      ]

let _tezos_sandbox =
  private_exe
    "main"
    ~path:"src/bin_sandbox"
    ~opam:""
    ~bisect_ppx:false
    ~deps:[tezos_base; tezos_base_unix; fmt; flextesa]

let _tezos_proxy_server =
  public_exe
    "tezos-proxy-server"
    ~path:"src/bin_proxy_server"
    ~internal_name:"main_proxy_server"
    ~synopsis:"Tezos: `tezos-proxy-server` binary"
    ~deps:
      ([
         tezos_base;
         tezos_base_unix;
         cmdliner;
         lwt_exit;
         tezos_proxy;
         tezos_proxy_server_config;
         tezos_rpc_http_client_unix;
         tezos_rpc_http_server;
         tezos_shell_services;
         tezos_version;
       ]
      @ Protocol.all_optionally [Protocol.client; Protocol.plugin])
    ~linkall:true
    ~opens:["Tezos_base__TzPervasives"; "Tezos_base"; "Tezos_stdlib_unix"]

let _tezos_snoop =
  public_exe
    "tezos-snoop"
    ~path:"src/bin_snoop"
    ~internal_name:"main_snoop"
    ~synopsis:"Tezos: `tezos-snoop` binary"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_stdlib_unix;
        tezos_clic;
        tezos_benchmark;
        tezos_benchmark_examples;
        tezos_shell_benchmarks;
        tezos_benchmarks_proto_alpha;
        str;
        ocamlgraph;
        pyml;
        pyml_plot;
        prbnmcn_stats;
      ]
    ~linkall:true
    ~opens:["Tezos_base__TzPervasives"; "Tezos_stdlib_unix"; "Tezos_benchmark"]

(* We use Dune's select statement and keep uTop optional *)
(* Keeping uTop optional lets `make build` succeed, *)
(* which uses tezos/opam-repository to resolve dependencies, *)
(* on the CI. This prevents having to add dev-dependency to *)
(* tezos/opam-repository unnecessarily *)
(* We set [~static] to false because we don't release this as a static binary. *)
let _tztop =
  public_exe
    "tztop"
    ~path:"src/tooling/tztop"
    ~internal_name:"tztop_main"
    ~opam:"src/tooling/tezos-tooling"
    ~modes:[Byte]
    ~bisect_ppx:false
    ~release:false
    ~static:false
    ~deps:
      [
        coq_of_ocaml;
        ocamlformat;
        bisect_ppx;
        (* The following deps come from the original dune file. *)
        tezos_protocol_compiler_lib;
        tezos_base;
        compiler_libs_toplevel;
        select
          ~package:utop
          ~source_if_present:"tztop.utop.ml"
          ~source_if_absent:"tztop.vanilla.ml"
          ~target:"tztop.ml";
      ]

let _tezos_signer =
  public_exe
    "tezos-signer"
    ~path:"src/bin_signer"
    ~internal_name:"main_signer"
    ~synopsis:"Tezos: `tezos-signer` binary"
    ~deps:
      [
        tezos_base;
        tezos_base_unix;
        tezos_client_base;
        tezos_client_base_unix;
        tezos_client_commands;
        tezos_signer_services;
        tezos_rpc_http_server;
        tezos_rpc_http_client_unix;
        tezos_stdlib_unix;
        tezos_signer_backends_unix;
      ]
    ~opens:
      [
        "Tezos_base__TzPervasives";
        "Tezos_client_base";
        "Tezos_client_base_unix";
        "Tezos_client_commands";
        "Tezos_signer_services";
        "Tezos_rpc_http";
        "Tezos_rpc_http_server";
        "Tezos_rpc_http_client_unix";
        "Tezos_stdlib_unix";
        "Tezos_stdlib";
      ]

let _rpc_openapi =
  private_exe
    "rpc_openapi"
    ~path:"src/bin_openapi"
    ~opam:""
    ~deps:[tezos_openapi]

let _tezos_tps_evaluation =
  public_exe
    "tezos-tps-evaluation"
    ~internal_name:"main_tps_evaluation"
    ~path:"src/bin_tps_evaluation"
    ~synopsis:"Tezos TPS evaluation tool"
    ~deps:
      [
        caqti;
        caqti_driver_postgresql;
        caqti_lwt;
        cmdliner;
        data_encoding;
        lwt;
        ppx_blob;
        tezos_client_base_unix;
        Protocol.(main alpha);
        tezt;
        tezt_tezos;
      ]
    ~preprocess:[PPS ppx_blob]
    ~preprocessor_deps:[File "./sql/get_all_operations.sql"]
    ~static:false
    ~release:false
    ~opens:["Tezos_base__TzPervasives"; "Tezt"; "Tezt_tezos"; "Tezt.Base"]

(* For now we don't generate:
   - protocol files (that's a TODO);
   - lib_time_measurement (its dune structure is *very* specific);
   - src/lib_protocol_compiler/test/dune (it does not define any library,
     executable or test stanza, it only defines aliases).

   Note that [filename] is relative to the manifest directory,
   i.e. it starts with "../". *)
let exclude filename =
  has_prefix ~prefix:"../src/proto_" filename
  || has_prefix ~prefix:"../src/lib_time_measurement/" filename
  ||
  match filename with
  | "../src/lib_protocol_compiler/test/dune" -> true
  | _ -> false

(* Generate dune and opam files. *)
let () = generate ~exclude ()

(* Generate active_protocol_versions. *)
let () =
  let ch = open_out "../active_protocol_versions" in
  Fun.protect ~finally:(fun () -> close_out ch) @@ fun () ->
  let write_protocol protocol =
    Option.iter (Printf.fprintf ch "%03d-") (Protocol.number protocol) ;
    output_string ch (Protocol.name protocol) ;
    output_char ch '\n'
  in
  List.iter write_protocol Protocol.active
