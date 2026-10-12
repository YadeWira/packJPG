{ Port de pjaffi/src/lib.rs: la frontera C++ <-> Pascal del contenedor.

  La misma superficie que la version Rust (include/pjacore.h), con los mismos
  codigos de estado, mas pja_iniciar/pja_terminar y dos codigos nuevos.

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
    implementacion las convierte en PJA_ERR_INTERNO. El Rust abortaba el
    proceso; aca vuelve un codigo. }
library pjaffi;
{$I pja.inc}
{$ifdef MSWINDOWS}
  { DYNAMIC_BASE + NX_COMPAT: FPC arma la DLL reubicable pero no la DECLARA
    apta para ASLR ni DEP. Verificado en el PE (fpc-link). }
  {$SetPEOptFlags $140}
{$endif}

uses
  {$ifdef unix} cthreads, {$endif}
  SysUtils, pjacripto, pjaindice, pjaescritor, pjacifrado, pjacontenedor;

const
  PJA_OK            = 0;
  PJA_ERR_NULL      = -1;
  PJA_ERR_BUF_CHICO = -2;
  PJA_ERR_FORMATO   = -3;
  PJA_ERR_LIMITE    = -4;
  PJA_ERR_NOMBRE    = -5;
  PJA_ERR_CLAVE     = -6;
  PJA_ERR_INDICE    = -7;
  PJA_ERR_RANGO     = -8;
  PJA_ERR_INTERNO   = -9;    { una excepcion adentro: un defecto nuestro, nunca una entrada valida }
  PJA_ERR_NO_INIT   = -10;   { se llamo sin pja_iniciar (enlace estatico) }

type
  TPjaAbierto = record
    a: TAbierto;
  end;
  PPjaAbierto = ^TPjaAbierto;
  PPPjaAbierto = ^PPjaAbierto;

  { Mismo layout que PjaEntradaC en pjacore.h. }
  TPjaEntradaC = record
    nombre: PByte;
    nombre_largo: SizeUInt;
    payload: PByte;
    payload_largo: SizeUInt;
    hash: THash16;
    tam_orig: QWord;
  end;
  PPjaEntradaC = ^TPjaEntradaC;

var
  { Dato estatico: legible ANTES de que corra la inicializacion de la unidad.
    Lo pone en True el bloque principal de la libreria. }
  inicializado: Boolean = False;

{ ------------------------------------------------------------------------
  Implementacion. Aca si puede haber variables administradas y try. }

function Traducir(const r: TResultadoContenedor): LongInt;
begin
  case r.err of
    ecoNinguno: Result := PJA_OK;
    ecoContrasenaFaltante, ecoContrasenaSobrante, ecoCifrado: Result := PJA_ERR_CLAVE;
    ecoArchivoCorto: Result := PJA_ERR_FORMATO;
    ecoEscritura: Result := PJA_ERR_NOMBRE;
    ecoIndice:
      case r.indice.err of
        eNombreInvalido, eNombreDuplicado: Result := PJA_ERR_NOMBRE;
        eIndiceAlterado: Result := PJA_ERR_INDICE;
        eDemasiadosMiembros, eCountImposible, eRatioExcedido, ePresupuestoExcedido,
        eSumaNoCuadra, ePayloadFueraDeRango, eDesborde: Result := PJA_ERR_LIMITE;
      else Result := PJA_ERR_FORMATO;
      end;
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

function AbrirImpl(datos: PByte; largo: SizeUInt; pass: PByte; pass_largo: SizeUInt;
                   salida: PPPjaAbierto): LongInt;
var d: TBytes; h: PPjaAbierto; r: TResultadoContenedor;
begin
  h := nil;
  try
    d := Copiar(datos, largo);
    New(h);
    if pass = nil then r := Abrir(d, h^.a)
    else r := Abrir(d, Copiar(pass, pass_largo), h^.a);
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

{ Copia `src` al buffer del llamador, con los chequeos de largo de la frontera. }
function CopiarAfuera(const src: TBytes; buf: PByte; buf_largo: SizeUInt): LongInt;
begin
  if buf_largo < SizeUInt(Length(src)) then Exit(PJA_ERR_BUF_CHICO);
  if Length(src) > 0 then Move(src[0], buf^, Length(src));
  Result := PJA_OK;
end;

function CantidadImpl(h: PPjaAbierto): Int64;
begin
  try Result := Length(h^.a.contenedor.miembros); except Result := PJA_ERR_INTERNO; end;
end;

function NombreLargoImpl(h: PPjaAbierto; i: SizeUInt): Int64;
begin
  try
    if i >= SizeUInt(Length(h^.a.contenedor.miembros)) then Exit(PJA_ERR_RANGO);
    Result := Length(h^.a.contenedor.miembros[i].nombre);
  except Result := PJA_ERR_INTERNO; end;
end;

