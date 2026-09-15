//! De dónde salen los `.pjg` reales que usan las pruebas.
//!
//! Antes esto era una constante con una ruta absoluta de la máquina de
//! desarrollo. Las 43 pruebas pasaban ahí y **no podían pasar en ningún otro
//! lado**: en un checkout limpio `read_dir` de esa ruta falla y toda prueba que
//! toque material real revienta. No se notó hasta que el contenedor entró a CI,
//! que es exactamente la clase de defecto que una suite sin CI acumula.
//!
//! Ahora la ruta sale de `PJA_CORPUS`, con un default relativo al repo. Y si no
//! hay material, la prueba **falla**; no se saltea. Una prueba que se saltea
//! cuando falta el corpus habría escondido este mismo problema: verde, cero
//! cobertura, nadie enterado.

use std::path::PathBuf;

/// Directorio con `.pjg` válidos. `PJA_CORPUS` lo pisa.
pub fn dir() -> PathBuf {
    if let Ok(p) = std::env::var("PJA_CORPUS") {
        return PathBuf::from(p);
    }
    // Default relativo al crate, no a la cwd: `cargo test` corre con la cwd en
    // el directorio del crate, pero un runner puede invocarlo de otro lado.
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../pruebas/corpus")
}

/// Los primeros `n` `.pjg` del corpus, ordenados. Falla con un mensaje que dice
/// qué hacer, en vez de con un `unwrap` pelado sobre `read_dir`.
pub fn pjgs(n: usize) -> Vec<PathBuf> {
    let d = dir();
    let entradas = std::fs::read_dir(&d).unwrap_or_else(|e| {
        panic!(
            "no puedo leer el corpus en {}: {e}\n\
             Las pruebas necesitan .pjg reales, comprimidos por el packJPG de\n\
             este arbol. Generalos con:\n\
             \x20 make -C source pja-corpus\n\
             O apunta PJA_CORPUS a un directorio propio con .pjg validos.",
            d.display()
        )
    });
    let mut r: Vec<PathBuf> = entradas
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map_or(false, |x| x == "pjg"))
        .collect();
    r.sort();
    assert!(
        r.len() >= n,
        "el corpus en {} tiene {} .pjg y esta prueba necesita {n}",
        d.display(),
        r.len()
    );
    r.truncate(n);
    r
}
