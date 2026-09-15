//! Asignador global apoyado en el `malloc` del runtime de C, para que Rust y
//! el lado C++ compartan **un solo heap**.
//!
//! Maneja alineaciones mayores a las que `malloc` garantiza. La versión
//! anterior devolvía nulo en ese caso, y eso no falla como error: Rust lo trata
//! como sin memoria y **aborta el proceso**. Apareció con Argon2, que pide
//! bloques alineados a línea de caché, y sólo desde C++ — los tests de Rust
//! usan la `std` y su asignador, así que no lo veían.

use core::alloc::{GlobalAlloc, Layout};
use core::mem::size_of;

extern "C" {
    fn malloc(n: usize) -> *mut u8;
    fn free(p: *mut u8);
}

/// Alineación que `malloc` garantiza en las plataformas que soportamos.
const ALIN_MALLOC: usize = size_of::<usize>() * 2;

pub struct AsignadorC;

/// Sobre-asigna y guarda el puntero original justo antes del que se devuelve,
/// para poder liberarlo. Es la técnica estándar y funciona igual en Windows,
/// donde no hay `posix_memalign`.
unsafe fn alinear(size: usize, align: usize) -> *mut u8 {
    let extra = align - 1 + size_of::<*mut u8>();
    let crudo = malloc(size + extra);
    if crudo.is_null() { return core::ptr::null_mut(); }
    let base = crudo as usize + size_of::<*mut u8>();
    let alineado = (base + align - 1) & !(align - 1);
    // El puntero original va en los bytes inmediatamente anteriores.
    core::ptr::write_unaligned((alineado as *mut *mut u8).offset(-1), crudo);
    alineado as *mut u8
}

unsafe fn liberar_alineado(p: *mut u8) {
    if p.is_null() { return; }
    let crudo = core::ptr::read_unaligned((p as *mut *mut u8).offset(-1));
    free(crudo);
}

unsafe impl GlobalAlloc for AsignadorC {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        if l.align() <= ALIN_MALLOC { malloc(l.size()) } else { alinear(l.size(), l.align()) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        if l.align() <= ALIN_MALLOC { free(p) } else { liberar_alineado(p) }
    }
}

#[cfg(not(test))]
#[global_allocator]
static ASIGNADOR: AsignadorC = AsignadorC;
