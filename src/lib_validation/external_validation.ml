(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Nomadic Labs. <contact@nomadic-labs.com>               *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

type parameters = {
  context_root : string;
  protocol_root : string;
  genesis : Genesis.t;
  sandbox_parameters : Data_encoding.json option;
  user_activated_upgrades : User_activated.upgrades;
  user_activated_protocol_overrides : User_activated.protocol_overrides;
}

type request =
  | Init
  | Validate of {
      chain_id : Chain_id.t;
      block_header : Block_header.t;
      predecessor_block_header : Block_header.t;
      predecessor_block_metadata_hash : Block_metadata_hash.t option;
      predecessor_ops_metadata_hash :
        Operation_metadata_list_list_hash.t option;
      operations : Operation.t list list;
      max_operations_ttl : int;
    }
  | Preapply of {
      chain_id : Chain_id.t;
      timestamp : Time.Protocol.t;
      protocol_data : bytes;
      live_blocks : Block_hash.Set.t;
      live_operations : Operation_hash.Set.t;
      predecessor_shell_header : Block_header.shell_header;
      predecessor_hash : Block_hash.t;
      predecessor_block_metadata_hash : Block_metadata_hash.t option;
      predecessor_ops_metadata_hash :
        Operation_metadata_list_list_hash.t option;
      operations : Operation.t list list;
    }
  | Commit_genesis of {chain_id : Chain_id.t}
  | Fork_test_chain of {
      context_hash : Context_hash.t;
      forked_header : Block_header.t;
    }
  | Terminate
  | Reconfigure_event_logging of Internal_event_unix.Configuration.t

let request_pp ppf = function
  | Init -> Format.fprintf ppf "process handshake"
  | Validate {block_header; chain_id; _} ->
      Format.fprintf
        ppf
        "block validation %a for chain %a"
        Block_hash.pp_short
        (Block_header.hash block_header)
        Chain_id.pp_short
        chain_id
  | Preapply {predecessor_hash; chain_id; _} ->
      Format.fprintf
        ppf
        "preapply block ontop of %a for chain %a"
        Block_hash.pp_short
        predecessor_hash
        Chain_id.pp_short
        chain_id
  | Commit_genesis {chain_id} ->
      Format.fprintf
        ppf
        "commit genesis block for chain %a"
        Chain_id.pp_short
        chain_id
  | Fork_test_chain {forked_header; _} ->
      Format.fprintf
        ppf
        "test chain fork on block %a"
        Block_hash.pp_short
        (Block_header.hash forked_header)
  | Terminate -> Format.fprintf ppf "terminate validation process"
  | Reconfigure_event_logging _ ->
      Format.fprintf ppf "reconfigure event logging"

let magic = Bytes.of_string "TEZOS_FORK_VALIDATOR_MAGIC_0"

let parameters_encoding =
  let open Data_encoding in
  conv
    (fun {
           context_root;
           protocol_root;
           genesis;
           user_activated_upgrades;
           user_activated_protocol_overrides;
           sandbox_parameters;
         } ->
      ( context_root,
        protocol_root,
        genesis,
        user_activated_upgrades,
        user_activated_protocol_overrides,
        sandbox_parameters ))
    (fun ( context_root,
           protocol_root,
           genesis,
           user_activated_upgrades,
           user_activated_protocol_overrides,
           sandbox_parameters ) ->
      {
        context_root;
        protocol_root;
        genesis;
        user_activated_upgrades;
        user_activated_protocol_overrides;
        sandbox_parameters;
      })
    (obj6
       (req "context_root" string)
       (req "protocol_root" string)
       (req "genesis" Genesis.encoding)
       (req "user_activated_upgrades" User_activated.upgrades_encoding)
       (req
          "user_activated_protocol_overrides"
          User_activated.protocol_overrides_encoding)
       (opt "sandbox_parameters" json))

let case_validate tag =
  let open Data_encoding in
  case
    tag
    ~title:"validate"
    (obj7
       (req "chain_id" Chain_id.encoding)
       (req "block_header" (dynamic_size Block_header.encoding))
       (req "pred_header" (dynamic_size Block_header.encoding))
       (opt "pred_block_metadata_hash" Block_metadata_hash.encoding)
       (opt "pred_ops_metadata_hash" Operation_metadata_list_list_hash.encoding)
       (req "max_operations_ttl" int31)
       (req "operations" (list (list (dynamic_size Operation.encoding)))))
    (function
      | Validate
          {
            chain_id;
            block_header;
            predecessor_block_header;
            predecessor_block_metadata_hash;
            predecessor_ops_metadata_hash;
            max_operations_ttl;
            operations;
          } ->
          Some
            ( chain_id,
              block_header,
              predecessor_block_header,
              predecessor_block_metadata_hash,
              predecessor_ops_metadata_hash,
              max_operations_ttl,
              operations )
      | _ -> None)
    (fun ( chain_id,
           block_header,
           predecessor_block_header,
           predecessor_block_metadata_hash,
           predecessor_ops_metadata_hash,
           max_operations_ttl,
           operations ) ->
      Validate
        {
          chain_id;
          block_header;
          predecessor_block_header;
          predecessor_block_metadata_hash;
          predecessor_ops_metadata_hash;
          max_operations_ttl;
          operations;
        })

let case_preapply tag =
  let open Data_encoding in
  case
    tag
    ~title:"preapply"
    (obj10
       (req "chain_id" Chain_id.encoding)
       (req "timestamp" Time.Protocol.encoding)
       (req "protocol_data" bytes)
       (req "live_blocks" Block_hash.Set.encoding)
       (req "live_operations" Operation_hash.Set.encoding)
       (req "predecessor_shell_header" Block_header.shell_header_encoding)
       (req "predecessor_hash" Block_hash.encoding)
       (opt "predecessor_block_metadata_hash" Block_metadata_hash.encoding)
       (opt
          "predecessor_ops_metadata_hash"
          Operation_metadata_list_list_hash.encoding)
       (req "operations" (list (list (dynamic_size Operation.encoding)))))
    (function
      | Preapply
          {
            chain_id;
            timestamp;
            protocol_data;
            live_blocks;
            live_operations;
            predecessor_shell_header;
            predecessor_hash;
            predecessor_block_metadata_hash;
            predecessor_ops_metadata_hash;
            operations;
          } ->
          Some
            ( chain_id,
              timestamp,
              protocol_data,
              live_blocks,
              live_operations,
              predecessor_shell_header,
              predecessor_hash,
              predecessor_block_metadata_hash,
              predecessor_ops_metadata_hash,
              operations )
      | _ -> None)
    (fun ( chain_id,
           timestamp,
           protocol_data,
           live_blocks,
           live_operations,
           predecessor_shell_header,
           predecessor_hash,
           predecessor_block_metadata_hash,
           predecessor_ops_metadata_hash,
           operations ) ->
      Preapply
        {
          chain_id;
          timestamp;
          protocol_data;
          live_blocks;
          live_operations;
          predecessor_shell_header;
          predecessor_hash;
          predecessor_block_metadata_hash;
          predecessor_ops_metadata_hash;
          operations;
        })

let request_encoding =
  let open Data_encoding in
  union
    [
      case
        (Tag 0)
        ~title:"init"
        empty
        (function Init -> Some () | _ -> None)
        (fun () -> Init);
      case_validate (Tag 1);
      case
        (Tag 2)
        ~title:"commit_genesis"
        (obj1 (req "chain_id" Chain_id.encoding))
        (function Commit_genesis {chain_id} -> Some chain_id | _ -> None)
        (fun chain_id -> Commit_genesis {chain_id});
      case
        (Tag 3)
        ~title:"fork_test_chain"
        (obj2
           (req "context_hash" Context_hash.encoding)
           (req "forked_header" Block_header.encoding))
        (function
          | Fork_test_chain {context_hash; forked_header} ->
              Some (context_hash, forked_header)
          | _ -> None)
        (fun (context_hash, forked_header) ->
          Fork_test_chain {context_hash; forked_header});
      case
        (Tag 4)
        ~title:"terminate"
        unit
        (function Terminate -> Some () | _ -> None)
        (fun () -> Terminate);
      (* Tag 5 was ["restore_integrity"]. *)
      case
        (Tag 6)
        ~title:"reconfigure_event_logging"
        Internal_event_unix.Configuration.encoding
        (function Reconfigure_event_logging c -> Some c | _ -> None)
        (fun c -> Reconfigure_event_logging c);
      case_preapply (Tag 7);
    ]

let send pin encoding data =
  let msg = Data_encoding.Binary.to_bytes_exn encoding data in
  Lwt_io.write_int pin (Bytes.length msg) >>= fun () ->
  Lwt_io.write pin (Bytes.to_string msg) >>= fun () -> Lwt_io.flush pin

let recv_result pout encoding =
  Lwt_io.read_int pout >>= fun count ->
  let buf = Bytes.create count in
  Lwt_io.read_into_exactly pout buf 0 count >>= fun () ->
  Lwt.return
    (Data_encoding.Binary.of_bytes_exn
       (Error_monad.result_encoding encoding)
       buf)

let recv pout encoding =
  Lwt_io.read_int pout >>= fun count ->
  let buf = Bytes.create count in
  Lwt_io.read_into_exactly pout buf 0 count >>= fun () ->
  Lwt.return (Data_encoding.Binary.of_bytes_exn encoding buf)

let socket_path_prefix = "tezos-validation-socket-"

let socket_path ~socket_dir ~pid =
  let filename = Format.sprintf "%s%d" socket_path_prefix pid in
  Filename.concat socket_dir filename

(* To get optimized socket communication of processes on the same
   machine, we use Unix domain sockets: ADDR_UNIX. *)
let make_socket socket_path = Unix.ADDR_UNIX socket_path

let create_socket ~canceler =
  let socket = Lwt_unix.socket PF_UNIX SOCK_STREAM 0o000 in
  Lwt_unix.set_close_on_exec socket ;
  Lwt_canceler.on_cancel canceler (fun () ->
      Lwt_utils_unix.safe_close socket >>= fun _ -> Lwt.return_unit) ;
  Lwt_unix.setsockopt socket SO_REUSEADDR true ;
  Lwt.return socket

let create_socket_listen ~canceler ~max_requests ~socket_path =
  create_socket ~canceler >>= fun socket ->
  Lwt.catch
    (fun () -> Lwt_unix.bind socket (make_socket socket_path) >>= return)
    (function
      | Unix.Unix_error (ENAMETOOLONG, _, _) ->
          (* Unix.ENAMETOOLONG (Filename too long (POSIX.1-2001)) can
             be thrown if the given directory has a too long path. *)
          fail
            Block_validator_errors.(
              Validation_process_failed (Socket_path_too_long socket_path))
      | Unix.Unix_error (EACCES, _, _) ->
          (* Unix.EACCES (Permission denied (POSIX.1-2001)) can be
             thrown when the given directory has wrong access rights.
             Unix.EPERM (Operation not permitted (POSIX.1-2001)) should
             not be thrown in this case. *)
          fail
            Block_validator_errors.(
              Validation_process_failed
                (Socket_path_wrong_permission socket_path))
      | exn ->
          fail
            (Block_validator_errors.Validation_process_failed
               (Cannot_run_external_validator (Printexc.to_string exn))))
  >>=? fun () ->
  Lwt_unix.listen socket max_requests ;
  return socket

let create_socket_connect ~canceler ~socket_path =
  create_socket ~canceler >>= fun socket ->
  Lwt_unix.connect socket (make_socket socket_path) >>= fun () ->
  Lwt.return socket
