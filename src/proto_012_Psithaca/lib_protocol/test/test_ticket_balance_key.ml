(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Trili Tech, <contact@trili.tech>                       *)
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
    Component: Protocol (Ticket_balance_key)
    Invocation: dune exec src/proto_alpha/lib_protocol/test/main.exe \
                -- test "^ticket balance key"
    Subject: Ticket balance key hashing
*)

open Protocol
open Alpha_context

let ( let* ) m f = m >>=? f

let wrap m = m >|= Environment.wrap_tzresult

let new_ctxt () =
  let* (block, _) = Context.init 1 in
  let* incr = Incremental.begin_construction block in
  return @@ Incremental.alpha_ctxt incr

let make_contract ticketer = wrap @@ Lwt.return @@ Contract.of_b58check ticketer

let make_ex_ticket ctxt ~ticketer ~typ ~content ~amount =
  let* (Script_ir_translator.Ex_comparable_ty cty, ctxt) =
    let node = Micheline.root @@ Expr.from_string typ in
    wrap @@ Lwt.return @@ Script_ir_translator.parse_comparable_ty ctxt node
  in
  let* ticketer = make_contract ticketer in
  let* (contents, ctxt) =
    let node = Micheline.root @@ Expr.from_string content in
    wrap @@ Script_ir_translator.parse_comparable_data ctxt cty node
  in
  let amount = Script_int.(abs @@ of_int amount) in
  let ticket = Script_typed_ir.{ticketer; contents; amount} in
  return (Ticket_scanner.Ex_ticket (cty, ticket), ctxt)

let make_key ctxt ~ticketer ~typ ~content ~amount ~owner =
  let* (ex_ticket, ctxt) =
    make_ex_ticket ctxt ~ticketer ~typ ~content ~amount
  in
  let* owner = make_contract owner in
  let* (key, amount, ctxt) =
    wrap
    @@ Ticket_balance_key.ticket_balance_key_and_amount ctxt ex_ticket ~owner
  in
  return (key, amount, ctxt)

let equal_script_hash ~loc msg key1 key2 =
  Assert.equal
    ~loc
    Script_expr_hash.equal
    msg
    Script_expr_hash.pp
    (Ticket_balance.script_expr_hash_of_key_hash key1)
    (Ticket_balance.script_expr_hash_of_key_hash key2)

let not_equal_script_hash ~loc msg key1 key2 =
  Assert.not_equal
    ~loc
    Script_expr_hash.equal
    msg
    Script_expr_hash.pp
    (Ticket_balance.script_expr_hash_of_key_hash key1)
    (Ticket_balance.script_expr_hash_of_key_hash key2)

let assert_keys ~ticketer1 ~ticketer2 ~typ1 ~typ2 ~amount1 ~amount2 ~content1
    ~content2 ~owner1 ~owner2 assert_condition =
  let* ctxt = new_ctxt () in
  let* (key1, amount1, ctxt) =
    make_key
      ctxt
      ~ticketer:ticketer1
      ~typ:typ1
      ~content:content1
      ~amount:amount1
      ~owner:owner1
  in
  let* (key2, amount2, _) =
    make_key
      ctxt
      ~ticketer:ticketer2
      ~typ:typ2
      ~content:content2
      ~amount:amount2
      ~owner:owner2
  in
  assert_condition (key1, amount1) (key2, amount2)

let assert_keys_not_equal ~loc =
  assert_keys (fun (key1, _) (key2, _) ->
      not_equal_script_hash ~loc "Assert that keys are not equal" key1 key2)

let assert_keys_equal ~loc =
  assert_keys (fun (key1, _) (key2, _) ->
      equal_script_hash ~loc "Assert that keys are equal" key1 key2)

let assert_amount ~loc ~ticketer ~typ ~content ~amount ~owner expected =
  let* ctxt = new_ctxt () in
  let* (_, amount, _ctxt) =
    make_key ctxt ~ticketer ~typ ~content ~amount ~owner
  in
  Assert.equal_int ~loc (Z.to_int amount) expected

(** Test that the amount returned is as expected. *)
let test_amount () =
  assert_amount
    ~loc:__LOC__
    ~ticketer:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ:"unit"
    ~content:"Unit"
    ~amount:42
    ~owner:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    42

(** Test that tickets with two different amounts map to the same hash.
    The amount is not part of the ticket balance key. *)
let test_different_amounts () =
  assert_keys_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"unit"
    ~typ2:"unit"
    ~content1:"Unit"
    ~content2:"Unit"
    ~amount1:1
    ~amount2:2
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that two tickets with different ticketers map to different hashes. *)
let test_different_ticketers () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~typ1:"nat"
    ~typ2:"nat"
    ~content1:"1"
    ~content2:"1"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that two tickets with different owners map to different hashes. *)
let test_different_owners () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"nat"
    ~typ2:"nat"
    ~content1:"1"
    ~content2:"1"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"

(** Test that two tickets with different contents map to different hashes. *)
let test_different_content () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"nat"
    ~typ2:"nat"
    ~content1:"1"
    ~content2:"2"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type nat and a ticket of type int, with the same
    content, map to different hashes. *)
let test_nat_int () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"nat"
    ~typ2:"int"
    ~content1:"1"
    ~content2:"1"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type nat and a ticket of type mutez, with the same
    content, map to different hashes. *)
let test_nat_mutez () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"nat"
    ~typ2:"mutez"
    ~content1:"1"
    ~content2:"1"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type nat and a ticket of type bool, with the
    contents (False/0), map to different hashes. *)
