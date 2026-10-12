// pjatool — el formato .pja punta a punta con packJPG, via las dos librerias.
//
// No toca el codec ni el CLI del repo: usa pjglib_convert_stream2mem para
// comprimir y descomprimir en memoria, y pjacore para el formato. Es lo que
// el CLI va a hacer al engancharse, y la prueba de que el orden es el bueno:
//
//   comprimir:  JPEG -> hash y tamaño -> .pjg -> .pja
//   extraer:    .pja -> (autenticar) -> tope = tam_orig -> .pjg -> JPEG
//               -> el JPEG mide tam_orig y tiene el hash -> recien ahi se escribe
//
//   pjatool a <foto.jpg> <salida.pja> [contraseña]
//   pjatool x <archivo.pja> <salida.jpg> [contraseña]
//   pjatool corrupcion <foto.jpg> <n>   n bits al azar sobre un .pja sin cifrar:
//                                       ninguno puede terminar en un JPEG distinto
//                                       entregado como bueno
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include "packjpglib.h"
#include "pjacore.h"

static std::vector<uint8_t> leer(const std::string& r) {
    FILE* f = fopen(r.c_str(), "rb");
    if (!f) return {};
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> v(n);
    if (n && fread(v.data(), 1, n, f) != (size_t)n) v.clear();
    fclose(f); return v;
}
static bool escribir(const std::string& r, const std::vector<uint8_t>& d) {
    FILE* f = fopen(r.c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(d.data(), 1, d.size(), f) == d.size();
    return fclose(f) == 0 && ok;
}

// Convierte en memoria con la libreria (JPEG <-> .pjg, segun lo que entre).
// Devuelve vacio si falla.
static std::vector<uint8_t> convertir(std::vector<uint8_t>& entrada, std::string& err) {
    unsigned char* salida = nullptr; unsigned int n = 0;
    char msg[PJG_MSG_SIZE] = {0};
    pjglib_init_streams(entrada.data(), 1, (int)entrada.size(), nullptr, 1);
    // El puntero se reinicializa antes de cada llamada: si la conversion falla,
    // la libreria NO escribe los parametros de salida y quedaria el de la
    // vuelta anterior, ya liberado.
    if (!pjglib_convert_stream2mem(&salida, &n, msg) || !salida) {
        err = msg[0] ? msg : "conversion fallida";
        return {};
    }
    std::vector<uint8_t> v(salida, salida + n);
    free(salida);
    return v;
}

// JPEG -> .pja. Vacio si falla.
static std::vector<uint8_t> comprimir(std::vector<uint8_t>& jpg, const char* pass, std::string& err) {
    uint8_t h[16];
    pja_hash128(jpg.data(), jpg.size(), h, sizeof h);
    std::vector<uint8_t> pjg = convertir(jpg, err);
    if (pjg.empty()) return {};
    int64_t n = pja_escribir_largo(pjg.size(), pass != nullptr);
    if (n < 0) { err = "pja_escribir_largo: " + std::to_string(n); return {}; }
    std::vector<uint8_t> out(n);
    int32_t rc = pja_escribir(pjg.data(), pjg.size(), h, jpg.size(),
                              (const uint8_t*)pass, pass ? strlen(pass) : 0, out.data(), out.size());
    if (rc != PJA_OK) { err = "pja_escribir: " + std::to_string(rc); return {}; }
    return out;
}

enum Desenlace { BIEN, RECHAZO_PJA, RECHAZO_CODEC, NO_VERIFICA };
static const char* NOMBRE[] = { "bien", "rechazado por el formato", "rechazado por el codec",
                                "decodifico, pero no verifica" };

// .pja -> JPEG verificado. Solo BIEN deja algo en `jpg`.
static Desenlace extraer(const std::vector<uint8_t>& pja, const char* pass,
                         std::vector<uint8_t>& jpg, std::string& err) {
    jpg.clear();
    PjaAbierto* h = nullptr;
    int32_t rc = pja_abrir(pja.data(), pja.size(), (const uint8_t*)pass, pass ? strlen(pass) : 0, &h);
    if (rc != PJA_OK) { err = "pja_abrir: " + std::to_string(rc); return RECHAZO_PJA; }
    int64_t tam = pja_tam_orig(h);
    std::vector<uint8_t> pjg(pja_payload_largo(h));
    uint8_t decl[16];
    pja_payload(h, pjg.data(), pjg.size());
    pja_hash(h, decl, sizeof decl);
    pja_cerrar(h);

    // El tamaño declarado es el tope del decodificador: una bomba no llega a
    // reservar mas de lo que el archivo dijo. Y un tam_orig por encima del
    // tope del usuario se rechazaria aca, antes de decodificar.
    unsigned int previo = pjglib_get_max_output_size();
    pjglib_set_max_output_size(tam > 0xFFFFFFFFll ? 0xFFFFFFFFu : (unsigned int)tam);
    std::vector<uint8_t> salida = convertir(pjg, err);
    pjglib_set_max_output_size(previo);
    if (salida.empty()) return RECHAZO_CODEC;

    // El hash es del JPEG ORIGINAL: verifica lo que el programa promete --que
    // la reconstruccion sea identica-- y no un proxy. Sin esto, un .pjg
    // alterado puede decodificar a OTRO JPEG valido sin que nada lo note.
    uint8_t calc[16];
    pja_hash128(salida.data(), salida.size(), calc, sizeof calc);
    if ((int64_t)salida.size() != tam || memcmp(calc, decl, 16) != 0) {
        err = "el JPEG reconstruido no tiene el tamaño o el hash declarados";
        return NO_VERIFICA;
    }
    jpg.swap(salida);
    return BIEN;
}

static int cmd_a(const char* ent, const char* sal, const char* pass) {
    std::vector<uint8_t> jpg = leer(ent);
    if (jpg.empty()) { printf("no se pudo leer %s\n", ent); return 1; }
    std::string err;
    std::vector<uint8_t> pja = comprimir(jpg, pass, err);
    if (pja.empty()) { printf("%s: %s\n", ent, err.c_str()); return 1; }
    if (!escribir(sal, pja)) { printf("no se pudo escribir %s\n", sal); return 1; }
    printf("%s: %zu -> %zu bytes (%.1f%%)%s\n", ent, jpg.size(), pja.size(),
           100.0 * pja.size() / jpg.size(), pass ? ", cifrado" : "");
    return 0;
}

static int cmd_x(const char* ent, const char* sal, const char* pass) {
    std::vector<uint8_t> pja = leer(ent), jpg;
    if (pja.empty()) { printf("no se pudo leer %s\n", ent); return 1; }
    std::string err;
    Desenlace d = extraer(pja, pass, jpg, err);
    if (d != BIEN) { printf("%s: %s (%s)\n", ent, NOMBRE[d], err.c_str()); return 1; }
    if (!escribir(sal, jpg)) { printf("no se pudo escribir %s\n", sal); return 1; }
    printf("%s: %zu bytes, tamaño y hash verificados\n", sal, jpg.size());
    return 0;
}

// La propiedad que el formato promete, medida con el codec de verdad.
static int cmd_corrupcion(const char* ent, long n) {
    std::vector<uint8_t> jpg = leer(ent);
    std::string err;
    std::vector<uint8_t> pja = comprimir(jpg, nullptr, err), salida;
    if (pja.empty()) { printf("%s: %s\n", ent, err.c_str()); return 1; }
    if (extraer(pja, nullptr, salida, err) != BIEN || salida != jpg) { printf("control: no hace ida y vuelta\n"); return 1; }
    long cuenta[4] = {0, 0, 0, 0}, mal = 0;
    uint64_t x = 0x9E3779B97F4A7C15ull ^ pja.size();
    for (long k = 0; k < n; k++) {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;          // xorshift64, determinista
        size_t bit = x % (pja.size() * 8);
        std::vector<uint8_t> m = pja;
        m[bit / 8] ^= (uint8_t)(1u << (bit % 8));
        Desenlace d = extraer(m, nullptr, salida, err);
        cuenta[d]++;
        // BIEN con otra salida seria el agujero. BIEN con la misma salida es
        // un bit que el codec no usa (relleno del aritmetico): inofensivo.
        if (d == BIEN && salida != jpg) { mal++; printf("  MAL: bit %zu da un JPEG distinto entregado como bueno\n", bit); }
    }
    printf("%s: %ld bits volteados sobre %zu bytes\n", ent, n, pja.size());
    for (int d = 0; d < 4; d++) printf("  %-34s %ld\n", NOMBRE[d], cuenta[d]);
    printf("  %-34s %ld\n", "JPEG distinto entregado como bueno", mal);
    return mal ? 1 : 0;
}

static int principal(int argc, char** argv);

int main(int argc, char** argv, char** envp) {
    // El nucleo primero: sin esto, del lado Pascal todo da PJA_ERR_NO_INIT.
    if (int32_t r = pja_iniciar(argc, argv, envp); r != PJA_OK) {
        printf("pja_iniciar: %d\n", r);
        return 1;
    }
    int rc = principal(argc, argv);
    pja_terminar();
    return rc;
}

static int principal(int argc, char** argv) {
    if (argc < 4) {
        printf("uso:\n  pjatool a <foto.jpg> <salida.pja> [contraseña]\n"
               "  pjatool x <archivo.pja> <salida.jpg> [contraseña]\n"
               "  pjatool corrupcion <foto.jpg> <n>\n");
        return 2;
    }
    std::string cmd = argv[1];
    const char* pass = argc > 4 ? argv[4] : nullptr;
    if (cmd == "a") return cmd_a(argv[2], argv[3], pass);
    if (cmd == "x") return cmd_x(argv[2], argv[3], pass);
    if (cmd == "corrupcion") return cmd_corrupcion(argv[2], atol(argv[3]));
    printf("comando desconocido: %s\n", cmd.c_str());
    return 2;
}
