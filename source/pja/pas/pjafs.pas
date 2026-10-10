{ Port de pjafs/src/lib.rs: la extraccion, la parte que toca el sistema de
  archivos.

  Va aparte del nucleo a proposito: aca vive lo que solo se puede decidir
  contra el disco de destino -- resolver enlaces, verificar contencion, y el
  limite de ruta de la plataforma, que NO se puede chequear al crear porque
  incluye el directorio destino.

  Las rutas son UTF-8 en RawByteString y se tratan como bytes. En Windows se
  pasan a UTF-16 recien al llamar a la API (las funciones W), y la ruta
  resuelta vuelve a UTF-8.

  Cada llamada al sistema es la MISMA que hace la std de Rust en esa
  plataforma (realpath, lstat, open O_EXCL, mkdir 0777, rename; en Windows
  GetFinalPathNameByHandleW, CreateFileW CREATE_NEW, MoveFileExW), asi los
  codigos de error que salen son los mismos y el diferencial los compara. }
unit pjafs;
{$I pja.inc}

interface

uses
  SysUtils, pjacripto, pjanombres;

const
  { Limite de ruta completa de Windows sin opt-in explicito. Se aplica
    siempre, no solo compilando para Windows: un contenedor armado en Linux
    tiene que poder avisar que va a ser inextraible alla. }
  MAX_PATH_WINDOWS = 260;
  {$ifdef MSWINDOWS} SEP_RUTA = '\'; {$else} SEP_RUTA = '/'; {$endif}

type
  TErrorExtraccion = (exNinguno, exNombreInvalido, exEscapaDelDestino, exRutaMuyLargaParaWindows,
                      exDestinoYaExiste, exDestinoNoEsDirectorio);

  TResultadoExtraccion = record
    error: TErrorExtraccion;
    largo: SizeInt;            { solo con exRutaMuyLargaParaWindows }
    function Ok: Boolean;
    { Mismo texto que el Debug de Rust: "EscapaDelDestino", "RutaMuyLargaParaWindows(261)" }
    function Texto: string;
  end;

  { Que hacer con un archivo ya escrito cuyo hash no coincide. El default es
    Borrar: un archivo con nombre bueno y contenido malo es peor que ningun
    archivo. Conservar lo deja con OTRO nombre, nunca con el suyo. }
  TSiFalla = (sfBorrar, sfConservar);

  TTipoDesenlace = (deVerificado, deBorrado, deConservado);
  TDesenlace = record
    tipo: TTipoDesenlace;
    ruta: RawByteString;       { Verificado y Conservado }
    esperado, obtenido: THash16;   { Borrado y Conservado }
  end;

  TErrorFs = (efNinguno,
              { No se pudo escribir. Lo que se haya escrito ya se borro. }
              efIo,
              { El hash no coincidia, se pidio conservar, y no se pudo
                renombrar. El archivo se borro. }
              efNoSePudoConservar);
  TResultadoFs = record
    error: TErrorFs;
    { errno en Unix, GetLastError en Windows; -1 si el error no vino del
      sistema ("no quedan nombres .corrupto libres"). }
    codigo: LongInt;
    function Ok: Boolean;
    { "Io(13)", "NoSePudoConservar(-)": el diferencial imprime asi las dos puntas }
    function Texto: string;
  end;

{ Resuelve donde va un miembro dentro de `destino`, o rechaza. Ver el Rust:
  primero el nombre, despues la ruta, y al final que lo resuelto siga adentro.
  La ruta devuelta cuelga del destino YA resuelto. }
function DestinoDe(const destino: RawByteString; const nombre: TBytes; rutas, sobrescribir: Boolean;
                   out rutaFinal: RawByteString): TResultadoExtraccion;

{ Escribe un miembro y verifica DESPUES de escribir. El archivo se CREA (nunca
  se abre uno existente, y no se siguen enlaces); con `sobrescribir`, la
  entrada que haya se borra antes. }
function EscribirVerificado(const archivo: RawByteString; const datos: TBytes; const esperado: THash16;
                            siFalla: TSiFalla; sobrescribir: Boolean; out d: TDesenlace): TResultadoFs;

