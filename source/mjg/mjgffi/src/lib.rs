#![cfg_attr(not(test), no_std)]
//! Frontera C++ <-> Rust del contenedor.
//!
//! Angosta a propósito, y esa angostura es la garantía: cada `extern "C"` es
//! donde terminan las de Rust. Si la frontera fuera ancha, se obtendría lo peor
//! de los dos lenguajes.
//!
//! Reglas, todas verificables leyendo las firmas:
//! - entran punteros con largo, salen códigos de estado; **0 es éxito**
//! - **ninguna propiedad de memoria cruza**: los buffers los provee el llamador
//! - lo único con estado es un manejador opaco, con su `abrir`/`cerrar`
//! - `panic = "abort"`: un panic que desenrollara hacia C++ sería
//!   comportamiento indefinido
//!
//! `no_std` porque la `std` de Rust en Windows importa `WaitOnAddress`
//! (Windows 8+) y packJPG declara soporte desde Windows 7 SP1.

extern crate alloc;
use alloc::{boxed::Box, vec::Vec};
use mjgcore::{cifrado, contenedor, escritor::Entrada, indice};

mod asignador;

// --- códigos de estado -----------------------------------------------------
pub const MJG_OK: i32 = 0;
pub const MJG_ERR_NULL: i32 = -1;
pub const MJG_ERR_BUF_CHICO: i32 = -2;
pub const MJG_ERR_FORMATO: i32 = -3;
pub const MJG_ERR_LIMITE: i32 = -4;
pub const MJG_ERR_NOMBRE: i32 = -5;
pub const MJG_ERR_CLAVE: i32 = -6;
pub const MJG_ERR_INDICE: i32 = -7;
pub const MJG_ERR_RANGO: i32 = -8;

fn traducir(e: &contenedor::Error) -> i32 {
    use contenedor::Error as E;
    match e {
        E::ContraseñaFaltante | E::ContraseñaSobrante => MJG_ERR_CLAVE,
        E::Cifrado(_) => MJG_ERR_CLAVE,
        E::ArchivoCorto => MJG_ERR_FORMATO,
        E::Indice(i) => match i {
            indice::Error::NombreInvalido(_) | indice::Error::NombreDuplicado(_) => MJG_ERR_NOMBRE,
            indice::Error::IndiceAlterado => MJG_ERR_INDICE,
            indice::Error::DemasiadosMiembros(_) | indice::Error::CountImposible
            | indice::Error::RatioExcedido | indice::Error::PresupuestoExcedido
            | indice::Error::SumaNoCuadra | indice::Error::PayloadFueraDeRango(_)
            | indice::Error::Desborde => MJG_ERR_LIMITE,
            _ => MJG_ERR_FORMATO,
        },
        E::Escritura(_) => MJG_ERR_NOMBRE,
    }
}

/// Manejador opaco. El lado C++ nunca ve su interior.
pub struct MjgAbierto { inner: contenedor::Abierto }

// --- lectura ---------------------------------------------------------------

/// Abre un contenedor en memoria. `pass` puede ser nulo si no está cifrado.
///
/// # Safety
/// `datos` apunta a `largo` bytes legibles. `salida` recibe un manejador que
/// **debe liberarse con `mjg_cerrar`**.
#[no_mangle]
pub unsafe extern "C" fn mjg_abrir(
    datos: *const u8, largo: usize,
    pass: *const u8, pass_largo: usize,
    salida: *mut *mut MjgAbierto,
) -> i32 {
    if datos.is_null() || salida.is_null() { return MJG_ERR_NULL; }
    *salida = core::ptr::null_mut();
    let d = core::slice::from_raw_parts(datos, largo);
    let p = if pass.is_null() { None } else { Some(core::slice::from_raw_parts(pass, pass_largo)) };
    match contenedor::abrir(d, p) {
        Ok(a) => { *salida = Box::into_raw(Box::new(MjgAbierto { inner: a })); MJG_OK }
        Err(e) => traducir(&e),
    }
}

/// Libera el manejador. Pasar nulo es válido y no hace nada.
///
/// # Safety
/// `h` viene de `mjg_abrir` y no se usa después de esta llamada.
#[no_mangle]
pub unsafe extern "C" fn mjg_cerrar(h: *mut MjgAbierto) {
    if !h.is_null() { drop(Box::from_raw(h)); }
}

