//! Veredictos del nombres.rs REAL para cada entrada de un corpus (hex, una por
//! linea). Es la referencia contra la que se compara el port a Pascal
//! (`source/pja/pas/diferencial/`): mismo formato, linea por linea.
use std::io::{BufRead, BufWriter, Write};
use pjacore::nombres::{plano, ruta};
fn main() {
    let a = std::env::args().nth(1).expect("uso: dif_nombres <corpus.hex>");
    let f = std::io::BufReader::new(std::fs::File::open(a).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    for l in f.lines() {
        let l = l.unwrap();
        let b: Vec<u8> = (0..l.len()).step_by(2).map(|i| u8::from_str_radix(&l[i..i + 2], 16).unwrap()).collect();
        writeln!(o, "{:?} {:?}", plano(&b), ruta(&b)).unwrap();
    }
}
