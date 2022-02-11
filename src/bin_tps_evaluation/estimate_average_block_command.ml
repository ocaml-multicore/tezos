(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** The different kinds of Tezos operations we're analyzing. *)
type transaction_kind = Contract | Regular | Origination

(** The rows returned by the summary query. *)
type summary_row = {transaction_kind : transaction_kind; operation_count : int}

(** The rows returned by the contract query. *)
type contract_row = {contract_address : string; total_contract_operations : int}

module Encoding = struct
  (** Helper functions to convert from and to the Caqti_type used to interface with the database. *)
  let transaction_kind =
    let encode = function
      | Contract -> Ok "contract"
      | Regular -> Ok "regular"
      | Origination -> Ok "origination"
    in
    let decode = function
      | "contract" -> Ok Contract
      | "regular" -> Ok Regular
      | "origination" -> Ok Origination
      | v ->
          Error ("value of " ^ v ^ " could not be decoded as a transaction type")
    in
    let rep = Caqti_type.string in
    Caqti_type.custom ~encode ~decode rep

  let summary_row =
    let encode {transaction_kind; operation_count} =
      Ok (transaction_kind, operation_count)
    in
    let decode (transaction_kind, operation_count) =
      Ok {transaction_kind; operation_count}
    in
    let rep = Caqti_type.(tup2 transaction_kind int) in
    Caqti_type.custom ~encode ~decode rep

  let contract_row =
    let encode {contract_address; total_contract_operations} =
      Ok (contract_address, total_contract_operations)
    in
    let decode (contract_address, total_contract_operations) =
      Ok {contract_address; total_contract_operations}
    in
    let rep = Caqti_type.(tup2 string int) in
    Caqti_type.custom ~encode ~decode rep
end

module Db = struct
  (** Establish a connection pool that will be used to make the database queries. *)
  let mk_pool conn_str =
    match Caqti_lwt.connect_pool ~max_size:10 (Uri.of_string conn_str) with
    | Ok pool -> pool
    | Error err -> Stdlib.failwith (Caqti_error.show err)

  (** Retrieve the top N contracts used as destination in transactions. *)
  let top_n_contracts =
    let query =
      Printf.sprintf
        {|
      WITH _group AS (
        SELECT
          total.tx_dst_addr,
          count(total.tx_dst_addr) AS ops_count
        FROM
          (
            -- included subquery on a new line to avoid breaking single line comments
            %s
          ) AS total
        WHERE
          total.transaction_kind = 'contract'
        GROUP BY
          total.tx_dst_addr
      )

      SELECT _final.tx_dst_addr, _final.ops_count FROM (
        SELECT *,
               COALESCE(CAST(1.0 * ops_count / nullif (sum(ops_count) OVER (), 0) AS numeric(6, 5)), 0) AS percentage
        FROM _group
      ) AS _final
      WHERE _final.percentage >= ?
    |}
        [%blob "./sql/get_all_operations.sql"]
    in
    Caqti_request.collect
      Caqti_type.(tup3 string string float)
      Encoding.contract_row
      query

  let get_top_contracts conn_str start_date end_date limit () =
    let main' (module C : Caqti_lwt.CONNECTION) =
      C.fold
        top_n_contracts
        (fun row acc ->
          {
            contract_address = row.contract_address;
            total_contract_operations = row.total_contract_operations;
          }
          :: acc)
        (start_date, end_date, limit)
        []
    in
    Caqti_lwt.Pool.use main' (mk_pool conn_str)

  (** The main analysis query that categorizes the Tezos operations within a given time frame. *)
  let summary_query =
    let query =
      Printf.sprintf
        {|
      SELECT
        total.transaction_kind,
        count(total.transaction_kind) AS ops_count
      FROM
        (
          -- included subquery on a new line to avoid breaking single line comments
          %s
        ) AS total
      GROUP BY
        total.transaction_kind
    |}
        [%blob "./sql/get_all_operations.sql"]
    in
    Caqti_request.collect
      Caqti_type.(tup2 string string)
      Encoding.summary_row
      query

  let get_operation_summary conn_str start_date end_date () =
    let main' (module C : Caqti_lwt.CONNECTION) =
      C.fold
        summary_query
        (fun row acc ->
          {
            transaction_kind = row.transaction_kind;
            operation_count = row.operation_count;
          }
          :: acc)
        (start_date, end_date)
        []
    in
    Caqti_lwt.Pool.use main' (mk_pool conn_str)
end

module Json = struct
  (** Calculate the total count operations of the given type. *)
  let get_total_by_type (rows : summary_row list) (ty : transaction_kind) : int
      =
    List.fold_left
      ( + )
      0
      (List.map
         (fun a -> a.operation_count)
         (List.filter (fun a -> a.transaction_kind == ty) rows))

  let list_contract rows =
    List.map (fun a -> (a.contract_address, a.total_contract_operations)) rows

  (** Construct the final JSON object to present the result of the analysis. *)
  let show_summary summary top_contracts =
    let json_output =
      Average_block.
        {
          regular = get_total_by_type summary Regular;
          origination = get_total_by_type summary Origination;
          contract = list_contract top_contracts;
        }
    in
    print_string
      (Data_encoding.Json.to_string
         ~newline:true
         ~minify:false
         (Data_encoding.Json.construct Average_block.encoding json_output))
end

(** Execute the query against the database and formats the result. *)
let query_db start_date end_date limit conn_str =
  Lwt_main.run
    ( Lwt.bind
        (Db.get_operation_summary conn_str start_date end_date ())
        (function
          | Ok rows -> Lwt.return rows
          | Error e -> Stdlib.failwith (Caqti_error.show e))
    >>= fun summary ->
      Lwt.bind
        (Db.get_top_contracts conn_str start_date end_date limit ())
        (function
          | Ok rows -> Lwt.return rows
          | Error e -> Stdlib.failwith (Caqti_error.show e))
      >>= fun top_contracts ->
      Lwt.return (Json.show_summary summary top_contracts) )

module Term = struct
  let connection_string_arg =
    let open Cmdliner in
    let doc = "PostgreSQL connection string" in
    let docv = "CONNECTION_STRING" in
    Arg.(
      value
      & opt string "postgresql://postgres:postgres@localhost:5432/postgres"
      & info ["c"; "connection-string"] ~docv ~doc)

  let start_date_arg =
    let open Cmdliner in
    let doc = "The start date to use in the query" in
    let docv = "START_DATE" in
    let info = Arg.info ["s"; "start-date"] ~docv ~doc in
    Arg.required (Arg.opt (Arg.some Arg.string) None info)

  let end_date_arg =
    let open Cmdliner in
    let doc = "The end date to use in the the query" in
    let docv = "END_DATE" in
    let info = Arg.info ["e"; "end-date"] ~docv ~doc in
    Arg.required (Arg.opt (Arg.some Arg.string) None info)

  let contract_min_percentage_arg =
    let open Cmdliner in
    let doc =
      "The minimum percentage of operations for a contract to be included"
    in
    let docv = "CONTRACT_MIN_PERCENTAGE" in
    Arg.(
      value & opt float 0.1 & info ["p"; "contract-min-percentage"] ~docv ~doc)

  let estimate_average_block =
    let open Cmdliner.Term in
    const query_db $ start_date_arg $ end_date_arg $ contract_min_percentage_arg
    $ connection_string_arg
end

module Manpage = struct
  let command_description =
    "Use historical data to estimate contents of the average block"

  let description = [`S "DESCRIPTION"; `P command_description]

  let man = description

  let info =
    Cmdliner.Term.info ~doc:command_description ~man "estimate-average-block"
end

let cmd = (Term.estimate_average_block, Manpage.info)
