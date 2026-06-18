/* SPDX-License-Identifier: Apache-2.0
 *
 * Lean FFI shim for Ed25519 signature verification (seal v2, M5).
 *
 * TCB(A3) boundary: the actual Ed25519 verification is performed by vendored
 * TweetNaCl (c/tweetnacl.c, pure Ed25519 / RFC 8032, SHA-512). This shim only
 * marshals Lean `ByteArray` arguments and adapts TweetNaCl's ATTACHED
 * `crypto_sign_open` into a detached-verify predicate. No proof in the Lean core
 * depends on this code being correct; origin authentication is a trusted
 * assumption (A3 = "vendored ed25519 verify is correct"), not a Lean theorem.
 */

#include <lean/lean.h>
#include <string.h>
#include <stdlib.h>
#include "tweetnacl.h"

/* TweetNaCl declares `extern void randombytes(u8*, u64);` and references it from
 * crypto_box_keypair / crypto_sign_keypair only. The verify path (crypto_sign_open)
 * never calls it. We neither generate keys nor sign on the C side, so provide a
 * loud-failing stub: if it is ever reached, that is a misuse, not a silent weakness. */
void randombytes(unsigned char *x, unsigned long long xlen) {
    (void)x; (void)xlen;
    abort();
}

/* Detached Ed25519 verify: returns 1 iff `sig` (64 bytes) is a valid signature of
 * `msg` under public key `pk` (32 bytes), else 0. TweetNaCl ships only the attached
 * form, so reconstruct the signed message sm = sig || msg and check it opens cleanly. */
LEAN_EXPORT uint8_t lean_seal_ed25519_verify(b_lean_obj_arg pk_obj,
                                             b_lean_obj_arg msg_obj,
                                             b_lean_obj_arg sig_obj) {
    size_t pk_len  = lean_sarray_size(pk_obj);
    size_t msg_len = lean_sarray_size(msg_obj);
    size_t sig_len = lean_sarray_size(sig_obj);

    /* Ed25519: public key 32 bytes, signature 64 bytes. Reject anything else. */
    if (pk_len != 32 || sig_len != 64) return 0;

    const uint8_t *pk  = lean_sarray_cptr(pk_obj);
    const uint8_t *msg = lean_sarray_cptr(msg_obj);
    const uint8_t *sig = lean_sarray_cptr(sig_obj);

    unsigned long long smlen = (unsigned long long)sig_len + (unsigned long long)msg_len;
    uint8_t *sm = (uint8_t *)malloc((size_t)smlen ? (size_t)smlen : 1);
    uint8_t *m  = (uint8_t *)malloc((size_t)smlen ? (size_t)smlen : 1);
    if (sm == NULL || m == NULL) { free(sm); free(m); return 0; }

    memcpy(sm, sig, 64);
    if (msg_len) memcpy(sm + 64, msg, msg_len);

    unsigned long long mlen = 0;
    int rc = crypto_sign_open(m, &mlen, sm, smlen, pk);

    free(sm);
    free(m);
    return (rc == 0) ? 1 : 0;
}
