// Diferencial de la FRONTERA: el mismo programa C++ se enlaza dos veces, contra
// libpjaffi.a (Rust) y contra libpjaffi_pas.a (Pascal), y las dos salidas tienen
// que ser iguales linea por linea.
//
//   dif_frontera <dir_pjg> <cifrado.pja> <contraseña>
//
// Ejercita toda la superficie de pjacore.h, caminos de error incluidos: nulos,
// buffers chicos, indices fuera de rango, entradas invalidas para escribir,
// contenedores alterados bit a bit y truncados, contraseña faltante, sobrante,
// vacia e incorrecta. Los resumenes de lo que sale se calculan ACA (FNV-1a), no
// con pja_hash128, que es parte de lo que se prueba.
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <dirent.h>
#include "pjacore.h"

typedef std::vector<uint8_t> B;
static uint64_t fnv(const uint8_t* p, size_t n) {
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ull; }
    return h;
}
static B leer(const std::string& ruta) {
    FILE* f = fopen(ruta.c_str(), "rb"); if (!f) return {};
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    B v(n); if (n && fread(v.data(), 1, n, f) != (size_t)n) v.clear(); fclose(f); return v;
}
static long lineas = 0;
#define OUT(...) do { printf(__VA_ARGS__); printf("\n"); lineas++; } while (0)

// Vuelca todo lo que se puede leer de un manejador, con sus errores.
static void volcar(const char* et, PjaAbierto* h) {
    int64_t n = pja_cantidad(h);
    std::string s = std::to_string(n);
    for (int64_t i = 0; i < n; i++) {
        int64_t ln = pja_nombre_largo(h, i), lp = pja_payload_largo(h, i);
        B nom(ln > 0 ? ln : 1), pay(lp > 0 ? lp : 1), hs(16);
        int32_t a = pja_nombre(h, i, nom.data(), ln > 0 ? ln : 0);
        int32_t b = pja_payload(h, i, pay.data(), lp > 0 ? lp : 0);
        int32_t c = pja_hash(h, i, hs.data(), 16);
        char t[160];
        snprintf(t, sizeof t, " [%lld %lld %d %d %d %016llx %016llx %016llx]", (long long)ln, (long long)lp, a, b, c,
                 (unsigned long long)fnv(nom.data(), ln > 0 ? ln : 0), (unsigned long long)fnv(pay.data(), lp > 0 ? lp : 0),
                 (unsigned long long)fnv(hs.data(), 16));
        s += t;
    }
    // y los bordes: indice n, buffers de menos, nulos
    B chico(3), h8(8), h16(16);
    char t[200];
    snprintf(t, sizeof t, " | rango %lld %lld %d %d %d | chico %d %d %d | nulo %d %d %d",
             (long long)pja_nombre_largo(h, n), (long long)pja_payload_largo(h, n),
             pja_nombre(h, n, chico.data(), 3), pja_payload(h, n, chico.data(), 3), pja_hash(h, n, h16.data(), 16),
             n > 0 ? pja_nombre(h, 0, chico.data(), 0) : 99, n > 0 ? pja_payload(h, 0, chico.data(), 2) : 99,
             pja_hash(h, 0, h8.data(), 8),
             pja_nombre(h, 0, nullptr, 10), pja_payload(h, 0, nullptr, 10), pja_hash(h, 0, nullptr, 16));
    s += t;
    OUT("%s %s", et, s.c_str());
}

static void abrir(const char* et, const B& d, const uint8_t* pass, size_t pl, bool volcar_si_ok = true) {
    PjaAbierto* h = (PjaAbierto*)0x1;   // tiene que quedar en nulo si falla
    int32_t rc = pja_abrir(d.empty() ? (const uint8_t*)"" : d.data(), d.size(), pass, pl, &h);
    if (rc == PJA_OK && volcar_si_ok) volcar(et, h);
    else OUT("%s rc=%d h=%s", et, rc, h == nullptr ? "nulo" : (rc == PJA_OK ? "ok" : "BASURA"));
    if (rc == PJA_OK) pja_cerrar(h);
}

