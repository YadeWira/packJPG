//! Límites del contenedor. Los números salen de `doc/POLITICA.md`, donde cada
//! uno dice de dónde viene.

/// Tope absoluto de miembros. Acota antes de reservar el índice: un `u32` crudo
/// serían 4.294.967.295 entradas.
pub const MAX_MIEMBROS: u32 = 1_048_576;

/// Bytes mínimos que ocupa una entrada del índice. Sirve para descartar un
/// `count` imposible contra el tamaño real del archivo.
pub const MIN_BYTES_ENTRADA: u64 = 32;

/// Cabecera `.pjg` mínima; ningún payload puede ser más chico.
pub const MIN_PAYLOAD: u64 = 12;

/// Igual que `PJG_MAX_BLOWUP_RATIO` en el códec. Medido: la expansión real
/// jpg/pjg va de 1,08x a 2,14x, así que 500 es tope de último recurso.
pub const MAX_RATIO_EXPANSION: u64 = 500;

/// Presupuesto agregado por defecto. Un timelapse de 240 cuadros de 20 MB son
/// 4,8 GB legítimos, así que heredar los 256 MB por archivo rompería el caso
/// real. 0 = sin límite.
pub const PRESUPUESTO_POR_DEFECTO: u64 = 8 * 1024 * 1024 * 1024;

/// Límites de nombres. **Son bytes, no caracteres**: medido, 255 caracteres
/// acentuados son 510 bytes y el sistema de archivos los rechaza.
pub const MAX_BYTES_COMPONENTE: usize = 255;
pub const MAX_BYTES_RUTA: usize = 1024;
pub const MAX_PROFUNDIDAD: usize = 32;
