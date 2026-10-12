// Control: un anfitrion que se OLVIDA de pja_iniciar. Medido en el spike: sin
// runtime, el camino normal de FPC anda igual pero la proteccion de rango se
// apaga en silencio y los hilos revientan. La frontera tiene que convertir eso
// en PJA_ERR_NO_INIT en todas las funciones, desde cualquier hilo, sin crash.
// Solo tiene sentido contra el nucleo Pascal enlazado estatico.
#include <cstdio>
#include <thread>
#include <vector>
#include <atomic>
#include "pjacore.h"

static int todas(void) {
    uint8_t b[64] = {0};
    PjaAbierto* h = nullptr;
    int32_t cif = 7;
    int malas = 0;
    malas += pja_examinar(b, 64, &cif) != PJA_ERR_NO_INIT || cif != 7;
    malas += pja_abrir(b, 64, nullptr, 0, &h) != PJA_ERR_NO_INIT || h != nullptr;
    malas += pja_tam_orig((PjaAbierto*)b) != PJA_ERR_NO_INIT;      // ni siquiera mira el puntero
    malas += pja_payload_largo((PjaAbierto*)b) != PJA_ERR_NO_INIT;
    malas += pja_payload((PjaAbierto*)b, b, 64) != PJA_ERR_NO_INIT;
    malas += pja_hash((PjaAbierto*)b, b, 64) != PJA_ERR_NO_INIT;
    malas += pja_hash128(b, 64, b, 16) != PJA_ERR_NO_INIT;
    malas += pja_escribir_largo(20, 0) != PJA_ERR_NO_INIT;
    malas += pja_escribir(b, 20, b, 100, nullptr, 0, b, 64) != PJA_ERR_NO_INIT;
    malas += pja_escribir(b, 20, b, 100, b, 3, b, 64) != PJA_ERR_NO_INIT;
    malas += pja_guardar("x", 1, b, 4, b, 0, 0, &cif, &cif, nullptr, 0, nullptr) != PJA_ERR_NO_INIT;
    malas += pja_inicializado() != 0;
    pja_cerrar((PjaAbierto*)b);          // sin runtime no puede liberar nada: tiene que no tocarlo
    return malas;
}

int main() {
    int m = todas();
    std::atomic<int> mh{0};
    std::vector<std::thread> hs;
    for (int t = 0; t < 8; t++) hs.emplace_back([&] { for (int k = 0; k < 2000; k++) mh += todas(); });
    for (auto& t : hs) t.join();
    printf("sin pja_iniciar: %d malas en el hilo principal, %d en 8 hilos x 2000 rondas\n", m, mh.load());
    return (m || mh) ? 1 : 0;
}
