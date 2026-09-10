// Ejercita la frontera desde C++ como la usaria packJPG, incluidos los
// caminos de error. No prueba el nucleo -- eso ya esta probado en Rust --
// prueba que el CONTRATO se respete desde el otro lado.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include "mjgcore.h"

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
    printf("version del nucleo: %u\n", mjg_version());
    if (argc < 2) { printf("uso: frontera <contenedor.pjg> [contraseña]\n"); return 2; }

    std::vector<uint8_t> datos = leer(argv[1]);
    chequear(!datos.empty(), "el contenedor de prueba se leyo");

    const uint8_t* pass = nullptr; size_t pass_largo = 0;
    if (argc >= 3) { pass = (const uint8_t*)argv[2]; pass_largo = strlen(argv[2]); }

    MjgAbierto* h = nullptr;
    int32_t rc = mjg_abrir(datos.data(), datos.size(), pass, pass_largo, &h);
    chequear(rc == MJG_OK && h != nullptr, "mjg_abrir devuelve OK y un manejador");
    if (rc != MJG_OK) return 1;

    int64_t n = mjg_cantidad(h);
    chequear(n > 0, "mjg_cantidad > 0");

    // Camino normal: preguntar largo, reservar, copiar.
    bool todos = true;
    for (int64_t i = 0; i < n; i++) {
        int64_t ln = mjg_nombre_largo(h, i);
        int64_t lp = mjg_payload_largo(h, i);
        if (ln <= 0 || lp <= 0) { todos = false; break; }
        std::vector<uint8_t> nombre(ln), payload(lp), hash(16), calc(16);
        if (mjg_nombre(h, i, nombre.data(), nombre.size()) != MJG_OK) { todos = false; break; }
        if (mjg_payload(h, i, payload.data(), payload.size()) != MJG_OK) { todos = false; break; }
        if (mjg_hash(h, i, hash.data(), hash.size()) != MJG_OK) { todos = false; break; }
        // El hash declarado es del JPEG original; sobre el payload .pjg no
        // tiene por que coincidir. Lo que si se verifica es que mjg_hash128
        // sea determinista y no toque el buffer de entrada.
        if (mjg_hash128(payload.data(), payload.size(), calc.data(), calc.size()) != MJG_OK)
            { todos = false; break; }
        std::vector<uint8_t> calc2(16);
        mjg_hash128(payload.data(), payload.size(), calc2.data(), calc2.size());
        if (calc != calc2) { todos = false; break; }
    }
    chequear(todos, "nombre, payload y hash de cada miembro");

    // Caminos de error: cada uno tiene que dar SU codigo, no un exito casual.
    std::vector<uint8_t> chico(4);
    chequear(mjg_nombre(h, 0, chico.data(), chico.size()) == MJG_ERR_BUF_CHICO,
             "buffer chico -> MJG_ERR_BUF_CHICO");
    chequear(mjg_nombre_largo(h, 99999) == MJG_ERR_RANGO,
             "indice fuera de rango -> MJG_ERR_RANGO");
    chequear(mjg_payload(h, 0, nullptr, 100) == MJG_ERR_NULL,
             "buffer nulo -> MJG_ERR_NULL");
    std::vector<uint8_t> h8(8);
    chequear(mjg_hash(h, 0, h8.data(), h8.size()) == MJG_ERR_BUF_CHICO,
             "hash con buffer de 8 -> MJG_ERR_BUF_CHICO");

    // Un byte alterado en la cabecera no debe abrir.
    std::vector<uint8_t> roto = datos;
    roto[5] ^= 1;
    MjgAbierto* h2 = nullptr;
    int32_t rc2 = mjg_abrir(roto.data(), roto.size(), pass, pass_largo, &h2);
    chequear(rc2 != MJG_OK && h2 == nullptr, "un bit en flags -> no abre y no deja manejador");

    // Basura no abre.
    std::vector<uint8_t> basura(200, 0x41);
    MjgAbierto* h3 = nullptr;
    chequear(mjg_abrir(basura.data(), basura.size(), nullptr, 0, &h3) == MJG_ERR_FORMATO
             && h3 == nullptr, "basura -> MJG_ERR_FORMATO");

    mjg_cerrar(h);
    mjg_cerrar(nullptr);          // pasar nulo tiene que ser valido
    chequear(true, "mjg_cerrar(nullptr) no revienta");

    printf("\n%s (%d fallos)\n", fallos ? "HAY FALLOS" : "todo en verde", fallos);
    return fallos ? 1 : 0;
}
