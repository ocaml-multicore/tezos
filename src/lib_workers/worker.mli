(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2018-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

(** Workers, their types and signatures, and a functor to make them. *)

(** {2 Worker group maker} *)

(** An error returned when trying to communicate with a worker that
    has been closed. *)
type worker_name = {base : string; name : string}

type Error_monad.error += Closed of worker_name

(** Functor to build a group of workers.
    At that point, all the types are fixed and introspectable,
    but the actual parameters and event handlers can be tweaked
    for each individual worker. *)
module type T = sig
  module Name : Worker_intf.NAME

  module Event : Worker_intf.EVENT

  module Request : Worker_intf.REQUEST

  module Types : Worker_intf.TYPES

  (** A handle to a specific worker, parameterized by the type of
      internal message buffer. *)
  type 'kind t

  (** A handle to a table of workers. *)
  type 'kind table

  (** Internal buffer kinds used as parameters to {!t}. *)
  type 'a queue

  and bounded

  and infinite

  type dropbox

  (** Supported kinds of internal buffers. *)
  type _ buffer_kind =
    | Queue : infinite queue buffer_kind
    | Bounded : {size : int} -> bounded queue buffer_kind
    | Dropbox : {
        merge :
          dropbox t -> any_request -> any_request option -> any_request option;
      }
        -> dropbox buffer_kind

  and any_request = Any_request : _ Request.t -> any_request

  (** Create a table of workers. *)
  val create_table : 'kind buffer_kind -> 'kind table

  (** The callback handlers specific to each worker instance. *)
  module type HANDLERS = sig
    (** Placeholder replaced with {!t} with the right parameters
        provided by the type of buffer chosen at {!launch}.*)
    type self

    (** Builds the initial internal state of a worker at launch.
        It is possible to initialize the message queue.
        Of course calling {!state} will fail at that point. *)
    val on_launch :
      self -> Name.t -> Types.parameters -> Types.state tzresult Lwt.t

    (** The main request processor, i.e. the body of the event loop. *)
    val on_request : self -> 'a Request.t -> 'a tzresult Lwt.t

    (** Called when no request has been made before the timeout, if
        the parameter has been passed to {!launch}. *)
    val on_no_request : self -> unit tzresult Lwt.t

    (** A function called when terminating a worker. *)
    val on_close : self -> unit Lwt.t

    (** A function called at the end of the worker loop in case of an
        abnormal error. This function can handle the error by
        returning [Ok ()], or leave the default unexpected error
        behavior by returning its parameter. A possibility is to
        handle the error for ad-hoc logging, and still use
        {!trigger_shutdown} to kill the worker. *)
    val on_error :
      self ->
      Request.view ->
      Worker_types.request_status ->
      error list ->
      unit tzresult Lwt.t

    (** A function called at the end of the worker loop in case of a
        successful treatment of the current request. *)
    val on_completion :
      self -> 'a Request.t -> 'a -> Worker_types.request_status -> unit Lwt.t
  end

  (** Creates a new worker instance.
      Parameter [queue_size] not passed means unlimited queue. *)
  val launch :
    'kind table ->
    ?timeout:Time.System.Span.t ->
    Name.t ->
    Types.parameters ->
    (module HANDLERS with type self = 'kind t) ->
    'kind t tzresult Lwt.t

  (** Triggers a worker termination and waits for its completion.
      Cannot be called from within the handlers.  *)
  val shutdown : _ t -> unit Lwt.t

  (** The following interface are common elements of multiple modules below.
      They are used to minimize repetition. *)
  module type BOX = sig
    (** With [BOX]es, you can put a request right at the front *)
    type t

    val put_request : t -> 'a Request.t -> unit

    val put_request_and_wait : t -> 'a Request.t -> 'a tzresult Lwt.t
  end

  module type QUEUE = sig
    (** With [QUEUE]s, you can push requests in the queue *)
    type 'a t

    val push_request_and_wait : 'q t -> 'a Request.t -> 'a tzresult Lwt.t

    val push_request : 'q t -> 'a Request.t -> unit Lwt.t

    val pending_requests : 'a t -> (Time.System.t * Request.view) list

    val pending_requests_length : 'a t -> int
  end

  module Dropbox : sig
    include BOX with type t := dropbox t
  end

  module Queue : sig
    include QUEUE with type 'a t := 'a queue t

    (** Adds a message to the queue immediately. *)
    val push_request_now : infinite queue t -> 'a Request.t -> unit
  end

  (** Detects cancellation from within the request handler to stop
      asynchronous operations. *)
  val protect :
    _ t ->
    ?on_error:(error list -> 'b tzresult Lwt.t) ->
    (unit -> 'b tzresult Lwt.t) ->
    'b tzresult Lwt.t

  (** Exports the canceler to allow cancellation of other tasks when this
      worker is shutdown or when it dies. *)
  val canceler : _ t -> Lwt_canceler.t

  (** Triggers a worker termination. *)
  val trigger_shutdown : _ t -> unit

  (** Record an event in the backlog. *)
  val record_event : _ t -> Event.t -> unit

  (** Record an event and make sure it is logged. *)
  val log_event : _ t -> Event.t -> unit Lwt.t

  (** Access the internal state, once initialized. *)
  val state : _ t -> Types.state

  (** Introspect the message queue, gives the times requests were pushed. *)
  val pending_requests : _ queue t -> (Time.System.t * Request.view) list

  (** Get the running status of a worker. *)
  val status : _ t -> Worker_types.worker_status

  (** Get the request being treated by a worker.
      Gives the time the request was pushed, and the time its
      treatment started. *)
  val current_request :
    _ t -> (Time.System.t * Time.System.t * Request.view) option

  val information : _ t -> Worker_types.worker_information

  (** Lists the running workers in this group. *)
  val list : 'a table -> (Name.t * 'a t) list

  (** [find_opt table n] is [Some worker] if the [worker] is in the [table] and
      has name [n]. *)
  val find_opt : 'a table -> Name.t -> 'a t option
end

module Make
    (Name : Worker_intf.NAME)
    (Event : Worker_intf.EVENT)
    (Request : Worker_intf.REQUEST)
    (Types : Worker_intf.TYPES)
    (Logger : Worker_intf.LOGGER
                with module Event = Event
                 and type Request.view = Request.view) :
  T
    with module Name = Name
     and module Event = Event
     and module Request = Request
     and module Types = Types
