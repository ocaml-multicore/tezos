(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
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

(** Testing
    -------
    Component:    Protocol Cache
    Invocation:   dune build @src/lib_protocol_environment/runtest
    Dependencies: src/lib_protocol_environment/test/assert.ml
    Subject:      Low-level operations on protocol cache
*)

open Environment_cache
open Lib_test.Qcheck_helpers

(*

   Helpers

*)

let position_of_assoc ~equal k ks =
  let rec aux i = function
    | [] -> None
    | (k', _) :: ks -> if equal k k' then Some i else aux (i + 1) ks
  in
  aux 0 ks

let gen_layout = QCheck.(make Gen.(list small_int))

let low_size = 5_000

let high_size = 100_000

let low_init_entries = 100

let high_init_entries = 10_000

let entry_size = 10

let almost_full_cache cache ~cache_index =
  match
    (cache_size cache ~cache_index, cache_size_limit cache ~cache_index)
  with
  | (Some size, Some limit) -> size + entry_size >= limit
  | (_, _) -> assert false

let equal_identifiers k1 k2 = identifier_of_key k1 = identifier_of_key k2

let number_of_keys cache =
  let r = ref 0 in
  for cache_index = 0 to number_of_caches cache - 1 do
    match list_keys cache ~cache_index with
    | Some l -> r := !r + List.length l
    | None -> assert false
    (* because cache_index is valid. *)
  done ;
  !r

let gen_entries ?(high_init_entries = high_init_entries) ncaches =
  QCheck.Gen.(
    list_size
      (int_range low_init_entries high_init_entries)
      (pair (int_bound (ncaches - 1)) (pair string_printable small_int))
    >>= fun entries ->
    List.sort_uniq
      (fun (n1, (k1, _)) (n2, (k2, _)) ->
        let c = compare n1 n2 in
        if c = 0 then String.compare k1 k2 else c)
      entries
    |> List.map (fun (cache_index, (identifier, value)) ->
           let k = key_of_identifier ~cache_index identifier in
           (cache_index, identifier, k, value))
    |> return)

let insert_entries cache entries =
  List.fold_left
    (fun cache (_, _, k, v) -> update cache k (Some (v, entry_size)))
    cache
    entries

let gen_cache ?(high_init_entries = high_init_entries) () =
  QCheck.(
    Gen.(
      int_range 1 3 >>= fun ncaches ->
      let layout = generate ~n:ncaches (int_range low_size high_size) in
      let cache = from_layout layout in
      int_range 0 100 >>= fun k ->
      if k = 0 then return (layout, [], cache)
      else
        gen_entries ~high_init_entries ncaches >>= fun entries ->
        let cache = insert_entries cache entries in
        return (layout, entries, cache)))

let pp_option what fmt = function
  | None -> Format.fprintf fmt "None"
  | Some x -> Format.fprintf fmt "Some %a" what x

let pp_int fmt x = Format.fprintf fmt "%d" x

let pp_identifier fmt s = Format.fprintf fmt "%s" s

let pp_layout = Format.pp_print_list pp_int

(*

   Cache-level tests
   =================

   The following unit tests exercise the cache data structure
   implemented in {!Environment_cache}.

   These tests are independent from the storage.

*)

(*

   Unit tests for [uninitialised]

*)

let check_uninitialised_is_unusable =
  let cache_fun f cache = ignore (f cache) in
  let cache_funs =
    [
      cache_fun number_of_caches;
      cache_fun clear;
      cache_fun (future_cache_expectation ~time_in_blocks:0);
      cache_fun (sync ~cache_nonce:Bytes.empty);
      cache_fun (cache_size ~cache_index:0);
      cache_fun (list_keys ~cache_index:0);
    ]
  in
  QCheck.Test.make
    ~count:1
    ~name:"an uninitialised cache is unusable"
    QCheck.(make Gen.(pair (oneofl cache_funs) (pure uninitialised)))
    (fun (cache_fun, cache) ->
      try
        cache_fun cache ;
        false
      with _ -> true)

(*

   Unit tests for [from_layout]

*)

let valid_empty_subcaches layout =
  let cache = from_layout layout in
  let len = List.length layout in
  number_of_caches cache = len
  && Stdlib.List.for_all2
       (fun cache_index expected_size_limit ->
         qcheck_eq
           ~pp:(pp_option pp_int)
           (Some 0)
           (cache_size cache ~cache_index)
         && qcheck_eq
              ~pp:(pp_option pp_int)
              (Some expected_size_limit)
              (cache_size_limit cache ~cache_index))
       (0 -- (len - 1))
       layout

let check_from_layout_is_empty =
  QCheck.Test.make
    ~count:50
    ~name:"from_layout produces valid empty subcaches"
    gen_layout
    valid_empty_subcaches

let check_from_layout_with_negative_size =
  QCheck.Test.make
    ~count:10
    ~name:"from_layout fails on negative sizes"
    QCheck.Gen.(
      QCheck.make
        ( int_range 1 10 >>= fun n ->
          list_repeat n small_int >>= fun layout ->
          int_range 0 (List.length layout - 1) >>= fun idx ->
          int_range (-100) (-1) >>= fun neg_size ->
          return (layout, idx, neg_size) ))
    (fun (layout, idx, neg_size) ->
      let layout =
        List.mapi (fun i x -> if i = idx then neg_size else x) layout
      in
      try
        ignore (from_layout layout) ;
        false
      with _ -> true)

(*

   Unit tests for invalid cache indices

*)
let invalid_cache_indices layout =
  let cache = from_layout layout in
  let len = List.length layout in
  match cache_size cache ~cache_index:len with
  | None -> true
  | Some _ ->
      QCheck.Test.fail_report "Out of bound cache index should produce failures"

let check_invalid_cache_indices =
  QCheck.Test.make
    ~count:50
    ~name:"invalid cache indices produce failures"
    gen_layout
    invalid_cache_indices

(*

   Unit tests for [compatible_layout]

*)
let compatible_layout_validates_correctly layout =
  let cache = from_layout layout in
  compatible_layout cache layout

let check_compatible_layout_validates_correctly =
  QCheck.Test.make
    ~count:10
    ~name:"compatible_layout validates correctly"
    gen_layout
    compatible_layout_validates_correctly

let compatible_layout_invalidates_correctly (layout1, layout2) =
  let cache = from_layout layout1 in
  (not (compatible_layout cache layout2))
  || qcheck_eq ~pp:pp_layout layout1 layout2

let check_compatible_layout_invalidates_correctly =
  QCheck.Test.make
    ~count:10
    ~name:"compatible_layout invalidates correctly"
    (QCheck.pair gen_layout gen_layout)
    compatible_layout_invalidates_correctly

(*

   Unit tests for [clear]

*)
let clear_preserves_layout_and_removes_entries (layout, _, cache) =
  from_layout layout = clear cache

let check_clear_preserves_layout_and_removes_entries =
  QCheck.Test.make
    ~count:50
    ~name:"clear preserves layout and removes entries"
    (QCheck.make (gen_cache ()))
    clear_preserves_layout_and_removes_entries

(*

   Unit tests for [key_of_identifier]

*)
let key_of_identifier_assigns_given_identifier (cache_index, identifier) =
  qcheck_eq
    ~pp:pp_identifier
    identifier
    (identifier_of_key @@ key_of_identifier ~cache_index identifier)

let check_key_of_identifier_assigns_given_identifier =
  QCheck.Test.make
    ~count:50
    ~name:"key_of_identifier uses given identifier"
    QCheck.(pair small_int string)
    key_of_identifier_assigns_given_identifier

(*

   Unit tests for [find] and [lookup]

*)

(*

   Given a list of entries inserted in a cache, a suffix of these
   entries -- the ones fitting in the cache -- must still be in the
   cache.

   The prefix of this list corresponds to entries that has
   been removed by lack of space. They should not be in the cache.

*)
let inserted_entries_are_in get (_, entries, cache) =
  let (cache, _) = sync cache ~cache_nonce:Bytes.empty in
  let full_flags = Array.make (number_of_caches cache) false in
  let rec process cache' = function
    | [] -> true
    | (cache_index, i, k, v) :: entries -> (
        match get cache k with
        | Some v' ->
            if full_flags.(cache_index) then
              QCheck.Test.fail_reportf
                "key %s should be removed, get %d instead"
                i
                v'
            else
              let r = v = v' in
              if not r then
                QCheck.Test.fail_reportf
                  "for key %s, expecting %d, get %d"
                  i
                  v
                  v'
              else
                let cache' = update cache' k (Some (v, entry_size)) in
                process cache' entries
        | None ->
            if full_flags.(cache_index) then process cache' entries
            else if almost_full_cache cache' ~cache_index then (
              full_flags.(cache_index) <- true ;
              process cache' entries)
            else
              QCheck.Test.fail_reportf
                "there is no value for key %s, expecting %d"
                i
                v)
  in
  process (clear cache) (List.rev entries)

let check_inserted_entries_are_in_order_with_find =
  QCheck.Test.make
    ~count:100
    ~name:"inserted entries are in the cache (with find)"
    (QCheck.make (gen_cache ()))
    (inserted_entries_are_in find)

let check_inserted_entries_are_in_order_with_lookup =
  QCheck.Test.make
    ~count:100
    ~name:"inserted entries are in the cache (with lookup)"
    (QCheck.make (gen_cache ()))
    (inserted_entries_are_in (fun cache k -> lookup cache k |> Option.map fst))

(*

   Unit tests for [update]

*)

let update_changes_cached_value (_, entries, cache) =
  let cache =
    List.fold_left
      (fun cache (_, _, k, v) ->
        match find cache k with
        | None -> cache
        | Some _ -> update cache k (Some (v + 1, entry_size)))
      cache
      entries
  in
  List.for_all
    (fun (_, i, k, v) ->
      match find cache k with
      | None -> true
      | Some v' ->
          if v' <> v + 1 then
            QCheck.Test.fail_reportf
              "For key %s, got %d, expecting %d\n"
              i
              v'
              (v + 1)
          else true)
    entries

let check_update_changes_cached_value =
  QCheck.Test.make
    ~count:100
    ~name:"update with some value changes mapping"
    (QCheck.make (gen_cache ()))
    update_changes_cached_value

let update_removes_cached_value (_, entries, cache) =
  let selected_for_removal v = v mod 2 = 0 in
  let cache' =
    List.fold_left
      (fun cache (_, _, k, v) ->
        match find cache k with
        | None -> cache
        | Some _ ->
            if selected_for_removal v then update cache k None else cache)
      cache
      entries
  in
  List.for_all
    (fun (_, i, k, _) ->
      match (find cache' k, find cache k) with
      | (None, None) -> true
      | (Some v, _) ->
          if selected_for_removal v then
            QCheck.Test.fail_reportf
              "For key %s, got %d, expecting absence\n"
              i
              v
          else true
      | (None, Some v) ->
          if not (selected_for_removal v) then
            QCheck.Test.fail_reportf
              "For key %s, expecting %d, got absence\n"
              i
              v
          else true)
    entries

let check_update_removes_cached_value =
  QCheck.Test.make
    ~count:100
    ~name:"update with none removes mapping"
    (QCheck.make (gen_cache ()))
    update_removes_cached_value

(*

   Unit tests for [future_cache_expectation]

*)
let future_cache_expectation_does_not_change_not_full_cache
    (time_in_blocks, (_, _, cache)) =
  let cache =
    Utils.fold_n_times
      10
      (fun cache -> fst (sync cache ~cache_nonce:Bytes.empty))
      cache
  in
  future_cache_expectation ~time_in_blocks cache = cache

let check_future_cache_expectation_does_not_change_not_full_cache =
  QCheck.Test.make
    ~count:100
    ~name:"future_cache_expectation does not change not full cache"
    QCheck.(pair small_int (QCheck.make (gen_cache ())))
    future_cache_expectation_does_not_change_not_full_cache

let future_cache_expectation_repeats_the_past
    (time_in_blocks, (nb_removals, (_, entries, cache))) =
  if number_of_caches cache > 1 then true
  else
    let lr_entries = List.rev entries in
    let (cache, _) = sync cache ~cache_nonce:Bytes.empty in
    let remove_some_entries n (cache, lr_entries) =
      Utils.fold_n_times
        n
        (fun (cache, lr_entries) ->
          let (least_recent_entries, lr_entries) =
            List.split_n nb_removals lr_entries
          in
          let cache =
            List.fold_left
              (fun cache (_, _, k, _) -> update cache k None)
              cache
              least_recent_entries
          in
          (fst (sync cache ~cache_nonce:Bytes.empty), lr_entries))
        (cache, lr_entries)
    in
    let (cache, lr_entries) = remove_some_entries 10 (cache, lr_entries) in
    let predicted_cache = future_cache_expectation ~time_in_blocks cache in
    let predicted_size = number_of_keys predicted_cache in
    let (cache', _) = remove_some_entries time_in_blocks (cache, lr_entries) in
    let actual_size = number_of_keys cache' in
    if predicted_size - actual_size > actual_size / 3 then
      QCheck.Test.fail_reportf
        "Future cache expectation is not precise enough, predicted %d, got %d\n"
        predicted_size
        actual_size
    else true

let check_future_cache_expectation_repeats_the_past =
  QCheck.Test.make
    ~count:50
    ~name:"future_cache_expectation repeats the past"
    QCheck.(pair small_int (pair small_int (QCheck.make (gen_cache ()))))
    future_cache_expectation_repeats_the_past

(*

   Unit tests for [sync]

*)
let after_sync_cache_nonce_are_set (entries, cache, fresh_entries) =
  let if_in_then_has_cache_nonce cache entries nonce =
    List.for_all
      (fun (_, _, k, _) ->
        match lookup cache k with
        | None -> true
        | Some (_, metadata) -> Bytes.equal metadata.cache_nonce nonce)
      entries
  in
  let nonce1 = Bytes.of_string "init" in
  let nonce2 = Bytes.of_string "new" in
  let (cache, _) = sync cache ~cache_nonce:nonce1 in
  if_in_then_has_cache_nonce cache entries nonce1
  &&
  let cache = insert_entries cache fresh_entries in
  let (cache, _) = sync cache ~cache_nonce:nonce2 in
  if_in_then_has_cache_nonce cache fresh_entries nonce2

let check_after_sync_cache_nonce_are_set =
  QCheck.Test.make
    ~count:50
    ~name:"after sync, cache nonce are set"
    QCheck.(
      make
        Gen.(
          gen_cache () >>= fun (_, entries, cache) ->
          gen_entries (number_of_caches cache) >>= fun fresh_entries ->
          return (entries, cache, fresh_entries)))
    after_sync_cache_nonce_are_set

(*

   Unit tests for [list_keys]

*)
let list_keys_returns_entries (_, entries, cache) =
  List.for_all
    (fun cache_index ->
      match list_keys cache ~cache_index with
      | None -> assert false
      | Some ks ->
          let entries =
            List.filter (fun (c, _, _, _) -> cache_index = c) entries
          in
          List.for_all
            (fun (_, _, k, _) ->
              match lookup cache k with
              | None -> true
              | Some (_, metadata) -> (
                  match List.assoc ~equal:equal_identifiers k ks with
                  | None -> false
                  | Some size -> metadata.size = size))
            entries
          && List.for_all
               (fun (k, size) ->
                 match lookup cache k with
                 | None -> false
                 | Some (_, metadata) -> metadata.size = size)
               ks)
    (0 -- (number_of_caches cache - 1))

let check_list_keys_returns_entries =
  QCheck.Test.make
    ~count:100
    ~name:"list keys returns all entries"
    (QCheck.make (gen_cache ()))
    list_keys_returns_entries

(*

   Unit tests for [key_rank]

*)

let key_rank_returns_valid_rank (_, entries, cache) =
  let (cache, _) = sync cache ~cache_nonce:Bytes.empty in
  List.for_all
    (fun cache_index ->
      match list_keys cache ~cache_index with
      | None -> assert false
      | Some ks ->
          let entries =
            List.filter (fun (c, _, _, _) -> cache_index = c) entries
          in
          List.for_all
            (fun (_, _, k, _) ->
              match
                ( key_rank cache k,
                  position_of_assoc ~equal:equal_identifiers k ks )
              with
              | (None, None) -> true
              | (Some rank, Some pos) -> rank = pos
              | (_, _) -> false)
            entries)
    (0 -- (number_of_caches cache - 1))

let check_key_rank_returns_valid_rank =
  QCheck.Test.make
    ~count:25
    ~name:"key rank returns valid rank"
    (QCheck.make (gen_cache ()))
    key_rank_returns_valid_rank

(*

   Unit tests for [from_cache]

*)
let same_cache_keys cache cache' =
  number_of_caches cache = number_of_caches cache'
  && List.for_all
       (fun cache_index ->
         list_keys cache ~cache_index = list_keys cache' ~cache_index)
       (0 -- (number_of_caches cache - 1))

let from_cache_with_same_domain_copies (_, _, cache) =
  let (cache, domain) = sync cache ~cache_nonce:Bytes.empty in
  from_cache cache domain ~value_of_key:(fun _ -> assert false)
  >>=? fun cache' -> return (same_cache_keys cache cache')

let check_from_cache_with_same_domain_copies =
  QCheck.Test.make
    ~count:25
    ~name:"from_cache with same domain copies"
    (QCheck.make (gen_cache ()))
    (fun x ->
      Lwt_main.run (from_cache_with_same_domain_copies x) |> function
      | Ok b -> b
      | _ -> QCheck.Test.fail_report "Unexpected error while testing from_cache")

(*

   Context-level tests
   ===================

   The following tests exercise the cache integration in the storage
   implemented in {!Environment_context}.

*)
open Environment_context

type Context.cache_value += Int of int

let load_cache_correctly_restores_cache_in_memory builder mode
    (layout, entries, _) =
  let entries =
    List.map
      (fun (cache_index, identifier, _, value) ->
        (Context.Cache.key_of_identifier ~cache_index identifier, value))
      entries
  in
  let ctxt = Memory_context.empty in
  Context.Cache.set_cache_layout ctxt layout >>= fun ctxt ->
  let ctxt =
    List.fold_left
      (fun ctxt (key, value) ->
        Context.Cache.update ctxt key (Some (Int value, entry_size)))
      ctxt
      entries
  in
  Context.Cache.sync ctxt ~cache_nonce:Bytes.empty >>= fun ctxt0 ->
  (* We want to avoid a cache hit in the cache of caches. *)
  let block = Block_hash.hash_string [string_of_int (Random.bits ())] in
  let ctxt0 = Context.Cache.clear ctxt0 in
  Context.load_cache block ctxt0 mode (builder entries) >>=? fun ctxt1 ->
  (* We force the execution of [value_of_key] even in Lazy mode by
     performing lookups in the cache. *)
  List.iter_es
    (fun (key, value) ->
      Lwt.catch
        (fun () ->
          Context.Cache.find ctxt1 key >>= function
          | None -> QCheck.Test.fail_report "Unexpected missing key"
          | Some (Int value') ->
              if value <> value' then
                QCheck.Test.fail_report "Invalid fetched value from cache"
              else return_unit
          | Some _ -> QCheck.Test.fail_report "Unexpected value type in cache")
        (fun _ -> failwith "Lookup raised an exception"))
    entries
  >>=? fun () -> Context.Cache.Internal_for_tests.same_cache_domains ctxt0 ctxt1

let load_cache_correctly_restores_cache_in_memory_normal_case =
  let builder entries key =
    let value = Stdlib.List.assoc key entries in
    return (Int value)
  in
  load_cache_correctly_restores_cache_in_memory builder

let check_load_cache_correctly_restores_cache_in_memory mode_label mode =
  QCheck.Test.make
    ~count:50
    ~name:("load_cache correctly restores in-memory caches " ^ mode_label)
    (QCheck.make (gen_cache ~high_init_entries:low_init_entries ()))
    (fun x ->
      Lwt_main.run
        (load_cache_correctly_restores_cache_in_memory_normal_case mode x)
      |> function
      | Ok b -> b
      | _ ->
          QCheck.Test.fail_report
            ("Unexpected error while testing from_cache " ^ mode_label))

let load_cache_correctly_restores_cache_in_memory_fatal_error_case =
  let builder _entries _key = failwith "This builder fails." in
  load_cache_correctly_restores_cache_in_memory builder

let check_load_cache_fails_if_builder_fails mode_label mode =
  QCheck.Test.make
    ~count:1
    ~name:("load_cache fails if builder fails " ^ mode_label)
    (QCheck.make (gen_cache ~high_init_entries:low_init_entries ()))
    (fun x ->
      Lwt_main.run
        (load_cache_correctly_restores_cache_in_memory_fatal_error_case mode x)
      |> function
      | Ok _ ->
          QCheck.Test.fail_report
            ("Unexpected success while testing from_cache " ^ mode_label)
      | _ -> true)

let qtests =
  [
    check_uninitialised_is_unusable;
    check_from_layout_is_empty;
    check_from_layout_with_negative_size;
    check_invalid_cache_indices;
    check_compatible_layout_validates_correctly;
    check_compatible_layout_invalidates_correctly;
    check_clear_preserves_layout_and_removes_entries;
    check_key_of_identifier_assigns_given_identifier;
    check_inserted_entries_are_in_order_with_find;
    check_inserted_entries_are_in_order_with_lookup;
    check_update_changes_cached_value;
    check_update_removes_cached_value;
    check_future_cache_expectation_does_not_change_not_full_cache;
    check_future_cache_expectation_repeats_the_past;
    check_after_sync_cache_nonce_are_set;
    check_list_keys_returns_entries;
    check_key_rank_returns_valid_rank;
    check_from_cache_with_same_domain_copies;
    check_load_cache_correctly_restores_cache_in_memory "(`Load mode)" `Load;
    check_load_cache_correctly_restores_cache_in_memory "(`Lazy mode)" `Lazy;
    check_load_cache_fails_if_builder_fails "(`Load mode)" `Load;
    check_load_cache_fails_if_builder_fails "(`Lazy mode)" `Lazy;
  ]

let tests =
  let to_alcotest_lwt test =
    QCheck_alcotest.to_alcotest test |> fun (name, speed, f) ->
    (name, speed, fun () -> Lwt.return (f ()))
  in
  List.map to_alcotest_lwt qtests
