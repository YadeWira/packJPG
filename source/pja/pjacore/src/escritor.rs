//! Serializa el contenedor. Es el inverso exacto de `indice::leer_indice`, y
//! **valida antes de escribir**: un contenedor que no se puede leer no se
//! produce.

use crate::indice::*;
use crate::limites::*;
use crate::nombres::{self, Veredicto};

#[cfg(not(test))] use alloc::vec::Vec;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ErrorEscritura {
    NombreInvalido(usize),
    NombreDuplicado(usize),
    DemasiadosMiembros,
    PayloadFueraDeRango(usize),
    LargoDeclaradoNoCoincide(usize),
    Desborde,
}

pub struct Entrada<'a> {
    pub nombre: &'a [u8],
    /// Tamaño del JPEG original, para el rechazo temprano al descomprimir.
    pub tam_orig: u64,
    /// El `.pjg` ya comprimido.
    pub payload: &'a [u8],
    pub hash: [u8; 16],
}

/// Miembros que llevaron aviso de incompatibilidad con Windows. No impide
/// escribir: son nombres legales en Linux.
pub type Avisos = Vec<(usize, nombres::Motivo)>;

pub fn escribir(entradas: &[Entrada], flags: u8) -> Result<(Vec<u8>, Avisos), ErrorEscritura> {
    if entradas.len() as u64 > MAX_MIEMBROS as u64 {
        return Err(ErrorEscritura::DemasiadosMiembros);
    }
    let mut avisos: Avisos = Vec::new();

    for (i, e) in entradas.iter().enumerate() {
        let v = if flags & FLAG_RUTAS != 0 { nombres::ruta(e.nombre) }
                else { nombres::plano(e.nombre) };
        match v {
            Veredicto::Rechazo(_) => return Err(ErrorEscritura::NombreInvalido(i)),
            Veredicto::SoloWindows(m) => avisos.push((i, m)),
            Veredicto::Ok => {}
        }
        if (e.payload.len() as u64) < MIN_PAYLOAD {
            return Err(ErrorEscritura::PayloadFueraDeRango(i));
        }
        for otra in &entradas[..i] {
            if otra.nombre == e.nombre { return Err(ErrorEscritura::NombreDuplicado(i)); }
        }
    }

    let mut idx: Vec<u8> = Vec::new();
    idx.extend_from_slice(&(entradas.len() as u32).to_le_bytes());
    for e in entradas {
        idx.extend_from_slice(&(e.nombre.len() as u16).to_le_bytes());
        idx.extend_from_slice(e.nombre);
        idx.extend_from_slice(&e.tam_orig.to_le_bytes());
        idx.extend_from_slice(&(e.payload.len() as u64).to_le_bytes());
        idx.extend_from_slice(&e.hash);
        idx.push(0);
    }

    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(&MAGIA);
    out.push(VERSION);
    out.push(flags);
    // kdf(1) + reservado(1). El perfil sólo va cuando hay cifrado; sin cifrado
    // ese byte tiene que ser cero y `leer_cabecera` lo exige.
    out.push( if flags & FLAG_CIFRADO != 0 { crate::cifrado::PerfilKdf::V1.a_byte() } else { 0 } );
    out.push(0);
    out.extend_from_slice(&(idx.len() as u32).to_le_bytes());
    out.extend_from_slice(&[0u8; 16]);          // hueco del hash
    out.extend_from_slice(&idx);
    let h = hash_cabecera_indice(&out[..TAM_CABECERA], &idx);
    out[12..28].copy_from_slice(&h);
    for e in entradas { out.extend_from_slice(e.payload); }
    Ok((out, avisos))
}

/// Dónde arranca el payload de cada miembro, en orden.
pub fn desplazamientos(c: &Contenedor, tam_indice: u64) -> Vec<u64> {
    let mut p = TAM_CABECERA as u64 + tam_indice;
    let mut v = Vec::new();
    for m in &c.miembros { v.push(p); p += m.tam_payload; }
    v
}

// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;

    fn ent<'a>(n: &'a [u8], p: &'a [u8]) -> Entrada<'a> {
        Entrada { nombre: n, tam_orig: p.len() as u64 * 2, payload: p, hash: [7u8; 16] }
    }

    #[test] fn round_trip_lo_que_se_escribe_se_lee_igual() {
        let a = vec![1u8; 100]; let b = vec![2u8; 250];
        let (bytes, avisos) = escribir(&[ent(b"a.jpg", &a), ent(b"b.jpg", &b)], 0).unwrap();
        assert!(avisos.is_empty());

        let c = leer_indice(&bytes).expect("lo que escribimos tiene que leerse");
        assert_eq!(c.miembros.len(), 2);
        assert_eq!(c.miembros[0].nombre, b"a.jpg");
        assert_eq!(c.miembros[0].tam_payload, 100);
        assert_eq!(c.miembros[1].tam_payload, 250);
        assert_eq!(c.miembros[0].hash, [7u8; 16]);

        // Y los payloads salen byte por byte donde dice el indice.
        let (_, ti, _) = leer_cabecera(&bytes).unwrap();
        let offs = desplazamientos(&c, ti as u64);
        assert_eq!(&bytes[offs[0] as usize .. offs[0] as usize + 100], &a[..]);
        assert_eq!(&bytes[offs[1] as usize .. offs[1] as usize + 250], &b[..]);
    }

    #[test] fn round_trip_con_rutas_y_unicode() {
        let p = vec![9u8; 64];
        let (bytes, avisos) = escribir(
            &[ent("2026/enero/ñandú.jpg".as_bytes(), &p),
              ent("2026/enero/写真.jpg".as_bytes(), &p)], FLAG_RUTAS).unwrap();
        assert!(avisos.is_empty());
        let c = leer_indice(&bytes).unwrap();
        assert_eq!(c.miembros[0].nombre, "2026/enero/ñandú.jpg".as_bytes());
        assert_eq!(c.miembros[1].nombre, "2026/enero/写真.jpg".as_bytes());
    }

    #[test] fn avisa_pero_escribe_lo_que_solo_rompe_en_windows() {
        let p = vec![3u8; 32];
        let (bytes, avisos) = escribir(&[ent(b"foto?.jpg", &p), ent(b"CON.jpg", &p)], 0).unwrap();
        assert_eq!(avisos.len(), 2);
        assert_eq!(avisos[0].1, nombres::Motivo::CaracterIlegalEnWindows);
        assert_eq!(avisos[1].1, nombres::Motivo::NombreReservado);
        // Y el contenedor es valido: son nombres legales en Linux.
        assert!(leer_indice(&bytes).is_ok());
    }

    #[test] fn no_escribe_lo_que_no_podria_leer() {
        let p = vec![1u8; 32];
        assert_eq!(escribir(&[ent(b"../x.jpg", &p)], FLAG_RUTAS).err(),
                   Some(ErrorEscritura::NombreInvalido(0)));
        assert_eq!(escribir(&[ent(b"a.jpg", &p), ent(b"a.jpg", &p)], 0).err(),
                   Some(ErrorEscritura::NombreDuplicado(1)));
        let corto = vec![0u8; 4];
        assert_eq!(escribir(&[ent(b"a.jpg", &corto)], 0).err(),
                   Some(ErrorEscritura::PayloadFueraDeRango(0)));
    }

    #[test] fn contenedor_vacio_es_valido_y_se_lee() {
        let (bytes, _) = escribir(&[], 0).unwrap();
        let c = leer_indice(&bytes).unwrap();
        assert_eq!(c.miembros.len(), 0);
    }
}

// ---------------------------------------------------------------------------
// Round-trip con archivos reales. No sintéticos: `.pjg` producidos por packJPG.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod reales {
    use super::*;
    use std::fs;
    use std::path::Path;

    #[test] fn round_trip_con_pjg_reales() {
        // Antes esto arrancaba con:
        //     if !dir.exists() { eprintln!("corpus ausente"); return; }
        // o sea que sin corpus la prueba pasaba en verde sin probar nada. En la
        // maquina de desarrollo el corpus estaba, asi que nunca se noto; en un
        // checkout limpio habria sido cobertura cero y silenciosa. Falta de
        // material es un fallo, no una omision.
        let rutas = crate::corpus::pjgs(10);

        let datos: Vec<Vec<u8>> = rutas.iter().map(|p| fs::read(p).unwrap()).collect();
        let nombres: Vec<Vec<u8>> = rutas.iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().as_bytes().to_vec())
            .collect();

        let entradas: Vec<Entrada> = datos.iter().zip(&nombres).map(|(d, n)| Entrada {
            nombre: n, tam_orig: d.len() as u64 * 2, payload: d,
            hash: { let h = blake3::hash(d); let mut a = [0u8; 16];
                    a.copy_from_slice(&h.as_bytes()[..16]); a },
        }).collect();

        let (bytes, avisos) = escribir(&entradas, 0).unwrap();
        assert!(avisos.is_empty(), "nombres del corpus no deberian dar aviso");

        let c = leer_indice(&bytes).expect("el contenedor tiene que leerse");
        assert_eq!(c.miembros.len(), datos.len());

        let (_, ti, _) = leer_cabecera(&bytes).unwrap();
        let offs = desplazamientos(&c, ti as u64);

        let mut total = 0usize;
        for (i, m) in c.miembros.iter().enumerate() {
            let ini = offs[i] as usize;
            let salida = &bytes[ini .. ini + m.tam_payload as usize];
            assert_eq!(salida, &datos[i][..], "miembro {i} no salio byte-exacto");
            let h = blake3::hash(salida);
            assert_eq!(&h.as_bytes()[..16], &m.hash[..], "hash del miembro {i}");
            total += salida.len();
        }
        eprintln!("  round-trip real: {} miembros, {} bytes, byte-exactos",
                  c.miembros.len(), total);

        // El contenedor no infla: solo la cabecera y el indice.
        let suma: usize = datos.iter().map(|d| d.len()).sum();
        let sobrecarga = bytes.len() - suma;
        eprintln!("  sobrecarga del contenedor: {} bytes ({:.4}%)",
                  sobrecarga, 100.0 * sobrecarga as f64 / suma as f64);
        assert!(sobrecarga < 4096, "sobrecarga inesperada: {sobrecarga}");
    }
}
