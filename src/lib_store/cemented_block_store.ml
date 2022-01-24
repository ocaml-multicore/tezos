(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

open Store_errors

(* Cemented files overlay:

   | <n> x <offset (4 bytes)> | <n> x <blocks> |

   <offset> is an absolute offset in the file.
   <blocks> are prefixed by 4 bytes of length
*)
(* On-disk index of block's hashes to level *)
module Cemented_block_level_index =
  Index_unix.Make (Block_key) (Block_level) (Index.Cache.Unbounded)

(* On-disk index of block's level to hash *)
module Cemented_block_hash_index =
  Index_unix.Make (Block_level) (Block_key) (Index.Cache.Unbounded)

type cemented_metadata_file = {
  start_level : int32;
  end_level : int32;
  metadata_file : [`Cemented_blocks_metadata] Naming.file;
}

type cemented_blocks_file = {
  start_level : int32;
  end_level : int32;
  file : [`Cemented_blocks_file] Naming.file;
}

type t = {
  cemented_blocks_dir : [`Cemented_blocks_dir] Naming.directory;
  cemented_block_level_index : Cemented_block_level_index.t;
  cemented_block_hash_index : Cemented_block_hash_index.t;
  mutable cemented_blocks_files : cemented_blocks_file array option;
}

let cemented_blocks_files {cemented_blocks_files; _} = cemented_blocks_files

let cemented_blocks_file_length {start_level; end_level; _} =
  (* nb blocks : (end_level - start_level) + 1 *)
  Int32.(succ (sub end_level start_level))

let cemented_block_level_index {cemented_block_level_index; _} =
  cemented_block_level_index

let cemented_block_hash_index {cemented_block_hash_index; _} =
  cemented_block_hash_index

(* The log_size corresponds to the maximum size of the memory zone
   allocated in memory before flushing it onto the disk. It is
   basically a cache which is use for the index. The cache size is
   `log_size * log_entry` where a `log_entry` is roughly 56 bytes. *)
let default_index_log_size = 10_000

let default_compression_level = 9

let create ~log_size cemented_blocks_dir =
  protect (fun () ->
      let cemented_blocks_dir_path = Naming.dir_path cemented_blocks_dir in
      let cemented_blocks_metadata_dir =
        cemented_blocks_dir |> Naming.cemented_blocks_metadata_dir
      in
      let cemented_blocks_metadata_dir_path =
        Naming.dir_path cemented_blocks_metadata_dir
      in
      Lwt.catch
        (fun () ->
          Lwt_utils_unix.create_dir cemented_blocks_dir_path >>= fun () ->
          Lwt_utils_unix.create_dir cemented_blocks_metadata_dir_path
          >>= fun () -> return_unit)
        (function
          | Failure s when s = "Not a directory" ->
              fail
                (Store_errors.Failed_to_init_cemented_block_store
                   cemented_blocks_dir_path)
          | e -> Lwt.fail e)
      >>=? fun () ->
      let cemented_block_level_index =
        Cemented_block_level_index.v
          ~readonly:false
          ~log_size
          (cemented_blocks_dir |> Naming.cemented_blocks_level_index_dir
         |> Naming.dir_path)
      in
      let cemented_block_hash_index =
        Cemented_block_hash_index.v
          ~readonly:false
          ~log_size
          (cemented_blocks_dir |> Naming.cemented_blocks_hash_index_dir
         |> Naming.dir_path)
      in
      (* Empty table at first *)
      let cemented_blocks_files = None in
      let cemented_store =
        {
          cemented_blocks_dir;
          cemented_block_level_index;
          cemented_block_hash_index;
          cemented_blocks_files;
        }
      in
      return cemented_store)

let compare_cemented_files {start_level; _} {start_level = start_level'; _} =
  Compare.Int32.compare start_level start_level'

let compare_cemented_metadata ({start_level; _} : cemented_metadata_file)
    ({start_level = start_level'; _} : cemented_metadata_file) =
  Compare.Int32.compare start_level start_level'

let load_table cemented_blocks_dir =
  protect (fun () ->
      let cemented_blocks_dir_path = Naming.dir_path cemented_blocks_dir in
      Lwt_unix.opendir cemented_blocks_dir_path >>= fun dir_handle ->
      let rec loop acc =
        Lwt.catch
          (fun () -> Lwt_unix.readdir dir_handle >>= Lwt.return_some)
          (function End_of_file -> Lwt.return_none | exn -> raise exn)
        >>= function
        | Some filename -> (
            let levels = String.split_on_char '_' filename in
            match levels with
            | [start_level; end_level] -> (
                let start_level_opt = Int32.of_string_opt start_level in
                let end_level_opt = Int32.of_string_opt end_level in
                match (start_level_opt, end_level_opt) with
                | (Some start_level, Some end_level) ->
                    let file =
                      Naming.cemented_blocks_file
                        cemented_blocks_dir
                        ~start_level
                        ~end_level
                    in
                    loop ({start_level; end_level; file} :: acc)
                | _ -> loop acc)
            | _ -> loop acc)
        | None -> Lwt.return acc
      in
      Lwt.finalize (fun () -> loop []) (fun () -> Lwt_unix.closedir dir_handle)
      >>= function
      | [] -> return_none
      | cemented_files_list ->
          let cemented_files_array = Array.of_list cemented_files_list in
          Array.sort compare_cemented_files cemented_files_array ;
          return_some cemented_files_array)

let load_metadata_table cemented_blocks_dir =
  protect (fun () ->
      let cemented_metadata_dir =
        Naming.cemented_blocks_metadata_dir cemented_blocks_dir
      in
      Lwt_unix.opendir (Naming.dir_path cemented_metadata_dir)
      >>= fun dir_handle ->
      let rec loop acc =
        Lwt.catch
          (fun () -> Lwt_unix.readdir dir_handle >>= Lwt.return_some)
          (function End_of_file -> Lwt.return_none | exn -> raise exn)
        >>= function
        | Some filename -> (
            let levels =
              String.split_on_char '_' (Filename.remove_extension filename)
            in
            match levels with
            | [start_level; end_level] -> (
                let start_level_opt = Int32.of_string_opt start_level in
                let end_level_opt = Int32.of_string_opt end_level in
                match (start_level_opt, end_level_opt) with
                | (Some start_level, Some end_level) ->
                    let file =
                      Naming.cemented_blocks_file
                        cemented_blocks_dir
                        ~start_level
                        ~end_level
                    in
                    let metadata_file =
                      Naming.cemented_blocks_metadata_file
                        cemented_metadata_dir
                        file
                    in
                    loop ({start_level; end_level; metadata_file} :: acc)
                | _ -> loop acc)
            | _ -> loop acc)
        | None -> Lwt.return acc
      in
      Lwt.finalize (fun () -> loop []) (fun () -> Lwt_unix.closedir dir_handle)
      >>= function
      | [] -> return_none
      | cemented_files_list ->
          let cemented_files_array = Array.of_list cemented_files_list in
          Array.sort compare_cemented_metadata cemented_files_array ;
          return_some cemented_files_array)

let load ~readonly ~log_size cemented_blocks_dir =
  let cemented_block_level_index =
    Cemented_block_level_index.v
      ~readonly
      ~log_size
      (cemented_blocks_dir |> Naming.cemented_blocks_level_index_dir
     |> Naming.dir_path)
  in
  let cemented_block_hash_index =
    Cemented_block_hash_index.v
      ~readonly
      ~log_size
      (cemented_blocks_dir |> Naming.cemented_blocks_hash_index_dir
     |> Naming.dir_path)
  in
  load_table cemented_blocks_dir >>=? fun cemented_blocks_files ->
  let cemented_store =
    {
      cemented_blocks_dir;
      cemented_block_level_index;
      cemented_block_hash_index;
      cemented_blocks_files;
    }
  in
  return cemented_store

let init ?(log_size = default_index_log_size) chain_dir ~readonly =
  let cemented_blocks_dir = Naming.cemented_blocks_dir chain_dir in
  let cemented_blocks_dir_path = Naming.dir_path cemented_blocks_dir in
  Lwt_unix.file_exists cemented_blocks_dir_path >>= function
  | true ->
      Lwt_utils_unix.is_directory cemented_blocks_dir_path
      >>= fun is_directory ->
      fail_unless
        is_directory
        (Failed_to_init_cemented_block_store cemented_blocks_dir_path)
      >>=? fun () -> load ~readonly ~log_size cemented_blocks_dir
  | false -> create ~log_size cemented_blocks_dir

let close cemented_store =
  (try
     Cemented_block_level_index.close cemented_store.cemented_block_level_index
   with Index.Closed -> ()) ;
  try Cemented_block_hash_index.close cemented_store.cemented_block_hash_index
  with Index.Closed -> ()

let offset_length = 4 (* file offset *)

let offset_encoding = Data_encoding.int31

let find_block_file cemented_store block_level =
  try
    if Compare.Int32.(block_level < 0l) then None
    else
      match cemented_store.cemented_blocks_files with
      | None -> None
      | Some cemented_blocks_files ->
          let length = Array.length cemented_blocks_files in
          let last_interval =
            cemented_blocks_file_length cemented_blocks_files.(length - 1)
          in
          (* Pivot heuristic: in the main chain, the first cycle is
             [0_1]. Then, the second cycle is [2_4097]. *)
          let heuristic_initial_pivot =
            match block_level with
            | 0l | 1l -> 0
            | _ ->
                Compare.Int.min
                  (length - 1)
                  (1 + Int32.(to_int (div (sub block_level 2l) last_interval)))
          in
          (* Dichotomic search *)
          let rec loop (inf, sup) pivot =
            if pivot < inf || pivot > sup || inf > sup then None
            else
              let ({start_level; end_level; _} as res) =
                cemented_blocks_files.(pivot)
              in
              if
                Compare.Int32.(
                  block_level >= start_level && block_level <= end_level)
              then (* Found *)
                Some res
              else if Compare.Int32.(block_level > end_level) then
                (* Making sure the pivot is strictly increasing *)
                let new_pivot = pivot + max 1 ((sup - pivot) / 2) in
                loop (pivot, sup) new_pivot
              else
                (* Making sure the pivot is strictly decreasing *)
                let new_pivot = pivot - max 1 ((pivot - inf) / 2) in
                loop (inf, pivot) new_pivot
          in
          loop (0, length - 1) heuristic_initial_pivot
  with _ -> None

(* Hypothesis: the table is ordered. *)
let compute_location cemented_store block_level =
  Option.map
    (function
      | {start_level; file; _} ->
          (file, Int32.(to_int (sub block_level start_level))))
    (find_block_file cemented_store block_level)

let is_cemented cemented_store hash =
  try
    Cemented_block_level_index.mem
      cemented_store.cemented_block_level_index
      hash
  with Not_found -> false

let get_cemented_block_level cemented_store hash =
  try
    Some
      (Cemented_block_level_index.find
         cemented_store.cemented_block_level_index
         hash)
  with Not_found -> None

let get_cemented_block_hash cemented_store level =
  try
    Some
      (Cemented_block_hash_index.find
         cemented_store.cemented_block_hash_index
         level)
  with Not_found -> None

let read_block_metadata ?location cemented_store block_level =
  let location =
    match location with
    | Some _ -> location
    | None -> compute_location cemented_store block_level
  in
  match location with
  | None -> return_none
  | Some (cemented_file, _block_number) -> (
      let metadata_file =
        Naming.(
          cemented_store.cemented_blocks_dir |> cemented_blocks_metadata_dir
          |> fun d -> cemented_blocks_metadata_file d cemented_file |> file_path)
      in
      Lwt_unix.file_exists metadata_file >>= function
      | false -> return_none
      | true ->
          Lwt.catch
            (fun () ->
              let in_file = Zip.open_in metadata_file in
              Lwt.catch
                (fun () ->
                  let entry =
                    Zip.find_entry in_file (Int32.to_string block_level)
                  in
                  let metadata = Zip.read_entry in_file entry in
                  Zip.close_in in_file ;
                  return_some
                    (Data_encoding.Binary.of_string_exn
                       Block_repr.metadata_encoding
                       metadata))
                (fun _ ->
                  Zip.close_in in_file ;
                  return_none))
            (fun _ -> return_none))

let cement_blocks_metadata cemented_store blocks =
  let cemented_metadata_dir =
    cemented_store.cemented_blocks_dir |> Naming.cemented_blocks_metadata_dir
  in
  let cemented_metadata_dir_path = cemented_metadata_dir |> Naming.dir_path in
  (Lwt_unix.file_exists cemented_metadata_dir_path >>= function
   | true -> Lwt.return_unit
   | false -> Lwt_utils_unix.create_dir cemented_metadata_dir_path)
  >>= fun () ->
  fail_unless (blocks <> []) (Cannot_cement_blocks_metadata `Empty)
  >>=? fun () ->
  find_block_file
    cemented_store
    (Block_repr.level
       (List.hd blocks |> WithExceptions.Option.get ~loc:__LOC__))
  |> function
  | None -> fail (Cannot_cement_blocks_metadata `Not_cemented)
  | Some {file; _} ->
      let tmp_metadata_file_path =
        Naming.cemented_blocks_tmp_metadata_file cemented_metadata_dir file
        |> Naming.file_path
      in
      if List.exists (fun block -> Block_repr.metadata block <> None) blocks
      then (
        let out_file = Zip.open_out tmp_metadata_file_path in
        List.iter_s
          (fun block ->
            let level = Block_repr.level block in
            match Block_repr.metadata block with
            | Some metadata ->
                let metadata =
                  Data_encoding.Binary.to_string_exn
                    Block_repr.metadata_encoding
                    metadata
                in
                Zip.add_entry
                  ~level:default_compression_level
                  metadata
                  out_file
                  (Int32.to_string level) ;
                Lwt.pause ()
            | None -> Lwt.return_unit)
          blocks
        >>= fun () ->
        Zip.close_out out_file ;
        let metadata_file_path =
          Naming.cemented_blocks_metadata_file cemented_metadata_dir file
          |> Naming.file_path
        in
        Lwt_unix.rename tmp_metadata_file_path metadata_file_path >>= fun () ->
        return_unit)
      else return_unit

let read_block fd block_number =
  Lwt_unix.lseek fd (block_number * offset_length) Unix.SEEK_SET >>= fun _ofs ->
  let offset_buffer = Bytes.create offset_length in
  (* We read the (absolute) offset at the position in the offset array *)
  Lwt_utils_unix.read_bytes ~pos:0 ~len:offset_length fd offset_buffer
  >>= fun () ->
  let offset =
    Data_encoding.(Binary.of_bytes_opt offset_encoding offset_buffer)
    |> WithExceptions.Option.get ~loc:__LOC__
  in
  Lwt_unix.lseek fd offset Unix.SEEK_SET >>= fun _ofs ->
  (* We move the cursor to the element's position *)
  Block_repr.read_next_block_exn fd >>= fun (block, _len) -> Lwt.return block

let get_lowest_cemented_level cemented_store =
  match cemented_store.cemented_blocks_files with
  | None -> None
  | Some cemented_blocks_files ->
      let nb_cemented_blocks = Array.length cemented_blocks_files in
      if nb_cemented_blocks > 0 then Some cemented_blocks_files.(0).start_level
      else None

let get_highest_cemented_level cemented_store =
  match cemented_store.cemented_blocks_files with
  | None -> None
  | Some cemented_blocks_files ->
      let nb_cemented_blocks = Array.length cemented_blocks_files in
      if nb_cemented_blocks > 0 then
        Some cemented_blocks_files.(nb_cemented_blocks - 1).end_level
      else (* No cemented blocks*)
        None

let get_cemented_block_by_level (cemented_store : t) ~read_metadata level =
  match compute_location cemented_store level with
  | None -> return_none
  | Some ((filename, block_number) as location) ->
      let file_path = Naming.file_path filename in
      Lwt_unix.openfile file_path [Unix.O_RDONLY; O_CLOEXEC] 0o444 >>= fun fd ->
      Lwt.finalize
        (fun () -> read_block fd block_number)
        (fun () -> Lwt_utils_unix.safe_close fd >>= fun _ -> Lwt.return_unit)
      >>= fun block ->
      if read_metadata then
        read_block_metadata ~location cemented_store level >>=? fun metadata ->
        return_some {block with metadata}
      else return_some block

let read_block_metadata cemented_store block_level =
  read_block_metadata cemented_store block_level

let get_cemented_block_by_hash ~read_metadata (cemented_store : t) hash =
  match get_cemented_block_level cemented_store hash with
  | None -> return_none
  | Some level ->
      get_cemented_block_by_level ~read_metadata cemented_store level

(* Hypothesis:
   - The block list is expected to be ordered by increasing
     level and no blocks are skipped.
   - If the first block has metadata, metadata are written
     and all blocks are expected to have metadata. *)
let cement_blocks ?(check_consistency = true) (cemented_store : t)
    ~write_metadata (blocks : Block_repr.t list) =
  let nb_blocks = List.length blocks in
  let preamble_length = nb_blocks * offset_length in
  fail_when (nb_blocks = 0) (Cannot_cement_blocks `Empty) >>=? fun () ->
  let first_block = List.hd blocks |> WithExceptions.Option.get ~loc:__LOC__ in
  let first_block_level = Block_repr.level first_block in
  let last_block_level =
    Int32.(add first_block_level (of_int (nb_blocks - 1)))
  in
  (if check_consistency then
   match get_highest_cemented_level cemented_store with
   | None -> return_unit
   | Some highest_cemented_block ->
       fail_when
         Compare.Int32.(first_block_level <> Int32.succ highest_cemented_block)
         (Cannot_cement_blocks `Higher_cemented)
  else return_unit)
  >>=? fun () ->
  let file =
    Naming.cemented_blocks_file
      cemented_store.cemented_blocks_dir
      ~start_level:first_block_level
      ~end_level:last_block_level
  in
  let final_path = Naming.file_path file in
  (* Manipulate temporary files and swap it when everything is written *)
  let tmp_file_path = final_path ^ ".tmp" in
  Lwt_unix.file_exists tmp_file_path >>= fun exists ->
  fail_when exists (Temporary_cemented_file_exists tmp_file_path) >>=? fun () ->
  Lwt_unix.openfile
    tmp_file_path
    Unix.[O_CREAT; O_TRUNC; O_RDWR; O_CLOEXEC]
    0o644
  >>= fun fd ->
  Lwt.finalize
    (fun () ->
      (* Blit the offset preamble *)
      let offsets_buffer = Bytes.create preamble_length in
      Lwt_utils_unix.write_bytes ~pos:0 ~len:preamble_length fd offsets_buffer
      >>= fun () ->
      let first_offset = preamble_length in
      (* Cursor is now at the beginning of the element section *)
      Lwt_list.fold_left_s
        (fun (i, current_offset) block ->
          let block_bytes =
            Data_encoding.Binary.to_bytes_exn
              Block_repr.encoding
              (* Don't write metadata in this file *)
              {block with metadata = None}
          in
          let block_offset_bytes =
            Data_encoding.Binary.to_bytes_exn offset_encoding current_offset
          in
          (* We start by blitting the corresponding offset in the preamble part *)
          Bytes.blit
            block_offset_bytes
            0
            offsets_buffer
            (i * offset_length)
            offset_length ;
          let block_len = Bytes.length block_bytes in
          (* We write the block in the file *)
          Lwt_utils_unix.write_bytes ~pos:0 ~len:block_len fd block_bytes
          >>= fun () ->
          let level = Int32.(add first_block_level (of_int i)) in
          (* We also populate the indexes *)
          Cemented_block_level_index.replace
            cemented_store.cemented_block_level_index
            block.hash
            level ;
          Cemented_block_hash_index.replace
            cemented_store.cemented_block_hash_index
            level
            block.hash ;
          Lwt.return (succ i, current_offset + block_len))
        (0, first_offset)
        blocks
      >>= fun _ ->
      (* We now write the real offsets in the preamble *)
      Lwt_unix.lseek fd 0 Unix.SEEK_SET >>= fun _ofs ->
      Lwt_utils_unix.write_bytes ~pos:0 ~len:preamble_length fd offsets_buffer)
    (fun () -> Lwt_utils_unix.safe_close fd >>= fun _ -> Lwt.return_unit)
  >>= fun () ->
  Lwt_unix.rename tmp_file_path final_path >>= fun () ->
  (* Flush the indexes to make sure that the data is stored on disk *)
  Cemented_block_level_index.flush
    ~with_fsync:true
    cemented_store.cemented_block_level_index ;
  Cemented_block_hash_index.flush
    ~with_fsync:true
    cemented_store.cemented_block_hash_index ;
  (* Update table *)
  let cemented_block_interval =
    {start_level = first_block_level; end_level = last_block_level; file}
  in
  let new_array =
    match cemented_store.cemented_blocks_files with
    | None -> [|cemented_block_interval|]
    | Some arr ->
        if not (Array.mem cemented_block_interval arr) then
          Array.append arr [|cemented_block_interval|]
        else arr
  in
  (* If the cementing is done arbitrarily, we need to make sure the
     files remain sorted. *)
  if not check_consistency then Array.sort compare_cemented_files new_array ;
  cemented_store.cemented_blocks_files <- Some new_array ;
  (* Compress and write the metadatas *)
  if write_metadata then cement_blocks_metadata cemented_store blocks
  else return_unit

let trigger_full_gc cemented_store cemented_blocks_files offset =
  let nb_files = Array.length cemented_blocks_files in
  if nb_files <= offset then Lwt.return_unit
  else
    let cemented_files = Array.to_list cemented_blocks_files in
    let (files_to_remove, _files_to_keep) =
      List.split_n (nb_files - offset) cemented_files
    in
    (* Remove the rest of the files to prune *)
    Lwt_list.iter_s
      (fun {file; _} ->
        let metadata_file_path =
          Naming.(
            cemented_blocks_metadata_file
              (cemented_blocks_metadata_dir cemented_store.cemented_blocks_dir)
              file
            |> file_path)
        in
        Unit.catch_s (fun () -> Lwt_unix.unlink metadata_file_path))
      files_to_remove

let trigger_rolling_gc cemented_store cemented_blocks_files offset =
  let nb_files = Array.length cemented_blocks_files in
  if nb_files <= offset then Lwt.return_unit
  else
    let {end_level = last_level_to_purge; _} =
      cemented_blocks_files.(nb_files - offset - 1)
    in
    let cemented_files = Array.to_list cemented_blocks_files in
    (* Start by updating the indexes by filtering blocks that are
       below the offset *)
    Cemented_block_hash_index.filter
      cemented_store.cemented_block_hash_index
      (fun (level, _) -> Compare.Int32.(level > last_level_to_purge)) ;
    Cemented_block_level_index.filter
      cemented_store.cemented_block_level_index
      (fun (_, level) -> Compare.Int32.(level > last_level_to_purge)) ;
    let (files_to_remove, _files_to_keep) =
      List.split_n (nb_files - offset) cemented_files
    in
    (* Remove the rest of the files to prune *)
    Lwt_list.iter_s
      (fun {file; _} ->
        let metadata_file_path =
          Naming.(
            cemented_blocks_metadata_file
              (cemented_blocks_metadata_dir cemented_store.cemented_blocks_dir)
              file
            |> file_path)
        in
        Unit.catch_s (fun () -> Lwt_unix.unlink metadata_file_path)
        >>= fun () ->
        Unit.catch_s (fun () -> Lwt_unix.unlink (Naming.file_path file)))
      files_to_remove

let trigger_gc cemented_store =
  match cemented_store.cemented_blocks_files with
  | None -> fun _ -> Lwt.return_unit
  | Some cemented_blocks_files -> (
      function
      | History_mode.Archive -> Lwt.return_unit
      | Full offset ->
          let offset =
            (Option.value
               offset
               ~default:History_mode.default_additional_cycles)
              .offset
          in
          trigger_full_gc cemented_store cemented_blocks_files offset
      | Rolling offset ->
          let offset =
            (Option.value
               offset
               ~default:History_mode.default_additional_cycles)
              .offset
          in
          trigger_rolling_gc cemented_store cemented_blocks_files offset)

let iter_cemented_file f ({file; _} as cemented_blocks_file) =
  protect (fun () ->
      let file_path = Naming.file_path file in
      Lwt_io.with_file
        ~flags:[Unix.O_RDONLY; O_CLOEXEC]
        ~mode:Lwt_io.Input
        file_path
        (fun channel ->
          let nb_blocks = cemented_blocks_file_length cemented_blocks_file in
          Lwt_io.BE.read_int channel >>= fun first_block_offset ->
          Lwt_io.set_position channel (Int64.of_int first_block_offset)
          >>= fun () ->
          let rec loop n =
            if n = 0 then Lwt.return_unit
            else
              (* Read length *)
              Lwt_io.BE.read_int channel >>= fun length ->
              let full_length = 4 (* int32 length *) + length in
              let block_bytes = Bytes.create full_length in
              Lwt_io.read_into_exactly channel block_bytes 4 length
              >>= fun () ->
              Bytes.set_int32_be block_bytes 0 (Int32.of_int length) ;
              f
                (Data_encoding.Binary.of_bytes_exn
                   Block_repr.encoding
                   block_bytes)
              >>= fun () -> loop (pred n)
          in
          Lwt.catch
            (fun () -> loop (Int32.to_int nb_blocks) >>= fun () -> return_unit)
            (fun exn ->
              Format.kasprintf
                (fun trace ->
                  fail (Inconsistent_cemented_file (file_path, trace)))
                "%s"
                (Printexc.to_string exn))))

let check_indexes_consistency ?(post_step = fun () -> Lwt.return_unit)
    ?genesis_hash cemented_store =
  match cemented_store.cemented_blocks_files with
  | None -> return_unit
  | Some table ->
      let len = Array.length table in
      let rec check_contiguity i =
        if i = len || i = len - 1 then return_unit
        else
          fail_unless
            Compare.Int32.(
              Int32.succ table.(i).end_level = table.(i + 1).start_level)
            (Inconsistent_cemented_store
               (Missing_cycle
                  {
                    low_cycle = Naming.file_path table.(i).file;
                    high_cycle = Naming.file_path table.(i + 1).file;
                  }))
          >>=? fun () -> check_contiguity (succ i)
      in
      check_contiguity 0 >>=? fun () ->
      let table_list = Array.to_list table in
      List.iter_es
        (fun ({start_level = inf; file; _} as cemented_blocks_file) ->
          Lwt_unix.openfile
            (Naming.file_path file)
            [Unix.O_RDONLY; O_CLOEXEC]
            0o444
          >>= fun fd ->
          Lwt.finalize
            (fun () ->
              let nb_blocks =
                Int32.to_int (cemented_blocks_file_length cemented_blocks_file)
              in
              (* Load the offset region *)
              let len_offset = nb_blocks * offset_length in
              let bytes = Bytes.create len_offset in
              Lwt_utils_unix.read_bytes ~len:len_offset fd bytes >>= fun () ->
              let offsets =
                Data_encoding.Binary.of_bytes_exn
                  Data_encoding.(Variable.array ~max_length:nb_blocks int31)
                  bytes
              in
              (* Cursor is now after the offset region *)
              let rec iter_blocks ?pred_block n =
                if n = nb_blocks then return_unit
                else
                  Lwt_unix.lseek fd 0 Unix.SEEK_CUR >>= fun cur_offset ->
                  fail_unless
                    Compare.Int.(cur_offset = offsets.(n))
                    (Inconsistent_cemented_store
                       (Bad_offset {level = n; cycle = Naming.file_path file}))
                  >>=? fun () ->
                  Block_repr.read_next_block_exn fd >>= fun (block, _) ->
                  fail_unless
                    Compare.Int32.(
                      Block_repr.level block = Int32.(add inf (of_int n)))
                    (Inconsistent_cemented_store
                       (Unexpected_level
                          {
                            block_hash = Block_repr.hash block;
                            expected = Int32.(add inf (of_int n));
                            got = Block_repr.level block;
                          }))
                  >>=? fun () ->
                  Block_repr.check_block_consistency
                    ?genesis_hash
                    ?pred_block
                    block
                  >>=? fun () ->
                  let level = Block_repr.level block in
                  let hash = Block_repr.hash block in
                  fail_unless
                    (Cemented_block_level_index.mem
                       cemented_store.cemented_block_level_index
                       hash
                    && Cemented_block_hash_index.mem
                         cemented_store.cemented_block_hash_index
                         level)
                    (Inconsistent_cemented_store (Corrupted_index hash))
                  >>=? fun () -> iter_blocks ~pred_block:block (succ n)
              in
              protect (fun () ->
                  iter_blocks 0 >>=? fun () ->
                  post_step () >>= fun () -> return_unit))
            (fun () ->
              Lwt_utils_unix.safe_close fd >>= fun _ -> Lwt.return_unit))
        table_list
      >>=? fun () -> return_unit
