(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2018-2021 Nomadic Labs. <contact@nomadic-labs.com>          *)
(* Copyright (c) 2018-2020 Tarides <contact@tarides.com>                     *)
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

include Context_dump_intf

(*****************************************************************************)

type error +=
  | System_write_error of string
  | Context_not_found of Bytes.t
  | System_read_error of string
  | Inconsistent_context_dump
  | Restore_context_failure

let () =
  let open Data_encoding in
  register_error_kind
    `Permanent
    ~id:"context_dump.writing_error"
    ~title:"Writing error"
    ~description:"Cannot write in file for context dump"
    ~pp:(fun ppf s ->
      Format.fprintf ppf "Unable to write file for context dumping: %s" s)
    (obj1 (req "context_dump_no_space" string))
    (function System_write_error s -> Some s | _ -> None)
    (fun s -> System_write_error s) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.context_not_found"
    ~title:"Context not found"
    ~description:"Cannot find context corresponding to hash"
    ~pp:(fun ppf mb ->
      Format.fprintf ppf "No context with hash: %s" (Bytes.to_string mb))
    (obj1 (req "context_not_found" bytes))
    (function Context_not_found mb -> Some mb | _ -> None)
    (fun mb -> Context_not_found mb) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.system_read_error"
    ~title:"System read error"
    ~description:"Failed to read file"
    ~pp:(fun ppf uerr ->
      Format.fprintf ppf "Error while reading file for context dumping: %s" uerr)
    (obj1 (req "system_read_error" string))
    (function System_read_error e -> Some e | _ -> None)
    (fun e -> System_read_error e) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.inconsistent_context_dump"
    ~title:"Inconsistent context dump"
    ~description:"Error while reading context dump"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Failed to read context dump. The provided file is inconsistent.")
    empty
    (function Inconsistent_context_dump -> Some () | _ -> None)
    (fun () -> Inconsistent_context_dump) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.restore_context_failure"
    ~title:"Failed to restore context"
    ~description:"Internal error while restoring the context"
    ~pp:(fun ppf () ->
      Format.fprintf ppf "Internal error while restoring the context.")
    empty
    (function Restore_context_failure -> Some () | _ -> None)
    (fun () -> Restore_context_failure)

module Make (I : Dump_interface) = struct
  type command =
    | Root
    | Node of (string * I.Kinded_hash.t) list
    | Node_seq of (string * I.Kinded_hash.t, error trace) Seq_es.t
    | Blob of bytes
    | Eoc of {info : I.commit_info; parents : I.Commit_hash.t list}
    | Eof

  (* Command encoding. *)

  let blob_encoding =
    let open Data_encoding in
    case
      ~title:"blob"
      (Tag (Char.code 'b'))
      bytes
      (function Blob b -> Some b | _ -> None)
      (function b -> Blob b)

  let node_encoding =
    let open Data_encoding in
    case
      ~title:"node"
      (Tag (Char.code 'n'))
      (list (obj2 (req "name" string) (req "hash" I.Kinded_hash.encoding)))
      (function Node x -> Some x | _ -> None)
      (function x -> Node x)

  let eof_encoding =
    let open Data_encoding in
    case
      ~title:"eof"
      (Tag (Char.code 'e'))
      empty
      (function Eof -> Some () | _ -> None)
      (fun () -> Eof)

  let root_encoding =
    let open Data_encoding in
    case
      ~title:"root"
      (Tag (Char.code 'r'))
      empty
      (function Root -> Some () | _ -> None)
      (fun () -> Root)

  let eoc_encoding =
    let open Data_encoding in
    case
      ~title:"eoc"
      (Tag (Char.code 'c'))
      (obj2
         (req "info" I.commit_info_encoding)
         (req "parents" (list I.Commit_hash.encoding)))
      (function Eoc {info; parents} -> Some (info, parents) | _ -> None)
      (fun (info, parents) -> Eoc {info; parents})

  let command_encoding =
    Data_encoding.union
      ~tag_size:`Uint8
      [blob_encoding; node_encoding; eoc_encoding; root_encoding; eof_encoding]

  (* IO toolkit. *)

  let rec read_string rbuf ~len =
    let (fd, buf, ofs, total) = !rbuf in
    if Bytes.length buf - ofs < len then (
      let blen = Bytes.length buf - ofs in
      let neu = Bytes.create (blen + 1_000_000) in
      Bytes.blit buf ofs neu 0 blen ;
      Lwt_unix.read fd neu blen 1_000_000 >>= fun bread ->
      total := !total + bread ;
      if bread = 0 then fail Inconsistent_context_dump
      else
        let neu =
          if bread <> 1_000_000 then Bytes.sub neu 0 (blen + bread) else neu
        in
        rbuf := (fd, neu, 0, total) ;
        read_string rbuf ~len)
    else
      let res = Bytes.sub_string buf ofs len in
      rbuf := (fd, buf, ofs + len, total) ;
      return res

  let read_mbytes rbuf b =
    read_string rbuf ~len:(Bytes.length b) >>=? fun string ->
    Bytes.blit_string string 0 b 0 (Bytes.length b) ;
    return ()

  let set_int64 buf i =
    let b = Bytes.create 8 in
    EndianBytes.BigEndian.set_int64 b 0 i ;
    Buffer.add_bytes buf b

  let get_int64 rbuf =
    read_string ~len:8 rbuf >>=? fun s ->
    return @@ EndianString.BigEndian.get_int64 s 0

  let get_char rbuf =
    read_string ~len:1 rbuf >>=? fun s ->
    return @@ EndianString.BigEndian.get_int8 s 0

  let get_int4 rbuf =
    read_string ~len:4 rbuf >>=? fun s ->
    return @@ EndianString.BigEndian.get_int32 s 0

  let set_mbytes buf b =
    set_int64 buf (Int64.of_int (Bytes.length b)) ;
    Buffer.add_bytes buf b

  (* To decode a variable size string we need to: 1/ read the length of the
     string, encoded on 4 bytes; 2/ reset the offset to the beginning of the string
     encoding. *)
  let get_length_and_reset_offset rbuf =
    get_int4 rbuf >|=? Int32.to_int >>=? fun length ->
    let (fd, buf, ofs, total) = !rbuf in
    rbuf := (fd, buf, ofs - 4, total) ;
    Lwt.return_ok (length + 4)

  let read_variable_length_string rbuf =
    get_length_and_reset_offset rbuf >>=? fun length_name ->
    let b = Bytes.create length_name in
    read_mbytes rbuf b >|=? fun () ->
    let name = Data_encoding.(Binary.of_bytes_exn string) b in
    (length_name, name)

  let read_fixed_length_hash rbuf =
    let length_hash = 1 + 4 + 32 (*enum + size + hash*) in
    let b = Bytes.create length_hash in
    read_mbytes rbuf b >|=? fun () ->
    let hash = Data_encoding.Binary.of_bytes_exn I.Kinded_hash.encoding b in
    (length_hash, hash)

  let read_seq rbuf total =
    let step i =
      if i >= total then Lwt.return_ok None
      else
        read_variable_length_string rbuf >>=? fun (length_name, name) ->
        read_fixed_length_hash rbuf >|=? fun (length_hash, hash) ->
        let node = (name, hash) in
        let i = i + length_name + length_hash in
        Some (node, i)
    in
    Seq_es.unfold_es step 0

  let eoc_encoding_raw =
    let open Data_encoding in
    obj2
      (req "info" I.commit_info_encoding)
      (req "parents" (list I.Commit_hash.encoding))

  let get_command rbuf =
    get_int64 rbuf >|=? Int64.to_int >>=? fun total ->
    get_char rbuf >|=? Char.chr >>=? fun tag ->
    let read_empty () =
      let len = total - 1 in
      let b = Bytes.create len in
      read_mbytes rbuf b >|=? fun () ->
      Data_encoding.Binary.of_bytes_exn Data_encoding.empty b
    in
    match tag with
    | 'r' -> read_empty () >|=? fun () -> Root
    | 'e' -> read_empty () >|=? fun () -> Eof
    | 'c' ->
        let len = total - 1 in
        let b = Bytes.create len in
        read_mbytes rbuf b >|=? fun () ->
        let (info, parents) =
          Data_encoding.Binary.of_bytes_exn eoc_encoding_raw b
        in
        Eoc {info; parents}
    | 'b' ->
        let len = total - 1 in
        let b = Bytes.create len in
        read_mbytes rbuf b >|=? fun () ->
        let data = Data_encoding.Binary.of_bytes_exn Data_encoding.bytes b in
        Blob data
    | 'n' ->
        get_int4 rbuf >|=? Int32.to_int >>=? fun list_size ->
        let data = read_seq rbuf list_size in
        Lwt.return_ok (Node_seq data)
    | _ -> fail Restore_context_failure
  (* Getter and setters *)

  let set_root buf =
    let root = Root in
    let bytes = Data_encoding.Binary.to_bytes_exn command_encoding root in
    set_mbytes buf bytes

  let set_tree buf tree =
    (match tree with `Branch node -> Node node | `Leaf blob -> Blob blob)
    |> Data_encoding.Binary.to_bytes_exn command_encoding
    |> set_mbytes buf

  let set_eoc buf info parents =
    let eoc = Eoc {info; parents} in
    let bytes = Data_encoding.Binary.to_bytes_exn command_encoding eoc in
    set_mbytes buf bytes

  let set_end buf =
    let bytes = Data_encoding.Binary.to_bytes_exn command_encoding Eof in
    set_mbytes buf bytes

  let serialize_tree ~notify ~maybe_flush buf =
    I.tree_iteri_unique (fun sub_tree ->
        set_tree buf sub_tree ;
        maybe_flush () >>= fun () -> notify ())

  let dump_context_fd idx context_hash ~context_fd =
    (* Dumping *)
    let buf = Buffer.create 1_000_000 in
    let written = ref 0 in
    let flush () =
      let contents = Buffer.contents buf in
      Buffer.clear buf ;
      written := !written + String.length contents ;
      Lwt_utils_unix.write_string context_fd contents
    in
    let maybe_flush () =
      if Buffer.length buf > 1_000_000 then flush () else Lwt.return_unit
    in
    Lwt.catch
      (fun () ->
        I.checkout idx context_hash >>= function
        | None ->
            (* FIXME: dirty *)
            fail @@ Context_not_found (I.Commit_hash.to_bytes context_hash)
        | Some ctxt ->
            Animation.display_progress
              ~every:1000
              ~pp_print_step:(fun fmt i ->
                Format.fprintf
                  fmt
                  "Copying context: %dK elements, %s written"
                  (i / 1000)
                  (if !written > 1_048_576 then
                   Format.asprintf "%dMiB" (!written / 1_048_576)
                  else Format.asprintf "%dKiB" (!written / 1_024)))
              (fun notify ->
                set_root buf ;
                I.context_tree ctxt |> serialize_tree ~notify ~maybe_flush buf
                >>= fun elements ->
                let parents = I.context_parents ctxt in
                set_eoc buf (I.context_info ctxt) parents ;
                set_end buf ;
                return_unit >>=? fun () ->
                flush () >>= fun () -> return elements))
      (function
        | Unix.Unix_error (e, _, _) ->
            fail @@ System_write_error (Unix.error_message e)
        | err -> Lwt.fail err)

  (* Restoring *)

  let restore_context_fd index ~expected_context_hash ~fd ~nb_context_elements =
    let read = ref 0 in
    let rbuf = ref (fd, Bytes.empty, 0, read) in
    (* Editing the repository *)
    let add_blob t blob = I.add_bytes t blob >>= fun tree -> return tree in
    let add_dir t keys =
      I.add_dir t keys >>=? function
      | None -> fail Restore_context_failure
      | Some tree -> return tree
    in
    let restore () =
      let first_pass () =
        get_command rbuf >>=? function
        | Root -> return_unit
        | _ -> fail Inconsistent_context_dump
      in
      let rec second_pass batch ctxt context_hash notify =
        notify () >>= fun () ->
        get_command rbuf >>=? function
        | Node_seq contents ->
            add_dir batch contents >>=? fun tree ->
            second_pass batch (I.update_context ctxt tree) context_hash notify
        | Blob data ->
            add_blob batch data >>=? fun tree ->
            second_pass batch (I.update_context ctxt tree) context_hash notify
        | Eoc {info; parents} -> (
            I.set_context ~info ~parents ctxt context_hash >>= function
            | false -> fail Inconsistent_context_dump
            | true -> return_unit)
        | _ -> fail Inconsistent_context_dump
      in
      let check_eof () =
        get_command rbuf >>=? function
        | Eof -> return_unit
        | _ -> fail Inconsistent_context_dump
      in
      first_pass () >>=? fun block_data ->
      Animation.display_progress
        ~every:1000
        ~pp_print_step:(fun fmt i ->
          Format.fprintf
            fmt
            "Writing context: %dK/%dK (%d%%) elements, %s read"
            (i / 1_000)
            (nb_context_elements / 1_000)
            (100 * i / nb_context_elements)
            (if !read > 1_048_576 then
             Format.asprintf "%dMiB" (!read / 1_048_576)
            else Format.asprintf "%dKiB" (!read / 1_024)))
        (fun notify ->
          I.batch index (fun batch ->
              second_pass
                batch
                (I.make_context index)
                expected_context_hash
                notify))
      >>=? fun () ->
      check_eof () >>=? fun () -> return block_data
    in
    Lwt.catch
      (fun () -> restore ())
      (function
        | Unix.Unix_error (e, _, _) ->
            fail @@ System_read_error (Unix.error_message e)
        | err -> Lwt.fail err)
