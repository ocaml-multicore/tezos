(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020-2021 Nomadic Labs <contact@nomadic-labs.com>           *)
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

open Protocol

module Common = struct
  let memo_size_of_int i =
    match Alpha_context.Sapling.Memo_size.parse_z @@ Z.of_int i with
    | Ok memo_size -> memo_size
    | Error _ -> assert false

  let int_of_memo_size ms =
    Alpha_context.Sapling.Memo_size.unparse_to_z ms |> Z.to_int

  let wrap e = Lwt.return (Environment.wrap_tzresult e)

  let assert_true res = res >|=? fun res -> assert res

  let assert_false res = res >|=? fun res -> assert (not res)

  let assert_some res = res >|=? function Some s -> s | None -> assert false

  let assert_none res =
    res >>=? function Some _ -> assert false | None -> return_unit

  let assert_error res =
    res >>= function Ok _ -> assert false | Error _ -> return_unit

  let print ?(prefix = "") e v =
    Printf.printf
      "%s: %s\n"
      prefix
      Data_encoding.(Json.to_string (Json.construct e v))

  let to_hex x encoding =
    Hex.show (Hex.of_bytes Data_encoding.Binary.(to_bytes_exn encoding x))

  let randomized_byte ?pos v encoding =
    let bytes = Data_encoding.Binary.(to_bytes_exn encoding v) in
    let rec aux () =
      let random_char = Random.int 256 |> char_of_int in
      let pos = Option.value ~default:(Random.int (Bytes.length bytes)) pos in
      if random_char = Bytes.get bytes pos then aux ()
      else Bytes.set bytes pos random_char
    in
    aux () ;
    Data_encoding.Binary.(of_bytes_exn encoding bytes)

  type wallet = {
    sk : Tezos_sapling.Core.Wallet.Spending_key.t;
    vk : Tezos_sapling.Core.Wallet.Viewing_key.t;
  }

  let wallet_gen () =
    let sk =
      Tezos_sapling.Core.Wallet.Spending_key.of_seed
        (Tezos_crypto.Hacl.Rand.gen 32)
    in
    let vk = Tezos_sapling.Core.Wallet.Viewing_key.of_sk sk in
    {sk; vk}

  let gen_addr n vk =
    let rec aux n index res =
      if Compare.Int.( <= ) n 0 then res
      else
        let (new_index, new_addr) =
          Tezos_sapling.Core.Client.Viewing_key.new_address vk index
        in
        aux (n - 1) new_index (new_addr :: res)
    in
    aux n Tezos_sapling.Core.Client.Viewing_key.default_index []

  let gen_nf () =
    let {vk; _} = wallet_gen () in
    let addr =
      snd
      @@ Tezos_sapling.Core.Wallet.Viewing_key.(new_address vk default_index)
    in
    let amount = 10L in
    let rcm = Tezos_sapling.Core.Client.Rcm.random () in
    let position = 10L in
    Tezos_sapling.Core.Client.Nullifier.compute addr vk ~amount rcm ~position

  let gen_cm_cipher ~memo_size () =
    let open Tezos_sapling.Core.Client in
    let {vk; _} = wallet_gen () in
    let addr =
      snd
      @@ Tezos_sapling.Core.Wallet.Viewing_key.(new_address vk default_index)
    in
    let amount = 10L in
    let rcm = Tezos_sapling.Core.Client.Rcm.random () in
    let cm = Commitment.compute addr ~amount rcm in
    let cipher =
      let payload_enc =
        Data_encoding.Binary.to_bytes_exn
          Data_encoding.bytes
          (Hacl.Rand.gen (memo_size + 4 + 16 + 11 + 32 + 8))
      in
      Data_encoding.Binary.of_bytes_exn
        Ciphertext.encoding
        (Bytes.concat
           Bytes.empty
           [
             Bytes.create (32 + 32);
             payload_enc;
             Bytes.create (24 + 64 + 16 + 24);
           ])
    in
    (cm, cipher)

  (* rebuilds from empty at each call *)
  let client_state_of_diff ~memo_size (root, diff) =
    let open Alpha_context.Sapling in
    let cs =
      Tezos_sapling.Storage.add
        (Tezos_sapling.Storage.empty ~memo_size)
        diff.commitments_and_ciphertexts
    in
    assert (Tezos_sapling.Storage.get_root cs = root) ;
    List.fold_left
      (fun s nf -> Tezos_sapling.Storage.add_nullifier s nf)
      cs
      diff.nullifiers
end