#[no_mangle]
pub unsafe extern "C" fn mjg_cantidad(h: *const MjgAbierto) -> i64 {
    if h.is_null() { return MJG_ERR_NULL as i64; }
    let a = &*h;
    a.inner.contenedor.miembros.len() as i64
}

/// Largo en bytes del nombre del miembro `i`, para que el llamador reserve.
#[no_mangle]
pub unsafe extern "C" fn mjg_nombre_largo(h: *const MjgAbierto, i: usize) -> i64 {
    if h.is_null() { return MJG_ERR_NULL as i64; }
    let a = &*h;
    match a.inner.contenedor.miembros.get(i) {
        Some(m) => m.nombre.len() as i64,
        None => MJG_ERR_RANGO as i64,
    }
}

/// Copia el nombre del miembro `i`. No se agrega NUL: el nombre puede llevar
/// cualquier byte salvo los de control, y un NUL implícito escondería un
/// truncamiento.
///
/// # Safety
/// `buf` apunta a `buf_largo` bytes escribibles.
#[no_mangle]
pub unsafe extern "C" fn mjg_nombre(h: *const MjgAbierto, i: usize,
                                    buf: *mut u8, buf_largo: usize) -> i32 {
    if h.is_null() || buf.is_null() { return MJG_ERR_NULL; }
    let a = &*h;
    let m = match a.inner.contenedor.miembros.get(i) { Some(m) => m, None => return MJG_ERR_RANGO };
    if buf_largo < m.nombre.len() { return MJG_ERR_BUF_CHICO; }
    core::ptr::copy_nonoverlapping(m.nombre.as_ptr(), buf, m.nombre.len());
    MJG_OK
}

#[no_mangle]
pub unsafe extern "C" fn mjg_payload_largo(h: *const MjgAbierto, i: usize) -> i64 {
    if h.is_null() { return MJG_ERR_NULL as i64; }
    let a = &*h;
    match a.inner.payloads.get(i) { Some(p) => p.len() as i64, None => MJG_ERR_RANGO as i64 }
}

/// Copia el payload `.pjg` del miembro `i`. Ya pasó por todas las validaciones
/// y, si el contenedor estaba cifrado, por la autenticación.
///
/// # Safety
/// `buf` apunta a `buf_largo` bytes escribibles.
#[no_mangle]
pub unsafe extern "C" fn mjg_payload(h: *const MjgAbierto, i: usize,
                                     buf: *mut u8, buf_largo: usize) -> i32 {
    if h.is_null() || buf.is_null() { return MJG_ERR_NULL; }
    let a = &*h;
    let p = match a.inner.payloads.get(i) { Some(p) => p, None => return MJG_ERR_RANGO };
    if buf_largo < p.len() { return MJG_ERR_BUF_CHICO; }
    core::ptr::copy_nonoverlapping(p.as_ptr(), buf, p.len());
    MJG_OK
}

/// Hash BLAKE3-128 del JPEG original declarado para el miembro `i`.
///
/// # Safety
/// `buf` apunta a al menos 16 bytes escribibles.
#[no_mangle]
pub unsafe extern "C" fn mjg_hash(h: *const MjgAbierto, i: usize,
                                  buf: *mut u8, buf_largo: usize) -> i32 {
    if h.is_null() || buf.is_null() { return MJG_ERR_NULL; }
    if buf_largo < 16 { return MJG_ERR_BUF_CHICO; }
    let a = &*h;
    let m = match a.inner.contenedor.miembros.get(i) { Some(m) => m, None => return MJG_ERR_RANGO };
    core::ptr::copy_nonoverlapping(m.hash.as_ptr(), buf, 16);
    MJG_OK
}

