/* mjgcore.h — frontera C++ <-> Rust del contenedor MJG.
 *
 * Contrato, deliberadamente angosto:
 *   - entra puntero + largo, sale un codigo de estado; 0 es exito
 *   - NINGUNA propiedad de memoria cruza el borde: los buffers los provee
 *     el llamador, y el unico objeto con estado es un manejador opaco con
 *     su abrir/cerrar
 *   - los `*_largo` existen para preguntar el tamaño ANTES de reservar
 *   - el lado Rust compila con panic = "abort": un panic que desenrollara
 *     hacia C++ seria comportamiento indefinido
 *   - Rust y C++ comparten un solo heap (el asignador de Rust usa malloc)
 */
#ifndef MJGCORE_H
#define MJGCORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define MJG_OK              0
#define MJG_ERR_NULL       -1
#define MJG_ERR_BUF_CHICO  -2
#define MJG_ERR_FORMATO    -3
#define MJG_ERR_LIMITE     -4   /* alguno de los seis limites de POLITICA.md */
#define MJG_ERR_NOMBRE     -5
#define MJG_ERR_CLAVE      -6   /* contraseña incorrecta, faltante o sobrante */
#define MJG_ERR_INDICE     -7   /* cabecera o indice alterados */
#define MJG_ERR_RANGO      -8

typedef struct MjgAbierto MjgAbierto;

/* Abre un contenedor en memoria. `pass` puede ser NULL si no esta cifrado.
 * Al volver MJG_OK, `*salida` debe liberarse con mjg_cerrar. */
int32_t mjg_abrir(const uint8_t* datos, size_t largo,
                  const uint8_t* pass, size_t pass_largo,
                  MjgAbierto** salida);
void    mjg_cerrar(MjgAbierto* h);

int64_t mjg_cantidad(const MjgAbierto* h);
int64_t mjg_nombre_largo(const MjgAbierto* h, size_t i);
/* No agrega NUL: un nombre puede llevar cualquier byte salvo los de control,
 * y un NUL implicito escondería un truncamiento. */
int32_t mjg_nombre(const MjgAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);
int64_t mjg_payload_largo(const MjgAbierto* h, size_t i);
int32_t mjg_payload(const MjgAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);
int32_t mjg_hash(const MjgAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);

/* BLAKE3-128 de un buffer, para verificar contra mjg_hash tras decodificar. */
int32_t mjg_hash128(const uint8_t* datos, size_t largo, uint8_t* buf, size_t buf_largo);

/* --- escritura --- */
typedef struct {
    const uint8_t* nombre;
    size_t         nombre_largo;
    const uint8_t* payload;
    size_t         payload_largo;
    uint8_t        hash[16];
    /* Tamaño del JPEG original; 0 = usar el del payload. */
    uint64_t       tam_orig;
} MjgEntradaC;

/* Cuantos bytes ocupa el contenedor. Valida todo: si da error, mjg_escribir
   va a dar el mismo. */
int64_t mjg_escribir_largo(const MjgEntradaC* ents, size_t n, uint8_t flags);
int32_t mjg_escribir(const MjgEntradaC* ents, size_t n, uint8_t flags,
                     uint8_t* buf, size_t buf_largo);

uint32_t mjg_version(void);

#ifdef __cplusplus
}
#endif
#endif