module Alpha_context_helpers = struct
  include Common

  let init () =
    Context.init 1 >>=? fun (b, _) ->
    Alpha_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
    (* ~fitness:b.header.shell.fitness *)
    >>= wrap
    >|=? fun (ctxt, _, _) -> ctxt

  (* takes a state obtained from Sapling.empty_state or Sapling.state_from_id and
     passed through Sapling.verify_update *)
  let finalize ctx =
    let open Alpha_context in
    let open Sapling in
    function
    | {id = None; diff; memo_size} ->
        Sapling.fresh ~temporary:false ctx >>= wrap >>=? fun (ctx, id) ->
        let init = Lazy_storage.Alloc {memo_size} in
        let lazy_storage_diff = Lazy_storage.Update {init; updates = diff} in
        let diffs = [Lazy_storage.make Sapling_state id lazy_storage_diff] in
        Lazy_storage.apply ctx diffs >>= wrap >|=? fun (ctx, _added_size) ->
        (ctx, id)
    | {id = Some id; diff; _} ->
        let init = Lazy_storage.Existing in
        let lazy_storage_diff = Lazy_storage.Update {init; updates = diff} in
        let diffs = [Lazy_storage.make Sapling_state id lazy_storage_diff] in
        Lazy_storage.apply ctx diffs >>= wrap >|=? fun (ctx, _added_size) ->
        (ctx, id)

  (* disk only version *)
  let verify_update ctx ?memo_size ?id vt =
    let anti_replay = "anti-replay" in
    (match id with
    | None ->
        (match memo_size with
        | None -> (
            match vt.Environment.Sapling.UTXO.outputs with
            | [] -> failwith "Can't infer memo_size from empty outputs"
            | output :: _ ->
                return
                @@ Environment.Sapling.Ciphertext.get_memo_size
                     output.ciphertext)
        | Some memo_size -> return memo_size)
        >>=? fun memo_size ->
        let memo_size = memo_size_of_int memo_size in
        let vs = Alpha_context.Sapling.empty_state ~memo_size () in
        return (vs, ctx)
    | Some id ->
        (* Storage.Sapling.Roots.get (Obj.magic ctx, id) 0l *)
        (*       >>= wrap *)
        (*       >>=? fun (_, root) -> *)
        (*       print ~prefix:"verify: " Environment.Sapling.Hash.encoding root ; *)
        Alpha_context.Sapling.state_from_id ctx id >>= wrap)
    >>=? fun (vs, ctx) ->
    Alpha_context.Sapling.verify_update ctx vs vt anti_replay >>= wrap
    >>=? fun (ctx, res) ->
    match res with
    | None -> return_none
    | Some (_balance, vs) ->
        finalize ctx vs >>=? fun (ctx, id) ->
        let fake_fitness =
          Alpha_context.(
            let level =
              match Raw_level.of_int32 0l with
              | Error _ -> assert false
              | Ok l -> l
            in
            Fitness.create_without_locked_round
              ~level
              ~predecessor_round:Round.zero
              ~round:Round.zero
            |> Fitness.to_raw)
        in
        let ectx = (Alpha_context.finalize ctx fake_fitness).context in
        (* bump the level *)
        Alpha_context.prepare
          ectx
          ~level:
            Alpha_context.(
              Raw_level.to_int32 Level.((succ ctx (current ctx)).level))
          ~predecessor_timestamp:(Time.Protocol.of_seconds Int64.zero)
          ~timestamp:(Time.Protocol.of_seconds Int64.zero)
        >>= wrap
        >|=? fun (ctx, _, _) -> Some (ctx, id)

  let transfer_inputs_outputs w cs is =
    (* Tezos_sapling.Storage.size cs *)
    (*   |> fun (a, b) -> *)
    (*   Printf.printf "%Ld %Ld" a b ; *)
    let inputs =
      List.map
        (fun i ->
          Tezos_sapling.Forge.Input.get cs (Int64.of_int i) w.vk
          |> WithExceptions.Option.get ~loc:__LOC__
          |> snd)
        is
    in
    let addr =
      snd
      @@ Tezos_sapling.Core.Wallet.Viewing_key.(new_address w.vk default_index)
    in
    let memo_size = Tezos_sapling.Storage.get_memo_size cs in
    let o =
      Tezos_sapling.Forge.make_output addr 1000000L (Bytes.create memo_size)
    in
    (inputs, [o])

  let transfer w cs is =
    let anti_replay = "anti-replay" in
    let (ins, outs) = transfer_inputs_outputs w cs is in
    (* change the wallet of this last line *)
    Tezos_sapling.Forge.forge_transaction ins outs w.sk anti_replay cs

  let client_state_alpha ctx id =
    Alpha_context.Sapling.get_diff ctx id () >>= wrap >>=? fun diff ->
    Alpha_context.Sapling.state_from_id ctx id >>= wrap
    >|=? fun ({memo_size; _}, _ctx) ->
    let memo_size = int_of_memo_size memo_size in
    client_state_of_diff ~memo_size diff
