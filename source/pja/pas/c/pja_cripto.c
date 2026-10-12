/* syscall() y O_CLOEXEC: con -std=c99 estricto no se declaran sin esto. */
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#  define _GNU_SOURCE
#endif
#include "pja_cripto.h"
#include "blake3/blake3.h"
#include "monocypher/monocypher.h"
#include <stdlib.h>
#ifdef _WIN32
#  include <windows.h>
/* RtlGenRandom: exportada por advapi32 como SystemFunction036 desde XP; es
 * lo que usan las CRT de Microsoft para rand_s. BCryptGenRandom pediria otra
 * biblioteca y no da nada mas en Windows 7. */
BOOLEAN NTAPI SystemFunction036(PVOID buf, ULONG n);
#else
#  include <errno.h>
#  include <fcntl.h>
#  include <unistd.h>
#  if defined(__linux__)
#    include <sys/syscall.h>
#  endif
#endif
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

int pja_aleatorio(uint8_t *buf, size_t n) {
#ifdef _WIN32
    while (n > 0) {
        ULONG k = n > 0x10000000u ? 0x10000000u : (ULONG)n;
        if (!SystemFunction036(buf, k)) return -1;
        buf += k; n -= k;
    }
    return 0;
#else
#  if defined(__linux__) && defined(SYS_getrandom)
    /* getrandom por syscall y no por <sys/random.h>: la funcion de glibc es de
     * 2.25, y el binario de 32 bits tiene que andar en sistemas mas viejos.
     * Bloquea hasta que el generador del kernel este sembrado; /dev/urandom no. */
    while (n > 0) {
        long r = syscall(SYS_getrandom, buf, n, 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            if (errno == ENOSYS) break;        /* kernel < 3.17: al archivo */
            return -1;
        }
        buf += r; n -= (size_t)r;
    }
    if (n == 0) return 0;
#  endif
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    while (n > 0) {
        ssize_t r = read(fd, buf, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) { close(fd); return -1; }
        buf += r; n -= (size_t)r;
    }
    close(fd);
    return 0;
#endif
}
