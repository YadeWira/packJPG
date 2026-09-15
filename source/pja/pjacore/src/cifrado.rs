//! Cifrado autenticado por trozos.
//!
//! **El MAC se verifica antes de que un byte llegue al códec.** No es por el
//! secreto: sin autenticar, un atacante tendría un oráculo de bits volteados
//! apuntando al decodificador, que es justo la clase de defecto que costó
//! semanas encontrar en packJPG.
//!
//! Por trozos y no en un bloque porque un AEAD único obligaría a tener el
//! contenedor entero en memoria antes de verificar el tag; con 5 GB no es
//! viable.
//!
//! Las dos reglas que se olvidan y son el error clásico del cifrado por trozos:
//! el **número de trozo va en el AAD**, así reordenar falla; y el **último
//! trozo se marca en su propio AAD**, así truncar falla. Sin ellas, cada tag
//! individual sigue siendo válido y lo que cambia es el conjunto.

use chacha20poly1305::{XChaCha20Poly1305, XNonce, KeyInit, aead::{Aead, Payload}};

#[cfg(not(test))] use alloc::vec::Vec;

pub const TAM_TROZO: usize = 64 * 1024;
pub const TAM_TAG: usize = 16;
pub const TAM_SAL: usize = 16;
pub const TAM_NONCE: usize = 24;

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    ClaveIncorrecta,
    /// Un trozo no autenticó: alterado, reordenado, duplicado o de otro archivo.
    TrozoAlterado(usize),
    /// El último trozo no está marcado como tal: el archivo fue truncado.
    Truncado,
    Formato,
}

/// Perfil de derivación de clave. Va identificado por un byte en la cabecera,
/// no por sus números: un contenedor que declarara `m` y `t` crudos sería un
/// vector de DoS —pedir 4 GiB de memoria antes de validar nada— y habría que
/// acotarlo igual. Un identificador de perfil sólo puede valer lo que nosotros
/// definimos, y un perfil desconocido se rechaza.
///
/// El perfil no se puede cambiar sin cambiar el identificador: quien abra el
/// archivo tiene que poder derivar exactamente la misma clave.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PerfilKdf {
    /// v1: Argon2id, m = 64 MiB, t = 3, p = 1.
    ///
    /// Por arriba del mínimo de OWASP (19 MiB, t=2), que a 30 ms dejaba mucho
    /// margen sin usar. Medido en esta máquina: el mínimo costaba ~30 ms y este
    /// perfil ~100 ms. Para el usuario legítimo sigue siendo imperceptible en
    /// una CLI; para quien prueba un diccionario, el trabajo por intento se
    /// multiplica y la memoria requerida es lo que estorba a una GPU.
    V1,
}

impl PerfilKdf {
    pub fn de_byte(b: u8) -> Option<Self> {
        match b { 0 => Some(PerfilKdf::V1), _ => None }
    }
    pub fn a_byte(self) -> u8 {
        match self { PerfilKdf::V1 => 0 }
    }
    /// (memoria en KiB, pasadas, paralelismo)
    fn params(self) -> (u32, u32, u32) {
        match self { PerfilKdf::V1 => (64 * 1024, 3, 1) }
    }
}

/// Argon2id sobre la contraseña. No es un hash rápido a propósito.
pub fn derivar_clave(pass: &[u8], sal: &[u8; TAM_SAL]) -> Result<[u8; 32], Error> {
    derivar_clave_con(PerfilKdf::V1, pass, sal)
}

pub fn derivar_clave_con(perfil: PerfilKdf, pass: &[u8], sal: &[u8; TAM_SAL])
    -> Result<[u8; 32], Error>
{
    use argon2::{Argon2, Algorithm, Version, Params};
    let (m, t, p) = perfil.params();
    let params = Params::new(m, t, p, Some(32)).map_err(|_| Error::Formato)?;
    let a2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut clave = [0u8; 32];
    a2.hash_password_into(pass, sal, &mut clave).map_err(|_| Error::Formato)?;
    Ok(clave)
}

