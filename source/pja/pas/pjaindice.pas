{ Cabecera e indice del contenedor. Layout en doc/FORMATO.md.
  Port de pjacore/src/indice.rs.

  Todo lo de aca corre ANTES de que un byte llegue al codec: es el filtro donde
  se rechaza una bomba sin haber decodificado nada.

  El orden de los chequeos es el mismo que en Rust, porque de el sale QUE error
  se reporta, y la comparacion diferencial exige el mismo. Las sumas se
  chequean a mano, sin usar la excepcion de $Q+ como control de flujo: el
  resultado tiene que ser el mismo "Desborde" que devuelve el Rust. }
unit pjaindice;

{$I pja.inc}
{$ifopt R-}{$fatal pjaindice: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjaindice: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils, pjalimites, pjanombres, pjacripto;

const
  MAGIA: array[0..3] of Byte = (Ord('P'), Ord('J'), Ord('A'), $01);
  VERSION = 1;

  FLAG_CIFRADO = 1 shl 0;
  FLAG_RUTAS   = 1 shl 1;
  FLAG_SOLIDO  = 1 shl 2;
  FLAGS_CONOCIDOS = FLAG_CIFRADO or FLAG_RUTAS or FLAG_SOLIDO;

  { magia(4) + version(1) + flags(1) + kdf(1) + reservado(1) + tam_indice(4) + hash_indice(16) }
  TAM_CABECERA = 28;

  { Perfiles de derivacion de clave conocidos. Hoy uno solo: 0 = Argon2id
    64 MiB, t=3, p=1. Vive aca mientras cifrado no este portado. }
  PERFIL_KDF_V1 = 0;

type
  TErrorIndice = (
    eNinguno,
    eNoEsContenedor, eVersionFutura, eFlagDesconocido, eReservadoNoCero,
    eArchivoCorto, eIndiceNoEntra, eDemasiadosMiembros, eCountImposible,
    eNombreInvalido, eNombreDuplicado, ePayloadFueraDeRango, eSumaNoCuadra,
    eRatioExcedido, ePresupuestoExcedido, eDesborde, eIndiceTruncado,
    eIndiceAlterado, ePerfilKdfDesconocido);

  TResultado = record
    err: TErrorIndice;
    valor: QWord;            { el dato del error: version, count, indice, perfil }
    function Ok: Boolean;
    { Mismo texto que el Debug de Rust: "SumaNoCuadra", "VersionFutura(99)"... }
    function Texto: string;
  end;

  TMiembro = record
    nombre: TBytes;
    tam_orig: QWord;
    tam_payload: QWord;
    hash: THash16;
    m_flags: Byte;
  end;
  TMiembros = array of TMiembro;

  TContenedor = record
    flags: Byte;
    miembros: TMiembros;
  end;

{ Hash de la cabecera y el indice, truncado a 128 bits. Cubre los dos a
  proposito: un hash que solo cubriera el indice deja `flags` sin proteger, y
  ese byte decide cifrado, rutas y modo solido. Se saltea cab[12..28], que es el
  hash mismo. }
function HashCabeceraIndice(const datos: TBytes; idxIni, idxLen: SizeInt): THash16;

function LeerCabecera(const datos: TBytes; out flags: Byte; out tamIndice: LongWord;
                      out hashDecl: THash16): TResultado;
function LeerIndice(const datos: TBytes; out c: TContenedor): TResultado;
{ Los seis limites mas los nombres. Aparte para poder probarlo solo. }
function Validar(const ms: TMiembros; flags: Byte; tamArchivo, tamIndice: QWord): TResultado;

implementation

const
  NOMBRES_ERROR: array[TErrorIndice] of string = (
    'Ninguno',
    'NoEsContenedor', 'VersionFutura', 'FlagDesconocido', 'ReservadoNoCero',
    'ArchivoCorto', 'IndiceNoEntra', 'DemasiadosMiembros', 'CountImposible',
    'NombreInvalido', 'NombreDuplicado', 'PayloadFueraDeRango', 'SumaNoCuadra',
    'RatioExcedido', 'PresupuestoExcedido', 'Desborde', 'IndiceTruncado',
    'IndiceAlterado', 'PerfilKdfDesconocido');

function TResultado.Ok: Boolean;
begin
  Result := err = eNinguno;
end;

function TResultado.Texto: string;
begin
  case err of
    eVersionFutura, eDemasiadosMiembros, eNombreInvalido, eNombreDuplicado,
    ePayloadFueraDeRango, ePerfilKdfDesconocido:
      Result := NOMBRES_ERROR[err] + '(' + IntToStr(valor) + ')';
  else
    Result := NOMBRES_ERROR[err];
  end;
end;

function R(e: TErrorIndice; v: QWord = 0): TResultado;
begin
  Result.err := e; Result.valor := v;
end;

function U16(const b: TBytes; i: SizeInt): LongWord;
begin
  Result := LongWord(b[i]) or (LongWord(b[i + 1]) shl 8);
end;

function U32(const b: TBytes; i: SizeInt): LongWord;
begin
  Result := LongWord(b[i]) or (LongWord(b[i + 1]) shl 8) or
            (LongWord(b[i + 2]) shl 16) or (LongWord(b[i + 3]) shl 24);
end;

function U64(const b: TBytes; i: SizeInt): QWord;
begin
  Result := QWord(U32(b, i)) or (QWord(U32(b, i + 4)) shl 32);
end;

{ ---- sumas chequeadas: devuelven False si desbordaria ---- }
function SumarQ(a, b: QWord; out s: QWord): Boolean;
begin
  if a > High(QWord) - b then Exit(False);
  s := a + b; Result := True;
end;

function MultiplicarQ(a, b: QWord; out s: QWord): Boolean;
begin
  if (b <> 0) and (a > High(QWord) div b) then Exit(False);
  s := a * b; Result := True;
end;

function HashCabeceraIndice(const datos: TBytes; idxIni, idxLen: SizeInt): THash16;
begin
  { magia, version, flags, kdf, reservado, tam_indice = datos[0..12), y el indice }
  Result := Blake3_128(datos, 0, 12, datos, idxIni, idxLen);
end;

function LeerCabecera(const datos: TBytes; out flags: Byte; out tamIndice: LongWord;
                      out hashDecl: THash16): TResultado;
var
  i: Integer;
  ver: Byte;   { NO `version`: Pascal no distingue mayusculas, y una variable
                 `version` tapa a la constante VERSION. Pasaba: la comparacion
                 quedaba `version > version`, siempre falsa, y ninguna version
                 futura se rechazaba. Sin advertencia del compilador. Lo agarro
                 la prueba diferencial: 63 de 63 VersionFutura del Rust. }
begin
  flags := 0; tamIndice := 0; FillChar(hashDecl, SizeOf(hashDecl), 0);
  if Length(datos) < TAM_CABECERA then Exit(R(eArchivoCorto));
  for i := 0 to 3 do
    if datos[i] <> MAGIA[i] then Exit(R(eNoEsContenedor));
  ver := datos[4];
  if ver > VERSION then Exit(R(eVersionFutura, ver));
  flags := datos[5];
  if (flags and (not FLAGS_CONOCIDOS) and $FF) <> 0 then Exit(R(eFlagDesconocido));
  if datos[7] <> 0 then Exit(R(eReservadoNoCero));
  { El perfil de KDF solo tiene sentido cifrando, y solo puede valer lo que esta
    version conoce: derivar con parametros equivocados daria una clave
    equivocada, y eso se veria como "contrasena incorrecta" sobre un archivo y
    una contrasena que estaban bien. }
  if (flags and FLAG_CIFRADO) = 0 then begin
    if datos[6] <> 0 then Exit(R(eReservadoNoCero));
  end else if datos[6] <> PERFIL_KDF_V1 then
    Exit(R(ePerfilKdfDesconocido, datos[6]));
  tamIndice := U32(datos, 8);
  Move(datos[12], hashDecl[0], 16);
  { El indice tiene que entrar en el archivo, cabecera incluida. }
  if QWord(tamIndice) > QWord(Length(datos)) - TAM_CABECERA then Exit(R(eIndiceNoEntra));
  Result := R(eNinguno);
end;

function Validar(const ms: TMiembros; flags: Byte; tamArchivo, tamIndice: QWord): TResultado;
var
  i, dup: SizeInt;
  sumaPayload, sumaOrig, total, techo: QWord;
  v: TVeredicto;
  noms: TListaNombres;
begin
  sumaPayload := 0; sumaOrig := 0;
  noms := nil; SetLength(noms, Length(ms));
  for i := 0 to High(ms) do noms[i] := ms[i].nombre;   { refcount, no copia }
  dup := PrimerDuplicado(noms);
  for i := 0 to High(ms) do begin
    { Limite 6: ningun payload vacio ni imposible. }
    if (ms[i].tam_payload < MIN_PAYLOAD) or (ms[i].tam_payload > tamArchivo) then
      Exit(R(ePayloadFueraDeRango, i));
    { Sumar con deteccion de desborde: sumar y despues comparar es el bug. }
    if not SumarQ(sumaPayload, ms[i].tam_payload, sumaPayload) then Exit(R(eDesborde));
    if not SumarQ(sumaOrig, ms[i].tam_orig, sumaOrig) then Exit(R(eDesborde));

    if (flags and FLAG_RUTAS) <> 0 then v := Ruta(ms[i].nombre) else v := Plano(ms[i].nombre);
    if v.tipo = vRechazo then Exit(R(eNombreInvalido, i));

    { Duplicados: se rechazan al abrir, no al extraer. }
    if i = dup then Exit(R(eNombreDuplicado, i));
  end;

  { Limite 3: la suma tiene que dar el archivo exacto. }
  if not SumarQ(sumaPayload, tamIndice, total) then Exit(R(eDesborde));
  if not SumarQ(total, TAM_CABECERA, total) then Exit(R(eDesborde));
  if total <> tamArchivo then Exit(R(eSumaNoCuadra));
  { Limite 4: el ratio, que escala solo. }
  if not MultiplicarQ(tamArchivo, MAX_RATIO_EXPANSION, techo) then Exit(R(eDesborde));
  if sumaOrig > techo then Exit(R(eRatioExcedido));
  { Limite 5: presupuesto absoluto. }
  if (PRESUPUESTO_POR_DEFECTO > 0) and (sumaOrig > PRESUPUESTO_POR_DEFECTO) then
    Exit(R(ePresupuestoExcedido));
  Result := R(eNinguno);
end;

function LeerIndice(const datos: TBytes; out c: TContenedor): TResultado;
var
  flags: Byte;
  tamIndice, count, nlen, k: LongWord;
  hashDecl, h: THash16;
  ini, fin, p: Int64;       { Int64: p + nlen + 33 no puede desbordar ni en 32 bits }
  ms: TMiembros;
  res: TResultado;
  j: Integer;
  iguales: Boolean;
begin
  c.flags := 0; c.miembros := nil;
  res := LeerCabecera(datos, flags, tamIndice, hashDecl);
  if not res.Ok then Exit(res);
  ini := TAM_CABECERA;
  fin := ini + tamIndice;

  { El hash del indice se verifica ANTES de deserializar nada. }
  h := HashCabeceraIndice(datos, TAM_CABECERA, tamIndice);
  iguales := True;
  for j := 0 to 15 do if h[j] <> hashDecl[j] then iguales := False;
  if not iguales then Exit(R(eIndiceAlterado));

  if tamIndice < 4 then Exit(R(eIndiceTruncado));
  count := U32(datos, ini);

  { Limite 1: tope absoluto, antes de reservar nada. }
  if count > MAX_MIEMBROS then Exit(R(eDemasiadosMiembros, count));
  { Limite 2: el indice minimo tiene que caber en el archivo real. }
  if QWord(count) * MIN_BYTES_ENTRADA > QWord(Length(datos)) then Exit(R(eCountImposible));

  SetLength(ms, count);
  p := ini + 4;
  if count > 0 then
    for k := 0 to count - 1 do begin
      if p + 2 > fin then Exit(R(eIndiceTruncado));
      nlen := U16(datos, p); p := p + 2;
      if p + nlen + 8 + 8 + 16 + 1 > fin then Exit(R(eIndiceTruncado));
      ms[k].nombre := Copy(datos, p, nlen); p := p + nlen;
      ms[k].tam_orig := U64(datos, p); p := p + 8;
      ms[k].tam_payload := U64(datos, p); p := p + 8;
      Move(datos[p], ms[k].hash[0], 16); p := p + 16;
      ms[k].m_flags := datos[p]; p := p + 1;
    end;

  res := Validar(ms, flags, Length(datos), tamIndice);
  if not res.Ok then Exit(res);
  c.flags := flags; c.miembros := ms;
  Result := R(eNinguno);
end;

end.
