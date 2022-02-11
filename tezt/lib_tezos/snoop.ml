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

type t = {path : string; name : string; color : Log.Color.t}

type determinizer = Percentile of int | Mean

type regression_method =
  | Lasso of {positive : bool}
  | Ridge of {positive : bool}
  | NNLS

type tag =
  | Proto of Protocol.t
  | Interpreter
  | Translator
  | Sapling
  | Encoding
  | Io
  | Misc
  | Builtin
  | Gtoc
  | Cache
  | Carbonated_map

type michelson_term_kind = Data | Code

type list_mode = All | Any | Exactly

let create ?(path = Constant.tezos_snoop) ?(color = Log.Color.FG.blue) () =
  {path; name = "snoop"; color}

let spawn_command snoop command =
  Process.spawn ~name:snoop.name ~color:snoop.color snoop.path @@ command

(* Benchmark command *)

let string_of_determinizer = function
  | Mean -> "mean"
  | Percentile i -> Printf.sprintf "percentile@%d" i

let benchmark_command ~bench_name ~bench_num ~save_to ~nsamples ~determinizer
    ?seed ?config_dir ?csv_dump () =
  let command =
    [
      "benchmark";
      bench_name;
      "and";
      "save";
      "to";
      save_to;
      "--determinizer";
      string_of_determinizer determinizer;
      "--bench-num";
      string_of_int bench_num;
      "--nsamples";
      string_of_int nsamples;
    ]
  in
  let seed =
    match seed with None -> [] | Some seed -> ["--seed"; string_of_int seed]
  in
  let config_dir =
    match config_dir with
    | None -> []
    | Some config_dir -> ["--config-dir"; config_dir]
  in
  let csv_dump =
    match csv_dump with None -> [] | Some csv -> ["--dump-csv"; csv]
  in
  command @ seed @ config_dir @ csv_dump

let spawn_benchmark ~bench_name ~bench_num ~nsamples ~determinizer ~save_to
    ?seed ?config_dir ?csv_dump snoop =
  spawn_command
    snoop
    (benchmark_command
       ~bench_name
       ~bench_num
       ~save_to
       ~nsamples
       ~determinizer
       ?seed
       ?config_dir
       ?csv_dump
       ())

let benchmark ~bench_name ~bench_num ~nsamples ~determinizer ~save_to ?seed
    ?config_dir ?csv_dump snoop =
  spawn_benchmark
    ~bench_name
    ~bench_num
    ~nsamples
    ~determinizer
    ~save_to
    ?seed
    ?config_dir
    ?csv_dump
    snoop
  |> Process.check

(* Infer command *)

let infer_command ~model_name ~workload_data ~regression_method ~dump_csv
    ~solution ?report ?graph () =
  let regression_method =
    match regression_method with
    | Lasso {positive} ->
        if positive then ["lasso"; "--lasso-positive"] else ["lasso"]
    | Ridge {positive} ->
        if positive then ["ridge"; "--ridge-positive"] else ["ridge"]
    | NNLS -> ["nnls"]
  in
  let report =
    match report with
    | None -> []
    | Some report_file -> ["--report"; report_file]
  in
  let graph =
    match graph with
    | None -> []
    | Some graph_file -> ["--dot-file"; graph_file]
  in
  [
    "infer";
    "parameters";
    "for";
    "model";
    model_name;
    "on";
    "data";
    workload_data;
    "using";
  ]
  @ regression_method
  @ ["--dump-csv"; dump_csv; "--save-solution"; solution]
  @ report @ graph

let spawn_infer_parameters ~model_name ~workload_data ~regression_method
    ~dump_csv ~solution ?report ?graph snoop =
  spawn_command
    snoop
    (infer_command
       ~model_name
       ~workload_data
       ~regression_method
       ~dump_csv
       ~solution
       ?report
       ?graph
       ())

let infer_parameters ~model_name ~workload_data ~regression_method ~dump_csv
    ~solution ?report ?graph snoop =
  spawn_infer_parameters
    ~model_name
    ~workload_data
    ~regression_method
    ~dump_csv
    ~solution
    ?report
    ?graph
    snoop
  |> Process.check

(* Sapling generation *)

let sapling_generate_command ~tx_count ~max_inputs ~max_outputs ~file
    ?(protocol = Protocol.Alpha) ?max_nullifiers ?max_additional_commitments
    ?seed () =
  let max_nullifiers =
    match max_nullifiers with
    | None -> []
    | Some max_nf -> ["--max-nullifiers"; string_of_int max_nf]
  in
  let max_additional_commitments =
    match max_additional_commitments with
    | None -> []
    | Some max_ac -> ["--max-additional-commitments"; string_of_int max_ac]
  in
  let seed =
    match seed with None -> [] | Some seed -> ["--seed"; string_of_int seed]
  in
  let proto_tag = Protocol.tag protocol in
  [
    proto_tag;
    "sapling";
    "generate";
    string_of_int tx_count;
    "transactions";
    "in";
    file;
    "--max-inputs";
    string_of_int max_inputs;
    "--max-outputs";
    string_of_int max_outputs;
  ]
  @ max_nullifiers @ max_additional_commitments @ seed