{ Expuestas para las pruebas: unidades UTF-16 que cuenta Windows (sin el
  prefijo \\?\), la contencion por componentes y el padre de una ruta. }
function LargoWindows(const p: RawByteString): SizeInt;
function EmpiezaCon(const p, base: RawByteString): Boolean;
{ Path::parent; False en la raiz o con la ruta vacia. }
function Padre(const p: RawByteString; out q: RawByteString): Boolean;

implementation

uses
  {$ifdef MSWINDOWS} Windows {$else} BaseUnix {$endif};

function TResultadoExtraccion.Ok: Boolean; begin Result := error = exNinguno; end;
function TResultadoExtraccion.Texto: string;
const N: array[TErrorExtraccion] of string = ('Ninguno', 'NombreInvalido', 'EscapaDelDestino',
  'RutaMuyLargaParaWindows', 'DestinoYaExiste', 'DestinoNoEsDirectorio');
begin
  Result := N[error];
  if error = exRutaMuyLargaParaWindows then Result := Result + '(' + IntToStr(largo) + ')';
end;

function TResultadoFs.Ok: Boolean; begin Result := error = efNinguno; end;
function TResultadoFs.Texto: string;
const N: array[TErrorFs] of string = ('Ninguno', 'Io', 'NoSePudoConservar');
begin
  Result := N[error];
  if error <> efNinguno then
    if codigo < 0 then Result := Result + '(-)' else Result := Result + '(' + IntToStr(codigo) + ')';
end;

function RE(e: TErrorExtraccion; largo: SizeInt = 0): TResultadoExtraccion;
begin Result.error := e; Result.largo := largo; end;
function RF(e: TErrorFs; codigo: LongInt): TResultadoFs;
begin Result.error := e; Result.codigo := codigo; end;

{ ------------------------------------------------------------------------
  Capa de sistema. Todo lo que depende de la plataforma esta aca. }

{$ifdef MSWINDOWS}
const
  FILE_SHARE_DELETE_ = $00000004;
  FILE_FLAG_BACKUP_SEMANTICS_ = $02000000;
  VOLUME_NAME_DOS = 0;
{ Vista+; FPC 3.2.2 no la declara. Es la que usa std::fs::canonicalize. }
function GetFinalPathNameByHandleW(h: THandle; buf: PWideChar; n: DWORD; flags: DWORD): DWORD;
  stdcall; external 'kernel32' name 'GetFinalPathNameByHandleW';

function W(const p: RawByteString): UnicodeString;
begin Result := UTF8Decode(p); end;

function Canonicalizar(const p: RawByteString; out r: RawByteString): Boolean;
var h: THandle; buf: UnicodeString; n: DWORD;
begin
  Result := False; r := '';
  h := CreateFileW(PWideChar(W(p)), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE_, nil,
                   OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS_, 0);
  if h = INVALID_HANDLE_VALUE then Exit;
  try
    SetLength(buf, 512);
    n := GetFinalPathNameByHandleW(h, PWideChar(buf), Length(buf), VOLUME_NAME_DOS);
    if n >= DWORD(Length(buf)) then begin
      SetLength(buf, n);
      n := GetFinalPathNameByHandleW(h, PWideChar(buf), Length(buf), VOLUME_NAME_DOS);
    end;
    if (n = 0) or (n >= DWORD(Length(buf))) then Exit;
    SetLength(buf, n);
    r := UTF8Encode(buf);
    Result := True;
  finally CloseHandle(h); end;
end;

function EsDirectorio(const p: RawByteString): Boolean;
var a: DWORD;
begin
  a := GetFileAttributesW(PWideChar(W(p)));
  Result := (a <> INVALID_FILE_ATTRIBUTES) and ((a and FILE_ATTRIBUTE_DIRECTORY) <> 0);
end;

{ La entrada, sin seguir enlaces (GetFileAttributes no los sigue). }
function ExisteEntrada(const p: RawByteString): Boolean;
begin Result := GetFileAttributesW(PWideChar(W(p))) <> INVALID_FILE_ATTRIBUTES; end;

