//! Diferencial de `cifrado`. Tres clases de casos, una por linea:
//!   K pass_hex sal_hex                 derivar_clave (perfil V1)    -> clave hex
//!   C clave nonce largo semilla        cifrar                        -> largo + BLAKE3-128
//!   D base clave nonce op...           descifrar(mutar(base, op))    -> Ok largo + BLAKE3 | Err
//! Las bases son cifrados que produce ESTE Rust (archivos base_N.bin): el port a
//! Pascal tiene que descifrar exactamente lo que el Rust escribe.
//!
//! Operaciones de mutacion (iguales de los dos lados):
//!   id | x pos mascara | t largo | a n | s i j | d i | r i | p i valor
//! s/d/r/p se refieren a TROZOS de la base (largo u32 + cuerpo + tag).
//!
//!   dif_cifrado generar <dir>     |     dif_cifrado leer <dir>
use pjacore::cifrado::*;
use std::io::{BufRead, BufWriter, Write};

fn hx(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
fn dehx(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect() }
fn payload(largo: usize, semilla: u64) -> Vec<u8> {
    (0..largo).map(|k| (semilla.wrapping_mul(31).wrapping_add(k as u64 * 7) & 0xFF) as u8).collect()
}
fn b3(b: &[u8]) -> String { hx(&blake3::hash(b).as_bytes()[..16]) }
fn trozos(c: &[u8]) -> Vec<(usize, usize)> {
    let mut v = Vec::new(); let mut p = 0;
    while p + 4 <= c.len() {
        let l = u32::from_le_bytes([c[p], c[p + 1], c[p + 2], c[p + 3]]) as usize;
        if p + 4 + l > c.len() { break; }
        v.push((p, 4 + l)); p += 4 + l;
    }
    v
}
fn mutar(base: &[u8], op: &[&str]) -> Vec<u8> {
    let n = |i: usize| op[i].parse::<usize>().unwrap();
    let t = trozos(base);
    match op[0] {
        "id" => base.to_vec(),
        "x" => { let mut c = base.to_vec(); let i = n(1); if i < c.len() { c[i] ^= n(2) as u8; } c }
        "t" => base[..n(1).min(base.len())].to_vec(),
        "a" => { let mut c = base.to_vec(); c.extend(std::iter::repeat(0u8).take(n(1))); c }
        "s" => {
            let (i, j) = (n(1), n(2)); let mut c = Vec::new();
            for k in 0..t.len() { let q = if k == i { j } else if k == j { i } else { k };
                c.extend_from_slice(&base[t[q].0..t[q].0 + t[q].1]); }
            c
        }
        "d" => { let i = n(1); let mut c = Vec::new();
            for k in 0..t.len() { c.extend_from_slice(&base[t[k].0..t[k].0 + t[k].1]);
                if k == i { c.extend_from_slice(&base[t[k].0..t[k].0 + t[k].1]); } }
            c }
        "r" => { let i = n(1); let mut c = Vec::new();
            for k in 0..t.len() { if k != i { c.extend_from_slice(&base[t[k].0..t[k].0 + t[k].1]); } }
            c }
        "p" => { let mut c = base.to_vec(); let (i, v) = (n(1), n(2) as u32);
            if i < t.len() { c[t[i].0..t[i].0 + 4].copy_from_slice(&v.to_le_bytes()); } c }
        _ => panic!("op desconocida {}", op[0]),
    }
}

fn generar(dir: &str) {
    std::fs::create_dir_all(dir).unwrap();
    let mut o = BufWriter::new(std::fs::File::create(format!("{dir}/corpus.txt")).unwrap());
    // K: contrasenas y sales, incluidas vacia, larga, con NUL y no ASCII
    let pases: Vec<Vec<u8>> = vec![b"".to_vec(), b"a".to_vec(), b"secreta".to_vec(), "ñandú 写真".as_bytes().to_vec(),
        b"con\x00nulo".to_vec(), vec![0xFF; 200], b"clave de prueba KAT \xc3\xb1".to_vec()];
    let sales: Vec<[u8; TAM_SAL]> = vec![[0u8; 16], [0xFF; 16], [7u8; 16],
        core::array::from_fn(|i| (0xA0 + i) as u8)];
    for p in &pases { for s in &sales[..2] { writeln!(o, "K {} {}", hx(p), hx(s)).unwrap(); } }
    for s in &sales[2..] { writeln!(o, "K {} {}", hx(b"secreta"), hx(s)).unwrap(); }
    // claves y nonces fijos para C y D (Argon2 es caro: no se deriva por caso)
    let claves: [[u8; 32]; 2] = [core::array::from_fn(|i| (i * 7 + 1) as u8), [0x5Au8; 32]];
    let nonces: [[u8; TAM_NONCE]; 2] = [core::array::from_fn(|i| (0x10 + 7 * i) as u8), [0u8; TAM_NONCE]];
    // C: largos en los bordes de un trozo de 64 KB
    let largos = [0usize, 1, 15, 16, 17, 100, 65535, 65536, 65537, 131071, 131072, 131073, 200_000];
    for (ci, k) in claves.iter().enumerate() { for nb in &nonces { for &l in &largos {
        writeln!(o, "C {} {} {} {}", hx(k), hx(nb), l, ci as u64 + l as u64 % 97).unwrap(); } } }
    // D: bases cifradas por el Rust, y mutaciones sobre cada una
    let bases: [(usize, u64); 5] = [(0, 1), (100, 2), (65536, 3), (65537, 4), (200_000, 5)];
    for (bi, &(l, s)) in bases.iter().enumerate() {
        let (k, nb) = (&claves[0], &nonces[0]);
        let c = cifrar(k, nb, &payload(l, s)).unwrap();
        std::fs::write(format!("{dir}/base_{bi}.bin"), &c).unwrap();
        let t = trozos(&c);
        let d = |o: &mut BufWriter<std::fs::File>, op: String| writeln!(o, "D base_{bi}.bin {} {} {}", hx(k), hx(nb), op).unwrap();
        d(&mut o, "id".into());
        // clave y nonce equivocados
        writeln!(o, "D base_{bi}.bin {} {} id", hx(&claves[1]), hx(nb)).unwrap();
        writeln!(o, "D base_{bi}.bin {} {} id", hx(k), hx(&nonces[1])).unwrap();
        for (ti, &(ini, lar)) in t.iter().enumerate() {
            // cada byte del largo, primeros y ultimos bytes del cuerpo, cada byte del tag
            let mut pos: Vec<usize> = (ini..ini + 4).collect();
            pos.extend((ini + 4..(ini + 36).min(ini + lar)).step_by(1));
            pos.extend((ini + lar).saturating_sub(48)..ini + lar);
            pos.sort(); pos.dedup();
            for p in pos { for m in [0x01u8, 0x80, 0xFF] { d(&mut o, format!("x {p} {m}")); } }
            for v in [0u32, 15, 16, (lar - 4) as u32 - 1, (lar - 4) as u32 + 1, u32::MAX] {
                d(&mut o, format!("p {ti} {v}")); }
            d(&mut o, format!("d {ti}")); d(&mut o, format!("r {ti}"));
            for tj in ti + 1..t.len() { d(&mut o, format!("s {ti} {tj}")); }
            // truncar en el limite del trozo y adentro
            for cut in [ini, ini + 1, ini + 3, ini + 4, ini + 5, ini + lar - 1] { d(&mut o, format!("t {cut}")); }
        }
        for n in [1usize, 3, 4, 20, 64] { d(&mut o, format!("a {n}")); }
        d(&mut o, format!("t {}", c.len())); d(&mut o, "t 0".into());
    }
    o.flush().unwrap();
}

fn leer(dir: &str) {
    let f = std::io::BufReader::new(std::fs::File::open(format!("{dir}/corpus.txt")).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    let mut cache: std::collections::HashMap<String, Vec<u8>> = Default::default();
    for l in f.lines() {
        let l = l.unwrap(); let w: Vec<&str> = l.split(' ').collect();
        match w[0] {
            "K" => {
                let s: [u8; TAM_SAL] = dehx(w[2]).try_into().unwrap();
                match derivar_clave(&dehx(w[1]), &s) {
                    Ok(k) => writeln!(o, "{}", hx(&k)).unwrap(),
                    Err(e) => writeln!(o, "{:?}", e).unwrap(),
                }
            }
            "C" => {
                let k: [u8; 32] = dehx(w[1]).try_into().unwrap(); let nb: [u8; TAM_NONCE] = dehx(w[2]).try_into().unwrap();
                let c = cifrar(&k, &nb, &payload(w[3].parse().unwrap(), w[4].parse().unwrap())).unwrap();
                writeln!(o, "len:{} b3:{}", c.len(), b3(&c)).unwrap();
            }
            "D" => {
                let base = cache.entry(w[1].to_string()).or_insert_with(|| std::fs::read(format!("{dir}/{}", w[1])).unwrap()).clone();
                let k: [u8; 32] = dehx(w[2]).try_into().unwrap(); let nb: [u8; TAM_NONCE] = dehx(w[3]).try_into().unwrap();
                match descifrar(&k, &nb, &mutar(&base, &w[4..])) {
                    Ok(p) => writeln!(o, "Ok len:{} b3:{}", p.len(), b3(&p)).unwrap(),
                    Err(e) => writeln!(o, "{:?}", e).unwrap(),
                }
            }
            _ => panic!("linea desconocida"),
        }
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("generar") => generar(&a[2]),
        Some("leer") => leer(&a[2]),
        _ => { eprintln!("uso: dif_cifrado generar|leer <dir>"); std::process::exit(2); }
    }
}
