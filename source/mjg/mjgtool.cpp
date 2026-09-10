// mjgtool — integracion del contenedor con packJPG, via la libreria.
//
// No toca el codec ni el CLI del repo: usa pjglib_convert_stream2mem para
// comprimir y descomprimir en memoria, y mjgcore para el contenedor. Es la
// demostracion punta a punta antes de tocar packjpg.cpp.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <array>
#include "packjpglib.h"
#include "mjgcore.h"

static std::vector<uint8_t> leer(const std::string& r) {
    FILE* f = fopen(r.c_str(), "rb");
    if (!f) return {};
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> v(n);
    if (n && fread(v.data(), 1, n, f) != (size_t)n) v.clear();
    fclose(f); return v;
}
static bool escribir(const std::string& r, const uint8_t* d, size_t n) {
    FILE* f = fopen(r.c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(d, 1, n, f) == n;
    fclose(f); return ok;
}
static std::string base(const std::string& r) {
    size_t i = r.find_last_of("/\\");
    return i == std::string::npos ? r : r.substr(i + 1);
}

// Convierte en memoria con la libreria. Devuelve vacio si falla.
static std::vector<uint8_t> convertir(std::vector<uint8_t>& entrada, std::string& err) {
    unsigned char* salida = nullptr; unsigned int n = 0;
    char msg[PJG_MSG_SIZE] = {0};
    pjglib_init_streams(entrada.data(), 1, (int)entrada.size(), nullptr, 1);
    // El puntero se reinicializa antes de cada llamada: si la conversion falla,
    // la libreria NO escribe los parametros de salida y quedaria el de la
    // vuelta anterior, ya liberado. Es el defecto 5 de los nueve medidos.
    if (!pjglib_convert_stream2mem(&salida, &n, msg) || !salida) {
        err = msg[0] ? msg : "conversion fallida";
        return {};
    }
    std::vector<uint8_t> v(salida, salida + n);
    free(salida);
    return v;
}

static int crear(const std::string& destino, const std::vector<std::string>& jpgs) {
    std::vector<std::vector<uint8_t>> payloads;
    std::vector<std::string> nombres;
    std::vector<std::array<uint8_t,16>> hashes;

    for (const auto& r : jpgs) {
        std::vector<uint8_t> jpg = leer(r);
        if (jpg.empty()) { printf("  %-28s no se pudo leer\n", base(r).c_str()); continue; }
        std::array<uint8_t,16> h{};
        mjg_hash128(jpg.data(), jpg.size(), h.data(), h.size());
        std::string err;
        std::vector<uint8_t> pjg = convertir(jpg, err);
        if (pjg.empty()) { printf("  %-28s %s\n", base(r).c_str(), err.c_str()); continue; }
        printf("  %-28s %8zu -> %8zu  (%.1f%%)\n", base(r).c_str(),
               jpg.size(), pjg.size(), 100.0 * pjg.size() / jpg.size());
        payloads.push_back(std::move(pjg));
        nombres.push_back(base(r));
        hashes.push_back(h);
    }
    if (payloads.empty()) { printf("nada que empaquetar\n"); return 1; }

    // El escritor del contenedor vive en Rust; se le pasan punteros con largo.
    std::vector<MjgEntradaC> ents(payloads.size());
    for (size_t i = 0; i < payloads.size(); i++) {
        ents[i].nombre = (const uint8_t*)nombres[i].data();
        ents[i].nombre_largo = nombres[i].size();
        ents[i].payload = payloads[i].data();
        ents[i].payload_largo = payloads[i].size();
        memcpy(ents[i].hash, hashes[i].data(), 16);
        ents[i].tam_orig = 0;
    }
    int64_t n = mjg_escribir_largo(ents.data(), ents.size(), 0);
    if (n < 0) { printf("mjg_escribir_largo: %ld\n", (long)n); return 1; }
    std::vector<uint8_t> out(n);
    int32_t rc = mjg_escribir(ents.data(), ents.size(), 0, out.data(), out.size());
    if (rc != MJG_OK) { printf("mjg_escribir: %d\n", rc); return 1; }
    if (!escribir(destino, out.data(), out.size())) { printf("no se pudo escribir\n"); return 1; }
    printf("\n%s: %zu miembros, %zu bytes\n", destino.c_str(), payloads.size(), out.size());
    return 0;
}

static int extraer(const std::string& origen, const std::string& dir) {
    std::vector<uint8_t> datos = leer(origen);
    if (datos.empty()) { printf("no se pudo leer %s\n", origen.c_str()); return 1; }
    MjgAbierto* h = nullptr;
    int32_t rc = mjg_abrir(datos.data(), datos.size(), nullptr, 0, &h);
    if (rc != MJG_OK) { printf("mjg_abrir: %d\n", rc); return 1; }

    int64_t n = mjg_cantidad(h);
    int malos = 0;
    for (int64_t i = 0; i < n; i++) {
        std::vector<uint8_t> nombre(mjg_nombre_largo(h, i));
        mjg_nombre(h, i, nombre.data(), nombre.size());
        std::string nom((const char*)nombre.data(), nombre.size());

        std::vector<uint8_t> pjg(mjg_payload_largo(h, i));
        mjg_payload(h, i, pjg.data(), pjg.size());

        std::string err;
        std::vector<uint8_t> jpg = convertir(pjg, err);
        if (jpg.empty()) { printf("  %-28s %s\n", nom.c_str(), err.c_str()); malos++; continue; }

        uint8_t decl[16], calc[16];
        mjg_hash(h, i, decl, sizeof decl);
        mjg_hash128(jpg.data(), jpg.size(), calc, sizeof calc);
        bool coincide = memcmp(decl, calc, 16) == 0;
        // El hash es del JPEG ORIGINAL: verifica lo que el programa promete
        // -- que la reconstruccion sea identica -- y no un proxy.
        printf("  %-28s %8zu bytes  hash %s\n", nom.c_str(), jpg.size(),
               coincide ? "coincide" : "NO COINCIDE");
        if (!coincide) malos++;
        std::string salida = dir + "/" + nom;
        if (!escribir(salida, jpg.data(), jpg.size())) { printf("    no se pudo escribir\n"); malos++; }
    }
    mjg_cerrar(h);
    printf("\n%ld miembros, %d con problemas\n", (long)n, malos);
    return malos ? 1 : 0;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("uso:\n  mjgtool crear  <salida.pjg> <foto.jpg>...\n"
               "  mjgtool extraer <contenedor.pjg> <directorio>\n");
        return 2;
    }
    std::string cmd = argv[1];
    if (cmd == "crear") {
        std::vector<std::string> jpgs(argv + 3, argv + argc);
        return crear(argv[2], jpgs);
    }
    if (cmd == "extraer") return extraer(argv[2], argc > 3 ? argv[3] : ".");
    printf("comando desconocido: %s\n", cmd.c_str());
    return 2;
}
