{ Serializa el contenedor. Es el inverso exacto de pjaindice.LeerIndice.
  Port de pjacore/src/escritor.rs.

  OJO, heredado del Rust y todavia sin decidir: el Rust dice "valida antes de
  escribir: un contenedor que no se puede leer no se produce", y NO es cierto.
  Chequea nombres, duplicados y el largo minimo, pero no el ratio (limite 4) ni
  el presupuesto (limite 5) que exige el lector, ni que los flags sean
  conocidos. Medido: un backup legitimo con originales de 8 GiB + 1 se escribe
  y despues LeerIndice lo rechaza con PresupuestoExcedido. El port reproduce el
  comportamiento del Rust tal cual, para que la comparacion diferencial sea
  limpia; la correccion se aplica a los dos juntos cuando se decida. }
unit pjaescritor;

{$I pja.inc}
{$ifopt R-}{$fatal pjaescritor: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjaescritor: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils, pjalimites, pjanombres, pjacripto, pjaindice;

type
  { Mismo orden que el enum de Rust. LargoDeclaradoNoCoincide y Desborde estan
    declarados alla y NUNCA se producen; se conservan para que los nombres
    coincidan. }
  TErrorEscritura = (ewNinguno, ewNombreInvalido, ewNombreDuplicado, ewDemasiadosMiembros,
                     ewPayloadFueraDeRango, ewLargoDeclaradoNoCoincide, ewDesborde);

  TResultadoEscritura = record
    err: TErrorEscritura;
    valor: SizeInt;
    function Ok: Boolean;
    function Texto: string;     { mismo texto que el Debug de Rust }
  end;

  TEntrada = record
    nombre: TBytes;
    tam_orig: QWord;     { tamano del JPEG original, para el rechazo temprano al descomprimir }
    payload: TBytes;     { el .pjg ya comprimido }
    hash: THash16;
  end;
  TEntradas = array of TEntrada;

  TAviso = record
    indice: SizeInt;
    motivo: TMotivo;
  end;
  TAvisos = array of TAviso;

  TDesplazamientos = array of QWord;

{ Miembros con aviso de incompatibilidad con Windows NO impiden escribir: son
  nombres legales en Linux. }
function Escribir(const es: TEntradas; flags: Byte; out bytes: TBytes; out avisos: TAvisos): TResultadoEscritura;
{ Donde arranca el payload de cada miembro, en orden. }
function Desplazamientos(const c: TContenedor; tamIndice: QWord): TDesplazamientos;

implementation

const
  NOMBRES_ERROR: array[TErrorEscritura] of string = ('Ninguno', 'NombreInvalido', 'NombreDuplicado',
    'DemasiadosMiembros', 'PayloadFueraDeRango', 'LargoDeclaradoNoCoincide', 'Desborde');

function TResultadoEscritura.Ok: Boolean;
begin Result := err = ewNinguno; end;

function TResultadoEscritura.Texto: string;
begin
  case err of
    ewNombreInvalido, ewNombreDuplicado, ewPayloadFueraDeRango, ewLargoDeclaradoNoCoincide:
      Result := NOMBRES_ERROR[err] + '(' + IntToStr(valor) + ')';
  else
    Result := NOMBRES_ERROR[err];
  end;
end;

function RE(e: TErrorEscritura; v: SizeInt = 0): TResultadoEscritura;
begin Result.err := e; Result.valor := v; end;

procedure Pon16(var b: TBytes; var p: SizeInt; v: LongWord);
begin b[p] := v and $FF; b[p + 1] := (v shr 8) and $FF; Inc(p, 2); end;
procedure Pon32(var b: TBytes; var p: SizeInt; v: LongWord);
var k: Integer; begin for k := 0 to 3 do b[p + k] := (v shr (8 * k)) and $FF; Inc(p, 4); end;
procedure Pon64(var b: TBytes; var p: SizeInt; v: QWord);
var k: Integer; begin for k := 0 to 7 do b[p + k] := (v shr (8 * k)) and $FF; Inc(p, 8); end;
procedure PonBytes(var b: TBytes; var p: SizeInt; const x: TBytes);
begin if Length(x) > 0 then Move(x[0], b[p], Length(x)); Inc(p, Length(x)); end;

function Escribir(const es: TEntradas; flags: Byte; out bytes: TBytes; out avisos: TAvisos): TResultadoEscritura;
var
  i, dup, p, na: SizeInt;
  v: TVeredicto;
  noms: TListaNombres;
  tamIdx, total: Int64;
  h: THash16;
begin
  bytes := nil; avisos := nil;
  if Int64(Length(es)) > MAX_MIEMBROS then Exit(RE(ewDemasiadosMiembros));

  noms := nil; SetLength(noms, Length(es));
  for i := 0 to High(es) do noms[i] := es[i].nombre;
  dup := PrimerDuplicado(noms);

  na := 0; SetLength(avisos, Length(es));
  for i := 0 to High(es) do begin
    if (flags and FLAG_RUTAS) <> 0 then v := Ruta(es[i].nombre) else v := Plano(es[i].nombre);
    case v.tipo of
      vRechazo: begin avisos := nil; Exit(RE(ewNombreInvalido, i)); end;
      vSoloWindows: begin avisos[na].indice := i; avisos[na].motivo := v.motivo; Inc(na); end;
      vOk: ;
    end;
    if Length(es[i].payload) < MIN_PAYLOAD then begin avisos := nil; Exit(RE(ewPayloadFueraDeRango, i)); end;
    if i = dup then begin avisos := nil; Exit(RE(ewNombreDuplicado, i)); end;
  end;
  SetLength(avisos, na);

  { Tamano exacto de una vez, sin crecer el arreglo de a pedazos. Int64: la
    suma no puede desbordar antes de comparar. Un contenedor que no entra en la
    memoria de este proceso no se puede armar entero -- el escritor todavia no
    es streaming (pendiente, y peor en 32 bits); el Rust abortaria por falta de
    memoria, aca se devuelve Desborde. }
  tamIdx := 4;
  for i := 0 to High(es) do tamIdx := tamIdx + 2 + Length(es[i].nombre) + 8 + 8 + 16 + 1;
  total := TAM_CABECERA + tamIdx;
  for i := 0 to High(es) do total := total + Length(es[i].payload);
  if (total > High(SizeInt)) or (tamIdx > High(LongWord)) then begin avisos := nil; Exit(RE(ewDesborde)); end;

  SetLength(bytes, total);
  p := 0;
  PonBytes(bytes, p, TBytes.Create(MAGIA[0], MAGIA[1], MAGIA[2], MAGIA[3]));
  bytes[p] := VERSION; Inc(p);
  bytes[p] := flags; Inc(p);
  { kdf(1) + reservado(1): el perfil solo va cuando hay cifrado; sin cifrado ese
    byte tiene que ser cero y LeerCabecera lo exige. }
  if (flags and FLAG_CIFRADO) <> 0 then bytes[p] := PERFIL_KDF_V1 else bytes[p] := 0; Inc(p);
  bytes[p] := 0; Inc(p);
  Pon32(bytes, p, LongWord(tamIdx));
  FillChar(bytes[p], 16, 0); Inc(p, 16);          { hueco del hash }
  Pon32(bytes, p, Length(es));
  for i := 0 to High(es) do begin
    Pon16(bytes, p, Length(es[i].nombre));
    PonBytes(bytes, p, es[i].nombre);
    Pon64(bytes, p, es[i].tam_orig);
    Pon64(bytes, p, Length(es[i].payload));
    Move(es[i].hash[0], bytes[p], 16); Inc(p, 16);
    bytes[p] := 0; Inc(p);
  end;
  h := HashCabeceraIndice(bytes, TAM_CABECERA, SizeInt(tamIdx));
  Move(h[0], bytes[12], 16);
  for i := 0 to High(es) do PonBytes(bytes, p, es[i].payload);
  if p <> total then raise Exception.CreateFmt('escritor: escribi %d de %d bytes', [p, total]);
  Result := RE(ewNinguno);
end;

function Desplazamientos(const c: TContenedor; tamIndice: QWord): TDesplazamientos;
var i: SizeInt; p: QWord;
begin
  Result := nil; SetLength(Result, Length(c.miembros));
  p := TAM_CABECERA + tamIndice;
  for i := 0 to High(c.miembros) do begin Result[i] := p; p := p + c.miembros[i].tam_payload; end;
end;

end.
