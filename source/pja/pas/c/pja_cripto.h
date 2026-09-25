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
#endif
