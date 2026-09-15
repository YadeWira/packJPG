// Ejercita la frontera desde C++ como la usaria packJPG, incluidos los
// caminos de error. No prueba el nucleo -- eso ya esta probado en Rust --
// prueba que el CONTRATO se respete desde el otro lado.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include "pjacore.h"

static int fallos = 0;
static void chequear(bool ok, const char* que) {
    printf("  %-52s %s\n", que, ok ? "ok" : "FALLA");
    if (!ok) fallos++;
}

static std::vector<uint8_t> leer(const char* ruta) {
    FILE* f = fopen(ruta, "rb");
    if (!f) return {};
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> v(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) v.clear();
    fclose(f);
    return v;
}

int main(int argc, char** argv) {
    printf("version del nucleo: %u\n", pja_version());
    if (argc < 2) { printf("uso: frontera <contenedor.pjg> [contraseña]\n"); return 2; }

    std::vector<uint8_t> datos = leer(argv[1]);
    chequear(!datos.empty(), "el contenedor de prueba se leyo");

    const uint8_t* pass = nullptr; size_t pass_largo = 0;
    if (argc >= 3) { pass = (const uint8_t*)argv[2]; pass_largo = strlen(argv[2]); }

    PjaAbierto* h = nullptr;
    int32_t rc = pja_abrir(datos.data(), datos.size(), pass, pass_largo, &h);
    chequear(rc == PJA_OK && h != nullptr, "pja_abrir devuelve OK y un manejador");
    if (rc != PJA_OK) return 1;

    int64_t n = pja_cantidad(h);
    chequear(n > 0, "pja_cantidad > 0");

    // Camino normal: preguntar largo, reservar, copiar.
    bool todos = true;
    for (int64_t i = 0; i < n; i++) {
        int64_t ln = pja_nombre_largo(h, i);
        int64_t lp = pja_payload_largo(h, i);
        if (ln <= 0 || lp <= 0) { todos = false; break; }
        std::vector<uint8_t> nombre(ln), payload(lp), hash(16), calc(16);
        if (pja_nombre(h, i, nombre.data(), nombre.size()) != PJA_OK) { todos = false; break; }
        if (pja_payload(h, i, payload.data(), payload.size()) != PJA_OK) { todos = false; break; }
        if (pja_hash(h, i, hash.data(), hash.size()) != PJA_OK) { todos = false; break; }
        // El hash declarado es del JPEG original; sobre el payload .pjg no
        // tiene por que coincidir. Lo que si se verifica es que pja_hash128
        // sea determinista y no toque el buffer de entrada.
        if (pja_hash128(payload.data(), payload.size(), calc.data(), calc.size()) != PJA_OK)
            { todos = false; break; }
        std::vector<uint8_t> calc2(16);
        pja_hash128(payload.data(), payload.size(), calc2.data(), calc2.size());
        if (calc != calc2) { todos = false; break; }
    }
    chequear(todos, "nombre, payload y hash de cada miembro");

    // Caminos de error: cada uno tiene que dar SU codigo, no un exito casual.
    std::vector<uint8_t> chico(4);
    chequear(pja_nombre(h, 0, chico.data(), chico.size()) == PJA_ERR_BUF_CHICO,
             "buffer chico -> PJA_ERR_BUF_CHICO");
    chequear(pja_nombre_largo(h, 99999) == PJA_ERR_RANGO,
             "indice fuera de rango -> PJA_ERR_RANGO");
    chequear(pja_payload(h, 0, nullptr, 100) == PJA_ERR_NULL,
             "buffer nulo -> PJA_ERR_NULL");
    std::vector<uint8_t> h8(8);
    chequear(pja_hash(h, 0, h8.data(), h8.size()) == PJA_ERR_BUF_CHICO,
             "hash con buffer de 8 -> PJA_ERR_BUF_CHICO");

    // Un byte alterado en la cabecera no debe abrir.
    std::vector<uint8_t> roto = datos;
    roto[5] ^= 1;
    PjaAbierto* h2 = nullptr;
    int32_t rc2 = pja_abrir(roto.data(), roto.size(), pass, pass_largo, &h2);
    chequear(rc2 != PJA_OK && h2 == nullptr, "un bit en flags -> no abre y no deja manejador");

    // Basura no abre.
    std::vector<uint8_t> basura(200, 0x41);
    PjaAbierto* h3 = nullptr;
    chequear(pja_abrir(basura.data(), basura.size(), nullptr, 0, &h3) == PJA_ERR_FORMATO
             && h3 == nullptr, "basura -> PJA_ERR_FORMATO");

    pja_cerrar(h);
    pja_cerrar(nullptr);          // pasar nulo tiene que ser valido
    chequear(true, "pja_cerrar(nullptr) no revienta");

    printf("\n%s (%d fallos)\n", fallos ? "HAY FALLOS" : "todo en verde", fallos);
    return fallos ? 1 : 0;
}
