//! Diferencial de `indice`: genera un corpus de contenedores hostiles y vuelca
//! lo que `leer_indice` del Rust REAL dice de cada uno. El port a Pascal
//! (`source/pja/pas/diferencial/dif_indice.pas`) tiene que decir lo mismo.
//!
//!   dif_indice generar <corpus.hex>     una entrada por linea, en hex
//!   dif_indice leer    <corpus.hex>     un veredicto por linea
//!
//! Las mutaciones del indice se RESELLAN (hash recalculado): sin eso casi todo
//! daria IndiceAlterado y los seis limites no se ejercitarian nunca.
use pjacore::indice::*;
use std::io::{BufRead, BufWriter, Write};

fn armar(noms: &[&[u8]], orig: u64, pay: u64, flags: u8, kdf: u8) -> Vec<u8> {
    let mut idx = Vec::new();
    idx.extend_from_slice(&(noms.len() as u32).to_le_bytes());
    for (i, n) in noms.iter().enumerate() {
        idx.extend_from_slice(&(n.len() as u16).to_le_bytes());
        idx.extend_from_slice(n);
        idx.extend_from_slice(&orig.to_le_bytes());
        idx.extend_from_slice(&pay.to_le_bytes());
        idx.extend_from_slice(&[(i as u8).wrapping_mul(37); 16]);
        idx.push(i as u8);
    }
    let mut c = Vec::new();
    c.extend_from_slice(&MAGIA); c.push(VERSION); c.push(flags); c.push(kdf); c.push(0);
    c.extend_from_slice(&(idx.len() as u32).to_le_bytes()); c.extend_from_slice(&[0u8; 16]);
    c.extend_from_slice(&idx);
    resellar(&mut c);
    c.resize(c.len() + pay as usize * noms.len(), 0xAB);
    c
}
/// Recalcula el hash si tam_indice entra; si no, no hay nada que resellar.
fn resellar(c: &mut Vec<u8>) {
    if c.len() < TAM_CABECERA { return; }
    let ti = u32::from_le_bytes([c[8], c[9], c[10], c[11]]) as usize;
    if TAM_CABECERA + ti > c.len() { return; }
    let h = hash_cabecera_indice(&c[..TAM_CABECERA], &c[TAM_CABECERA..TAM_CABECERA + ti].to_vec());
    c[12..28].copy_from_slice(&h);
}
fn escribir_campo(c: &mut Vec<u8>, off: usize, v: &[u8]) {
    if off + v.len() <= c.len() { c[off..off + v.len()].copy_from_slice(v); }
}