// Recalcula hash_indice (BLAKE3-128 de cabecera[0..12) || indice) para que un
// dano adentro del indice llegue a las validaciones de los miembros en vez de
// cortar en IndiceAlterado. Usa pja_hash128, que las dos puntas ya comparan
// arriba por separado.
static bool resellar(B& c) {
    if (c.size() < 28) return false;
    uint32_t ti = c[8] | (c[9] << 8) | (c[10] << 16) | ((uint32_t)c[11] << 24);
    if (28 + (uint64_t)ti > c.size()) return false;
    B m(c.begin(), c.begin() + 12); m.insert(m.end(), c.begin() + 28, c.begin() + 28 + ti);
    return pja_hash128(m.data(), m.size(), &c[12], 16) == PJA_OK;
}
static size_t fin_indice(const B& c) {
    return c.size() < 28 ? 0 : 28 + (c[8] | (c[9] << 8) | (c[10] << 16) | ((size_t)c[11] << 24));
}

struct Ent { B nombre; B payload; uint8_t hash[16]; uint64_t tam; };
static std::vector<PjaEntradaC> c_de(std::vector<Ent>& es) {
    std::vector<PjaEntradaC> v;
    for (auto& e : es) {
        PjaEntradaC c; c.nombre = e.nombre.data(); c.nombre_largo = e.nombre.size();
        c.payload = e.payload.data(); c.payload_largo = e.payload.size();
        memcpy(c.hash, e.hash, 16); c.tam_orig = e.tam; v.push_back(c);
    }
    return v;
}
static B escribir(const char* et, std::vector<PjaEntradaC>& v, uint8_t flags) {
    int64_t n = pja_escribir_largo(v.data(), v.size(), flags);
    if (n < 0) { OUT("%s largo=%lld", et, (long long)n); return {}; }
    B out(n + 3, 0xEE), chico(n > 0 ? n - 1 : 1);
    int32_t rc = pja_escribir(v.data(), v.size(), flags, out.data(), out.size());
    int32_t rc2 = pja_escribir(v.data(), v.size(), flags, chico.data(), n > 0 ? n - 1 : 0);
    int32_t rc3 = pja_escribir(v.data(), v.size(), flags, nullptr, n);
    OUT("%s largo=%lld rc=%d chico=%d nulo=%d fnv=%016llx cola=%02x%02x%02x", et, (long long)n, rc, rc2, rc3,
        (unsigned long long)fnv(out.data(), n), out[n], out[n + 1], out[n + 2]);
    out.resize(n);
    return out;
}

