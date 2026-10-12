/* pja_inicio.c — arranque del runtime de FreePascal cuando la capa Pascal va
 * ENLAZADA ESTATICAMENTE adentro de un ejecutable C/C++ (Linux).
 *
 * Una libreria de FPC espera que su runtime lo arranque el cargador
 * (-init FPC_SHARED_LIB_START en una .so, DllMain en Windows). Metida en el
 * ejecutable no hay cargador que lo haga, y lo medido en el spike de enlace
 * (fpc-link/RESULTADOS.md) es que SIN esto el camino normal anda igual pero
 * la proteccion de rango se apaga en silencio y los hilos revientan. Por eso
 * cada funcion exportada devuelve PJA_ERR_NO_INIT hasta que esto corra.
 *
 * En Windows la capa va como DLL y pja_iniciar/pja_terminar los exporta la
 * propia DLL: este archivo no se compila alla. */
#include <stdint.h>
#include "pjacore.h"

extern void FPC_SHARED_LIB_START(int argc, char** argv, char** envp);
extern void FPC_LIB_EXIT(void);
extern int32_t pja_iniciar_pascal(void);

static int arrancado = 0;

int32_t pja_iniciar(int argc, char** argv, char** envp) {
    if (!arrancado) {
        arrancado = 1;
        FPC_SHARED_LIB_START(argc, argv, envp);
    }
    return pja_iniciar_pascal();
}

void pja_terminar(void) {
    if (arrancado) {
        arrancado = 0;
        FPC_LIB_EXIT();
    }
}
