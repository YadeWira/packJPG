//! Une el contenedor con el cifrado.
//!
//! Cuando `FLAG_CIFRADO` está puesto, **índice y payloads viajan en la misma
//! secuencia de trozos**: el índice no se puede leer sin haber autenticado.
//! Ese orden es lo que da la seguridad, no los chequeos sueltos.
//!
//! Layout cifrado:
//! ```text
//!   magia · version · flags · reservado        (en claro, 8 bytes)
//!   tam_indice(4) · hash(16)                   (en claro CERO; los de verdad
//!                                               van adentro del cifrado)
//!   sal(16) · nonce_base(24)                   (en claro)
//!   trozos AEAD de [ tam_indice ‖ hash ‖ índice ‖ payloads ]
//! ```
//! **`tam_indice` y el hash no pueden quedar en claro.** El hash es
//! BLAKE3(cabecera ‖ índice) y el índice es la lista de nombres: dejarlo
//! visible convierte el archivo en un oráculo de confirmación — cualquiera
//! que sospeche qué nombres hay adentro los tipea, calcula el hash y compara,
//! sin contraseña. `tam_indice` por su lado deja leer cuántos miembros hay y
//! cuán largos son sus nombres. Los dos campos se ponen en cero en la
//! cabecera de disco y se llevan al frente del cuerpo cifrado, donde el AEAD
//! ya los autentica.
//!
//! La cabecera en claro queda entonces con lo mínimo para saber qué archivo
//! es y si hace falta contraseña: magia, versión, flags y reservado.

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