fn generar(salida: &str) {
    let mut o = BufWriter::new(std::fs::File::create(salida).unwrap());
    let mut n = 0usize;
    let mut put = |c: &[u8], o: &mut BufWriter<std::fs::File>| {
        writeln!(o, "{}", c.iter().map(|b| format!("{:02x}", b)).collect::<String>()).unwrap(); n += 1;
    };
    let ruta = FLAG_RUTAS; let cif = FLAG_CIFRADO;
    let bases: Vec<Vec<u8>> = vec![
        armar(&[], 0, 12, 0, 0),
        armar(&[b"a.jpg"], 200, 100, 0, 0),
        armar(&[b"a.jpg", b"b.jpg"], 200, 100, 0, 0),
        armar(&[b"x", b"y", b"z"], 24, 12, 0, 0),
        armar(&[b"2026/enero/a.jpg", b"2026/b.jpg"], 200, 100, ruta, 0),
        armar(&[b"a.jpg", b"b.jpg"], 200, 100, cif, 0),
        armar(&[b"d/a", b"d/b"], 200, 100, cif | ruta, 0),
        armar(&[b"CON.jpg", b"foto?.jpg"], 200, 100, 0, 0),         // SoloWindows: pasan
        armar(&[b"solido.jpg"], 200, 100, FLAG_SOLIDO, 0),
    ];
    for b in &bases {
        put(b, &mut o);
        // truncados y agregados
        for l in 0..b.len() { put(&b[..l], &mut o); }
        for extra in [1usize, 12, 100] { let mut c = b.clone(); c.extend(std::iter::repeat(0).take(extra)); put(&c, &mut o); }
        // cada byte, con cuatro valores, sin resellar y resellando
        for i in 0..b.len() {
            for &v in &[b[i] ^ 0x01, b[i] ^ 0x80, 0x00, 0xFF] {
                if v == b[i] { continue; }
                let mut c = b.clone(); c[i] = v; put(&c, &mut o);
                if i < 12 || i >= TAM_CABECERA { resellar(&mut c); put(&c, &mut o); }
            }
        }
        // cabecera: version, cada flag, kdf, reservado — reseladas
        for ver in [0u8, 1, 2, 3, 255] { let mut c = b.clone(); c[4] = ver; resellar(&mut c); put(&c, &mut o); }
        for fl in 0..=255u8 { let mut c = b.clone(); c[5] = fl; resellar(&mut c); put(&c, &mut o); }
        for kd in [0u8, 1, 2, 255] { let mut c = b.clone(); c[6] = kd; resellar(&mut c); put(&c, &mut o); }
        for re in [1u8, 0x80, 0xFF] { let mut c = b.clone(); c[7] = re; resellar(&mut c); put(&c, &mut o); }
        // tam_indice en los bordes
        let ti = u32::from_le_bytes([b[8], b[9], b[10], b[11]]);
        for t in [0u32, 1, 3, 4, ti.saturating_sub(1), ti + 1, (b.len() - TAM_CABECERA) as u32,
                  (b.len() - TAM_CABECERA) as u32 + 1, u32::MAX] {
            let mut c = b.clone(); escribir_campo(&mut c, 8, &t.to_le_bytes()); resellar(&mut c); put(&c, &mut o);
        }
        // count en los bordes
        let cnt = u32::from_le_bytes([b[28], b[29], b[30], b[31]]);
        for k in [0u32, 1, cnt.saturating_sub(1), cnt + 1, 1_048_575, 1_048_576, 1_048_577, u32::MAX] {
            let mut c = b.clone(); escribir_campo(&mut c, 28, &k.to_le_bytes()); resellar(&mut c); put(&c, &mut o);
        }
        // campos del primer miembro, si hay
        if cnt > 0 {
            let nl = u16::from_le_bytes([b[32], b[33]]) as usize;
            for v in [0u16, 1, 255, 256, 1024, 1025, u16::MAX] {
                let mut c = b.clone(); escribir_campo(&mut c, 32, &v.to_le_bytes()); resellar(&mut c); put(&c, &mut o);
            }
            let off_orig = 34 + nl; let off_pay = off_orig + 8;
            for v in [0u64, 1, 11, 12, 13, b.len() as u64, b.len() as u64 + 1, u64::MAX / 500, u64::MAX / 500 + 1,
                      8 * 1024 * 1024 * 1024, 8 * 1024 * 1024 * 1024 + 1, u64::MAX] {
                let mut c = b.clone(); escribir_campo(&mut c, off_orig, &v.to_le_bytes()); resellar(&mut c); put(&c, &mut o);
                let mut c = b.clone(); escribir_campo(&mut c, off_pay, &v.to_le_bytes()); resellar(&mut c); put(&c, &mut o);
            }
        }
    }
    // duplicados e invalidos en todas las posiciones relativas: el ORDEN decide que error sale
    let casos: &[&[&[u8]]] = &[
        &[b"a", b"a"], &[b"a", b"b", b"a"], &[b"a", b"b", b"b", b"a"], &[b"b", b"a", b"b", b"a"],
        &[b"../x", b"a", b"a"], &[b"a", b"a", b"../x"], &[b"a", b"../x", b"a"],
        &[b"a", b"b", b"c", b"d", b"c", b"b", b"a"], &[b"", b"a"], &[b"a", b""],
        &[b"CON", b"CON"], &[b"a/b", b"a/b"], &[b"a.jpg", b"A.jpg"],
    ];
    for noms in casos {
        for fl in [0u8, FLAG_RUTAS] { put(&armar(noms, 200, 100, fl, 0), &mut o); }
    }
    // ratio y presupuesto: tam_orig grande repartido
    for orig in [0u64, 1000, 50_000, 49_999 * 1000, u64::MAX / 2, u64::MAX] {
        put(&armar(&[b"a", b"b"], orig, 100, 0, 0), &mut o);
    }
    // presupuesto: solo alcanzable si el ratio (500 x archivo) no dispara antes,
    // o sea con un archivo de mas de 8 GiB / 500 = 17.179.869 B.
    let grande = 18_000_000u64;   // 8 GiB / 500 = 17.179.869 B: hay que pasar eso
    let presupuesto = 8u64 * 1024 * 1024 * 1024;
    for orig in [presupuesto, presupuesto + 1] {
        put(&armar(&[b"grande.jpg"], orig, grande, 0, 0), &mut o);
    }
    drop(put);
    eprintln!("{} entradas", n);
}

fn leer(corpus: &str) {
    let f = std::io::BufReader::new(std::fs::File::open(corpus).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    for l in f.lines() {
        let l = l.unwrap();
        let d: Vec<u8> = (0..l.len()).step_by(2).map(|i| u8::from_str_radix(&l[i..i + 2], 16).unwrap()).collect();
        match leer_indice(&d) {
            Err(e) => writeln!(o, "{:?}", e).unwrap(),
            Ok(c) => {
                write!(o, "Ok flags={} n={} ", c.flags, c.miembros.len()).unwrap();
                for m in &c.miembros {
                    let h = |b: &[u8]| b.iter().map(|x| format!("{:02x}", x)).collect::<String>();
                    write!(o, "{}:{}:{}:{}:{};", h(&m.nombre), m.tam_orig, m.tam_payload, h(&m.hash), m.m_flags).unwrap();
                }
                writeln!(o).unwrap();
            }
        }
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("generar") => generar(&a[2]),
        Some("leer") => leer(&a[2]),
        _ => { eprintln!("uso: dif_indice generar|leer <archivo>"); std::process::exit(2); }
    }
}
