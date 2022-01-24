(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** This module provides functions used for tests. *)

type error += Timeout_exceed of string

let () =
  register_error_kind
    `Permanent
    ~id:"test_p2p.utils.timeout_exceed"
    ~title:"Timeout exceed"
    ~description:"The timeout used to wait connections has been exceed."
    ~pp:(fun ppf msg ->
      Format.fprintf ppf "The timeout has been exceed : %s." msg)
    Data_encoding.(obj1 (req "msg" Data_encoding.string))
    (function Timeout_exceed msg -> Some msg | _ -> None)
    (fun msg -> Timeout_exceed msg)

let connect_all ?timeout connect_handler points =
  List.map_ep
    (fun point -> P2p_connect_handler.connect ?timeout connect_handler point)
    points

type 'a timeout_t = {time : float; msg : 'a -> string}

(* [wait_pred] wait until [pred] [arg] is true or [timeout] is exceed. If
     [timeout] is exceed an error is raised. There is a Lwt cooperation
     point. *)
let wait_pred ?timeout ~pred ~arg () =
  let open Lwt_result_syntax in
  let rec inner_wait_pred () =
    let*! () = Lwt.pause () in
    if not (pred arg) then inner_wait_pred () else return_unit
  in
  match timeout with
  | None -> inner_wait_pred ()
  | Some timeout ->
      Lwt.pick
        [
          (let*! () = Lwt_unix.sleep timeout.time in
           Error_monad.fail (Timeout_exceed (timeout.msg arg)));
          inner_wait_pred ();
        ]

let wait_pred_s ?timeout ~pred ~arg () =
  let open Lwt_result_syntax in
  let rec inner_wait_pred () =
    let*! () = Lwt.pause () in
    let*! cond = pred arg in
    if not cond then inner_wait_pred () else return_unit
  in
  match timeout with
  | None -> inner_wait_pred ()
  | Some timeout ->
      Lwt.pick
        [
          (let*! () = Lwt_unix.sleep timeout.time in
           Error_monad.fail (Timeout_exceed (timeout.msg arg)));
          inner_wait_pred ();
        ]

let wait_conns ?timeout ~pool n =
  let timeout =
    Option.map
      (fun timeout ->
        {
          time = timeout;
          msg =
            (fun (pool, n) ->
              Format.asprintf
                "in wait_conns with n = %d and conns = %d"
                n
                (P2p_pool.active_connections pool));
        })
      timeout
  in
  wait_pred
    ?timeout
    ~pred:(fun (pool, n) -> P2p_pool.active_connections pool = n)
    ~arg:(pool, n)
    ()

let close_active_conns pool =
  P2p_pool.Connection.fold
    ~init:Lwt.return_unit
    ~f:(fun _ conn _ -> P2p_conn.disconnect ~wait:true conn)
    pool

let canceler = Lwt_canceler.create () (* unused *)

let proof_of_work_target = Crypto_box.make_pow_target 1.

let id1 = P2p_identity.generate proof_of_work_target

let id2 = P2p_identity.generate proof_of_work_target

let addr = ref Ipaddr.V6.localhost

let version =
  {
    Network_version.chain_name =
      Distributed_db_version.Name.of_string "SANDBOXED_TEZOS";
    distributed_db_version = Distributed_db_version.one;
    p2p_version = P2p_version.zero;
  }

let conn_meta_config : unit P2p_params.conn_meta_config =
  {
    conn_meta_encoding = Data_encoding.empty;
    conn_meta_value = (fun () -> ());
    private_node = (fun _ -> false);
  }

let rec listen ?port addr =
  let open Lwt_syntax in
  let tentative_port =
    match port with None -> 49152 + Random.int 16384 | Some port -> port
  in
  let uaddr = Ipaddr_unix.V6.to_inet_addr addr in
  let main_socket = Lwt_unix.(socket PF_INET6 SOCK_STREAM 0) in
  Lwt_unix.(setsockopt main_socket SO_REUSEADDR true) ;
  Lwt.catch
    (fun () ->
      let* () = Lwt_unix.bind main_socket (ADDR_INET (uaddr, tentative_port)) in
      Lwt_unix.listen main_socket 1 ;
      Lwt.return (main_socket, tentative_port))
    (function
      | Unix.Unix_error ((Unix.EADDRINUSE | Unix.EADDRNOTAVAIL), _, _)
        when port = None ->
          listen addr
      | exn -> Lwt.fail exn)

let rec sync_nodes nodes =
  let open Lwt_result_syntax in
  let* () = List.iter_ep (fun p -> Process.receive p) nodes in
  let* () = List.iter_ep (fun p -> Process.send p ()) nodes in
  sync_nodes nodes

let sync_nodes nodes =
  let open Lwt_result_syntax in
  let*! r = sync_nodes nodes in
  match r with
  | Ok () | Error (Exn End_of_file :: _) -> return_unit
  | Error _ as err -> Lwt.return err

let run_nodes client server =
  let open Lwt_result_syntax in
  let*! (main_socket, port) = listen !addr in
  let* server_node =
    Process.detach ~prefix:"server: " (fun channel ->
        let sched = P2p_io_scheduler.create ~read_buffer_size:(1 lsl 12) () in
        let* () = server channel sched main_socket in
        let*! () = P2p_io_scheduler.shutdown sched in
        return_unit)
  in
  let* client_node =
    Process.detach ~prefix:"client: " (fun channel ->
        let*! () =
          let*! r = Lwt_utils_unix.safe_close main_socket in
          match r with
          | Error trace ->
              Format.eprintf "Uncaught error: %a\n%!" pp_print_trace trace ;
              Lwt.return_unit
          | Ok () -> Lwt.return_unit
        in
        let sched = P2p_io_scheduler.create ~read_buffer_size:(1 lsl 12) () in
        let* () = client channel sched !addr port in
        let*! () = P2p_io_scheduler.shutdown sched in
        return_unit)
  in
  let nodes = [server_node; client_node] in
  Lwt.ignore_result (sync_nodes nodes) ;
  Process.wait_all nodes

let raw_accept sched main_socket =
  let open Lwt_syntax in
  let* (fd, sockaddr) = P2p_fd.accept main_socket in
  let fd = P2p_io_scheduler.register sched fd in
  let point =
    match sockaddr with
    | Lwt_unix.ADDR_UNIX _ -> assert false
    | Lwt_unix.ADDR_INET (addr, port) ->
        (Ipaddr_unix.V6.of_inet_addr_exn addr, port)
  in
  Lwt.return (fd, point)

(** [accept ?id ?proof_of_work_target sched main_socket] connect
   and performs [P2p_socket.authenticate] with the given
   [proof_of_work_target].  *)
let accept ?(id = id1) ?(proof_of_work_target = proof_of_work_target) sched
    main_socket =
  let open Lwt_syntax in
  let* (fd, point) = raw_accept sched main_socket in
  let* id1 = id in
  P2p_socket.authenticate
    ~canceler
    ~proof_of_work_target
    ~incoming:true
    fd
    point
    id1
    version
    conn_meta_config

let raw_connect sched addr port =
  let open Lwt_syntax in
  let* fd = P2p_fd.socket PF_INET6 SOCK_STREAM 0 in
  let uaddr = Lwt_unix.ADDR_INET (Ipaddr_unix.V6.to_inet_addr addr, port) in
  let* () = P2p_fd.connect fd uaddr in
  let fd = P2p_io_scheduler.register sched fd in
  Lwt.return fd

(** [connect ?proof_of_work_target sched addr port] connect
   and performs [P2p_socket.authenticate] with the given
   [proof_of_work_target]. *)
let connect ?(proof_of_work_target = proof_of_work_target) sched addr port id =
  let open Lwt_syntax in
  let* fd = raw_connect sched addr port in
  P2p_socket.authenticate
    ~canceler
    ~proof_of_work_target
    ~incoming:false
    fd
    (addr, port)
    id
    version
    conn_meta_config

let sync ch =
  let open Lwt_result_syntax in
  let* () = Process.Channel.push ch () in
  let* () = Process.Channel.pop ch in
  return_unit
