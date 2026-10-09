/* pja_cripto.h — la frontera angosta entre la capa Pascal y la cripto en C.
 * Pascal nunca ve las estructuras internas de BLAKE3 ni de Monocypher: sólo
 * punteros con largo y búferes de salida de tamaño fijo. */
#ifndef PJA_CRIPTO_H
#define PJA_CRIPTO_H
#include <stddef.h>
#include <stdint.h>
/* BLAKE3 de la concatenación a ‖ b, truncado a 16 bytes. Dos tramos porque el
 * hash del índice cubre cab[0..12] ‖ índice sin copiarlos a un búfer común;
 * para un solo tramo, nb = 0. */
void pja_blake3_128(const uint8_t *a, size_t na, const uint8_t *b, size_t nb, uint8_t out[16]);

/* Argon2id (v1.3) sin secreto ni datos asociados: lo mismo que
 * argon2::Argon2::hash_password_into del Rust de referencia. Reserva su área de
 * trabajo (m_kib KiB), la limpia y la libera. 0 = bien; -1 = parámetros
 * inválidos o sin memoria. Nunca aborta. */
int pja_argon2id(const uint8_t *pass, size_t npass, const uint8_t *salt, size_t nsalt,
                 uint32_t m_kib, uint32_t t, uint32_t p, uint8_t out[32]);

/* XChaCha20-Poly1305 de un trozo. `cifra` recibe n bytes y `mac` el tag. */
void pja_aead_lock(const uint8_t key[32], const uint8_t nonce[24],
                   const uint8_t *ad, size_t nad,
                   const uint8_t *plano, size_t n, uint8_t *cifra, uint8_t mac[16]);
/* 0 = autenticó y `plano` tiene n bytes; -1 = no autenticó, y `plano` NO SE
 * TOCA: Monocypher verifica el MAC antes de descifrar (crypto_aead_read), así
 * que nunca se produce texto sin autenticar. Verificado en el código 4.0.3. */
int pja_aead_unlock(const uint8_t key[32], const uint8_t nonce[24],
                    const uint8_t *ad, size_t nad,
                    const uint8_t *cifra, size_t n, const uint8_t mac[16], uint8_t *plano);

void pja_wipe(void *p, size_t n);
#endif
