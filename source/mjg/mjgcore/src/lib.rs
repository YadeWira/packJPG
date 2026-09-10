#![cfg_attr(not(test), no_std)]
//! Núcleo del contenedor MJG.
//!
//! `no_std` a propósito: la biblioteca estándar de Rust en Windows importa
//! `WaitOnAddress` de `api-ms-win-core-synch-l1-2-0.dll`, que existe desde
//! Windows 8, y packJPG declara soporte desde Windows 7 SP1. Sin `std` ese
//! import desaparece y el piso de sistema operativo no baja.
//!
//! Frontera FFI angosta a propósito: entran slices con largo, salen códigos de
//! estado, ninguna propiedad de memoria cruza el borde. `panic = "abort"` en
//! release, porque un panic que desenrollara hacia C++ sería comportamiento
//! indefinido.

extern crate alloc;

pub mod cifrado;
pub mod contenedor;
pub mod corrupcion;
pub mod escritor;
pub mod indice;
pub mod limites;
pub mod nombres;
