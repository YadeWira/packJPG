# BLAKE3 — código C oficial, sin modificar

- origen: https://github.com/BLAKE3-team/BLAKE3, tag `1.8.7`, directorio `c/`
- **misma versión que el crate `blake3` del Rust de referencia** (`Cargo.lock`),
  para que la comparación diferencial no mezcle versiones
- se compila **portable**, sin SIMD: `-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41
  -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512`. Correcto en cualquier CPU de 32 y 64 bits;
  la velocidad se revisa después.
- verificado el 25/09/2026 contra el Rust sobre 0, 1, 1024, 1025 B y 1 MiB, en
  Linux 32/64 y Windows 7 real 32/64: mismo hash
  (`/mnt/IA_LAB/agentes/PJPG/monocypher-kat/RESULTADOS.md`)
- licencia: CC0 1.0 o Apache 2.0 a elección (archivos `LICENSE_*` de acá)
