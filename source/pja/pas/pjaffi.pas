{ La frontera C++ <-> Pascal del formato .pja (include/pjacore.h).

  Reglas, todas medidas en el spike de enlace (fpc-link/RESULTADOS.md):
  - entra puntero + largo, sale un codigo de estado; 0 es exito
  - NINGUNA propiedad de memoria cruza: los buffers los provee el llamador, y
    lo unico con estado es un manejador opaco con su abrir/cerrar
  - $R+ NO controla accesos por puntero: lo que entra por puntero se copia a
    un arreglo antes de validar nada
  - cada funcion exportada es una CASCARA sin variables administradas y sin
    try, que mira `inicializado` y recien ahi llama a la implementacion. Si la
    guarda viviera adentro de una funcion con strings, arreglos o try, FPC arma
    el marco de excepciones en el prologo, ANTES de la guarda, y un hilo del
    anfitrion que llama sin runtime revienta ahi.
  - olvidarse de inicializar el runtime NO falla solo: el camino normal anda
    y la proteccion de rango se apaga. Por eso la bandera, y PJA_ERR_NO_INIT.
  - ninguna excepcion cruza hacia C++ (seria comportamiento indefinido): la
    implementacion las convierte en PJA_ERR_INTERNO. }
library pjaffi;
{$I pja.inc}
{$ifdef MSWINDOWS}
  { DYNAMIC_BASE + NX_COMPAT: FPC arma la DLL reubicable pero no la DECLARA
    apta para ASLR ni DEP. Verificado en el PE (fpc-link). }
  {$SetPEOptFlags $140}
{$endif}

uses
  {$ifdef unix} cthreads, {$endif}
  SysUtils, pjacripto, pjacifrado, pjaformato, pjafs;

const
  PJA_OK            = 0;
  PJA_ERR_NULL      = -1;
  PJA_ERR_BUF_CHICO = -2;
  PJA_ERR_FORMATO   = -3;
  PJA_ERR_LIMITE    = -4;
  PJA_ERR_CLAVE     = -6;
  PJA_ERR_ALTERADO  = -7;
  PJA_ERR_INTERNO   = -9;    { una excepcion adentro: un defecto nuestro, nunca una entrada valida }
  PJA_ERR_NO_INIT   = -10;   { se llamo sin pja_iniciar (enlace estatico) }
  PJA_ERR_ALEATORIO = -11;
  PJA_ERR_IO        = -12;

type
  TPjaAbierto = record
    p: TPja;
  end;
  PPjaAbierto = ^TPjaAbierto;
  PPPjaAbierto = ^PPjaAbierto;

var
  { Dato estatico: legible ANTES de que corra la inicializacion de la unidad.
    Lo pone en True el bloque principal de la libreria. }
  inicializado: Boolean = False;

{ ------------------------------------------------------------------------
  Implementacion. Aca si puede haber variables administradas y try. }

function Traducir(const r: TResultadoPja): LongInt;
begin
  case r.err of
    epNinguno: Result := PJA_OK;
    epArchivoCorto, epNoEsPja, epVersionFutura, epVersionVieja, epFlagDesconocido,
    epReservadoNoCero, epPerfilKdfDesconocido: Result := PJA_ERR_FORMATO;
    epContrasenaFaltante, epContrasenaSobrante: Result := PJA_ERR_CLAVE;
    epCifrado:
      case r.cifrado.err of
        { el primer trozo: contraseña equivocada o trozo alterado, el AEAD no
          los distingue }
        ecTrozoAlterado: if r.cifrado.valor = 0 then Result := PJA_ERR_CLAVE
                         else Result := PJA_ERR_ALTERADO;
        ecTruncado, ecSobranTrozos: Result := PJA_ERR_ALTERADO;
        ecFormato: Result := PJA_ERR_FORMATO;
      else Result := PJA_ERR_INTERNO;
      end;
    epCabeceraAlterada: Result := PJA_ERR_ALTERADO;
    epPayloadFueraDeRango, epTamOrigInvalido, epRatioExcedido, epDesborde: Result := PJA_ERR_LIMITE;
    epSinAleatorio: Result := PJA_ERR_ALEATORIO;
  else Result := PJA_ERR_INTERNO;
  end;
