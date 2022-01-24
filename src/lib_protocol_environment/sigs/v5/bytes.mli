(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Byte sequence operations.

   A byte sequence is a mutable data structure that contains a
   fixed-length sequence of bytes. Each byte can be indexed in
   constant time for reading or writing.

   Given a byte sequence [s] of length [l], we can access each of the
   [l] bytes of [s] via its index in the sequence. Indexes start at
   [0], and we will call an index valid in [s] if it falls within the
   range [[0...l-1]] (inclusive). A position is the point between two
   bytes or at the beginning or end of the sequence.  We call a
   position valid in [s] if it falls within the range [[0...l]]
   (inclusive). Note that the byte at index [n] is between positions
   [n] and [n+1].

   Two parameters [start] and [len] are said to designate a valid
   range of [s] if [len >= 0] and [start] and [start+len] are valid
   positions in [s].

   Byte sequences can be modified in place, for instance via the [set]
   and [blit] functions described below.  See also strings (module
   {!String}), which are almost the same data structure, but cannot be
   modified in place.

   Bytes are represented by the OCaml type [char].

   @since 4.02.0
 *)

external length : bytes -> int = "%bytes_length"
(** Return the length (number of bytes) of the argument. *)

external get : bytes -> int -> char = "%bytes_safe_get"
(** [get s n] returns the byte at index [n] in argument [s].

    Raise [Invalid_argument] if [n] is not a valid index in [s]. *)

external set : bytes -> int -> char -> unit = "%bytes_safe_set"
(** [set s n c] modifies [s] in place, replacing the byte at index [n]
    with [c].

    Raise [Invalid_argument] if [n] is not a valid index in [s]. *)

val make : int -> char -> bytes
(** [make n c] returns a new byte sequence of length [n], filled with
    the byte [c].

    Raise [Invalid_argument] if [n < 0] or [n > ]{!Sys.max_string_length}. *)

val init : int -> (int -> char) -> bytes
(** [Bytes.init n f] returns a fresh byte sequence of length [n], with
    character [i] initialized to the result of [f i] (in increasing
    index order).

    Raise [Invalid_argument] if [n < 0] or [n > ]{!Sys.max_string_length}. *)

val empty : bytes
(** A byte sequence of size 0. *)

val copy : bytes -> bytes
(** Return a new byte sequence that contains the same bytes as the
    argument. *)

val of_string : string -> bytes
(** Return a new byte sequence that contains the same bytes as the
    given string. *)

val to_string : bytes -> string
(** Return a new string that contains the same bytes as the given byte
    sequence. *)

val sub : bytes -> int -> int -> bytes
(** [sub s start len] returns a new byte sequence of length [len],
    containing the subsequence of [s] that starts at position [start]
    and has length [len].

    Raise [Invalid_argument] if [start] and [len] do not designate a
    valid range of [s]. *)

val sub_string : bytes -> int -> int -> string
(** Same as [sub] but return a string instead of a byte sequence. *)

val extend : bytes -> int -> int -> bytes
(** [extend s left right] returns a new byte sequence that contains
    the bytes of [s], with [left] uninitialized bytes prepended and
    [right] uninitialized bytes appended to it. If [left] or [right]
    is negative, then bytes are removed (instead of appended) from
    the corresponding side of [s].

    Raise [Invalid_argument] if the result length is negative or
    longer than {!Sys.max_string_length} bytes. *)

val fill : bytes -> int -> int -> char -> unit
(** [fill s start len c] modifies [s] in place, replacing [len]
    characters with [c], starting at [start].

    Raise [Invalid_argument] if [start] and [len] do not designate a
    valid range of [s]. *)

val blit : bytes -> int -> bytes -> int -> int -> unit
(** [blit src srcoff dst dstoff len] copies [len] bytes from sequence
    [src], starting at index [srcoff], to sequence [dst], starting at
    index [dstoff]. It works correctly even if [src] and [dst] are the
    same byte sequence, and the source and destination intervals
    overlap.

    Raise [Invalid_argument] if [srcoff] and [len] do not
    designate a valid range of [src], or if [dstoff] and [len]
    do not designate a valid range of [dst]. *)

val blit_string : string -> int -> bytes -> int -> int -> unit
(** [blit src srcoff dst dstoff len] copies [len] bytes from string
    [src], starting at index [srcoff], to byte sequence [dst],
    starting at index [dstoff].

    Raise [Invalid_argument] if [srcoff] and [len] do not
    designate a valid range of [src], or if [dstoff] and [len]
    do not designate a valid range of [dst]. *)

val concat : bytes -> bytes list -> bytes
(** [concat sep sl] concatenates the list of byte sequences [sl],
    inserting the separator byte sequence [sep] between each, and
    returns the result as a new byte sequence.

    Raise [Invalid_argument] if the result is longer than
    {!Sys.max_string_length} bytes. *)

