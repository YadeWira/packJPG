{ Primitivas criptograficas, en C, detras de una frontera angosta.

  El cifrado NO se escribe en Pascal: va en C (BLAKE3 1.8.7 y Monocypher 4.0.3
  oficiales), verificados byte a byte contra el Rust de referencia.
  Esta unidad es la unica que toca punteros hacia C, y los toma recien DESPUES
  de validar los limites del tramo sobre el arreglo, con $R+: los accesos por
  puntero no estan controlados, y @a[0] de un arreglo vacio dispara el control
  de rango. }
unit pjacripto;

{$I pja.inc}
{$ifopt R-}{$fatal pjacripto: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjacripto: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils;

type
  THash16 = array[0..15] of Byte;
  TClave  = array[0..31] of Byte;
  TNonce  = array[0..23] of Byte;
  ETramoInvalido = class(Exception);

{ BLAKE3 de a[aIni..aIni+aLen) seguido de b[bIni..bIni+bLen), truncado a 16 B.
  Un tramo de largo 0 es valido con cualquier arreglo, incluso vacio. }
function Blake3_128(const a: TBytes; aIni, aLen: SizeInt;
                    const b: TBytes; bIni, bLen: SizeInt): THash16;
{ Atajo para un solo arreglo entero. }
function Blake3_128(const a: TBytes): THash16;

{ Argon2id v1.3, sin secreto ni datos asociados. False = parametros invalidos o
  sin memoria para el area de trabajo (m KiB). }
function Argon2id(const pass, sal: TBytes; mKiB, t, p: LongWord; out clave: TClave): Boolean;
{ XChaCha20-Poly1305 de plano[ini..ini+n): devuelve cifrado ++ tag (n + 16 B),
  el mismo orden que el `encrypt` de RustCrypto. }
function AeadLock(const clave: TClave; const nonce: TNonce; const ad: array of Byte;
                  const plano: TBytes; ini, n: SizeInt): TBytes;
{ datos[ini..ini+n) es cifrado ++ tag. False si no autentica, y entonces `plano`
  vuelve vacio: Monocypher verifica el MAC antes de descifrar, nunca entrega
  texto sin autenticar. }
function AeadUnlock(const clave: TClave; const nonce: TNonce; const ad: array of Byte;
                    const datos: TBytes; ini, n: SizeInt; out plano: TBytes): Boolean;
{ Pone en cero de una forma que el compilador no puede sacar por "inutil". }
procedure Limpiar(var x; n: SizeInt);

implementation

{$L pja_cripto.o}
{$L blake3.o}
{$L blake3_dispatch.o}
{$L blake3_portable.o}
{$L monocypher.o}
{ malloc/memcpy/strlen/_assert del C: libc en Unix; en Windows msvcrt, que es la
  que trae todo Windows desde 7 (la libc.a de Linux ni siquiera es COFF). }
{$ifdef MSWINDOWS}{$linklib msvcrt}{$else}{$linklib c}{$endif}
{ libgcc: BLAKE3 cuenta bits con __builtin_popcountll, que sin -mpopcnt GCC
  resuelve llamando a __popcountdi2 de libgcc. -mpopcnt no es opcion: esa
  instruccion no existe en CPUs viejas de 32 bits. El build pasa la ruta con -Fl. }
{$linklib gcc}

procedure pja_blake3_128(a: PByte; na: SizeUInt; b: PByte; nb: SizeUInt; out16: PByte);
  cdecl; external name 'pja_blake3_128';

function pja_argon2id(pass: PByte; npass: SizeUInt; salt: PByte; nsalt: SizeUInt;
  m_kib, t, p: LongWord; out32: PByte): LongInt; cdecl; external name 'pja_argon2id';
procedure pja_aead_lock(key, nonce, ad: PByte; nad: SizeUInt; plano: PByte; n: SizeUInt;
  cifra, mac: PByte); cdecl; external name 'pja_aead_lock';
function pja_aead_unlock(key, nonce, ad: PByte; nad: SizeUInt; cifra: PByte; n: SizeUInt;
  mac, plano: PByte): LongInt; cdecl; external name 'pja_aead_unlock';
procedure pja_wipe(p: Pointer; n: SizeUInt); cdecl; external name 'pja_wipe';

function Puntero(const x: TBytes; ini, largo: SizeInt): PByte;
begin
  if largo = 0 then Exit(nil);
  { Int64 para que ini + largo no desborde en 32 bits antes de comparar. }
  if (ini < 0) or (largo < 0) or (Int64(ini) + Int64(largo) > Length(x)) then
    raise ETramoInvalido.CreateFmt('tramo [%d, +%d) fuera de un arreglo de %d', [ini, largo, Length(x)]);
  Result := @x[ini];     { controlado por $R+: ini ya es un indice valido }
end;

function Blake3_128(const a: TBytes; aIni, aLen: SizeInt;
                    const b: TBytes; bIni, bLen: SizeInt): THash16;
var pa, pb: PByte;
begin
  pa := Puntero(a, aIni, aLen);
  pb := Puntero(b, bIni, bLen);
  pja_blake3_128(pa, SizeUInt(aLen), pb, SizeUInt(bLen), @Result[0]);
end;

function Blake3_128(const a: TBytes): THash16;
begin
  Result := Blake3_128(a, 0, Length(a), nil, 0, 0);
end;

function Argon2id(const pass, sal: TBytes; mKiB, t, p: LongWord; out clave: TClave): Boolean;
begin
  FillChar(clave, SizeOf(clave), 0);
  Result := pja_argon2id(Puntero(pass, 0, Length(pass)), Length(pass),
                         Puntero(sal, 0, Length(sal)), Length(sal), mKiB, t, p, @clave[0]) = 0;
end;

function PunteroAd(const ad: array of Byte): PByte;
begin
  if Length(ad) = 0 then Result := nil else Result := @ad[0];
end;

function AeadLock(const clave: TClave; const nonce: TNonce; const ad: array of Byte;
                  const plano: TBytes; ini, n: SizeInt): TBytes;
var pp, pc: PByte;
begin
  pp := Puntero(plano, ini, n);         { valida el tramo antes de cualquier puntero }
  Result := nil; SetLength(Result, n + 16);
  if n > 0 then pc := @Result[0] else pc := nil;
  pja_aead_lock(@clave[0], @nonce[0], PunteroAd(ad), Length(ad), pp, n, pc, @Result[n]);
end;

function AeadUnlock(const clave: TClave; const nonce: TNonce; const ad: array of Byte;
                    const datos: TBytes; ini, n: SizeInt; out plano: TBytes): Boolean;
var pc, pm, pp: PByte; largo: SizeInt;
begin
  plano := nil;
  if n < 16 then raise ETramoInvalido.CreateFmt('AeadUnlock: %d B no alcanzan para el tag', [n]);
  largo := n - 16;
  pc := Puntero(datos, ini, largo);
  pm := Puntero(datos, ini + largo, 16);
  SetLength(plano, largo);
  if largo > 0 then pp := @plano[0] else pp := nil;
  Result := pja_aead_unlock(@clave[0], @nonce[0], PunteroAd(ad), Length(ad), pc, largo, pm, pp) = 0;
  if not Result then plano := nil;
end;

procedure Limpiar(var x; n: SizeInt);
begin
  if n > 0 then pja_wipe(@x, n);
end;

end.
