(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Nomadic Labs. <contact@nomadic-labs.com>               *)
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

open Environment_context
open Environment_protocol_T

module type V2 = sig
  include
    Tezos_protocol_environment_sigs.V2.T
      with type Format.formatter = Format.formatter
       and type 'a Data_encoding.t = 'a Data_encoding.t
       and type 'a Data_encoding.lazy_t = 'a Data_encoding.lazy_t
       and type 'a Lwt.t = 'a Lwt.t
       and type ('a, 'b) Pervasives.result = ('a, 'b) result
       and type Chain_id.t = Chain_id.t
       and type Block_hash.t = Block_hash.t
       and type Operation_hash.t = Operation_hash.t
       and type Operation_list_hash.t = Operation_list_hash.t
       and type Operation_list_list_hash.t = Operation_list_list_hash.t
       and type Context.t = Context.t
       and type Context_hash.t = Context_hash.t
       and type Protocol_hash.t = Protocol_hash.t
       and type Time.t = Time.Protocol.t
       and type Operation.shell_header = Operation.shell_header
       and type Operation.t = Operation.t
       and type Block_header.shell_header = Block_header.shell_header
       and type Block_header.t = Block_header.t
       and type 'a RPC_directory.t = 'a RPC_directory.t
       and type Ed25519.Public_key_hash.t = Ed25519.Public_key_hash.t
       and type Ed25519.Public_key.t = Ed25519.Public_key.t
       and type Ed25519.t = Ed25519.t
       and type Secp256k1.Public_key_hash.t = Secp256k1.Public_key_hash.t
       and type Secp256k1.Public_key.t = Secp256k1.Public_key.t
       and type Secp256k1.t = Secp256k1.t
       and type P256.Public_key_hash.t = P256.Public_key_hash.t
       and type P256.Public_key.t = P256.Public_key.t
       and type P256.t = P256.t
       and type Signature.public_key_hash = Signature.public_key_hash
       and type Signature.public_key = Signature.public_key
       and type Signature.t = Signature.t
       and type Signature.watermark = Signature.watermark
       and type Pvss_secp256k1.Commitment.t = Pvss_secp256k1.Commitment.t
       and type Pvss_secp256k1.Encrypted_share.t =
            Pvss_secp256k1.Encrypted_share.t
       and type Pvss_secp256k1.Clear_share.t = Pvss_secp256k1.Clear_share.t
       and type Pvss_secp256k1.Public_key.t = Pvss_secp256k1.Public_key.t
       and type Pvss_secp256k1.Secret_key.t = Pvss_secp256k1.Secret_key.t
       and type 'a Micheline.canonical = 'a Micheline.canonical
       and type Z.t = Z.t
       and type ('a, 'b) Micheline.node = ('a, 'b) Micheline.node
       and type Data_encoding.json_schema = Data_encoding.json_schema
       and type ('a, 'b) RPC_path.t = ('a, 'b) RPC_path.t
       and type RPC_service.meth = RPC_service.meth
       and type (+'m, 'pr, 'p, 'q, 'i, 'o) RPC_service.t =
            ('m, 'pr, 'p, 'q, 'i, 'o) RPC_service.t
       and type Error_monad.shell_tztrace = Error_monad.tztrace
       and type 'a Error_monad.shell_tzresult = ('a, Error_monad.tztrace) result
       and module Sapling = Tezos_sapling.Core.Validator

  type error += Ecoproto_error of Error_monad.error

  val wrap_tzerror : Error_monad.error -> error

  val wrap_tztrace : Error_monad.error Error_monad.trace -> error trace

  val wrap_tzresult : 'a Error_monad.tzresult -> 'a tzresult

  module Lift (P : Updater.PROTOCOL) :
    PROTOCOL
      with type block_header_data = P.block_header_data
       and type block_header_metadata = P.block_header_metadata
       and type block_header = P.block_header
       and type operation_data = P.operation_data
       and type operation_receipt = P.operation_receipt
       and type operation = P.operation
       and type validation_state = P.validation_state

  class ['chain, 'block] proto_rpc_context :
    Tezos_rpc.RPC_context.t
    -> (unit, (unit * 'chain) * 'block) RPC_path.t
    -> ['chain * 'block] RPC_context.simple

  class ['block] proto_rpc_context_of_directory :
    ('block -> RPC_context.t)
    -> RPC_context.t RPC_directory.t
    -> ['block] RPC_context.simple
end

module MakeV2 (Param : sig
  val name : string
end)
() =
struct
  include Stdlib

  (* The modules provided in the [_struct.V2.M] pack are meant specifically to
     shadow modules from [Stdlib]/[Base]/etc. with backwards compatible
     versions. Thus we open the module, hiding the incompatible, newer modules.
  *)
  open Tezos_protocol_environment_structs.V2.M
  module Pervasives = Stdlib
  module Compare = Compare
  module List = List
  module Char = Char
  module Bytes = Bytes
  module Hex = Hex
  module String = String
  module Bits = Bits
  module TzEndian = TzEndian
  module Set = Stdlib.Set
  module Map = Stdlib.Map
  module Int32 = Int32
  module Int64 = Int64
  module Buffer = Buffer
  module Format = Format
  module Option = Tezos_error_monad.TzLwtreslib.Option

  module Raw_hashes = struct
    let sha256 = Hacl.Hash.SHA256.digest

    let sha512 = Hacl.Hash.SHA512.digest

    let blake2b msg = Blake2B.to_bytes (Blake2B.hash_bytes [msg])

    let keccak256 msg = Hacl.Hash.Keccak_256.digest msg

    let sha3_256 msg = Hacl.Hash.SHA3_256.digest msg

    let sha3_512 msg = Hacl.Hash.SHA3_512.digest msg
  end

  module Z = Z
  module Lwt = Lwt
  module Lwt_list = Lwt_list
  module Uri = Uri

  module Data_encoding = struct
    include Data_encoding

    type tag_size = [`Uint8 | `Uint16]

    let def name ?title ?description encoding =
      def (Param.name ^ "." ^ name) ?title ?description encoding
  end

  module Time = Time.Protocol
  module Bls12_381 = Bls12_381
  module Ed25519 = Ed25519
  module Secp256k1 = Secp256k1
  module P256 = P256
  module Signature = Signature
  module Pvss_secp256k1 = Pvss_secp256k1

  module S = struct
    module type T = Tezos_base.S.T

    module type HASHABLE = Tezos_base.S.HASHABLE

    module type MINIMAL_HASH = Tezos_crypto.S.MINIMAL_HASH

    module type B58_DATA = sig
      type t

      val to_b58check : t -> string

      val to_short_b58check : t -> string

      val of_b58check_exn : string -> t

      val of_b58check_opt : string -> t option

      type Base58.data += Data of t

      val b58check_encoding : t Base58.encoding
    end

    module type RAW_DATA = sig
      type t

      val size : int (* in bytes *)

      val to_bytes : t -> Bytes.t

      val of_bytes_opt : Bytes.t -> t option

      val of_bytes_exn : Bytes.t -> t
    end

    module type ENCODER = sig
      type t

      val encoding : t Data_encoding.t

      val rpc_arg : t RPC_arg.t
    end

    module type SET = S.SET

    module type MAP = S.MAP

    module type INDEXES_SET = sig
      include SET

      val encoding : t Data_encoding.t
    end

    module type INDEXES_MAP = sig
      include MAP

      val encoding : 'a Data_encoding.t -> 'a t Data_encoding.t
    end

    module type INDEXES = sig
      type t

      val to_path : t -> string list -> string list

      val of_path : string list -> t option

      val of_path_exn : string list -> t

      val prefix_path : string -> string list

      val path_length : int

      module Set : INDEXES_SET with type elt = t

      module Map : INDEXES_MAP with type key = t
    end

    module type HASH = sig
      include MINIMAL_HASH

      include RAW_DATA with type t := t

      include B58_DATA with type t := t

      include ENCODER with type t := t

      include INDEXES with type t := t
    end

    module type MERKLE_TREE = sig
      type elt

      include HASH

      val compute : elt list -> t

      val empty : t

      type path = Left of path * t | Right of t * path | Op

      val compute_path : elt list -> int -> path

      val check_path : path -> elt -> t * int

      val path_encoding : path Data_encoding.t
    end

    module type SIGNATURE_PUBLIC_KEY_HASH = sig
      type t

      val pp : Format.formatter -> t -> unit

      val pp_short : Format.formatter -> t -> unit

      include Compare.S with type t := t

      include RAW_DATA with type t := t

      include B58_DATA with type t := t

      include ENCODER with type t := t

      include INDEXES with type t := t

      val zero : t
    end

    module type SIGNATURE_PUBLIC_KEY = sig
      type t

      val pp : Format.formatter -> t -> unit

      include Compare.S with type t := t

      include B58_DATA with type t := t

      include ENCODER with type t := t

      type public_key_hash_t

      val hash : t -> public_key_hash_t

      val size : t -> int (* in bytes *)

      val of_bytes_without_validation : bytes -> t option
    end

    module type SIGNATURE = sig
      module Public_key_hash : SIGNATURE_PUBLIC_KEY_HASH

      module Public_key :
        SIGNATURE_PUBLIC_KEY with type public_key_hash_t := Public_key_hash.t

      type t

      val pp : Format.formatter -> t -> unit

      include RAW_DATA with type t := t

      include Compare.S with type t := t

      include B58_DATA with type t := t

      include ENCODER with type t := t

      val zero : t

      type watermark

      (** Check a signature *)
      val check : ?watermark:watermark -> Public_key.t -> t -> Bytes.t -> bool
    end

    module type FIELD = sig
      type t

      (** The order of the finite field *)
      val order : Z.t

      (** minimal number of bytes required to encode a value of the field. *)
      val size_in_bytes : int

      (** [check_bytes bs] returns [true] if [bs] is a correct byte
      representation of a field element *)
      val check_bytes : Bytes.t -> bool

      (** The neutral element for the addition *)
      val zero : t

      (** The neutral element for the multiplication *)
      val one : t

      (** [add a b] returns [a + b mod order] *)
      val add : t -> t -> t

      (** [mul a b] returns [a * b mod order] *)
      val mul : t -> t -> t

      (** [eq a b] returns [true] if [a = b mod order], else [false] *)
      val eq : t -> t -> bool

      (** [negate x] returns [-x mod order]. Equivalently, [negate x] returns the
      unique [y] such that [x + y mod order = 0]
      *)
      val negate : t -> t

      (** [inverse_opt x] returns [x^-1] if [x] is not [0] as an option, else [None] *)
      val inverse_opt : t -> t option

      (** [pow x n] returns [x^n] *)
      val pow : t -> Z.t -> t

      (** From a predefined bytes representation, construct a value t. It is not
      required that to_bytes [(Option.get (of_bytes_opt t)) = t]. By default, little endian encoding
      is used and the given element is modulo the prime order *)
      val of_bytes_opt : Bytes.t -> t option

      (** Convert the value t to a bytes representation which can be used for
      hashing for instance. It is not required that [Option.get (to_bytes
      (of_bytes_opt t)) = t]. By default, little endian encoding is used, and
      length of the resulting bytes may vary depending on the order.
      *)
      val to_bytes : t -> Bytes.t
    end

    (** Module type for the prime fields GF(p) *)
    module type PRIME_FIELD = sig
      include FIELD

      (** [of_z x] builds an element t from the Zarith element [x]. [mod order] is
      applied if [x >= order] or [x < 0]. *)
      val of_z : Z.t -> t

      (** [to_z x] builds a Zarith element, using the decimal representation.
      Arithmetic on the result can be done using the modular functions on
      integers *)
      val to_z : t -> Z.t
    end

    module type CURVE = sig
      (** The type of the element in the elliptic curve *)
      type t

      (** The size of a point representation, in bytes *)
      val size_in_bytes : int

      module Scalar : FIELD

      (** Check if a point, represented as a byte array, is on the curve **)
      val check_bytes : Bytes.t -> bool

      (** Attempt to construct a point from a byte array *)
      val of_bytes_opt : Bytes.t -> t option

      (** Return a representation in bytes *)
      val to_bytes : t -> Bytes.t

      (** Zero of the elliptic curve *)
      val zero : t

      (** A fixed generator of the elliptic curve *)
      val one : t

      (** Return the addition of two element *)
      val add : t -> t -> t

      (** Double the element *)
      val double : t -> t

      (** Return the opposite of the element *)
      val negate : t -> t

      (** Return [true] if the two elements are algebraically the same *)
      val eq : t -> t -> bool

      (** Multiply an element by a scalar *)
      val mul : t -> Scalar.t -> t
    end

    module type PAIRING = sig
      module Gt : FIELD

      module G1 : CURVE

      module G2 : CURVE

      val miller_loop : (G1.t * G2.t) list -> Gt.t

      val final_exponentiation_opt : Gt.t -> Gt.t option

      val pairing : G1.t -> G2.t -> Gt.t
    end

    module type PVSS_ELEMENT = sig
      type t

      include B58_DATA with type t := t

      include ENCODER with type t := t
    end

    module type PVSS_PUBLIC_KEY = sig
      type t

      val pp : Format.formatter -> t -> unit

      include Compare.S with type t := t

      include RAW_DATA with type t := t

      include B58_DATA with type t := t

      include ENCODER with type t := t
    end

    module type PVSS_SECRET_KEY = sig
      type public_key

      type t

      include ENCODER with type t := t

      val to_public_key : t -> public_key
    end

    module type PVSS = sig
      type proof

      module Clear_share : PVSS_ELEMENT

      module Commitment : PVSS_ELEMENT

      module Encrypted_share : PVSS_ELEMENT

      module Public_key : PVSS_PUBLIC_KEY

      module Secret_key : PVSS_SECRET_KEY with type public_key := Public_key.t

      val proof_encoding : proof Data_encoding.t

      val check_dealer_proof :
        Encrypted_share.t list ->
        Commitment.t list ->
        proof:proof ->
        public_keys:Public_key.t list ->
        bool

      val check_revealed_share :
        Encrypted_share.t ->
        Clear_share.t ->
        public_key:Public_key.t ->
        proof ->
        bool

      val reconstruct : Clear_share.t list -> int list -> Public_key.t
    end
  end

  module Error_core = struct
    include
      Tezos_error_monad.Core_maker.Make
        (struct
          let id = Format.asprintf "proto.%s." Param.name
        end)
        (Tezos_protocol_environment_structs.V2.M.Error_monad_classification)

    let error_encoding = Data_encoding.dynamic_size error_encoding
  end

  type error_category = Error_core.error_category

  type error += Ecoproto_error of Error_core.error

  module Wrapped_error_monad = struct
    type unwrapped = Error_core.error = ..

    include (
      Error_core :
        sig
          include
            Tezos_error_monad.Sig.CORE
              with type error := unwrapped
               and type error_category = error_category
        end)

    let unwrap = function Ecoproto_error ecoerror -> Some ecoerror | _ -> None

    let wrap ecoerror = Ecoproto_error ecoerror
  end

  module Error_monad = struct
    type shell_tztrace = Error_monad.tztrace

    type 'a shell_tzresult = ('a, Error_monad.tztrace) result

    include Error_core
    include Tezos_error_monad.TzLwtreslib.Monad
    include
      Tezos_error_monad.Monad_extension_maker.Make (Error_core) (TzTrace)
        (Tezos_error_monad.TzLwtreslib.Monad)

    (* Backwards compatibility additions (traversors, dont_wait, trace helpers) *)
    include Error_monad_traversors
    include Error_monad_preallocated_values
    include Error_monad_trace_eval

    let dont_wait ex er f = dont_wait f er ex

    let make_trace_encoding e = TzTrace.encoding e

    let pp_trace = pp_print_trace

    type 'err trace = 'err TzTrace.trace

    (* Shouldn't be used, only to keep the same environment interface *)
    let classify_error error = (find_info_of_error error).category

    let both_e = Tzresult_syntax.both

    let join_e = Tzresult_syntax.join

    let all_e = Tzresult_syntax.all
  end

  let () =
    let id = Format.asprintf "proto.%s.wrapper" Param.name in
    register_wrapped_error_kind
      (module Wrapped_error_monad)
      ~id
      ~title:("Error returned by protocol " ^ Param.name)
      ~description:("Wrapped error for economic protocol " ^ Param.name ^ ".")

  let wrap_tzerror error = Ecoproto_error error

  let wrap_tztrace t = List.map wrap_tzerror t

  let wrap_tzresult r = Result.map_error wrap_tztrace r

  module Chain_id = Chain_id
  module Block_hash = Block_hash
  module Operation_hash = Operation_hash
  module Operation_list_hash = Operation_list_hash
  module Operation_list_list_hash = Operation_list_list_hash
  module Context_hash = Context_hash
  module Protocol_hash = Protocol_hash
  module Blake2B = Blake2B
  module Fitness = Fitness
  module Operation = Operation
  module Block_header = Block_header
  module Protocol = Protocol
  module RPC_arg = RPC_arg
  module RPC_path = RPC_path
  module RPC_query = RPC_query
  module RPC_service = RPC_service

  module RPC_answer = struct
    type 'o t =
      [ `Ok of 'o (* 200 *)
      | `OkStream of 'o stream (* 200 *)
      | `Created of string option (* 201 *)
      | `No_content (* 204 *)
      | `Unauthorized of Error_monad.error list option (* 401 *)
      | `Forbidden of Error_monad.error list option (* 403 *)
      | `Not_found of Error_monad.error list option (* 404 *)
      | `Conflict of Error_monad.error list option (* 409 *)
      | `Error of Error_monad.error list option (* 500 *) ]

    and 'a stream = 'a Resto_directory.Answer.stream = {
      next : unit -> 'a option Lwt.t;
      shutdown : unit -> unit;
    }

    let return x = Lwt.return (`Ok x)

    let return_chunked x = Lwt.return (`OkChunk x)

    let return_stream x = Lwt.return (`OkStream x)

    let not_found = Lwt.return (`Not_found None)

    let fail err = Lwt.return (`Error (Some err))
  end

  module RPC_directory = struct
    include RPC_directory

    let gen_register dir service handler =
      gen_register dir service (fun p q i ->
          handler p q i >>= function
          | `Ok o -> RPC_answer.return_chunked o
          | `OkStream s -> RPC_answer.return_stream s
          | `Created s -> Lwt.return (`Created s)
          | `No_content -> Lwt.return `No_content
          | `Unauthorized e ->
              let e = Option.map (List.map (fun e -> Ecoproto_error e)) e in
              Lwt.return (`Unauthorized e)
          | `Forbidden e ->
              let e = Option.map (List.map (fun e -> Ecoproto_error e)) e in
              Lwt.return (`Forbidden e)
          | `Not_found e ->
              let e = Option.map (List.map (fun e -> Ecoproto_error e)) e in
              Lwt.return (`Not_found e)
          | `Conflict e ->
              let e = Option.map (List.map (fun e -> Ecoproto_error e)) e in
              Lwt.return (`Conflict e)
          | `Error e ->
              let e = Option.map (List.map (fun e -> Ecoproto_error e)) e in
              Lwt.return (`Error e))

    let register dir service handler =
      gen_register dir service (fun p q i ->
          handler p q i >>= function
          | Ok o -> RPC_answer.return o
          | Error e -> RPC_answer.fail e)

    let opt_register dir service handler =
      gen_register dir service (fun p q i ->
          handler p q i >>= function
          | Ok (Some o) -> RPC_answer.return o
          | Ok None -> RPC_answer.not_found
          | Error e -> RPC_answer.fail e)

    let lwt_register dir service handler =
      gen_register dir service (fun p q i ->
          handler p q i >>= fun o -> RPC_answer.return o)

    open Curry

    let register0 root s f = register root s (curry Z f)

    let register1 root s f = register root s (curry (S Z) f)

    let register2 root s f = register root s (curry (S (S Z)) f)

    let register3 root s f = register root s (curry (S (S (S Z))) f)

    let register4 root s f = register root s (curry (S (S (S (S Z)))) f)

    let register5 root s f = register root s (curry (S (S (S (S (S Z))))) f)

    let opt_register0 root s f = opt_register root s (curry Z f)

    let opt_register1 root s f = opt_register root s (curry (S Z) f)

    let opt_register2 root s f = opt_register root s (curry (S (S Z)) f)

    let opt_register3 root s f = opt_register root s (curry (S (S (S Z))) f)

    let opt_register4 root s f = opt_register root s (curry (S (S (S (S Z)))) f)

    let opt_register5 root s f =
      opt_register root s (curry (S (S (S (S (S Z))))) f)

    let gen_register0 root s f = gen_register root s (curry Z f)

    let gen_register1 root s f = gen_register root s (curry (S Z) f)

    let gen_register2 root s f = gen_register root s (curry (S (S Z)) f)

    let gen_register3 root s f = gen_register root s (curry (S (S (S Z))) f)

    let gen_register4 root s f = gen_register root s (curry (S (S (S (S Z)))) f)

    let gen_register5 root s f =
      gen_register root s (curry (S (S (S (S (S Z))))) f)

    let lwt_register0 root s f = lwt_register root s (curry Z f)

    let lwt_register1 root s f = lwt_register root s (curry (S Z) f)

    let lwt_register2 root s f = lwt_register root s (curry (S (S Z)) f)

    let lwt_register3 root s f = lwt_register root s (curry (S (S (S Z))) f)

    let lwt_register4 root s f = lwt_register root s (curry (S (S (S (S Z)))) f)

    let lwt_register5 root s f =
      lwt_register root s (curry (S (S (S (S (S Z))))) f)
  end

  module RPC_context = struct
    type t = rpc_context

    class type ['pr] simple =
      object
        method call_proto_service0 :
          'm 'q 'i 'o.
          (([< RPC_service.meth] as 'm), t, t, 'q, 'i, 'o) RPC_service.t ->
          'pr ->
          'q ->
          'i ->
          'o Error_monad.shell_tzresult Lwt.t

        method call_proto_service1 :
          'm 'a 'q 'i 'o.
          (([< RPC_service.meth] as 'm), t, t * 'a, 'q, 'i, 'o) RPC_service.t ->
          'pr ->
          'a ->
          'q ->
          'i ->
          'o Error_monad.shell_tzresult Lwt.t

        method call_proto_service2 :
          'm 'a 'b 'q 'i 'o.
          ( ([< RPC_service.meth] as 'm),
            t,
            (t * 'a) * 'b,
            'q,
            'i,
            'o )
          RPC_service.t ->
          'pr ->
          'a ->
          'b ->
          'q ->
          'i ->
          'o Error_monad.shell_tzresult Lwt.t

        method call_proto_service3 :
          'm 'a 'b 'c 'q 'i 'o.
          ( ([< RPC_service.meth] as 'm),
            t,
            ((t * 'a) * 'b) * 'c,
            'q,
            'i,
            'o )
          RPC_service.t ->
          'pr ->
          'a ->
          'b ->
          'c ->
          'q ->
          'i ->
          'o Error_monad.shell_tzresult Lwt.t
      end

    let make_call0 s (ctxt : _ simple) = ctxt#call_proto_service0 s

    let make_call0 = (make_call0 : _ -> _ simple -> _ :> _ -> _ #simple -> _)

    let make_call1 s (ctxt : _ simple) = ctxt#call_proto_service1 s

    let make_call1 = (make_call1 : _ -> _ simple -> _ :> _ -> _ #simple -> _)

    let make_call2 s (ctxt : _ simple) = ctxt#call_proto_service2 s

    let make_call2 = (make_call2 : _ -> _ simple -> _ :> _ -> _ #simple -> _)

    let make_call3 s (ctxt : _ simple) = ctxt#call_proto_service3 s

    let make_call3 = (make_call3 : _ -> _ simple -> _ :> _ -> _ #simple -> _)

    let make_opt_call0 s ctxt block q i =
      make_call0 s ctxt block q i >>= function
      | Error [RPC_context.Not_found _] -> Lwt.return_ok None
      | Error _ as v -> Lwt.return v
      | Ok v -> Lwt.return_ok (Some v)

    let make_opt_call1 s ctxt block a1 q i =
      make_call1 s ctxt block a1 q i >>= function
      | Error [RPC_context.Not_found _] -> Lwt.return_ok None
      | Error _ as v -> Lwt.return v
      | Ok v -> Lwt.return_ok (Some v)

    let make_opt_call2 s ctxt block a1 a2 q i =
      make_call2 s ctxt block a1 a2 q i >>= function
      | Error [RPC_context.Not_found _] -> Lwt.return_ok None
      | Error _ as v -> Lwt.return v
      | Ok v -> Lwt.return_ok (Some v)

    let make_opt_call3 s ctxt block a1 a2 a3 q i =
      make_call3 s ctxt block a1 a2 a3 q i >>= function
      | Error [RPC_context.Not_found _] -> Lwt.return_ok None
      | Error _ as v -> Lwt.return v
      | Ok v -> Lwt.return_ok (Some v)
  end

  module Sapling = Tezos_sapling.Core.Validator

  module Micheline = struct
    include Micheline
    include Tezos_micheline.Micheline_encoding

    let canonical_encoding_v1 ~variant encoding =
      canonical_encoding_v1 ~variant:(Param.name ^ "." ^ variant) encoding

    let canonical_encoding ~variant encoding =
      canonical_encoding_v0 ~variant:(Param.name ^ "." ^ variant) encoding
  end

  module Logging = Internal_event.Legacy_logging.Make (Param)

  module Updater = struct
    type nonrec validation_result = validation_result = {
      context : Context.t;
      fitness : Fitness.t;
      message : string option;
      max_operations_ttl : int;
      last_allowed_fork_level : Int32.t;
    }

    type nonrec quota = quota = {max_size : int; max_op : int option}

    type nonrec rpc_context = rpc_context = {
      block_hash : Block_hash.t;
      block_header : Block_header.shell_header;
      context : Context.t;
    }

    let activate = Context.set_protocol

    let fork_test_chain = Context.fork_test_chain

    module type PROTOCOL =
      Environment_protocol_T_V0.T
        with type context := Context.t
         and type quota := quota
         and type validation_result := validation_result
         and type rpc_context := rpc_context
         and type 'a tzresult := 'a Error_monad.tzresult
  end

  module Base58 = struct
    include Tezos_crypto.Base58

    let simple_encode enc s = simple_encode enc s

    let simple_decode enc s = simple_decode enc s

    include Make (struct
      type context = Context.t
    end)

    let decode s = decode s
  end

  module Context = struct
    include Context
    include Environment_context.V2

    let fold ?depth ctxt k ~init ~f =
      Context.fold ?depth ctxt k ~order:`Sorted ~init ~f

    module Tree = struct
      include Tree

      let fold ?depth ctxt k ~init ~f =
        fold ?depth ctxt k ~order:`Sorted ~init ~f
    end

    let register_resolver = Base58.register_resolver

    let complete ctxt s = Base58.complete ctxt s
  end

  module LiftV2 (P : Updater.PROTOCOL) = struct
    include P

    let begin_partial_application ~chain_id ~ancestor_context
        ~predecessor_timestamp ~predecessor_fitness raw_block =
      begin_partial_application
        ~chain_id
        ~ancestor_context
        ~predecessor_timestamp
        ~predecessor_fitness
        raw_block
      >|= wrap_tzresult

    let begin_application ~chain_id ~predecessor_context ~predecessor_timestamp
        ~predecessor_fitness raw_block =
      begin_application
        ~chain_id
        ~predecessor_context
        ~predecessor_timestamp
        ~predecessor_fitness
        raw_block
      >|= wrap_tzresult

    let begin_construction ~chain_id ~predecessor_context ~predecessor_timestamp
        ~predecessor_level ~predecessor_fitness ~predecessor ~timestamp
        ?protocol_data () =
      begin_construction
        ~chain_id
        ~predecessor_context
        ~predecessor_timestamp
        ~predecessor_level
        ~predecessor_fitness
        ~predecessor
        ~timestamp
        ?protocol_data
        ()
      >|= wrap_tzresult

    let current_context c = current_context c >|= wrap_tzresult

    let apply_operation c o = apply_operation c o >|= wrap_tzresult

    let finalize_block c = finalize_block c >|= wrap_tzresult

    let init c bh = init c bh >|= wrap_tzresult
  end

  module Lift (P : Updater.PROTOCOL) = struct
    include LiftV2 (P)

    include IgnoreCaches (struct
      let set_log_message_consumer _ = ()

      let environment_version = Protocol.V2

      include Environment_protocol_T.V0toV3 (LiftV2 (P))
    end)

    let begin_partial_application ~chain_id ~ancestor_context
        ~(predecessor : Block_header.t) ~predecessor_hash:_ ~cache:_
        (raw_block : block_header) =
      begin_partial_application
        ~chain_id
        ~ancestor_context
        ~predecessor_timestamp:predecessor.shell.timestamp
        ~predecessor_fitness:predecessor.shell.fitness
        raw_block
  end

  class ['chain, 'block] proto_rpc_context (t : Tezos_rpc.RPC_context.t)
    (prefix : (unit, (unit * 'chain) * 'block) RPC_path.t) =
    object
      method call_proto_service0
          : 'm 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              RPC_context.t,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'chain * 'block ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s (chain, block) q i ->
          let s = RPC_service.subst0 s in
          let s = RPC_service.prefix prefix s in
          t#call_service s (((), chain), block) q i

      method call_proto_service1
          : 'm 'a 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              RPC_context.t * 'a,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'chain * 'block ->
            'a ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s (chain, block) a1 q i ->
          let s = RPC_service.subst1 s in
          let s = RPC_service.prefix prefix s in
          t#call_service s ((((), chain), block), a1) q i

      method call_proto_service2
          : 'm 'a 'b 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              (RPC_context.t * 'a) * 'b,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'chain * 'block ->
            'a ->
            'b ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s (chain, block) a1 a2 q i ->
          let s = RPC_service.subst2 s in
          let s = RPC_service.prefix prefix s in
          t#call_service s (((((), chain), block), a1), a2) q i

      method call_proto_service3
          : 'm 'a 'b 'c 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              ((RPC_context.t * 'a) * 'b) * 'c,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'chain * 'block ->
            'a ->
            'b ->
            'c ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s (chain, block) a1 a2 a3 q i ->
          let s = RPC_service.subst3 s in
          let s = RPC_service.prefix prefix s in
          t#call_service s ((((((), chain), block), a1), a2), a3) q i
    end

  class ['block] proto_rpc_context_of_directory conv dir :
    ['block] RPC_context.simple =
    let lookup = new Tezos_rpc.RPC_context.of_directory dir in
    object
      method call_proto_service0
          : 'm 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              RPC_context.t,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'block ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s block q i ->
          let rpc_context = conv block in
          lookup#call_service s rpc_context q i

      method call_proto_service1
          : 'm 'a 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              RPC_context.t * 'a,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'block ->
            'a ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s block a1 q i ->
          let rpc_context = conv block in
          lookup#call_service s (rpc_context, a1) q i

      method call_proto_service2
          : 'm 'a 'b 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              (RPC_context.t * 'a) * 'b,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'block ->
            'a ->
            'b ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s block a1 a2 q i ->
          let rpc_context = conv block in
          lookup#call_service s ((rpc_context, a1), a2) q i

      method call_proto_service3
          : 'm 'a 'b 'c 'q 'i 'o.
            ( ([< RPC_service.meth] as 'm),
              RPC_context.t,
              ((RPC_context.t * 'a) * 'b) * 'c,
              'q,
              'i,
              'o )
            RPC_service.t ->
            'block ->
            'a ->
            'b ->
            'c ->
            'q ->
            'i ->
            'o tzresult Lwt.t =
        fun s block a1 a2 a3 q i ->
          let rpc_context = conv block in
          lookup#call_service s (((rpc_context, a1), a2), a3) q i
    end

  module Equality_witness = Environment_context.Equality_witness
end
