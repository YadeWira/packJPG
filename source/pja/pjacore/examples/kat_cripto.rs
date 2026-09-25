//! Vectores de respuesta conocida, producidos con las funciones REALES de
//! pjacore: Argon2id (perfil V1), el cifrado por trozos y BLAKE3-128. La capa
//! Pascal (`source/pja/pas/pruebas/prueba_cripto.pas`) y la cripto en C los
//! tienen que reproducir byte a byte.
//!
//!   kat_cripto <directorio>
use pjacore::cifrado::{self, PerfilKdf, TAM_SAL, TAM_NONCE};
use std::fmt::Write as _;

fn hex(b: &[u8]) -> String { let mut s = String::new(); for x in b { write!(s, "{:02x}", x).unwrap(); } s }
fn patron(n: usize, semilla: u32) -> Vec<u8> {
    // determinista y sin periodo corto, para que un corrimiento se note
    let mut x = semilla; (0..n).map(|_| { x ^= x << 13; x ^= x >> 17; x ^= x << 5; (x >> 3) as u8 }).collect()
}

fn main() {
    let dir = std::env::args().nth(1).expect("uso: kat_cripto <dir>");
    std::fs::create_dir_all(&dir).unwrap();
    let pass = b"clave de prueba KAT \xc3\xb1";                 // incluye UTF-8 no ASCII
    let mut sal = [0u8; TAM_SAL]; for i in 0..TAM_SAL { sal[i] = (0xA0 + i) as u8; }
    let mut nb = [0u8; TAM_NONCE]; for i in 0..TAM_NONCE { nb[i] = (0x10 + 7 * i) as u8; }

    let clave = cifrado::derivar_clave_con(PerfilKdf::V1, pass, &sal).unwrap();
    let mut out = String::new();
    writeln!(out, "pass {}", hex(pass)).unwrap();
    writeln!(out, "sal {}", hex(&sal)).unwrap();
    writeln!(out, "nonce_base {}", hex(&nb)).unwrap();
    writeln!(out, "clave {}", hex(&clave)).unwrap();
    std::fs::write(format!("{dir}/kdf.txt"), &out).unwrap();

    // bordes del esquema por trozos (TAM_TROZO = 65536)
    for (nom, n) in [("vacio", 0usize), ("uno", 1), ("trozo_justo", 65536),
                     ("trozo_mas_uno", 65537), ("varios", 200_000)] {
        let p = patron(n, 0x9E3779B9 ^ n as u32);
        let c = cifrado::cifrar(&clave, &nb, &p).unwrap();
        std::fs::write(format!("{dir}/{nom}.plano"), &p).unwrap();
        std::fs::write(format!("{dir}/{nom}.cifrado"), &c).unwrap();
        println!("  {:14} plano {:7} B -> cifrado {:7} B", nom, n, c.len());
    }

    // BLAKE3-128 como lo usa el formato: los primeros 16 bytes del hash
    let mut h = String::new();
    for (nom, n) in [("vacio", 0usize), ("uno", 1), ("bloque", 1024), ("bloque_mas_uno", 1025), ("mega", 1 << 20)] {
        let p = patron(n, 0x1234567 ^ n as u32);
        std::fs::write(format!("{dir}/b3_{nom}.bin"), &p).unwrap();
        writeln!(h, "{} {}", nom, hex(&blake3::hash(&p).as_bytes()[..16])).unwrap();
    }
    std::fs::write(format!("{dir}/blake3.txt"), &h).unwrap();
    println!("  clave argon2id: {}", hex(&clave));
}
