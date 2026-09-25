#include "pja_cripto.h"
#include "blake3/blake3.h"
void pja_blake3_128(const uint8_t *a, size_t na, const uint8_t *b, size_t nb, uint8_t out[16]) {
    blake3_hasher h;
    blake3_hasher_init(&h);
    if (na) blake3_hasher_update(&h, a, na);
    if (nb) blake3_hasher_update(&h, b, nb);
    blake3_hasher_finalize(&h, out, 16);
}
