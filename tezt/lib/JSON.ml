(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(* [raw] contains a pair [name, raw_value].
   It is present for values that cannot be found easily elsewhere.
   For instance, [parse_file] sets [raw] to [None] because the raw value
   can be found easily in the file. But for JSON values that are obtained
   through other means, it is useful to print the value in the logs,
   so we store it in the error.

   [name] is the name of the root value; it is the [~origin] argument of [parse].

   [raw_value] is the string representation of the JSON value.

   [origin] is the string representation of the value of type [origin],
   which is [name] plus some location information.

   [message] is the error message. *)
type error = {
  raw : (string * string) option;
  origin : string;
  message : string;
}

let show_error {raw; origin; message} =
  match raw with
  | None ->
      Printf.sprintf "%s: %s" origin message
  | Some (raw_origin, raw_value) ->
      Printf.sprintf "%s = %s\n%s: %s" raw_origin raw_value origin message

exception Error of error

let () =
  Printexc.register_printer
  @@ function Error error -> Some (show_error error) | _ -> None

type u = Ezjsonm.value

(* Each [JSON.t] comes with its origin so that we can print nice error messages.

   - [Origin] denotes the original JSON value. Field [name] describes where it comes from,
     for instance ["RPC response"]. Field [json] is the full original JSON value.

   - [Field] denotes a field taken a JSON object.
     This JSON object itself originates from [origin], and the field name is [name].

   - [Item] denotes an item taken a JSON array.
     This JSON array itself originates from [origin], and the item index is [index].

   - [Error] denotes a field or an item taken from [origin] but which does not exist.
     The exact reason why it does not exist is [message]. *)
type origin =
  | Origin of {name : string; json : u}
  | Field of {origin : origin; name : string}
  | Item of {origin : origin; index : int}
  | Error of {origin : origin; message : string}

type t = {origin : origin; node : u}

let encode_u = Ezjsonm.value_to_string ~minify:false

let encode {node; _} = Ezjsonm.value_to_string ~minify:false node

let annotate ~origin node =
  {origin = Origin {name = origin; json = node}; node}

let unannotate {node; _} = node

let fail_string origin message =
  let rec gather_origin message fields = function
    | Origin {name; json} ->
        let origin =
          match fields with
          | [] ->
              name
          | _ :: _ ->
              name ^ ", at " ^ String.concat "" fields
        in
        raise (Error {raw = Some (name, encode_u json); origin; message})
    | Field {origin; name} ->
        gather_origin message (("." ^ name) :: fields) origin
    | Item {origin; index} ->
        gather_origin
          message
          (("[" ^ string_of_int index ^ "]") :: fields)
          origin
    | Error {origin; message} ->
        gather_origin message [] origin
  in
  gather_origin message [] origin

let fail origin x = Printf.ksprintf (fail_string origin) x

let parse_file file =
  let node =
    try Base.with_open_in file Ezjsonm.from_channel with
    | Ezjsonm.Parse_error (_, message) ->
        raise
          (Error
             {raw = None; origin = file; message = "invalid JSON: " ^ message})
    | Sys_error message ->
        raise
          (Error
             {
               raw = None;
               origin = file;
               message = "failed to read file: " ^ message;
             })
  in
  annotate ~origin:file node

let parse ~origin raw =
  let node =
    try Ezjsonm.value_from_string raw
    with Ezjsonm.Parse_error (_, message) ->
      raise
        (Error
           {
             raw = Some (origin, raw);
             origin;
             message = "invalid JSON: " ^ message;
           })
  in
  annotate ~origin node

let parse_opt ~origin raw =
  match Ezjsonm.from_string raw with
  | exception Ezjsonm.Parse_error _ ->
      None
  | node ->
      Some {origin = Origin {name = origin; json = node}; node}

let null_because_error origin message =
  let origin =
    match origin with
    | Error _ ->
        origin
    | Origin _ | Field _ | Item _ ->
        Error {origin; message}
  in
  {origin; node = `Null}

let get name {origin; node} =
  match node with
  | `O fields -> (
    match List.assoc_opt name fields with
    | None ->
        null_because_error origin ("missing field: " ^ name)
    | Some node ->
        {origin = Field {origin; name}; node} )
  | _ ->
      null_because_error origin "not an object"

let ( |-> ) json name = get name json

let geti index {origin; node} =
  match node with
  | `A items -> (
    match List.nth_opt items index with
    | None ->
        null_because_error origin ("missing item: " ^ string_of_int index)
    | Some node ->
        {origin = Item {origin; index}; node} )
  | _ ->
      null_because_error origin "not an array"

let ( |=> ) json index = geti index json

let check as_opt error_message json =
  match as_opt json with
  | None ->
      fail json.origin error_message
  | Some value ->
      value

let test as_opt json = match as_opt json with None -> false | Some _ -> true

let is_null {node; _} = match node with `Null -> true | _ -> false

let as_bool_opt json = match json.node with `Bool b -> Some b | _ -> None

let as_bool = check as_bool_opt "expected a boolean"

let is_bool = test as_bool_opt

let as_int_opt json =
  match json.node with
  | `Float f ->
      if Float.is_integer f then Some (Float.to_int f) else None
  | `String s ->
      int_of_string_opt s
  | _ ->
      None

let as_int = check as_int_opt "expected an integer"

let is_int = test as_int_opt

let as_int64_opt json =
  match json.node with
  | `Float f ->
      if Float.is_integer f then Some (Int64.of_float f) else None
  | `String s ->
      Int64.of_string_opt s
  | _ ->
      None

let as_int64 = check as_int64_opt "expected a 64-bit integer"

let is_int64 = test as_int64_opt

let as_float_opt json =
  match json.node with
  | `Float f ->
      Some f
  | `String s ->
      float_of_string_opt s
  | _ ->
      None

let as_float = check as_float_opt "expected a number"

let is_float = test as_float_opt

let as_string_opt json = match json.node with `String s -> Some s | _ -> None

let as_string = check as_string_opt "expected a string"

let is_string = test as_string_opt

let as_list_opt json =
  match json.node with
  | `Null ->
      Some []
  | `A l ->
      Some
        (List.mapi
           (fun index node ->
             {origin = Item {origin = json.origin; index}; node})
           l)
  | _ ->
      None

let as_list = check as_list_opt "expected an array"

let is_list = test as_list_opt

let as_object_opt json =
  match json.node with
  | `Null ->
      Some []
  | `O l ->
      Some
        (List.map
           (fun (name, node) ->
             (name, {origin = Field {origin = json.origin; name}; node}))
           l)
  | _ ->
      None

let as_object = check as_object_opt "expected an object"

let is_object = test as_object_opt
