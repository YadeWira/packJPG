{ El formato .pja: UN JPEG comprimido, con su tamano y su hash declarados y,
  si se pide, cifrado. Layout en doc/FORMATO.md.

  Lo que el .pja agrega sobre el .pjg y nada mas:
  - el hash BLAKE3-128 del JPEG original, para verificar la reconstruccion
    (un .pjg truncado o con un bit volteado puede decodificar a OTRO JPEG
    valido sin que nada lo note);
  - el tamano original, para rechazar una bomba antes de decodificar;
  - el cifrado autenticado, que se verifica antes de que un byte llegue al
    codec.

  El escritor y el lector validan con la MISMA funcion: lo que se escribe se
  puede leer, y lo que se rechaza al leer no se puede escribir. }
unit pjaformato;

{$I pja.inc}
{$ifopt R-}{$fatal pjaformato: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjaformato: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils, pjalimites, pjacripto, pjacifrado;

const
  MAGIA: array[0..3] of Byte = (Ord('P'), Ord('J'), Ord('A'), $01);
  { 1 fue el contenedor de varios archivos, descartado antes de publicarse. }
  VERSION = 2;

  FLAG_CIFRADO = 1 shl 0;
  FLAGS_CONOCIDOS = FLAG_CIFRADO;

  { magia(4) + version(1) + flags(1) + kdf(1) + reservado(1), siempre en claro }
  TAM_CABECERA = 8;
  { tam_orig(8) + hash(16) }
  TAM_DESCRIPTOR = 24;
  { sal(16) + nonce_base(24), en claro detras de la cabecera si hay cifrado }
  TAM_PREFIJO_CIFRADO = TAM_SAL + TAM_NONCE;

  { El byte que identifica al perfil V1 en la cabecera (ver pjacifrado). }
  PERFIL_KDF_V1 = 0;

type
  TErrorPja = (
    epNinguno,
    epArchivoCorto, epNoEsPja, epVersionFutura, epVersionVieja, epFlagDesconocido,
    epReservadoNoCero, epPerfilKdfDesconocido,
    epContrasenaFaltante, epContrasenaSobrante, epCifrado, epCabeceraAlterada,
    epPayloadFueraDeRango, epTamOrigInvalido, epRatioExcedido, epDesborde,
    { no hubo de donde sacar la sal y el nonce }
    epSinAleatorio);

  TResultadoPja = record
    err: TErrorPja;
    valor: QWord;                { version o perfil, segun el error }
    cifrado: TResultadoCifrado;  { con epCifrado }
    function Ok: Boolean;
    { "VersionFutura(3)", "Cifrado(TrozoAlterado(1))"... }
    function Texto: string;
  end;

  TPja = record
    cifrado: Boolean;
    tam_orig: QWord;    { del JPEG original }
    hash: THash16;      { BLAKE3-128 del JPEG original }
    payload: TBytes;    { el .pjg, ya en claro y autenticado si venia cifrado }
  end;

{ Lee solo los 8 bytes en claro: si es un .pja y si pide contrasena. Lo que
  necesita un programa para decidir si preguntarla, sin derivar nada. }
function Examinar(const datos: TBytes; out cifrado: Boolean): TResultadoPja;

{ Las reglas del descriptor, compartidas por el lector y el escritor. }
function ValidarDescriptor(tamOrig: QWord; tamPayload: QWord): TResultadoPja;

{ Sin contrasena, y con contrasena (vacia vale: es una contrasena). El orden es
  el de doc/FORMATO.md: cabecera, autenticar, descriptor; recien ahi el
  payload queda disponible para el codec. }
function Abrir(const datos: TBytes; out p: TPja): TResultadoPja; overload;
function Abrir(const datos: TBytes; const pass: TBytes; out p: TPja): TResultadoPja; overload;
{ Lo mismo con la clave ya derivada: para las pruebas, que abren miles de
  variantes de un mismo archivo y no pueden pagar Argon2id en cada una. La sal
  de la cabecera se ignora. }
function AbrirConClave(const datos: TBytes; const clave: TClave; out p: TPja): TResultadoPja;

{ Cuantos bytes ocupa el .pja de un payload de ese largo. -1 si no entra en
  SizeInt (32 bits). }
function LargoEscrito(tamPayload: Int64; cifrado: Boolean): Int64;

{ Sin cifrar. }
function Escribir(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                  out bytes: TBytes): TResultadoPja; overload;
{ Cifrado: deriva la clave con una sal y un nonce del sistema. }
function Escribir(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                  const pass: TBytes; out bytes: TBytes): TResultadoPja; overload;
{ Cifrado con sal y nonce dados: para las pruebas, que necesitan salidas fijas. }
function EscribirCon(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                     const pass: TBytes; const sal: TSal; const nonce: TNonce;
                     out bytes: TBytes): TResultadoPja;

implementation

const
  NOMBRES_ERROR: array[TErrorPja] of string = (
    'Ninguno',
    'ArchivoCorto', 'NoEsPja', 'VersionFutura', 'VersionVieja', 'FlagDesconocido',
    'ReservadoNoCero', 'PerfilKdfDesconocido',
    { 'ñ' en bytes UTF-8, para no depender de la codificacion del fuente }
    'Contrase'#$C3#$B1'aFaltante', 'Contrase'#$C3#$B1'aSobrante', 'Cifrado', 'CabeceraAlterada',
    'PayloadFueraDeRango', 'TamOrigInvalido', 'RatioExcedido', 'Desborde',
    'SinAleatorio');

function TResultadoPja.Ok: Boolean;
begin Result := err = epNinguno; end;

function TResultadoPja.Texto: string;
begin
  case err of
    epVersionFutura, epVersionVieja, epPerfilKdfDesconocido:
      Result := NOMBRES_ERROR[err] + '(' + IntToStr(valor) + ')';
    epCifrado: Result := NOMBRES_ERROR[err] + '(' + cifrado.Texto + ')';
  else
    Result := NOMBRES_ERROR[err];
  end;
end;

function R(e: TErrorPja; v: QWord = 0): TResultadoPja;
begin
  Result := Default(TResultadoPja);
  Result.err := e; Result.valor := v;
end;

function RCif(const c: TResultadoCifrado): TResultadoPja;
begin Result := R(epCifrado); Result.cifrado := c; end;

function U64(const b: TBytes; i: SizeInt): QWord;
var k: Integer;
begin
  Result := 0;
  for k := 7 downto 0 do Result := (Result shl 8) or b[i + k];
end;

procedure Pon64(var b: TBytes; i: SizeInt; v: QWord);
var k: Integer;
begin
  for k := 0 to 7 do b[i + k] := Byte((v shr (8 * k)) and $FF);
end;

{ ------------------------------------------------------------------------ }

function LeerCabecera(const datos: TBytes; out cifrado: Boolean): TResultadoPja;
var i: Integer; perfil: TPerfilKdf; ver, flags: Byte;
   { NO `version`: Pascal no distingue mayusculas, y una variable `version`
     tapa a la constante VERSION. Paso en el contenedor anterior: la
     comparacion quedaba `version > version`, siempre falsa. }
begin
  cifrado := False;
  if Length(datos) < TAM_CABECERA then Exit(R(epArchivoCorto));
  for i := 0 to 3 do
    if datos[i] <> MAGIA[i] then Exit(R(epNoEsPja));
  ver := datos[4];
  if ver > VERSION then Exit(R(epVersionFutura, ver));
  if ver < VERSION then Exit(R(epVersionVieja, ver));
  flags := datos[5];
  if (flags and (not FLAGS_CONOCIDOS) and $FF) <> 0 then Exit(R(epFlagDesconocido));
  if datos[7] <> 0 then Exit(R(epReservadoNoCero));
  cifrado := (flags and FLAG_CIFRADO) <> 0;
  { El perfil de KDF solo tiene sentido cifrando, y solo puede valer lo que esta
    version conoce: derivar con parametros equivocados daria una clave
    equivocada, y eso se veria como "contrasena incorrecta" sobre un archivo y
    una contrasena que estaban bien. }
  if not cifrado then begin
    if datos[6] <> 0 then Exit(R(epReservadoNoCero));
  end else if not PerfilDeByte(datos[6], perfil) then
    Exit(R(epPerfilKdfDesconocido, datos[6]));
  Result := R(epNinguno);
end;

function Examinar(const datos: TBytes; out cifrado: Boolean): TResultadoPja;
begin
  Result := LeerCabecera(datos, cifrado);
end;

function ValidarDescriptor(tamOrig: QWord; tamPayload: QWord): TResultadoPja;
begin
  if tamPayload < MIN_PAYLOAD then Exit(R(epPayloadFueraDeRango));
  { Un JPEG vacio no existe, y por encima de High(Int64) la frontera no lo
    puede devolver (pja_tam_orig es int64_t). }
  if (tamOrig = 0) or (tamOrig > QWord(High(Int64))) then Exit(R(epTamOrigInvalido));
  { Dividir en vez de multiplicar: tamPayload * 500 puede desbordar, el
    cociente no. tamOrig > 500 * tamPayload  <=>  (tamOrig - 1) div 500 >= tamPayload }
  if (tamOrig - 1) div MAX_RATIO_EXPANSION >= tamPayload then Exit(R(epRatioExcedido));
  Result := R(epNinguno);
end;

{ El descriptor y el payload a partir de cuerpo[ini..]. }
function LeerCuerpo(const cuerpo: TBytes; ini: SizeInt; var p: TPja): TResultadoPja;
var resto: SizeInt;
begin
  resto := Length(cuerpo) - ini;
  if resto < TAM_DESCRIPTOR then Exit(R(epArchivoCorto));
  p.tam_orig := U64(cuerpo, ini);
  Move(cuerpo[ini + 8], p.hash[0], 16);
  Result := ValidarDescriptor(p.tam_orig, QWord(resto - TAM_DESCRIPTOR));
  if not Result.Ok then Exit;
  { Copy NO controla rango ni con $R+: recorta en silencio. El largo ya esta
    validado arriba; esto es lo que efectivamente queda. }
  p.payload := Copy(cuerpo, ini + TAM_DESCRIPTOR, resto - TAM_DESCRIPTOR);
  if Length(p.payload) <> resto - TAM_DESCRIPTOR then
    raise ERangeError.Create('LeerCuerpo: el payload no salio entero');
end;

{ Un rechazo no deja nada a medio llenar: ni el tam_orig ni el hash leidos
  antes de que fallara la validacion. }
procedure Vaciar(out p: TPja);
begin
  p.cifrado := False; p.tam_orig := 0; FillChar(p.hash, SizeOf(p.hash), 0); p.payload := nil;
end;

{ El tramo cifrado: autenticar, la copia de la cabecera, el descriptor. }
function AbrirCifrado(const datos: TBytes; const clave: TClave; var p: TPja): TResultadoPja;
var rc: TResultadoCifrado; cuerpo: TBytes; nonce: TNonce; i: Integer;
begin
  Move(datos[TAM_CABECERA + TAM_SAL], nonce[0], TAM_NONCE);
  { Autenticar ANTES de mirar el descriptor. }
  rc := Descifrar(clave, nonce, datos, TAM_CABECERA + TAM_PREFIJO_CIFRADO, cuerpo);
  if not rc.Ok then Exit(RCif(rc));

  { El cuerpo cifrado empieza con una copia de la cabecera en claro, y tiene
    que coincidir. Hoy los 8 bytes de afuera ya estan atados de otra forma:
    LeerCabecera fija magia, version, reservado y el bit de cifrado, y el
    perfil de KDF cambia la clave. La copia es para el primer flag o perfil
    nuevo que NO cambie la clave: sin ella, quedaria afuera sin autenticar. }
  if Length(cuerpo) < TAM_CABECERA then Exit(R(epCabeceraAlterada));
  for i := 0 to TAM_CABECERA - 1 do
    if cuerpo[i] <> datos[i] then Exit(R(epCabeceraAlterada));
  Result := LeerCuerpo(cuerpo, TAM_CABECERA, p);
  if Result.Ok then p.cifrado := True;
end;

function AbrirConClave(const datos: TBytes; const clave: TClave; out p: TPja): TResultadoPja;
var cifrado: Boolean;
begin
  Vaciar(p);
  Result := LeerCabecera(datos, cifrado);
  if Result.Ok and not cifrado then Result := R(epContrasenaSobrante);
  if Result.Ok and (Length(datos) < TAM_CABECERA + TAM_PREFIJO_CIFRADO) then Result := R(epArchivoCorto);
  if Result.Ok then Result := AbrirCifrado(datos, clave, p);
  if not Result.Ok then Vaciar(p);
end;

function AbrirInterno(const datos: TBytes; conPass: Boolean; const pass: TBytes;
                      out p: TPja): TResultadoPja;
var
  rc: TResultadoCifrado; sal: TSal; clave: TClave; cifrado: Boolean;
begin
  Vaciar(p);
  { La cabecera se valida ANTES de mirar el bit de cifrado: basura con el
    byte 5 impar se rechaza por "no es un .pja", no por "falta contrasena". }
  Result := LeerCabecera(datos, cifrado);
  if not Result.Ok then Exit;

  if not cifrado then begin
    if conPass then Exit(R(epContrasenaSobrante));
    Result := LeerCuerpo(datos, TAM_CABECERA, p);
    if not Result.Ok then Vaciar(p);
    Exit;
  end;

  if not conPass then Exit(R(epContrasenaFaltante));
  if Length(datos) < TAM_CABECERA + TAM_PREFIJO_CIFRADO then Exit(R(epArchivoCorto));
  Move(datos[TAM_CABECERA], sal[0], TAM_SAL);
  rc := DerivarClave(pass, sal, clave);
  if not rc.Ok then begin Limpiar(clave, SizeOf(clave)); Exit(RCif(rc)); end;
  Result := AbrirCifrado(datos, clave, p);
  Limpiar(clave, SizeOf(clave));
  if not Result.Ok then Vaciar(p);
end;

function Abrir(const datos: TBytes; out p: TPja): TResultadoPja;
begin
  Result := AbrirInterno(datos, False, nil, p);
end;

function Abrir(const datos: TBytes; const pass: TBytes; out p: TPja): TResultadoPja;
begin
  Result := AbrirInterno(datos, True, pass, p);
end;

{ ------------------------------------------------------------------------ }

function LargoEscrito(tamPayload: Int64; cifrado: Boolean): Int64;
var cuerpo, trozos: Int64;
begin
  if (tamPayload < 0) or (tamPayload > High(SizeInt)) then Exit(-1);
  if not cifrado then
    cuerpo := TAM_CABECERA + TAM_DESCRIPTOR + tamPayload
  else begin
    { copia de la cabecera + descriptor + payload, por trozos de 64 KB, y cada
      trozo con su largo (4) y su tag (16). Al menos un trozo. }
    cuerpo := TAM_CABECERA + TAM_DESCRIPTOR + tamPayload;
    trozos := (cuerpo + TAM_TROZO - 1) div TAM_TROZO;
    if trozos < 1 then trozos := 1;
    cuerpo := TAM_CABECERA + TAM_PREFIJO_CIFRADO + cuerpo + trozos * (4 + TAM_TAG);
  end;
  if cuerpo > High(SizeInt) then Exit(-1);
  Result := cuerpo;
end;

{ Cabecera + descriptor + payload: el archivo sin cifrar, y el claro del
  cuerpo cifrado (que empieza con la copia de la cabecera). }
function ArmarClaro(const payload: TBytes; const hash: THash16; tamOrig: QWord;
               flags, kdf: Byte; out bytes: TBytes): TResultadoPja;
var total: Int64; i: Integer;
begin
  bytes := nil;
  Result := ValidarDescriptor(tamOrig, Length(payload));
  if not Result.Ok then Exit;
  total := Int64(TAM_CABECERA) + TAM_DESCRIPTOR + Length(payload);
  if total > High(SizeInt) then Exit(R(epDesborde));
  SetLength(bytes, total);
  for i := 0 to 3 do bytes[i] := MAGIA[i];
  bytes[4] := VERSION; bytes[5] := flags; bytes[6] := kdf; bytes[7] := 0;
  Pon64(bytes, TAM_CABECERA, tamOrig);
  Move(hash[0], bytes[TAM_CABECERA + 8], 16);
  if Length(payload) > 0 then Move(payload[0], bytes[TAM_CABECERA + TAM_DESCRIPTOR], Length(payload));
end;

function Escribir(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                  out bytes: TBytes): TResultadoPja;
begin
  Result := ArmarClaro(payload, hash, tamOrig, 0, 0, bytes);
end;

function EscribirCon(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                     const pass: TBytes; const sal: TSal; const nonce: TNonce;
                     out bytes: TBytes): TResultadoPja;
var plano, ct: TBytes; clave: TClave; rc: TResultadoCifrado; total: Int64;
begin
  bytes := nil;
  Result := ArmarClaro(payload, hash, tamOrig, FLAG_CIFRADO, PERFIL_KDF_V1, plano);
  if not Result.Ok then Exit;
  total := LargoEscrito(Length(payload), True);
  if total < 0 then Exit(R(epDesborde));
  rc := DerivarClave(pass, sal, clave);
  if not rc.Ok then begin Limpiar(clave, SizeOf(clave)); Exit(RCif(rc)); end;
  rc := Cifrar(clave, nonce, plano, ct);
  Limpiar(clave, SizeOf(clave));
  if not rc.Ok then Exit(RCif(rc));
  SetLength(bytes, total);
  Move(plano[0], bytes[0], TAM_CABECERA);
  Move(sal[0], bytes[TAM_CABECERA], TAM_SAL);
  Move(nonce[0], bytes[TAM_CABECERA + TAM_SAL], TAM_NONCE);
  if TAM_CABECERA + TAM_PREFIJO_CIFRADO + Length(ct) <> total then
    raise Exception.CreateFmt('Escribir: el cifrado dio %d B, LargoEscrito %d',
                              [TAM_CABECERA + TAM_PREFIJO_CIFRADO + Length(ct), total]);
  Move(ct[0], bytes[TAM_CABECERA + TAM_PREFIJO_CIFRADO], Length(ct));
end;

function Escribir(const payload: TBytes; const hash: THash16; tamOrig: QWord;
                  const pass: TBytes; out bytes: TBytes): TResultadoPja;
var sal: TSal; nonce: TNonce;
begin
  bytes := nil;
  { Validar primero: no derivar 64 MiB de Argon2id para un descriptor malo. }
  Result := ValidarDescriptor(tamOrig, Length(payload));
  if not Result.Ok then Exit;
  if not Aleatorio(sal, SizeOf(sal)) or not Aleatorio(nonce, SizeOf(nonce)) then
    Exit(R(epSinAleatorio));
  Result := EscribirCon(payload, hash, tamOrig, pass, sal, nonce, bytes);
end;

end.
