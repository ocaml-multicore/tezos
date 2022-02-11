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

(** The [S] signature is similar to {!Seq.S} except that suspended nodes are
    wrapped in a result-Lwt.

    This allows some additional traversors ([map_ep], etc.) to be applied
    lazily.

    The functions [of_seq] and [of_seq_*] allow conversion from vanilla
    sequences. *)
module type S = sig
  type ('a, 'e) seq_e_t (* For substitution by [Seq_e.t] *)

  type 'a seq_s_t (* For substitution by [Seq_s.t] *)

  (** This is similar to {!Seq.S}[.t] but the suspended node is a promised
      result.

      Similarly to [Seq_e], sequences of this module can be interrupted by an
      error. In this case, traversal has fully applied to the successful prefix
      before the returned promise evaluates to [Error _].
   *)
  type (+'a, 'e) node = Nil | Cons of 'a * ('a, 'e) t

  and ('a, 'e) t = unit -> (('a, 'e) node, 'e) result Lwt.t

  val empty : ('a, 'e) t

  val nil : ('a, 'e) node

  val cons : 'a -> ('a, 'e) t -> ('a, 'e) t

  val cons_s : 'a Lwt.t -> ('a, 'e) t -> ('a, 'e) t

  val cons_e : ('a, 'e) result -> ('a, 'e) t -> ('a, 'e) t

  val cons_es : ('a, 'e) result Lwt.t -> ('a, 'e) t -> ('a, 'e) t

  val append : ('a, 'e) t -> ('a, 'e) t -> ('a, 'e) t

  val return : 'a -> ('a, 'e) t

  val return_e : ('a, 'e) result -> ('a, 'e) t

  val return_s : 'a Lwt.t -> ('a, 'e) t

  val return_es : ('a, 'e) result Lwt.t -> ('a, 'e) t

  val interrupted : 'e -> ('a, 'e) t

  val interrupted_s : 'e Lwt.t -> ('a, 'e) t

  val first : ('a, 'e) t -> ('a, 'e) result option Lwt.t

  val fold_left : ('a -> 'b -> 'a) -> 'a -> ('b, 'e) t -> ('a, 'e) result Lwt.t

  val fold_left_e :
    ('a -> 'b -> ('a, 'e) result) -> 'a -> ('b, 'e) t -> ('a, 'e) result Lwt.t

  val fold_left_e_discriminated :
    ('a -> 'b -> ('a, 'f) result) ->
    'a ->
    ('b, 'e) t ->
    ('a, ('e, 'f) Either.t) result Lwt.t

  val fold_left_s :
    ('a -> 'b -> 'a Lwt.t) -> 'a -> ('b, 'e) t -> ('a, 'e) result Lwt.t

  val fold_left_es :
    ('a -> 'b -> ('a, 'e) result Lwt.t) ->
    'a ->
    ('b, 'e) t ->
    ('a, 'e) result Lwt.t

  val fold_left_es_discriminated :
    ('a -> 'b -> ('a, 'f) result Lwt.t) ->
    'a ->
    ('b, 'e) t ->
    ('a, ('e, 'f) Either.t) result Lwt.t

  val iter : ('a -> unit) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  val iter_e :
    ('a -> (unit, 'e) result) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  val iter_e_discriminated :
    ('a -> (unit, 'f) result) ->
    ('a, 'e) t ->
    (unit, ('e, 'f) Either.t) result Lwt.t

  val iter_s : ('a -> unit Lwt.t) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  val iter_es :
    ('a -> (unit, 'e) result Lwt.t) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  val iter_es_discriminated :
    ('a -> (unit, 'f) result Lwt.t) ->
    ('a, 'e) t ->
    (unit, ('e, 'f) Either.t) result Lwt.t

  val map : ('a -> 'b) -> ('a, 'e) t -> ('b, 'e) t

  val map_e : ('a -> ('b, 'e) result) -> ('a, 'e) t -> ('b, 'e) t

  val map_s : ('a -> 'b Lwt.t) -> ('a, 'e) t -> ('b, 'e) t

  val map_es : ('a -> ('b, 'e) result Lwt.t) -> ('a, 'e) t -> ('b, 'e) t

  val map_error : ('e -> 'f) -> ('a, 'e) t -> ('a, 'f) t

  val map_error_s : ('e -> 'f Lwt.t) -> ('a, 'e) t -> ('a, 'f) t

  val filter : ('a -> bool) -> ('a, 'e) t -> ('a, 'e) t

  val filter_e : ('a -> (bool, 'e) result) -> ('a, 'e) t -> ('a, 'e) t

  val filter_s : ('a -> bool Lwt.t) -> ('a, 'e) t -> ('a, 'e) t

  val filter_es : ('a -> (bool, 'e) result Lwt.t) -> ('a, 'e) t -> ('a, 'e) t

  val filter_map : ('a -> 'b option) -> ('a, 'e) t -> ('b, 'e) t

  val filter_map_e : ('a -> ('b option, 'e) result) -> ('a, 'e) t -> ('b, 'e) t

  val filter_map_s : ('a -> 'b option Lwt.t) -> ('a, 'e) t -> ('b, 'e) t

  val filter_map_es :
    ('a -> ('b option, 'e) result Lwt.t) -> ('a, 'e) t -> ('b, 'e) t

  val unfold : ('b -> ('a * 'b) option) -> 'b -> ('a, 'e) t

  val unfold_s : ('b -> ('a * 'b) option Lwt.t) -> 'b -> ('a, 'e) t

  val unfold_e : ('b -> (('a * 'b) option, 'e) result) -> 'b -> ('a, 'e) t

  val unfold_es :
    ('b -> (('a * 'b) option, 'e) result Lwt.t) -> 'b -> ('a, 'e) t

  val of_seq : 'a Stdlib.Seq.t -> ('a, 'e) t

  val of_seq_s : 'a Lwt.t Stdlib.Seq.t -> ('a, 'e) t

  val of_seqs : 'a seq_s_t -> ('a, 'e) t

  val of_seq_e : ('a, 'e) result Stdlib.Seq.t -> ('a, 'e) t

  val of_seqe : ('a, 'e) seq_e_t -> ('a, 'e) t

  val of_seq_es : ('a, 'e) result Lwt.t Stdlib.Seq.t -> ('a, 'e) t
end
