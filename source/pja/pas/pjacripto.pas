{ Primitivas criptograficas, en C, detras de una frontera angosta.

  El cifrado NO se escribe en Pascal: va en C (BLAKE3 oficial y, al portar
  cifrado, Monocypher 4), verificados byte a byte contra el Rust de referencia.
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
  ETramoInvalido = class(Exception);

{ BLAKE3 de a[aIni..aIni+aLen) seguido de b[bIni..bIni+bLen), truncado a 16 B.
  Un tramo de largo 0 es valido con cualquier arreglo, incluso vacio. }
function Blake3_128(const a: TBytes; aIni, aLen: SizeInt;
                    const b: TBytes; bIni, bLen: SizeInt): THash16;
{ Atajo para un solo arreglo entero. }
function Blake3_128(const a: TBytes): THash16;

implementation

{$L pja_cripto.o}
{$L blake3.o}
{$L blake3_dispatch.o}
{$L blake3_portable.o}
{$linklib c}
{ libgcc: BLAKE3 cuenta bits con __builtin_popcountll, que sin -mpopcnt GCC
  resuelve llamando a __popcountdi2 de libgcc. -mpopcnt no es opcion: esa
  instruccion no existe en CPUs viejas de 32 bits. El build pasa la ruta con -Fl. }
{$linklib gcc}

procedure pja_blake3_128(a: PByte; na: SizeUInt; b: PByte; nb: SizeUInt; out16: PByte);
  cdecl; external name 'pja_blake3_128';

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

end.
