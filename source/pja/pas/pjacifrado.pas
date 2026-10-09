{ Cifrado autenticado por trozos. Port de pjacore/src/cifrado.rs, con las
  primitivas en C (Monocypher 4.0.3) detras de pjacripto.

  El MAC se verifica antes de que un byte llegue al codec. Por trozos de 64 KB
  y no en un bloque, porque un AEAD unico obligaria a tener el contenedor entero
  en memoria antes de verificar el tag. Las dos reglas que se olvidan y son el
  error clasico del cifrado por trozos: el NUMERO de trozo va en el AAD (asi
  reordenar falla) y el ULTIMO se marca en su propio AAD (asi truncar falla).

  Heredado del Rust tal cual, para que la comparacion diferencial sea limpia:
  - descifrar acepta trozos DESPUES del marcado como ultimo, si autentican.
    No es explotable desde afuera (armar un trozo valido exige la clave), pero
    pesa en el diseno append-only, donde quien tiene la clave SI agrega datos.
  - ClaveIncorrecta esta declarada y nunca se produce: una contrasena
    equivocada da TrozoAlterado(0). }
unit pjacifrado;

{$I pja.inc}
{$ifopt R-}{$fatal pjacifrado: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjacifrado: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils, pjacripto;

const
  TAM_TROZO = 64 * 1024;
  TAM_TAG   = 16;
  TAM_SAL   = 16;
  TAM_NONCE = 24;

type
  TErrorCifrado = (ecNinguno, ecClaveIncorrecta, ecTrozoAlterado, ecTruncado, ecFormato);
  TResultadoCifrado = record
    err: TErrorCifrado;
    valor: QWord;           { el numero de trozo, en TrozoAlterado }
    function Ok: Boolean;
    function Texto: string; { mismo texto que el Debug de Rust }
  end;

  { Perfil de derivacion de clave. Va identificado por un byte en la cabecera,
    no por sus numeros: un contenedor que declarara m y t crudos seria un vector
    de DoS -- pedir memoria arbitraria antes de validar nada. }
  TPerfilKdf = (pkV1);   { Argon2id, m = 64 MiB, t = 3, p = 1 }
  TSal = array[0..TAM_SAL - 1] of Byte;

function PerfilDeByte(b: Byte; out perfil: TPerfilKdf): Boolean;
function PerfilAByte(p: TPerfilKdf): Byte;

function DerivarClave(const pass: TBytes; const sal: TSal; out clave: TClave): TResultadoCifrado;
function DerivarClaveCon(perfil: TPerfilKdf; const pass: TBytes; const sal: TSal;
                         out clave: TClave): TResultadoCifrado;

function Cifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                out salida: TBytes): TResultadoCifrado;
function Descifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                   out salida: TBytes): TResultadoCifrado;
{ Lo mismo sobre datos[ini..]: el contenedor descifra despues de su prefijo sin
  copiar el archivo entero. ini fuera de [0, Length] es error de programa. }
function Descifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                   ini: SizeInt; out salida: TBytes): TResultadoCifrado;

{ Expuestas para las pruebas del esquema (nonce distinto por trozo). }
function NonceDe(const base: TNonce; i: QWord): TNonce;

implementation

function TResultadoCifrado.Ok: Boolean;
begin Result := err = ecNinguno; end;

function TResultadoCifrado.Texto: string;
begin
  case err of
    ecNinguno:         Result := 'Ninguno';
    ecClaveIncorrecta: Result := 'ClaveIncorrecta';
    ecTrozoAlterado:   Result := 'TrozoAlterado(' + IntToStr(valor) + ')';
    ecTruncado:        Result := 'Truncado';
    ecFormato:         Result := 'Formato';
  end;
end;

function RC(e: TErrorCifrado; v: QWord = 0): TResultadoCifrado;
begin Result.err := e; Result.valor := v; end;

function PerfilDeByte(b: Byte; out perfil: TPerfilKdf): Boolean;
begin
  perfil := pkV1;
  Result := b = 0;
end;

function PerfilAByte(p: TPerfilKdf): Byte;
begin
  case p of pkV1: Result := 0; end;
end;

function DerivarClave(const pass: TBytes; const sal: TSal; out clave: TClave): TResultadoCifrado;
begin
  Result := DerivarClaveCon(pkV1, pass, sal, clave);
end;

function DerivarClaveCon(perfil: TPerfilKdf; const pass: TBytes; const sal: TSal;
                         out clave: TClave): TResultadoCifrado;
var s: TBytes; m, t, p: LongWord;
begin
  case perfil of pkV1: begin m := 64 * 1024; t := 3; p := 1; end; end;
  s := nil; SetLength(s, TAM_SAL); Move(sal[0], s[0], TAM_SAL);
  if Argon2id(pass, s, m, t, p, clave) then Result := RC(ecNinguno)
  else Result := RC(ecFormato);
end;