/// Hash BLAKE3-128 de un buffer, para verificar contra `mjg_hash` tras decodificar.
///
/// # Safety
/// `datos` apunta a `largo` bytes legibles; `buf` a 16 escribibles.
#[no_mangle]
pub unsafe extern "C" fn mjg_hash128(datos: *const u8, largo: usize,
                                     buf: *mut u8, buf_largo: usize) -> i32 {
    if buf.is_null() { return MJG_ERR_NULL; }
    if buf_largo < 16 { return MJG_ERR_BUF_CHICO; }
    if datos.is_null() && largo != 0 { return MJG_ERR_NULL; }
    let d = if largo == 0 { &[][..] } else { core::slice::from_raw_parts(datos, largo) };
    let h = blake3::hash(d);
    core::ptr::copy_nonoverlapping(h.as_bytes().as_ptr(), buf, 16);
    MJG_OK
}

// --- escritura ------------------------------------------------------------

/// Entrada para escribir un contenedor. Los punteros son del llamador y sólo
/// tienen que sobrevivir a la llamada: nada se guarda.
#[repr(C)]
pub struct MjgEntradaC {
    pub nombre: *const u8,
    pub nombre_largo: usize,
    pub payload: *const u8,
    pub payload_largo: usize,
    pub hash: [u8; 16],
    /// Tamaño del JPEG original. Si es 0 se toma el del payload, que es una
    /// cota inferior honesta y no una mentira sobre el tamaño real.
    pub tam_orig: u64,
}

unsafe fn recolectar<'a>(ents: *const MjgEntradaC, n: usize) -> Option<Vec<Entrada<'a>>> {
    if ents.is_null() && n != 0 { return None; }
    let mut v = Vec::with_capacity(n);
    for i in 0..n {
        let e = &*ents.add(i);
        if e.nombre.is_null() || e.payload.is_null() { return None; }
        v.push(Entrada {
            nombre: core::slice::from_raw_parts(e.nombre, e.nombre_largo),
            payload: core::slice::from_raw_parts(e.payload, e.payload_largo),
            tam_orig: if e.tam_orig != 0 { e.tam_orig } else { e.payload_largo as u64 },
            hash: e.hash,
        });
    }
    Some(v)
}

/// Cuántos bytes va a ocupar el contenedor, para que el llamador reserve.
/// Valida todo: si devuelve un error, `mjg_escribir` va a dar el mismo.
///
/// # Safety
/// `ents` apunta a `n` entradas válidas.
#[no_mangle]
pub unsafe extern "C" fn mjg_escribir_largo(ents: *const MjgEntradaC, n: usize, flags: u8) -> i64 {
    let v = match recolectar(ents, n) { Some(v) => v, None => return MJG_ERR_NULL as i64 };
    match contenedor::escribir(&v, flags, None) {
        Ok((bytes, _)) => bytes.len() as i64,
        Err(e) => traducir(&e) as i64,
    }
}

/// Escribe el contenedor en el buffer del llamador.
///
/// # Safety
/// `buf` apunta a `buf_largo` bytes escribibles.
#[no_mangle]
pub unsafe extern "C" fn mjg_escribir(ents: *const MjgEntradaC, n: usize, flags: u8,
                                      buf: *mut u8, buf_largo: usize) -> i32 {
    if buf.is_null() { return MJG_ERR_NULL; }
    let v = match recolectar(ents, n) { Some(v) => v, None => return MJG_ERR_NULL };
    match contenedor::escribir(&v, flags, None) {
        Ok((bytes, _)) => {
            if buf_largo < bytes.len() { return MJG_ERR_BUF_CHICO; }
            core::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, bytes.len());
            MJG_OK
        }
        Err(e) => traducir(&e),
    }
}

#[no_mangle]
pub extern "C" fn mjg_version() -> u32 { 1 }

// --- panic y personality ---------------------------------------------------
#[cfg(not(test))]
#[panic_handler]
fn panico(_: &core::panic::PanicInfo) -> ! {
    // panic = "abort" ya corta antes; esto es el requisito de no_std, y aborta
    // en vez de devolver control a C++.
    loop { unsafe { core::arch::asm!("ud2", options(nomem, nostack)) } }
}

/// `core` viene precompilado con desenrollado y referencia esto, aunque con
/// `panic = "abort"` nunca se lo llame.
#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

// evita el aviso de import sin usar cuando no se compilan las rutas de escritura
#[allow(dead_code)]
fn _usos(_: Option<cifrado::Error>) {}
