{ Escribir la salida sin seguir enlaces, sin escrituras a medias y sin dejar
  con su nombre un archivo cuyo hash no coincide (doc/FORMATO.md 4.5).

    prueba_pjafs <dir_temporal>   (se crea y se borra pjafs_* adentro) }
program prueba_pjafs;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_pjafs: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, {$ifndef MSWINDOWS} BaseUnix, {$endif} pjacripto, pjafs;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:64, '  ok') else begin Inc(fallas); Writeln('  ', q:64, '  FALLA'); end; end;

function B(const s: RawByteString): TBytes;
begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;
function H16(const s: RawByteString): THash16; begin Result := Blake3_128(B(s)); end;
function Leer(const f: string): RawByteString; var st: TFileStream;
begin
  st := TFileStream.Create(f, fmOpenRead or fmShareDenyNone);
  try Result := ''; SetLength(Result, st.Size); if st.Size > 0 then st.ReadBuffer(Result[1], st.Size);
  finally st.Free; end;
end;
procedure Poner(const f: string; const s: RawByteString); var st: TFileStream;
begin
  st := TFileStream.Create(f, fmCreate);
  try if s <> '' then st.WriteBuffer(s[1], Length(s)); finally st.Free; end;
end;
function Existe(const p: string): Boolean;
{$ifndef MSWINDOWS} var st: Stat; {$endif}
begin {$ifdef MSWINDOWS} Result := FileExists(p) or DirectoryExists(p); {$else} Result := fpLstat(PChar(p), st) = 0; {$endif} end;
function EsEnlace(const p: string): Boolean;
{$ifndef MSWINDOWS} var st: Stat; {$endif}
begin {$ifdef MSWINDOWS} Result := False; {$else} Result := (fpLstat(PChar(p), st) = 0) and fpS_ISLNK(st.st_mode); {$endif} end;
procedure Enlace(const objetivo, p: string);
begin {$ifndef MSWINDOWS} if fpSymlink(PChar(objetivo), PChar(p)) <> 0 then raise Exception.Create('symlink ' + p); {$endif} end;