function NombreImpl(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt;
begin
  try
    if i >= SizeUInt(Length(h^.a.contenedor.miembros)) then Exit(PJA_ERR_RANGO);
    Result := CopiarAfuera(h^.a.contenedor.miembros[i].nombre, buf, buf_largo);
  except Result := PJA_ERR_INTERNO; end;
end;

function PayloadLargoImpl(h: PPjaAbierto; i: SizeUInt): Int64;
begin
  try
    if i >= SizeUInt(Length(h^.a.payloads)) then Exit(PJA_ERR_RANGO);
    Result := Length(h^.a.payloads[i]);
  except Result := PJA_ERR_INTERNO; end;
end;

function PayloadImpl(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt;
begin
  try
    if i >= SizeUInt(Length(h^.a.payloads)) then Exit(PJA_ERR_RANGO);
    Result := CopiarAfuera(h^.a.payloads[i], buf, buf_largo);
  except Result := PJA_ERR_INTERNO; end;
end;

function HashImpl(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt;
begin
  try
    { el orden de los chequeos es el del Rust: buffer chico antes que rango }
    if buf_largo < 16 then Exit(PJA_ERR_BUF_CHICO);
    if i >= SizeUInt(Length(h^.a.contenedor.miembros)) then Exit(PJA_ERR_RANGO);
    Move(h^.a.contenedor.miembros[i].hash[0], buf^, 16);
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

{ recolectar() del Rust: nulo en una entrada (o en la lista con n > 0) es PJA_ERR_NULL. }
function Recolectar(ents: PPjaEntradaC; n: SizeUInt; out es: TEntradas): Boolean;
var i: SizeUInt; e: PPjaEntradaC;
begin
  es := nil;
  if (ents = nil) and (n <> 0) then Exit(False);
  SetLength(es, n);
  if n > 0 then
    for i := 0 to n - 1 do begin
      e := ents + i;
      if (e^.nombre = nil) or (e^.payload = nil) then Exit(False);
      es[i].nombre := Copiar(e^.nombre, e^.nombre_largo);
      es[i].payload := Copiar(e^.payload, e^.payload_largo);
      if e^.tam_orig <> 0 then es[i].tam_orig := e^.tam_orig else es[i].tam_orig := e^.payload_largo;
      es[i].hash := e^.hash;
    end;
  Result := True;
end;

function EscribirLargoImpl(ents: PPjaEntradaC; n: SizeUInt; flags: Byte): Int64;
var es: TEntradas; bytes: TBytes; av: TAvisos; r: TResultadoContenedor;
begin
  try
    if not Recolectar(ents, n, es) then Exit(PJA_ERR_NULL);
    r := EscribirContenedor(es, flags, bytes, av);
    if not r.Ok then Exit(Traducir(r));
    Result := Length(bytes);
  except Result := PJA_ERR_INTERNO; end;
end;

function EscribirImpl(ents: PPjaEntradaC; n: SizeUInt; flags: Byte; buf: PByte; buf_largo: SizeUInt): LongInt;
var es: TEntradas; bytes: TBytes; av: TAvisos; r: TResultadoContenedor;
begin
  try
    if not Recolectar(ents, n, es) then Exit(PJA_ERR_NULL);
    r := EscribirContenedor(es, flags, bytes, av);
    if not r.Ok then Exit(Traducir(r));
    Result := CopiarAfuera(bytes, buf, buf_largo);
  except Result := PJA_ERR_INTERNO; end;
end;

{ ------------------------------------------------------------------------
  La frontera: cascaras. Sin variables administradas, sin try. }

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

function pja_cantidad(h: PPjaAbierto): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if h = nil then Exit(PJA_ERR_NULL);
  Result := CantidadImpl(h);
end;

function pja_nombre_largo(h: PPjaAbierto; i: SizeUInt): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if h = nil then Exit(PJA_ERR_NULL);
  Result := NombreLargoImpl(h, i);
end;

function pja_nombre(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (h = nil) or (buf = nil) then Exit(PJA_ERR_NULL);
  Result := NombreImpl(h, i, buf, buf_largo);
end;

function pja_payload_largo(h: PPjaAbierto; i: SizeUInt): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if h = nil then Exit(PJA_ERR_NULL);
  Result := PayloadLargoImpl(h, i);
end;

function pja_payload(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (h = nil) or (buf = nil) then Exit(PJA_ERR_NULL);
  Result := PayloadImpl(h, i, buf, buf_largo);
end;

function pja_hash(h: PPjaAbierto; i: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if (h = nil) or (buf = nil) then Exit(PJA_ERR_NULL);
  Result := HashImpl(h, i, buf, buf_largo);
end;

function pja_hash128(datos: PByte; largo: SizeUInt; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if buf = nil then Exit(PJA_ERR_NULL);
  if buf_largo < 16 then Exit(PJA_ERR_BUF_CHICO);
  if (datos = nil) and (largo <> 0) then Exit(PJA_ERR_NULL);
  Result := Hash128Impl(datos, largo, buf);
end;

function pja_escribir_largo(ents: PPjaEntradaC; n: SizeUInt; flags: Byte): Int64; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  Result := EscribirLargoImpl(ents, n, flags);
end;

function pja_escribir(ents: PPjaEntradaC; n: SizeUInt; flags: Byte; buf: PByte; buf_largo: SizeUInt): LongInt; cdecl;
begin
  if not inicializado then Exit(PJA_ERR_NO_INIT);
  if buf = nil then Exit(PJA_ERR_NULL);
  Result := EscribirImpl(ents, n, flags, buf, buf_largo);
end;

function pja_version: LongWord; cdecl;
begin
  Result := 1;
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
  pja_abrir name 'pja_abrir',
  pja_cerrar name 'pja_cerrar',
  pja_cantidad name 'pja_cantidad',
  pja_nombre_largo name 'pja_nombre_largo',
  pja_nombre name 'pja_nombre',
  pja_payload_largo name 'pja_payload_largo',
  pja_payload name 'pja_payload',
  pja_hash name 'pja_hash',
  pja_hash128 name 'pja_hash128',
  pja_escribir_largo name 'pja_escribir_largo',
  pja_escribir name 'pja_escribir',
  pja_version name 'pja_version',
  pja_inicializado name 'pja_inicializado',
  pja_rango_activo name 'pja_rango_activo',
  {$ifdef MSWINDOWS} pja_iniciar name 'pja_iniciar', pja_terminar name 'pja_terminar', {$endif}
  pja_iniciar_pascal name 'pja_iniciar_pascal';

begin
  inicializado := True;
end.
