//! Cabecera e índice del contenedor. Layout en `doc/FORMATO.md`.
//!
//! Todo lo de acá corre **antes** de que un byte llegue al códec: es el
//! filtro donde se rechaza una bomba sin haber decodificado nada.

use crate::limites::*;
use crate::nombres::{self, Veredicto};

#[cfg(not(test))] use alloc::vec::Vec;
use alloc::collections::BTreeSet;

pub const MAGIA: [u8; 4] = [b'P', b'J', b'A', 0x01];
pub const VERSION: u8 = 1;

pub const FLAG_CIFRADO: u8 = 1 << 0;
pub const FLAG_RUTAS: u8 = 1 << 1;
pub const FLAG_SOLIDO: u8 = 1 << 2;
const FLAGS_CONOCIDOS: u8 = FLAG_CIFRADO | FLAG_RUTAS | FLAG_SOLIDO;

/// magia(4) + version(1) + flags(1) + kdf(1) + reservado(1) + tam_indice(4) + hash_indice(16)
///
/// `kdf` identifica el perfil de derivación de clave y **sólo puede ser
/// distinto de cero con `FLAG_CIFRADO` puesto**. Existe para que subir el costo
/// de Argon2 más adelante no vuelva ilegibles los archivos ya escritos: quien
/// abra el contenedor tiene que derivar exactamente la misma clave que quien lo
/// escribió, así que el parámetro es parte del formato, se quiera o no. Va como
/// identificador y no como `m`/`t`/`p` crudos: números crudos serían pedir
/// memoria arbitraria antes de validar nada, y habría que acotarlos igual.
///
/// Queda dentro de `cab[0..12]`, que es lo que cubre el hash del índice, así
/// que voltear ese byte no pasa desapercibido.
pub const TAM_CABECERA: usize = 4 + 1 + 1 + 2 + 4 + 16;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Error {
    NoEsContenedor,
    VersionFutura(u8),
    FlagDesconocido,
    ReservadoNoCero,
    ArchivoCorto,
    IndiceNoEntra,
    DemasiadosMiembros(u32),
    CountImposible,
    NombreInvalido(usize),
    NombreDuplicado(usize),
    PayloadFueraDeRango(usize),
    SumaNoCuadra,
    RatioExcedido,
    PresupuestoExcedido,
    Desborde,
    IndiceTruncado,
    /// La cabecera o el índice no coinciden con el hash declarado.
    IndiceAlterado,
    /// El contenedor declara un perfil de derivación de clave que esta versión
    /// no conoce. Viene de un packJPG más nuevo.
    PerfilKdfDesconocido(u8),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Miembro {
    pub nombre: Vec<u8>,
    pub tam_orig: u64,
    pub tam_payload: u64,
    pub hash: [u8; 16],
    pub m_flags: u8,
}

#[derive(Debug)]
pub struct Contenedor {
    pub flags: u8,
    pub miembros: Vec<Miembro>,
}

/// Hash de la **cabecera y el índice**, truncado a 128 bits.
///
/// Cubre los dos a propósito. Un hash que sólo cubriera el índice deja
/// `flags` sin proteger, y ese byte decide si el contenedor está cifrado, si
/// preserva rutas —lo que cambia cómo se validan todos los nombres— y si es
/// sólido. Medido: con el hash sólo sobre el índice, un bit en `flags` producía
/// un contenedor que se leía sin error y con otro significado.
///
/// El propio campo de hash se excluye, porque incluirse a sí mismo es circular.
pub fn hash_cabecera_indice(cab: &[u8], idx: &[u8]) -> [u8; 16] {
    let mut h = blake3::Hasher::new();
    h.update(&cab[0..12]);   // magia, version, flags, reservado, tam_indice
    h.update(idx);           // se saltea cab[12..28], que es el hash mismo
    let mut a = [0u8; 16];
    a.copy_from_slice(&h.finalize().as_bytes()[..16]);
    a
}

fn u32le(b: &[u8]) -> u32 { u32::from_le_bytes([b[0], b[1], b[2], b[3]]) }
fn u64le(b: &[u8]) -> u64 {
    u64::from_le_bytes([b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7]])
}

