//! Une el contenedor con el cifrado.
//!
//! Cuando `FLAG_CIFRADO` está puesto, **índice y payloads viajan en la misma
//! secuencia de trozos**: el índice no se puede leer sin haber autenticado.
//! Ese orden es lo que da la seguridad, no los chequeos sueltos.
//!
//! Layout cifrado:
//! ```text
//!   magia · version · flags · reservado · tam_indice · hash        (en claro)
//!   sal(16) · nonce_base(24)                                       (en claro)
//!   trozos AEAD de [ índice ‖ payloads ]
//! ```
//! `tam_indice` y el hash quedan en claro para poder cortar el índice del
//! resto una vez descifrado, y para que la cabecera esté atada igual que en
//! el caso sin cifrar.

use crate::cifrado::{self, TAM_SAL, TAM_NONCE};
use crate::escritor::{self, Entrada, ErrorEscritura, Avisos};
use crate::indice::{self, Contenedor, TAM_CABECERA, FLAG_CIFRADO};

#[cfg(not(test))] use alloc::vec::Vec;

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    Escritura(ErrorEscritura),
    Indice(indice::Error),
    Cifrado(cifrado::Error),
    /// El archivo dice estar cifrado y no se dio contraseña, o al revés.
    ContraseñaFaltante,
    ContraseñaSobrante,
    ArchivoCorto,
}

#[derive(Debug)]
pub struct Abierto {
    pub contenedor: Contenedor,
    /// Payloads ya en claro, en el orden del índice.
    pub payloads: Vec<Vec<u8>>,
}

const TAM_PREFIJO_CIFRADO: usize = TAM_SAL + TAM_NONCE;

pub fn escribir(
    entradas: &[Entrada],
    flags: u8,
    clave_y_nonce: Option<(&[u8; 32], &[u8; TAM_NONCE], &[u8; TAM_SAL])>,
) -> Result<(Vec<u8>, Avisos), Error> {
    let (plano, avisos) = escritor::escribir(entradas, flags).map_err(Error::Escritura)?;

    match (flags & FLAG_CIFRADO != 0, clave_y_nonce) {
        (false, None) => Ok((plano, avisos)),
        (false, Some(_)) => Err(Error::ContraseñaSobrante),
        (true, None) => Err(Error::ContraseñaFaltante),
        (true, Some((clave, nonce, sal))) => {
            // La cabecera queda en claro; el resto -- indice y payloads juntos
            // -- se cifra como una sola secuencia de trozos.
            let cuerpo = &plano[TAM_CABECERA..];
            let ct = cifrado::cifrar(clave, nonce, cuerpo).map_err(Error::Cifrado)?;
            let mut out = Vec::with_capacity(TAM_CABECERA + TAM_PREFIJO_CIFRADO + ct.len());
            out.extend_from_slice(&plano[..TAM_CABECERA]);
            out.extend_from_slice(sal);
            out.extend_from_slice(nonce);
            out.extend_from_slice(&ct);
            Ok((out, avisos))
        }
    }
}

/// Abre el contenedor. **El orden importa y es el de `doc/FORMATO.md`:**
/// cabecera, autenticar, deserializar, límites, nombres, y recién ahí los
/// payloads quedan disponibles para el códec.
pub fn abrir(datos: &[u8], pass: Option<&[u8]>) -> Result<Abierto, Error> {
    let (flags, tam_indice, _) = indice::leer_cabecera(datos).map_err(Error::Indice)?;
    let cifrado_puesto = flags & FLAG_CIFRADO != 0;

    let plano: Vec<u8> = if cifrado_puesto {
        let pass = pass.ok_or(Error::ContraseñaFaltante)?;
        if datos.len() < TAM_CABECERA + TAM_PREFIJO_CIFRADO { return Err(Error::ArchivoCorto); }
        let mut sal = [0u8; TAM_SAL];
        sal.copy_from_slice(&datos[TAM_CABECERA .. TAM_CABECERA + TAM_SAL]);
        let mut nonce = [0u8; TAM_NONCE];
        nonce.copy_from_slice(&datos[TAM_CABECERA + TAM_SAL .. TAM_CABECERA + TAM_PREFIJO_CIFRADO]);

        let clave = cifrado::derivar_clave(pass, &sal).map_err(Error::Cifrado)?;
        // Autenticar ANTES de mirar el indice.
        let cuerpo = cifrado::descifrar(&clave, &nonce,
                        &datos[TAM_CABECERA + TAM_PREFIJO_CIFRADO ..]).map_err(Error::Cifrado)?;
        let mut v = Vec::with_capacity(TAM_CABECERA + cuerpo.len());
        v.extend_from_slice(&datos[..TAM_CABECERA]);
        v.extend_from_slice(&cuerpo);
        v
    } else {
        if pass.is_some() { return Err(Error::ContraseñaSobrante); }
        datos.to_vec()
    };

    // Desde acá el camino es el mismo, cifrado o no: hash de cabecera+indice,
    // deserializar, los seis limites, y los nombres.
    let c = indice::leer_indice(&plano).map_err(Error::Indice)?;

    let mut payloads = Vec::with_capacity(c.miembros.len());
    let mut p = TAM_CABECERA + tam_indice as usize;
    for m in &c.miembros {
        let fin = p + m.tam_payload as usize;
        payloads.push(plano[p..fin].to_vec());
        p = fin;
    }
    Ok(Abierto { contenedor: c, payloads })
}

// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::indice::FLAG_RUTAS;
    use std::fs;

    const SAL: [u8; TAM_SAL] = [5u8; TAM_SAL];
    const NB: [u8; TAM_NONCE] = [6u8; TAM_NONCE];
    const CORPUS: &str = "/mnt/IA_LAB/agentes/PJPG/verificacion/corpus-validos";

    fn reales(n: usize) -> (Vec<Vec<u8>>, Vec<Vec<u8>>) {
        let mut r: Vec<_> = fs::read_dir(CORPUS).unwrap().filter_map(|e| e.ok())
            .map(|e| e.path()).filter(|p| p.extension().map_or(false, |x| x == "pjg")).collect();
        r.sort(); r.truncate(n);
        let datos = r.iter().map(|p| fs::read(p).unwrap()).collect();
        let nombres = r.iter().map(|p| p.file_name().unwrap()
            .to_string_lossy().as_bytes().to_vec()).collect();
        (datos, nombres)
    }

    fn ents<'a>(d: &'a [Vec<u8>], n: &'a [Vec<u8>]) -> Vec<Entrada<'a>> {
        d.iter().zip(n).map(|(d, n)| Entrada {
            nombre: n, tam_orig: d.len() as u64 * 2, payload: d,
            hash: { let h = blake3::hash(d); let mut a=[0u8;16];
                    a.copy_from_slice(&h.as_bytes()[..16]); a },
        }).collect()
    }

    #[test] fn round_trip_cifrado_con_pjg_reales() {
        let (d, n) = reales(8);
        let clave = cifrado::derivar_clave("contraseña de prueba".as_bytes(), &SAL).unwrap();
        let (bytes, _) = escribir(&ents(&d, &n), FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();

        // El indice NO puede leerse sin la clave: viaja adentro de los trozos.
        assert!(indice::leer_indice(&bytes).is_err(),
                "el indice cifrado no debe poder deserializarse en claro");
        // Y ningun nombre del corpus aparece en el archivo.
        for nombre in &n {
            assert!(bytes.windows(nombre.len()).all(|w| w != &nombre[..]),
                    "un nombre quedo visible en el contenedor cifrado");
        }

        let a = abrir(&bytes, Some("contraseña de prueba".as_bytes())).unwrap();
        assert_eq!(a.contenedor.miembros.len(), d.len());
        for (i, p) in a.payloads.iter().enumerate() {
            assert_eq!(p, &d[i], "miembro {i} no salio byte-exacto");
            let h = blake3::hash(p);
            assert_eq!(&h.as_bytes()[..16], &a.contenedor.miembros[i].hash[..]);
        }
    }

    #[test] fn round_trip_sin_cifrar_sigue_andando() {
        let (d, n) = reales(5);
        let (bytes, _) = escribir(&ents(&d, &n), 0, None).unwrap();
        let a = abrir(&bytes, None).unwrap();
        assert_eq!(a.payloads.len(), 5);
        assert_eq!(a.payloads[0], d[0]);
    }

    #[test] fn contraseña_incorrecta_no_llega_al_indice() {
        let (d, n) = reales(4);
        let clave = cifrado::derivar_clave(b"buena", &SAL).unwrap();
        let (bytes, _) = escribir(&ents(&d, &n), FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();
        match abrir(&bytes, Some(b"mala")) {
            Err(Error::Cifrado(cifrado::Error::TrozoAlterado(0))) => {}
            otro => panic!("esperaba fallo de autenticacion, dio {otro:?}"),
        }
    }

    #[test] fn contraseña_faltante_y_sobrante() {
        let (d, n) = reales(3);
        let clave = cifrado::derivar_clave(b"x", &SAL).unwrap();
        let (cif, _) = escribir(&ents(&d, &n), FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();
        assert_eq!(abrir(&cif, None).err(), Some(Error::ContraseñaFaltante));
        let (llano, _) = escribir(&ents(&d, &n), 0, None).unwrap();
        assert_eq!(abrir(&llano, Some(b"x")).err(), Some(Error::ContraseñaSobrante));
        assert_eq!(escribir(&ents(&d, &n), FLAG_CIFRADO, None).err(), Some(Error::ContraseñaFaltante));
    }

    #[test] fn un_bit_en_el_cuerpo_cifrado_no_llega_al_codec() {
        let (d, n) = reales(4);
        let clave = cifrado::derivar_clave(b"x", &SAL).unwrap();
        let (mut bytes, _) = escribir(&ents(&d, &n), FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();
        let p = TAM_CABECERA + TAM_SAL + TAM_NONCE + 40;
        bytes[p] ^= 1;
        assert!(matches!(abrir(&bytes, Some(b"x")),
                Err(Error::Cifrado(cifrado::Error::TrozoAlterado(_)))));
    }

    #[test] fn rutas_y_unicode_cifrados() {
        let (d, _) = reales(2);
        let n: Vec<Vec<u8>> = vec!["2026/enero/ñandú.jpg".into(), "2026/enero/写真.jpg".into()];
        let clave = cifrado::derivar_clave(b"x", &SAL).unwrap();
        let (bytes, av) = escribir(&ents(&d, &n), FLAG_CIFRADO | FLAG_RUTAS,
                                   Some((&clave, &NB, &SAL))).unwrap();
        assert!(av.is_empty());
        let a = abrir(&bytes, Some(b"x")).unwrap();
        assert_eq!(a.contenedor.miembros[0].nombre, "2026/enero/ñandú.jpg".as_bytes());
    }
}