/// Lo que queda visible de la cabecera cuando el contenedor está cifrado:
/// magia(4) + version(1) + flags(1) + reservado(2).
const TAM_CLARO_CABECERA: usize = 8;
/// Lo que se muda adentro del cifrado: tam_indice(4) + hash(16).
const TAM_SECRETO_CABECERA: usize = TAM_CABECERA - TAM_CLARO_CABECERA;

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
            // Del encabezado sólo sobreviven en claro los 8 bytes que hacen
            // falta para identificar el archivo y saber que pide contraseña.
            // tam_indice y el hash se mudan al frente del cuerpo cifrado.
            let mut cuerpo = Vec::with_capacity(TAM_SECRETO_CABECERA + plano.len() - TAM_CABECERA);
            cuerpo.extend_from_slice(&plano[TAM_CLARO_CABECERA..TAM_CABECERA]);
            cuerpo.extend_from_slice(&plano[TAM_CABECERA..]);
            let ct = cifrado::cifrar(clave, nonce, &cuerpo).map_err(Error::Cifrado)?;
            let mut out = Vec::with_capacity(TAM_CABECERA + TAM_PREFIJO_CIFRADO + ct.len());
            out.extend_from_slice(&plano[..TAM_CLARO_CABECERA]);
            out.resize(TAM_CABECERA, 0);   // tam_indice y hash en cero
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
    // La cabecera se valida ANTES de mirar el bit de cifrado. Sacando flags
    // del byte crudo, 200 bytes de basura cuyo byte 5 tuviera el bit puesto
    // se rechazaban por "falta contraseña" en vez de por "no es un
    // contenedor" -- la magia dejaba de ser lo primero que se chequea.
    // Lo agarro la prueba de frontera en C++.
    //
    // De `leer_cabecera` acá sólo sirven magia, version, flags y reservado:
    // el tam_indice que devuelve es el de disco, que con cifrado es cero.
    let (flags, _, _) = indice::leer_cabecera(datos).map_err(Error::Indice)?;
    let cifrado_puesto = flags & FLAG_CIFRADO != 0;

    let plano: Vec<u8> = if cifrado_puesto {
        let pass = pass.ok_or(Error::ContraseñaFaltante)?;
        if datos.len() < TAM_CABECERA + TAM_PREFIJO_CIFRADO { return Err(Error::ArchivoCorto); }
        // Con cifrado, esos 20 bytes tienen que estar en cero: los de verdad
        // van adentro. Si no se exigiera, serian 160 bits del archivo que no
        // significan nada, y un bit volteado ahi pasaria sin que nadie lo
        // note -- que es justo lo que la bateria de corrupcion busca.
        if datos[TAM_CLARO_CABECERA..TAM_CABECERA].iter().any(|&b| b != 0) {
            return Err(Error::Indice(indice::Error::IndiceAlterado));
        }
        let mut sal = [0u8; TAM_SAL];
        sal.copy_from_slice(&datos[TAM_CABECERA .. TAM_CABECERA + TAM_SAL]);
        let mut nonce = [0u8; TAM_NONCE];
        nonce.copy_from_slice(&datos[TAM_CABECERA + TAM_SAL .. TAM_CABECERA + TAM_PREFIJO_CIFRADO]);

        let clave = cifrado::derivar_clave(pass, &sal).map_err(Error::Cifrado)?;
        // Autenticar ANTES de mirar el indice.
        let cuerpo = cifrado::descifrar(&clave, &nonce,
                        &datos[TAM_CABECERA + TAM_PREFIJO_CIFRADO ..]).map_err(Error::Cifrado)?;
        // El cuerpo empieza con los campos que sacamos de la cabecera. Al
        // reponerlos queda el mismo `plano` que en el caso sin cifrar, y de
        // ahi para abajo el camino es uno solo.
        if cuerpo.len() < TAM_SECRETO_CABECERA { return Err(Error::ArchivoCorto); }
        let mut v = Vec::with_capacity(TAM_CLARO_CABECERA + cuerpo.len());
        v.extend_from_slice(&datos[..TAM_CLARO_CABECERA]);
        v.extend_from_slice(&cuerpo);
        v
    } else {
        if pass.is_some() { return Err(Error::ContraseñaSobrante); }
        datos.to_vec()
    };

    // tam_indice se lee del plano, no del disco: cuando hay cifrado el de
    // disco es cero a proposito.
    let (_, tam_indice, _) = indice::leer_cabecera(&plano).map_err(Error::Indice)?;

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

    /// El archivo cifrado no puede confirmar qué nombres hay adentro.
    ///
    /// El hash declarado es BLAKE3(cabecera ‖ índice) y el índice es la lista
    /// de nombres. Si ese hash queda en claro, cualquiera que sospeche los
    /// nombres los tipea, rearma el índice, calcula el hash y compara — sin
    /// contraseña. La prueba hace exactamente ese ataque y exige que falle.
    ///
    /// Con **control positivo en la misma prueba**: el mismo ataque contra el
    /// contenedor SIN cifrar tiene que tener éxito. Sin esa mitad, un ataque
    /// que no funciona porque está mal armado se ve igual que uno que no
    /// funciona porque el formato lo impide.
    #[test] fn el_cifrado_no_deja_confirmar_los_nombres() {
        let (d, n) = reales(4);
        let e = ents(&d, &n);

        // -- control positivo: sin cifrar, el hash declarado ESTÁ en el archivo
        let (claro, _) = escribir(&e, 0, None).unwrap();
        let (_, ti, hash_claro) = indice::leer_cabecera(&claro).unwrap();
        let recalculado = indice::hash_cabecera_indice(
            &claro[..TAM_CABECERA], &claro[TAM_CABECERA..TAM_CABECERA + ti as usize]);
        assert_eq!(hash_claro, recalculado,
            "control: sin cifrar el hash del índice tiene que ser verificable desde afuera");
        assert!(claro.windows(16).any(|w| w == recalculado),
            "control: el hash tiene que aparecer literal en el archivo sin cifrar");

        // -- el caso real: cifrado, ese mismo hash no aparece en ningún lado
        let clave = cifrado::derivar_clave(b"correcta", &SAL).unwrap();
        let (cif, _) = escribir(&e, FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();
        assert!(!cif.windows(16).any(|w| w == recalculado),
            "el hash del índice quedó legible: el archivo confirma los nombres sin contraseña");
        assert!(cif[TAM_CLARO_CABECERA..TAM_CABECERA].iter().all(|&b| b == 0),
            "tam_indice y el hash tienen que estar en cero en la cabecera de disco");
        // y tam_indice tampoco se lee de afuera
        assert_eq!(indice::leer_cabecera(&cif).unwrap().1, 0,
            "tam_indice en claro delata cuántos miembros hay");

        // -- y sigue abriendo con la contraseña
        let a = abrir(&cif, Some(b"correcta")).unwrap();
        assert_eq!(a.contenedor.miembros.len(), 4);
        assert_eq!(a.payloads, d);
    }

    /// Los 20 bytes que se mudaron adentro no pueden quedar como relleno
    /// libre: si se aceptara cualquier cosa ahí, serían 160 bits del archivo
    /// que un bit volteado no cambia y nadie detecta.
    #[test] fn los_campos_mudados_deben_estar_en_cero() {
        let (d, n) = reales(3);
        let e = ents(&d, &n);
        let clave = cifrado::derivar_clave(b"pass", &SAL).unwrap();
        let (cif, _) = escribir(&e, FLAG_CIFRADO, Some((&clave, &NB, &SAL))).unwrap();
        assert!(abrir(&cif, Some(b"pass")).is_ok(), "control: intacto tiene que abrir");
        let mut celdas = 0; let mut rechazadas = 0;
        for i in TAM_CLARO_CABECERA..TAM_CABECERA {
            for bit in 0..8 {
                celdas += 1;
                let mut m = cif.clone();
                m[i] ^= 1 << bit;
                if abrir(&m, Some(b"pass")).is_err() { rechazadas += 1; }
            }
        }
        assert_eq!(celdas, 160, "la cuenta de celdas tiene que ser 20 bytes x 8 bits");
        assert_eq!(rechazadas, celdas, "quedaron bits sin significado en la cabecera");
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