/// Nonce del trozo `i`: la base con el contador mezclado en los últimos 8
/// bytes. Nunca se repite dentro de un archivo, que es la propiedad que hace
/// falta.
fn nonce_de(base: &[u8; TAM_NONCE], i: u64) -> XNonce {
    let mut n = *base;
    let c = i.to_le_bytes();
    for k in 0..8 { n[TAM_NONCE - 8 + k] ^= c[k]; }
    *XNonce::from_slice(&n)
}

/// AAD del trozo: número y marca de último. Es lo que ata el trozo a su
/// posición y al final del archivo.
fn aad_de(i: u64, ultimo: bool) -> [u8; 9] {
    let mut a = [0u8; 9];
    a[..8].copy_from_slice(&i.to_le_bytes());
    a[8] = ultimo as u8;
    a
}

pub fn cifrar(clave: &[u8; 32], nonce_base: &[u8; TAM_NONCE], datos: &[u8]) -> Result<Vec<u8>, Error> {
    let c = XChaCha20Poly1305::new(clave.into());
    let mut out = Vec::new();
    let total = datos.len().div_ceil(TAM_TROZO).max(1);
    for i in 0..total {
        let ini = i * TAM_TROZO;
        let fin = core::cmp::min(ini + TAM_TROZO, datos.len());
        let ultimo = i + 1 == total;
        let aad = aad_de(i as u64, ultimo);
        let ct = c.encrypt(&nonce_de(nonce_base, i as u64),
                           Payload { msg: &datos[ini..fin], aad: &aad })
                  .map_err(|_| Error::Formato)?;
        out.extend_from_slice(&(ct.len() as u32).to_le_bytes());
        out.extend_from_slice(&ct);
    }
    Ok(out)
}