int main(int argc, char** argv, char** envp) {
    if (argc != 4) { fprintf(stderr, "uso: dif_frontera <dir_pjg> <cifrado.pja> <contraseña>\n"); return 2; }
    if (pja_iniciar(argc, argv, envp) != PJA_OK) { fprintf(stderr, "pja_iniciar fallo\n"); return 1; }
    OUT("version=%u rango=%d init=%d", pja_version(), pja_rango_activo(), pja_inicializado());

    // .pjg reales, ordenados como en las otras pruebas
    std::vector<std::string> nombres;
    if (DIR* d = opendir(argv[1])) {
        while (dirent* e = readdir(d)) { std::string n = e->d_name; if (n.size() > 4 && n.substr(n.size() - 4) == ".pjg") nombres.push_back(n); }
        closedir(d);
    }
    std::sort(nombres.begin(), nombres.end());
    if (nombres.size() < 8) { fprintf(stderr, "hacen falta 8 .pjg\n"); return 2; }
    std::vector<Ent> reales;
    for (auto& n : nombres) {
        Ent e; e.nombre.assign(n.begin(), n.end()); e.payload = leer(std::string(argv[1]) + "/" + n);
        for (int k = 0; k < 16; k++) e.hash[k] = (uint8_t)(e.payload.size() * 7 + k);
        e.tam = 0; reales.push_back(e);
    }

    // --- pja_hash128 ---
    {
        uint8_t h[16], h2[8]; B d(1000); for (size_t i = 0; i < d.size(); i++) d[i] = (uint8_t)(i * 13);
        for (size_t n : {0u, 1u, 63u, 64u, 65u, 1000u}) {
            int32_t rc = pja_hash128(n ? d.data() : nullptr, n, h, 16);
            OUT("hash128 n=%zu rc=%d %016llx", n, rc, (unsigned long long)fnv(h, 16));
        }
        OUT("hash128 bordes %d %d %d %d", pja_hash128(nullptr, 5, h, 16), pja_hash128(d.data(), 5, nullptr, 16),
            pja_hash128(d.data(), 5, h2, 8), pja_hash128(d.data(), 0, h, 16));
    }

    // --- nulos en el manejador ---
    {
        uint8_t b[16];
        OUT("nulos %lld %lld %d %lld %d %d", (long long)pja_cantidad(nullptr), (long long)pja_nombre_largo(nullptr, 0),
            pja_nombre(nullptr, 0, b, 16), (long long)pja_payload_largo(nullptr, 0), pja_payload(nullptr, 0, b, 16),
            pja_hash(nullptr, 0, b, 16));
        PjaAbierto* h = nullptr;
        OUT("abrir nulos %d %d", pja_abrir(nullptr, 10, nullptr, 0, &h), pja_abrir(b, 16, nullptr, 0, nullptr));
        pja_cerrar(nullptr);
    }

    // --- escribir: conjuntos validos e invalidos ---
    std::vector<B> contenedores;
    {
        std::vector<PjaEntradaC> vacio;
        OUT("escribir n=0 lista nula %lld", (long long)pja_escribir_largo(nullptr, 0, 0));
        OUT("escribir n=3 lista nula %lld %d", (long long)pja_escribir_largo(nullptr, 3, 0),
            pja_escribir(nullptr, 3, 0, (uint8_t*)"x", 1));
        contenedores.push_back(escribir("vacio", vacio, 0));
        for (size_t k = 1; k <= reales.size(); k++) {
            std::vector<Ent> es(reales.begin(), reales.begin() + k);
            auto v = c_de(es);
            contenedores.push_back(escribir(("k" + std::to_string(k)).c_str(), v, 0));
        }
        for (int fl = 0; fl < 256; fl++) {
            std::vector<Ent> es(reales.begin(), reales.begin() + 2);
            auto v = c_de(es);
            B c = escribir(("flags" + std::to_string(fl)).c_str(), v, (uint8_t)fl);
            if (!c.empty() && fl < 8) contenedores.push_back(c);
        }
        const char* noms[] = {"a.jpg", "", "../x.jpg", "/abs.jpg", "a/b.jpg", "CON.jpg", "foto?.jpg", "a:b",
                              "con\x01trol", "\xff\xfe", "C:x", "a//b", "a/./b", "dup.jpg"};
        for (const char* nm : noms) for (int fl : {0, 2}) {
            std::vector<Ent> es(reales.begin(), reales.begin() + 2);
            es[0].nombre.assign(nm, nm + strlen(nm));
            if (std::string(nm) == "dup.jpg") es[1].nombre = es[0].nombre;
            auto v = c_de(es);
            B c = escribir(("nombre[" + std::string(nm) + "]" + std::to_string(fl)).c_str(), v, (uint8_t)fl);
            if (!c.empty()) contenedores.push_back(c);
        }
        for (uint64_t tam : {0ull, 1ull, 11ull, 12ull, 1000000ull, 8ull << 30, (8ull << 30) + 1, ~0ull}) {
            std::vector<Ent> es(reales.begin(), reales.begin() + 3);
            es[1].tam = tam;
            auto v = c_de(es);
            escribir(("tam" + std::to_string(tam)).c_str(), v, 0);
        }
        for (size_t pl : {0u, 1u, 11u, 12u, 13u}) {
            std::vector<Ent> es(reales.begin(), reales.begin() + 2);
            es[0].payload.resize(pl);
            auto v = c_de(es);
            escribir(("payload" + std::to_string(pl)).c_str(), v, 0);
        }
        {   // punteros nulos adentro de una entrada
            std::vector<Ent> es(reales.begin(), reales.begin() + 2);
            auto v = c_de(es); v[1].nombre = nullptr;
            OUT("entrada nombre nulo %lld", (long long)pja_escribir_largo(v.data(), v.size(), 0));
            v = c_de(es); v[0].payload = nullptr;
            OUT("entrada payload nulo %lld", (long long)pja_escribir_largo(v.data(), v.size(), 0));
        }
    }

    // --- abrir lo escrito, y alterado ---
    for (size_t ci = 0; ci < contenedores.size(); ci++) {
        const B& c = contenedores[ci];
        std::string et = "c" + std::to_string(ci);
        abrir((et + " intacto").c_str(), c, nullptr, 0);
        abrir((et + " pass_sobrante").c_str(), c, (const uint8_t*)"x", 1);
        abrir((et + " pass_vacia").c_str(), c, (const uint8_t*)"", 0);
        if (ci % 4 != 1) continue;        // el barrido completo, en uno de cada cuatro
        for (size_t p = 0; p < c.size() && p < 600; p++)
            for (int bit : {0, 5}) { B d = c; d[p] ^= (uint8_t)(1 << bit); abrir((et + " x" + std::to_string(p) + "." + std::to_string(bit)).c_str(), d, nullptr, 0, false); }
        for (size_t k = 0; k < c.size(); k += 1 + c.size() / 300) { B d(c.begin(), c.begin() + k); abrir((et + " t" + std::to_string(k)).c_str(), d, nullptr, 0, false); }
        B d = c; d.push_back(0); abrir((et + " +1").c_str(), d, nullptr, 0, false);
        // el indice, danado y RESELLADO: llega a las validaciones de cada miembro
        for (size_t p = 28; p < fin_indice(c) && p < c.size(); p++)
            for (int bit : {0, 3, 7}) {
                B r = c; r[p] ^= (uint8_t)(1 << bit);
                if (resellar(r)) abrir((et + " r" + std::to_string(p) + "." + std::to_string(bit)).c_str(), r, nullptr, 0, false);
            }
    }

    // --- nombres que el escritor nunca produce, armados a mano y resellados ---
    {
        std::vector<Ent> es(reales.begin(), reales.begin() + 3);
        es[0].nombre = {'a', '.', 'j', 'p', 'g'}; es[1].nombre = {'b', '.', 'j', 'p', 'g'}; es[2].nombre = {'c', '.', 'j', 'p', 'g'};
        for (int fl : {0, 2}) {
            auto v = c_de(es);
            B c = escribir(("aman" + std::to_string(fl)).c_str(), v, (uint8_t)fl);
            if (c.empty()) continue;
            // posiciones de los nombres en el indice: 28+4 (count) y despues
            // cada entrada es nlen(2) + nombre + 8 + 8 + 16 + 1
            size_t p0 = 28 + 4 + 2, p1 = p0 + 5 + 33 + 2, p2 = p1 + 5 + 33 + 2;
            struct { const char* et; size_t pos; const char* nuevo; } casos[] = {
                {"dup01", p1, "a.jpg"}, {"dup02", p2, "a.jpg"}, {"dup12", p2, "b.jpg"},
                {"padre", p0, "../ab"}, {"abs", p1, "/b.jp"}, {"barra", p1, "b/jpg"},
                {"ctrl", p2, "c\x01jpg"}, {"dospts", p0, "a:jpg"}, {"CON", p0, "CON.j"},
                {"vacio_no", p0, "     "}, {"punto", p1, "b.jp."}, {"utf8", p2, "\xff\xfejpg"},
            };
            for (auto& k : casos) {
                B r = c; memcpy(&r[k.pos], k.nuevo, 5);
                if (resellar(r)) abrir(("aman" + std::to_string(fl) + " " + k.et).c_str(), r, nullptr, 0);
            }
        }
    }

    // --- cifrado (cada apertura deriva con Argon2id: pocas) ---
    B cif = leer(argv[2]);
    const uint8_t* pw = (const uint8_t*)argv[3]; size_t pwl = strlen(argv[3]);
    abrir("cif buena", cif, pw, pwl);
    abrir("cif sin pass", cif, nullptr, 0);
    abrir("cif vacia", cif, (const uint8_t*)"", 0);
    abrir("cif mala", cif, (const uint8_t*)"secreta124", 10);
    for (size_t p : {0u, 5u, 6u, 7u, 8u, 12u, 27u, 28u, 40u, 43u, 44u, 67u, 68u, 100u, 5000u})
        if (p < cif.size()) { B d = cif; d[p] ^= 1; abrir(("cif x" + std::to_string(p)).c_str(), d, pw, pwl, false); }
    for (size_t k : {0u, 27u, 28u, 67u, 68u, 69u, 100u}) { B d(cif.begin(), cif.begin() + std::min(k, cif.size())); abrir(("cif t" + std::to_string(k)).c_str(), d, pw, pwl, false); }
    { B d(cif.begin(), cif.end() - 1); abrir("cif t-1", d, pw, pwl, false); }

    pja_terminar();
    fprintf(stderr, "%ld lineas\n", lineas);
    return 0;
}