let test_bool_nat () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"bool"
    ~typ2:"nat"
    ~content1:"False"
    ~content2:"0"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type nat and a ticket of type bytes, with the
    contents (0/0x), map to different hashes. *)
let test_nat_bytes () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"nat"
    ~typ2:"bytes"
    ~content1:"0"
    ~content2:"0x"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a chain_id with same content
    map to different hashes. *)
let test_string_chain_id () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"chain_id"
    ~content1:{|"NetXynUjJNZm7wi"|}
    ~content2:{|"NetXynUjJNZm7wi"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a key_hash with same content
    map to different hashes. *)
let test_string_key_hash () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"key_hash"
    ~content1:{|"tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"|}
    ~content2:{|"tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a key with same content
    map to different hashes. *)
let test_string_key () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"key"
    ~content1:{|"edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav"|}
    ~content2:{|"edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a timestamp with same content
    map to different hashes. *)
let test_string_timestamp () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"timestamp"
    ~content1:{|"2019-09-26T10:59:51Z"|}
    ~content2:{|"2019-09-26T10:59:51Z"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a address with same content
    map to different hashes. *)
let test_string_address () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"address"
    ~content1:{|"KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi%entrypoint"|}
    ~content2:{|"KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi%entrypoint"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type string and a signature with same content
    map to different hashes. *)
let test_string_signature () =
  let signature =
    {|"edsigthTzJ8X7MPmNeEwybRAvdxS1pupqcM5Mk4uCuyZAe7uEk68YpuGDeViW8wSXMrCi5CwoNgqs8V2w8ayB5dMJzrYCHhD8C7"|}
  in
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"string"
    ~typ2:"signature"
    ~content1:signature
    ~content2:signature
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Tests that annotations are not taken into account when hashing keys.
    Two comparable types that only differ in their annotations should
    map to to the same hash. Here, the type [pair int string] is identical to
    [pair (int %id) (string %name)].
    *)
let test_annotation_pair () =
  assert_keys_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"(pair int string)"
    ~typ2:{|(pair (int %id) (string %name))|}
    ~content1:{|Pair 1 "hello"|}
    ~content2:{|Pair 1 "hello"|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Tests that annotations are not taken into account when hashing keys.
    Here the types [or int string] and [or (int %id) (string %name)]
    should hash to the same key.
   *)
let test_annotation_or () =
  assert_keys_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"(or int string)"
    ~typ2:{|(or (int %id) (string %name))|}
    ~content1:{|Left 1|}
    ~content2:{|Left 1|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Tests that annotations are not taken into account when hashing keys.
    Here the types [int] and [(int :int_alias)] should hash to the same key.
   *)
let test_annotation_type_alias () =
  assert_keys_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"int"
    ~typ2:"(int :int_alias)"
    ~content1:"0"
    ~content2:"0"
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Tests that annotations are not taken into account when hashing keys.
    Here the types [pair (or int string) int] and
    [pair (or (int %id) (string %name)) int] should hash to the same key.
   *)
let test_annotation_pair_or () =
  assert_keys_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"pair (or int string) int"
    ~typ2:{|pair (or (int %id) (string %name)) int|}
    ~content1:{|Pair (Left 1) 2|}
    ~content2:{|Pair (Left 1) 2|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type [option int] and [option nat] with the same
    content, [None], don't map to the same hash. *)
let test_option_none () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"option int"
    ~typ2:"option nat"
    ~content1:{|None|}
    ~content2:{|None|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

(** Test that a ticket of type [option int] and [option nat] with the same
    content, [Some 0], don't map to the same hash. *)
let test_option_some () =
  assert_keys_not_equal
    ~loc:__LOC__
    ~ticketer1:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~ticketer2:"KT1ThEdxfUcWUwqsdergy3QnbCWGHSUHeHJq"
    ~typ1:"option int"
    ~typ2:"option nat"
    ~content1:{|Some 0|}
    ~content2:{|Some 0|}
    ~amount1:1
    ~amount2:1
    ~owner1:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"
    ~owner2:"KT1AafHA1C1vk959wvHWBispY9Y2f3fxBUUo"

let tests =
  [
    Tztest.tztest "Test amount" `Quick test_amount;
    Tztest.tztest "Test different ticketers" `Quick test_different_ticketers;
    Tztest.tztest "Test different owners" `Quick test_different_owners;
    Tztest.tztest "Test different content" `Quick test_different_content;
    Tztest.tztest "Test different amounts" `Quick test_different_amounts;
    Tztest.tztest "Test nat int" `Quick test_nat_int;
    Tztest.tztest "Test nat mutez" `Quick test_nat_mutez;
    Tztest.tztest "Test not bool" `Quick test_bool_nat;
    Tztest.tztest "Test nat bytes" `Quick test_nat_bytes;
    Tztest.tztest "Test string chain_id" `Quick test_string_chain_id;
    Tztest.tztest "Test string key_hash" `Quick test_string_key_hash;
    Tztest.tztest "Test string timestamp" `Quick test_string_timestamp;
    Tztest.tztest "Test string address" `Quick test_string_address;
    Tztest.tztest "Test string key" `Quick test_string_key;
    Tztest.tztest "Test string signature" `Quick test_string_signature;
    Tztest.tztest "Test annotations for pair" `Quick test_annotation_pair;
    Tztest.tztest "Test annotations for or" `Quick test_annotation_or;
    Tztest.tztest
      "Test annotations for type alias"
      `Quick
      test_annotation_type_alias;
    Tztest.tztest
      "Test annotations for paired ors"
      `Quick
      test_annotation_pair_or;
    Tztest.tztest "Test option none" `Quick test_option_none;
    Tztest.tztest "Test option some" `Quick test_option_some;
  ]