pub fn descifrar(clave: &[u8; 32], nonce_base: &[u8; TAM_NONCE], datos: &[u8]) -> Result<Vec<u8>, Error> {
    let c = XChaCha20Poly1305::new(clave.into());
    let mut out = Vec::new();
    let mut p = 0usize;
    let mut i = 0u64;
    let mut vi_el_ultimo = false;

    while p < datos.len() {
        if p + 4 > datos.len() { return Err(Error::Formato); }
        let len = u32::from_le_bytes([datos[p], datos[p+1], datos[p+2], datos[p+3]]) as usize;
        p += 4;
        if len < TAM_TAG || p + len > datos.len() { return Err(Error::Formato); }
        let ct = &datos[p..p+len]; p += len;

        // Se prueba primero como trozo intermedio y despues como ultimo: el AAD
        // los distingue, asi que sólo uno de los dos puede autenticar.
        let n = nonce_de(nonce_base, i);
        let pt = match c.decrypt(&n, Payload { msg: ct, aad: &aad_de(i, false) }) {
            Ok(v) => v,
            Err(_) => match c.decrypt(&n, Payload { msg: ct, aad: &aad_de(i, true) }) {
                Ok(v) => { vi_el_ultimo = true; v }
                Err(_) => return Err(Error::TrozoAlterado(i as usize)),
            },
        };
        out.extend_from_slice(&pt);
        i += 1;
    }
    // Sin esto, cortar el archivo por un limite de trozo pasaria inadvertido:
    // todos los trozos que quedan autentican perfecto.
    if !vi_el_ultimo { return Err(Error::Truncado); }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Batería 4.4 de `doc/FORMATO.md`.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;

    const SAL: [u8; TAM_SAL] = [7u8; TAM_SAL];
    const NB: [u8; TAM_NONCE] = [3u8; TAM_NONCE];

    fn clave(p: &[u8]) -> [u8; 32] { derivar_clave(p, &SAL).unwrap() }

    /// Tres trozos y pico, para que reordenar y truncar tengan sentido.
    fn datos() -> Vec<u8> {
        (0..TAM_TROZO * 3 + 1234).map(|i| (i % 251) as u8).collect()
    }

    /// Devuelve los trozos como (inicio, largo_total_con_prefijo).
    fn trozos(c: &[u8]) -> Vec<(usize, usize)> {
        let mut v = Vec::new(); let mut p = 0;
        while p < c.len() {
            let len = u32::from_le_bytes([c[p],c[p+1],c[p+2],c[p+3]]) as usize;
            v.push((p, 4 + len)); p += 4 + len;
        }
        v
    }

    #[test] fn control_positivo_round_trip() {
        let d = datos(); let k = clave(b"secreta");
        let ct = cifrar(&k, &NB, &d).unwrap();
        assert_ne!(&ct[..64], &d[..64], "el ciphertext no puede parecerse al claro");
        assert_eq!(descifrar(&k, &NB, &ct).unwrap(), d);
    }

    #[test] fn contraseña_incorrecta_no_llega_al_codec() {
        let d = datos(); let ct = cifrar(&clave(b"secreta"), &NB, &d).unwrap();
        assert_eq!(descifrar(&clave(b"otra"), &NB, &ct), Err(Error::TrozoAlterado(0)));
    }

    #[test] fn un_bit_volteado_falla_el_tag() {
        let d = datos(); let k = clave(b"secreta");
        let mut ct = cifrar(&k, &NB, &d).unwrap();
        let t = trozos(&ct);
        ct[t[1].0 + 10] ^= 1;
        assert_eq!(descifrar(&k, &NB, &ct), Err(Error::TrozoAlterado(1)));
    }

    #[test] fn sal_distinta_da_clave_distinta() {
        let d = datos();
        let ct = cifrar(&clave(b"secreta"), &NB, &d).unwrap();
        let otra = derivar_clave(b"secreta", &[9u8; TAM_SAL]).unwrap();
        assert_eq!(descifrar(&otra, &NB, &ct), Err(Error::TrozoAlterado(0)));
    }

    #[test] fn dos_trozos_intercambiados_fallan_por_el_aad() {
        let d = datos(); let k = clave(b"secreta");
        let ct = cifrar(&k, &NB, &d).unwrap();
        let t = trozos(&ct);
        // Trozos 0 y 1 son del mismo largo; se intercambian enteros.
        assert_eq!(t[0].1, t[1].1);
        let mut mal = ct.clone();
        mal[t[0].0 .. t[0].0 + t[0].1].copy_from_slice(&ct[t[1].0 .. t[1].0 + t[1].1]);
        mal[t[1].0 .. t[1].0 + t[1].1].copy_from_slice(&ct[t[0].0 .. t[0].0 + t[0].1]);
        assert_eq!(descifrar(&k, &NB, &mal), Err(Error::TrozoAlterado(0)),
                   "cada tag sigue siendo valido: lo que cambia es el orden");
    }

    #[test] fn quitar_el_ultimo_trozo_falla_por_la_marca_de_fin() {
        let d = datos(); let k = clave(b"secreta");
        let ct = cifrar(&k, &NB, &d).unwrap();
        let t = trozos(&ct);
        let cortado = &ct[..t[t.len()-1].0];
        // Todos los trozos que quedan autentican perfecto. Sin la marca de
        // ultimo, esto pasaria inadvertido.
        assert_eq!(descifrar(&k, &NB, cortado), Err(Error::Truncado));
    }

    #[test] fn trozo_duplicado_falla_por_el_contador() {
        let d = datos(); let k = clave(b"secreta");
        let ct = cifrar(&k, &NB, &d).unwrap();
        let t = trozos(&ct);
        let mut mal = Vec::new();
        mal.extend_from_slice(&ct[t[0].0 .. t[0].0 + t[0].1]);
        mal.extend_from_slice(&ct[t[0].0 .. t[0].0 + t[0].1]);  // el 0 otra vez
        mal.extend_from_slice(&ct[t[2].0 ..]);
        assert_eq!(descifrar(&k, &NB, &mal), Err(Error::TrozoAlterado(1)));
    }

    #[test] fn nonce_distinto_por_trozo() {
        let a = nonce_de(&NB, 0); let b = nonce_de(&NB, 1); let c = nonce_de(&NB, 1000);
        assert_ne!(a, b); assert_ne!(b, c); assert_ne!(a, c);
    }
}
