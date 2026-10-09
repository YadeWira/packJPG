//! Diferencial de `contenedor`: `escribir` (con y sin cifrado) y `abrir` sobre
//! contenedores intactos, dañados, y RESELLADOS -- un contenedor en claro
//! mutado por dentro y cifrado después, para que el daño llegue al camino que
//! corre recién después de autenticar.
//!
//!   dif_contenedor generar <dir>    escribe <dir>/corpus.txt y los base_N.bin
//!   dif_contenedor leer    <dir>    un resultado por línea de corpus.txt
//!
//! Líneas del corpus:
//!   K pass_hex sal_hex nonce_hex     la clave de las líneas E (se deriva UNA vez)
//!   E flags cifrar(0|1) e1|e2|...    escribir; ei = nombre_hex,largo,semilla
//!   A base_N.bin pass op...          abrir; pass = "-" (ninguna) o hex ("~" = vacía)
//! ops, en orden:  id | x pos mascara | t largo | a n | w pos byte | h
//!   (h = recalcular el hash de cabecera+índice con el tam_indice que haya)
//! Salidas: E -> "Ok avisos=[..] len:N b3:H" ; A -> "Ok n:N flags:F b3:H" ;
//! error -> su Debug.
use pjacore::cifrado::{self, TAM_NONCE, TAM_SAL};
use pjacore::contenedor::{abrir, escribir};
use pjacore::escritor::{self, Entrada};
use pjacore::indice::{hash_cabecera_indice, TAM_CABECERA, FLAG_CIFRADO, FLAG_RUTAS};
use std::io::{BufRead, BufWriter, Write};

