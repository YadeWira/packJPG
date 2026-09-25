//! Diferencial de `escritor`: conjuntos de entradas, y lo que `escribir` del
//! Rust REAL produce con cada uno. El port a Pascal tiene que producir el mismo
//! archivo byte a byte, o el mismo error.
//!
//!   dif_escritor generar <corpus.txt>   un conjunto por linea
//!   dif_escritor leer    <corpus.txt>   un resultado por linea
//!
//! Formato de un conjunto:  flags;e1|e2|...   con cada entrada
//!   nombre_hex,tam_orig,largo_payload,semilla,hash_hex
//! El payload se deriva de (largo, semilla) de la misma forma de los dos lados.
use pjacore::escritor::{escribir, Entrada};
use std::io::{BufRead, BufWriter, Write};

fn payload(largo: usize, semilla: u64) -> Vec<u8> {
    (0..largo).map(|k| (semilla.wrapping_mul(31).wrapping_add(k as u64 * 7) & 0xFF) as u8).collect()
}
fn hx(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
fn dehx(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect() }

struct Gen(u64);
impl Gen { fn n(&mut self) -> u64 { self.0 ^= self.0 << 13; self.0 ^= self.0 >> 7; self.0 ^= self.0 << 17; self.0 } }

fn generar(salida: &str) {
    let mut o = BufWriter::new(std::fs::File::create(salida).unwrap());
    let mut total = 0usize;
    let mut put = |flags: u8, es: &[(Vec<u8>, u64, usize, u64, [u8; 16])], o: &mut BufWriter<std::fs::File>| {
        let v: Vec<String> = es.iter().map(|(n, t, l, s, h)| format!("{},{},{},{},{}", hx(n), t, l, s, hx(h))).collect();
        writeln!(o, "{};{}", flags, v.join("|")).unwrap(); total += 1;
    };
    let e = |n: &[u8], t: u64, l: usize, s: u64| (n.to_vec(), t, l, s, [(s as u8).wrapping_mul(13); 16]);
    // flags: todos los valores, con un conjunto chico fijo. El escritor escribe
    // el byte tal cual -- incluidos bits desconocidos que el lector rechaza.
    for fl in 0..=255u8 { put(fl, &[e(b"a.jpg", 200, 100, 1), e(b"d/b.jpg", 30, 12, 2)], &mut o); put(fl, &[], &mut o); }
    // largos de payload en el borde del minimo, tam_orig en los extremos
    for l in [0usize, 1, 11, 12, 13, 64, 300] {
        for t in [0u64, 1, 12, 1 << 32, u64::MAX] { put(0, &[e(b"x.jpg", t, l, 7)], &mut o); }
    }
    // orden de los errores adentro de una entrada: nombre, despues payload, despues duplicado
    let casos: &[&[(&[u8], usize)]] = &[
        &[(b"a", 12), (b"a", 12)], &[(b"a", 12), (b"a", 0)], &[(b"a", 12), (b"../a", 0)],
        &[(b"../a", 0), (b"a", 12)], &[(b"a", 0), (b"a", 12)], &[(b"a", 12), (b"b", 12), (b"a", 12)],
        &[(b"a", 12), (b"b", 12), (b"c", 12), (b"b", 12), (b"a", 12)], &[(b"", 12)], &[(b"a/b", 12)],
        &[(b"CON.jpg", 12), (b"foto?.jpg", 12), (b"nul", 12)], &[(b"CON.jpg", 12), (b"CON.jpg", 12)],
        &[(b"a.jpg ", 12), (b"b.", 12)], &[(b"x:y", 12)], &[(b"\xc3\xb1and\xc3\xba.jpg", 12)], &[(b"\xff", 12)],
    ];
    for c in casos {
        for fl in [0u8, 2] {   // plano y con rutas
            let v: Vec<_> = c.iter().enumerate().map(|(i, (n, l))| e(n, 24, *l, i as u64)).collect();
            put(fl, &v, &mut o);
        }
    }
    // nombres al azar sesgados, en conjuntos de 1 a 8, plano y rutas
    let alfa = b"ab.. //\\\\::*?<>|\"CONnul\x00\x1f\x7f\xc3\xb1\xe5\x86\x99\xff".to_vec();
    let mut g = Gen(20260925);
    for _ in 0..4000 {
        let k = 1 + (g.n() % 8) as usize;
        let v: Vec<_> = (0..k).map(|i| {
            let nl = 1 + (g.n() % 12) as usize;
            let n: Vec<u8> = (0..nl).map(|_| alfa[(g.n() % alfa.len() as u64) as usize]).collect();
            e(&n, g.n() % 1000, 12 + (g.n() % 40) as usize, i as u64)
        }).collect();
        put(if g.n() % 2 == 0 { 0 } else { 2 }, &v, &mut o);
    }
    // nombres mayormente VALIDOS sacados de un conjunto chico, para que haya
    // muchos Ok, muchos avisos de Windows y muchos duplicados en posiciones
    // distintas (la tanda de arriba sale casi toda NombreInvalido)
    let pozo: Vec<&[u8]> = vec![b"a.jpg", b"b.jpg", b"c.jpg", b"d/e.jpg", b"d/f.jpg", b"2026/x.jpg",
        b"CON.jpg", b"foto?.jpg", b"arch.", b"con espacio .jpg", b"\xc3\xb1.jpg", b"\xe5\x86\x99.jpg",
        b"LPT1", b"a<b>.jpg", b"z.jpg ", b"aux.txt", b"q.jpg", b"r.jpg"];
    for _ in 0..6000 {
        let k = 1 + (g.n() % 7) as usize;
        let v: Vec<_> = (0..k).map(|i| {
            let n = pozo[(g.n() % pozo.len() as u64) as usize];
            let l = if g.n() % 25 == 0 { (g.n() % 12) as usize } else { 12 + (g.n() % 30) as usize };
            e(n, g.n() % 5000, l, i as u64)
        }).collect();
        put(if g.n() % 2 == 0 { 0 } else { 2 }, &v, &mut o);
    }
    // muchos nombres distintos, con y sin un repetido al final
    let muchos: Vec<_> = (0..3000).map(|i| e(format!("f{:05}.jpg", i).as_bytes(), 24, 12, i)).collect();
    put(0, &muchos, &mut o);
    let mut con_rep = muchos.clone(); con_rep.push(e(b"f01500.jpg", 24, 12, 9)); put(0, &con_rep, &mut o);
    drop(put);
    eprintln!("{} conjuntos", total);
}

fn leer(corpus: &str) {
    let f = std::io::BufReader::new(std::fs::File::open(corpus).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    for l in f.lines() {
        let l = l.unwrap();
        let (fl, resto) = l.split_once(';').unwrap();
        let flags: u8 = fl.parse().unwrap();
        let mut datos: Vec<(Vec<u8>, u64, Vec<u8>, [u8; 16])> = Vec::new();
        if !resto.is_empty() {
            for c in resto.split('|') {
                let p: Vec<&str> = c.split(',').collect();
                let mut h = [0u8; 16]; h.copy_from_slice(&dehx(p[4]));
                datos.push((dehx(p[0]), p[1].parse().unwrap(), payload(p[2].parse().unwrap(), p[3].parse().unwrap()), h));
            }
        }
        let es: Vec<Entrada> = datos.iter().map(|(n, t, p, h)| Entrada { nombre: n, tam_orig: *t, payload: p, hash: *h }).collect();
        match escribir(&es, flags) {
            Err(e) => writeln!(o, "{:?}", e).unwrap(),
            Ok((b, av)) => {
                let a: Vec<String> = av.iter().map(|(i, m)| format!("{}:{:?}", i, m)).collect();
                writeln!(o, "Ok avisos=[{}] {}", a.join(","), hx(&b)).unwrap();
            }
        }
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("generar") => generar(&a[2]),
        Some("leer") => leer(&a[2]),
        _ => { eprintln!("uso: dif_escritor generar|leer <archivo>"); std::process::exit(2); }
    }
}
