{ Validacion de nombres. La politica vive en doc/POLITICA.md; aca se aplica.
  Port de pjacore/src/nombres.rs.

  Dos niveles, y la diferencia importa: lo que es PELIGRO se rechaza al crear;
  lo que es INCOMPATIBILIDAD CON WINDOWS se avisa al crear y se rechaza al
  extraer, porque son nombres legales en Linux y rechazarlos al crear le
  impediria a alguien archivar un archivo suyo valido.

  Todo trabaja sobre `TBytes`, nunca sobre punteros ni strings: $R+ no
  controla indices de puntero, y los AnsiString de FPC pueden transcodificar
  en silencio al asignarse entre paginas de codigos distintas. Un nombre es
  una secuencia de bytes y se trata como tal. }
unit pjanombres;

{$I pja.inc}
{$ifopt R-}{$fatal pjanombres: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjanombres: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses
  SysUtils, pjalimites;

type
  { Mismo orden que el enum de Rust: el orden no importa para la logica, pero
    sí para que la comparacion diferencial imprima lo mismo de los dos lados. }
  TMotivo = (
    mVacio,
    mByteDeControl,
    mSeparadorEnComponente,
    mComponentePadre,
    mRutaAbsoluta,
    mLetraDeUnidad,
    mDosPuntos,
    mUtf8Invalido,
    mComponenteMuyLargo,
    mRutaMuyLarga,
    mMuyProfunda,
    mNombreReservado,
    mTerminaEnPuntoOEspacio,
    mCaracterIlegalEnWindows
  );

  TTipoVeredicto = (vOk, vRechazo, vSoloWindows);

  TVeredicto = record
    tipo: TTipoVeredicto;
    motivo: TMotivo;          { sin significado cuando tipo = vOk }
    class function Ok: TVeredicto; static;
    class function Rechazo(m: TMotivo): TVeredicto; static;
    class function SoloWindows(m: TMotivo): TVeredicto; static;
    function Igual(const o: TVeredicto): Boolean;
    { Mismo texto que el Debug de Rust: "Ok", "Rechazo(Vacio)", ... }
    function Texto: string;
  end;

{ Un solo componente, sin rutas. }
function Plano(const nombre: TBytes): TVeredicto;
{ Ruta relativa en modo --keep-structure. }
function Ruta(const r: TBytes): TVeredicto;
{ UTF-8 estricto, identico a core::str::from_utf8 de Rust. Publico porque se
  prueba aparte: es el punto donde un port diverge sin que se note. }
function Utf8Valido(const b: TBytes): Boolean;

implementation

const
  NOMBRES_MOTIVO: array[TMotivo] of string = (
    'Vacio', 'ByteDeControl', 'SeparadorEnComponente', 'ComponentePadre',
    'RutaAbsoluta', 'LetraDeUnidad', 'DosPuntos', 'Utf8Invalido',
    'ComponenteMuyLargo', 'RutaMuyLarga', 'MuyProfunda', 'NombreReservado',
    'TerminaEnPuntoOEspacio', 'CaracterIlegalEnWindows');

  RESERVADOS: array[0..21] of string = (
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9');

class function TVeredicto.Ok: TVeredicto;
begin
  Result.tipo := vOk; Result.motivo := mVacio;
end;

class function TVeredicto.Rechazo(m: TMotivo): TVeredicto;
begin
  Result.tipo := vRechazo; Result.motivo := m;
end;

class function TVeredicto.SoloWindows(m: TMotivo): TVeredicto;
begin
  Result.tipo := vSoloWindows; Result.motivo := m;
end;

function TVeredicto.Igual(const o: TVeredicto): Boolean;
begin
  Result := (tipo = o.tipo) and ((tipo = vOk) or (motivo = o.motivo));
end;

function TVeredicto.Texto: string;
begin
  case tipo of
    vOk:          Result := 'Ok';
    vRechazo:     Result := 'Rechazo(' + NOMBRES_MOTIVO[motivo] + ')';
    vSoloWindows: Result := 'SoloWindows(' + NOMBRES_MOTIVO[motivo] + ')';
  end;
end;

{ Tabla 3-7 de Unicode ("Well-Formed UTF-8 Byte Sequences"), que es lo que
  aplica core::str::from_utf8. Rechaza secuencias sobrelargas (C0, C1, E0 80,
  F0 80), sustitutos UTF-16 (ED A0..BF), valores > U+10FFFF (F4 90.., F5..FF),
  continuaciones sueltas y secuencias truncadas. }
function Utf8Valido(const b: TBytes): Boolean;
var
  i, n: SizeInt;
  c: Byte;

  function Cont(k: SizeInt; lo, hi: Byte): Boolean;
  begin
    Result := (k <= High(b)) and (b[k] >= lo) and (b[k] <= hi);
  end;

begin
  Result := False;
  n := Length(b);
  i := 0;
  while i < n do
  begin
    c := b[i];
    if c <= $7F then
      Inc(i)
    else if (c >= $C2) and (c <= $DF) then
    begin
      if not Cont(i + 1, $80, $BF) then Exit;
      Inc(i, 2);
    end
    else if c = $E0 then
    begin
      if not (Cont(i + 1, $A0, $BF) and Cont(i + 2, $80, $BF)) then Exit;
      Inc(i, 3);
    end
    else if ((c >= $E1) and (c <= $EC)) or (c = $EE) or (c = $EF) then
    begin
      if not (Cont(i + 1, $80, $BF) and Cont(i + 2, $80, $BF)) then Exit;
      Inc(i, 3);
    end
    else if c = $ED then
    begin
      if not (Cont(i + 1, $80, $9F) and Cont(i + 2, $80, $BF)) then Exit;
      Inc(i, 3);
    end
    else if c = $F0 then
    begin
      if not (Cont(i + 1, $90, $BF) and Cont(i + 2, $80, $BF) and Cont(i + 3, $80, $BF)) then Exit;
      Inc(i, 4);
    end
    else if (c >= $F1) and (c <= $F3) then
    begin
      if not (Cont(i + 1, $80, $BF) and Cont(i + 2, $80, $BF) and Cont(i + 3, $80, $BF)) then Exit;
      Inc(i, 4);
    end
    else if c = $F4 then
    begin
      if not (Cont(i + 1, $80, $8F) and Cont(i + 2, $80, $BF) and Cont(i + 3, $80, $BF)) then Exit;
      Inc(i, 4);
    end
    else
      Exit;  { 80..C1 como primer byte, F5..FF }
  end;
  Result := True;
end;

function EsReservado(const c: TBytes; largoBase: SizeInt): Boolean;
var
  k, j: SizeInt;
  b: Byte;
  r: string;
begin
  Result := False;
  for k := Low(RESERVADOS) to High(RESERVADOS) do
  begin
    r := RESERVADOS[k];
    if Length(r) <> largoBase then Continue;
    Result := True;
    for j := 0 to largoBase - 1 do
    begin
      b := c[j];
      { to_ascii_uppercase: solo a..z. No usar UpCase/UpperCase de la RTL, que
        dependen de la pagina de codigos. }
      if (b >= Ord('a')) and (b <= Ord('z')) then Dec(b, 32);
      if b <> Ord(r[j + 1]) then begin Result := False; Break; end;
    end;
    if Result then Exit;
  end;
end;

{ Un componente suelto (sin separadores). El orden de los chequeos es el mismo
  que en Rust, porque de el sale QUE motivo se reporta. }
function Componente(const c: TBytes): TVeredicto;
var
  i, base: SizeInt;
  b, ultimo: Byte;
begin
  if Length(c) = 0 then Exit(TVeredicto.Rechazo(mVacio));
  if Length(c) > MAX_BYTES_COMPONENTE then Exit(TVeredicto.Rechazo(mComponenteMuyLargo));
  if (Length(c) = 1) and (c[0] = Ord('.')) then Exit(TVeredicto.Rechazo(mComponentePadre));
  if (Length(c) = 2) and (c[0] = Ord('.')) and (c[1] = Ord('.')) then Exit(TVeredicto.Rechazo(mComponentePadre));

  { Byte por byte: el PRIMER byte problematico decide el motivo, igual que el
    bucle de Rust. No es lo mismo que "primero todos los de control, despues
    todos los ':'". }
  for i := 0 to High(c) do
  begin
    b := c[i];
    if (b < $20) or (b = $7F) then Exit(TVeredicto.Rechazo(mByteDeControl));
    if (b = Ord('/')) or (b = Ord('\')) then Exit(TVeredicto.Rechazo(mSeparadorEnComponente));
    if b = Ord(':') then Exit(TVeredicto.Rechazo(mDosPuntos));
  end;
  if not Utf8Valido(c) then Exit(TVeredicto.Rechazo(mUtf8Invalido));

  { A partir de aca: legal en Linux, problematico en Windows. }
  ultimo := c[High(c)];
  if (ultimo = Ord('.')) or (ultimo = Ord(' ')) then
    Exit(TVeredicto.SoloWindows(mTerminaEnPuntoOEspacio));
  for i := 0 to High(c) do
    if c[i] in [Ord('*'), Ord('?'), Ord('<'), Ord('>'), Ord('|'), Ord('"')] then
      Exit(TVeredicto.SoloWindows(mCaracterIlegalEnWindows));

  { Reservado con o sin extension, sin distinguir mayusculas. }
  base := Length(c);
  for i := 0 to High(c) do
    if c[i] = Ord('.') then begin base := i; Break; end;
  if (base <= 4) and EsReservado(c, base) then
    Exit(TVeredicto.SoloWindows(mNombreReservado));

  Result := TVeredicto.Ok;
end;

function Plano(const nombre: TBytes): TVeredicto;
begin
  Result := Componente(nombre);
end;

function Ruta(const r: TBytes): TVeredicto;
var
  i, ini, partes: SizeInt;
  v: TVeredicto;
  hayAviso: Boolean;
  aviso: TMotivo;
begin
  if Length(r) = 0 then Exit(TVeredicto.Rechazo(mVacio));
  if Length(r) > MAX_BYTES_RUTA then Exit(TVeredicto.Rechazo(mRutaMuyLarga));
  if r[0] = Ord('/') then Exit(TVeredicto.Rechazo(mRutaAbsoluta));
  if (Length(r) >= 2) and (r[1] = Ord(':')) then Exit(TVeredicto.Rechazo(mLetraDeUnidad));
  for i := 0 to High(r) do
    if r[i] = Ord('\') then Exit(TVeredicto.Rechazo(mSeparadorEnComponente));

  { La profundidad se cuenta ANTES de validar los componentes, como en Rust:
    una ruta de 34 niveles se rechaza por profunda aunque traiga un '..'. }
  partes := 1;
  for i := 0 to High(r) do
    if r[i] = Ord('/') then Inc(partes);
  if partes > MAX_PROFUNDIDAD then Exit(TVeredicto.Rechazo(mMuyProfunda));

  hayAviso := False; aviso := mVacio;
  ini := 0;
  for i := 0 to Length(r) do          { i = Length(r) cierra el ultimo tramo }
    if (i = Length(r)) or (r[i] = Ord('/')) then
    begin
      v := Componente(Copy(r, ini, i - ini));
      case v.tipo of
        vRechazo: Exit(v);
        vSoloWindows: if not hayAviso then begin hayAviso := True; aviso := v.motivo; end;
        vOk: ;
      end;
      ini := i + 1;
    end;

  if hayAviso then Result := TVeredicto.SoloWindows(aviso) else Result := TVeredicto.Ok;
end;

end.
