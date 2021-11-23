/* global _HACL */

//Provides: hacl_create_buffer
//Requires: caml_bytes_unsafe_get
function hacl_create_buffer(MlBytes) {
  var len = MlBytes.l;
  var buf = new joo_global_object.Uint8Array(len);
  var i=0;
  for (i=0; i<len; i++) {
    var uint8 = caml_bytes_unsafe_get(MlBytes, i);
    buf[i] = uint8;
  }
  return buf;
}

//Provides: hacl_blit_buf_to_bytes
//Requires: caml_string_unsafe_set
function hacl_blit_buf_to_bytes(buf, MlBytes) {
  buf.forEach(function(uint8, index) {
    if(index < MlBytes.l)
      caml_string_unsafe_set(MlBytes, index, uint8)
  });
  return 0;
}

//Provides: _1_Lib_RandomBuffer_System_randombytes
//Requires: hacl_blit_buf_to_bytes
function _1_Lib_RandomBuffer_System_randombytes(buf) {
  return ((typeof self !== 'undefined' && (self.crypto || self.msCrypto))
    ? function() { // Browsers
      var crypto = (self.crypto || self.msCrypto), QUOTA = 65536;
      return function(n) {
        var result = new joo_global_object.Uint8Array(n);
        for (var i = 0; i < n; i += QUOTA) {
          crypto.getRandomValues(result.subarray(i, i + Math.min(n - i, QUOTA)));
        }
        hacl_blit_buf_to_bytes(result, buf);
        return true;
      };
    }
    : function() { // Node
      var result = require("crypto").randomBytes(60);
      hacl_blit_buf_to_bytes(result, buf);
      return true;
    })(buf)
}


