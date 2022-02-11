(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

(* Tezos Command line interface - Local Storage for Configuration *)

open Clic

module type Entity = sig
  type t

  val encoding : t Data_encoding.t

  val of_source : string -> t tzresult Lwt.t

  val to_source : t -> string tzresult Lwt.t

  val name : string

  include Compare.S with type t := t
end

module type Alias = sig
  type t

  type fresh_param

  val encoding : t Data_encoding.t

  val load : #Client_context.wallet -> (string * t) list tzresult Lwt.t

  val set : #Client_context.wallet -> (string * t) list -> unit tzresult Lwt.t

  val find : #Client_context.wallet -> string -> t tzresult Lwt.t

  val find_opt : #Client_context.wallet -> string -> t option tzresult Lwt.t

  val rev_find : #Client_context.wallet -> t -> string option tzresult Lwt.t

  val rev_find_all : #Client_context.wallet -> t -> string list tzresult Lwt.t

  val name : #Client_context.wallet -> t -> string tzresult Lwt.t

  val mem : #Client_context.wallet -> string -> bool tzresult Lwt.t

  val add :
    force:bool -> #Client_context.wallet -> string -> t -> unit tzresult Lwt.t

  val del : #Client_context.wallet -> string -> unit tzresult Lwt.t

  val update : #Client_context.wallet -> string -> t -> unit tzresult Lwt.t

  val of_source : string -> t tzresult Lwt.t

  val to_source : t -> string tzresult Lwt.t

  val alias_parameter :
    unit -> (string * t, #Client_context.wallet) Clic.parameter

  val alias_param :
    ?name:string ->
    ?desc:string ->
    ('a, (#Client_context.wallet as 'b)) Clic.params ->
    (string * t -> 'a, 'b) Clic.params

  val aliases_param :
    ?name:string ->
    ?desc:string ->
    ('a, (#Client_context.wallet as 'b)) Clic.params ->
    ((string * t) list -> 'a, 'b) Clic.params

  val fresh_alias_param :
    ?name:string ->
    ?desc:string ->
    ('a, (< .. > as 'obj)) Clic.params ->
    (fresh_param -> 'a, 'obj) Clic.params

  val force_switch : unit -> (bool, _) arg

  val of_fresh :
    #Client_context.wallet -> bool -> fresh_param -> string tzresult Lwt.t

  val source_param :
    ?name:string ->
    ?desc:string ->
    ('a, (#Client_context.wallet as 'obj)) Clic.params ->
    (t -> 'a, 'obj) Clic.params

  val source_arg :
    ?long:string ->
    ?placeholder:string ->
    ?doc:string ->
    unit ->
    (t option, (#Client_context.wallet as 'obj)) Clic.arg

  val autocomplete : #Client_context.wallet -> string list tzresult Lwt.t
end

module Alias (Entity : Entity) = struct
  open Client_context

  let wallet_encoding : (string * Entity.t) list Data_encoding.encoding =
    let open Data_encoding in
    list (obj2 (req "name" string) (req "value" Entity.encoding))

  let load (wallet : #wallet) =
    wallet#load Entity.name ~default:[] wallet_encoding

  let set (wallet : #wallet) entries =
    wallet#write Entity.name entries wallet_encoding

  let autocomplete wallet =
    let open Lwt_syntax in
    let* r = load wallet in
    match r with
    | Error _ -> return_ok_nil
    | Ok list -> return_ok (List.map fst list)

  let find_opt (wallet : #wallet) name =
    let open Lwt_tzresult_syntax in
    let+ list = load wallet in
    List.assoc ~equal:String.equal name list

  let find (wallet : #wallet) name =
    let open Lwt_tzresult_syntax in
    let* list = load wallet in
    match List.assoc ~equal:String.equal name list with
    | Some v -> return v
    | None -> failwith "no %s alias named %s" Entity.name name

  let rev_find (wallet : #wallet) v =
    let open Lwt_tzresult_syntax in
    let+ list = load wallet in
    Option.map fst @@ List.find (fun (_, v') -> Entity.(v = v')) list

  let rev_find_all (wallet : #wallet) v =
    let open Lwt_tzresult_syntax in
    let* list = load wallet in
    return
      (List.filter_map
         (fun (n, v') -> if Entity.(v = v') then Some n else None)
         list)

  let mem (wallet : #wallet) name =
    let open Lwt_tzresult_syntax in
    let+ list = load wallet in
    List.mem_assoc ~equal:String.equal name list

  let add ~force (wallet : #wallet) name value =
    let open Lwt_tzresult_syntax in
    let keep = ref false in
    let* list = load wallet in
    let* () =
      if force then return_unit
      else
        List.iter_es
          (fun (n, v) ->
            if Compare.String.(n = name) && Entity.(v = value) then (
              keep := true ;
              return_unit)
            else if Compare.String.(n = name) && Entity.(v <> value) then
              failwith
                "another %s is already aliased as %s, use --force to update"
                Entity.name
                n
            else if Compare.String.(n <> name) && Entity.(v = value) then
              failwith
                "this %s is already aliased as %s, use --force to insert \
                 duplicate"
                Entity.name
                n
            else return_unit)
          list
    in
    let list = List.filter (fun (n, _) -> not (String.equal n name)) list in
    let list = (name, value) :: list in
    if !keep then return_unit else wallet#write Entity.name list wallet_encoding

  let del (wallet : #wallet) name =
    let open Lwt_tzresult_syntax in
    let* list = load wallet in
    let list = List.filter (fun (n, _) -> not (String.equal n name)) list in
    wallet#write Entity.name list wallet_encoding

  let update (wallet : #wallet) name value =
    let open Lwt_tzresult_syntax in
    let* list = load wallet in
    let list =
      List.map
        (fun (n, v) -> (n, if String.equal n name then value else v))
        list
    in
    wallet#write Entity.name list wallet_encoding

  include Entity

  let alias_parameter () =
    let open Lwt_tzresult_syntax in
    parameter ~autocomplete (fun cctxt s ->
        let* v = find cctxt s in
        return (s, v))

  let alias_param ?(name = "name")
      ?(desc = "existing " ^ Entity.name ^ " alias") next =
    param ~name ~desc (alias_parameter ()) next

  let aliases_parameter () =
    let open Lwt_tzresult_syntax in
    parameter ~autocomplete (fun cctxt s ->
        String.split ',' s
        |> List.map_es (fun s ->
               let* pkh = find cctxt s in
               return (s, pkh)))

  let aliases_param ?(name = "name")
      ?(desc = "existing " ^ Entity.name ^ " aliases") next =
    param ~name ~desc (aliases_parameter ()) next

  type fresh_param = Fresh of string

  let of_fresh (wallet : #wallet) force (Fresh s) =
    let open Lwt_tzresult_syntax in
    let* list = load wallet in
    let* () =
      if force then return_unit
      else
        List.iter_es
          (fun (n, v) ->
            if String.equal n s then
              let* value = Entity.to_source v in
              failwith
                "@[<v 2>The %s alias %s already exists.@,\
                 The current value is %s.@,\
                 Use --force to update@]"
                Entity.name
                n
                value
            else return_unit)
          list
    in
    return s

  let fresh_alias_param ?(name = "new")
      ?(desc = "new " ^ Entity.name ^ " alias") next =
    param ~name ~desc (parameter (fun (_ : < .. >) s -> return @@ Fresh s)) next

  let parse_source_string cctxt s =
    let open Lwt_tzresult_syntax in
    match String.split ~limit:1 ':' s with
    | ["alias"; alias] -> find cctxt alias
    | ["text"; text] -> of_source text
    | ["file"; path] ->
        let* s = cctxt#read_file path in
        of_source s
    | _ -> (
        let*! r = find cctxt s in
        match r with
        | Ok v -> return v
        | Error a_errs -> (
            let*! r =
              let* s = cctxt#read_file s in
              of_source s
            in
            match r with
            | Ok v -> return v
            | Error r_errs -> (
                let*! r = of_source s in
                match r with
                | Ok v -> return v
                | Error s_errs ->
                    let all_errs = List.flatten [a_errs; r_errs; s_errs] in
                    Lwt.return_error all_errs)))

  let source_param ?(name = "src") ?(desc = "source " ^ Entity.name) next =
    let desc =
      Format.asprintf
        "%s\n\
         Can be a %s name, a file or a raw %s literal. If the parameter is not \
         the name of an existing %s, the client will look for a file \
         containing a %s, and if it does not exist, the argument will be read \
         as a raw %s.\n\
         Use 'alias:name', 'file:path' or 'text:literal' to disable autodetect."
        desc
        Entity.name
        Entity.name
        Entity.name
        Entity.name
        Entity.name
    in
    param ~name ~desc (parameter parse_source_string) next

  let source_arg ?(long = "source " ^ Entity.name) ?(placeholder = "src")
      ?(doc = "") () =
    let doc =
      Format.asprintf
        "%s\n\
         Can be a %s name, a file or a raw %s literal. If the parameter is not \
         the name of an existing %s, the client will look for a file \
         containing a %s, and if it does not exist, the argument will be read \
         as a raw %s.\n\
         Use 'alias:name', 'file:path' or 'text:literal' to disable autodetect."
        doc
        Entity.name
        Entity.name
        Entity.name
        Entity.name
        Entity.name
    in
    arg ~long ~placeholder ~doc (parameter parse_source_string)

  let force_switch () =
    Clic.switch
      ~long:"force"
      ~short:'f'
      ~doc:("overwrite existing " ^ Entity.name)
      ()

  let name (wallet : #wallet) d =
    let open Lwt_result_syntax in
    let* o = rev_find wallet d in
    match o with None -> Entity.to_source d | Some name -> return name
end
