/* pjacore.h — frontera C++ <-> nucleo del contenedor PJA (Pascal; Rust hasta
 * que el port termine, con la misma interfaz).
 *
 * Contrato, deliberadamente angosto:
 *   - entra puntero + largo, sale un codigo de estado; 0 es exito
 *   - NINGUNA propiedad de memoria cruza el borde: los buffers los provee
 *     el llamador, y el unico objeto con estado es un manejador opaco con
 *     su abrir/cerrar
 *   - los `*_largo` existen para preguntar el tamaño ANTES de reservar
 *   - ninguna excepcion cruza el borde: un defecto interno vuelve como
 *     PJA_ERR_INTERNO (el lado Rust abortaba el proceso)
 *   - ANTES de cualquier otra llamada, pja_iniciar(argc, argv, envp) al
 *     principio de main; pja_terminar() al final. Enlazada estatica (Linux),
 *     sin pja_iniciar todo devuelve PJA_ERR_NO_INIT: sin runtime la
 *     proteccion de rango del lado Pascal se apaga en silencio, y eso no
 *     puede pasar callado. En la DLL (Windows) el runtime arranca al
 *     cargarla y pja_iniciar solo lo confirma.
 */
#ifndef PJACORE_H
#define PJACORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define PJA_OK              0
#define PJA_ERR_NULL       -1
#define PJA_ERR_BUF_CHICO  -2
#define PJA_ERR_FORMATO    -3
#define PJA_ERR_LIMITE     -4   /* alguno de los seis limites de POLITICA.md */
#define PJA_ERR_NOMBRE     -5
#define PJA_ERR_CLAVE      -6   /* contraseña incorrecta, faltante o sobrante */
#define PJA_ERR_INDICE     -7   /* cabecera o indice alterados */
#define PJA_ERR_RANGO      -8
#define PJA_ERR_INTERNO    -9   /* defecto nuestro: una excepcion adentro */
#define PJA_ERR_NO_INIT   -10   /* falto pja_iniciar */

int32_t pja_iniciar(int argc, char** argv, char** envp);
void    pja_terminar(void);
/* 1 si el runtime esta arrancado. */
int32_t pja_inicializado(void);
/* 1 si el nucleo se compilo con control de rango. Una prueba que no lo mire
 * podria pasar con la red apagada. */
int32_t pja_rango_activo(void);

typedef struct PjaAbierto PjaAbierto;

/* Abre un contenedor en memoria. `pass` puede ser NULL si no esta cifrado.
 * Al volver PJA_OK, `*salida` debe liberarse con pja_cerrar. */
int32_t pja_abrir(const uint8_t* datos, size_t largo,
                  const uint8_t* pass, size_t pass_largo,
                  PjaAbierto** salida);
void    pja_cerrar(PjaAbierto* h);

int64_t pja_cantidad(const PjaAbierto* h);
int64_t pja_nombre_largo(const PjaAbierto* h, size_t i);
/* No agrega NUL: un nombre puede llevar cualquier byte salvo los de control,
 * y un NUL implicito escondería un truncamiento. */
int32_t pja_nombre(const PjaAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);
int64_t pja_payload_largo(const PjaAbierto* h, size_t i);
int32_t pja_payload(const PjaAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);
int32_t pja_hash(const PjaAbierto* h, size_t i, uint8_t* buf, size_t buf_largo);

/* BLAKE3-128 de un buffer, para verificar contra pja_hash tras decodificar. */
int32_t pja_hash128(const uint8_t* datos, size_t largo, uint8_t* buf, size_t buf_largo);

/* --- escritura --- */
typedef struct {
    const uint8_t* nombre;
    size_t         nombre_largo;
    const uint8_t* payload;
    size_t         payload_largo;
    uint8_t        hash[16];
    /* Tamaño del JPEG original; 0 = usar el del payload. */
    uint64_t       tam_orig;
} PjaEntradaC;

/* Cuantos bytes ocupa el contenedor. Valida todo: si da error, pja_escribir
   va a dar el mismo. */
int64_t pja_escribir_largo(const PjaEntradaC* ents, size_t n, uint8_t flags);
int32_t pja_escribir(const PjaEntradaC* ents, size_t n, uint8_t flags,
                     uint8_t* buf, size_t buf_largo);

uint32_t pja_version(void);

#ifdef __cplusplus
}
#endif
#endif
