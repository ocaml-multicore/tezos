(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018-2021 Tarides <contact@tarides.com>                     *)
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

open Tezos_context_encoding.Context

module type DB =
  Irmin.S
    with type key = Path.t
     and type contents = Contents.t
     and type branch = Branch.t
     and type hash = Hash.t
     and type step = Path.step
     and type metadata = Metadata.t
     and type Key.step = Path.step

module Make_tree (Store : DB) = struct
  include Store.Tree

  module Kinded_hash = struct
    let of_context_hash = function
      | `Contents h -> `Contents (Hash.of_context_hash h, ())
      | `Node h -> `Node (Hash.of_context_hash h)

    let to_context_hash = function
      | `Contents (h, ()) -> `Contents (Hash.to_context_hash h)
      | `Node h -> `Node (Hash.to_context_hash h)
  end

  module DB_proof = Store.Tree.Proof

  module Proof = struct
    include Tezos_context_sigs.Context.Proof_types

    let v ~before ~after state = {before; after; state}

    let before t = t.before

    let after t = t.after

    let state t = t.state

    module State = struct
      let rec to_inode : type a b. (a -> b) -> a DB_proof.inode -> b inode =
       fun f {length; proofs} ->
        {length; proofs = List.map (fun (k, v) -> (k, f v)) proofs}

      and to_tree : DB_proof.tree -> tree = function
        | Contents (c, ()) -> Contents c
        | Blinded_contents (h, ()) -> Blinded_contents (Hash.to_context_hash h)
        | Node l -> Node (List.map (fun (k, v) -> (k, to_tree v)) l)
        | Blinded_node h -> Blinded_node (Hash.to_context_hash h)
        | Inode i -> Inode (to_inode to_inode_tree i)
        | Extender e -> Extender (to_inode_extender to_inode_tree e)

      and to_inode_extender :
          type a b. (a -> b) -> a DB_proof.inode_extender -> b inode_extender =
       fun f {length; segments; proof} -> {length; segments; proof = f proof}

      and to_inode_tree : DB_proof.inode_tree -> tree inode_tree = function
        | Blinded_inode h -> Blinded_inode (Hash.to_context_hash h)
        | Inode_values l ->
            Inode_values (List.map (fun (k, v) -> (k, to_tree v)) l)
        | Inode_tree i -> Inode_tree (to_inode to_inode_tree i)
        | Inode_extender e -> Inode_extender (to_inode_extender to_inode_tree e)

      let rec of_inode : type a b. (a -> b) -> a inode -> b DB_proof.inode =
       fun f {length; proofs} ->
        {length; proofs = List.map (fun (k, v) -> (k, f v)) proofs}

      and of_tree : tree -> DB_proof.tree = function
        | Contents c -> Contents (c, ())
        | Blinded_contents h -> Blinded_contents (Hash.of_context_hash h, ())
        | Node l -> Node (List.map (fun (k, v) -> (k, of_tree v)) l)
        | Blinded_node h -> Blinded_node (Hash.of_context_hash h)
        | Inode i -> Inode (of_inode of_inode_tree i)
        | Extender e -> Extender (of_inode_extender of_inode_tree e)

      and of_inode_extender :
          type a b. (a -> b) -> a inode_extender -> b DB_proof.inode_extender =
       fun f {length; segments; proof} -> {length; segments; proof = f proof}

      and of_inode_tree : tree inode_tree -> DB_proof.inode_tree = function
        | Blinded_inode h -> Blinded_inode (Hash.of_context_hash h)
        | Inode_values l ->
            Inode_values (List.map (fun (k, v) -> (k, of_tree v)) l)
        | Inode_tree i -> Inode_tree (of_inode of_inode_tree i)
        | Inode_extender e -> Inode_extender (of_inode_extender of_inode_tree e)

      let of_stream_elt : elt -> DB_proof.elt = function
        | Contents c -> Contents c
        | Node l ->
            Node (List.map (fun (k, v) -> (k, Kinded_hash.of_context_hash v)) l)
        | Inode i -> Inode (of_inode Hash.of_context_hash i)
        | Inode_extender e ->
            Inode_extender (of_inode_extender Hash.of_context_hash e)

      let of_stream : stream -> DB_proof.stream = Seq.map of_stream_elt

      let to_stream_elt : DB_proof.elt -> elt = function
        | Contents c -> Contents c
        | Node l ->
            Node (List.map (fun (k, v) -> (k, Kinded_hash.to_context_hash v)) l)
        | Inode i -> Inode (to_inode Hash.to_context_hash i)
        | Inode_extender e ->
            Inode_extender (to_inode_extender Hash.to_context_hash e)

      let to_stream : DB_proof.stream -> stream = Seq.map to_stream_elt
    end

    let of_proof f p =
      let before = Kinded_hash.to_context_hash (Proof.before p) in
      let after = Kinded_hash.to_context_hash (Proof.after p) in
      let state = f (Proof.state p) in
      v ~before ~after state

    let to_proof f p =
      let before = Kinded_hash.of_context_hash p.before in
      let after = Kinded_hash.of_context_hash p.after in
      let state = f p.state in
      DB_proof.v ~before ~after state

    let to_tree = of_proof State.to_tree

    let of_tree = to_proof State.of_tree

    let to_stream = of_proof State.to_stream

    let of_stream = to_proof State.of_stream
  end

  let produce_proof repo hash f =
    let hash = Kinded_hash.of_context_hash hash in
    produce_proof repo hash f >|= fun (p, r) -> (Proof.to_tree p, r)

  let verify_proof proof f =
    let proof = Proof.of_tree proof in
    verify_proof proof f

  let produce_stream repo hash f =
    let hash = Kinded_hash.of_context_hash hash in
    produce_stream repo hash f >|= fun (p, r) -> (Proof.to_stream p, r)

  let verify_stream proof f =
    let proof = Proof.of_stream proof in
    verify_stream proof f

  let pp = Irmin.Type.pp Store.tree_t

  let empty _ = Store.Tree.empty ()

  let equal = Irmin.Type.(unstage (equal Store.tree_t))

  let is_empty t = equal (Store.Tree.empty ()) t

  let hash t = Hash.to_context_hash (Store.Tree.hash t)

  let add t k v = Store.Tree.add t k v

  let kind t =
    match Store.Tree.destruct t with `Contents _ -> `Value | `Node _ -> `Tree

  let to_value t =
    match Store.Tree.destruct t with
    | `Contents (c, _) -> Store.Tree.Contents.force_exn c >|= Option.some
    | `Node _ -> Lwt.return_none

  let of_value _ v = Store.Tree.add (Store.Tree.empty ()) [] v

  let fold ?depth t k ~(order : [`Sorted | `Undefined]) ~init ~f =
    find_tree t k >>= function
    | None -> Lwt.return init
    | Some t ->
        let order =
          (order :> [`Random of Random.State.t | `Sorted | `Undefined])
        in
        Store.Tree.fold
          ?depth
          ~force:`True
          ~cache:false
          ~uniq:`False
          ~order
          ~tree:(fun k t acc ->
            match kind t with
            | `Value -> if k = [] then Lwt.return acc else f k t acc
            | `Tree -> f k t acc)
          t
          init

  type raw = [`Value of bytes | `Tree of raw TzString.Map.t]

  type concrete = Store.Tree.concrete

  let rec raw_of_concrete : type a. (raw -> a) -> concrete -> a =
   fun k -> function
    | `Tree l -> raw_of_node (fun l -> k (`Tree (TzString.Map.of_seq l))) l
    | `Contents (v, _) -> k (`Value v)

  and raw_of_node :
      type a. ((string * raw) Seq.t -> a) -> (string * concrete) list -> a =
   fun k -> function
    | [] -> k Seq.empty
    | (n, v) :: t ->
        raw_of_concrete
          (fun v -> raw_of_node (fun t -> k (fun () -> Seq.Cons ((n, v), t))) t)
          v

  let to_raw t = Store.Tree.to_concrete t >|= raw_of_concrete (fun t -> t)

  let rec concrete_of_raw : type a. (concrete -> a) -> raw -> a =
   fun k -> function
    | `Tree l -> concrete_of_node (fun l -> k (`Tree l)) (TzString.Map.to_seq l)
    | `Value v -> k (`Contents (v, ()))

  and concrete_of_node :
      type a. ((string * concrete) list -> a) -> (string * raw) Seq.t -> a =
   fun k seq ->
    match seq () with
    | Nil -> k []
    | Cons ((n, v), t) ->
        concrete_of_raw
          (fun v -> concrete_of_node (fun t -> k ((n, v) :: t)) t)
          v

  let of_raw = concrete_of_raw Store.Tree.of_concrete

  let raw_encoding : raw Data_encoding.t =
    let open Data_encoding in
    mu "Tree.raw" (fun encoding ->
        let map_encoding =
          conv
            TzString.Map.bindings
            (fun bindings -> TzString.Map.of_seq (List.to_seq bindings))
            (list (tup2 string encoding))
        in
        union
          [
            case
              ~title:"tree"
              (Tag 0)
              map_encoding
              (function `Tree t -> Some t | `Value _ -> None)
              (fun t -> `Tree t);
            case
              ~title:"value"
              (Tag 1)
              bytes
              (function `Value v -> Some v | `Tree _ -> None)
              (fun v -> `Value v);
          ])

  type repo = Store.repo

  let make_repo =
    let prng_state = lazy (Random.State.make_self_init ()) in
    (* [irmin-pack] stores implicitly share instances according to a string
       argument (for persistent stores, this is the store's file path). To avoid
       having hidden global state, we generate a unique string each time. *)
    let random_store_name () =
      let prng_state = Lazy.force prng_state in
      String.init 64 (fun _ -> Char.chr (Random.State.int prng_state 256))
    in
    fun () -> Store.Repo.v @@ Irmin_pack.config @@ random_store_name ()

  let shallow repo kinded_hash =
    Store.Tree.shallow
      repo
      (match kinded_hash with
      | `Node hash -> `Node (Hash.of_context_hash hash)
      | `Contents hash -> `Contents (Hash.of_context_hash hash, ()))

  let list tree ?offset ?length key =
    Store.Tree.list ~cache:true tree ?offset ?length key

  let length tree key = Store.Tree.length ~cache:true tree key

  exception Context_dangling_hash of string

  exception Dangling_hash = Store.Private.Node.Val.Dangling_hash

  let find_tree tree key =
    Lwt.catch
      (fun () -> Store.Tree.find_tree tree key)
      (function
        | Dangling_hash {context; hash} ->
            let str =
              Fmt.str
                "%s encountered dangling hash %a"
                context
                (Irmin.Type.pp Hash.t)
                hash
            in
            raise (Context_dangling_hash str)
        | exn -> raise exn)

  let add_tree tree key value =
    Lwt.catch
      (fun () -> Store.Tree.add_tree tree key value)
      (function
        | Dangling_hash {context; hash} ->
            let str =
              Fmt.str
                "%s encountered dangling hash %a"
                context
                (Irmin.Type.pp Hash.t)
                hash
            in
            raise (Context_dangling_hash str)
        | exn -> raise exn)
end

type error += Unsupported_context_hash_version of Context_hash.Version.t

let () =
  register_error_kind
    `Permanent
    ~id:"context_hash.unsupported_version"
    ~title:"Unsupported context hash version"
    ~description:"Unsupported context hash version."
    ~pp:(fun ppf version ->
      Format.fprintf
        ppf
        "@[Context hash version %a is not supported.@,\
         You might need to update the shell.@]"
        Context_hash.Version.pp
        version)
    Data_encoding.(obj1 (req "version" Context_hash.Version.encoding))
    (function
      | Unsupported_context_hash_version version -> Some version | _ -> None)
    (fun version -> Unsupported_context_hash_version version)
