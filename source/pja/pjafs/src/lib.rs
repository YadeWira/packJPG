//! Extracción: la parte que toca el sistema de archivos.
//!
//! Va aparte del núcleo a propósito. `pjacore` es `no_std` y no sabe de rutas
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

/// Qué hacer con un archivo ya escrito cuyo hash no coincide.
///
/// El default es `Borrar` y la razón es la del resto del proyecto: un archivo
/// con nombre bueno y contenido malo es peor que ningún archivo. El que quiera
/// los bytes igual —un JPEG parcial suele verse— pide `Conservar`, y entonces
/// el archivo queda con otro nombre, nunca con el suyo.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SiFalla { Borrar, Conservar }

/// Qué pasó con un miembro al extraerlo.
#[derive(Debug, PartialEq, Eq)]
pub enum Desenlace {
    /// Escrito y verificado. **Es el único caso en que el archivo queda con
    /// su propio nombre.**
    Verificado(PathBuf),
    /// El hash no coincidía y el archivo se borró.
    Borrado { esperado: [u8; 16], obtenido: [u8; 16] },
    /// El hash no coincidía y el archivo quedó con otro nombre.
    Conservado { ruta: PathBuf, esperado: [u8; 16], obtenido: [u8; 16] },
}

#[derive(Debug)]
pub enum ErrorEscritura {
    /// No se pudo escribir. Lo que se haya escrito ya se borró.
    Io(std::io::Error),
    /// El hash no coincidía, se pidió conservar, y no se pudo renombrar.
    /// El archivo se borró: quedarse con el nombre bueno no es una opción.
    NoSePudoConservar(std::io::Error),
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
    use pjacore::nombres::{plano, ruta, Veredicto};
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

/// Escribe un miembro y **verifica después de escribir**.
///
/// El orden es ese y no al revés porque la reconstrucción del `.pjg` sale del
/// códec en streaming: verificar antes obligaría a tener el archivo entero en
/// memoria, que es justo lo que el contenedor evita. La garantía que queda es
/// la que importa: **un archivo que sigue en disco con su propio nombre pasó
/// la verificación.**
///
/// Si falla, el default borra. `SiFalla::Conservar` renombra a
/// `<nombre>.corrupto` (o `.corrupto.N` si ya existe). Si tampoco se puede
/// renombrar, se borra igual y se devuelve error: lo que nunca puede pasar es
/// que el archivo se quede con el nombre bueno.
pub fn escribir_verificado(ruta: &Path, datos: &[u8], esperado: &[u8; 16], si_falla: SiFalla)
    -> Result<Desenlace, ErrorEscritura>
{
    use std::fs;
    if let Some(p) = ruta.parent() {
        fs::create_dir_all(p).map_err(ErrorEscritura::Io)?;
    }
    if let Err(e) = fs::write(ruta, datos) {
        // Una escritura a medias no se deja tirada.
        let _ = fs::remove_file(ruta);
        return Err(ErrorEscritura::Io(e));
    }

    let mut obtenido = [0u8; 16];
    obtenido.copy_from_slice(&blake3::hash(datos).as_bytes()[..16]);
    if obtenido == *esperado {
        return Ok(Desenlace::Verificado(ruta.to_path_buf()));
    }

    match si_falla {
        SiFalla::Borrar => {
            fs::remove_file(ruta).map_err(ErrorEscritura::Io)?;
            Ok(Desenlace::Borrado { esperado: *esperado, obtenido })
        }
        SiFalla::Conservar => match ruta_corrupta_libre(ruta) {
            Some(destino) => match fs::rename(ruta, &destino) {
                Ok(()) => Ok(Desenlace::Conservado { ruta: destino, esperado: *esperado, obtenido }),
                Err(e) => { let _ = fs::remove_file(ruta); Err(ErrorEscritura::NoSePudoConservar(e)) }
            },
            None => {
                let _ = fs::remove_file(ruta);
                Err(ErrorEscritura::NoSePudoConservar(std::io::Error::new(
                    std::io::ErrorKind::AlreadyExists,
                    "no quedan nombres .corrupto libres")))
            }
        },
    }
}

/// Primer `<ruta>.corrupto[.N]` que no exista. `None` si están todos tomados.
fn ruta_corrupta_libre(ruta: &Path) -> Option<PathBuf> {
    let base = ruta.as_os_str().to_owned();
    let mut c = base.clone(); c.push(".corrupto");
    let p = PathBuf::from(&c);
    if !p.exists() { return Some(p); }
    for n in 1..1000u32 {
        let mut c = base.clone(); c.push(format!(".corrupto.{n}"));
        let p = PathBuf::from(&c);
        if !p.exists() { return Some(p); }
    }
    None
}

// ---------------------------------------------------------------------------
// Batería 4.5 de `doc/FORMATO.md`. Necesita disco de verdad, por eso vive acá.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;
    use std::fs;

