#include "pja_cripto.h"
#include "blake3/blake3.h"
#include "monocypher/monocypher.h"
#include <stdlib.h>
void pja_blake3_128(const uint8_t *a, size_t na, const uint8_t *b, size_t nb, uint8_t out[16]) {
    blake3_hasher h;
    blake3_hasher_init(&h);
    if (na) blake3_hasher_update(&h, a, na);
    if (nb) blake3_hasher_update(&h, b, nb);
    blake3_hasher_finalize(&h, out, 16);
}

int pja_argon2id(const uint8_t *pass, size_t npass, const uint8_t *salt, size_t nsalt,
                 uint32_t m_kib, uint32_t t, uint32_t p, uint8_t out[32]) {
    /* Las mismas restricciones que argon2::Params::new del Rust: m >= 8p, t >= 1,
     * p >= 1. Los largos de Monocypher son uint32_t. */
    if (t < 1 || p < 1 || m_kib < 8u * p) return -1;
    if (npass > 0xFFFFFFFFu || nsalt > 0xFFFFFFFFu) return -1;
    size_t tam = (size_t)m_kib * 1024u;
    if (tam / 1024u != m_kib) return -1;            /* no entra en size_t (32 bits) */
    void *area = malloc(tam);
    if (!area) return -1;
    crypto_argon2_config cfg = { CRYPTO_ARGON2_ID, m_kib, t, p };
    crypto_argon2_inputs in = { pass, salt, (uint32_t)npass, (uint32_t)nsalt };
    crypto_argon2(out, 32, area, cfg, in, crypto_argon2_no_extras);
    crypto_wipe(area, tam);                         /* tiene material derivado de la contraseña */
    free(area);
    return 0;
}

void pja_aead_lock(const uint8_t key[32], const uint8_t nonce[24],
                   const uint8_t *ad, size_t nad,
                   const uint8_t *plano, size_t n, uint8_t *cifra, uint8_t mac[16]) {
    crypto_aead_lock(cifra, mac, key, nonce, ad, nad, plano, n);
}

int pja_aead_unlock(const uint8_t key[32], const uint8_t nonce[24],
                    const uint8_t *ad, size_t nad,
                    const uint8_t *cifra, size_t n, const uint8_t mac[16], uint8_t *plano) {
    return crypto_aead_unlock(plano, mac, key, nonce, ad, nad, cifra, n);
}

void pja_wipe(void *p, size_t n) { crypto_wipe(p, n); }
