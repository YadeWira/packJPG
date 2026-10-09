# Monocypher — código C oficial, sin modificar

- origen: https://github.com/LoupVaillant/Monocypher, release `4.0.3`
- verificado el 25/09/2026: el tarball difiere del tag `4.0.3` del repo en **una
  sola línea por archivo**, el comentario `// Monocypher version __git__` →
  `4.0.3`. El código es idéntico.
- verificado contra el Rust de referencia (RustCrypto `chacha20poly1305` y
  `argon2`): Argon2id con el perfil V1 da la misma clave, y el cifrado por trozos
  da el mismo archivo byte a byte, en Linux 32/64 y Windows 7 real 32/64
  (`/mnt/IA_LAB/agentes/PJPG/monocypher-kat/RESULTADOS.md`)
- se usan sólo `crypto_aead_lock`/`crypto_aead_unlock` (XChaCha20-Poly1305,
  nonce de 24 B) y `crypto_argon2` con `CRYPTO_ARGON2_ID`
- licencia: BSD 2 cláusulas o CC0, a elección (`LICENCE.md`)