    fn temporal(nombre: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("pjafs_{nombre}"));
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

    fn h16(d: &[u8]) -> [u8; 16] {
        let mut a = [0u8; 16];
        a.copy_from_slice(&blake3::hash(d).as_bytes()[..16]);
        a
    }

    /// La regla decidida: si el hash no coincide, el archivo no se queda con
    /// su nombre. Con control positivo en la misma prueba — el caso bueno
    /// tiene que quedar en disco, o "no hay archivo" pasaría siempre.
    #[test] fn hash_que_no_coincide_no_deja_el_archivo_con_su_nombre() {
        let d = temporal("verif");
        let buenos = b"contenido correcto";

        // control positivo
        let r = d.join("ok.jpg");
        let v = escribir_verificado(&r, buenos, &h16(buenos), SiFalla::Borrar).unwrap();
        assert_eq!(v, Desenlace::Verificado(r.clone()));
        assert_eq!(fs::read(&r).unwrap(), buenos, "el caso bueno tiene que quedar en disco");

        // el caso real: el hash esperado es de otro contenido
        let m = d.join("mal.jpg");
        let ajeno = h16(b"otra cosa");
        match escribir_verificado(&m, buenos, &ajeno, SiFalla::Borrar).unwrap() {
            Desenlace::Borrado { esperado, obtenido } => {
                assert_eq!(esperado, ajeno);
                assert_eq!(obtenido, h16(buenos));
            }
            otro => panic!("esperaba Borrado, dio {otro:?}"),
        }
        assert!(!m.exists(), "el archivo con hash malo quedó en disco con su nombre");
    }

    #[test] fn conservar_renombra_y_nunca_deja_el_nombre_bueno() {
        let d = temporal("conservar");
        let m = d.join("foto.jpg");
        let datos = b"bytes rescatables";
        let ajeno = h16(b"otra cosa");

        match escribir_verificado(&m, datos, &ajeno, SiFalla::Conservar).unwrap() {
            Desenlace::Conservado { ruta, .. } => {
                assert_eq!(ruta.file_name().unwrap(), "foto.jpg.corrupto");
                assert_eq!(fs::read(&ruta).unwrap(), datos, "los bytes tienen que sobrevivir");
            }
            otro => panic!("esperaba Conservado, dio {otro:?}"),
        }
        assert!(!m.exists(), "el nombre bueno tiene que quedar libre");

        // y un segundo intento no pisa al primero
        match escribir_verificado(&m, b"otro intento", &ajeno, SiFalla::Conservar).unwrap() {
            Desenlace::Conservado { ruta, .. } =>
                assert_eq!(ruta.file_name().unwrap(), "foto.jpg.corrupto.1"),
            otro => panic!("esperaba Conservado, dio {otro:?}"),
        }
        assert!(!m.exists());
        assert_eq!(fs::read(d.join("foto.jpg.corrupto")).unwrap(), datos,
                   "el primer .corrupto no se puede pisar");
    }

    #[test] fn nombres_peligrosos_no_llegan_ni_a_resolverse() {
        let d = temporal("peligro");
        for n in [&b"../fuera.jpg"[..], b"/etc/passwd", b"a/../../b.jpg"] {
            assert_eq!(destino_de(&d, n, true, false), Err(ErrorExtraccion::NombreInvalido),
                       "{:?} tenia que rechazarse en la validacion", std::str::from_utf8(n));
        }
    }
}