val cat : bytes -> bytes -> bytes
(** [cat s1 s2] concatenates [s1] and [s2] and returns the result
     as new byte sequence.

    Raise [Invalid_argument] if the result is longer than
    {!Sys.max_string_length} bytes. *)

val iter : (char -> unit) -> bytes -> unit
(** [iter f s] applies function [f] in turn to all the bytes of [s].
    It is equivalent to [f (get s 0); f (get s 1); ...; f (get s
    (length s - 1)); ()]. *)

val iteri : (int -> char -> unit) -> bytes -> unit
(** Same as {!Bytes.iter}, but the function is applied to the index of
    the byte as first argument and the byte itself as second
    argument. *)

val map : (char -> char) -> bytes -> bytes
(** [map f s] applies function [f] in turn to all the bytes of [s]
    (in increasing index order) and stores the resulting bytes in
    a new sequence that is returned as the result. *)

val mapi : (int -> char -> char) -> bytes -> bytes
(** [mapi f s] calls [f] with each character of [s] and its
    index (in increasing index order) and stores the resulting bytes
    in a new sequence that is returned as the result. *)

val trim : bytes -> bytes
(** Return a copy of the argument, without leading and trailing
    whitespace. The bytes regarded as whitespace are the ASCII
    characters [' '], ['\012'], ['\n'], ['\r'], and ['\t']. *)

val escaped : bytes -> bytes
(** Return a copy of the argument, with special characters represented
    by escape sequences, following the lexical conventions of OCaml.
    All characters outside the ASCII printable range (32..126) are
    escaped, as well as backslash and double-quote.

    Raise [Invalid_argument] if the result is longer than
    {!Sys.max_string_length} bytes. *)

val index_opt: bytes -> char -> int option
(** [index_opt s c] returns the index of the first occurrence of byte [c]
    in [s] or [None] if [c] does not occur in [s].
    @since 4.05 *)

val rindex_opt: bytes -> char -> int option
(** [rindex_opt s c] returns the index of the last occurrence of byte [c]
    in [s] or [None] if [c] does not occur in [s].
    @since 4.05 *)

val index_from_opt: bytes -> int -> char -> int option
(** [index_from _opts i c] returns the index of the first occurrence of
    byte [c] in [s] after position [i] or [None] if [c] does not occur in [s]
    after position [i].
    [Bytes.index_opt s c] is equivalent to [Bytes.index_from_opt s 0 c].

    Raise [Invalid_argument] if [i] is not a valid position in [s].
    @since 4.05 *)

val rindex_from_opt: bytes -> int -> char -> int option
(** [rindex_from_opt s i c] returns the index of the last occurrence
    of byte [c] in [s] before position [i+1] or [None] if [c] does not
    occur in [s] before position [i+1].  [rindex_opt s c] is equivalent to
    [rindex_from s (Bytes.length s - 1) c].

    Raise [Invalid_argument] if [i+1] is not a valid position in [s].
    @since 4.05 *)

val contains : bytes -> char -> bool
(** [contains s c] tests if byte [c] appears in [s]. *)

val contains_from : bytes -> int -> char -> bool
(** [contains_from s start c] tests if byte [c] appears in [s] after
    position [start].  [contains s c] is equivalent to [contains_from
    s 0 c].

    Raise [Invalid_argument] if [start] is not a valid position in [s]. *)

val rcontains_from : bytes -> int -> char -> bool
(** [rcontains_from s stop c] tests if byte [c] appears in [s] before
    position [stop+1].

    Raise [Invalid_argument] if [stop < 0] or [stop+1] is not a valid
    position in [s]. *)

val uppercase_ascii : bytes -> bytes
(** Return a copy of the argument, with all lowercase letters
   translated to uppercase, using the US-ASCII character set.
   @since 4.03.0 *)

val lowercase_ascii : bytes -> bytes
(** Return a copy of the argument, with all uppercase letters
   translated to lowercase, using the US-ASCII character set.
   @since 4.03.0 *)

val capitalize_ascii : bytes -> bytes
(** Return a copy of the argument, with the first character set to uppercase,
   using the US-ASCII character set.
   @since 4.03.0 *)

val uncapitalize_ascii : bytes -> bytes
(** Return a copy of the argument, with the first character set to lowercase,
   using the US-ASCII character set.
   @since 4.03.0 *)

type t = bytes
(** An alias for the type of byte sequences. *)

val compare: t -> t -> int
(** The comparison function for byte sequences, with the same
    specification as {!Stdlib.compare}.  Along with the type [t],
    this function [compare] allows the module [Bytes] to be passed as
    argument to the functors {!Set.Make} and {!Map.Make}. *)

val equal: t -> t -> bool
(** The equality function for byte sequences.
    @since 4.03.0 *)