end;

{ Copia `n` bytes desde un puntero a un arreglo: a partir de aca, $R+ cuida. }
function Copiar(p: PByte; n: SizeUInt): TBytes;
begin
  Result := nil;
  SetLength(Result, n);
  if n > 0 then Move(p^, Result[0], n);
end;

function ExaminarImpl(datos: PByte; largo: SizeUInt; cifrado: PLongInt): LongInt;
var c: Boolean; r: TResultadoPja; cab: TBytes;
begin
  try
    { solo los 8 bytes que se miran: no copiar un archivo de 200 MB para eso }
    if largo > TAM_CABECERA then largo := TAM_CABECERA;
    cab := Copiar(datos, largo);
    r := Examinar(cab, c);
    if not r.Ok then Exit(Traducir(r));
    cifrado^ := Ord(c);
    Result := PJA_OK;
  except Result := PJA_ERR_INTERNO; end;
end;

function AbrirImpl(datos: PByte; largo: SizeUInt; pass: PByte; pass_largo: SizeUInt;
                   salida: PPPjaAbierto): LongInt;
var d: TBytes; h: PPjaAbierto; r: TResultadoPja;
begin
  h := nil;
  try
    d := Copiar(datos, largo);
    New(h);
    if pass = nil then r := Abrir(d, h^.p)
    else r := Abrir(d, Copiar(pass, pass_largo), h^.p);
    if not r.Ok then begin Dispose(h); h := nil; Exit(Traducir(r)); end;
    salida^ := h;
    Result := PJA_OK;
  except
    if h <> nil then Dispose(h);
    Result := PJA_ERR_INTERNO;
  end;
end;

procedure CerrarImpl(h: PPjaAbierto);
begin
  try Dispose(h); except end;
end;

function PayloadImpl(h: PPjaAbierto; buf: PByte; buf_largo: SizeUInt): LongInt;
begin
  try
    if buf_largo < SizeUInt(Length(h^.p.payload)) then Exit(PJA_ERR_BUF_CHICO);
    if Length(h^.p.payload) > 0 then Move(h^.p.payload[0], buf^, Length(h^.p.payload));
    Result := PJA_OK;
  except Result := PJA_ERR_INTERNO; end;
end;

function Hash128Impl(datos: PByte; largo: SizeUInt; buf: PByte): LongInt;
var x: THash16;
begin
  try
    x := Blake3_128(Copiar(datos, largo));
    Move(x[0], buf^, 16);
    Result := PJA_OK;
  except Result := PJA_ERR_INTERNO; end;
end;

function EscribirLargoImpl(payload_largo: SizeUInt; cifrado: LongInt): Int64;
begin
  try
    if payload_largo > SizeUInt(High(SizeInt)) then Exit(PJA_ERR_LIMITE);
    Result := LargoEscrito(Int64(payload_largo), cifrado <> 0);
    if Result < 0 then Result := PJA_ERR_LIMITE;
  except Result := PJA_ERR_INTERNO; end;
end;

