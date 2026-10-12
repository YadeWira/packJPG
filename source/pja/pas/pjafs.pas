{ Escribir a disco el JPEG reconstruido, sin seguir enlaces y verificando el
  hash. La parte que toca el sistema de archivos, aparte del formato.

  La ruta la elige el usuario, no el archivo: no hay nombres de adentro que
  contener. Lo que queda es no escribir A TRAVES de lo que ya esta en el
  destino -- un enlace simbolico o duro con el nombre de la salida --, no
  dejar escrituras a medias, y no dejar con su nombre un archivo cuyo hash no
  coincide.

  Las rutas son UTF-8 en RawByteString y se tratan como bytes. En Windows se
  pasan a UTF-16 recien al llamar a la API (las funciones W).

  Las llamadas al sistema son las que hacia la std de Rust del modulo de
  referencia (lstat, open O_EXCL, mkdir 0777, rename; en Windows CreateFileW
  CREATE_NEW, MoveFileExW), con los mismos codigos de error. }
unit pjafs;
{$I pja.inc}

interface

uses
  SysUtils, pjacripto;


type
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
    { "Io(13)", "NoSePudoConservar(-)" }
    function Texto: string;
  end;

{ Escribe el archivo y verifica DESPUES de escribir. El archivo se CREA (nunca
  se abre uno existente, y no se siguen enlaces); con `sobrescribir`, la
  entrada que haya se borra antes. }
function EscribirVerificado(const archivo: RawByteString; const datos: TBytes; const esperado: THash16;
                            siFalla: TSiFalla; sobrescribir: Boolean; out d: TDesenlace): TResultadoFs;

{ Expuesta para las pruebas. Path::parent; False en la raiz o con la ruta vacia. }
function Padre(const p: RawByteString; out q: RawByteString): Boolean;

implementation

uses
  {$ifdef MSWINDOWS} Windows {$else} BaseUnix {$endif};

function TResultadoFs.Ok: Boolean; begin Result := error = efNinguno; end;
function TResultadoFs.Texto: string;
const N: array[TErrorFs] of string = ('Ninguno', 'Io', 'NoSePudoConservar');
begin
  Result := N[error];
  if error <> efNinguno then
    if codigo < 0 then Result := Result + '(-)' else Result := Result + '(' + IntToStr(codigo) + ')';
end;

function RF(e: TErrorFs; codigo: LongInt): TResultadoFs;
begin Result.error := e; Result.codigo := codigo; end;

{ ------------------------------------------------------------------------
  Capa de sistema. Todo lo que depende de la plataforma esta aca. }

{$ifdef MSWINDOWS}
const
  FILE_SHARE_DELETE_ = $00000004;
function W(const p: RawByteString): UnicodeString;
begin Result := UTF8Decode(p); end;

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
  {$ifdef linux} O_CLOEXEC_ = $80000; {$else} O_CLOEXEC_ = 0; {$endif}

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

{ La ruta la escribe el usuario: en Windows puede venir con '/' o con '\'. }
function EsSep(c: Char): Boolean; inline;
begin
  {$ifdef MSWINDOWS} Result := (c = '\') or (c = '/'); {$else} Result := c = '/'; {$endif}
end;

{ Raiz: '/' en Unix; en Windows "C:\", "\\srv\rec\", o lo mismo con el
  prefijo "\\?\" (o "\\?\UNC\"). }
function EsRaiz(const p: RawByteString): Boolean;
{$ifdef MSWINDOWS}
var r: RawByteString; i, n: SizeInt;
begin
  { No alcanza con "termina en \": asi el padre de \\?\C:\a\b salia
    \\?\C:\a\ (visto en Windows 10 real). Raiz es X:\ o \\srv\recurso\,
    con o sin el prefijo \\?\ (o \\?\UNC\). }
  if (p = '') or not EsSep(p[Length(p)]) then Exit(False);
  if Copy(p, 1, 8) = '\\?\UNC\' then r := '\\' + Copy(p, 9, MaxInt)
  else if Copy(p, 1, 4) = '\\?\' then r := Copy(p, 5, MaxInt)
  else r := p;
  if (Length(r) = 3) and (r[2] = ':') then Exit(True);
  if (Length(r) >= 2) and EsSep(r[1]) and EsSep(r[2]) then begin
    n := 0;
    for i := 3 to Length(r) do if EsSep(r[i]) then Inc(n);
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
  while (i > 0) and not EsSep(p[i]) do Dec(i);
  if i = 0 then begin q := ''; Exit(True); end;    { "x" -> "" }
  q := Copy(p, 1, i - 1);
  { el separador de la raiz se queda: "/a" -> "/", "\\?\C:\a" -> "\\?\C:\" }
  if (q = '') or EsRaiz(Copy(p, 1, i)) then q := Copy(p, 1, i);
  { Este Result faltaba: la funcion devolvia lo que quedara en el registro.
    En el diferencial contra el Rust daba "Io(-)" en 1 de cada ~10 corridas.
    FPC no avisa si algun camino hace Exit(valor): resultados.py si. }
  Result := True;
end;

{ ------------------------------------------------------------------------ }

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
