// Ejercita la frontera desde C++ como la usaria packJPG, incluidos los
// caminos de error. No prueba el nucleo -- eso lo prueban las pruebas Pascal
// -- prueba que el CONTRATO de pjacore.h se respete desde el otro lado: cada
// error con SU codigo, ningun manejador colgando, nada escrito fuera del
// buffer, y lo mismo desde 8 hilos.
//
//   test_frontera <archivo.pjg>     (un .pjg real, para el payload)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include "pjacore.h"

static int fallos = 0;
static void chequear(bool ok, const char* que) {
    printf("  %-60s %s\n", que, ok ? "ok" : "FALLA");
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

static const uint8_t* P(const char* s) { return (const uint8_t*)s; }

// Escribe un .pja; vacio si falla (y el codigo en *rc).
static std::vector<uint8_t> escribir(const std::vector<uint8_t>& pay, const uint8_t h[16], uint64_t tam,
                                     const char* pass, int32_t* rc) {
    int64_t n = pja_escribir_largo(pay.size(), pass != nullptr);
    if (n < 0) { *rc = (int32_t)n; return {}; }
    std::vector<uint8_t> out(n + 64, 0xEE);   // 64 de mas, para ver que no se escribe fuera
    *rc = pja_escribir(pay.data(), pay.size(), h, tam, P(pass), pass ? strlen(pass) : 0, out.data(), n);
    for (size_t i = n; i < out.size(); i++) if (out[i] != 0xEE) { *rc = 999; return {}; }
    if (*rc != PJA_OK) return {};
    out.resize(n);
    return out;
}

// Abre y devuelve el codigo; si abre, copia lo leido y cierra.
struct Leido { int64_t tam = -1; std::vector<uint8_t> pay; uint8_t h[16] = {0}; };
static int32_t abrir(const std::vector<uint8_t>& d, const char* pass, Leido* l, size_t pass_largo = (size_t)-1) {
    PjaAbierto* x = (PjaAbierto*)0x1;
    if (pass_largo == (size_t)-1) pass_largo = pass ? strlen(pass) : 0;
    int32_t rc = pja_abrir(d.data(), d.size(), P(pass), pass_largo, &x);
    if (rc != PJA_OK) { if (x != nullptr) return 998; return rc; }   // un error no deja manejador
    if (l) {
        l->tam = pja_tam_orig(x);
        l->pay.resize(pja_payload_largo(x));
        if (pja_payload(x, l->pay.data(), l->pay.size()) != PJA_OK) rc = 997;
        if (pja_hash(x, l->h, 16) != PJA_OK) rc = 996;
    }
    pja_cerrar(x);
    return rc;
}

int main(int argc, char** argv, char** envp) {
    // Antes de pja_iniciar, el lado Pascal enlazado estatico tiene que negarse
    // con su codigo, no andar a medias (sin runtime, $R+ se apaga en silencio).
    // En la DLL de Windows el runtime ya arranco al cargarla.
    bool sin_init_niega = pja_inicializado() == 1 || pja_tam_orig(nullptr) == PJA_ERR_NO_INIT;
    int32_t ri = pja_iniciar(argc, argv, envp);
    printf("version del formato: %u\n", pja_version());
    chequear(sin_init_niega, "antes de pja_iniciar: PJA_ERR_NO_INIT (o DLL ya iniciada)");
    chequear(ri == PJA_OK && pja_inicializado() == 1, "pja_iniciar -> OK, inicializado");
    chequear(pja_rango_activo() == 1, "el nucleo controla rangos");
    chequear(pja_version() == 2, "formato version 2");
    if (argc < 2) { printf("uso: test_frontera <archivo.pjg>\n"); return 2; }

    std::vector<uint8_t> pjg = leer(argv[1]);
    chequear(pjg.size() >= 12, "el .pjg de prueba se leyo");
    if (pjg.size() < 12) return 1;
    uint8_t h[16];
    chequear(pja_hash128(pjg.data(), pjg.size(), h, 16) == PJA_OK, "pja_hash128");
    const uint64_t tam = pjg.size() * 2;

    // --- sin cifrar
    int32_t rc;
    std::vector<uint8_t> claro = escribir(pjg, h, tam, nullptr, &rc);
    chequear(rc == PJA_OK, "escribir sin cifrar (sin tocar fuera del buffer)");
    chequear((int64_t)claro.size() == pja_escribir_largo(pjg.size(), 0), "  mide lo que anuncia pja_escribir_largo");
    Leido l;
    chequear(abrir(claro, nullptr, &l) == PJA_OK, "abrir sin cifrar");
    chequear(l.tam == (int64_t)tam && l.pay == pjg && memcmp(l.h, h, 16) == 0, "  tam_orig, payload y hash vuelven iguales");
    int32_t cif = 7;
    chequear(pja_examinar(claro.data(), claro.size(), &cif) == PJA_OK && cif == 0, "examinar: no pide contraseña");
    chequear(pja_examinar(claro.data(), 8, &cif) == PJA_OK && cif == 0, "examinar con solo los 8 bytes de cabecera");

    // --- cifrado: un .pjg real, y un payload de 3 trozos y pico
    std::vector<uint8_t> grande(3 * 65536 + 777);
    for (size_t i = 0; i < grande.size(); i++) grande[i] = (uint8_t)(i * 7 + i / 251);
    uint8_t hg[16]; pja_hash128(grande.data(), grande.size(), hg, 16);
    std::vector<uint8_t> c1 = escribir(pjg, h, tam, "secreta", &rc);
    chequear(rc == PJA_OK, "escribir cifrado");
    chequear((int64_t)c1.size() == pja_escribir_largo(pjg.size(), 1), "  mide lo que anuncia pja_escribir_largo");
    std::vector<uint8_t> cg = escribir(grande, hg, grande.size(), "secreta", &rc);
    chequear(rc == PJA_OK && (int64_t)cg.size() == pja_escribir_largo(grande.size(), 1), "escribir cifrado de 4 trozos");
    chequear(pja_examinar(c1.data(), c1.size(), &cif) == PJA_OK && cif == 1, "examinar: pide contraseña");
    chequear(abrir(c1, "secreta", &l) == PJA_OK && l.pay == pjg && l.tam == (int64_t)tam && memcmp(l.h, h, 16) == 0,
             "abrir con la contraseña: todo igual");
    chequear(abrir(cg, "secreta", &l) == PJA_OK && l.pay == grande, "abrir el de 4 trozos");
    chequear(abrir(c1, nullptr, nullptr) == PJA_ERR_CLAVE, "cifrado sin contraseña -> CLAVE");
    chequear(abrir(claro, "secreta", nullptr) == PJA_ERR_CLAVE, "sin cifrar con contraseña -> CLAVE");
    chequear(abrir(c1, "secretA", nullptr) == PJA_ERR_CLAVE, "contraseña equivocada -> CLAVE");
    std::vector<uint8_t> otro = escribir(pjg, h, tam, "secreta", &rc);
    chequear(rc == PJA_OK && otro != c1 && otro.size() == c1.size(), "dos cifrados iguales: bytes distintos (sal del sistema)");
    std::vector<uint8_t> cv = escribir(pjg, h, tam, "", &rc);
    chequear(rc == PJA_OK, "contraseña vacia (no nula) cifra");
    chequear(abrir(cv, "", nullptr) == PJA_OK, "  y abre con la vacia");
    chequear(abrir(cv, nullptr, nullptr) == PJA_ERR_CLAVE, "  y sin contraseña (nula), no");

    // --- alterados: cada uno con su codigo
    std::vector<uint8_t> x = cg; x[cg.size() - 30] ^= 1;
    chequear(abrir(x, "secreta", nullptr) == PJA_ERR_ALTERADO, "un bit en el ultimo trozo -> ALTERADO");
    x = cg; x[8 + 40 + 4 + 100] ^= 1;
    chequear(abrir(x, "secreta", nullptr) == PJA_ERR_CLAVE, "un bit en el primer trozo -> CLAVE (no se distingue)");
    x.assign(cg.begin(), cg.begin() + 8 + 40 + 2 * (4 + 65536 + 16));
    chequear(abrir(x, "secreta", nullptr) == PJA_ERR_ALTERADO, "cortado en un borde de trozo -> ALTERADO");
    x = cg; x.insert(x.end(), cg.end() - 20, cg.end());
    chequear(abrir(x, "secreta", nullptr) == PJA_ERR_ALTERADO, "el ultimo trozo repetido -> ALTERADO");
    x = claro; x[4] = 1;
    chequear(abrir(x, nullptr, nullptr) == PJA_ERR_FORMATO, "version 1 (el contenedor descartado) -> FORMATO");
    x = claro; x[5] ^= 2;
    chequear(abrir(x, nullptr, nullptr) == PJA_ERR_FORMATO, "un flag desconocido -> FORMATO");
    std::vector<uint8_t> basura(200, 0x41);
    chequear(abrir(basura, nullptr, nullptr) == PJA_ERR_FORMATO, "basura -> FORMATO");
    chequear(pja_examinar(basura.data(), basura.size(), &cif) == PJA_ERR_FORMATO, "examinar basura -> FORMATO");
    chequear(abrir(std::vector<uint8_t>(claro.begin(), claro.begin() + 30), nullptr, nullptr) == PJA_ERR_FORMATO,
             "sin cifrar, cortado en el descriptor -> FORMATO");
    chequear(abrir(std::vector<uint8_t>(claro.begin(), claro.begin() + 40), nullptr, nullptr) == PJA_ERR_LIMITE,
             "sin cifrar, con 8 B de payload -> LIMITE");
    x = claro; for (int i = 8; i < 16; i++) x[i] = 0;
    chequear(abrir(x, nullptr, nullptr) == PJA_ERR_LIMITE, "tam_orig 0 -> LIMITE");

    // --- el escritor rechaza lo mismo, con el mismo codigo
    std::vector<uint8_t> buf(pja_escribir_largo(pjg.size(), 1) + 64);
    chequear(pja_escribir(pjg.data(), pjg.size(), h, 0, nullptr, 0, buf.data(), buf.size()) == PJA_ERR_LIMITE,
             "escribir con tam_orig 0 -> LIMITE");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, 500 * (uint64_t)pjg.size() + 1, nullptr, 0, buf.data(), buf.size())
             == PJA_ERR_LIMITE, "escribir con mas de 500x -> LIMITE");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, 500 * (uint64_t)pjg.size(), nullptr, 0, buf.data(), buf.size())
             == PJA_OK, "  500x justo -> OK");
    chequear(pja_escribir(pjg.data(), 11, h, 100, nullptr, 0, buf.data(), buf.size()) == PJA_ERR_LIMITE,
             "escribir un payload de 11 B -> LIMITE");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, tam, nullptr, 0, buf.data(), pja_escribir_largo(pjg.size(), 0) - 1)
             == PJA_ERR_BUF_CHICO, "escribir en un buffer un byte chico -> BUF_CHICO");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, tam, P("x"), 1, buf.data(), pja_escribir_largo(pjg.size(), 1) - 1)
             == PJA_ERR_BUF_CHICO, "  y cifrado (antes de derivar)");

    // --- nulos y buffers chicos
    PjaAbierto* hh = nullptr;
    chequear(pja_abrir(c1.data(), c1.size(), P("secreta"), 7, &hh) == PJA_OK, "un manejador abierto");
    std::vector<uint8_t> chico(4);
    chequear(pja_payload(hh, chico.data(), chico.size()) == PJA_ERR_BUF_CHICO, "payload en buffer chico -> BUF_CHICO");
    chequear(pja_payload(hh, nullptr, 100000) == PJA_ERR_NULL, "payload en buffer nulo -> NULL");
    uint8_t h8[8];
    chequear(pja_hash(hh, h8, sizeof h8) == PJA_ERR_BUF_CHICO, "hash en buffer de 8 -> BUF_CHICO");
    chequear(pja_tam_orig(nullptr) == PJA_ERR_NULL && pja_payload_largo(nullptr) == PJA_ERR_NULL,
             "manejador nulo -> NULL");
    pja_cerrar(hh);
    chequear(pja_abrir(nullptr, 10, nullptr, 0, &hh) == PJA_ERR_NULL, "abrir datos nulos -> NULL");
    chequear(pja_abrir(claro.data(), claro.size(), nullptr, 0, nullptr) == PJA_ERR_NULL, "abrir sin salida -> NULL");
    chequear(pja_examinar(claro.data(), claro.size(), nullptr) == PJA_ERR_NULL, "examinar sin salida -> NULL");
    chequear(pja_examinar(nullptr, 0, &cif) == PJA_ERR_FORMATO, "examinar 0 bytes -> FORMATO");
    chequear(pja_hash128(nullptr, 5, h, 16) == PJA_ERR_NULL, "hash128 de datos nulos -> NULL");
    chequear(pja_hash128(pjg.data(), pjg.size(), h8, 8) == PJA_ERR_BUF_CHICO, "hash128 en buffer de 8 -> BUF_CHICO");
    chequear(pja_escribir(pjg.data(), pjg.size(), nullptr, tam, nullptr, 0, buf.data(), buf.size()) == PJA_ERR_NULL,
             "escribir sin hash -> NULL");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, tam, nullptr, 5, buf.data(), buf.size()) == PJA_ERR_NULL,
             "escribir con contraseña nula de largo 5 -> NULL");
    chequear(pja_escribir(pjg.data(), pjg.size(), h, tam, nullptr, 0, nullptr, 0) == PJA_ERR_NULL,
             "escribir sin buffer -> NULL");

    // Hilos del anfitrion llamando a la vez (el runtime de FPC: cthreads y el
    // heap compartido). Cada hilo abre, lee y cierra; todos tienen que ver
    // exactamente lo mismo que el hilo principal, y los errores tambien.
    {
        std::atomic<int> malas{0}, hechas{0};
        std::vector<std::thread> hs;
        for (int t = 0; t < 8; t++) hs.emplace_back([&] {
            Leido lt;
            for (int k = 0; k < 150; k++) {
                if (abrir(claro, nullptr, &lt) != PJA_OK || lt.pay != pjg || memcmp(lt.h, h, 16) != 0) malas++;
                if (abrir(basura, nullptr, nullptr) != PJA_ERR_FORMATO) malas++;
                hechas++;
            }
            // con contraseña cada apertura deriva Argon2id (64 MiB): una por hilo
            if (abrir(c1, "secreta", &lt) != PJA_OK || lt.pay != pjg) malas++;
        });
        for (auto& t : hs) t.join();
        char q[96]; snprintf(q, sizeof q, "8 hilos: %d aperturas, %d malas", hechas.load() + 8, malas.load());
        chequear(malas == 0 && hechas == 8 * 150, q);
    }

    pja_cerrar(nullptr);          // pasar nulo tiene que ser valido
    chequear(true, "pja_cerrar(nullptr) no revienta");

    printf("\n%s (%d fallos)\n", fallos ? "HAY FALLOS" : "todo en verde", fallos);
    pja_terminar();
    return fallos ? 1 : 0;
}