let spawn_sapling_generate ?protocol ~tx_count ~max_inputs ~max_outputs ~file
    ?max_nullifiers ?max_additional_commitments ?seed snoop =
  spawn_command
    snoop
    (sapling_generate_command
       ~tx_count
       ~max_inputs
       ~max_outputs
       ~file
       ?protocol
       ?max_nullifiers
       ?max_additional_commitments
       ?seed
       ())

let sapling_generate ?protocol ~tx_count ~max_inputs ~max_outputs ~file
    ?max_nullifiers ?max_additional_commitments ?seed snoop =
  spawn_sapling_generate
    ~tx_count
    ~max_inputs
    ~max_outputs
    ~file
    ?protocol
    ?max_nullifiers
    ?max_additional_commitments
    ?seed
    snoop
  |> Process.check

(* Michelson generation *)

let string_of_kind kind = match kind with Data -> "data" | Code -> "code"

let michelson_generate_command ?(protocol = Protocol.Alpha) ~terms_count ~kind
    ~file ?min_size ?max_size ?burn_in ?seed () =
  let seed =
    match seed with None -> [] | Some seed -> ["--seed"; string_of_int seed]
  in
  let min_size =
    match min_size with
    | None -> []
    | Some sz -> ["--min-size"; string_of_int sz]
  in
  let max_size =
    match max_size with
    | None -> []
    | Some sz -> ["--max-size"; string_of_int sz]
  in
  let burn_in =
    match burn_in with
    | None -> []
    | Some burn_in -> ["--burn-in"; string_of_int burn_in]
  in
  let proto_tag = Protocol.tag protocol in
  [
    proto_tag;
    "michelson";
    "generate";
    string_of_int terms_count;
    "terms";
    "of";
    "kind";
    string_of_kind kind;
    "in";
    file;
  ]
  @ seed @ min_size @ max_size @ burn_in

let spawn_michelson_generate ?protocol ~terms_count ~kind ~file ?min_size
    ?max_size ?burn_in ?seed snoop =
  spawn_command
    snoop
    (michelson_generate_command
       ?protocol
       ~terms_count
       ~kind
       ~file
       ?min_size
       ?max_size
       ?burn_in
       ?seed
       ())

let michelson_generate ?protocol ~terms_count ~kind ~file ?min_size ?max_size
    ?burn_in ?seed snoop =
  spawn_michelson_generate
    ?protocol
    ~terms_count
    ~kind
    ~file
    ?min_size
    ?max_size
    ?burn_in
    ?seed
    snoop
  |> Process.check

(* Michelson file concatenation *)

let michelson_concat_command ?(protocol = Protocol.Alpha) ~file1 ~file2 ~target
    () =
  let proto_tag = Protocol.tag protocol in
  [
    proto_tag;
    "michelson";
    "concat";
    "files";
    file1;
    "and";
    file2;
    "into";
    target;
  ]

let spawn_michelson_concat ?protocol ~file1 ~file2 ~target snoop =
  spawn_command
    snoop
    (michelson_concat_command ?protocol ~file1 ~file2 ~target ())

let michelson_concat ?protocol ~file1 ~file2 ~target snoop =
  spawn_michelson_concat ?protocol ~file1 ~file2 ~target snoop |> Process.check

(* Benchmark listing *)

let string_of_tag (tag : tag) =
  match tag with
  | Proto proto -> Protocol.tag proto
  | Interpreter -> "interpreter"
  | Translator -> "translator"
  | Sapling -> "sapling"
  | Encoding -> "encoding"
  | Io -> "io"
  | Misc -> "misc"
  | Builtin -> "builtin"
  | Gtoc -> "global_constants"
  | Cache -> "cache"
  | Carbonated_map -> "carbonated_map"

let list_benchmarks_command mode tags =
  let tags = List.map string_of_tag tags in
  match mode with
  | All -> ["list"; "benchmarks"; "with"; "tags"; "all"; "of"] @ tags
  | Any -> ["list"; "benchmarks"; "with"; "tags"; "any"; "of"] @ tags
  | Exactly -> ["list"; "benchmarks"; "with"; "tags"; "exactly"] @ tags

let spawn_list_benchmarks ~mode ~tags snoop =
  spawn_command snoop (list_benchmarks_command mode tags)

let list_benchmarks ~mode ~tags snoop =
  let process = spawn_list_benchmarks ~mode ~tags snoop in
  let* output = Process.check_and_read_stdout process in
  let lines = String.split_on_char '\n' output in
  Lwt_list.filter_map_s
    (function
      | "" -> return None
      | line -> (
          match line =~* rex "(.*):.*" with
          | None -> Test.fail "Can't parse benchmark out of \"%s\"" line
          | Some s -> return (Some s)))
    lines