end

(* Legacy errors*)
type error +=
  | Inconsistent_snapshot_file
  | Inconsistent_snapshot_data
  | Invalid_snapshot_version of string * string list

let () =
  let open Data_encoding in
  register_error_kind
    `Permanent
    ~id:"context_dump.inconsistent_snapshot_file"
    ~title:"Inconsistent snapshot file"
    ~description:"Error while opening snapshot file"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "Failed to read snapshot file. The provided file is inconsistent.")
    empty
    (function Inconsistent_snapshot_file -> Some () | _ -> None)
    (fun () -> Inconsistent_snapshot_file) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.inconsistent_snapshot_data"
    ~title:"Inconsistent snapshot data"
    ~description:"The data provided by the snapshot is inconsistent"
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "The data provided by the snapshot file is inconsistent (context_hash \
         does not correspond for block).")
    empty
    (function Inconsistent_snapshot_data -> Some () | _ -> None)
    (fun () -> Inconsistent_snapshot_data) ;
  register_error_kind
    `Permanent
    ~id:"context_dump.invalid_snapshot_version"
    ~title:"Invalid snapshot version"
    ~description:"The version of the snapshot to import is not valid"
    ~pp:(fun ppf (found, expected) ->
      Format.fprintf
        ppf
        "The snapshot to import has version \"%s\" but one of %a was expected."
        found
        Format.(
          pp_print_list
            ~pp_sep:(fun ppf () -> fprintf ppf ", ")
            (fun ppf version -> fprintf ppf "\"%s\"" version))
        expected)
    (obj2 (req "found" string) (req "expected" (list string)))
    (function
      | Invalid_snapshot_version (found, expected) -> Some (found, expected)
      | _ -> None)
    (fun (found, expected) -> Invalid_snapshot_version (found, expected))
