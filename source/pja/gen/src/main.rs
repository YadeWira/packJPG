fn main() {
    let args: Vec<String> = std::env::args().collect();
    let salida = &args[1];
    let pass = if args[2] == "-" { None } else { Some(&args[2]) };
    let rutas: Vec<_> = args[3..].to_vec();
    let datos: Vec<Vec<u8>> = rutas.iter().map(|p| std::fs::read(p).unwrap()).collect();
    let nombres: Vec<Vec<u8>> = rutas.iter()
        .map(|p| std::path::Path::new(p).file_name().unwrap().to_string_lossy().as_bytes().to_vec()).collect();
    let ents: Vec<pjacore::escritor::Entrada> = datos.iter().zip(&nombres).map(|(d,n)| pjacore::escritor::Entrada{
        nombre: n, tam_orig: d.len() as u64, payload: d,
        hash: { let h = blake3::hash(d); let mut a=[0u8;16]; a.copy_from_slice(&h.as_bytes()[..16]); a },
    }).collect();
    let bytes = match pass {
        Some(p) => {
            let sal = [7u8;16]; let nb = [9u8;24];
            let clave = pjacore::cifrado::derivar_clave(p.as_bytes(), &sal).unwrap();
            pjacore::contenedor::escribir(&ents, pjacore::indice::FLAG_CIFRADO, Some((&clave,&nb,&sal))).unwrap().0
        }
        None => pjacore::contenedor::escribir(&ents, 0, None).unwrap().0,
    };
    std::fs::write(salida, &bytes).unwrap();
    println!("escrito {} ({} bytes)", salida, bytes.len());
}
