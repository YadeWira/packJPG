//! Extracción: la parte que toca el sistema de archivos.
//!
//! Va aparte del núcleo a propósito. `mjgcore` es `no_std` y no sabe de rutas
//! reales; acá vive lo que sólo se puede decidir contra el disco de destino —
//! resolver enlaces, verificar contención, y el límite de ruta de la plataforma,
//! que **no se puede chequear al crear** porque incluye el directorio destino.

use std::path::{Component, Path, PathBuf};

/// Límite de ruta completa de Windows sin opt-in explícito. Se aplica siempre,
/// no sólo compilando para Windows: un contenedor armado en Linux tiene que
/// poder avisar que va a ser inextraíble allá.
pub const MAX_PATH_WINDOWS: usize = 260;

#[derive(Debug, PartialEq, Eq)]
pub enum ErrorExtraccion {
    NombreInvalido,
    EscapaDelDestino,
    RutaMuyLargaParaWindows(usize),
    DestinoYaExiste,
    DestinoNoEsDirectorio,
}

/// Resuelve dónde va un miembro dentro de `destino`, o rechaza.
///
/// El orden importa: primero se valida el nombre con las reglas del núcleo,
/// después se arma la ruta, y **al final se verifica que lo resuelto siga
/// adentro**. Ese último paso es redundante con la validación y va igual: la
/// validación sola ya falló en archivadores conocidos.
pub fn destino_de(destino: &Path, nombre: &[u8], rutas: bool, sobrescribir: bool)
    -> Result<PathBuf, ErrorExtraccion>
{
    use mjgcore::nombres::{plano, ruta, Veredicto};
    let v = if rutas { ruta(nombre) } else { plano(nombre) };
    if let Veredicto::Rechazo(_) = v { return Err(ErrorExtraccion::NombreInvalido); }

    let s = std::str::from_utf8(nombre).map_err(|_| ErrorExtraccion::NombreInvalido)?;
    let candidato = destino.join(s);

    // Ningun componente puede ser `..` ni raiz, ni siquiera tras el join.
    for c in Path::new(s).components() {
        match c {
            Component::Normal(_) => {}
            _ => return Err(ErrorExtraccion::EscapaDelDestino),
        }
    }

    // Contencion real: se compara contra el destino YA resuelto, asi un enlace
    // simbolico que apunte afuera se detecta aunque el nombre sea impecable.
    let base = destino.canonicalize().map_err(|_| ErrorExtraccion::DestinoNoEsDirectorio)?;
    if !base.is_dir() { return Err(ErrorExtraccion::DestinoNoEsDirectorio); }

    let padre = candidato.parent().unwrap_or(&base);
    let padre_resuelto = match padre.canonicalize() {
        Ok(p) => p,
        // Si el padre no existe todavia, se resuelve el ancestro que si exista.
        Err(_) => {
            // Si el padre no existe todavia, se resuelve el ancestro mas
            // cercano que si exista: es contra ese que hay que verificar.
            let mut p = padre.to_path_buf();
            let resuelto = loop {
                match p.canonicalize() {
                    Ok(c) => break c,
                    Err(_) => match p.parent() {
                        Some(q) => p = q.to_path_buf(),
                        None => return Err(ErrorExtraccion::EscapaDelDestino),
                    },
                }
            };
            resuelto
        }
    };
    if !padre_resuelto.starts_with(&base) { return Err(ErrorExtraccion::EscapaDelDestino); }

    // Limite de Windows: se mide sobre la ruta RESUELTA, que es la unica que
    // se conoce recien acá. Se rechaza con mensaje; nunca se trunca.
    let largo = candidato.as_os_str().len();
    if largo > MAX_PATH_WINDOWS {
        return Err(ErrorExtraccion::RutaMuyLargaParaWindows(largo));
    }

    if candidato.exists() && !sobrescribir { return Err(ErrorExtraccion::DestinoYaExiste); }
    Ok(candidato)
}

// ---------------------------------------------------------------------------
// Batería 4.5 de `doc/FORMATO.md`. Necesita disco de verdad, por eso vive acá.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;
    use std::fs;

    fn temporal(nombre: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("mjgfs_{nombre}"));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test] fn control_positivo_un_nombre_normal_resuelve() {
        let d = temporal("ok");
        let r = destino_de(&d, b"foto.jpg", false, false).unwrap();
        assert_eq!(r.file_name().unwrap(), "foto.jpg");
        assert!(r.starts_with(d.canonicalize().unwrap()));
    }

    #[test] fn enlace_simbolico_que_sale_afuera_se_rechaza() {
        let d = temporal("symlink");
        let afuera = temporal("symlink_afuera");
        // Un subdirectorio del destino que en realidad apunta afuera.
        std::os::unix::fs::symlink(&afuera, d.join("sub")).unwrap();

        // El nombre es impecable: no tiene `..` ni nada raro.
        let r = destino_de(&d, b"sub/foto.jpg", true, false);
        assert_eq!(r, Err(ErrorExtraccion::EscapaDelDestino),
                   "un nombre valido sobre un enlace que sale afuera tiene que rechazarse");
    }

    #[test] fn enlace_simbolico_que_queda_adentro_se_acepta() {
        // El control negativo del anterior: si rechazara TODO enlace, la prueba
        // de arriba pasaria sin discriminar.
        let d = temporal("symlink_ok");
        fs::create_dir_all(d.join("real")).unwrap();
        std::os::unix::fs::symlink(d.join("real"), d.join("sub")).unwrap();
        let r = destino_de(&d, b"sub/foto.jpg", true, false);
        assert!(r.is_ok(), "un enlace que queda adentro tiene que aceptarse: {r:?}");
    }

    #[test] fn ruta_muy_larga_para_windows_se_rechaza_sin_truncar() {
        let d = temporal("largo");
        let nombre: String = "a".repeat(250) + ".jpg";
        match destino_de(&d, nombre.as_bytes(), false, false) {
            Err(ErrorExtraccion::RutaMuyLargaParaWindows(n)) => assert!(n > MAX_PATH_WINDOWS),
            otro => panic!("esperaba rechazo por largo, dio {otro:?}"),
        }
    }

    #[test] fn destino_existente_se_rechaza_salvo_que_se_pida() {
        let d = temporal("existe");
        fs::write(d.join("foto.jpg"), b"x").unwrap();
        assert_eq!(destino_de(&d, b"foto.jpg", false, false),
                   Err(ErrorExtraccion::DestinoYaExiste));
        assert!(destino_de(&d, b"foto.jpg", false, true).is_ok());
    }

    #[test] fn nombres_peligrosos_no_llegan_ni_a_resolverse() {
        let d = temporal("peligro");
        for n in [&b"../fuera.jpg"[..], b"/etc/passwd", b"a/../../b.jpg"] {
            assert_eq!(destino_de(&d, n, true, false), Err(ErrorExtraccion::NombreInvalido),
                       "{:?} tenia que rechazarse en la validacion", std::str::from_utf8(n));
        }
    }
}