/// Lee y valida la cabecera. Devuelve `(flags, tam_indice)`.
pub fn leer_cabecera(datos: &[u8]) -> Result<(u8, u32, [u8; 16]), Error> {
    if datos.len() < TAM_CABECERA { return Err(Error::ArchivoCorto); }
    if datos[0..4] != MAGIA { return Err(Error::NoEsContenedor); }
    let version = datos[4];
    if version > VERSION { return Err(Error::VersionFutura(version)); }
    let flags = datos[5];
    if flags & !FLAGS_CONOCIDOS != 0 { return Err(Error::FlagDesconocido); }
    if datos[7] != 0 { return Err(Error::ReservadoNoCero); }
    // El perfil de KDF sólo tiene sentido cifrando; y sólo puede valer lo que
    // esta versión conoce. Un perfil desconocido se rechaza en vez de caer a
    // uno por defecto: derivar con los parámetros equivocados da una clave
    // equivocada, y eso se manifestaría como "contraseña incorrecta" sobre un
    // archivo y una contraseña que estaban bien.
    if flags & FLAG_CIFRADO == 0 {
        if datos[6] != 0 { return Err(Error::ReservadoNoCero); }
    } else if crate::cifrado::PerfilKdf::de_byte( datos[6] ).is_none() {
        return Err(Error::PerfilKdfDesconocido( datos[6] ));
    }
    let tam_indice = u32le(&datos[8..12]);
    let mut hash_indice = [0u8; 16];
    hash_indice.copy_from_slice(&datos[12..28]);
    // El indice tiene que entrar en el archivo, cabecera incluida.
    if (tam_indice as u64) > datos.len() as u64 - TAM_CABECERA as u64 {
        return Err(Error::IndiceNoEntra);
    }
    Ok((flags, tam_indice, hash_indice))
}

/// Deserializa y valida el índice completo. Aplica los seis límites de
/// `POLITICA.md` **antes** de devolver nada usable.
pub fn leer_indice(datos: &[u8]) -> Result<Contenedor, Error> {
    let (flags, tam_indice, hash_decl) = leer_cabecera(datos)?;
    let ini = TAM_CABECERA;
    let fin = ini + tam_indice as usize;
    let idx = &datos[ini..fin];

    // El hash del indice se verifica ANTES de deserializar nada. Sin esto, un
    // bit alterado ahi produce un contenedor que se lee sin error y con
    // metadatos distintos: nombre cambiado, tamaño declarado cambiado, o el
    // hash de un miembro cambiado -- que haria fallar la verificacion sobre un
    // archivo sano.
    if hash_cabecera_indice(&datos[..TAM_CABECERA], idx) != hash_decl {
        return Err(Error::IndiceAlterado);
    }

    if idx.len() < 4 { return Err(Error::IndiceTruncado); }
    let count = u32le(&idx[0..4]);

    // Limite 1: tope absoluto, antes de reservar nada.
    if count > MAX_MIEMBROS { return Err(Error::DemasiadosMiembros(count)); }
    // Limite 2: el indice minimo tiene que caber en el archivo real.
    if (count as u64).saturating_mul(MIN_BYTES_ENTRADA) > datos.len() as u64 {
        return Err(Error::CountImposible);
    }

    let mut miembros: Vec<Miembro> = Vec::new();
    let mut p = 4usize;
    for _ in 0..count {
        if p + 2 > idx.len() { return Err(Error::IndiceTruncado); }
        let nlen = u16::from_le_bytes([idx[p], idx[p+1]]) as usize; p += 2;
        if p + nlen + 8 + 8 + 16 + 1 > idx.len() { return Err(Error::IndiceTruncado); }
        let nombre = idx[p..p+nlen].to_vec(); p += nlen;
        let tam_orig = u64le(&idx[p..p+8]); p += 8;
        let tam_payload = u64le(&idx[p..p+8]); p += 8;
        let mut hash = [0u8; 16];
        hash.copy_from_slice(&idx[p..p+16]); p += 16;
        let m_flags = idx[p]; p += 1;
        miembros.push(Miembro { nombre, tam_orig, tam_payload, hash, m_flags });
    }

    validar(&miembros, flags, datos.len() as u64, tam_indice as u64)?;
    Ok(Contenedor { flags, miembros })
}