fn payload(largo: usize, semilla: u64) -> Vec<u8> {
    (0..largo).map(|k| (semilla.wrapping_mul(31).wrapping_add(k as u64 * 7) & 0xFF) as u8).collect()
}
fn hx(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
fn dehx(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect() }
fn b3(b: &[u8]) -> String { hx(&blake3::hash(b).as_bytes()[..16]) }

struct Gen(u64);
impl Gen { fn n(&mut self) -> u64 { self.0 ^= self.0 << 13; self.0 ^= self.0 >> 7; self.0 ^= self.0 << 17; self.0 } }

const PASS: &[u8] = b"pja-dif";
const SAL: [u8; TAM_SAL] = [0x51; TAM_SAL];
const NB: [u8; TAM_NONCE] = [0x2b; TAM_NONCE];

/// (nombre, largo, semilla) -> Entrada. tam_orig = 2 * largo y el hash es el
/// BLAKE3 del payload, como lo arma el CLI.
fn entradas(spec: &[(Vec<u8>, usize, u64)]) -> (Vec<Vec<u8>>, Vec<[u8; 16]>) {
    let ps: Vec<Vec<u8>> = spec.iter().map(|(_, l, s)| payload(*l, *s)).collect();
    let hs = ps.iter().map(|p| { let mut a = [0u8; 16]; a.copy_from_slice(&blake3::hash(p).as_bytes()[..16]); a }).collect();
    (ps, hs)
}
fn armar<'a>(spec: &'a [(Vec<u8>, usize, u64)], ps: &'a [Vec<u8>], hs: &[[u8; 16]]) -> Vec<Entrada<'a>> {
    spec.iter().zip(ps).zip(hs).map(|(((n, _, _), p), h)| Entrada { nombre: n, tam_orig: p.len() as u64 * 2, payload: p, hash: *h }).collect()
}

/// Lo mismo que hace `contenedor::escribir` con un plano ya armado, pero sobre
/// un plano que puede estar dañado.
fn sellar(plano: &[u8], clave: &[u8; 32]) -> Vec<u8> {
    let ct = cifrado::cifrar(clave, &NB, &plano[8..]).unwrap();
    let mut out = plano[..8].to_vec();
    out.resize(TAM_CABECERA, 0);
    out.extend_from_slice(&SAL); out.extend_from_slice(&NB); out.extend_from_slice(&ct);
    out
}
fn resellar(c: &mut Vec<u8>) {
    if c.len() < TAM_CABECERA { return; }
    let ti = u32::from_le_bytes([c[8], c[9], c[10], c[11]]) as usize;
    if TAM_CABECERA + ti > c.len() { return; }
    let h = hash_cabecera_indice(&c[..TAM_CABECERA], &c[TAM_CABECERA..TAM_CABECERA + ti]);
    c[12..28].copy_from_slice(&h);
}
fn mutar(base: &[u8], ops: &[&str]) -> Vec<u8> {
    let mut c = base.to_vec(); let mut i = 0;
    while i < ops.len() {
        let n = |k: usize| ops[i + k].parse::<u64>().unwrap();
        match ops[i] {
            "id" => { i += 1; }
            "x" => { let p = n(1) as usize; if p < c.len() { c[p] ^= n(2) as u8; } i += 3; }
            "t" => { let l = (n(1) as usize).min(c.len()); c.truncate(l); i += 2; }
            "a" => { let k = n(1) as usize; c.resize(c.len() + k, 0); i += 2; }
            "w" => { let p = n(1) as usize; if p < c.len() { c[p] = n(2) as u8; } i += 3; }
            "h" => { resellar(&mut c); i += 1; }
            o => panic!("op {o}"),
        }
    }
    c
}

fn generar(dir: &str) {
    std::fs::create_dir_all(dir).unwrap();
    let clave = cifrado::derivar_clave(PASS, &SAL).unwrap();
    let mut o = BufWriter::new(std::fs::File::create(format!("{dir}/corpus.txt")).unwrap());
    let mut g = Gen(20261009);
    let (mut ne, mut na, mut nd) = (0, 0, 0);   // escribir, abrir, abrir que llega a derivar (aprox.)
    writeln!(o, "K {} {} {}", hx(PASS), hx(&SAL), hx(&NB)).unwrap();

    // ---- E: escribir. Cifrado, contraseña faltante/sobrante, y el orden
    // frente a los errores del escritor (que van primero).
    let validos: Vec<Vec<(Vec<u8>, usize, u64)>> = vec![
        vec![],
        vec![(b"a.jpg".to_vec(), 12, 1)],
        vec![(b"a.jpg".to_vec(), 100, 1), (b"b.jpg".to_vec(), 300, 2), (b"c.jpg".to_vec(), 40, 3)],
        vec![("ñandú.jpg".as_bytes().to_vec(), 70000, 4)],             // payload de más de un trozo
        vec![(b"d/x.jpg".to_vec(), 20, 5), (b"CON.jpg".to_vec(), 20, 6)],
        vec![(b"g.jpg".to_vec(), 65536 - 200, 7), (b"h.jpg".to_vec(), 400, 8)],  // índice+payloads cruzan el borde
    ];
    let invalidos: Vec<Vec<(Vec<u8>, usize, u64)>> = vec![
        vec![(b"../a".to_vec(), 12, 1)], vec![(b"a".to_vec(), 5, 1)], vec![(b"a".to_vec(), 12, 1), (b"a".to_vec(), 12, 2)],
    ];
    let spec_txt = |s: &[(Vec<u8>, usize, u64)]| s.iter().map(|(n, l, se)| format!("{},{},{}", hx(n), l, se)).collect::<Vec<_>>().join("|");
    for s in validos.iter().chain(invalidos.iter()) {
        for fl in [0u8, 1, 2, 3, 4, 5, 8, 9, 0x81] {
            for cif in [0, 1] { writeln!(o, "E {} {} {}", fl, cif, spec_txt(s)).unwrap(); ne += 1; }
        }
    }
    for _ in 0..300 {
        let k = (g.n() % 6) as usize;
        let s: Vec<_> = (0..k).map(|i| (format!("f{}.jpg", g.n() % 9).into_bytes(), 12 + (g.n() % 3000) as usize, i as u64)).collect();
        let fl = [0u8, 1, 2, 3][(g.n() % 4) as usize];
        writeln!(o, "E {} {} {}", fl, g.n() % 2, spec_txt(&s)).unwrap(); ne += 1;
    }

    // ---- bases
    let mut bases: Vec<(String, Vec<u8>, bool)> = Vec::new();   // (archivo, bytes, cifrado)
    let guardar = |b: Vec<u8>, cif: bool, bases: &mut Vec<(String, Vec<u8>, bool)>| {
        let f = format!("base_{}.bin", bases.len());
        std::fs::write(format!("{dir}/{f}"), &b).unwrap();
        bases.push((f, b, cif));
    };
    for s in &validos {
        let (ps, hs) = entradas(s); let es = armar(s, &ps, &hs);
        for fl in [0u8, FLAG_RUTAS] {
            // las combinaciones que el escritor rechaza ya las cubren las líneas E
            if let Ok((c, _)) = escribir(&es, fl, None) { guardar(c, false, &mut bases); }
            if let Ok((c, _)) = escribir(&es, fl | FLAG_CIFRADO, Some((&clave, &NB, &SAL))) { guardar(c, true, &mut bases); }
        }
    }
    let nbase = bases.len();
    // resellados: el plano (con el bit de cifrado puesto) se daña por dentro y
    // recién después se cifra. Es lo único que llega a validar el índice de
    // un contenedor cifrado sin pasar por el escritor.
    let s3 = &validos[2]; let (ps, hs) = entradas(s3); let es = armar(s3, &ps, &hs);
    let plano = escritor::escribir(&es, FLAG_CIFRADO).unwrap().0;
    let ti = u32::from_le_bytes([plano[8], plano[9], plano[10], plano[11]]) as usize;
    let mut resell = Vec::new();
    for k in 0..120 {
        let mut m = plano.clone();
        match k % 6 {
            0 => { let p = 8 + (g.n() as usize % (TAM_CABECERA + ti - 8)); m[p] ^= 1 << (g.n() % 8); }       // sin resellar
            1 => { let p = TAM_CABECERA + (g.n() as usize % ti); m[p] ^= 1 << (g.n() % 8); resellar(&mut m); }
            2 => { let w = (g.n() % 4) as usize; m[8 + w] = m[8 + w].wrapping_add(1 + (g.n() % 3) as u8); resellar(&mut m); }
            3 => { let l = m.len() - 1 - (g.n() as usize % 300); m.truncate(l); }
            4 => { let l = m.len() + 1 + (g.n() as usize % 50); m.resize(l, 0); }
            _ => { let p = TAM_CABECERA + (g.n() as usize % ti); m[p] = 0xFF; resellar(&mut m); }
        }
        resell.push(m);
    }
    for c in [8usize, 9, 20, 27, 28, 29] { resell.push(plano[..c].to_vec()); }   // cuerpo más corto que 20, justo, etc.
    for m in resell { guardar(sellar(&m, &clave), true, &mut bases); }

    let pass_ok = hx(PASS);
    let mut a = |f: &str, pass: &str, ops: &str, o: &mut BufWriter<std::fs::File>| { writeln!(o, "A {} {} {}", f, pass, ops).unwrap(); na += 1; };
    for (bi, (f, b, cif)) in bases.iter().enumerate() {
        let sellado = bi >= nbase;
        if sellado { a(f, &pass_ok, "id", &mut o); nd += 1; continue; }
        // contraseña: ninguna, buena, mala, vacía
        for p in ["-", &pass_ok, "6d616c61", "~"] { a(f, p, "id", &mut o); if *cif && p != "-" { nd += 1; } }
        let pa: &str = if *cif { &pass_ok } else { "-" };
        // cabecera y algo de índice/cuerpo, bit a bit en claro; en cifrado sólo
        // la cabecera bit a bit (no deriva) y un bit por byte de sal/nonce
        let hasta = if *cif { TAM_CABECERA } else { b.len().min(TAM_CABECERA + 90) };
        for p in 0..hasta { for bit in 0..8 { a(f, pa, &format!("x {} {}", p, 1 << bit), &mut o); } }
        if !*cif { for p in 0..hasta { a(f, pa, &format!("x {} 4 h", p), &mut o); } }
        if *cif && bi % 4 == 1 {
            for p in TAM_CABECERA..TAM_CABECERA + TAM_SAL + TAM_NONCE { if p % 5 == 0 { a(f, pa, &format!("x {} 1", p), &mut o); nd += 1; } }
            a(f, pa, &format!("x {} 1", b.len() - 1), &mut o); nd += 1;
        }
        // truncados y agregados
        for l in [0usize, 7, 8, 27, 28, 29, 67, 68, 69, 88, 89] { a(f, pa, &format!("t {}", l), &mut o); if *cif && l >= 68 { nd += 1; } }
        if !*cif { for _ in 0..20 { a(f, pa, &format!("t {}", g.n() as usize % (b.len() + 1)), &mut o); } }
        for k in [1u64, 16, 100] { a(f, pa, &format!("a {}", k), &mut o); if *cif { nd += 1; } }
        // flags y perfil reescritos, con y sin resellar
        for v in [0u8, 1, 2, 3, 4, 7, 8, 0x80] {
            a(f, pa, &format!("w 5 {}", v), &mut o); if *cif && v & 1 == 1 && v < 8 { nd += 1; }
            if !*cif { a(f, pa, &format!("w 5 {} h", v), &mut o); }
        }
        for v in [1u8, 2, 255] { a(f, pa, &format!("w 6 {}", v), &mut o); }
        if !*cif { a(f, "-", "w 5 1 h", &mut o); a(f, &pass_ok, "w 5 1 h", &mut o); nd += 1; }
    }
    eprintln!("{} lineas E, {} lineas A ({} bases, ~{} derivan clave)", ne, na, bases.len(), nd);
}

fn leer(dir: &str) {
    let f = std::io::BufReader::new(std::fs::File::open(format!("{dir}/corpus.txt")).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    let mut clave = [0u8; 32]; let mut nb = [0u8; TAM_NONCE]; let mut sal = [0u8; TAM_SAL];
    for l in f.lines() {
        let l = l.unwrap(); let w: Vec<&str> = l.split(' ').collect();
        match w[0] {
            "K" => {
                sal.copy_from_slice(&dehx(w[2])); nb.copy_from_slice(&dehx(w[3]));
                clave = cifrado::derivar_clave(&dehx(w[1]), &sal).unwrap();
            }
            "E" => {
                let flags: u8 = w[1].parse().unwrap();
                let spec: Vec<(Vec<u8>, usize, u64)> = if w.len() < 4 || w[3].is_empty() { vec![] } else {
                    w[3].split('|').map(|e| { let p: Vec<&str> = e.split(',').collect(); (dehx(p[0]), p[1].parse().unwrap(), p[2].parse().unwrap()) }).collect()
                };
                let (ps, hs) = entradas(&spec); let es = armar(&spec, &ps, &hs);
                let r = if w[2] == "1" { escribir(&es, flags, Some((&clave, &nb, &sal))) } else { escribir(&es, flags, None) };
                match r {
                    Err(e) => writeln!(o, "{:?}", e).unwrap(),
                    Ok((b, av)) => {
                        let a: Vec<String> = av.iter().map(|(i, m)| format!("{}:{:?}", i, m)).collect();
                        writeln!(o, "Ok avisos=[{}] len:{} b3:{}", a.join(","), b.len(), b3(&b)).unwrap();
                    }
                }
            }
            "A" => {
                let base = std::fs::read(format!("{dir}/{}", w[1])).unwrap();
                let datos = mutar(&base, &w[3..]);
                let pass = match w[2] { "-" => None, "~" => Some(Vec::new()), h => Some(dehx(h)) };
                match abrir(&datos, pass.as_deref()) {
                    Err(e) => writeln!(o, "{:?}", e).unwrap(),
                    Ok(a) => {
                        // todo lo que sale, serializado en un orden fijo
                        let mut s = vec![a.contenedor.flags];
                        for (m, p) in a.contenedor.miembros.iter().zip(&a.payloads) {
                            s.extend_from_slice(&(m.nombre.len() as u16).to_le_bytes()); s.extend_from_slice(&m.nombre);
                            s.extend_from_slice(&m.tam_orig.to_le_bytes()); s.extend_from_slice(&m.tam_payload.to_le_bytes());
                            s.extend_from_slice(&m.hash); s.push(m.m_flags);
                            s.extend_from_slice(&(p.len() as u64).to_le_bytes()); s.extend_from_slice(p);
                        }
                        writeln!(o, "Ok n:{} flags:{} b3:{}", a.contenedor.miembros.len(), a.contenedor.flags, b3(&s)).unwrap();
                    }
                }
            }
            x => panic!("linea {x}"),
        }
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("generar") => generar(&a[2]),
        Some("leer") => leer(&a[2]),
        _ => { eprintln!("uso: dif_contenedor generar|leer <dir>"); std::process::exit(2); }
    }
}