//Provides: Hacl_Blake2b_32_blake2b
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Blake2b_32_blake2b(key, msg, digest_len, digest) {
  var H = joo_global_object._HACL;
  var bkey = hacl_create_buffer(key);
  var bmsg = hacl_create_buffer(msg);
  var bret = H.Blake2.blake2b(digest_len, bmsg, bkey);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_Hash_SHA2_hash_256
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Hash_SHA2_hash_256(msg, digest) {
  var H = joo_global_object._HACL;
  var bmsg = hacl_create_buffer(msg);
  var bret = H.SHA2.hash_256(bmsg);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_Hash_SHA2_hash_512
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Hash_SHA2_hash_512(msg, digest) {
  var H = joo_global_object._HACL;
  var bmsg = hacl_create_buffer(msg);
  var bret = H.SHA2.hash_512(bmsg);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_SHA3_sha3_256
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_SHA3_sha3_256(msg, digest) {
  var H = joo_global_object._HACL;
  var bmsg = hacl_create_buffer(msg);
  var bret = H.SHA3.hash_256(bmsg);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_SHA3_sha3_512
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_SHA3_sha3_512(msg, digest) {
  var H = joo_global_object._HACL;
  var bmsg = hacl_create_buffer(msg);
  var bret = H.SHA3.hash_512(bmsg);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_Impl_SHA3_keccak
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Impl_SHA3_keccak(rate, capacity, suffix, msg, digest) {
  var H = joo_global_object._HACL;
  var bmsg = hacl_create_buffer(msg);
  // The length of the output buffer needs to be passed in explicitly because
  // since the buffer itself is not passed there is no way to retrive its
  // size in api.js
  var bret = H.SHA3.keccak(rate, capacity, bmsg, suffix, digest.l);
  hacl_blit_buf_to_bytes(bret[0], digest);
  return 0;
}

//Provides: Hacl_HMAC_compute_sha2_256
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_HMAC_compute_sha2_256 (output, key, msg) {
  var H = joo_global_object._HACL;
  var bkey = hacl_create_buffer(key);
  var bmsg = hacl_create_buffer(msg);
  var bret = H.HMAC.sha256(bkey, bmsg);
  hacl_blit_buf_to_bytes(bret[0], output);
  return 0;
}

//Provides: Hacl_HMAC_compute_sha2_512
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_HMAC_compute_sha2_512 (output, key, msg) {
  var H = joo_global_object._HACL;
  var bkey = hacl_create_buffer(key);
  var bmsg = hacl_create_buffer(msg);
  var bret = H.HMAC.sha512(bkey, bmsg);
  hacl_blit_buf_to_bytes(bret[0], output);
  return 0;
}

//Provides: Hacl_Curve25519_51_scalarmult
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Curve25519_51_scalarmult(pk, sk, basepoint) {
  var H = joo_global_object._HACL;
  var bsk = hacl_create_buffer(sk);
  var bret = H.Curve25519_51.secret_to_public(bsk);
  hacl_blit_buf_to_bytes(bret[0], pk);
  return 0;
}

//Provides: Hacl_NaCl_crypto_secretbox_easy
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_secretbox_easy(c, m, n, k) {
  var H = joo_global_object._HACL;
  var bm = hacl_create_buffer(m);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.secretbox_easy(bm, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], c);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_secretbox_open_easy
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_secretbox_open_easy(m, c, n, k) {
  var H = joo_global_object._HACL;
  var bc = hacl_create_buffer(c);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.secretbox_open_easy(bc, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], m);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_box_beforenm
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_box_beforenm(k, pk, sk) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bsk = hacl_create_buffer(sk);
  var bret = H.NaCl.box_beforenm(bpk, bsk);
  hacl_blit_buf_to_bytes(bret[1], k);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_box_easy_afternm
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_box_easy_afternm(c, m, n, k) {
  var H = joo_global_object._HACL;
  var bm = hacl_create_buffer(m);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.box_easy_afternm(bm, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], c);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_box_open_easy_afternm
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_box_open_easy_afternm(m, c, n, k) {
  var H = joo_global_object._HACL;
  var bc = hacl_create_buffer(c);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.box_open_easy_afternm(bc, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], m);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_box_detached_afternm
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_box_detached_afternm(c, tag, m, n, k) {
  var H = joo_global_object._HACL;
  var bm = hacl_create_buffer(m);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.box_detached_afternm(bm, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], c);
  hacl_blit_buf_to_bytes(bret[2], tag);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_NaCl_crypto_box_open_detached_afternm
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_NaCl_crypto_box_open_detached_afternm(m, c, tag, n, k) {
  var H = joo_global_object._HACL;
  var btag = hacl_create_buffer(tag);
  var bc = hacl_create_buffer(c);
  var bn = hacl_create_buffer(n);
  var bk = hacl_create_buffer(k);
  var bret = H.NaCl.box_open_detached_afternm(bc, btag, bn, bk);
  hacl_blit_buf_to_bytes(bret[1], m);
  return (bret[0] === 0 ? 1 : 0);
}

//Provides: Hacl_Ed25519_secret_to_public
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Ed25519_secret_to_public(out, secret) {
  var H = joo_global_object._HACL;
  var bsecret = hacl_create_buffer(secret);
  var bret = H.Ed25519.secret_to_public(bsecret);
  hacl_blit_buf_to_bytes(bret[0], out);
  return 0;
}

//Provides: Hacl_Ed25519_sign
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_Ed25519_sign(signature, sk, msg) {
  var H = joo_global_object._HACL;
  var bsk = hacl_create_buffer(sk);
  var bmsg = hacl_create_buffer(msg);
  var bret = H.Ed25519.sign(bsk, bmsg);
  hacl_blit_buf_to_bytes(bret[0], signature);
  return 0;
}

//Provides: Hacl_Ed25519_verify
//Requires: hacl_create_buffer
function Hacl_Ed25519_verify(pk, msg, signature) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bmsg = hacl_create_buffer(msg);
  var bsignature = hacl_create_buffer(signature);
  var bret = H.Ed25519.verify(bpk, bmsg, bsignature);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_ecdsa_sign_p256_without_hash
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_ecdsa_sign_p256_without_hash (privkey, m, k, result) { // eslint-disable-line no-unused-vars
  var H = joo_global_object._HACL;
  var bm = hacl_create_buffer(m);
  var bprivkey = hacl_create_buffer(privkey);
  var bk = hacl_create_buffer(k);
  var bret = H.P256.ecdsa_sign_without_hash(bm, bprivkey, bk);
  hacl_blit_buf_to_bytes(bret[1], result);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_ecdsa_verif_without_hash
//Requires: hacl_create_buffer
function Hacl_P256_ecdsa_verif_without_hash (pk, msg, sig_r, sig_s) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bmsg = hacl_create_buffer(msg);
  var bsig_r = hacl_create_buffer(sig_r);
  var bsig_s = hacl_create_buffer(sig_s);
  var bret = H.P256.ecdsa_verif_without_hash(bmsg, bpk, bsig_r, bsig_s);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_is_more_than_zero_less_than_order
//Requires: hacl_create_buffer
function Hacl_P256_is_more_than_zero_less_than_order (sk) {
  var H = joo_global_object._HACL;
  var bsk = hacl_create_buffer(sk);
  var bret = H.P256.is_more_than_zero_less_than_order(bsk);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_verify_q
//Requires: hacl_create_buffer
function Hacl_P256_verify_q (pk) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bret = H.P256.verify_q(bpk);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_ecp256dh_i
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_ecp256dh_i (pk, sk) {
  var H = joo_global_object._HACL;
  var bsk = hacl_create_buffer(sk);
  var bret = H.P256.dh_initiator(bsk);
  hacl_blit_buf_to_bytes(bret[1], pk);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_compression_compressed_form
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_compression_compressed_form (pk, out) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bret = H.P256.compression_compressed_form(bpk);
  hacl_blit_buf_to_bytes(bret[0], out);
  return 0;
}

//Provides: Hacl_P256_compression_not_compressed_form
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_compression_not_compressed_form (pk, out) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bret = H.P256.compression_not_compressed_form(bpk);
  hacl_blit_buf_to_bytes(bret[0], out);
  return 0;
}

//Provides: Hacl_P256_decompression_compressed_form
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_decompression_compressed_form (pk, out) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bret = H.P256.decompression_compressed_form(bpk);
  hacl_blit_buf_to_bytes(bret[1], out);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_P256_decompression_not_compressed_form
//Requires: hacl_create_buffer, hacl_blit_buf_to_bytes
function Hacl_P256_decompression_not_compressed_form (pk, out) {
  var H = joo_global_object._HACL;
  var bpk = hacl_create_buffer(pk);
  var bret = H.P256.decompression_not_compressed_form(bpk);
  hacl_blit_buf_to_bytes(bret[1], out);
  return (bret[0] ? 1 : 0);
}

//Provides: Hacl_Hash_Core_SHA2_init_256
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_init_256(state) {
  caml_failwith(' not implemented Hacl_Hash_Core_SHA2_init_256');
}

//Provides: Hacl_Hash_Core_SHA2_update_256
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_update_256(state, bytes) {
  caml_failwith(' not implemented Hacl_Hash_Core_SHA2_update_256');
}

//Provides: Hacl_Hash_Core_SHA2_finish_256
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_finish_256(state, hash) {
    caml_failwith(' not implemented Hacl_Hash_Core_SHA2_finish_256');
}

//Provides: Hacl_Hash_Core_SHA2_init_512
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_init_512(state) {
    caml_failwith(' not implemented Hacl_Hash_Core_SHA2_init_512');
}

//Provides: Hacl_Hash_Core_SHA2_update_512
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_update_512(state, bytes) {
    caml_failwith(' not implemented Hacl_Hash_Core_SHA2_update_512');
}

//Provides: Hacl_Hash_Core_SHA2_finish_512
//Requires: caml_failwith
function Hacl_Hash_Core_SHA2_finish_512(state, hash) {
    caml_failwith(' not implemented Hacl_Hash_Core_SHA2_finish_512');
}