function EscribirImpl(payload: PByte; payload_largo: SizeUInt; hash: PByte; tam_orig: QWord;
                      pass: PByte; pass_largo: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt;
var pl, bytes: TBytes; h: THash16; r: TResultadoPja; n: Int64;
begin
  try
    if payload_largo > SizeUInt(High(SizeInt)) then Exit(PJA_ERR_LIMITE);
    { El buffer chico se rechaza ANTES de derivar: con cifrado, el escritor
      pagaria 64 MiB de Argon2id para despues no poder entregar nada. }
    n := LargoEscrito(Int64(payload_largo), pass <> nil);
    if n < 0 then Exit(PJA_ERR_LIMITE);
    if buf_largo < SizeUInt(n) then Exit(PJA_ERR_BUF_CHICO);
    pl := Copiar(payload, payload_largo);
    Move(hash^, h[0], 16);
    if pass = nil then r := Escribir(pl, h, tam_orig, bytes)
    else r := Escribir(pl, h, tam_orig, Copiar(pass, pass_largo), bytes);
    if not r.Ok then Exit(Traducir(r));
    if Length(bytes) <> n then raise Exception.Create('pja_escribir: largo distinto del anunciado');
    Move(bytes[0], buf^, Length(bytes));
    Result := PJA_OK;
  except Result := PJA_ERR_INTERNO; end;
end;

function GuardarImpl(ruta: PChar; ruta_largo: SizeUInt; datos: PByte; largo: SizeUInt; esperado: PByte;
                     conservar, sobrescribir: LongInt; desenlace, codigo: PLongInt;
                     ruta_final: PChar; ruta_final_largo: SizeUInt; ruta_final_usado: PSizeUInt): LongInt;
var r: RawByteString; h: THash16; d: TDesenlace; rf: TResultadoFs; sf: TSiFalla; n: SizeUInt;
begin
  try
    r := '';
    SetLength(r, ruta_largo);
    if ruta_largo > 0 then Move(ruta^, r[1], ruta_largo);
    Move(esperado^, h[0], 16);
    if conservar <> 0 then sf := sfConservar else sf := sfBorrar;
    rf := EscribirVerificado(r, Copiar(datos, largo), h, sf, sobrescribir <> 0, d);
    if codigo <> nil then codigo^ := rf.codigo;
    if not rf.Ok then begin
      { NoSePudoConservar: el archivo ya se borro; para quien llama es "no quedo nada" }
      if desenlace <> nil then desenlace^ := Ord(deBorrado);
      Exit(PJA_ERR_IO);
    end;
    if desenlace <> nil then desenlace^ := Ord(d.tipo);
    if ruta_final_usado <> nil then ruta_final_usado^ := Length(d.ruta);
    if (ruta_final <> nil) and (ruta_final_largo > 0) then begin
      n := Length(d.ruta);
      if n >= ruta_final_largo then n := ruta_final_largo - 1;
      if n > 0 then Move(d.ruta[1], ruta_final^, n);
      ruta_final[n] := #0;
    end;
    Result := PJA_OK;
  except Result := PJA_ERR_INTERNO; end;
end;

{ ------------------------------------------------------------------------
  La frontera: cascaras. Sin variables administradas, sin try. }

function pja_examinar(datos: PByte; largo: SizeUInt; cifrado: PLongInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (cifrado = nil) or ((datos = nil) and (largo <> 0)) then Exit(PJA_ERR_NULL);
  Result := ExaminarImpl(datos, largo, cifrado);
end;

function pja_abrir(datos: PByte; largo: SizeUInt; pass: PByte; pass_largo: SizeUInt;
                   salida: PPPjaAbierto): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (datos = nil) or (salida = nil) then Exit(PJA_ERR_NULL);
  salida^ := nil;
  Result := AbrirImpl(datos, largo, pass, pass_largo, salida);
end;

procedure pja_cerrar(h: PPjaAbierto); cdecl;
begin
  if not inicializado then Exit;
  if h <> nil then CerrarImpl(h);
end;

function pja_tam_orig(h: PPjaAbierto): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if h = nil then Exit(PJA_ERR_NULL);
  Result := Int64(h^.p.tam_orig);    { ValidarDescriptor garantiza <= High(Int64) }
end;

function pja_payload_largo(h: PPjaAbierto): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if h = nil then Exit(PJA_ERR_NULL);
  Result := Length(h^.p.payload);
end;

function pja_payload(h: PPjaAbierto; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (h = nil) or (buf = nil) then Exit(PJA_ERR_NULL);
  Result := PayloadImpl(h, buf, buf_largo);
end;

function pja_hash(h: PPjaAbierto; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (h = nil) or (buf = nil) then Exit(PJA_ERR_NULL);
  if buf_largo < 16 then Exit(PJA_ERR_BUF_CHICO);
  Move(h^.p.hash[0], buf^, 16);
  Result := PJA_OK;
end;

function pja_hash128(datos: PByte; largo: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if buf = nil then Exit(PJA_ERR_NULL);
  if buf_largo < 16 then Exit(PJA_ERR_BUF_CHICO);
  if (datos = nil) and (largo <> 0) then Exit(PJA_ERR_NULL);
  Result := Hash128Impl(datos, largo, buf);
end;

function pja_escribir_largo(payload_largo: SizeUInt; cifrado: LongInt): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  Result := EscribirLargoImpl(payload_largo, cifrado);
end;

function pja_escribir(payload: PByte; payload_largo: SizeUInt; hash: PByte; tam_orig: QWord;
                      pass: PByte; pass_largo: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (buf = nil) or (hash = nil) or ((payload = nil) and (payload_largo <> 0))
     or ((pass = nil) and (pass_largo <> 0)) then Exit(PJA_ERR_NULL);
  Result := EscribirImpl(payload, payload_largo, hash, tam_orig, pass, pass_largo, buf, buf_largo);
end;

function pja_guardar(ruta: PChar; ruta_largo: SizeUInt; datos: PByte; largo: SizeUInt; esperado: PByte;
                     conservar, sobrescribir: LongInt; desenlace, codigo: PLongInt;
                     ruta_final: PChar; ruta_final_largo: SizeUInt; ruta_final_usado: PSizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (ruta = nil) or (esperado = nil) or ((datos = nil) and (largo <> 0)) then Exit(PJA_ERR_NULL);
  Result := GuardarImpl(ruta, ruta_largo, datos, largo, esperado, conservar, sobrescribir, desenlace, codigo,
                        ruta_final, ruta_final_largo, ruta_final_usado);
end;

function pja_version: LongWord; cdecl;
begin
  Result := VERSION;
end;

{ 1 si el runtime esta inicializado. Para que el anfitrion lo verifique. }
function pja_inicializado: LongInt; cdecl;
begin
  if inicializado then Result := 1 else Result := 0;
end;

{ Control: que $R+ este prendido de verdad en lo que se compilo. Una prueba
  de la frontera que no mire esto podria pasar con la red apagada. }
function pja_rango_activo: LongInt; cdecl;
begin
  {$ifopt R+} Result := 1; {$else} Result := 0; {$endif}
end;

{ En la DLL el runtime ya arranco al cargarla: pja_iniciar solo confirma. En
  Linux (estatico) la que arranca el runtime es pja_iniciar de pja_inicio.c,
  que llama a FPC_SHARED_LIB_START y despues a esta. }
function pja_iniciar_pascal: LongInt; cdecl;
begin
  if inicializado then Result := PJA_OK else Result := PJA_ERR_NO_INIT;
end;

{$ifdef MSWINDOWS}
{ En la DLL, pja_iniciar/pja_terminar son de Pascal: el runtime arranco con la
  carga y se desarma con la descarga. Los argumentos se ignoran. }
function pja_iniciar(argc: LongInt; argv, envp: Pointer): LongInt; cdecl;
begin
  if inicializado then Result := PJA_OK else Result := PJA_ERR_NO_INIT;
end;
procedure pja_terminar; cdecl;
begin
end;
{$endif}

{ `name` explicito y nada mas: sin el, la tabla de exportacion se lleva
  tambien los nombres internos de Pascal (fpc-link). }
exports
  pja_examinar name 'pja_examinar',
  pja_abrir name 'pja_abrir',
  pja_cerrar name 'pja_cerrar',
  pja_tam_orig name 'pja_tam_orig',
  pja_payload_largo name 'pja_payload_largo',
  pja_payload name 'pja_payload',
  pja_hash name 'pja_hash',
  pja_hash128 name 'pja_hash128',
  pja_escribir_largo name 'pja_escribir_largo',
  pja_escribir name 'pja_escribir',
  pja_guardar name 'pja_guardar',
  pja_version name 'pja_version',
  pja_inicializado name 'pja_inicializado',
  pja_rango_activo name 'pja_rango_activo',
  {$ifdef MSWINDOWS} pja_iniciar name 'pja_iniciar', pja_terminar name 'pja_terminar', {$endif}
  pja_iniciar_pascal name 'pja_iniciar_pascal';

begin
  inicializado := True;
end.