/// Los seis límites, más los nombres. Separado para poder probarlo solo.
pub fn validar(ms: &[Miembro], flags: u8, tam_archivo: u64, tam_indice: u64)
    -> Result<(), Error>
{
    let mut suma_payload: u64 = 0;
    let mut suma_orig: u64 = 0;
    // Nombres ya vistos. Antes esto era un bucle sobre ms[..i] por cada miembro:
    // cuadratico, con un tope de 1.048.576 miembros. Medido el 25/09/2026 con un
    // archivo real armado a mano (hash del indice bien calculado, que no es
    // secreto): 60.000 nombres distintos en 2,82 MB tardaban 7,1 s en
    // leer_indice, y llevado al tope serian ~39 minutos con nombres cortos y
    // ~2,4 horas con nombres de 250 B -- todo ANTES de que el limite 3 note que
    // las sumas no cuadran. Exactamente la bomba que esta capa existe para parar.
    // BTreeSet porque es no_std (alloc); el orden de los errores no cambia: el
    // duplicado se reporta en el primer i cuyo nombre ya aparecio antes.
    let mut vistos: BTreeSet<&[u8]> = BTreeSet::new();

    for (i, m) in ms.iter().enumerate() {
        // Limite 6: ningun payload vacio ni imposible.
        if m.tam_payload < MIN_PAYLOAD || m.tam_payload > tam_archivo {
            return Err(Error::PayloadFueraDeRango(i));
        }
        // Sumar con deteccion de desborde: sumar y despues comparar es el bug.
        suma_payload = suma_payload.checked_add(m.tam_payload).ok_or(Error::Desborde)?;
        suma_orig    = suma_orig.checked_add(m.tam_orig).ok_or(Error::Desborde)?;

        let v = if flags & FLAG_RUTAS != 0 { nombres::ruta(&m.nombre) }
                else { nombres::plano(&m.nombre) };
        if let Veredicto::Rechazo(_) = v { return Err(Error::NombreInvalido(i)); }

        // Duplicados: se rechazan al abrir, no al extraer.
        if !vistos.insert(&m.nombre[..]) { return Err(Error::NombreDuplicado(i)); }
    }

    // Limite 3: la suma tiene que dar el archivo exacto. Con suma chequeada: en
    // release, `+` a secas da la vuelta en silencio y el resultado podria
    // coincidir con tam_archivo por casualidad. (Hace falta un archivo de mas de
    // 16 TiB para alcanzarlo, pero el port a Pascal con overflow checks lanzaria
    // excepcion ahi, y los dos tienen que dar lo mismo.)
    let total = suma_payload.checked_add(tam_indice)
        .and_then(|x| x.checked_add(TAM_CABECERA as u64))
        .ok_or(Error::Desborde)?;
    if total != tam_archivo {
        return Err(Error::SumaNoCuadra);
    }
    // Limite 4: el ratio, que escala solo.
    let techo = tam_archivo.checked_mul(MAX_RATIO_EXPANSION).ok_or(Error::Desborde)?;
    if suma_orig > techo { return Err(Error::RatioExcedido); }
    // Limite 5: presupuesto absoluto.
    if PRESUPUESTO_POR_DEFECTO > 0 && suma_orig > PRESUPUESTO_POR_DEFECTO {
        return Err(Error::PresupuestoExcedido);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Baterías 4.1 y 4.2 de `doc/FORMATO.md`, caso por caso.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod pruebas {
    use super::*;

    /// Arma un contenedor válido mínimo: N miembros con payloads de `tam`.
    fn armar(nombres: &[&[u8]], tam: u64, flags: u8) -> Vec<u8> {
        let mut idx: Vec<u8> = Vec::new();
        idx.extend_from_slice(&(nombres.len() as u32).to_le_bytes());
        for n in nombres {
            idx.extend_from_slice(&(n.len() as u16).to_le_bytes());
            idx.extend_from_slice(n);
            idx.extend_from_slice(&(tam * 2).to_le_bytes());  // tam_orig
            idx.extend_from_slice(&tam.to_le_bytes());        // tam_payload
            idx.extend_from_slice(&[0u8; 16]);                // hash
            idx.push(0);                                      // m_flags
        }
        let mut out: Vec<u8> = Vec::new();
        out.extend_from_slice(&MAGIA);
        out.push(VERSION);
        out.push(flags);
        out.extend_from_slice(&[0, 0]);
        out.extend_from_slice(&(idx.len() as u32).to_le_bytes());
        out.extend_from_slice(&[0u8; 16]);       // hueco del hash
        out.extend_from_slice(&idx);
        let h = hash_cabecera_indice(&out[..TAM_CABECERA], &idx);
        out[12..28].copy_from_slice(&h);
        out.resize(out.len() + (tam as usize) * nombres.len(), 0);
        out
    }


    /// Recalcula el hash del índice tras mutarlo. Hace falta porque el hash
    /// dispara ANTES que los límites: sin esto, la batería 4.2 quedaría
    /// enmascarada y esos seis chequeos no se ejercitarían nunca.
    fn resellar(c: &mut Vec<u8>) {
        let ti = u32le(&c[8..12]) as usize;
        let idx = c[TAM_CABECERA..TAM_CABECERA + ti].to_vec();
        let h = hash_cabecera_indice(&c[..TAM_CABECERA], &idx);
        c[12..28].copy_from_slice(&h);
    }

    #[test] fn el_control_positivo_un_contenedor_valido_se_lee() {
        let c = armar(&[b"a.jpg", b"b.jpg"], 100, 0);
        let leido = leer_indice(&c).expect("un contenedor valido tiene que leerse");
        assert_eq!(leido.miembros.len(), 2);
        assert_eq!(leido.miembros[0].nombre, b"a.jpg");
    }

    #[test] fn bateria_4_1_cabecera() {
        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[0] = b'X';
        assert_eq!(leer_cabecera(&c).err(), Some(Error::NoEsContenedor));

        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[4] = 99;
        assert_eq!(leer_cabecera(&c).err(), Some(Error::VersionFutura(99)));

        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[6] = 1;
        assert_eq!(leer_cabecera(&c).err(), Some(Error::ReservadoNoCero));

        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[5] = 0x80;
        assert_eq!(leer_cabecera(&c).err(), Some(Error::FlagDesconocido));

        assert_eq!(leer_cabecera(&[]).err(), Some(Error::ArchivoCorto));
        assert_eq!(leer_cabecera(&[0u8; 27]).err(), Some(Error::ArchivoCorto));

        // tam_indice = 0xFFFFFFFF: rechaza SIN reservar.
        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
        assert_eq!(leer_cabecera(&c).err(), Some(Error::IndiceNoEntra));
    }

    #[test] fn bateria_4_2_indice() {
        // count absurdo: tope absoluto, antes de reservar.
        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[TAM_CABECERA..TAM_CABECERA+4].copy_from_slice(&u32::MAX.to_le_bytes());
        resellar(&mut c);
        assert_eq!(leer_indice(&c).err(), Some(Error::DemasiadosMiembros(u32::MAX)));

        // count 10.000 en un archivo chico: limite 2.
        let mut c = armar(&[b"a.jpg"], 100, 0);
        c[TAM_CABECERA..TAM_CABECERA+4].copy_from_slice(&10_000u32.to_le_bytes());
        resellar(&mut c);
        assert_eq!(leer_indice(&c).err(), Some(Error::CountImposible));

        // suma que no cuadra con el tamaño real.
        let mut c = armar(&[b"a.jpg"], 100, 0);
        c.push(0);
        assert_eq!(leer_indice(&c).err(), Some(Error::SumaNoCuadra));

        // payload de 0: limite 6.
        let c = armar(&[b"a.jpg"], 0, 0);
        assert_eq!(leer_indice(&c).err(), Some(Error::PayloadFueraDeRango(0)));

        // nombre duplicado.
        let c = armar(&[b"a.jpg", b"a.jpg"], 100, 0);
        assert_eq!(leer_indice(&c).err(), Some(Error::NombreDuplicado(1)));

        // nombre invalido.
        let c = armar(&[b"../x.jpg"], 100, 0);
        assert_eq!(leer_indice(&c).err(), Some(Error::NombreInvalido(0)));
    }


    #[test] fn el_hash_del_indice_detecta_un_bit_alterado() {
        let base = armar(&[b"a.jpg", b"b.jpg"], 100, 0);
        assert!(leer_indice(&base).is_ok(), "control positivo");
        // Un bit en el NOMBRE, dentro del indice: antes se leia sin error y
        // con el nombre cambiado.
        let mut c = base.clone();
        c[TAM_CABECERA + 6] ^= 0x20;
        assert_eq!(leer_indice(&c).err(), Some(Error::IndiceAlterado));
        // Y con el hash recalculado se lee: el chequeo mira el indice, no un byte fijo.
        resellar(&mut c);
        assert!(leer_indice(&c).is_ok());
    }

    /// Nombres distintos que obligaban a comparar todos contra todos. Con la
    /// version cuadratica, 200.000 miembros son ~85 s en la maquina donde se
    /// midio; con el conjunto, una fraccion de segundo. El margen de 10 s es
    /// para que la prueba no sea fragil en un runner lento, no una cota fina.
    #[test] fn los_duplicados_no_son_cuadraticos() {
        let n = 200_000usize;
        let ms: Vec<Miembro> = (0..n).map(|i| {
            let mut nom = b"aaaa".to_vec();
            nom.extend_from_slice(format!("{:08}", i).as_bytes());
            Miembro { nombre: nom, tam_orig: 100, tam_payload: 100, hash: [0; 16], m_flags: 0 }
        }).collect();
        let t = std::time::Instant::now();
        let r = validar(&ms, 0, 1u64 << 40, 50);
        let s = t.elapsed().as_secs_f64();
        assert_eq!(r, Err(Error::SumaNoCuadra), "tiene que llegar al limite 3");
        assert!(s < 10.0, "validar tardo {s:.1} s con {n} nombres distintos");
    }

    /// Y el duplicado se sigue reportando en el MISMO indice que antes: el
    /// primero cuyo nombre ya aparecio, no el segundo de la pareja.
    #[test] fn el_duplicado_se_reporta_en_el_mismo_indice() {
        let m = |n: &[u8]| Miembro { nombre: n.to_vec(), tam_orig: 100, tam_payload: 100, hash: [0; 16], m_flags: 0 };
        let ms = vec![m(b"a"), m(b"b"), m(b"c"), m(b"b"), m(b"a")];
        assert_eq!(validar(&ms, 0, 1u64 << 40, 50), Err(Error::NombreDuplicado(3)));
    }

    #[test] fn la_suma_del_limite_3_no_da_la_vuelta() {
        // un solo payload enorme (limite 6 lo deja pasar con tam_archivo = MAX):
        // suma_payload no desborda, pero sumarle el indice y la cabecera si.
        let ms = vec![Miembro { nombre: b"a".to_vec(), tam_orig: 1, tam_payload: u64::MAX - 10,
                                hash: [0; 16], m_flags: 0 }];
        assert_eq!(validar(&ms, 0, u64::MAX, 50), Err(Error::Desborde));
    }

    #[test] fn la_suma_no_desborda_antes_de_comparar() {
        let ms = vec![
            Miembro { nombre: b"a".to_vec(), tam_orig: u64::MAX, tam_payload: 100,
                      hash: [0;16], m_flags: 0 },
            Miembro { nombre: b"b".to_vec(), tam_orig: u64::MAX, tam_payload: 100,
                      hash: [0;16], m_flags: 0 },
        ];
        // Sumar y despues comparar habria dado la vuelta y pasado el chequeo.
        assert_eq!(validar(&ms, 0, 1000, 50), Err(Error::Desborde));
    }
}