end

(*
  Interpreter level
*)

module Interpreter_helpers = struct
  include Common
  include Contract_helpers

  (** Returns a block in which the contract is originated.
      Also returns the associated anti-replay string and KT1 address. *)
  let originate_contract file storage src b baker =
    originate_contract file storage src b baker >|=? fun (dst, b) ->
    let anti_replay =
      Format.asprintf
        "%a%a"
        Alpha_context.Contract.pp
        dst
        Chain_id.pp
        Chain_id.zero
    in
    (dst, b, anti_replay)

  let hex_shield ~memo_size wallet anti_replay =
    let ps = Tezos_sapling.Storage.empty ~memo_size in
    let addr =
      snd
      @@ Tezos_sapling.Core.Wallet.Viewing_key.(
           new_address wallet.vk default_index)
    in
    let output =
      Tezos_sapling.Forge.make_output addr 15L (Bytes.create memo_size)
    in
    let pt =
      Tezos_sapling.Forge.forge_transaction [] [output] wallet.sk anti_replay ps
    in
    let hex_string =
      "0x"
      ^ Hex.show
          (Hex.of_bytes
             Data_encoding.Binary.(
               to_bytes_exn
                 Tezos_sapling.Core.Client.UTXO.transaction_encoding
                 pt))
    in
    hex_string

  (* Make a transaction and sync a local client state. [to_exclude] is the list
     of addresses that cannot bake the block*)
  let transac_and_sync ~memo_size block parameters amount src dst baker =
    let amount_tez =
      Test_tez.(Alpha_context.Tez.one_mutez *! Int64.of_int amount)
    in
    let fee = Test_tez.of_int 10 in
    Op.transaction ~fee (B block) src dst amount_tez ~parameters
    >>=? fun operation ->
    Incremental.begin_construction ~policy:Block.(By_account baker) block
    >>=? fun incr ->
    Incremental.add_operation incr operation >>=? fun incr ->
    Incremental.finalize_block incr >>=? fun block ->
    Alpha_services.Contract.single_sapling_get_diff
      Block.rpc_ctxt
      block
      dst
      ~offset_commitment:0L
      ~offset_nullifier:0L
      ()
    >|=? fun diff ->
    let state = client_state_of_diff ~memo_size diff in
    (block, state)

  (* Returns a list of printed shield transactions and their total amount. *)
  let shield ~memo_size sk number_transac vk printer anti_replay =
    let state = Tezos_sapling.Storage.empty ~memo_size in
    let rec aux number_transac number_outputs index amount_output total res =
      if Compare.Int.(number_transac <= 0) then (res, total)
      else
        let (new_index, new_addr) =
          Tezos_sapling.Core.Wallet.Viewing_key.(new_address vk index)
        in
        let outputs =
          List.init ~when_negative_length:() number_outputs (fun _ ->
              Tezos_sapling.Forge.make_output
                new_addr
                amount_output
                (Bytes.create memo_size))
          |> function
          | Error () -> assert false (* conditional above guards against this *)
          | Ok outputs -> outputs
        in
        let tr_hex =
          to_hex
            (Tezos_sapling.Forge.forge_transaction
               ~number_dummy_inputs:0
               ~number_dummy_outputs:0
               []
               outputs
               sk
               anti_replay
               state)
            Tezos_sapling.Core.Client.UTXO.transaction_encoding
        in
        aux
          (number_transac - 1)
          (number_outputs + 1)
          new_index
          (Int64.add 20L amount_output)
          (total + (number_outputs * Int64.to_int amount_output))
          (printer tr_hex :: res)
    in
    aux
      number_transac
      2
      Tezos_sapling.Core.Wallet.Viewing_key.default_index
      20L
      0
      []

  (* This fails if the operation is not correct wrt the block *)
  let next_block block operation =
    Incremental.begin_construction block >>=? fun incr ->
    Incremental.add_operation incr operation >>=? fun incr ->
    Incremental.finalize_block incr
end