{ Nonce del trozo i: la base con el contador mezclado en los ultimos 8 bytes.
  Nunca se repite dentro de un archivo, que es la propiedad que hace falta. }
function NonceDe(const base: TNonce; i: QWord): TNonce;
var k: Integer;
begin
  Result := base;
  for k := 0 to 7 do
    Result[TAM_NONCE - 8 + k] := Result[TAM_NONCE - 8 + k] xor Byte((i shr (8 * k)) and $FF);
end;

type TAad = array[0..8] of Byte;
{ AAD del trozo: numero y marca de ultimo. Ata el trozo a su posicion y al
  final del archivo. }
function AadDe(i: QWord; ultimo: Boolean): TAad;
var k: Integer;
begin
  for k := 0 to 7 do Result[k] := Byte((i shr (8 * k)) and $FF);
  Result[8] := Ord(ultimo);
end;

function Cifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                out salida: TBytes): TResultadoCifrado;
var
  total, ini, fin, p: Int64;
  i: SizeInt;   { no Int64: en i386 no es ordinal y no sirve de variable de for }
  ct: TBytes;
  largo: LongWord;
  k: Integer;
begin
  { ceil(len / TAM_TROZO), y al menos 1: un archivo vacio es UN trozo vacio,
    asi la marca de ultimo existe siempre. }
  total := (Int64(Length(datos)) + TAM_TROZO - 1) div TAM_TROZO;
  if total < 1 then total := 1;
  salida := nil;
  SetLength(salida, Int64(Length(datos)) + total * (4 + TAM_TAG));
  p := 0;
  for i := 0 to total - 1 do begin
    ini := Int64(i) * TAM_TROZO;
    fin := ini + TAM_TROZO; if fin > Length(datos) then fin := Length(datos);
    ct := AeadLock(clave, NonceDe(nonceBase, i), AadDe(i, i + 1 = total), datos, ini, fin - ini);
    largo := Length(ct);
    for k := 0 to 3 do salida[p + k] := Byte((largo shr (8 * k)) and $FF);
    Inc(p, 4);
    Move(ct[0], salida[p], Length(ct)); Inc(p, Length(ct));
  end;
  if p <> Length(salida) then raise Exception.CreateFmt('Cifrar: escribi %d de %d', [p, Length(salida)]);
  Result := RC(ecNinguno);
end;

function Descifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                   out salida: TBytes): TResultadoCifrado;
begin
  Result := Descifrar(clave, nonceBase, datos, 0, salida);
end;

function Descifrar(const clave: TClave; const nonceBase: TNonce; const datos: TBytes;
                   ini: SizeInt; out salida: TBytes): TResultadoCifrado;
var
  p, largo, n: Int64;
  i: QWord;
  viElUltimo: Boolean;
  pt: TBytes;
  nn: TNonce;
begin
  { El claro nunca es mas largo que el cifrado: se reserva una vez y se recorta
    al final. Crecer de a un trozo (SetLength(salida, n + Length(pt)) en el
    lazo) copiaba todo lo acumulado en cada trozo: 64 MiB tardaban 20 s. }
  if (ini < 0) or (ini > Length(datos)) then
    raise ERangeError.CreateFmt('Descifrar: inicio %d fuera de [0, %d]', [ini, Length(datos)]);
  salida := nil; SetLength(salida, Length(datos) - ini); n := 0;
  p := ini; i := 0; viElUltimo := False;
  while p < Length(datos) do begin
    if p + 4 > Length(datos) then begin salida := nil; Exit(RC(ecFormato)); end;
    largo := Int64(datos[p]) or (Int64(datos[p + 1]) shl 8) or (Int64(datos[p + 2]) shl 16)
             or (Int64(datos[p + 3]) shl 24);
    Inc(p, 4);
    if (largo < TAM_TAG) or (p + largo > Length(datos)) then begin salida := nil; Exit(RC(ecFormato)); end;
    { Se prueba primero como trozo intermedio y despues como ultimo: el AAD los
      distingue, asi que solo uno de los dos puede autenticar. }
    nn := NonceDe(nonceBase, i);
    if not AeadUnlock(clave, nn, AadDe(i, False), datos, p, largo, pt) then begin
      if AeadUnlock(clave, nn, AadDe(i, True), datos, p, largo, pt) then viElUltimo := True
      else begin salida := nil; Exit(RC(ecTrozoAlterado, i)); end;
    end;
    if Length(pt) > 0 then Move(pt[0], salida[n], Length(pt));
    n := n + Length(pt);
    Inc(p, largo);
    Inc(i);
  end;
  { Sin esto, cortar el archivo por un limite de trozo pasaria inadvertido:
    todos los trozos que quedan autentican perfecto. }
  if not viElUltimo then begin salida := nil; Exit(RC(ecTruncado)); end;
  SetLength(salida, n);
  Result := RC(ecNinguno);
end;

end.
