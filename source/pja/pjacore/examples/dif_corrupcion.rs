//! Diferencial de `corrupcion`: la batería de `pjacore/src/corrupcion.rs`, pero
//! celda por celda en vez de baldes, para que el port a Pascal
//! (`source/pja/pas/diferencial/dif_corrupcion.pas`) tenga que coincidir en
//! cada una y no sólo en los totales.
//!
//!   dif_corrupcion generar <dir_pjg> <casos.txt>   una celda por línea
//!   dif_corrupcion leer    <dir_pjg> <casos.txt>   un veredicto por línea
//!
//! Las dos puntas arman el contenedor base por su cuenta, desde los mismos
//! `.pjg` reales, como la prueba. La primera línea (`base`) compara ese
//! contenedor: si difiere, todo lo demás compara cosas distintas.
//!
//! Celdas, sobre el contenedor entero (no una muestra del payload):
//!   base            len:N b3:H del contenedor armado
//!   x pos bit       un bit dado vuelta
//!   r pos bit       un bit dado vuelta y el hash RESELLADO: sin esto casi todo
//!                   da IndiceAlterado y las validaciones de los miembros
//!                   reales no corren nunca
//!   v pos byte      el byte reemplazado por un valor
//!   t len           truncado a len
//!   a n             n ceros agregados al final
//!
//! Veredicto: el Debug del error, `igual` si se lee lo mismo que el original,
//! o el contenedor leído entero si se lee algo distinto.
use pjacore::escritor::*;
use pjacore::indice::*;
use std::io::{BufRead, BufWriter, Write};
use std::path::{Path, PathBuf};

fn pjgs(dir: &str, n: usize) -> Vec<PathBuf> {
    let mut r: Vec<PathBuf> = std::fs::read_dir(dir).unwrap()
        .filter_map(|e| e.ok()).map(|e| e.path())
        .filter(|p| p.extension().map_or(false, |x| x == "pjg")).collect();
    r.sort();
    assert!(r.len() >= n, "hacen falta {n} .pjg en {dir}");
    r.truncate(n);
    r
}

/// El mismo contenedor que `corrupcion::bateria::contenedor_real`.
fn contenedor_real(dir: &str) -> Vec<u8> {
    let rutas = pjgs(dir, 6);
    let datos: Vec<Vec<u8>> = rutas.iter().map(|p| std::fs::read(p).unwrap()).collect();
    let nombres: Vec<Vec<u8>> = rutas.iter()
        .map(|p| Path::new(p).file_name().unwrap().to_string_lossy().as_bytes().to_vec()).collect();
    let ents: Vec<Entrada> = datos.iter().zip(&nombres).map(|(d, n)| Entrada {
        nombre: n, tam_orig: d.len() as u64 * 2, payload: d,
        hash: { let h = blake3::hash(d); let mut a = [0u8; 16];
                a.copy_from_slice(&h.as_bytes()[..16]); a },
    }).collect();
    escribir(&ents, 0).unwrap().0
}

fn resellar(c: &mut [u8]) {
    if c.len() < TAM_CABECERA { return; }
    let ti = u32::from_le_bytes([c[8], c[9], c[10], c[11]]) as usize;
    if TAM_CABECERA + ti > c.len() { return; }
    let h = hash_cabecera_indice(&c[..TAM_CABECERA], &c[TAM_CABECERA..TAM_CABECERA + ti].to_vec());
    c[12..28].copy_from_slice(&h);
}

fn generar(dir: &str, salida: &str) {
    let base = contenedor_real(dir);
    let fin_indice = TAM_CABECERA + u32::from_le_bytes([base[8], base[9], base[10], base[11]]) as usize;
    let mut o = BufWriter::new(std::fs::File::create(salida).unwrap());
    let mut n = 0usize;
    let mut put = |s: String| { writeln!(o, "{s}").unwrap(); n += 1; };
    put("base".into());
    for p in 0..base.len() {
        // cabecera e indice: los 8 bits; payload: tres bits, como la prueba
        let bits: &[u8] = if p < fin_indice { &[0, 1, 2, 3, 4, 5, 6, 7] } else { &[0, 3, 7] };
        for &b in bits { put(format!("x {p} {b}")); }
        if p < fin_indice && !(12..TAM_CABECERA).contains(&p) {
            for b in 0..8 { put(format!("r {p} {b}")); }
            for v in [0u8, 0xFF] { if base[p] != v { put(format!("v {p} {v}")); } }
        }
    }
    for k in 0..base.len() { put(format!("t {k}")); }
    for k in [1usize, 2, 16, 4096] { put(format!("a {k}")); }
    drop(put);
    eprintln!("{n} celdas, contenedor de {} B, indice hasta {fin_indice}", base.len());
}

fn texto(c: &Contenedor) -> String {
    let h = |b: &[u8]| b.iter().map(|x| format!("{:02x}", x)).collect::<String>();
    let mut s = format!("Ok flags={} n={} ", c.flags, c.miembros.len());
    for m in &c.miembros {
        s += &format!("{}:{}:{}:{}:{};", h(&m.nombre), m.tam_orig, m.tam_payload, h(&m.hash), m.m_flags);
    }
    s
}

fn leer(dir: &str, casos: &str) {
    let base = contenedor_real(dir);
    let orig = texto(&leer_indice(&base).unwrap());
    let f = std::io::BufReader::new(std::fs::File::open(casos).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    for l in f.lines() {
        let l = l.unwrap();
        let w: Vec<&str> = l.split(' ').collect();
        if w[0] == "base" {
            let h: String = blake3::hash(&base).as_bytes()[..16].iter().map(|x| format!("{:02x}", x)).collect();
            writeln!(o, "len:{} b3:{h}", base.len()).unwrap();
            continue;
        }
        let a: usize = w[1].parse().unwrap();
        let mut d = base.clone();
        match w[0] {
            "x" => d[a] ^= 1 << w[2].parse::<u8>().unwrap(),
            "r" => { d[a] ^= 1 << w[2].parse::<u8>().unwrap(); resellar(&mut d); }
            "v" => d[a] = w[2].parse().unwrap(),
            "t" => d.truncate(a),
            "a" => d.resize(d.len() + a, 0),
            _ => panic!("celda desconocida: {l}"),
        }
        match leer_indice(&d) {
            Err(e) => writeln!(o, "{:?}", e).unwrap(),
            Ok(c) => { let t = texto(&c); writeln!(o, "{}", if t == orig { "igual" } else { &t }).unwrap(); }
        }
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("generar") if a.len() == 4 => generar(&a[2], &a[3]),
        Some("leer") if a.len() == 4 => leer(&a[2], &a[3]),
        _ => { eprintln!("uso: dif_corrupcion generar|leer <dir_pjg> <casos.txt>"); std::process::exit(2); }
    }
}
