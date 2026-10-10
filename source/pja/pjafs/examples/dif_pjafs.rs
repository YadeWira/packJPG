//! Diferencial de `pjafs`: ejecuta cada caso de `casos.txt` contra un árbol de
//! escenarios ya preparado (lo arma `pas/diferencial/escenarios_fs.py`, igual
//! para las dos puntas) y vuelca lo que devuelve. El port a Pascal
//! (`pas/diferencial/dif_pjafs.pas`) tiene que decir lo mismo, y el árbol que
//! queda en disco después tiene que ser el mismo.
//!
//!   dif_pjafs <raiz> <casos.txt>
//!
//! `raiz` es la ruta canónica del árbol; las rutas de la salida la llevan
//! reemplazada por `R`, así las dos puntas (con raíces del mismo largo) se
//! comparan línea a línea. Casos, campos separados por espacio, hex para bytes:
//!
//!   D esc dest nombre rutas sobrescribir            destino_de
//!   W esc dest nombre rutas sobr semilla ok si      destino_de + escribir_verificado
//!   X esc ruta sobr semilla ok si                   escribir_verificado directo (carreras)
//!   C ...                                           como D, con la cwd en R/esc y `dest` relativo
//!
//! `dest`, `nombre` y `ruta` en hex (`-` es vacío); `ok` 1/0: el hash esperado
//! es el de los datos o el de otra cosa; `si` B (borrar) o C (conservar).
use pjafs::*;
use std::io::{BufRead, BufWriter, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

fn hex(s: &str) -> Vec<u8> {
    if s == "-" { return Vec::new(); }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
}
fn ah(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
fn h16(d: &[u8]) -> [u8; 16] {
    let mut a = [0u8; 16];
    a.copy_from_slice(&blake3::hash(d).as_bytes()[..16]);
    a
}
fn datos(semilla: &str) -> Vec<u8> {
    let n: usize = semilla.parse().unwrap();
    (0..n).map(|i| (i * 31 + n) as u8).collect()
}
/// La ruta con la raíz reemplazada por `R`, en hex si no es UTF-8.
fn rel(raiz: &[u8], p: &Path) -> String {
    let b = p.as_os_str().as_bytes();
    let b = if b.starts_with(raiz) { [b"R".as_slice(), &b[raiz.len()..]].concat() } else { b.to_vec() };
    match std::str::from_utf8(&b) { Ok(s) => s.to_string(), Err(_) => format!("hex:{}", ah(&b)) }
}
fn ext(r: &Result<PathBuf, ErrorExtraccion>, raiz: &[u8]) -> String {
    match r { Ok(p) => format!("Ok {}", rel(raiz, p)), Err(e) => format!("{:?}", e) }
}
fn esc(r: &Result<Desenlace, ErrorEscritura>, raiz: &[u8]) -> String {
    let c = |e: &std::io::Error| e.raw_os_error().map_or("-".to_string(), |n| n.to_string());
    match r {
        Ok(Desenlace::Verificado(p)) => format!("Verificado({})", rel(raiz, p)),
        Ok(Desenlace::Borrado { esperado, obtenido }) => format!("Borrado({},{})", ah(esperado), ah(obtenido)),
        Ok(Desenlace::Conservado { ruta, esperado, obtenido }) =>
            format!("Conservado({},{},{})", rel(raiz, ruta), ah(esperado), ah(obtenido)),
        Err(ErrorEscritura::Io(e)) => format!("Io({})", c(e)),
        Err(ErrorEscritura::NoSePudoConservar(e)) => format!("NoSePudoConservar({})", c(e)),
    }
}
fn escribir(p: &Path, w: &[&str], raiz: &[u8]) -> String {
    let d = datos(w[0]);
    let esperado = if w[1] == "1" { h16(&d) } else { h16(b"otra cosa") };
    let si = if w[2] == "C" { SiFalla::Conservar } else { SiFalla::Borrar };
    let sobr = w[3] == "1";
    esc(&escribir_verificado(p, &d, &esperado, si, sobr), raiz)
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 3 { eprintln!("uso: dif_pjafs <raiz> <casos.txt>"); std::process::exit(2); }
    let raiz = PathBuf::from(&a[1]);
    let rb = raiz.as_os_str().as_bytes().to_vec();
    let f = std::io::BufReader::new(std::fs::File::open(&a[2]).unwrap());
    let mut o = BufWriter::new(std::io::stdout());
    for l in f.lines() {
        let l = l.unwrap();
        let w: Vec<&str> = l.split(' ').collect();
        let base = raiz.join(w[1]);
        let s = match w[0] {
            "D" | "C" => {
                let dest = std::ffi::OsStr::from_bytes(&hex(w[2])).to_os_string();
                let dest = if w[0] == "C" { std::env::set_current_dir(&base).unwrap(); PathBuf::from(dest) }
                           else { base.join(dest) };
                let r = destino_de(&dest, &hex(w[3]), w[4] == "1", w[5] == "1");
                if w[0] == "C" { std::env::set_current_dir("/").unwrap(); }
                ext(&r, &rb)
            }
            "W" => {
                let dest = base.join(std::ffi::OsStr::from_bytes(&hex(w[2])));
                let r = destino_de(&dest, &hex(w[3]), w[4] == "1", w[5] == "1");
                match &r {
                    Ok(p) => format!("{} -> {}", ext(&r, &rb), escribir(p, &[w[6], w[7], w[8], w[5]], &rb)),
                    Err(_) => ext(&r, &rb),
                }
            }
            "X" => {
                let p = base.join(std::ffi::OsStr::from_bytes(&hex(w[2])));
                escribir(&p, &[w[4], w[5], w[6], w[3]], &rb)
            }
            _ => panic!("caso desconocido: {l}"),
        };
        writeln!(o, "{s}").unwrap();
    }
}