function UltimoError: LongInt; begin Result := LongInt(GetLastError); end;
const E_NO_EXISTE = ERROR_FILE_NOT_FOUND; E_NO_EXISTE2 = ERROR_PATH_NOT_FOUND;

function CrearDir(const p: RawByteString): Boolean;
begin Result := CreateDirectoryW(PWideChar(W(p)), nil); end;
function Borrar(const p: RawByteString): Boolean;
begin Result := DeleteFileW(PWideChar(W(p))); end;
function Renombrar(const a, b: RawByteString): Boolean;
begin Result := MoveFileExW(PWideChar(W(a)), PWideChar(W(b)), MOVEFILE_REPLACE_EXISTING); end;

type TArchivo = THandle;
function CrearNuevo(const p: RawByteString; out f: TArchivo): Boolean;
begin
  f := CreateFileW(PWideChar(W(p)), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE_,
                   nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  Result := f <> INVALID_HANDLE_VALUE;
end;
function EscribirTodo(f: TArchivo; const datos: TBytes): Boolean;
var hecho: SizeInt; n: DWORD; pedir: DWORD;
begin
  hecho := 0;
  while hecho < Length(datos) do begin
    pedir := DWORD(Length(datos) - hecho);
    if pedir > $40000000 then pedir := $40000000;
    if not WriteFile(f, datos[hecho], pedir, n, nil) then Exit(False);
    if n = 0 then begin SetLastError(0); Exit(False); end;   { como write_all: WriteZero, sin codigo }
    Inc(hecho, n);
  end;
  Result := True;
end;
procedure Cerrar(f: TArchivo); begin CloseHandle(f); end;

{$else}
const
  PATH_MAX_ = 4096;
  {$ifdef linux} O_CLOEXEC_ = $80000; {$else} O_CLOEXEC_ = 0; {$endif}
{ La de libc: es exactamente la que usa std::fs::canonicalize en Unix. }
function realpath(path: PChar; resolved: PChar): PChar; cdecl; external 'c' name 'realpath';

function Canonicalizar(const p: RawByteString; out r: RawByteString): Boolean;
var buf: array[0..PATH_MAX_] of Char;
begin
  r := '';
  if Pos(#0, p) > 0 then Exit(False);
  Result := realpath(PChar(p), @buf[0]) <> nil;
  if Result then r := PChar(@buf[0]);
end;

function EsDirectorio(const p: RawByteString): Boolean;
var st: Stat;
begin Result := (Pos(#0, p) = 0) and (fpStat(PChar(p), st) = 0) and fpS_ISDIR(st.st_mode); end;

function ExisteEntrada(const p: RawByteString): Boolean;
var st: Stat;
begin Result := (Pos(#0, p) = 0) and (fpLstat(PChar(p), st) = 0); end;

function UltimoError: LongInt; begin Result := fpgeterrno; end;
const E_NO_EXISTE = ESysENOENT; E_NO_EXISTE2 = ESysENOENT;

function CrearDir(const p: RawByteString): Boolean;
begin Result := fpMkdir(PChar(p), &777) = 0; end;
function Borrar(const p: RawByteString): Boolean;
begin Result := fpUnlink(PChar(p)) = 0; end;
function Renombrar(const a, b: RawByteString): Boolean;
begin Result := fpRename(PChar(a), PChar(b)) = 0; end;

type TArchivo = cint;
function CrearNuevo(const p: RawByteString; out f: TArchivo): Boolean;
begin
  f := fpOpen(PChar(p), O_WRONLY or O_CREAT or O_EXCL or O_CLOEXEC_, &666);
  Result := f >= 0;
end;
function EscribirTodo(f: TArchivo; const datos: TBytes): Boolean;
var hecho: SizeInt; n: TSsize;
begin
  hecho := 0;
  while hecho < Length(datos) do begin
    n := fpWrite(f, datos[hecho], Length(datos) - hecho);
    if n < 0 then begin
      if fpgeterrno = ESysEINTR then Continue;
      Exit(False);
    end;
    if n = 0 then begin fpseterrno(0); Exit(False); end;   { como write_all: WriteZero, sin codigo }
    Inc(hecho, n);
  end;
  Result := True;
end;
procedure Cerrar(f: TArchivo); begin fpClose(f); end;
{$endif}

{ ------------------------------------------------------------------------
  Rutas como texto. }

{ Raiz: '/' en Unix; en Windows lo que GetFinalPathNameByHandle devuelve para
  una unidad, "\\?\C:\" (o "\\?\UNC\srv\rec\"). }
function EsRaiz(const p: RawByteString): Boolean;
{$ifdef MSWINDOWS}
var r: RawByteString; i, n: SizeInt;
begin
  { No alcanza con "termina en \": asi el padre de \\?\C:\a\b salia
    \\?\C:\a\ (visto en Windows 10 real). Raiz es X:\ o \\srv\recurso\,
    con o sin el prefijo \\?\ (o \\?\UNC\). }
  if (p = '') or (p[Length(p)] <> '\') then Exit(False);
  if Copy(p, 1, 8) = '\\?\UNC\' then r := '\\' + Copy(p, 9, MaxInt)
  else if Copy(p, 1, 4) = '\\?\' then r := Copy(p, 5, MaxInt)
  else r := p;
  if (Length(r) = 3) and (r[2] = ':') then Exit(True);
  if Copy(r, 1, 2) = '\\' then begin
    n := 0;
    for i := 3 to Length(r) do if r[i] = '\' then Inc(n);
    Exit(n = 2);
  end;
  Result := False;
end;
{$else}
begin
  Result := p = '/';
end;
{$endif}

{ Path::parent: sin el ultimo componente; False si ya es la raiz. }
function Padre(const p: RawByteString; out q: RawByteString): Boolean;
var i: SizeInt;
begin
  q := '';
  if EsRaiz(p) or (p = '') then Exit(False);
  i := Length(p);
  while (i > 0) and (p[i] <> SEP_RUTA) do Dec(i);
  if i = 0 then begin q := ''; Exit(True); end;    { "x" -> "" }
  q := Copy(p, 1, i - 1);
  { el separador de la raiz se queda: "/a" -> "/", "\\?\C:\a" -> "\\?\C:\" }
  if (q = '') or EsRaiz(Copy(p, 1, i)) then q := Copy(p, 1, i);
  { Este Result faltaba: la funcion devolvia lo que quedara en el registro.
    En el diferencial daba "Io(-)" en 1 de cada ~10 corridas, y en DestinoDe
    un falso hacia verificar la contencion contra el destino y no contra el
    padre. FPC no avisa si algun camino hace Exit(valor): resultados.py si. }
  Result := True;
end;

{ Path::starts_with: por componentes, no por bytes ("/tmp/ab" NO empieza
  con "/tmp/a"). Las dos rutas vienen de Canonicalizar: sin separadores
  repetidos ni finales salvo el de la raiz. }
function EmpiezaCon(const p, base: RawByteString): Boolean;
begin
  if base = '' then Exit(False);
  if EsRaiz(base) then Exit(Copy(p, 1, Length(base)) = base);
  Result := (p = base) or ((Length(p) > Length(base)) and (Copy(p, 1, Length(base)) = base)
                           and (p[Length(base) + 1] = SEP_RUTA));
end;

{ Unidades UTF-16 de la ruta, como to_string_lossy().encode_utf16().count():
  una secuencia UTF-8 invalida cuenta como un U+FFFD por cada "subparte
  maximal" (la regla de Unicode que sigue Rust), y lo que esta fuera del BMP
  cuenta 2. Sin el prefijo \\?\, y \\?\UNC\x cuenta como \\x. }
function LargoWindows(const p: RawByteString): SizeInt;
var i, n, k, falta: SizeInt; b, lo, hi: Byte; ini: SizeInt;
begin
  ini := 1; Result := 0;
  if Copy(p, 1, 8) = '\\?\UNC\' then begin ini := 9; Result := 2; end
  else if Copy(p, 1, 4) = '\\?\' then ini := 5;
  n := Length(p); i := ini;
  while i <= n do begin
    b := Ord(p[i]);
    if b < $80 then begin Inc(Result); Inc(i); Continue; end;
    lo := $80; hi := $BF;
    case b of
      $C2..$DF: falta := 1;
      $E0: begin falta := 2; lo := $A0; end;
      $E1..$EC, $EE..$EF: falta := 2;
      $ED: begin falta := 2; hi := $9F; end;
      $F0: begin falta := 3; lo := $90; end;
      $F1..$F3: falta := 3;
      $F4: begin falta := 3; hi := $8F; end;
    else
      Inc(Result); Inc(i); Continue;          { byte que no puede empezar nada }
    end;
    k := 1;
    while k <= falta do begin
      if i + k > n then Break;
      b := Ord(p[i + k]);
      if (b < lo) or (b > hi) then Break;
      lo := $80; hi := $BF;                    { solo el segundo byte tiene rango especial }
      Inc(k);
    end;
    if k > falta then begin
      if falta = 3 then Inc(Result, 2) else Inc(Result);
      Inc(i, falta + 1);
    end else begin
      Inc(Result);                             { un U+FFFD por la subparte maximal }
      Inc(i, k);
    end;
  end;
end;

{ ------------------------------------------------------------------------ }

function DestinoDe(const destino: RawByteString; const nombre: TBytes; rutas, sobrescribir: Boolean;
                   out rutaFinal: RawByteString): TResultadoExtraccion;
var v: TVeredicto; s, base, candidato, padreC, padreR, q, sig: RawByteString; i, ini: SizeInt; c: RawByteString;
begin
  rutaFinal := '';
  if rutas then v := Ruta(nombre) else v := Plano(nombre);
  if v.tipo = vRechazo then Exit(RE(exNombreInvalido));
  { POLITICA.md 3.2: lo que solo es ilegal en Windows se rechaza al extraer EN Windows. }
  {$ifdef MSWINDOWS}
  if v.tipo = vSoloWindows then Exit(RE(exNombreInvalido));
  {$endif}
  if not Utf8Valido(nombre) then Exit(RE(exNombreInvalido));
  SetLength(s, Length(nombre));
  if Length(nombre) > 0 then Move(nombre[0], s[1], Length(nombre));

  { Ningun componente puede ser `..`, `.`, vacio ni raiz. Redundante con la
    validacion, a proposito. }
  ini := 1;
  for i := 1 to Length(s) + 1 do
    if (i > Length(s)) or (s[i] = '/') then begin
      c := Copy(s, ini, i - ini);
      if (c = '') or (c = '.') or (c = '..') then Exit(RE(exEscapaDelDestino));
      ini := i + 1;
    end;

  { Contencion real: contra el destino YA resuelto. }
  if not Canonicalizar(destino, base) then Exit(RE(exDestinoNoEsDirectorio));
  if not EsDirectorio(base) then Exit(RE(exDestinoNoEsDirectorio));

  { Componente por componente: en Windows `base` trae \\?\ y con ese prefijo
    el sistema ya no traduce '/'. }
  candidato := base;
  ini := 1;
  for i := 1 to Length(s) + 1 do
    if (i > Length(s)) or (s[i] = '/') then begin
      if not EsRaiz(candidato) then candidato := candidato + SEP_RUTA;
      candidato := candidato + Copy(s, ini, i - ini);
      ini := i + 1;
    end;

  if not Padre(candidato, padreC) then padreC := base;
  if not Canonicalizar(padreC, padreR) then begin
    { El padre no existe todavia: se resuelve el ancestro mas cercano que si. }
    q := padreC;
    repeat
      if not Padre(q, sig) then Exit(RE(exEscapaDelDestino));
      q := sig;
    until Canonicalizar(q, padreR);
  end;
  if not EmpiezaCon(padreR, base) then Exit(RE(exEscapaDelDestino));

  { Limite de Windows, sobre la ruta resuelta, en unidades UTF-16. }
  i := LargoWindows(candidato);
  if i > MAX_PATH_WINDOWS then Exit(RE(exRutaMuyLargaParaWindows, i));

  { El ultimo componente, SIN seguir enlaces: un enlace colgante ocupa el nombre. }
  if ExisteEntrada(candidato) and not sobrescribir then Exit(RE(exDestinoYaExiste));
  rutaFinal := candidato;
  Result := RE(exNinguno);
end;

{ fs::create_dir_all, el mismo algoritmo: mkdir; si falta el padre, crear el
  padre y reintentar; si mkdir falla pero ya es un directorio, alcanza. }
function CrearDirectorios(const p: RawByteString; out codigo: LongInt): Boolean;
var q: RawByteString;
begin
  codigo := 0;
  if p = '' then Exit(True);
  if CrearDir(p) then Exit(True);
  codigo := UltimoError;
  if (codigo <> E_NO_EXISTE) and (codigo <> E_NO_EXISTE2) then begin
    Result := EsDirectorio(p);
    if Result then codigo := 0;
    Exit;
  end;
  if not Padre(p, q) then begin codigo := -1; Exit(False); end;
  if not CrearDirectorios(q, codigo) then Exit(False);
  if CrearDir(p) then begin codigo := 0; Exit(True); end;
  codigo := UltimoError;
  Result := EsDirectorio(p);
  if Result then codigo := 0;
end;

{ Primer `<ruta>.corrupto[.N]` libre, mirando la entrada y no lo que apunta. }
function RutaCorruptaLibre(const archivo: RawByteString; out r: RawByteString): Boolean;
var n: Integer;
begin
  r := archivo + '.corrupto';
  if not ExisteEntrada(r) then Exit(True);
  for n := 1 to 999 do begin
    r := archivo + '.corrupto.' + IntToStr(n);
    if not ExisteEntrada(r) then Exit(True);
  end;
  r := '';
  Result := False;
end;

function EscribirVerificado(const archivo: RawByteString; const datos: TBytes; const esperado: THash16;
                            siFalla: TSiFalla; sobrescribir: Boolean; out d: TDesenlace): TResultadoFs;
var p, otro: RawByteString; codigo: LongInt; f: TArchivo; obtenido: THash16;
begin
  d.tipo := deVerificado; d.ruta := '';
  FillChar(d.esperado, SizeOf(d.esperado), 0); FillChar(d.obtenido, SizeOf(d.obtenido), 0);
  if Pos(#0, archivo) > 0 then Exit(RF(efIo, -1));
  if Padre(archivo, p) then
    if not CrearDirectorios(p, codigo) then Exit(RF(efIo, codigo));
  if sobrescribir then
    if not Borrar(archivo) then begin
      codigo := UltimoError;
      if (codigo <> E_NO_EXISTE) and (codigo <> E_NO_EXISTE2) then Exit(RF(efIo, codigo));
    end;
  { Si no se pudo crear no hay nada nuestro que borrar. }
  if not CrearNuevo(archivo, f) then Exit(RF(efIo, UltimoError));
  if not EscribirTodo(f, datos) then begin
    codigo := UltimoError;
    if codigo = 0 then codigo := -1;
    Cerrar(f);
    Borrar(archivo);                     { una escritura a medias no se deja tirada }
    Exit(RF(efIo, codigo));
  end;
  Cerrar(f);

  obtenido := Blake3_128(datos);
  if CompareMem(@obtenido[0], @esperado[0], SizeOf(THash16)) then begin
    d.tipo := deVerificado; d.ruta := archivo;
    Exit(RF(efNinguno, 0));
  end;
  d.esperado := esperado; d.obtenido := obtenido;

  if siFalla = sfBorrar then begin
    if not Borrar(archivo) then Exit(RF(efIo, UltimoError));
    d.tipo := deBorrado;
    Exit(RF(efNinguno, 0));
  end;
  if not RutaCorruptaLibre(archivo, otro) then begin
    Borrar(archivo);
    Exit(RF(efNoSePudoConservar, -1));
  end;
  if not Renombrar(archivo, otro) then begin
    codigo := UltimoError;
    Borrar(archivo);
    Exit(RF(efNoSePudoConservar, codigo));
  end;
  d.tipo := deConservado; d.ruta := otro;
  Result := RF(efNinguno, 0);
end;

end.
