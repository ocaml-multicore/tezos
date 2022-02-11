(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

open Snapshots_events
open Store_types

(* This module handles snapshot's versioning system. *)
module Version = struct
  type t = int

  let (version_encoding : t Data_encoding.t) =
    let open Data_encoding in
    obj1 (req "version" int31)

  (* Current version of the snapshots, since 0.0.5.
   * Previous versions are:
   * - 1: snapshot exported with storage 0.0.1 to 0.0.4 *)
  let current_version = 2
end

let current_version = Version.current_version

type error +=
  | Incompatible_history_mode of {
      requested : History_mode.t;
      stored : History_mode.t;
    }
  | Invalid_export_block of {
      block : Block_hash.t option;
      reason :
        [ `Pruned
        | `Pruned_pred
        | `Unknown
        | `Unknown_ancestor
        | `Caboose
        | `Genesis
        | `Not_enough_pred ];
    }
  | Invalid_export_path of string
  | Snapshot_file_not_found of string
  | Inconsistent_protocol_hash of {
      expected : Protocol_hash.t;
      got : Protocol_hash.t;
    }
  | Inconsistent_context_hash of {
      expected : Context_hash.t;
      got : Context_hash.t;
    }
  | Inconsistent_context of Context_hash.t
  | Cannot_decode_protocol of Protocol_hash.t
  | Cannot_write_metadata of string
  | Cannot_read of {
      kind :
        [ `Version
        | `Metadata
        | `Block_data
        | `Context
        | `Protocol_table
        | `Protocol
        | `Cemented_cycle ];
      path : string;
    }
  | Inconsistent_floating_store of block_descriptor * block_descriptor
  | Missing_target_block of block_descriptor
  | Cannot_read_floating_store of string
  | Cannot_retrieve_block_interval
  | Invalid_cemented_file of string
  | Missing_cemented_file of string
  | Corrupted_floating_store
  | Invalid_protocol_file of string
  | Target_block_validation_failed of Block_hash.t * string
  | Directory_already_exists of string
  | Empty_floating_store
  | Cannot_create_tmp_export_directory of string
  | Inconsistent_chain_import of {
      expected : Distributed_db_version.Name.t;
      got : Distributed_db_version.Name.t;
    }
  | Inconsistent_imported_block of Block_hash.t * Block_hash.t
  | Wrong_snapshot_file of {filename : string}
  | Invalid_chain_store_export of Chain_id.t * string

let () =
  let open Data_encoding in
  register_error_kind
    `Permanent
    ~id:"snapshots.incompatible_export"
    ~title:"Incompatible snapshot export"
    ~description:
      "The requested history mode for the snapshot is not compatible with the \
       given storage."
    ~pp:(fun ppf (requested, stored) ->
      Format.fprintf
        ppf
        "The requested history mode (%a) for the snapshot export is not \
         compatible with the given storage (running with history mode %a)."
        History_mode.pp_short
        requested
        History_mode.pp_short
        stored)
    (obj2
       (req "stored" History_mode.encoding)
       (req "requested" History_mode.encoding))
    (function
      | Incompatible_history_mode {requested; stored} -> Some (requested, stored)
      | _ -> None)
    (fun (requested, stored) -> Incompatible_history_mode {requested; stored}) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.invalid_export_block"
    ~title:"Invalid export block"
    ~description:"Invalid block provided for snapshot export."
    ~pp:(fun ppf (hash, reason) ->
      Format.fprintf
        ppf
        "The selected block %a is invalid: %s."
        (Format.pp_print_option
           ~none:(fun fmt () -> Format.fprintf fmt "(n/a)")
           Block_hash.pp)
        hash
        (match reason with
        | `Pruned -> "the block is too old and has been pruned"
        | `Pruned_pred -> "its predecessor has been pruned"
        | `Unknown -> "the block is unknown"
        | `Unknown_ancestor -> "the block's ancestor is unknown"
        | `Genesis -> "the genesis block is not a valid export point"
        | `Caboose -> "the caboose block is not a valid export point"
        | `Not_enough_pred -> "not enough of the block's predecessors are known"))
    (obj2
       (opt "block" Block_hash.encoding)
       (req
          "reason"
          (string_enum
             [
               ("pruned", `Pruned);
               ("pruned_pred", `Pruned_pred);
               ("unknown", `Unknown);
               ("unknown_ancestor", `Unknown_ancestor);
               ("genesis", `Genesis);
               ("caboose", `Genesis);
               ("not_enough_pred", `Not_enough_pred);
             ])))
    (function
      | Invalid_export_block {block; reason} -> Some (block, reason) | _ -> None)
    (fun (block, reason) -> Invalid_export_block {block; reason}) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.invalid_export_path"
    ~title:"Invalid export path"
    ~description:"Invalid path to export snapshot"
    ~pp:(fun ppf path ->
      Format.fprintf
        ppf
        "Failed to export snapshot: the file or directory %s already exists."
        path)
    (obj1 (req "path" string))
    (function Invalid_export_path path -> Some path | _ -> None)
    (fun path -> Invalid_export_path path) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.snapshot_file_not_found"
    ~title:"Snapshot file not found"
    ~description:"The snapshot file cannot be found."
    ~pp:(fun ppf given_file ->
      Format.fprintf ppf "The snapshot file %s does not exists." given_file)
    (obj1 (req "given_snapshot_file" string))
    (function Snapshot_file_not_found file -> Some file | _ -> None)
    (fun file -> Snapshot_file_not_found file) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.inconsistent_protocol_hash"
    ~title:"Inconsistent protocol hash"
    ~description:"The announced protocol hash doesn't match the computed hash."
    ~pp:(fun ppf (oph, oph') ->
      Format.fprintf
        ppf
        "Inconsistent protocol_hash. Expected: %a, got %a."
        Protocol_hash.pp
        oph
        Protocol_hash.pp
        oph')
    (obj2
       (req "expected" Protocol_hash.encoding)
       (req "got" Protocol_hash.encoding))
    (function
      | Inconsistent_protocol_hash {expected; got} -> Some (expected, got)
      | _ -> None)
    (fun (expected, got) -> Inconsistent_protocol_hash {expected; got}) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.inconsistent_context_hash"
    ~title:"Inconsistent context hash"
    ~description:"The announced context hash doesn't match the computed hash."
    ~pp:(fun ppf (oph, oph') ->
      Format.fprintf
        ppf
        "Inconsistent context_hash. Expected: %a, got %a."
        Context_hash.pp
        oph
        Context_hash.pp
        oph')
    (obj2
       (req "expected" Context_hash.encoding)
       (req "got" Context_hash.encoding))
    (function
      | Inconsistent_context_hash {expected; got} -> Some (expected, got)
      | _ -> None)
    (fun (expected, got) -> Inconsistent_context_hash {expected; got}) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.inconsistent_context"
    ~title:"Inconsistent context"
    ~description:"Inconsistent context after restore."
    ~pp:(fun ppf h ->
      Format.fprintf
        ppf
        "Failed to checkout context %a after restoring it."
        Context_hash.pp
        h)
    (obj1 (req "context_hash" Context_hash.encoding))
    (function Inconsistent_context h -> Some h | _ -> None)
    (fun h -> Inconsistent_context h) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.cannot_decode_protocol"
    ~title:"Protocol import cannot decode"
    ~description:"Failed to decode file when importing protocol"
    ~pp:(fun ppf hash ->
      Format.fprintf
        ppf
        "Cannot decode the protocol in file: %a"
        Protocol_hash.pp
        hash)
    (obj1 (req "filename" Protocol_hash.encoding))
    (function Cannot_decode_protocol hash -> Some hash | _ -> None)
    (fun hash -> Cannot_decode_protocol hash) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.cannot_write_metadata"
    ~title:"Cannot write metadata"
    ~description:"Cannot write metadata while exporting snapshot."
    ~pp:(fun ppf msg ->
      Format.fprintf
        ppf
        "Cannot write metadata while exporting snapshot: %s."
        msg)
    (obj1 (req "msg" string))
    (function Cannot_write_metadata msg -> Some msg | _ -> None)
    (fun msg -> Cannot_write_metadata msg) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.cannot_read"
    ~title:"Cannot read"
    ~description:"Cannot read some snapshot data."
    ~pp:(fun ppf (kind, path) ->
      let kind =
        match kind with
        | `Version -> "version"
        | `Metadata -> "metadata"
        | `Block_data -> "block data"
        | `Context -> "context"
        | `Protocol_table -> "protocol table"
        | `Protocol -> "protocol"
        | `Cemented_cycle -> "cemented cycle"
      in
      Format.fprintf ppf "Cannot read snapshot's %s from %s." kind path)
    (obj2
       (req
          "kind"
          (string_enum
             [
               ("version", `Version);
               ("metadata", `Metadata);
               ("block_data", `Block_data);
               ("context", `Context);
               ("protocol_table", `Protocol_table);
               ("protocol", `Protocol);
               ("cemented_cycle", `Cemented_cycle);
             ]))
       (req "path" string))
    (function Cannot_read {kind; path} -> Some (kind, path) | _ -> None)
    (fun (kind, path) -> Cannot_read {kind; path}) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.inconsistent_floating_store"
    ~title:"Inconsistent floating store"
    ~description:"The floating block store is inconsistent."
    ~pp:(fun ppf (target_blk, first_blk) ->
      Format.fprintf
        ppf
        "Failed to export floating store, the first block %a is above the \
         target block %a (broken invariant)."
        pp_block_descriptor
        first_blk
        pp_block_descriptor
        target_blk)
    (obj2
       (req "target" block_descriptor_encoding)
       (req "first" block_descriptor_encoding))
    (function
      | Inconsistent_floating_store (target, first) -> Some (target, first)
      | _ -> None)
    (fun (target, first) -> Inconsistent_floating_store (target, first)) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.missing_target_block"
    ~title:"Missing target block in floating stores"
    ~description:"Floating stores does not contain the target block."
    ~pp:(fun ppf target_blk ->
      Format.fprintf
        ppf
        "Failed to export floating blocks as the target block %a cannot be \
         found."
        pp_block_descriptor
        target_blk)
    (obj1 (req "target" block_descriptor_encoding))
    (function Missing_target_block descr -> Some descr | _ -> None)
    (fun descr -> Missing_target_block descr) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.cannot_read_floating_stores"
    ~title:"Cannot read floating stores"
    ~description:"Unable to read floating stores."
    ~pp:(fun ppf msg ->
      Format.fprintf ppf "Cannot read the floating blocks stores: %s" msg)
    (obj1 (req "msg" string))
    (function Cannot_read_floating_store msg -> Some msg | _ -> None)
    (fun msg -> Cannot_read_floating_store msg) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.cannot_retrieve_block_interval"
    ~title:"Cannot retrieve block interval"
    ~description:"Cannot retrieve block interval from store"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Cannot retrieve block interval: failed to retrieve blocks.")
    unit
    (function Cannot_retrieve_block_interval -> Some () | _ -> None)
    (fun () -> Cannot_retrieve_block_interval) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.invalid_cemented_file"
    ~title:"Invalid cemented file"
    ~description:
      "Encountered an invalid cemented file while restoring the cemented store"
    ~pp:(fun ppf file ->
      Format.fprintf
        ppf
        "Failed to restore cemented blocks. Encountered an invalid file '%s'."
        file)
    (obj1 (req "file" string))
    (function Invalid_cemented_file s -> Some s | _ -> None)
    (fun s -> Invalid_cemented_file s) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.missing_cemented_file"
    ~title:"Missing cemented file"
    ~description:"Cannot find cemented file while restoring cemented store"
    ~pp:(fun ppf file ->
      Format.fprintf
        ppf
        "Failed to restore cemented blocks. The cycle '%s' is missing."
        file)
    (obj1 (req "cycle" string))
    (function Missing_cemented_file s -> Some s | _ -> None)
    (fun s -> Missing_cemented_file s) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.corrupted_floating_store"
    ~title:"Corrupted floating store"
    ~description:"Failed to read floating store"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Failed to restore floating blocks. The floating store is corrupted.")
    unit
    (function Corrupted_floating_store -> Some () | _ -> None)
    (fun () -> Corrupted_floating_store) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.protocol_import_invalid_file"
    ~title:"Protocol import invalid file"
    ~description:"Failed to import protocol as the filename is invalid"
    ~pp:(fun ppf filename ->
      Format.fprintf
        ppf
        "Failed to import protocol. The protocol file '%s' is invalid"
        filename)
    (obj1 (req "filename" string))
    (function Invalid_protocol_file filename -> Some filename | _ -> None)
    (fun filename -> Invalid_protocol_file filename) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.target_block_validation_failed"
    ~title:"target block validation failed"
    ~description:"Failed to validate the target block."
    ~pp:(fun ppf (h, errs) ->
      Format.fprintf ppf "Failed to validate block %a: %s" Block_hash.pp h errs)
    (obj2 (req "block" Block_hash.encoding) (req "errors" string))
    (function
      | Target_block_validation_failed (h, errs) -> Some (h, errs) | _ -> None)
    (fun (h, errs) -> Target_block_validation_failed (h, errs)) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.directory_already_exists"
    ~title:"Directory already exists"
    ~description:"The given data directory already exists."
    ~pp:(fun ppf s ->
      Format.fprintf
        ppf
        "Failed to import snasphot as the given directory %s already exists."
        s)
    (obj1 (req "path" string))
    (function Directory_already_exists s -> Some s | _ -> None)
    (fun s -> Directory_already_exists s) ;
  register_error_kind
    `Permanent
    ~id:"snapshot.empty_floating_store"
    ~title:"Empty floating store"
    ~description:"Floating store is empty."
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Failed to export floating blocks: the floating store does not contain \
         any blocks (broken invariant).")
    unit
    (function Empty_floating_store -> Some () | _ -> None)
    (fun () -> Empty_floating_store) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.cannot_create_tmp_export_directory"
    ~title:"Cannot create temporary export directory"
    ~description:"Cannot create temporary directory for exporting snapshot."
    ~pp:(fun ppf msg ->
      Format.fprintf
        ppf
        "Cannot export snapshot: the temporary snapshot directory already \
         exists. Please remove %s and restart the snapshot export."
        msg)
    (obj1 (req "message" string))
    (function Cannot_create_tmp_export_directory str -> Some str | _ -> None)
    (fun str -> Cannot_create_tmp_export_directory str) ;
  register_error_kind
    `Permanent
    ~id:"snapshots.inconsistent_chain_import"
    ~title:"Inconsistent chain import"
    ~description:
      "The imported chain is inconsistent with the target data directory."
    ~pp:(fun ppf (expected, got) ->
      Format.fprintf
        ppf
        "The chain name contained in the snapshot file (%a) is not consistent \
         with the network configured in the targeted data directory (%a). \
         Please check your configuration file."
        Distributed_db_version.Name.pp
        expected
        Distributed_db_version.Name.pp
        got)
    (obj2
       (req "expected" Distributed_db_version.Name.encoding)
       (req "got" Distributed_db_version.Name.encoding))
    (function
      | Inconsistent_chain_import {expected; got} -> Some (expected, got)
      | _ -> None)
    (fun (expected, got) -> Inconsistent_chain_import {expected; got}) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.inconsistent_imported_block"
    ~title:"Inconsistent imported block"
    ~description:"The imported block is not the expected one."
    ~pp:(fun ppf (got, exp) ->
      Format.fprintf
        ppf
        "The block contained in the file is %a instead of %a."
        Block_hash.pp
        got
        Block_hash.pp
        exp)
    (obj2
       (req "block_hash" Block_hash.encoding)
       (req "block_hash_expected" Block_hash.encoding))
    (function
      | Inconsistent_imported_block (got, exp) -> Some (got, exp) | _ -> None)
    (fun (got, exp) -> Inconsistent_imported_block (got, exp)) ;
  register_error_kind
    `Permanent
    ~id:"Snapshot.wrong_snapshot_file"
    ~title:"Wrong snapshot file"
    ~description:"Error while opening snapshot file"
    ~pp:(fun ppf filename ->
      Format.fprintf
        ppf
        "Failed to read snapshot file %s. The provided file is inconsistent or \
         is from Octez 9.7 (or before) and it cannot be imported anymore."
        filename)
    Data_encoding.(obj1 (req "filename" string))
    (function Wrong_snapshot_file {filename} -> Some filename | _ -> None)
    (fun filename -> Wrong_snapshot_file {filename}) ;
  register_error_kind
    `Permanent
    ~id:"Snapshot.invalid_chain_store_export"
    ~title:"Invalid chain store export"
    ~description:"Error while exporting snapshot"
    ~pp:(fun ppf (chain_id, store_dir) ->
      Format.fprintf
        ppf
        "Failed to export snapshot. Cannot find chain %a from store located at \
         directory %s."
        Chain_id.pp_short
        chain_id
        store_dir)
    Data_encoding.(
      obj2 (req "chain_id" Chain_id.encoding) (req "store_dir" string))
    (function
      | Invalid_chain_store_export (chain_id, store_dir) ->
          Some (chain_id, store_dir)
      | _ -> None)
    (fun (chain_id, store_dir) ->
      Invalid_chain_store_export (chain_id, store_dir))

type metadata = {
  chain_name : Distributed_db_version.Name.t;
  history_mode : History_mode.t;
  block_hash : Block_hash.t;
  level : Int32.t;
  timestamp : Time.Protocol.t;
  context_elements : int;
}

let metadata_encoding =
  let open Data_encoding in
  conv
    (fun {
           chain_name;
           history_mode;
           block_hash;
           level;
           timestamp;
           context_elements;
         } ->
      (chain_name, history_mode, block_hash, level, timestamp, context_elements))
    (fun ( chain_name,
           history_mode,
           block_hash,
           level,
           timestamp,
           context_elements ) ->
      {chain_name; history_mode; block_hash; level; timestamp; context_elements})
    (obj6
       (req "chain_name" Distributed_db_version.Name.encoding)
       (req "mode" History_mode.encoding)
       (req "block_hash" Block_hash.encoding)
       (req "level" int32)
       (req "timestamp" Time.Protocol.encoding)
       (req "context_elements" int31))

(* A snapshot header is made of a version and some metadata. The
   encoding of the version aims to be fixed between snapshots
   version. On the contrary, metadata may evolve with snapshot
   versions. *)
type header = Version.t * metadata

type snapshot_header = Current_header of header

let pp_snapshot_header ppf = function
  | Current_header
      (version, {chain_name; history_mode; block_hash; level; timestamp; _}) ->
      Format.fprintf
        ppf
        "chain %a, block hash %a at level %ld, timestamp %a in %a (snapshot \
         version %d)"
        Distributed_db_version.Name.pp
        chain_name
        Block_hash.pp
        block_hash
        level
        Time.Protocol.pp_hum
        timestamp
        History_mode.pp_short
        history_mode
        version

let version = function Current_header (version, _) -> version

type snapshot_format = Tar | Raw

let snapshot_format_encoding =
  Data_encoding.string_enum [("Tar", Tar); ("Raw", Raw)]

let pp_snapshot_format ppf = function
  | Tar -> Format.fprintf ppf "tar (single file)"
  | Raw -> Format.fprintf ppf "directory"

(* To speed up the import of the cemented blocks we increase,
   temporarily the index cache size. *)
let cemented_import_log_size = 100_000

type block_data = {
  block_header : Block_header.t;
  operations : Operation.t list list;
  predecessor_header : Block_header.t;
  predecessor_block_metadata_hash : Block_metadata_hash.t option;
  predecessor_ops_metadata_hash : Operation_metadata_list_list_hash.t option;
}

let block_data_encoding =
  let open Data_encoding in
  conv
    (fun {
           block_header;
           operations;
           predecessor_header;
           predecessor_block_metadata_hash;
           predecessor_ops_metadata_hash;
         } ->
      ( operations,
        block_header,
        predecessor_header,
        predecessor_block_metadata_hash,
        predecessor_ops_metadata_hash ))
    (fun ( operations,
           block_header,
           predecessor_header,
           predecessor_block_metadata_hash,
           predecessor_ops_metadata_hash ) ->
      {
        block_header;
        operations;
        predecessor_header;
        predecessor_block_metadata_hash;
        predecessor_ops_metadata_hash;
      })
    (obj5
       (req "operations" (list (list (dynamic_size Operation.encoding))))
       (req "block_header" (dynamic_size Block_header.encoding))
       (req "predecessor_header" (dynamic_size Block_header.encoding))
       (opt "predecessor_block_metadata_hash" Block_metadata_hash.encoding)
       (opt
          "predecessor_ops_metadata_hash"
          Operation_metadata_list_list_hash.encoding))

let default_snapshot_filename metadata =
  let {chain_name; block_hash; level; history_mode; _} = metadata in
  (* The generated filename follows this pattern:
     <NETWORK>-<BLOCK_HASH>-<BLOCK_LEVEL>.<SNAPSHOT_HISTORY_MODE> *)
  let default_name =
    Format.asprintf
      "%a-%a-%ld.%a"
      Distributed_db_version.Name.pp
      chain_name
      Block_hash.pp
      block_hash
      level
      History_mode.pp_short
      history_mode
  in
  let unique_name name =
    let rec aux i =
      let new_name = Format.sprintf "%s-%d" name i in
      if Sys.file_exists new_name then aux (i + 1) else new_name
    in
    aux 1
  in
  if Sys.file_exists default_name then unique_name default_name
  else default_name

let ensure_valid_tmp_snapshot_path snapshot_tmp_dir =
  fail_when
    (Sys.file_exists (Naming.dir_path snapshot_tmp_dir))
    (Cannot_create_tmp_export_directory (Naming.dir_path snapshot_tmp_dir))

let ensure_valid_export_path = function
  | Some path -> fail_when (Sys.file_exists path) (Invalid_export_path path)
  | None -> return_unit

let clean_all paths =
  Lwt_list.iter_s
    (fun path ->
      Unit.catch_s (fun () ->
          if Sys.is_directory path then Lwt_utils_unix.remove_dir path
          else Lwt_unix.unlink path))
    paths

(* This module allows to create a tar archive by adding files to it,
   one by one. It can be seen as a list of contiguous files (made of a
   header followed by a raw data) closed by a specific end of file
   flag. *)
module Onthefly : sig
  (* The type of a file contained in the tar archive. It is basically
     a header and a raw data. *)
  type file

  (* The type of an output tar archive. *)
  type o

  (* The type of an input tar archive. *)
  type i

  (* output utilities *)

  (* [open_out ~file] opens a tar archive as an output archive located at
     [file]. *)
  val open_out : file:string -> o Lwt.t

  (* [close_out tar] closes an output tar archive. *)
  val close_out : o -> unit Lwt.t

  (* [add_raw_and_finalize tar ~f ~filename] exposes a file
     descriptor of the tar archive through [f] to be able to write
     arbitrary data in the [tar]. When [f] terminates, a valid tar
     header referenced by [filename] is written *)
  val add_raw_and_finalize :
    o -> f:(Lwt_unix.file_descr -> 'a Lwt.t) -> filename:string -> 'a Lwt.t

  (* [add_file_and_finalize tar ~file ~filename] copies the [file], and
     reference it through the given [filename], into a [tar]. It handles all
     specific operations an returns a handler ready to be enriched. *)
  val add_file_and_finalize : o -> file:string -> filename:string -> unit Lwt.t

  (* [add_directory_and_finalize ?archive_prefix tar ~dir_path] copies
     the [dir_path] and all its sub directories or files into a
     [tar]. By default, the tar archive file path are similar to the
     [dir_path]. They can be overridden using the [archive_prefix].
     It handles all specific operations an returns a handler ready to
     be enriched.
     For example,
     if the directory `/path/to/data` contains 2 files `a` and `b`:
     With the default behaviour, the tar will contain two files:
         - `/path/to/data/a`
         - `/path/to/data/b`
     If the archive_prefix is given with value `local_path`, the tar
     archive will contain:
        - `local_path/a`
        - `local_path/b`
  *)
  val add_directory_and_finalize :
    ?archive_prefix:string -> o -> dir_path:string -> unit Lwt.t

  (* input utilities *)

  (* [open_out ~file] opens a tar archive as an input archive located at
     [file]. *)
  val open_in : file:string -> i Lwt.t

  (* [close_in tar] closes an input tar archive. *)
  val close_in : i -> unit Lwt.t

  (* [list_files tar] returns the list of files contained in the
     [tar]. *)
  val list_files : i -> file list Lwt.t

  (* [get_file tar ~filename] returns the first occurrence of the
     file name [filename] from [tar]. *)
  val get_file : i -> filename:string -> file option Lwt.t

  (* [get_filename file] returns the file name of a [file] contained
     in a tar. *)
  val get_filename : file -> string

  (* [get_file_size file] returns the file size of a [file] contained
     in a tar. *)
  val get_file_size : file -> int64

  (* [get_raw_input_fd tar] returns the file descriptor to read
     directly in the tar file. It is no recommended to use it. *)
  val get_raw_input_fd : i -> Lwt_unix.file_descr

  (* [get_raw_file_ofs file] returns the position offset, from the
     beginning of the tar archive, of the given [file]. *)
  val get_raw_file_ofs : file -> int64

  (* [find_file tar ~filename] returns the file corresponding to the
     given [filename] within the given [tar]. *)
  val find_file : i -> filename:string -> file option Lwt.t

  (* [find_files_with_common_path tar ~pattern] returns, from the [tar] all
      the files matching the given [pattern]. *)
  val find_files_with_common_path : i -> pattern:string -> file list Lwt.t

  (* [read_raw tar file] returns a file descriptor on the [tar] file
     which is pointing toward the data of the given [file] *)
  val read_raw : i -> file -> Lwt_unix.file_descr Lwt.t

  (* [load_file tar file] loads the [file] from the [tar] and returns
     it as bytes.
     Warning, this function loads the whole data in
     memory. *)
  val load_file : i -> file -> string Lwt.t

  (* [load_from_filename tar ~filename] loads the file with the name
     [filename] from the given [tar] and returns it as
     bytes.
     Warning, this function loads the whole data in memory *)
  val load_from_filename : i -> filename:string -> string option Lwt.t

  (* [copy_to_file tar file ~dst] copies the [file] from the [tar]
     into new file designated by [dst]. *)
  val copy_to_file : i -> file -> dst:string -> unit Lwt.t
end = struct
  include Tar

  module Reader = struct
    type in_channel = Lwt_unix.file_descr

    type 'a t = 'a Lwt.t

    let really_read fd = Lwt_cstruct.(complete (read fd))

    let skip (ifd : Lwt_unix.file_descr) (n : int) =
      let buffer_size = 32768 in
      let buffer = Cstruct.create buffer_size in
      let rec loop (n : int) =
        if n <= 0 then Lwt.return ()
        else
          let amount = min n buffer_size in
          let block = Cstruct.sub buffer 0 amount in
          really_read ifd block >>= fun () -> loop (n - amount)
      in
      loop n
  end

  module Writer = struct
    type out_channel = Lwt_unix.file_descr

    type 'a t = 'a Lwt.t

    let really_write fd = Lwt_cstruct.(complete (write fd))
  end

  module HR = Tar.HeaderReader (Lwt) (Reader)
  module HW = Tar.HeaderWriter (Lwt) (Writer)

  type file = {header : Tar.Header.t; data_ofs : Int64.t}

  type o = {
    mutable current_pos : Int64.t;
    mutable data_pos : Int64.t;
    fd : Lwt_unix.file_descr;
  }

  let open_out ~file =
    Lwt_unix.openfile file Unix.[O_WRONLY; O_CREAT] 0o777 >>= fun fd ->
    let data_pos = Int64.of_int Header.length in
    Lwt_unix.LargeFile.lseek fd data_pos SEEK_SET >>= fun _ ->
    Lwt.return {current_pos = 0L; data_pos; fd}

  (* Writes the double zero blocks to close the archive, as it is
     defined in the RFC.*)
  let close_out t =
    Lwt_unix.LargeFile.lseek t.fd t.current_pos SEEK_SET >>= fun _eof ->
    Writer.really_write t.fd Tar.Header.zero_block >>= fun () ->
    Writer.really_write t.fd Tar.Header.zero_block >>= fun () ->
    Lwt_unix.close t.fd

  (* Builds a tar header for the given sequence of bytes *)
  let header_of_bytes ?level ~filename ~data_size (file : Lwt_unix.file_descr) :
      Header.t Lwt.t =
    let level =
      match level with None -> Tar.Header.V7 | Some level -> level
    in
    (* Use Posix by default instead of V7? *)
    Lwt_unix.LargeFile.fstat file >>= fun stat ->
    Lwt_unix.getpwuid stat.Lwt_unix.LargeFile.st_uid >>= fun pwent ->
    Lwt_unix.getgrgid stat.Lwt_unix.LargeFile.st_gid >>= fun grent ->
    let file_mode = stat.Lwt_unix.LargeFile.st_perm in
    let user_id = stat.Lwt_unix.LargeFile.st_uid in
    let group_id = stat.Lwt_unix.LargeFile.st_gid in
    let mod_time = Int64.of_float stat.Lwt_unix.LargeFile.st_mtime in
    let link_indicator = Tar.Header.Link.Normal in
    let link_name = "" in
    let uname = if level = V7 then "" else pwent.Lwt_unix.pw_name in
    let gname = if level = V7 then "" else grent.Lwt_unix.gr_name in
    let devmajor =
      if level = Ustar then stat.Lwt_unix.LargeFile.st_dev else 0
    in
    let devminor =
      if level = Ustar then stat.Lwt_unix.LargeFile.st_rdev else 0
    in
    Lwt.return
      (Tar.Header.make
         ~file_mode
         ~user_id
         ~group_id
         ~mod_time
         ~link_indicator
         ~link_name
         ~uname
         ~gname
         ~devmajor
         ~devminor
         filename
         data_size)

  (* [finalize tar ~bytes_written ~filename] writes the header
     corresponding to the quantity of data given through
     [bytes_written] in the [tar]. Then, it finalizes the file and returns a new
     handle. The file descriptor of that handle is positioned to allow
     writing data. *)
  let finalize t ~bytes_written ~filename =
    (* Build the header based of the bytes_written *)
    header_of_bytes ~filename ~data_size:bytes_written t.fd >>= fun header ->
    let header_length = Int64.of_int Header.length in
    (* Compute and right the adequate padding for finalizing a block data *)
    let c = Tar.Header.zero_padding header in
    let zero_padding = Cstruct.to_bytes c in
    let zero_padding_length = Bytes.length zero_padding in
    (* Make sure that the fd position is after the written data *)
    Lwt_unix.LargeFile.lseek t.fd (Int64.add t.data_pos bytes_written) SEEK_SET
    >>= fun _ ->
    Lwt_unix.write t.fd zero_padding 0 zero_padding_length >>= fun _ ->
    (* Go back to the header position to write it *)
    Lwt_unix.LargeFile.lseek t.fd t.current_pos SEEK_SET >>= fun _ ->
    HW.write header t.fd >>= fun () ->
    let next_block_start =
      Int64.(
        add
          (add t.current_pos header_length)
          (add bytes_written (of_int zero_padding_length)))
    in
    let next_data_pos = Int64.(add next_block_start header_length) in
    (* Set fd position to be ready for next data write *)
    Lwt_unix.LargeFile.lseek t.fd next_data_pos SEEK_SET >>= fun _ ->
    t.current_pos <- next_block_start ;
    t.data_pos <- next_data_pos ;
    Lwt.return_unit

  let add_raw_and_finalize t ~f ~filename =
    Lwt.catch
      (fun () -> f t.fd)
      (function
        | exn ->
            (* Rewind file descriptor to the start of the current data
               slot. Then, the next write will overwrite the corrupted
               data. *)
            Lwt_unix.LargeFile.lseek t.fd t.data_pos SEEK_SET >>= fun _ ->
            Lwt.fail exn)
    >>= fun res ->
    Lwt_unix.LargeFile.lseek t.fd 0L SEEK_CUR >>= fun eor ->
    let bytes_written = Int64.sub eor t.data_pos in
    finalize t ~bytes_written ~filename >>= fun () -> Lwt.return res

  let copy_n ifd ofd n =
    let block_size = 32768 in
    let buffer = Cstruct.create block_size in
    let rec loop remaining =
      if remaining = 0L then Lwt.return ()
      else
        let this = Int64.(to_int (min (of_int block_size) remaining)) in
        let block = Cstruct.sub buffer 0 this in
        Reader.really_read ifd block >>= fun () ->
        Writer.really_write ofd block >>= fun () ->
        loop Int64.(sub remaining (of_int this))
    in
    loop n

  let add_file_and_finalize tar ~file ~filename =
    Lwt_unix.openfile file [Unix.O_RDONLY] 0o777 >>= fun fd ->
    Lwt_unix.LargeFile.fstat fd >>= fun stat ->
    let file_size = stat.st_size in
    copy_n fd tar.fd file_size >>= fun () ->
    finalize tar ~bytes_written:file_size ~filename >>= fun () ->
    Lwt_unix.close fd >>= fun () -> Lwt.return_unit

  let rec readdir dir_handler =
    Option.catch_os
      ~catch_only:(function End_of_file -> true | _ -> false)
      (fun () ->
        Lwt_unix.readdir dir_handler >>= function
        | filename
          when filename = Filename.current_dir_name
               || filename = Filename.parent_dir_name ->
            readdir dir_handler
        | any -> Lwt.return_some any)

  let enumerate path =
    let rec aux prefix dir_handler acc =
      readdir dir_handler >>= function
      | Some any ->
          let full_path = Filename.concat prefix any in
          if Sys.is_directory full_path then
            Lwt_unix.opendir full_path >>= fun new_dir_handler ->
            aux full_path new_dir_handler [] >>= fun sub_folder ->
            Lwt_unix.closedir new_dir_handler >>= fun () ->
            aux prefix dir_handler (sub_folder @ acc)
          else aux prefix dir_handler (full_path :: acc)
      | None -> Lwt.return acc
    in
    Lwt_unix.opendir path >>= fun dir_handler ->
    aux path dir_handler [] >>= fun res ->
    Lwt_unix.closedir dir_handler >>= fun () -> Lwt.return res

  let add_directory_and_finalize ?archive_prefix tar ~dir_path =
    let dir_prefix = Filename.dirname dir_path in
    enumerate dir_path >>= fun file_paths ->
    let archive_prefix = Option.value archive_prefix ~default:dir_prefix in
    let files =
      let dir_length = String.length dir_prefix in
      List.map
        (fun file_path ->
          let filename =
            String.sub
              file_path
              (dir_length + 1)
              String.(length file_path - dir_length - 1)
          in
          (file_path, filename))
        file_paths
    in
    Lwt_list.iter_s
      (fun (file, filename) ->
        add_file_and_finalize
          tar
          ~file
          ~filename:Filename.(concat archive_prefix filename))
      files

  type i = {
    mutable current_pos : Int64.t;
    mutable data_pos : Int64.t;
    fd : Lwt_unix.file_descr;
    mutable files : file list option;
  }

  let open_in ~file =
    Lwt_unix.openfile file Unix.[O_RDONLY] 0o444 >>= fun fd ->
    let data_pos = Int64.of_int Header.length in
    let files = None in
    Lwt.return {current_pos = 0L; data_pos; fd; files}

  let close_in t = Lwt_unix.close t.fd

  (*[list_files tar] returns the list of files contained in the
     [tar]. *)
  let list_files t =
    Lwt_unix.LargeFile.lseek t.fd 0L SEEK_SET >>= fun _ ->
    (* This implementation is way faster than the one implemented in
       Tar_lwt_unix.Archive.list function which reads the whole file
    *)
    let rec loop pos acc =
      Lwt_unix.LargeFile.lseek t.fd pos SEEK_SET >>= fun _ ->
      Lwt_unix.lseek t.fd 0 SEEK_CUR >>= fun _ ->
      HR.read t.fd >>= function
      | Error `Eof -> Lwt.return (List.rev acc)
      | Ok hdr ->
          (* Header length can be 1024 if extended *)
          Lwt_unix.LargeFile.lseek t.fd 0L SEEK_CUR >>= fun data_pos ->
          let header_length = Int64.sub data_pos pos in
          let file_size = hdr.Tar.Header.file_size in
          let padding =
            Int64.of_int (Tar.Header.compute_zero_padding_length hdr)
          in
          let next_header = Int64.(add (add file_size padding) header_length) in
          Lwt_unix.LargeFile.lseek t.fd next_header SEEK_SET >>= fun _ ->
          let h = {header = hdr; data_ofs = data_pos} in
          loop (Int64.add pos next_header) (h :: acc)
    in
    loop 0L []

  let update_files t files = t.files <- Some files

  let may_update_files t files =
    match t.files with Some _ -> () | None -> update_files t files

  let get_files t =
    match t.files with
    | Some files -> Lwt.return files
    | None ->
        list_files t >>= fun files ->
        update_files t files ;
        Lwt.return files

  let get_file tar ~filename =
    get_files tar >>= fun files ->
    Lwt.return
      (List.find_opt (fun {header; _} -> header.file_name = filename) files)

  let get_filename {header; _} = header.Tar.Header.file_name

  let get_file_size {header; _} = header.Tar.Header.file_size

  (*[get_raw tar file] loads the [file] from [tar] in memory *)
  let get_raw t {header; data_ofs} =
    Lwt_unix.LargeFile.lseek t.fd data_ofs SEEK_SET >>= fun _ ->
    let data_size = Int64.to_int header.file_size in
    let buf = Bytes.create data_size in
    Lwt_unix.read t.fd buf 0 data_size >>= fun _ ->
    Lwt.return (Bytes.unsafe_to_string buf)

  let get_raw_input_fd {fd; _} = fd

  let get_raw_file_ofs {data_ofs; _} = data_ofs

  let find_file t ~filename =
    (* If the files were already listed, there is no need to read the whole tar archive.*)
    match t.files with
    | Some _ -> get_file t ~filename
    | None ->
        Lwt_unix.LargeFile.lseek t.fd 0L SEEK_SET >>= fun _ ->
        let rec loop pos acc =
          Lwt_unix.LargeFile.lseek t.fd pos SEEK_SET >>= fun _ ->
          Lwt_unix.lseek t.fd 0 SEEK_CUR >>= fun _ ->
          HR.read t.fd >>= function
          | Error `Eof ->
              (* If the end of file is reached, all the files were
                 enumerated without finding the expected one. In this case,
                 the files are updated. *)
              may_update_files t acc ;
              Lwt.return_none
          | Ok hdr ->
              (* Header length can be 1024 if extended *)
              Lwt_unix.LargeFile.lseek t.fd 0L SEEK_CUR >>= fun data_pos ->
              if hdr.file_name = filename then
                Lwt.return_some {header = hdr; data_ofs = data_pos}
              else
                let header_length = Int64.sub data_pos pos in
                let file_size = hdr.Tar.Header.file_size in
                let padding =
                  Int64.of_int (Tar.Header.compute_zero_padding_length hdr)
                in
                let next_header =
                  Int64.(add (add file_size padding) header_length)
                in
                Lwt_unix.LargeFile.lseek t.fd next_header SEEK_SET >>= fun _ ->
                let h = {header = hdr; data_ofs = data_pos} in
                loop (Int64.add pos next_header) (h :: acc)
        in
        loop 0L []

  let find_files_with_common_path t ~pattern =
    get_files t >>= fun files ->
    let pattern = Re.compile (Re.Perl.re pattern) in
    Lwt.return
      (List.filter
         (fun {header; _} -> Re.execp pattern header.Tar.Header.file_name)
         files)

  let read_raw t {data_ofs; _} =
    Lwt_unix.LargeFile.lseek t.fd data_ofs SEEK_SET >>= fun _ -> Lwt.return t.fd

  let load_file t file = get_raw t file

  let load_from_filename t ~filename =
    get_file t ~filename >>= function
    | Some hd -> get_raw t hd >>= fun str -> Lwt.return_some str
    | None -> Lwt.return_none

  let copy_to_file tar {header; data_ofs} ~dst =
    Lwt_unix.LargeFile.lseek tar.fd data_ofs SEEK_SET >>= fun _ ->
    Lwt_unix.openfile dst Unix.[O_WRONLY; O_CREAT; O_TRUNC] 0o644 >>= fun fd ->
    Lwt.finalize
      (fun () -> copy_n tar.fd fd header.Tar.Header.file_size)
      (fun () -> Lwt_unix.close fd)
end

module type EXPORTER = sig
  type t

  val init : string option -> t tzresult Lwt.t

  val write_block_data :
    t ->
    predecessor_header:Block_header.t ->
    predecessor_block_metadata_hash:Block_metadata_hash.t option ->
    predecessor_ops_metadata_hash:Operation_metadata_list_list_hash.t option ->
    export_block:Store.Block.t ->
    unit Lwt.t

  val dump_context : t -> Context.index -> Context_hash.t -> int tzresult Lwt.t

  val copy_cemented_block :
    t -> file:string -> start_level:int32 -> end_level:int32 -> unit Lwt.t

  val create_cemented_block_indexes :
    t ->
    Cemented_block_store.Cemented_block_level_index.t
    * Cemented_block_store.Cemented_block_hash_index.t

  val write_cemented_block_indexes : t -> unit Lwt.t

  val filter_cemented_block_indexes : t -> limit:int32 -> unit

  val write_floating_blocks :
    t -> f:(Lwt_unix.file_descr -> 'a Lwt.t) -> 'a Lwt.t

  val write_protocols_table :
    t -> f:(Lwt_unix.file_descr -> 'a Lwt.t) -> 'a Lwt.t

  val copy_protocol : t -> src:string -> dst_ph:Protocol_hash.t -> unit Lwt.t

  val write_metadata : t -> metadata -> unit tzresult Lwt.t

  val cleaner : ?to_clean:string list -> t -> unit Lwt.t

  val finalize : t -> metadata -> string tzresult Lwt.t
end

module Raw_exporter : EXPORTER = struct
  type t = {
    snapshot_dir : string option;
    snapshot_tmp_dir : [`Snapshot_tmp_dir] Naming.directory;
    snapshot_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    snapshot_protocol_dir : [`Protocol_dir] Naming.directory;
  }

  let init snapshot_dir =
    (* Creates the requested export folder and its hierarchy *)
    let snapshot_tmp_dir =
      let tmp_dir = Naming.snapshot_dir ?snapshot_path:snapshot_dir () in
      Naming.snapshot_tmp_dir tmp_dir
    in
    ensure_valid_export_path snapshot_dir >>=? fun () ->
    ensure_valid_tmp_snapshot_path snapshot_tmp_dir >>=? fun () ->
    Lwt_unix.mkdir (Naming.dir_path snapshot_tmp_dir) 0o755 >>= fun () ->
    let snapshot_cemented_dir = Naming.cemented_blocks_dir snapshot_tmp_dir in
    Lwt_unix.mkdir (Naming.dir_path snapshot_cemented_dir) 0o755 >>= fun () ->
    let snapshot_protocol_dir = Naming.protocol_store_dir snapshot_tmp_dir in
    Lwt_unix.mkdir (Naming.dir_path snapshot_protocol_dir) 0o755 >>= fun () ->
    let version_file =
      Naming.snapshot_version_file snapshot_tmp_dir |> Naming.file_path
    in
    let version_json =
      Data_encoding.Json.construct Version.version_encoding current_version
    in
    Lwt_utils_unix.Json.write_file version_file version_json >>=? fun () ->
    return
      {
        snapshot_dir;
        snapshot_tmp_dir;
        snapshot_cemented_dir;
        snapshot_protocol_dir;
      }

  let write_block_data t ~predecessor_header ~predecessor_block_metadata_hash
      ~predecessor_ops_metadata_hash ~export_block =
    let block_data =
      {
        block_header = Store.Block.header export_block;
        operations = Store.Block.operations export_block;
        predecessor_header;
        predecessor_block_metadata_hash;
        predecessor_ops_metadata_hash;
      }
    in
    let bytes =
      Data_encoding.Binary.to_bytes_exn block_data_encoding block_data
    in
    let file =
      Naming.(snapshot_block_data_file t.snapshot_tmp_dir |> file_path)
    in
    Lwt_unix.openfile file Unix.[O_CREAT; O_TRUNC; O_WRONLY] 0o444 >>= fun fd ->
    Lwt.finalize
      (fun () -> Lwt_utils_unix.write_bytes fd bytes)
      (fun () -> Lwt_unix.close fd)

  let dump_context t context_index context_hash =
    Lwt_unix.openfile
      Naming.(snapshot_context_file t.snapshot_tmp_dir |> file_path)
      Unix.[O_CREAT; O_TRUNC; O_WRONLY]
      0o444
    >>= fun fd ->
    Lwt.finalize
      (fun () -> Context.dump_context context_index context_hash ~fd)
      (fun () -> Lwt_unix.close fd)

  let copy_cemented_block t ~file ~start_level ~end_level =
    let filename =
      Naming.(
        cemented_blocks_file t.snapshot_cemented_dir ~start_level ~end_level
        |> file_path)
    in
    Lwt_utils_unix.copy_file ~src:file ~dst:filename

  let create_cemented_block_indexes t =
    let open Cemented_block_store in
    let fresh_level_index =
      Cemented_block_level_index.v
        ~fresh:true
        ~readonly:false
        ~log_size:cemented_import_log_size
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    let fresh_hash_index =
      Cemented_block_hash_index.v
        ~fresh:true
        ~readonly:false
        ~log_size:cemented_import_log_size
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    (fresh_level_index, fresh_hash_index)

  let write_cemented_block_indexes t =
    Lwt.catch
      (fun () ->
        Lwt_unix.unlink
          Naming.(
            file_path
              (cemented_blocks_hash_lock_file
                 (cemented_blocks_hash_index_dir
                    (cemented_blocks_dir t.snapshot_tmp_dir)))))
      (function
        | Unix.Unix_error (ENOENT, _, _) -> Lwt.return_unit
        | exn -> Lwt.fail exn)
    >>= fun () ->
    Lwt.catch
      (fun () ->
        Lwt_unix.unlink
          Naming.(
            file_path
              (cemented_blocks_level_lock_file
                 (cemented_blocks_level_index_dir
                    (cemented_blocks_dir t.snapshot_tmp_dir)))))
      (function
        | Unix.Unix_error (ENOENT, _, _) -> Lwt.return_unit
        | exn -> Lwt.fail exn)

  let filter_cemented_block_indexes t ~limit =
    let open Cemented_block_store in
    let fresh_level_index =
      Cemented_block_level_index.v
        ~fresh:false
        ~readonly:false
        ~log_size:10_000
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    let fresh_hash_index =
      Cemented_block_hash_index.v
        ~fresh:false
        ~readonly:false
        ~log_size:10_000
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    Cemented_block_level_index.filter fresh_level_index (fun (_, level) ->
        level <= limit) ;
    Cemented_block_hash_index.filter fresh_hash_index (fun (level, _) ->
        level <= limit) ;
    Cemented_block_level_index.close fresh_level_index ;
    Cemented_block_hash_index.close fresh_hash_index

  let write_floating_blocks t ~f =
    let floating_file =
      Naming.(snapshot_floating_blocks_file t.snapshot_tmp_dir |> file_path)
    in
    Lwt_unix.openfile floating_file Unix.[O_CREAT; O_TRUNC; O_WRONLY] 0o444
    >>= fun fd -> Lwt.finalize (fun () -> f fd) (fun () -> Lwt_unix.close fd)

  let write_protocols_table t ~f =
    Lwt_unix.openfile
      Naming.(
        snapshot_protocol_levels_file t.snapshot_tmp_dir |> encoded_file_path)
      Unix.[O_CREAT; O_TRUNC; O_WRONLY]
      0o444
    >>= fun fd ->
    Lwt.finalize
      (fun () -> f fd)
      (fun () -> Lwt_unix.close fd >>= fun () -> Lwt.return_unit)

  let copy_protocol t ~src ~dst_ph =
    let dst =
      Naming.(
        protocol_file (protocol_store_dir t.snapshot_tmp_dir) dst_ph
        |> file_path)
    in
    Lwt_utils_unix.copy_file ~src ~dst

  let write_metadata t metadata =
    let metadata_file =
      Naming.(snapshot_metadata_file t.snapshot_tmp_dir |> file_path)
    in
    let metadata_json =
      Data_encoding.Json.(construct metadata_encoding metadata)
    in
    Lwt_utils_unix.Json.write_file metadata_file metadata_json

  let cleaner ?to_clean t =
    Event.(emit cleaning_after_failure ()) >>= fun () ->
    let paths =
      match to_clean with
      | Some paths -> paths
      | None -> [Naming.dir_path t.snapshot_tmp_dir]
    in
    clean_all paths

  let finalize t metadata =
    let snapshot_filename =
      match t.snapshot_dir with
      | Some path -> path
      | None -> default_snapshot_filename metadata
    in
    write_metadata t metadata >>=? fun () ->
    protect
      ~on_error:(fun errors ->
        cleaner ~to_clean:[Naming.dir_path t.snapshot_tmp_dir] t >>= fun () ->
        Lwt.return (Error errors))
      (fun () ->
        Lwt_unix.rename (Naming.dir_path t.snapshot_tmp_dir) snapshot_filename
        >>= fun () -> return snapshot_filename)
end

module Tar_exporter : EXPORTER = struct
  type t = {
    snapshot_file : string option;
    snapshot_tar : [`Tar_archive] Naming.directory;
    snapshot_tar_file : [`Snapshot_tar_file] Naming.file;
    snapshot_tmp_dir : [`Snapshot_tmp_dir] Naming.directory;
    snapshot_tmp_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    snapshot_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    snapshot_protocol_dir : [`Protocol_dir] Naming.directory;
    tar : Onthefly.o;
  }

  let init snapshot_file =
    (* Creates the requested export folder and its hierarchy *)
    let snapshot_tmp_dir =
      let tmp_dir = Naming.snapshot_dir ?snapshot_path:snapshot_file () in
      Naming.snapshot_tmp_dir tmp_dir
    in
    ensure_valid_export_path snapshot_file >>=? fun () ->
    ensure_valid_tmp_snapshot_path snapshot_tmp_dir >>=? fun () ->
    Lwt_unix.mkdir (Naming.dir_path snapshot_tmp_dir) 0o755 >>= fun () ->
    let snapshot_tmp_cemented_dir =
      Naming.cemented_blocks_dir snapshot_tmp_dir
    in
    let snapshot_tar = Naming.snapshot_tar_root in
    let snapshot_cemented_dir = Naming.cemented_blocks_dir snapshot_tar in
    let snapshot_protocol_dir = Naming.protocol_store_dir snapshot_tar in
    let snapshot_tar_file = Naming.snapshot_tmp_tar_file snapshot_tmp_dir in
    Onthefly.open_out ~file:(snapshot_tar_file |> Naming.file_path)
    >>= fun tar ->
    let version_file =
      Naming.snapshot_version_file snapshot_tmp_dir |> Naming.file_path
    in
    let version_json =
      Data_encoding.Json.construct Version.version_encoding current_version
    in
    Lwt_utils_unix.Json.write_file version_file version_json >>=? fun () ->
    Onthefly.add_file_and_finalize
      tar
      ~file:version_file
      ~filename:(Filename.basename version_file)
    >>= fun () ->
    return
      {
        snapshot_file;
        snapshot_tar;
        snapshot_tar_file;
        snapshot_tmp_dir;
        snapshot_tmp_cemented_dir;
        snapshot_cemented_dir;
        snapshot_protocol_dir;
        tar;
      }

  let write_block_data t ~predecessor_header ~predecessor_block_metadata_hash
      ~predecessor_ops_metadata_hash ~export_block =
    let block_data =
      {
        block_header = Store.Block.header export_block;
        operations = Store.Block.operations export_block;
        predecessor_header;
        predecessor_block_metadata_hash;
        predecessor_ops_metadata_hash;
      }
    in
    let bytes =
      Data_encoding.Binary.to_bytes_exn block_data_encoding block_data
    in
    Onthefly.add_raw_and_finalize
      t.tar
      ~f:(fun fd -> Lwt_utils_unix.write_bytes fd bytes)
      ~filename:Naming.(snapshot_block_data_file t.snapshot_tar |> file_path)

  let dump_context t context_index context_hash =
    Onthefly.add_raw_and_finalize
      t.tar
      ~f:(fun context_fd ->
        Context.dump_context context_index context_hash ~fd:context_fd)
      ~filename:Naming.(snapshot_context_file t.snapshot_tar |> file_path)

  let copy_cemented_block t ~file ~start_level ~end_level =
    let cemented_filename =
      Naming.(
        cemented_blocks_file t.snapshot_cemented_dir ~start_level ~end_level
        |> file_path)
    in
    Onthefly.add_file_and_finalize t.tar ~file ~filename:cemented_filename

  let create_cemented_block_indexes t =
    let open Cemented_block_store in
    let fresh_level_index =
      Cemented_block_level_index.v
        ~fresh:true
        ~readonly:false
        ~log_size:cemented_import_log_size
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_tmp_cemented_dir
          |> dir_path)
    in
    let fresh_hash_index =
      Cemented_block_hash_index.v
        ~fresh:true
        ~readonly:false
        ~log_size:cemented_import_log_size
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_tmp_cemented_dir |> dir_path)
    in
    (fresh_level_index, fresh_hash_index)

  let write_cemented_block_indexes t =
    Lwt.catch
      (fun () ->
        Lwt_unix.unlink
          Naming.(
            file_path
              (cemented_blocks_hash_lock_file
                 (cemented_blocks_hash_index_dir t.snapshot_tmp_cemented_dir))))
      (function
        | Unix.Unix_error (ENOENT, _, _) -> Lwt.return_unit
        | exn -> Lwt.fail exn)
    >>= fun () ->
    Lwt.catch
      (fun () ->
        Lwt_unix.unlink
          Naming.(
            file_path
              (cemented_blocks_level_lock_file
                 (cemented_blocks_level_index_dir t.snapshot_tmp_cemented_dir))))
      (function
        | Unix.Unix_error (ENOENT, _, _) -> Lwt.return_unit
        | exn -> Lwt.fail exn)
    >>= fun () ->
    Onthefly.add_directory_and_finalize
      ~archive_prefix:(Naming.dir_path t.snapshot_cemented_dir)
      t.tar
      ~dir_path:
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_tmp_cemented_dir |> dir_path)
    >>= fun () ->
    Onthefly.add_directory_and_finalize
      ~archive_prefix:(Naming.dir_path t.snapshot_cemented_dir)
      t.tar
      ~dir_path:
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_tmp_cemented_dir
          |> dir_path)

  let filter_cemented_block_indexes t ~limit =
    let open Cemented_block_store in
    let fresh_level_index =
      Cemented_block_level_index.v
        ~fresh:false
        ~readonly:false
        ~log_size:10_000
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_tmp_cemented_dir
          |> dir_path)
    in
    let fresh_hash_index =
      Cemented_block_hash_index.v
        ~fresh:false
        ~readonly:false
        ~log_size:10_000
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_tmp_cemented_dir |> dir_path)
    in
    Cemented_block_level_index.filter fresh_level_index (fun (_, level) ->
        level <= limit) ;
    Cemented_block_hash_index.filter fresh_hash_index (fun (level, _) ->
        level <= limit) ;
    Cemented_block_level_index.close fresh_level_index ;
    Cemented_block_hash_index.close fresh_hash_index

  let write_floating_blocks t ~f =
    Onthefly.add_raw_and_finalize
      t.tar
      ~f
      ~filename:
        Naming.(snapshot_floating_blocks_file t.snapshot_tar |> file_path)

  let write_protocols_table t ~f =
    Onthefly.add_raw_and_finalize
      t.tar
      ~f
      ~filename:
        Naming.(
          snapshot_protocol_levels_file t.snapshot_tar |> encoded_file_path)

  let copy_protocol t ~src ~dst_ph =
    let dst =
      Filename.(
        concat
          (Naming.dir_path t.snapshot_protocol_dir)
          (Protocol_hash.to_b58check dst_ph))
    in
    Onthefly.add_file_and_finalize t.tar ~file:src ~filename:dst

  let write_metadata t metadata =
    let metadata_json =
      Data_encoding.Json.(construct metadata_encoding metadata)
    in
    let metadata_file =
      Naming.snapshot_metadata_file t.snapshot_tmp_dir |> Naming.file_path
    in
    Lwt_utils_unix.Json.write_file metadata_file metadata_json >>=? fun () ->
    Onthefly.add_file_and_finalize
      t.tar
      ~file:metadata_file
      ~filename:(Filename.basename metadata_file)
    >>= fun () -> return_unit

  let cleaner ?to_clean t =
    let paths =
      match to_clean with
      | Some paths -> paths
      | None -> [Naming.dir_path t.snapshot_tmp_dir]
    in
    clean_all paths

  let finalize t metadata =
    let snapshot_filename =
      match t.snapshot_file with
      | Some path -> path
      | None -> default_snapshot_filename metadata
    in
    write_metadata t metadata >>=? fun () ->
    Onthefly.close_out t.tar >>= fun () ->
    protect
      ~on_error:(fun errors ->
        cleaner ~to_clean:[Naming.dir_path t.snapshot_tmp_dir] t >>= fun () ->
        Lwt.return (Error errors))
      (fun () ->
        Lwt_unix.rename
          Naming.(snapshot_tmp_tar_file t.snapshot_tmp_dir |> file_path)
          snapshot_filename
        >>= fun () ->
        Lwt_utils_unix.remove_dir (Naming.dir_path t.snapshot_tmp_dir)
        >>= fun () -> return snapshot_filename)
end

module type Snapshot_exporter = sig
  type t

  val export :
    ?snapshot_path:string ->
    ?rolling:bool ->
    block:Block_services.block ->
    store_dir:string ->
    context_dir:string ->
    chain_name:Distributed_db_version.Name.t ->
    Genesis.t ->
    unit tzresult Lwt.t
end

module Make_snapshot_exporter (Exporter : EXPORTER) : Snapshot_exporter = struct
  type t = Exporter.t

  let init = Exporter.init

  let copy_cemented_blocks snapshot_exporter ~should_filter_indexes
      (files : Cemented_block_store.cemented_blocks_file list) =
    let open Cemented_block_store in
    let nb_cycles = List.length files in
    (* Rebuild fresh indexes: cannot cp because of concurrent accesses *)
    let (fresh_level_index, fresh_hash_index) =
      Exporter.create_cemented_block_indexes snapshot_exporter
    in
    protect (fun () ->
        Animation.display_progress
          ~pp_print_step:(fun fmt i ->
            Format.fprintf
              fmt
              "Copying cemented blocks and populating indexes: %d/%d cycles"
              i
              nb_cycles)
          (fun notify ->
            (* Bound the number of copying threads *)
            let tasks =
              let rec loop acc l =
                let (l, r) = List.split_n 20 l in
                if r = [] then l :: acc else loop (l :: acc) r
              in
              loop [] files
            in
            List.iter_es
              (List.iter_es
                 (fun ({start_level; end_level; file} as cemented_file) ->
                   Cemented_block_store.iter_cemented_file
                     (fun block ->
                       let hash = Block_repr.hash block in
                       let level = Block_repr.level block in
                       Cemented_block_level_index.replace
                         fresh_level_index
                         hash
                         level ;
                       Cemented_block_hash_index.replace
                         fresh_hash_index
                         level
                         hash ;
                       Lwt.return_unit)
                     cemented_file
                   >>=? fun () ->
                   let file_path = Naming.file_path file in
                   Exporter.copy_cemented_block
                     snapshot_exporter
                     ~file:file_path
                     ~start_level
                     ~end_level
                   >>= fun () ->
                   Lwt.return_unit >>= fun () ->
                   notify () >>= fun () -> return_unit))
              tasks)
        >>=? fun () ->
        Cemented_block_level_index.close fresh_level_index ;
        Cemented_block_hash_index.close fresh_hash_index ;
        Exporter.write_cemented_block_indexes snapshot_exporter >>= fun () ->
        if should_filter_indexes && files <> [] then
          Exporter.filter_cemented_block_indexes
            snapshot_exporter
            ~limit:
              (List.last_opt files |> WithExceptions.Option.get ~loc:__LOC__)
                .end_level ;
        return_unit)

  let write_floating_block fd (block : Block_repr.t) =
    let bytes = Data_encoding.Binary.to_bytes_exn Block_repr.encoding block in
    Lwt_utils_unix.write_bytes ~pos:0 ~len:(Bytes.length bytes) fd bytes

  let export_floating_blocks ~floating_ro_fd ~floating_rw_fd ~export_block =
    let ((limit_hash, limit_level) as export_block_descr) =
      Store.Block.descriptor export_block
    in
    let (stream, bpush) = Lwt_stream.create_bounded 1000 in
    (* Retrieve first floating block *)
    (Block_repr.read_next_block floating_ro_fd >>= function
     | Some (block, _length) -> return block
     | None -> (
         Block_repr.read_next_block floating_rw_fd >>= function
         | Some (block, _length) -> return block
         | None ->
             (* No block to read *)
             fail Empty_floating_store))
    >>=? fun first_block ->
    let first_block_level = Block_repr.level first_block in
    if Compare.Int32.(limit_level < first_block_level) then
      fail
        (Inconsistent_floating_store
           (export_block_descr, (Block_repr.hash first_block, first_block_level)))
    else
      let exception Done in
      let f block =
        (* FIXME: we also write potential branches, it will eventually
           be GCed *)
        if Compare.Int32.(Block_repr.level block >= limit_level) then
          if Block_hash.equal limit_hash (Block_repr.hash block) then raise Done
          else return_unit
        else
          let block = (* Prune everything  *) {block with metadata = None} in
          bpush#push block >>= return
      in
      let reading_thread =
        Lwt.finalize
          (fun () ->
            Lwt.catch
              (fun () ->
                Lwt_unix.lseek floating_ro_fd 0 Unix.SEEK_SET >>= fun _ ->
                Floating_block_store.iter_s_raw_fd f floating_ro_fd
                >>=? fun () ->
                Lwt_unix.lseek floating_rw_fd 0 Unix.SEEK_SET >>= fun _ ->
                Floating_block_store.iter_s_raw_fd f floating_rw_fd
                >>=? fun () -> fail (Missing_target_block export_block_descr))
              (function
                | Done -> return_unit
                | exn ->
                    fail (Cannot_read_floating_store (Printexc.to_string exn))))
          (fun () ->
            bpush#close ;
            Lwt.return_unit)
      in
      return (reading_thread, stream)

  (* Export the protocol table (info regarding the protocol transitions)
     as well as all the stored protocols *)
  let export_protocols snapshot_exporter export_block all_protocol_levels
      protocol_store_dir =
    let export_level = Store.Block.level export_block in
    (* Filter protocols to only export the protocols with an activation
       block below the block target. *)
    let protocol_levels =
      Protocol_levels.filter
        (fun _ {Protocol_levels.block = (_, activation_level); _} ->
          activation_level < export_level)
        all_protocol_levels
    in
    Exporter.write_protocols_table snapshot_exporter ~f:(fun fd ->
        let bytes =
          Data_encoding.Binary.to_bytes_exn
            Protocol_levels.encoding
            protocol_levels
        in
        Lwt_utils_unix.write_bytes ~pos:0 fd bytes)
    >>= fun () ->
    Lwt_unix.opendir (Naming.dir_path protocol_store_dir) >>= fun dir_handle ->
    let proto_to_export =
      List.map
        (fun (_, {Protocol_levels.protocol; _}) -> protocol)
        (Protocol_levels.bindings protocol_levels)
    in
    let nb_proto_to_export = List.length proto_to_export in
    Animation.display_progress
      ~pp_print_step:(fun fmt i ->
        Format.fprintf fmt "Copying protocols: %d/%d" i nb_proto_to_export)
      (fun notify ->
        let rec copy_protocols () =
          Lwt.catch
            (fun () ->
              Lwt_unix.readdir dir_handle >>= function
              | filename
                when filename = Filename.current_dir_name
                     || filename = Filename.parent_dir_name ->
                  copy_protocols ()
              | filename -> (
                  match Protocol_hash.of_b58check_opt filename with
                  | None -> return_unit
                  | Some ph ->
                      let src_protocol_file =
                        Naming.protocol_file protocol_store_dir ph
                      in
                      (if List.mem ~equal:Protocol_hash.equal ph proto_to_export
                      then
                       Exporter.copy_protocol
                         snapshot_exporter
                         ~src:(Naming.file_path src_protocol_file)
                         ~dst_ph:ph
                       >>= fun () -> notify ()
                      else Lwt.return_unit)
                      >>= fun () -> copy_protocols ()))
            (function End_of_file -> return_unit | exn -> fail_with_exn exn)
        in
        Lwt.finalize
          (fun () -> copy_protocols ())
          (fun () -> Lwt_unix.closedir dir_handle))

  (* Ensures that the data needed to export the snapshot from the target
     block is available:
     - the target_block is not the genesis
     - the target_block and its predecessor are known
     - the context of the predecessor of the target_block must be known
     - at least max_op_ttl(target_block) headers must be available
  *)
  let check_export_block_validity chain_store block =
    let (block_hash, block_level) = Store.Block.descriptor block in
    Store.Block.is_known_valid chain_store block_hash >>= fun is_known ->
    fail_unless
      is_known
      (Invalid_export_block {block = Some block_hash; reason = `Unknown})
    >>=? fun () ->
    fail_when
      (Store.Block.is_genesis chain_store block_hash)
      (Invalid_export_block {block = Some block_hash; reason = `Genesis})
    >>=? fun () ->
    Store.Chain.savepoint chain_store >>= fun (_, savepoint_level) ->
    fail_when
      Compare.Int32.(savepoint_level > block_level)
      (Invalid_export_block {block = Some block_hash; reason = `Pruned})
    >>=? fun () ->
    Store.Block.read_block chain_store block_hash >>=? fun block ->
    (Store.Block.read_predecessor_opt chain_store block >>= function
     | None ->
         fail
           (Invalid_export_block
              {block = Some block_hash; reason = `Not_enough_pred})
     | Some pred_block -> return pred_block)
    >>=? fun pred_block ->
    (* Make sure that the predecessor's context is known *)
    Store.Block.context_exists chain_store pred_block
    >>= fun pred_context_exists ->
    (* We also need the predecessor not to be pruned *)
    fail_when
      Compare.Int32.(
        savepoint_level > Int32.pred block_level && not pred_context_exists)
      (Invalid_export_block {block = Some block_hash; reason = `Pruned_pred})
    >>=? fun () ->
    (Store.Block.get_block_metadata_opt chain_store block >>= function
     | None ->
         fail (Invalid_export_block {block = Some block_hash; reason = `Pruned})
     | Some block_metadata -> return block_metadata)
    >>=? fun block_metadata ->
    Store.Chain.caboose chain_store >>= fun (_, caboose_level) ->
    (* We will need the following blocks
       [ (target_block - max_op_ttl(target_block)) ; ... ; target_block ] *)
    let block_max_op_ttl = Store.Block.max_operations_ttl block_metadata in
    Store.Chain.genesis_block chain_store >>= fun genesis_block ->
    let genesis_level = Store.Block.level genesis_block in
    let minimum_level_needed =
      Compare.Int32.(
        max genesis_level Int32.(sub block_level (of_int block_max_op_ttl)))
    in
    fail_when
      Compare.Int32.(minimum_level_needed < caboose_level)
      (Invalid_export_block {block = Some block_hash; reason = `Not_enough_pred})
    >>=? fun () -> return (pred_block, minimum_level_needed)

  (* Retrieves the block to export based on given block "as hint". As
     the checkpoint is provided as a default value, we must ensure that
     it is valid. It may be not the case when the checkpoint was set in
     the future. In this particular case, the last allowed fork level of
     the current head is chosen. *)
  let retrieve_export_block chain_store block =
    (match block with
    | `Genesis ->
        (* Exporting the genesis block does not make sense. *)
        fail
          (Invalid_export_block
             {
               block = Some (Store.Chain.genesis chain_store).Genesis.block;
               reason = `Genesis;
             })
    | `Alias (`Caboose, distance) when distance >= 0 ->
        (* With the caboose, we do not allow to use the ~/- as it is a
           non sense. Additionally, it is not allowed to export the
           caboose block. *)
        Store.Chain.caboose chain_store >>= fun (hash, _) ->
        fail (Invalid_export_block {block = Some hash; reason = `Caboose})
    | _ -> Store.Chain.block_of_identifier chain_store block)
    |> trace (Invalid_export_block {block = None; reason = `Unknown})
    >>=? fun export_block ->
    check_export_block_validity chain_store export_block
    >>=? fun (pred_block, minimum_level_needed) ->
    return (export_block, pred_block, minimum_level_needed)

  (* Returns the list of cemented files to export and an optional list
     of remaining blocks. If the export block is cemented, we need to cut
     the cycle containing the export block accordingly and retrieve the
     extra blocks. *)
  let compute_cemented_table_and_extra_cycle chain_store ~src_cemented_dir
      ~export_block =
    Cemented_block_store.load_table src_cemented_dir >>=? function
    | None -> return ([], None)
    | Some table_arr -> (
        let table_len = Array.length table_arr in
        let table = Array.to_list table_arr in
        (* Check whether the export_block is in the cemented blocks *)
        let export_block_level = Store.Block.level export_block in
        let is_cemented =
          table_len > 0
          && Compare.Int32.(
               export_block_level
               <= table_arr.(table_len - 1).Cemented_block_store.end_level)
        in
        if not is_cemented then
          (* Return either an empty list or the list of all cemented files *)
          return (table, None)
        else
          let is_last_cemented_block =
            Compare.Int32.(
              export_block_level
              = table_arr.(table_len - 1).Cemented_block_store.end_level)
          in
          if is_last_cemented_block then return (table, Some [])
          else
            (* If the export block is cemented, cut the cycle containing the
               export block accordingly and retrieve the extra blocks *)
            let (filtered_table, extra_cycles) =
              List.partition
                (fun {Cemented_block_store.end_level; _} ->
                  Compare.Int32.(export_block_level > end_level))
                table
            in
            assert (extra_cycles <> []) ;
            let extra_cycle =
              List.hd extra_cycles |> WithExceptions.Option.get ~loc:__LOC__
            in
            (* If the export block is the last block in cycle, append the cycle *)
            if Compare.Int32.(export_block_level = extra_cycle.end_level) then
              return (filtered_table @ [extra_cycle], Some [])
            else
              ( Store.Block.read_block_by_level
                  chain_store
                  extra_cycle.start_level
              >>=? fun first_block_in_cycle ->
                (* TODO explain this... *)
                if
                  Compare.Int32.(
                    Store.Block.level first_block_in_cycle > export_block_level)
                then
                  (* When the cycles are short, we may keep more blocks in the
                     floating store than in cemented *)
                  Store.Chain.caboose chain_store >>= fun (_, caboose_level) ->
                  Store.Block.read_block_by_level chain_store caboose_level
                else return first_block_in_cycle )
              >>=? fun first_block ->
              Store.Chain_traversal.path
                chain_store
                ~from_block:first_block
                ~to_block:export_block
              >>= function
              | None -> fail Cannot_retrieve_block_interval
              | Some floating_blocks ->
                  (* Don't forget to add the first block as
                     [Chain_traversal.path] does not include the lower-bound
                     block *)
                  let floating_blocks = first_block :: floating_blocks in
                  return (filtered_table, Some floating_blocks))

  (* Ensures that the history mode requested to export is compatible
     with the current storage. *)
  let check_history_mode chain_store ~rolling =
    match (Store.Chain.history_mode chain_store : History_mode.t) with
    | Archive | Full _ -> return_unit
    | Rolling _ when rolling -> return_unit
    | Rolling _ as stored ->
        fail (Incompatible_history_mode {stored; requested = Full None})

  let export_floating_block_stream snapshot_exporter floating_block_stream =
    let f fd =
      Lwt_stream.is_empty floating_block_stream >>= fun is_empty ->
      if is_empty then Lwt.return_unit
      else
        Animation.display_progress
          ~every:10
          ~pp_print_step:(fun fmt i ->
            Format.fprintf fmt "Copying floating blocks: %d blocks copied" i)
          (fun notify ->
            Lwt_stream.iter_s
              (fun b -> write_floating_block fd b >>= fun () -> notify ())
              floating_block_stream)
    in
    Exporter.write_floating_blocks snapshot_exporter ~f >>= return

  let export_rolling ~store_dir ~context_dir ~block ~rolling genesis =
    let export_rolling_f chain_store =
      check_history_mode chain_store ~rolling >>=? fun () ->
      retrieve_export_block chain_store block
      >>=? fun (export_block, pred_block, lowest_block_level_needed) ->
      (* The number of additional cycles to export is fixed as the
         snasphot content must not rely on the local configuration. *)
      let export_mode = History_mode.Rolling None in
      Event.(
        emit export_info (export_mode, Store.Block.descriptor export_block))
      >>= fun () ->
      (* Blocks *)
      (* Read the store to gather only the necessary blocks *)
      Store.Block.read_block_by_level chain_store lowest_block_level_needed
      >>=? fun minimum_block ->
      (Store.Chain_traversal.path
         chain_store
         ~from_block:minimum_block
         ~to_block:pred_block
       >>= function
       | None -> fail Cannot_retrieve_block_interval
       | Some blocks ->
           (* Don't forget to add the first block as
              [Chain_traversal.path] does not include the
              lower-bound block *)
           return (minimum_block :: blocks))
      >>=? fun floating_blocks ->
      (* Prune all blocks except for the export_block's predecessor *)
      let floating_block_stream =
        Lwt_stream.of_list
          (List.filter_map
             (fun b ->
               Some {(Store.Unsafe.repr_of_block b) with metadata = None})
             floating_blocks)
      in
      (* Protocols *)
      Store.Chain.all_protocol_levels chain_store >>= fun protocol_levels ->
      (* Filter protocols s.t. forall proto. proto.level >=
         caboose.proto_level. *)
      let protocol_levels =
        Protocol_levels.(
          filter
            (fun level {block; _} ->
              level >= Store.Block.proto_level minimum_block
              || Store.Block.is_genesis chain_store (fst block))
            protocol_levels)
      in
      return
        ( export_mode,
          export_block,
          pred_block,
          protocol_levels,
          (return_unit, floating_block_stream) )
    in
    Store.Unsafe.open_for_snapshot_export
      ~store_dir
      ~context_dir
      genesis
      ~locked_f:export_rolling_f
    >>=? fun ( export_mode,
               export_block,
               pred_block,
               protocol_levels,
               (return_unit, floating_block_stream) ) ->
    return
      ( export_mode,
        export_block,
        pred_block,
        protocol_levels,
        (return_unit, floating_block_stream) )

  let export_full snapshot_exporter ~store_dir ~context_dir ~block ~rolling
      genesis =
    let export_full_f chain_store =
      check_history_mode chain_store ~rolling >>=? fun () ->
      retrieve_export_block chain_store block
      >>=? fun (export_block, pred_block, _lowest_block_level_needed) ->
      (* The number of additional cycles to export is fixed as the
         snasphot content must not rely on the local configuration. *)
      let export_mode = History_mode.Full None in
      Event.(
        emit export_info (export_mode, Store.Block.descriptor export_block))
      >>= fun () ->
      let store_dir = Naming.store_dir ~dir_path:store_dir in
      let chain_id = Store.Chain.chain_id chain_store in
      let chain_dir = Naming.chain_dir store_dir chain_id in
      (* Open the floating FDs (in readonly) while the lock is present *)
      let ro_floating_blocks =
        Naming.floating_blocks_file (Naming.floating_blocks_dir chain_dir RO)
      in
      let rw_floating_blocks =
        Naming.floating_blocks_file (Naming.floating_blocks_dir chain_dir RW)
      in
      Lwt_unix.openfile
        (Naming.file_path ro_floating_blocks)
        [Unix.O_RDONLY]
        0o444
      >>= fun ro_fd ->
      Lwt_unix.openfile
        (Naming.file_path rw_floating_blocks)
        [Unix.O_RDONLY]
        0o644
      >>= fun rw_fd ->
      Lwt.catch
        (fun () ->
          let src_cemented_dir = Naming.cemented_blocks_dir chain_dir in
          (* Compute the necessary cemented table *)
          compute_cemented_table_and_extra_cycle
            chain_store
            ~src_cemented_dir
            ~export_block
          >>=? fun (cemented_table, extra_floating_blocks) ->
          Store.Chain.all_protocol_levels chain_store >>= fun protocol_levels ->
          let block_store = Store.Unsafe.get_block_store chain_store in
          let cemented_store = Block_store.cemented_block_store block_store in
          let should_filter_indexes =
            match
              Cemented_block_store.get_highest_cemented_level cemented_store
            with
            | None -> false
            | Some max_cemented_level ->
                Compare.Int32.(
                  max_cemented_level > Store.Block.level export_block)
          in
          return
            ( export_mode,
              export_block,
              pred_block,
              protocol_levels,
              cemented_table,
              (ro_fd, rw_fd),
              extra_floating_blocks,
              should_filter_indexes ))
        (fun exn ->
          Lwt_utils_unix.safe_close ro_fd >>= fun _ ->
          Lwt_utils_unix.safe_close rw_fd >>= fun _ -> fail_with_exn exn)
    in
    Store.Unsafe.open_for_snapshot_export
      ~store_dir
      ~context_dir
      genesis
      ~locked_f:export_full_f
    >>=? fun ( export_mode,
               export_block,
               pred_block,
               protocol_levels,
               cemented_table,
               (floating_ro_fd, floating_rw_fd),
               extra_floating_blocks,
               should_filter_indexes ) ->
    copy_cemented_blocks snapshot_exporter ~should_filter_indexes cemented_table
    >>=? fun () ->
    let finalizer () =
      Lwt_utils_unix.safe_close floating_ro_fd >>= fun _ ->
      Lwt_utils_unix.safe_close floating_rw_fd >>= fun _ -> Lwt.return_unit
    in
    (match extra_floating_blocks with
    | Some floating_blocks ->
        finalizer () >>= fun () ->
        return
          ( return_unit,
            Lwt_stream.of_list
              (List.map Store.Unsafe.repr_of_block floating_blocks) )
    | None ->
        (* The export block is in the floating stores, copy all the
           floating stores until the block is reached *)
        export_floating_blocks ~floating_ro_fd ~floating_rw_fd ~export_block
        >>=? fun (reading_thread, floating_block_stream) ->
        let reading_thread =
          Lwt.finalize (fun () -> reading_thread) finalizer
        in
        return (reading_thread, floating_block_stream))
    >>=? fun (reading_thread, floating_block_stream) ->
    return
      ( export_mode,
        export_block,
        pred_block,
        protocol_levels,
        (reading_thread, floating_block_stream) )

  let ensure_valid_export_chain_dir store_path chain_id =
    let store_dir = Naming.store_dir ~dir_path:store_path in
    let chain_dir = Naming.chain_dir store_dir chain_id in
    Lwt_unix.file_exists (Naming.dir_path chain_dir) >>= function
    | true -> return_unit
    | false ->
        fail (Invalid_chain_store_export (chain_id, Naming.dir_path store_dir))

  let export ?snapshot_path ?(rolling = false) ~block ~store_dir ~context_dir
      ~chain_name genesis =
    let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
    ensure_valid_export_chain_dir store_dir chain_id >>=? fun () ->
    init snapshot_path >>=? fun snapshot_exporter ->
    (* Register a clean up callback to prevent export cancelation not
       to be correctly cleaned. *)
    let cleaner_id =
      Lwt_exit.register_clean_up_callback ~loc:__LOC__ (fun _ ->
          Exporter.cleaner snapshot_exporter >>= fun () -> Lwt.return_unit)
    in
    protect
      ~on_error:(fun errors ->
        Exporter.cleaner snapshot_exporter >>= fun () ->
        Lwt.return (Error errors))
      (fun () ->
        (if rolling then
         export_rolling ~store_dir ~context_dir ~block ~rolling genesis
        else
          export_full
            snapshot_exporter
            ~store_dir
            ~context_dir
            ~block
            ~rolling
            genesis)
        >>=? fun ( export_mode,
                   export_block,
                   pred_block,
                   protocol_levels,
                   (reading_thread, floating_block_stream) ) ->
        (* TODO: when the context's GC is implemented, make sure a context
           pruning cannot occur while the dump context is being run. For
           now, it is performed outside the lock to allow the node from
           getting stuck while waiting a merge. *)
        Context.init ~readonly:true context_dir >>= fun context_index ->
        Context.checkout_exn
          context_index
          (Store.Block.context_hash export_block)
        >>= fun context ->
        (* Retrieve predecessor block metadata hash and operations
           metadata hash from the context of the exported block *)
        Context.find_predecessor_block_metadata_hash context
        >>= fun predecessor_block_metadata_hash ->
        Context.find_predecessor_ops_metadata_hash context
        >>= fun predecessor_ops_metadata_hash ->
        Exporter.write_block_data
          snapshot_exporter
          ~predecessor_header:(Store.Block.header pred_block)
          ~predecessor_block_metadata_hash
          ~predecessor_ops_metadata_hash
          ~export_block
        >>= fun () ->
        Exporter.dump_context
          snapshot_exporter
          context_index
          (Store.Block.context_hash pred_block)
        >>=? fun written_context_elements ->
        export_floating_block_stream snapshot_exporter floating_block_stream
        >>=? fun () ->
        reading_thread >>=? fun () ->
        export_protocols
          snapshot_exporter
          export_block
          protocol_levels
          (Naming.protocol_store_dir (Naming.store_dir ~dir_path:store_dir))
        >>=? fun () ->
        let metadata =
          {
            chain_name;
            history_mode = export_mode;
            block_hash = Store.Block.hash export_block;
            level = Store.Block.level export_block;
            timestamp = Store.Block.timestamp export_block;
            context_elements = written_context_elements;
          }
        in
        return metadata)
    >>=? fun metadata ->
    Exporter.finalize snapshot_exporter metadata
    >>=? fun exported_snapshot_filename ->
    Event.(emit export_success exported_snapshot_filename) >>= fun () ->
    Lwt_exit.unregister_clean_up_callback cleaner_id ;
    return_unit
end

module type LOADER = sig
  type t

  val load : string -> t Lwt.t

  val load_snapshot_header : t -> header tzresult Lwt.t

  val close : t -> unit Lwt.t
end

module Raw_loader : LOADER = struct
  type t = {snapshot_dir : [`Snapshot_dir] Naming.directory}

  let load snapshot_path =
    let snapshot_dir = Naming.snapshot_dir ~snapshot_path () in
    Lwt.return {snapshot_dir}

  let load_snapshot_version t =
    let snapshot_file =
      Naming.(snapshot_version_file t.snapshot_dir |> file_path)
    in
    let read_json json =
      Data_encoding.Json.destruct Version.version_encoding json
    in
    Lwt_utils_unix.Json.read_file snapshot_file >>=? fun json ->
    return (read_json json)

  let load_snapshot_metadata t =
    let metadata_file =
      Naming.(snapshot_metadata_file t.snapshot_dir |> file_path)
    in
    let read_json json = Data_encoding.Json.destruct metadata_encoding json in
    Lwt_utils_unix.Json.read_file metadata_file >>=? fun json ->
    return (read_json json)

  let load_snapshot_header t =
    load_snapshot_version t >>=? fun version ->
    load_snapshot_metadata t >>=? fun metadata -> return (version, metadata)

  let close _ = Lwt.return_unit
end

module Tar_loader : LOADER = struct
  type t = {
    tar : Onthefly.i;
    snapshot_file : [`Snapshot_file] Naming.file;
    snapshot_tar : [`Tar_archive] Naming.directory;
  }

  let load snapshot_path =
    let snapshot_dir =
      Naming.snapshot_dir ~snapshot_path:(Filename.dirname snapshot_path) ()
    in
    let snapshot_tar = Naming.snapshot_tar_root in
    let snapshot_file =
      Naming.snapshot_file
        ~snapshot_filename:(Filename.basename snapshot_path)
        snapshot_dir
    in
    Onthefly.open_in ~file:(Naming.file_path snapshot_file) >>= fun tar ->
    Lwt.return {tar; snapshot_file; snapshot_tar}

  let load_snapshot_version t =
    let filename = Naming.(snapshot_version_file t.snapshot_tar |> file_path) in
    (Onthefly.find_file t.tar ~filename >>= function
     | Some file -> (
         Onthefly.load_file t.tar file >>= fun str ->
         match Data_encoding.Json.from_string str with
         | Ok json ->
             Lwt.return_some
               (Data_encoding.Json.destruct Version.version_encoding json)
         | Error _ -> Lwt.return_none)
     | None -> Lwt.return_none)
    >>= function
    | Some version -> return version
    | None -> fail (Cannot_read {kind = `Version; path = filename})

  let load_snapshot_metadata t =
    let filename =
      Naming.(snapshot_metadata_file t.snapshot_tar |> file_path)
    in
    (Onthefly.find_file t.tar ~filename >>= function
     | Some file -> (
         Onthefly.load_file t.tar file >>= fun str ->
         match Data_encoding.Json.from_string str with
         | Ok json ->
             Lwt.return_some
               (Data_encoding.Json.destruct metadata_encoding json)
         | Error _ -> Lwt.return_none)
     | None -> Lwt.return_none)
    >>= function
    | Some metadata -> return metadata
    | None -> fail (Cannot_read {kind = `Metadata; path = filename})

  let load_snapshot_header t =
    load_snapshot_version t >>=? fun version ->
    load_snapshot_metadata t >>=? fun metadata -> return (version, metadata)

  let close t = Onthefly.close_in t.tar
end

module type Snapshot_loader = sig
  type t

  val load_snapshot_header : snapshot_path:string -> header tzresult Lwt.t
end

module Make_snapshot_loader (Loader : LOADER) : Snapshot_loader = struct
  type t = Loader.t

  let load = Loader.load

  let close = Loader.close

  let load_snapshot_header ~snapshot_path =
    load snapshot_path >>= fun loader ->
    trace (Wrong_snapshot_file {filename = snapshot_path})
    @@ protect
         (fun () -> Loader.load_snapshot_header loader)
         ~on_error:(fun err -> close loader >>= fun () -> Lwt.return_error err)
end

module type IMPORTER = sig
  type t

  val init :
    snapshot_path:string ->
    dst_store_dir:[`Store_dir] Naming.directory ->
    Chain_id.t ->
    t Lwt.t

  val load_snapshot_header : t -> header tzresult Lwt.t

  val load_block_data : t -> block_data tzresult Lwt.t

  val restore_context :
    t ->
    Context.index ->
    expected_context_hash:Context_hash.t ->
    nb_context_elements:int ->
    unit tzresult Lwt.t

  val load_protocol_table :
    t -> Protocol_levels.activation_block Protocol_levels.t tzresult Lwt.t

  val load_and_validate_protocol_filenames :
    t -> Protocol_hash.t list tzresult Lwt.t

  val copy_and_validate_protocol :
    t -> protocol_hash:Protocol_hash.t -> (unit, error trace) result Lwt.t

  val restore_cemented_indexes : t -> unit Lwt.t

  val load_cemented_files : t -> string list tzresult Lwt.t

  val restore_cemented_cycle : t -> file:string -> unit tzresult Lwt.t

  val restore_floating_blocks :
    t ->
    Block_hash.t ->
    (unit tzresult Lwt.t * Block_repr.block Lwt_stream.t) tzresult Lwt.t

  val close : t -> unit Lwt.t
end

module Raw_importer : IMPORTER = struct
  type t = {
    snapshot_dir : [`Snapshot_dir] Naming.directory;
    snapshot_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    snapshot_protocol_dir : [`Protocol_dir] Naming.directory;
    dst_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    dst_protocol_dir : [`Protocol_dir] Naming.directory;
    dst_store_dir : [`Store_dir] Naming.directory;
    dst_chain_dir : [`Chain_dir] Naming.directory;
  }

  let init ~snapshot_path ~dst_store_dir chain_id =
    let snapshot_dir = Naming.snapshot_dir ~snapshot_path () in
    let snapshot_cemented_dir = Naming.cemented_blocks_dir snapshot_dir in
    let snapshot_protocol_dir = Naming.protocol_store_dir snapshot_dir in
    let dst_chain_dir = Naming.chain_dir dst_store_dir chain_id in
    let dst_cemented_dir = Naming.cemented_blocks_dir dst_chain_dir in
    let dst_protocol_dir = Naming.protocol_store_dir dst_store_dir in
    Lwt.return
      {
        snapshot_dir;
        snapshot_cemented_dir;
        snapshot_protocol_dir;
        dst_cemented_dir;
        dst_protocol_dir;
        dst_store_dir;
        dst_chain_dir;
      }

  let load_snapshot_header t =
    let (module Loader) =
      (module Make_snapshot_loader (Raw_loader) : Snapshot_loader)
    in
    Loader.load_snapshot_header
      ~snapshot_path:Naming.(t.snapshot_dir |> dir_path)

  let load_block_data t =
    let file = Naming.(snapshot_block_data_file t.snapshot_dir |> file_path) in
    Lwt_utils_unix.read_file file >>= fun block_data ->
    match Data_encoding.Binary.of_string_opt block_data_encoding block_data with
    | Some block_data -> return block_data
    | None -> fail (Cannot_read {kind = `Block_data; path = file})

  let restore_context t context_index ~expected_context_hash
      ~nb_context_elements =
    let context_file_path =
      Naming.(snapshot_context_file t.snapshot_dir |> file_path)
    in
    Lwt.catch
      (fun () ->
        Lwt_unix.openfile context_file_path Lwt_unix.[O_RDONLY] 0o444 >>= return)
      (function
        | Unix.Unix_error (e, _, _) ->
            fail (Context.Cannot_open_file (Unix.error_message e))
        | exc ->
            let msg =
              Printf.sprintf "unknown error: %s" (Printexc.to_string exc)
            in
            fail (Context.Cannot_open_file msg))
    >>=? fun fd ->
    Lwt.finalize
      (fun () ->
        Context.restore_context
          context_index
          ~expected_context_hash
          ~fd
          ~nb_context_elements
        >>=? fun () ->
        (* FIXME: Is this test really usefull? *)
        Lwt_unix.lseek fd 0 Lwt_unix.SEEK_CUR >>= fun current ->
        Lwt_unix.fstat fd >>= fun stats ->
        let total = stats.Lwt_unix.st_size in
        if current = total then return_unit
        else fail (Context.Suspicious_file (total - current)))
      (fun () -> Lwt_unix.close fd)

  let load_protocol_table t =
    let protocol_tbl_filename =
      Naming.(snapshot_protocol_levels_file t.snapshot_dir |> encoded_file_path)
    in
    Lwt_utils_unix.read_file protocol_tbl_filename >>= fun table_bytes ->
    match
      Data_encoding.Binary.of_string_opt Protocol_levels.encoding table_bytes
    with
    | Some table -> return table
    | None ->
        fail
          (Cannot_read {kind = `Protocol_table; path = protocol_tbl_filename})

  let load_and_validate_protocol_filenames t =
    let protocol_levels_file =
      Naming.snapshot_protocol_levels_file t.snapshot_dir
    in
    let stream =
      Lwt_unix.files_of_directory (Naming.dir_path t.snapshot_protocol_dir)
    in
    Lwt_stream.to_list stream >>= fun files ->
    let is_not_a_protocol =
      let protocol_levels_path =
        Naming.encoded_file_path protocol_levels_file
      in
      fun file ->
        file = Filename.current_dir_name
        || file = Filename.parent_dir_name
        || file = Filename.basename protocol_levels_path
    in
    let protocol_files =
      List.filter_map
        (function
          | file when is_not_a_protocol file -> None | file -> Some file)
        files
    in
    List.map_es
      (fun file ->
        match Protocol_hash.of_b58check_opt file with
        | Some ph -> return ph
        | None -> fail (Invalid_protocol_file file))
      protocol_files

  let copy_and_validate_protocol t ~protocol_hash =
    let src =
      Filename.concat
        (Naming.dir_path t.snapshot_protocol_dir)
        (Protocol_hash.to_b58check protocol_hash)
    in
    let dst =
      Filename.concat
        (Naming.dir_path t.dst_protocol_dir)
        (Protocol_hash.to_b58check protocol_hash)
    in
    Lwt_utils_unix.copy_file ~src ~dst >>= fun () ->
    Lwt_utils_unix.read_file dst >>= fun protocol_sources ->
    match Protocol.of_string protocol_sources with
    | None -> fail (Cannot_decode_protocol protocol_hash)
    | Some p ->
        let hash = Protocol.hash p in
        fail_unless
          (Protocol_hash.equal protocol_hash hash)
          (Inconsistent_protocol_hash {expected = protocol_hash; got = hash})

  let restore_cemented_indexes t =
    let src_level_dir =
      Naming.(
        cemented_blocks_level_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    let src_hash_dir =
      Naming.(
        cemented_blocks_hash_index_dir t.snapshot_cemented_dir |> dir_path)
    in
    (if Sys.file_exists src_level_dir then
     Lwt_utils_unix.copy_dir
       src_level_dir
       Naming.(cemented_blocks_level_index_dir t.dst_cemented_dir |> dir_path)
    else Lwt.return_unit)
    >>= fun () ->
    if Sys.file_exists src_hash_dir then
      Lwt_utils_unix.copy_dir
        src_hash_dir
        Naming.(cemented_blocks_hash_index_dir t.dst_cemented_dir |> dir_path)
    else Lwt.return_unit

  let load_cemented_files t =
    let stream =
      Lwt_unix.files_of_directory (Naming.dir_path t.snapshot_cemented_dir)
    in
    Lwt_stream.to_list stream >>= fun files ->
    let is_not_cycle_file file =
      file = Filename.current_dir_name
      || file = Filename.parent_dir_name
      || file
         = Filename.basename
             (Naming.dir_path
                (Naming.cemented_blocks_hash_index_dir t.snapshot_cemented_dir))
      || file
         = Filename.basename
             (Naming.dir_path
                (Naming.cemented_blocks_level_index_dir t.snapshot_cemented_dir))
    in
    List.filter_es
      (function
        | file when is_not_cycle_file file -> return_false
        | file ->
            let is_valid =
              match String.split_on_char '_' file with
              | [s; e] ->
                  Int32.of_string_opt s <> None || Int32.of_string_opt e <> None
              | _ -> false
            in
            if not is_valid then fail (Invalid_cemented_file file)
            else return_true)
      files

  let restore_cemented_cycle t ~file =
    let src = Filename.concat (Naming.dir_path t.snapshot_cemented_dir) file in
    let dst = Filename.concat (Naming.dir_path t.dst_cemented_dir) file in
    Lwt_utils_unix.copy_file ~src ~dst >>= return

  let restore_floating_blocks t genesis_hash =
    let floating_blocks_file =
      Naming.(snapshot_floating_blocks_file t.snapshot_dir |> file_path)
    in
    if not (Sys.file_exists floating_blocks_file) then
      return (return_unit, Lwt_stream.of_list [])
    else
      Lwt_unix.openfile floating_blocks_file Unix.[O_RDONLY] 0o444 >>= fun fd ->
      let (stream, bounded_push) = Lwt_stream.create_bounded 1000 in
      let rec loop ?pred_block nb_bytes_left =
        if nb_bytes_left < 0 then fail Corrupted_floating_store
        else if nb_bytes_left = 0 then return_unit
        else
          Block_repr.read_next_block_exn fd >>= fun (block, len_read) ->
          Block_repr.check_block_consistency ~genesis_hash ?pred_block block
          >>=? fun () ->
          bounded_push#push block >>= fun () -> loop (nb_bytes_left - len_read)
      in
      let reading_thread =
        Lwt.finalize
          (fun () ->
            Lwt_unix.lseek fd 0 Unix.SEEK_END >>= fun eof_offset ->
            Lwt_unix.lseek fd 0 Unix.SEEK_SET >>= fun _ -> loop eof_offset)
          (fun () ->
            bounded_push#close ;
            Lwt_utils_unix.safe_close fd >>= fun _ -> Lwt.return_unit)
      in
      return (reading_thread, stream)

  let close _ = Lwt.return_unit
end

module Tar_importer : IMPORTER = struct
  type t = {
    snapshot_file : [`Snapshot_file] Naming.file;
    snapshot_tar : [`Tar_archive] Naming.directory;
    snapshot_cemented_blocks_dir : [`Cemented_blocks_dir] Naming.directory;
    dst_store_dir : [`Store_dir] Naming.directory;
    dst_chain_dir : [`Chain_dir] Naming.directory;
    dst_cemented_dir : [`Cemented_blocks_dir] Naming.directory;
    dst_protocol_dir : [`Protocol_dir] Naming.directory;
    tar : Onthefly.i;
    (* Store the files of the archive to avoid re-reading them *)
    files : Onthefly.file list;
  }

  let init ~snapshot_path ~dst_store_dir chain_id =
    let snapshot_dir =
      Naming.snapshot_dir ~snapshot_path:(Filename.dirname snapshot_path) ()
    in
    let snapshot_tar = Naming.snapshot_tar_root in
    let snapshot_file =
      Naming.snapshot_file
        ~snapshot_filename:(Filename.basename snapshot_path)
        snapshot_dir
    in
    let snapshot_cemented_blocks_dir =
      Naming.cemented_blocks_dir snapshot_tar
    in
    let dst_chain_dir = Naming.chain_dir dst_store_dir chain_id in
    let dst_cemented_dir = Naming.cemented_blocks_dir dst_chain_dir in
    let dst_protocol_dir = Naming.protocol_store_dir dst_store_dir in
    Onthefly.open_in ~file:(Naming.file_path snapshot_file) >>= fun tar ->
    Onthefly.list_files tar >>= fun files ->
    Lwt.return
      {
        snapshot_file;
        snapshot_tar;
        snapshot_cemented_blocks_dir;
        dst_store_dir;
        dst_chain_dir;
        dst_cemented_dir;
        dst_protocol_dir;
        tar;
        files;
      }

  let load_snapshot_header t =
    let (module Loader) =
      (module Make_snapshot_loader (Tar_loader) : Snapshot_loader)
    in
    Loader.load_snapshot_header
      ~snapshot_path:Naming.(t.snapshot_file |> file_path)

  let load_block_data t =
    let filename =
      Naming.(snapshot_block_data_file t.snapshot_tar |> file_path)
    in
    (Onthefly.load_from_filename t.tar ~filename >>= function
     | Some str -> (
         match Data_encoding.Binary.of_string_opt block_data_encoding str with
         | Some metadata -> return_some metadata
         | None -> return_none)
     | None -> return_none)
    >>=? function
    | Some metadata -> return metadata
    | None -> fail (Cannot_read {kind = `Block_data; path = filename})

  let restore_context t context_index ~expected_context_hash
      ~nb_context_elements =
    let filename = Naming.(snapshot_context_file t.snapshot_tar |> file_path) in
    (Onthefly.get_file t.tar ~filename >>= function
     | Some header -> return header
     | None -> fail (Cannot_read {kind = `Context; path = filename}))
    >>=? fun header ->
    Onthefly.read_raw t.tar header >>= fun fd ->
    Context.restore_context
      context_index
      ~expected_context_hash
      ~nb_context_elements
      ~fd

  let load_protocol_table t =
    let protocol_tbl_filename =
      Naming.(snapshot_protocol_levels_file t.snapshot_tar |> encoded_file_path)
    in
    Onthefly.load_from_filename t.tar ~filename:protocol_tbl_filename
    >>= function
    | Some str ->
        let (_ofs, res) =
          Data_encoding.Binary.read_exn
            Protocol_levels.encoding
            str
            0
            (String.length str)
        in
        return res
    | None ->
        fail
          (Cannot_read {kind = `Protocol_table; path = protocol_tbl_filename})

  let load_and_validate_protocol_filenames t =
    let protocol_tbl_filename =
      Naming.(snapshot_protocol_levels_file t.snapshot_tar |> encoded_file_path)
    in
    Onthefly.find_files_with_common_path
      t.tar
      ~pattern:Naming.(protocol_store_dir t.snapshot_tar |> dir_path)
    >>= fun protocol_dir_files ->
    let protocol_files =
      List.fold_left
        (fun acc file ->
          let filename = Filename.basename (Onthefly.get_filename file) in
          if filename <> protocol_tbl_filename then filename :: acc else acc)
        []
        protocol_dir_files
    in
    List.map_es
      (fun file ->
        match Protocol_hash.of_b58check_opt file with
        | Some ph -> return ph
        | None -> fail (Invalid_protocol_file file))
      protocol_files

  let copy_and_validate_protocol t ~protocol_hash =
    let src =
      Filename.(
        concat
          Naming.(protocol_store_dir t.snapshot_tar |> dir_path)
          (Protocol_hash.to_b58check protocol_hash))
    in
    (Onthefly.get_file t.tar ~filename:src >>= function
     | Some file -> return file
     | None -> fail (Cannot_read {kind = `Protocol; path = src}))
    >>=? fun file ->
    let dst =
      Filename.(
        concat
          (Naming.dir_path t.dst_protocol_dir)
          (Protocol_hash.to_b58check protocol_hash))
    in
    Onthefly.copy_to_file t.tar file ~dst >>= fun () ->
    Lwt_utils_unix.read_file dst >>= fun protocol_sources ->
    match Protocol.of_string protocol_sources with
    | None -> fail (Cannot_decode_protocol protocol_hash)
    | Some p ->
        let hash = Protocol.hash p in
        fail_unless
          (Protocol_hash.equal protocol_hash hash)
          (Inconsistent_protocol_hash {expected = protocol_hash; got = hash})

  let restore_cemented_indexes t =
    Onthefly.find_files_with_common_path
      t.tar
      ~pattern:
        Naming.(
          cemented_blocks_level_index_dir t.snapshot_cemented_blocks_dir
          |> dir_path)
    >>= fun cbl ->
    Onthefly.find_files_with_common_path
      t.tar
      ~pattern:
        Naming.(
          cemented_blocks_hash_index_dir t.snapshot_cemented_blocks_dir
          |> dir_path)
    >>= fun cbh ->
    let cemented_indexes_paths = cbl @ cbh in
    if cemented_indexes_paths <> [] then
      let level_index_dir =
        Naming.(cemented_blocks_level_index_dir t.dst_cemented_dir |> dir_path)
      in
      let hash_index_dir =
        Naming.(cemented_blocks_hash_index_dir t.dst_cemented_dir |> dir_path)
      in
      Lwt_unix.mkdir level_index_dir 0o755 >>= fun () ->
      Lwt_unix.mkdir hash_index_dir 0o755 >>= fun () ->
      Lwt_unix.mkdir Filename.(concat level_index_dir "index") 0o755
      >>= fun () ->
      Lwt_unix.mkdir Filename.(concat hash_index_dir "index") 0o755
      >>= fun () ->
      Lwt_list.iter_s
        (fun file ->
          Onthefly.copy_to_file
            t.tar
            file
            ~dst:
              (Filename.concat
                 (Naming.dir_path t.dst_chain_dir)
                 (Onthefly.get_filename file)))
        cemented_indexes_paths
    else Lwt.return_unit

  let load_cemented_files t =
    Onthefly.find_files_with_common_path t.tar ~pattern:"\\d+_\\d+"
    >>= fun cemented_files ->
    return
      (List.map
         (fun file -> Filename.basename (Onthefly.get_filename file))
         cemented_files)

  let restore_cemented_cycle t ~file =
    let filename =
      Filename.(
        concat Naming.(cemented_blocks_dir t.snapshot_tar |> dir_path) file)
    in
    (Onthefly.get_file t.tar ~filename >>= function
     | Some file -> return file
     | None -> fail (Cannot_read {kind = `Cemented_cycle; path = filename}))
    >>=? fun tar_file ->
    Onthefly.copy_to_file
      t.tar
      tar_file
      ~dst:
        (Filename.concat
           (Naming.dir_path t.dst_cemented_dir)
           (Filename.basename file))
    >>= return

  let restore_floating_blocks t genesis_hash =
    Onthefly.get_file
      t.tar
      ~filename:
        Naming.(snapshot_floating_blocks_file t.snapshot_tar |> file_path)
    >>= function
    | Some floating_blocks_file ->
        let file_size = Onthefly.get_file_size floating_blocks_file in
        let floating_blocks_file_fd = Onthefly.get_raw_input_fd t.tar in
        let (stream, bounded_push) = Lwt_stream.create_bounded 1000 in
        let rec loop ?pred_block nb_bytes_left =
          if nb_bytes_left < 0L then fail Corrupted_floating_store
          else if nb_bytes_left = 0L then return_unit
          else
            Block_repr.read_next_block_exn floating_blocks_file_fd
            >>= fun (block, len_read) ->
            Block_repr.check_block_consistency ~genesis_hash ?pred_block block
            >>=? fun () ->
            bounded_push#push block >>= fun () ->
            loop Int64.(sub nb_bytes_left (of_int len_read))
        in
        let reading_thread =
          Lwt.finalize
            (fun () ->
              let raw_data_ofs =
                Onthefly.get_raw_file_ofs floating_blocks_file
              in
              Lwt_unix.LargeFile.lseek
                floating_blocks_file_fd
                raw_data_ofs
                Unix.SEEK_SET
              >>= fun _ -> loop file_size)
            (fun () ->
              bounded_push#close ;
              Lwt.return_unit)
        in
        return (reading_thread, stream)
    | None -> return (return_unit, Lwt_stream.of_list [])

  let close t = Onthefly.close_in t.tar
end

module type Snapshot_importer = sig
  type t

  val read_snapshot_header : t -> header tzresult Lwt.t

  val import :
    snapshot_path:string ->
    ?patch_context:(Context.t -> Context.t tzresult Lwt.t) ->
    ?block:Block_hash.t ->
    ?check_consistency:bool ->
    dst_store_dir:[`Store_dir] Naming.directory ->
    dst_context_dir:string ->
    chain_name:Distributed_db_version.Name.t ->
    user_activated_upgrades:User_activated.upgrades ->
    user_activated_protocol_overrides:User_activated.protocol_overrides ->
    Genesis.t ->
    (unit, error trace) result Lwt.t
end

module Make_snapshot_importer (Importer : IMPORTER) : Snapshot_importer = struct
  type t = Importer.t

  let init = Importer.init

  let close = Importer.close

  let read_snapshot_header = Importer.load_snapshot_header

  let restore_cemented_blocks ?(check_consistency = true) ~dst_chain_dir
      ~genesis_hash snapshot_importer =
    Importer.restore_cemented_indexes snapshot_importer >>= fun () ->
    Importer.load_cemented_files snapshot_importer >>=? fun cemented_files ->
    let nb_cemented_files = List.length cemented_files in
    (if nb_cemented_files > 0 then
     Animation.display_progress
       ~pp_print_step:(fun fmt i ->
         Format.fprintf
           fmt
           "Copying cycles: %d/%d (%d%%)"
           i
           nb_cemented_files
           (100 * i / nb_cemented_files))
       (fun notify ->
         List.iter_es
           (fun file ->
             Importer.restore_cemented_cycle snapshot_importer ~file
             >>=? fun () -> notify () >>= return)
           cemented_files)
    else return_unit)
    >>=? fun () ->
    Cemented_block_store.init
      ~log_size:cemented_import_log_size
      ~readonly:false
      dst_chain_dir
    >>=? fun cemented_store ->
    (if check_consistency && nb_cemented_files > 0 then
     match Cemented_block_store.cemented_blocks_files cemented_store with
     | None -> failwith "unexpected empty set of cemented files"
     | Some stored_cemented_files ->
         List.iter_es
           (fun cemented_file ->
             if
               not
                 (Array.exists
                    (fun {Cemented_block_store.file; _} ->
                      Compare.String.equal
                        (Naming.file_path file |> Filename.basename)
                        cemented_file)
                    stored_cemented_files)
             then fail (Missing_cemented_file cemented_file)
             else return_unit)
           (List.sort compare cemented_files)
         >>=? fun () ->
         Animation.display_progress
           ~pp_print_step:(fun fmt i ->
             Format.fprintf
               fmt
               "Restoring cycles consistency: %d/%d (%d%%)"
               i
               nb_cemented_files
               (100 * i / nb_cemented_files))
           (fun notify ->
             Cemented_block_store.check_indexes_consistency
               ~post_step:notify
               ~genesis_hash
               cemented_store)
    else return_unit)
    >>=? fun () ->
    Cemented_block_store.close cemented_store ;
    return_unit

  let read_floating_blocks snapshot_importer ~genesis_hash =
    Importer.restore_floating_blocks snapshot_importer genesis_hash

  let restore_protocols snapshot_importer =
    (* Import protocol table *)
    Importer.load_protocol_table snapshot_importer >>=? fun protocol_levels ->
    (* Retrieve protocol files *)
    Importer.load_and_validate_protocol_filenames snapshot_importer
    >>=? fun protocols ->
    Animation.display_progress
      ~pp_print_step:(fun fmt i ->
        Format.fprintf fmt "Copying protocols: %d/%d" i (List.length protocols))
      (fun notify ->
        let validate_and_copy protocol_hash =
          Importer.copy_and_validate_protocol snapshot_importer ~protocol_hash
          >>=? fun () -> notify () >>= return
        in
        List.iter_es validate_and_copy protocols)
    >>=? fun () -> return protocol_levels

  let import_log_notice ?snapshot_header filename block =
    let header =
      Option.map
        (fun header -> Format.asprintf "%a" pp_snapshot_header header)
        snapshot_header
    in
    Event.(emit import_info (filename, header)) >>= fun () ->
    (match block with
    | None -> Event.(emit import_unspecified_hash ())
    | Some _ -> Lwt.return_unit)
    >>= fun () -> Event.(emit import_loading ())

  let check_context_hash_consistency validation_store block_header =
    fail_unless
      (Context_hash.equal
         validation_store.Tezos_validation.Block_validation.context_hash
         block_header.Block_header.shell.context)
      (Inconsistent_context_hash
         {
           expected = block_header.Block_header.shell.context;
           got = validation_store.Tezos_validation.Block_validation.context_hash;
         })

  let restore_and_apply_context snapshot_importer ?user_expected_block
      ~context_index ~user_activated_upgrades ~user_activated_protocol_overrides
      snapshot_metadata genesis chain_id =
    (* Start by committing genesis *)
    Context.commit_genesis
      context_index
      ~chain_id
      ~time:genesis.Genesis.time
      ~protocol:genesis.protocol
    >>=? fun genesis_ctxt_hash ->
    Importer.load_block_data snapshot_importer
    >>=? fun ({
                block_header;
                operations;
                predecessor_header;
                predecessor_block_metadata_hash;
                predecessor_ops_metadata_hash;
              } as block_data) ->
    (* Checks that the block hash imported from the snapshot is the one
       expected by the user's --block command line option *)
    let block_header_hash = Block_header.hash block_header in
    (match user_expected_block with
    | Some bh ->
        fail_unless
          (Block_hash.equal bh block_header_hash)
          (Inconsistent_imported_block (block_header_hash, bh))
    | None -> return_unit)
    >>=? fun () ->
    (* Checks that the block hash read from the snapshot metadata is the
       expected one *)
    fail_unless
      (Block_hash.equal snapshot_metadata.block_hash block_header_hash)
      (Inconsistent_imported_block
         (block_header_hash, snapshot_metadata.block_hash))
    >>=? fun () ->
    (* Restore context *)
    Importer.restore_context
      snapshot_importer
      context_index
      ~expected_context_hash:predecessor_header.Block_header.shell.context
      ~nb_context_elements:snapshot_metadata.context_elements
    >>=? fun () ->
    let pred_context_hash = predecessor_header.shell.context in
    (Context.checkout context_index pred_context_hash >>= function
     | Some ch -> return ch
     | None -> fail (Inconsistent_context pred_context_hash))
    >>=? fun predecessor_context ->
    let apply_environment =
      {
        Block_validation.max_operations_ttl =
          Int32.to_int predecessor_header.shell.level;
        chain_id;
        predecessor_block_header = predecessor_header;
        predecessor_context;
        predecessor_block_metadata_hash;
        predecessor_ops_metadata_hash;
        user_activated_upgrades;
        user_activated_protocol_overrides;
      }
    in
    (Block_validation.apply
       apply_environment
       block_header
       operations
       ~cache:`Lazy
     >>= function
     | Ok block_validation_result -> return block_validation_result
     | Error errs ->
         Format.kasprintf
           (fun errs ->
             fail
               (Target_block_validation_failed
                  (Block_header.hash block_header, errs)))
           "%a"
           pp_print_trace
           errs)
    >>=? fun {result = block_validation_result; _} ->
    check_context_hash_consistency
      block_validation_result.validation_store
      block_header
    >>=? fun () ->
    return (block_data, genesis_ctxt_hash, block_validation_result)

  (* TODO parallelise in another process *)
  (* TODO? remove patch context *)
  let import ~snapshot_path ?patch_context ?block:user_expected_block
      ?(check_consistency = true) ~dst_store_dir ~dst_context_dir ~chain_name
      ~user_activated_upgrades ~user_activated_protocol_overrides
      (genesis : Genesis.t) =
    let chain_id = Chain_id.of_block_hash genesis.Genesis.block in
    init ~snapshot_path ~dst_store_dir chain_id >>= fun snapshot_importer ->
    let dst_store_dir = Naming.dir_path dst_store_dir in
    fail_when
      (Sys.file_exists dst_store_dir)
      (Directory_already_exists dst_store_dir)
    >>=? fun () ->
    let dst_store_dir = Naming.store_dir ~dir_path:dst_store_dir in
    let dst_protocol_dir = Naming.protocol_store_dir dst_store_dir in
    let chain_id = Chain_id.of_block_hash genesis.block in
    let dst_chain_dir = Naming.chain_dir dst_store_dir chain_id in
    let dst_cemented_dir = Naming.cemented_blocks_dir dst_chain_dir in
    (* Create directories *)
    Lwt_list.iter_s
      (Lwt_utils_unix.create_dir ~perm:0o755)
      [
        Naming.dir_path dst_store_dir;
        Naming.dir_path dst_protocol_dir;
        Naming.dir_path dst_chain_dir;
        Naming.dir_path dst_cemented_dir;
      ]
    >>= fun () ->
    fail_unless
      (Sys.file_exists snapshot_path)
      (Snapshot_file_not_found snapshot_path)
    >>=? fun () ->
    Importer.load_snapshot_header snapshot_importer >>=? fun snapshot_header ->
    let (_, snapshot_metadata) = snapshot_header in
    fail_unless
      (Distributed_db_version.Name.equal
         chain_name
         snapshot_metadata.chain_name)
      (Inconsistent_chain_import
         {expected = snapshot_metadata.chain_name; got = chain_name})
    >>=? fun () ->
    import_log_notice
      ~snapshot_header:(Current_header snapshot_header)
      snapshot_path
      user_expected_block
    >>= fun () ->
    Context.init ~readonly:false ?patch_context dst_context_dir
    >>= fun context_index ->
    (* Restore context *)
    restore_and_apply_context
      snapshot_importer
      ?user_expected_block
      ~context_index
      ~user_activated_upgrades
      ~user_activated_protocol_overrides
      snapshot_metadata
      genesis
      chain_id
    >>=? fun (block_data, genesis_context_hash, block_validation_result) ->
    (* Restore store *)
    (* Restore protocols *)
    restore_protocols snapshot_importer >>=? fun protocol_levels ->
    (* Restore cemented dir *)
    restore_cemented_blocks
      snapshot_importer
      ~check_consistency
      ~dst_chain_dir
      ~genesis_hash:genesis.block
    >>=? fun () ->
    read_floating_blocks snapshot_importer ~genesis_hash:genesis.block
    >>=? fun (reading_thread, floating_blocks_stream) ->
    let {
      Block_validation.validation_store;
      block_metadata;
      ops_metadata;
      block_metadata_hash;
      ops_metadata_hashes;
    } =
      block_validation_result
    in
    let contents =
      {
        Block_repr.header = block_data.block_header;
        operations = block_data.operations;
        block_metadata_hash;
        operations_metadata_hashes = ops_metadata_hashes;
      }
    in
    let metadata =
      Some
        ({
           message = validation_store.message;
           max_operations_ttl = validation_store.max_operations_ttl;
           last_allowed_fork_level = validation_store.last_allowed_fork_level;
           block_metadata;
           operations_metadata = ops_metadata;
         }
          : Block_repr.metadata)
    in
    let new_head_with_metadata =
      ({hash = Block_header.hash block_data.block_header; contents; metadata}
        : Block_repr.block)
    in
    (* Set the history mode with the default additional cycle
       offset. This is necessary as the snapshot content does not rely
       on a given offset. If the node was configured to run with the
       non default number of additional cycles, it will be
       automatically updated when running the node. *)
    (let open History_mode in
    match snapshot_metadata.history_mode with
    | Archive -> assert false
    | Rolling _ -> return (Rolling None)
    | Full _ -> return (Full None))
    >>=? fun history_mode ->
    Animation.display_progress
      ~every:100
      ~pp_print_step:(fun fmt i ->
        Format.fprintf fmt "Storing floating blocks: %d blocks wrote" i)
      (fun notify ->
        Store.Unsafe.restore_from_snapshot
          ~notify
          dst_store_dir
          ~context_index
          ~genesis
          ~genesis_context_hash
          ~floating_blocks_stream
          ~new_head_with_metadata
          ~protocol_levels
          ~history_mode)
    >>=? fun () ->
    reading_thread >>=? fun () ->
    Context.close context_index >>= fun () ->
    Event.(emit import_success snapshot_path) >>= fun () ->
    close snapshot_importer >>= fun () -> return_unit
end

(* [snapshot_file_kind ~snapshot_path] returns the kind of a
   snapshot. We assume that a snapshot is valid if the medata can be
   read. *)
let snapshot_file_kind ~snapshot_path =
  let is_valid_uncompressed_snapshot file =
    let (module Loader) =
      (module Make_snapshot_loader (Tar_loader) : Snapshot_loader)
    in
    Lwt.catch
      (fun () ->
        Loader.load_snapshot_header ~snapshot_path:(Naming.file_path file)
        >>=? fun _header -> return_unit)
      (fun e -> fail_with_exn e)
  in
  let is_valid_raw_snapshot snapshot_dir =
    let (module Loader) =
      (module Make_snapshot_loader (Raw_loader) : Snapshot_loader)
    in
    Lwt.catch
      (fun () ->
        Loader.load_snapshot_header
          ~snapshot_path:(Naming.dir_path snapshot_dir)
        >>=? fun _header -> return_unit)
      fail_with_exn
  in
  protect (fun () ->
      Lwt_utils_unix.is_directory snapshot_path >>= fun is_dir ->
      if is_dir then
        let snapshot_dir = Naming.snapshot_dir ~snapshot_path () in
        is_valid_raw_snapshot snapshot_dir >>=? fun () -> return Raw
      else
        let snapshot_file =
          Naming.snapshot_file
            ~snapshot_filename:(Filename.basename snapshot_path)
            Naming.(
              snapshot_dir ~snapshot_path:(Filename.dirname snapshot_path) ())
        in
        is_valid_uncompressed_snapshot snapshot_file >>=? fun () -> return Tar)

let export ?snapshot_path export_format ?rolling ~block ~store_dir ~context_dir
    ~chain_name genesis =
  let (module Exporter) =
    match export_format with
    | Tar -> (module Make_snapshot_exporter (Tar_exporter) : Snapshot_exporter)
    | Raw -> (module Make_snapshot_exporter (Raw_exporter) : Snapshot_exporter)
  in
  Exporter.export
    ?snapshot_path
    ?rolling
    ~block
    ~store_dir
    ~context_dir
    ~chain_name
    genesis

let read_snapshot_header ~snapshot_path =
  snapshot_file_kind ~snapshot_path >>=? fun kind ->
  let (module Loader) =
    match kind with
    | Tar -> (module Make_snapshot_loader (Tar_loader) : Snapshot_loader)
    | Raw -> (module Make_snapshot_loader (Raw_loader) : Snapshot_loader)
  in
  Loader.load_snapshot_header ~snapshot_path >>=? fun (version, metadata) ->
  return (Current_header (version, metadata))

let import ~snapshot_path ?patch_context ?block ?check_consistency
    ~dst_store_dir ~dst_context_dir ~chain_name ~user_activated_upgrades
    ~user_activated_protocol_overrides genesis =
  snapshot_file_kind ~snapshot_path >>=? fun kind ->
  let (module Importer) =
    match kind with
    | Tar -> (module Make_snapshot_importer (Tar_importer) : Snapshot_importer)
    | Raw -> (module Make_snapshot_importer (Raw_importer) : Snapshot_importer)
  in
  let dst_store_dir = Naming.store_dir ~dir_path:dst_store_dir in
  Importer.import
    ~snapshot_path
    ?patch_context
    ?block
    ?check_consistency
    ~dst_store_dir
    ~dst_context_dir
    ~chain_name
    ~user_activated_upgrades
    ~user_activated_protocol_overrides
    genesis
