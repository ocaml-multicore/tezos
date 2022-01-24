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

open Baking_state
open Protocol.Alpha_context

type loop_state

val create_loop_state :
  proposal Lwt_stream.t -> Operation_worker.t -> loop_state

val sleep_until : Time.Protocol.t -> unit Lwt.t option

(** An event monitor using the streams in [loop_state] (to create
    promises) and a timeout promise [timeout]. The function reacts to a
    promise being fulfilled by firing an event [Baking_state.event]. *)
val wait_next_event :
  timeout:timeout_kind Lwt.t ->
  loop_state ->
  (event option, error trace) result Lwt.t

val compute_next_round_time : state -> (Time.Protocol.t * Round.t) option

val first_potential_round_at_next_level :
  state -> earliest_round:Round.t -> (Round.t * delegate) option

val compute_next_potential_baking_time_at_next_level :
  state -> (Time.Protocol.t * Round.t) option Lwt.t

val compute_next_timeout : state -> timeout_kind Lwt.t tzresult Lwt.t

val create_initial_state :
  Protocol_client_context.full ->
  ?synchronize:bool ->
  chain:Chain_services.chain ->
  Baking_configuration.t ->
  Operation_worker.t ->
  current_proposal:proposal ->
  delegate trace ->
  state tzresult Lwt.t

val compute_bootstrap_event : state -> event tzresult

val automaton_loop :
  ?stop_on_event:(event -> bool) ->
  config:Baking_configuration.t ->
  on_error:(tztrace -> (unit, tztrace) result Lwt.t) ->
  loop_state ->
  state ->
  event ->
  event option tzresult Lwt.t

val run :
  Protocol_client_context.full ->
  ?canceler:Lwt_canceler.t ->
  ?stop_on_event:(event -> bool) ->
  ?on_error:(tztrace -> unit tzresult Lwt.t) ->
  chain:Chain_services.chain ->
  Baking_configuration.t ->
  delegate trace ->
  unit tzresult Lwt.t
