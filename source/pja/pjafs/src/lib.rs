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
///
/// La ruta devuelta cuelga del destino YA resuelto, componente por componente,
/// y es sobre ella que se mide el largo: es la que el sistema va a ver.
pub fn destino_de(destino: &Path, nombre: &[u8], rutas: bool, sobrescribir: bool)
    -> Result<PathBuf, ErrorExtraccion>
{
    use pjacore::nombres::{plano, ruta, Veredicto};
    let v = if rutas { ruta(nombre) } else { plano(nombre) };
    if let Veredicto::Rechazo(_) = v { return Err(ErrorExtraccion::NombreInvalido); }
    // POLITICA.md 3.2: lo que sólo es ilegal en Windows se rechaza al extraer
    // EN Windows. Sin esto `CON.jpg` iba al dispositivo y `foto.` perdía el
    // punto en silencio, chocando con `foto`.
    if cfg!(windows) {
        if let Veredicto::SoloWindows(_) = v { return Err(ErrorExtraccion::NombreInvalido); }
    }

    let s = std::str::from_utf8(nombre).map_err(|_| ErrorExtraccion::NombreInvalido)?;

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

    // Componente por componente y no `join(s)`: en Windows `base` viene con el
    // prefijo `\\?\`, y con ese prefijo el sistema ya no traduce `/` a `\`.
    let mut candidato = base.clone();
    for c in s.split('/') { candidato.push(c); }

    let padre = candidato.parent().unwrap_or(&base);
    let padre_resuelto = match padre.canonicalize() {
        Ok(p) => p,
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

    // Limite de Windows, sobre la ruta resuelta y en unidades UTF-16, que es
    // lo que cuenta MAX_PATH. Se rechaza con mensaje; nunca se trunca.
    let largo = largo_windows(&candidato);
    if largo > MAX_PATH_WINDOWS {
        return Err(ErrorExtraccion::RutaMuyLargaParaWindows(largo));
    }

    // El ultimo componente se mira SIN seguir enlaces. `exists()` los sigue:
    // un enlace colgante daba "no existe" y la escritura lo seguia afuera, y
    // uno a un archivo de afuera, con sobrescribir, lo pisaba.
    if std::fs::symlink_metadata(&candidato).is_ok() && !sobrescribir {
        return Err(ErrorExtraccion::DestinoYaExiste);
    }
    Ok(candidato)
}

/// Largo de la ruta como lo cuenta Windows: unidades UTF-16, sin el prefijo
/// `\\?\` que agrega `canonicalize` (y `\\?\UNC\x` cuenta como `\\x`).
fn largo_windows(p: &Path) -> usize {
    let t = p.to_string_lossy();
    let (t, extra) = if let Some(r) = t.strip_prefix(r"\\?\UNC\") { (r, 2) }
                     else if let Some(r) = t.strip_prefix(r"\\?\") { (r, 0) }
                     else { (&t[..], 0) };
    t.encode_utf16().count() + extra
}

/// Escribe un miembro y **verifica después de escribir**.
///
/// El orden es ese y no al revés porque la reconstrucción del `.pjg` sale del
/// códec en streaming: verificar antes obligaría a tener el archivo entero en
/// memoria, que es justo lo que el contenedor evita. La garantía que queda es
/// la que importa: **un archivo que sigue en disco con su propio nombre pasó
/// la verificación.**
///
/// El archivo se CREA, nunca se abre uno existente (`create_new`, que no sigue
/// enlaces): así no se escribe a través de un enlace simbólico ni de un enlace
/// duro plantados en el destino. Con `sobrescribir`, la entrada que haya se
/// borra antes —el enlace, no su objetivo—, como hace tar.
///
/// Si falla, el default borra. `SiFalla::Conservar` renombra a
/// `<nombre>.corrupto` (o `.corrupto.N` si ya existe). Si tampoco se puede
/// renombrar, se borra igual y se devuelve error: lo que nunca puede pasar es
/// que el archivo se quede con el nombre bueno.
pub fn escribir_verificado(ruta: &Path, datos: &[u8], esperado: &[u8; 16], si_falla: SiFalla,
                           sobrescribir: bool) -> Result<Desenlace, ErrorEscritura>
{
    use std::fs;
    use std::io::Write;
    if let Some(p) = ruta.parent() {
        fs::create_dir_all(p).map_err(ErrorEscritura::Io)?;
    }
    if sobrescribir {
        match fs::remove_file(ruta) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(ErrorEscritura::Io(e)),
        }
    }
    // Si no se pudo crear no hay nada nuestro que borrar: lo que haya ahi no
    // lo escribimos nosotros.
    let mut f = fs::OpenOptions::new().write(true).create_new(true).open(ruta)
        .map_err(ErrorEscritura::Io)?;
    if let Err(e) = f.write_all(datos) {
        // Una escritura a medias no se deja tirada.
        drop(f);
        let _ = fs::remove_file(ruta);
        return Err(ErrorEscritura::Io(e));
    }
    drop(f);

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

/// Primer `<ruta>.corrupto[.N]` libre, mirando la entrada y no lo que apunta
/// (un enlace colgante ocupa el nombre). `None` si están todos tomados.
fn ruta_corrupta_libre(ruta: &Path) -> Option<PathBuf> {
    let libre = |p: &Path| std::fs::symlink_metadata(p).is_err();
    let base = ruta.as_os_str().to_owned();
    let mut c = base.clone(); c.push(".corrupto");
    let p = PathBuf::from(&c);
    if libre(&p) { return Some(p); }
    for n in 1..1000u32 {
        let mut c = base.clone(); c.push(format!(".corrupto.{n}"));
        let p = PathBuf::from(&c);
        if libre(&p) { return Some(p); }
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
        let v = escribir_verificado(&r, buenos, &h16(buenos), SiFalla::Borrar, false).unwrap();
        assert_eq!(v, Desenlace::Verificado(r.clone()));
        assert_eq!(fs::read(&r).unwrap(), buenos, "el caso bueno tiene que quedar en disco");

        // el caso real: el hash esperado es de otro contenido
        let m = d.join("mal.jpg");
        let ajeno = h16(b"otra cosa");
        match escribir_verificado(&m, buenos, &ajeno, SiFalla::Borrar, false).unwrap() {
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

        match escribir_verificado(&m, datos, &ajeno, SiFalla::Conservar, false).unwrap() {
            Desenlace::Conservado { ruta, .. } => {
                assert_eq!(ruta.file_name().unwrap(), "foto.jpg.corrupto");
                assert_eq!(fs::read(&ruta).unwrap(), datos, "los bytes tienen que sobrevivir");
            }
            otro => panic!("esperaba Conservado, dio {otro:?}"),
        }
        assert!(!m.exists(), "el nombre bueno tiene que quedar libre");

        // y un segundo intento no pisa al primero
        match escribir_verificado(&m, b"otro intento", &ajeno, SiFalla::Conservar, false).unwrap() {
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

    // --- Las de abajo reproducen defectos medidos el 2026-10-09 en la versión
    // anterior: cada una FALLABA antes del arreglo (ver doc en destino_de).

    /// Un enlace con el nombre del miembro, hacia un archivo de afuera, con
    /// sobrescribir: antes se escribia A TRAVES del enlace y se pisaba afuera.
    #[cfg(unix)]
    #[test] fn enlace_final_hacia_afuera_no_se_sigue_al_sobrescribir() {
        let d = temporal("final_afuera"); let afuera = temporal("final_afuera_x");
        fs::write(afuera.join("victima.txt"), b"original").unwrap();
        std::os::unix::fs::symlink(afuera.join("victima.txt"), d.join("a.jpg")).unwrap();
        let p = destino_de(&d, b"a.jpg", false, true).unwrap();
        let v = escribir_verificado(&p, b"nuevo", &h16(b"nuevo"), SiFalla::Borrar, true).unwrap();
        assert!(matches!(v, Desenlace::Verificado(_)));
        assert_eq!(fs::read(afuera.join("victima.txt")).unwrap(), b"original", "se escribio afuera");
        assert!(!fs::symlink_metadata(&p).unwrap().file_type().is_symlink(), "el enlace tenia que reemplazarse");
        assert_eq!(fs::read(&p).unwrap(), b"nuevo");
    }

    /// Un enlace colgante hacia afuera ocupa el nombre: sin sobrescribir se
    /// rechaza. Antes `exists()` lo seguia, daba "no existe", y la escritura
    /// creaba el archivo afuera, reportado como Verificado.
    #[cfg(unix)]
    #[test] fn enlace_colgante_ocupa_el_nombre() {
        let d = temporal("colgante"); let afuera = temporal("colgante_x");
        std::os::unix::fs::symlink(afuera.join("nuevo.txt"), d.join("b.jpg")).unwrap();
        assert_eq!(destino_de(&d, b"b.jpg", false, false), Err(ErrorExtraccion::DestinoYaExiste));
        // y aunque alguien llegue a escribir igual (carrera), no se sigue
        let p = d.canonicalize().unwrap().join("b.jpg");
        assert!(escribir_verificado(&p, b"x", &h16(b"x"), SiFalla::Borrar, false).is_err());
        assert!(!afuera.join("nuevo.txt").exists(), "se creo un archivo afuera");
    }

    /// Un enlace DURO adentro del destino hacia un archivo de afuera: escribir
    /// en el lugar lo pisaba. Crear de nuevo lo deja intacto.
    #[cfg(unix)]
    #[test] fn enlace_duro_no_se_escribe_a_traves() {
        let d = temporal("duro"); let afuera = temporal("duro_x");
        fs::write(afuera.join("victima.txt"), b"original").unwrap();
        fs::hard_link(afuera.join("victima.txt"), d.join("c.jpg")).unwrap();
        let p = destino_de(&d, b"c.jpg", false, true).unwrap();
        escribir_verificado(&p, b"nuevo", &h16(b"nuevo"), SiFalla::Borrar, true).unwrap();
        assert_eq!(fs::read(afuera.join("victima.txt")).unwrap(), b"original");
    }

    /// Sin sobrescribir, un archivo que aparece entre el chequeo y la escritura
    /// no se pisa ni se borra: no lo escribimos nosotros.
    #[test] fn sin_sobrescribir_un_archivo_ajeno_queda_intacto() {
        let d = temporal("ajeno");
        let p = destino_de(&d, b"f.jpg", false, false).unwrap();
        fs::write(&p, b"del usuario").unwrap();
        assert!(escribir_verificado(&p, b"x", &h16(b"x"), SiFalla::Borrar, false).is_err());
        assert_eq!(fs::read(&p).unwrap(), b"del usuario");
    }

    /// El largo se mide sobre la ruta resuelta: con un destino relativo antes
    /// se contaba sólo lo escrito, y pasaba un nombre inextraíble en Windows.
    #[test] fn el_largo_se_mide_sobre_la_ruta_resuelta() {
        let d = temporal("relativo");
        let abs = d.canonicalize().unwrap();
        // abs + "/" + nombre: 261 unidades, una de mas
        let nombre = "x".repeat(MAX_PATH_WINDOWS - abs.as_os_str().len() - 4) + ".jpg";
        std::env::set_current_dir(abs.parent().unwrap()).unwrap();
        let rel = Path::new(abs.file_name().unwrap());
        match destino_de(rel, nombre.as_bytes(), false, false) {
            Err(ErrorExtraccion::RutaMuyLargaParaWindows(n)) => assert_eq!(n, MAX_PATH_WINDOWS + 1),
            otro => panic!("esperaba RutaMuyLargaParaWindows, dio {otro:?}"),
        }
        // control: uno que entra justo
        let justo = "x".repeat(MAX_PATH_WINDOWS - abs.as_os_str().len() - 5) + ".jpg";
        assert!(destino_de(rel, justo.as_bytes(), false, false).is_ok());
    }

    /// Un `.corrupto` ocupado por un enlace colgante no cuenta como libre.
    #[cfg(unix)]
    #[test] fn corrupto_ocupado_por_enlace_colgante() {
        let d = temporal("corrupto_enlace");
        std::os::unix::fs::symlink(d.join("no_existe"), d.join("g.jpg.corrupto")).unwrap();
        match escribir_verificado(&d.join("g.jpg"), b"x", &h16(b"otro"), SiFalla::Conservar, false).unwrap() {
            Desenlace::Conservado { ruta, .. } => assert_eq!(ruta.file_name().unwrap(), "g.jpg.corrupto.1"),
            otro => panic!("esperaba Conservado, dio {otro:?}"),
        }
        assert!(fs::symlink_metadata(d.join("g.jpg.corrupto")).unwrap().file_type().is_symlink());
    }
}
