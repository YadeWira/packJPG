//! Batería de corrupción sobre contenedores reales.
//!
//! Distinta de las pruebas de construcción: acá se toma un contenedor válido
//! armado con `.pjg` de verdad y se lo daña sistemáticamente.
//!
//! Con la invariante que faltaba en todos nuestros barridos: **los baldes
//! suman la cuenta de celdas**, y una celda saltada hace fallar la corrida.

#[cfg(test)]
mod bateria {
    use crate::escritor::*;
    use crate::indice::*;
    use std::fs;

    const CORPUS: &str = "/mnt/IA_LAB/agentes/PJPG/verificacion/corpus-validos";

    #[derive(Default, Debug)]
    struct Cuenta {
        celdas: usize,
        rechaza: usize,
        lee_igual: usize,
        lee_distinto: usize,
        saltadas: usize,
    }

    impl Cuenta {
        /// Los baldes tienen que sumar las celdas. Sin esto, una clase nueva
        /// se cae de la tabla y el numero impreso sigue pareciendo razonable.
        fn cuadra(&self) -> bool {
            self.rechaza + self.lee_igual + self.lee_distinto + self.saltadas == self.celdas
        }
    }

    fn contenedor_real() -> (Vec<u8>, Contenedor) {
        let mut rutas: Vec<_> = fs::read_dir(CORPUS).unwrap()
            .filter_map(|e| e.ok()).map(|e| e.path())
            .filter(|p| p.extension().map_or(false, |x| x == "pjg")).collect();
        rutas.sort(); rutas.truncate(6);
        let datos: Vec<Vec<u8>> = rutas.iter().map(|p| fs::read(p).unwrap()).collect();
        let nombres: Vec<Vec<u8>> = rutas.iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().as_bytes().to_vec()).collect();
        let ents: Vec<Entrada> = datos.iter().zip(&nombres).map(|(d, n)| Entrada {
            nombre: n, tam_orig: d.len() as u64 * 2, payload: d,
            hash: { let h = blake3::hash(d); let mut a=[0u8;16];
                    a.copy_from_slice(&h.as_bytes()[..16]); a },
        }).collect();
        let (bytes, _) = escribir(&ents, 0).unwrap();
        let c = leer_indice(&bytes).unwrap();
        (bytes, c)
    }

    fn iguales(a: &Contenedor, b: &Contenedor) -> bool {
        a.flags == b.flags && a.miembros == b.miembros
    }

    #[test] fn corrupcion_de_un_bit_en_todo_el_contenedor() {
        let (base, orig) = contenedor_real();
        let (_, ti, _) = leer_cabecera(&base).unwrap();
        let fin_indice = TAM_CABECERA + ti as usize;

        // La fila conocida: el contenedor intacto se lee.
        assert!(leer_indice(&base).is_ok(), "control positivo");

        let mut c = Cuenta::default();
        // Un bit dado vuelta en cada byte de la cabecera y del indice, y en
        // una muestra del payload.
        let mut posiciones: Vec<usize> = (0..fin_indice).collect();
        posiciones.extend((fin_indice..base.len()).step_by(9_973));

        for &p in &posiciones {
            for bit in [0u8, 3, 7] {
                c.celdas += 1;
                let mut d = base.clone();
                d[p] ^= 1 << bit;
                match leer_indice(&d) {
                    Err(_) => c.rechaza += 1,
                    Ok(leido) => {
                        if iguales(&orig, &leido) { c.lee_igual += 1 }
                        else {
                            c.lee_distinto += 1;
                            let region = if p < 4 { "magia" }
                                else if p == 4 { "version" } else if p == 5 { "flags" }
                                else if p < 8 { "reservado" } else if p < 12 { "tam_indice" }
                                else if p < 28 { "hash_indice" }
                                else if p < fin_indice { "indice" } else { "payload" };
                            eprintln!("  LEE_DISTINTO en {region} offset {p} bit {bit}");
                            eprintln!("    flags {} -> {}", orig.flags, leido.flags);
                            for (i, (a, b)) in orig.miembros.iter().zip(&leido.miembros).enumerate() {
                                if a != b {
                                    eprintln!("    miembro {i} difiere:");
                                    if a.nombre != b.nombre {
                                        eprintln!("      nombre {:?} -> {:?}",
                                            core::str::from_utf8(&a.nombre), core::str::from_utf8(&b.nombre)); }
                                    if a.tam_orig != b.tam_orig {
                                        eprintln!("      tam_orig {} -> {}", a.tam_orig, b.tam_orig); }
                                    if a.tam_payload != b.tam_payload {
                                        eprintln!("      tam_payload {} -> {}", a.tam_payload, b.tam_payload); }
                                    if a.hash != b.hash { eprintln!("      hash cambiado"); }
                                    if a.m_flags != b.m_flags {
                                        eprintln!("      m_flags {} -> {}", a.m_flags, b.m_flags); }
                                }
                            }
                            if orig.miembros.len() != leido.miembros.len() {
                                eprintln!("    cantidad {} -> {}", orig.miembros.len(), leido.miembros.len()); }
                        }
                    }
                }
            }
        }

        eprintln!("  {:?}", c);
        assert!(c.cuadra(), "los baldes no suman las celdas: {c:?}");
        assert_eq!(c.saltadas, 0, "hubo celdas que se cayeron de la tabla");
        eprintln!("  indice sin proteccion de integridad -> lee_distinto = {}", c.lee_distinto);
    }

    #[test] fn truncacion_en_cada_region() {
        let (base, _) = contenedor_real();
        let mut c = Cuenta::default();
        let mut cortes: Vec<usize> = (0..64).collect();
        cortes.extend((64..base.len()).step_by(base.len() / 40));

        for k in cortes {
            c.celdas += 1;
            match leer_indice(&base[..k]) {
                Err(_) => c.rechaza += 1,
                Ok(_)  => c.lee_distinto += 1,   // leer un truncado es fallo
            }
        }
        eprintln!("  truncacion: {:?}", c);
        assert!(c.cuadra());
        assert_eq!(c.lee_distinto, 0, "un contenedor truncado nunca debe leerse");
    }
}