procedure BorrarArbol(const d: string);
var sr: TSearchRec;
begin
  if EsEnlace(d) then begin DeleteFile(d); Exit; end;
  if FindFirst(IncludeTrailingPathDelimiter(d) + '*', faAnyFile or faSymLink, sr) = 0 then begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      if EsEnlace(IncludeTrailingPathDelimiter(d) + sr.Name) then DeleteFile(IncludeTrailingPathDelimiter(d) + sr.Name)
      else if (sr.Attr and faDirectory) <> 0 then BorrarArbol(IncludeTrailingPathDelimiter(d) + sr.Name)
      else DeleteFile(IncludeTrailingPathDelimiter(d) + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(d);
end;

var TMP: string;
function Temporal(const nombre: string): string;
begin
  Result := IncludeTrailingPathDelimiter(TMP) + 'pjafs_' + nombre;
  BorrarArbol(Result);
  if not ForceDirectories(Result) then raise Exception.Create('no pude crear ' + Result);
end;
var d, afuera: string; q: RawByteString; f: TResultadoFs;
    des: TDesenlace; i: Integer; ajeno, hBueno: THash16;
const TEMPORALES: array[0..10] of string = ('verif', 'conservar', 'final_afuera', 'final_afuera_x', 'colgante',
        'colgante_x', 'duro', 'duro_x', 'ajeno', 'corrupto_enlace', 'dirs');
begin
  celdas := 0; fallas := 0;
  if ParamCount < 1 then begin Writeln('uso: prueba_pjafs <dir_temporal>'); Halt(2); end;
  TMP := ParamStr(1);

  Writeln('--- Padre: Path::parent');
  { Padre devolvia basura en el camino normal (faltaba Result := True): en este
    binario daba falso 1000 de 1000 llamando directo. }
  Ch(Padre('x', q) and (q = ''), 'x -> vacio, como Path::parent');
  Ch(not Padre('', q), 'vacio no tiene padre');
  Ch(Padre('a/b', q) and (q = 'a'), 'relativa: a/b -> a');
  {$ifndef MSWINDOWS}
  Ch(Padre('/a/b/c', q) and (q = '/a/b'), '/a/b/c -> /a/b');
  Ch(Padre('/a', q) and (q = '/'), '/a -> /');
  Ch(not Padre('/', q), '/ no tiene padre');
  Ch(Padre('a\b', q) and (q = ''), 'en Unix la barra invertida es parte del nombre');
  {$else}
  Ch(Padre('C:\a\b', q) and (q = 'C:\a'), 'C:\a\b -> C:\a');
  Ch(Padre('C:\a', q) and (q = 'C:\'), 'C:\a -> C:\');
  Ch(not Padre('C:\', q), 'C:\ no tiene padre');
  { la ruta la escribe el usuario: en Windows '/' tambien separa }
  Ch(Padre('C:/a/b', q) and (q = 'C:/a'), 'C:/a/b -> C:/a');
  Ch(Padre('C:/a', q) and (q = 'C:/'), 'C:/a -> C:/');
  Ch(not Padre('C:/', q), 'C:/ no tiene padre');
  Ch(Padre('dir\sub/x.jpg', q) and (q = 'dir\sub'), 'separadores mezclados');
  Ch(Padre('\\?\C:\a', q) and (q = '\\?\C:\'), '\\?\C:\a -> la raiz');
  Ch(Padre('\\?\UNC\srv\rec\a', q) and (q = '\\?\UNC\srv\rec\'), 'UNC: \\srv\rec\a -> \\srv\rec\');
  Ch(not Padre('\\srv\rec\', q), 'UNC sin prefijo: el recurso es la raiz');
  {$endif}

  Writeln('--- hash_que_no_coincide_no_deja_el_archivo_con_su_nombre');
  d := Temporal('verif');
  f := EscribirVerificado(d + '/ok.jpg', B('contenido correcto'), H16('contenido correcto'), sfBorrar, False, des);
  Ch(f.Ok and (des.tipo = deVerificado) and (des.ruta = d + '/ok.jpg'), 'control positivo: Verificado');
  Ch(Leer(d + '/ok.jpg') = 'contenido correcto', 'el caso bueno queda en disco');
  ajeno := H16('otra cosa');
  f := EscribirVerificado(d + '/mal.jpg', B('contenido correcto'), ajeno, sfBorrar, False, des);
  Ch(f.Ok and (des.tipo = deBorrado), 'hash ajeno: Borrado');
  hBueno := H16('contenido correcto');
  Ch(CompareMem(@des.esperado, @ajeno, 16) and CompareMem(@des.obtenido, @hBueno, 16),
     'esperado y obtenido correctos');
  Ch(not Existe(d + '/mal.jpg'), 'el archivo con hash malo no quedo con su nombre');
  f := EscribirVerificado(d + '/vacio.jpg', nil, H16(''), sfBorrar, False, des);
  Ch(f.Ok and (des.tipo = deVerificado) and Existe(d + '/vacio.jpg'), 'cero bytes: se crea y verifica');

  Writeln('--- conservar_renombra_y_nunca_deja_el_nombre_bueno');
  d := Temporal('conservar');
  f := EscribirVerificado(d + '/foto.jpg', B('bytes rescatables'), ajeno, sfConservar, False, des);
  Ch(f.Ok and (des.tipo = deConservado) and (ExtractFileName(des.ruta) = 'foto.jpg.corrupto'), 'Conservado como foto.jpg.corrupto');
  Ch(Leer(d + '/foto.jpg.corrupto') = 'bytes rescatables', 'los bytes sobreviven');
  Ch(not Existe(d + '/foto.jpg'), 'el nombre bueno queda libre');
  f := EscribirVerificado(d + '/foto.jpg', B('otro intento'), ajeno, sfConservar, False, des);
  Ch(f.Ok and (ExtractFileName(des.ruta) = 'foto.jpg.corrupto.1'), 'el segundo va a .corrupto.1');
  Ch(not Existe(d + '/foto.jpg'), 'y el nombre bueno sigue libre');
  Ch(Leer(d + '/foto.jpg.corrupto') = 'bytes rescatables', 'el primer .corrupto no se pisa');

  Writeln('--- sin_sobrescribir_un_archivo_ajeno_queda_intacto');
  d := Temporal('ajeno');
  Poner(d + '/f.jpg', 'del usuario');
  f := EscribirVerificado(d + '/f.jpg', B('x'), H16('x'), sfBorrar, False, des);
  Ch(not f.Ok, 'no escribe: ' + f.Texto);
  Ch(Leer(d + '/f.jpg') = 'del usuario', 'el archivo del usuario queda intacto');
  f := EscribirVerificado(d + '/f.jpg', B('malo'), H16('otro'), sfBorrar, True, des);
  Ch(f.Ok and (des.tipo = deBorrado) and (Leer(d + '/f.jpg') = 'del usuario'),
     'con sobrescribir y hash ajeno: el del usuario queda intacto');
  f := EscribirVerificado(d + '/f.jpg', B('malo'), H16('otro'), sfConservar, True, des);
  Ch(f.Ok and (des.tipo = deConservado) and (Leer(d + '/f.jpg') = 'del usuario')
     and (Leer(d + '/f.jpg.corrupto') = 'malo'), '  y con conservar, tambien: va a .corrupto');
  f := EscribirVerificado(d + '/f.jpg', B('x'), H16('x'), sfBorrar, True, des);
  Ch(f.Ok and (Leer(d + '/f.jpg') = 'x'), 'con sobrescribir: lo reemplaza');
  Ch(not Existe(d + '/f.jpg.pja-tmp0'), '  sin dejar el temporal');
  Poner(d + '/g.jpg.pja-tmp0', 'ocupado');
  f := EscribirVerificado(d + '/g.jpg', B('y'), H16('y'), sfBorrar, True, des);
  Ch(f.Ok and (Leer(d + '/g.jpg') = 'y') and (Leer(d + '/g.jpg.pja-tmp0') = 'ocupado'),
     '  con el temporal 0 ocupado, usa otro y no lo toca');
  ForceDirectories(d + '/carpeta.jpg');
  f := EscribirVerificado(d + '/carpeta.jpg', B('x'), H16('x'), sfBorrar, True, des);
  Ch((not f.Ok) and DirectoryExists(d + '/carpeta.jpg'), 'sobre un directorio, ni con sobrescribir: ' + f.Texto);

  Writeln('--- directorios intermedios');
  d := Temporal('dirs');
  f := EscribirVerificado(d + '/a/b/c/x.jpg', B('x'), H16('x'), sfBorrar, False, des);
  Ch(f.Ok and (Leer(d + '/a/b/c/x.jpg') = 'x'), 'crea los que faltan');
  Poner(d + '/archivo', 'x');
  f := EscribirVerificado(d + '/archivo/x.jpg', B('x'), H16('x'), sfBorrar, False, des);
  Ch(not f.Ok, 'un archivo en el lugar de un directorio: ' + f.Texto);
  if not SetCurrentDir(d) then raise Exception.Create('chdir');
  f := EscribirVerificado('rel.jpg', B('r'), H16('r'), sfBorrar, False, des);
  Ch(f.Ok and (Leer(d + '/rel.jpg') = 'r'), 'ruta relativa, sin directorio');
  f := EscribirVerificado('sub/rel.jpg', B('r'), H16('r'), sfBorrar, False, des);
  Ch(f.Ok and (Leer(d + '/sub/rel.jpg') = 'r'), 'ruta relativa con directorio');
  SetCurrentDir(TMP);

  { --- Defectos medidos el 2026-10-09 en la version Rust anterior. }
  {$ifndef MSWINDOWS}
  Writeln('--- enlace_final_hacia_afuera_no_se_sigue_al_sobrescribir');
  d := Temporal('final_afuera'); afuera := Temporal('final_afuera_x');
  Poner(afuera + '/victima.txt', 'original');
  Enlace(afuera + '/victima.txt', d + '/a.jpg');
  f := EscribirVerificado(d + '/a.jpg', B('nuevo'), H16('nuevo'), sfBorrar, False, des);
  Ch(not f.Ok, 'sin sobrescribir: el enlace ocupa el nombre, ' + f.Texto);
  Ch(Leer(afuera + '/victima.txt') = 'original', '  afuera intacto');
  f := EscribirVerificado(d + '/a.jpg', B('nuevo'), H16('nuevo'), sfBorrar, True, des);
  Ch(f.Ok and (des.tipo = deVerificado), 'con sobrescribir: Verificado');
  Ch(Leer(afuera + '/victima.txt') = 'original', '  afuera intacto');
  Ch(not EsEnlace(d + '/a.jpg'), '  el enlace se reemplazo');
  Ch(Leer(d + '/a.jpg') = 'nuevo', '  con el contenido nuevo');

  Writeln('--- enlace_colgante_ocupa_el_nombre');
  d := Temporal('colgante'); afuera := Temporal('colgante_x');
  Enlace(afuera + '/nuevo.txt', d + '/b.jpg');
  f := EscribirVerificado(d + '/b.jpg', B('x'), H16('x'), sfBorrar, False, des);
  Ch((not f.Ok) and (f.codigo = ESysEEXIST), 'Io(EEXIST), ' + f.Texto);
  Ch(not Existe(afuera + '/nuevo.txt'), 'no se creo nada afuera');

  Writeln('--- enlace_duro_no_se_escribe_a_traves');
  d := Temporal('duro'); afuera := Temporal('duro_x');
  Poner(afuera + '/victima.txt', 'original');
  if fpLink(PChar(afuera + '/victima.txt'), PChar(d + '/c.jpg')) <> 0 then raise Exception.Create('link');
  f := EscribirVerificado(d + '/c.jpg', B('nuevo'), H16('nuevo'), sfBorrar, True, des);
  Ch(f.Ok, 'escribe');
  Ch(Leer(afuera + '/victima.txt') = 'original', 'afuera intacto');

  Writeln('--- corrupto_ocupado_por_enlace_colgante');
  d := Temporal('corrupto_enlace');
  Enlace(d + '/no_existe', d + '/g.jpg.corrupto');
  f := EscribirVerificado(d + '/g.jpg', B('x'), H16('otro'), sfConservar, False, des);
  Ch(f.Ok and (ExtractFileName(des.ruta) = 'g.jpg.corrupto.1'), 'va a .corrupto.1');
  Ch(EsEnlace(d + '/g.jpg.corrupto'), 'el enlace sigue ahi');
  {$endif}

  { arreglo declarado y no `for n in [...]`: con literales, FPC los recorta al largo del primero }
  for i := 0 to High(TEMPORALES) do BorrarArbol(IncludeTrailingPathDelimiter(TMP) + 'pjafs_' + TEMPORALES[i]);

  Writeln;
  Writeln(celdas, ' celdas, ', fallas, ' fallas');
  {$ifdef MSWINDOWS} if (fallas > 0) or (celdas < 30) then Halt(1);
  {$else} if (fallas > 0) or (celdas < 39) then Halt(1); {$endif}
end.
