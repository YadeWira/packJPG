//! Validación de nombres. La política vive en `doc/POLITICA.md`; acá se aplica.
//!
//! Dos niveles, y la diferencia importa: lo que es **peligro** se rechaza al
//! crear; lo que es **incompatibilidad con Windows** se avisa al crear y se
//! rechaza al extraer, porque son nombres legales en Linux y rechazarlos al
//! crear le impediría a alguien archivar un archivo suyo válido.

use crate::limites::*;
#[cfg(not(test))] use alloc::vec::Vec;
#[cfg(test)] use std::vec::Vec;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Veredicto {
    Ok,
    /// Peligro: se rechaza siempre.
    Rechazo(Motivo),
    /// Legal en Linux, ilegal en Windows: avisa al crear, rechaza al extraer allá.
    SoloWindows(Motivo),
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Motivo {
    Vacio,
    ByteDeControl,
    SeparadorEnComponente,
    ComponentePadre,
    RutaAbsoluta,
    LetraDeUnidad,
    DosPuntos,
    Utf8Invalido,
    ComponenteMuyLargo,
    RutaMuyLarga,
    MuyProfunda,
    NombreReservado,
    TerminaEnPuntoOEspacio,
    CaracterIlegalEnWindows,
}

const RESERVADOS: [&str; 22] = [
    "CON", "PRN", "AUX", "NUL",
    "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
    "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Valida un componente suelto (sin separadores).
fn componente(c: &[u8]) -> Veredicto {
    if c.is_empty() { return Veredicto::Rechazo(Motivo::Vacio); }
    if c.len() > MAX_BYTES_COMPONENTE { return Veredicto::Rechazo(Motivo::ComponenteMuyLargo); }
    if c == b"." || c == b".." { return Veredicto::Rechazo(Motivo::ComponentePadre); }

    for &b in c {
        if b < 0x20 || b == 0x7F { return Veredicto::Rechazo(Motivo::ByteDeControl); }
        if b == b'/' || b == b'\\' { return Veredicto::Rechazo(Motivo::SeparadorEnComponente); }
        if b == b':' { return Veredicto::Rechazo(Motivo::DosPuntos); }
    }
    if core::str::from_utf8(c).is_err() { return Veredicto::Rechazo(Motivo::Utf8Invalido); }

    // A partir de acá: legal en Linux, problemático en Windows.
    let ultimo = c[c.len() - 1];
    if ultimo == b'.' || ultimo == b' ' {
        return Veredicto::SoloWindows(Motivo::TerminaEnPuntoOEspacio);
    }
    for &b in c {
        if matches!(b, b'*' | b'?' | b'<' | b'>' | b'|' | b'"') {
            return Veredicto::SoloWindows(Motivo::CaracterIlegalEnWindows);
        }
    }
    // Reservado con o sin extensión, sin distinguir mayúsculas.
    let base: &[u8] = match c.iter().position(|&b| b == b'.') { Some(i) => &c[..i], None => c };
    if base.len() <= 4 {
        let mut mayus = [0u8; 4];
        for (i, &b) in base.iter().enumerate() { mayus[i] = b.to_ascii_uppercase(); }
        let s = core::str::from_utf8(&mayus[..base.len()]).unwrap_or("");
        if RESERVADOS.contains(&s) { return Veredicto::SoloWindows(Motivo::NombreReservado); }
    }
    Veredicto::Ok
}

/// Valida un nombre en modo plano: un solo componente, sin rutas.
pub fn plano(nombre: &[u8]) -> Veredicto {
    componente(nombre)
}

/// Valida una ruta relativa en modo `--keep-structure`.
pub fn ruta(r: &[u8]) -> Veredicto {
    if r.is_empty() { return Veredicto::Rechazo(Motivo::Vacio); }
    if r.len() > MAX_BYTES_RUTA { return Veredicto::Rechazo(Motivo::RutaMuyLarga); }
    if r[0] == b'/' { return Veredicto::Rechazo(Motivo::RutaAbsoluta); }
    if r.len() >= 2 && r[1] == b':' { return Veredicto::Rechazo(Motivo::LetraDeUnidad); }
    if r.contains(&b'\\') { return Veredicto::Rechazo(Motivo::SeparadorEnComponente); }

    let partes: Vec<&[u8]> = r.split(|&b| b == b'/').collect();
    if partes.len() > MAX_PROFUNDIDAD { return Veredicto::Rechazo(Motivo::MuyProfunda); }

    let mut aviso = None;
    for p in partes {
        match componente(p) {
            Veredicto::Ok => {}
            Veredicto::SoloWindows(m) => { if aviso.is_none() { aviso = Some(m); } }
            r @ Veredicto::Rechazo(_) => return r,
        }
    }
    match aviso { Some(m) => Veredicto::SoloWindows(m), None => Veredicto::Ok }
}

// ---------------------------------------------------------------------------
// Batería 4.3 de `doc/FORMATO.md`, caso por caso. Cada fila del documento es
// una prueba acá, con el mismo veredicto esperado.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;

    #[test] fn peligro_se_rechaza_siempre() {
        assert_eq!(ruta(b"../../etc/passwd"), Veredicto::Rechazo(Motivo::ComponentePadre));
        assert_eq!(ruta(b"/etc/passwd"),      Veredicto::Rechazo(Motivo::RutaAbsoluta));
        assert_eq!(ruta(b"C:\\Windows\\x"),   Veredicto::Rechazo(Motivo::LetraDeUnidad));
        assert_eq!(ruta(b"a/../../b"),        Veredicto::Rechazo(Motivo::ComponentePadre));
        assert_eq!(plano(b"foto.jpg:carga"),  Veredicto::Rechazo(Motivo::DosPuntos));
        assert_eq!(plano(b"con\x00nulo"),     Veredicto::Rechazo(Motivo::ByteDeControl));
        assert_eq!(plano(b"salto\nlinea"),    Veredicto::Rechazo(Motivo::ByteDeControl));
        assert_eq!(plano(b"\xff\xfe"),        Veredicto::Rechazo(Motivo::Utf8Invalido));
        assert_eq!(plano(b""),                Veredicto::Rechazo(Motivo::Vacio));
    }

    #[test] fn el_limite_es_en_bytes_no_en_caracteres() {
        assert_eq!(plano(&[b'a'; 255]), Veredicto::Ok);
        assert_eq!(plano(&[b'a'; 256]), Veredicto::Rechazo(Motivo::ComponenteMuyLargo));
        // 128 acentuados son 256 bytes: se rechaza aunque sean "menos caracteres".
        let acentuados = "á".repeat(128).into_bytes();
        assert_eq!(acentuados.len(), 256);
        assert_eq!(plano(&acentuados), Veredicto::Rechazo(Motivo::ComponenteMuyLargo));
        let cortos = "á".repeat(127).into_bytes();
        assert_eq!(cortos.len(), 254);
        assert_eq!(plano(&cortos), Veredicto::Ok);
    }

    #[test] fn profundidad_y_largo_total() {
        let profunda = "a/".repeat(33) + "f.jpg";
        assert_eq!(ruta(profunda.as_bytes()), Veredicto::Rechazo(Motivo::MuyProfunda));
        let larga = "a/".repeat(600) + "f.jpg";
        assert_eq!(ruta(larga.as_bytes()), Veredicto::Rechazo(Motivo::RutaMuyLarga));
    }

    #[test] fn incompatible_con_windows_pero_legal_en_linux() {
        assert_eq!(plano(b"CON.jpg"),      Veredicto::SoloWindows(Motivo::NombreReservado));
        assert_eq!(plano(b"nul.JPG"),      Veredicto::SoloWindows(Motivo::NombreReservado));
        assert_eq!(plano(b"LPT9"),         Veredicto::SoloWindows(Motivo::NombreReservado));
        assert_eq!(plano(b"archivo.jpg "), Veredicto::SoloWindows(Motivo::TerminaEnPuntoOEspacio));
        assert_eq!(plano(b"archivo."),     Veredicto::SoloWindows(Motivo::TerminaEnPuntoOEspacio));
        // Y el que NO es problema: el espacio en el medio es legal en Windows.
        assert_eq!(plano(b"archivo .jpg"),  Veredicto::Ok);
        assert_eq!(plano(b"foto?.jpg"),    Veredicto::SoloWindows(Motivo::CaracterIlegalEnWindows));
        assert_eq!(plano(b"a<b>.jpg"),     Veredicto::SoloWindows(Motivo::CaracterIlegalEnWindows));
    }

    #[test] fn lo_que_pasa_sin_objecion() {
        assert_eq!(plano("ñandú.jpg".as_bytes()),      Veredicto::Ok);
        assert_eq!(plano("写真.jpg".as_bytes()),        Veredicto::Ok);
        assert_eq!(plano("foto 1 (a).jpg".as_bytes()), Veredicto::Ok);
        assert_eq!(ruta(b"2026/enero/foto.jpg"),       Veredicto::Ok);
    }

    #[test] fn control_negativo_el_validador_discrimina() {
        // Sin esta, un validador que rechazara TODO pasaria las de arriba.
        assert_eq!(plano(b"normal.jpg"), Veredicto::Ok);
        assert_ne!(plano(b"normal.jpg"), plano(b"../x"));
    }
}
