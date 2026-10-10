{ Port de las pruebas de pjafs/src/lib.rs (bateria 4.5 de doc/FORMATO.md),
  mas las de las dos piezas que en Rust da la std y aca son nuestras: el
  conteo UTF-16 de LargoWindows y la contencion por componentes.

    prueba_pjafs <dir_temporal>   (se crea y se borra pjafs_* adentro; ruta ya resuelta,
                                   sin enlaces: se compara contra lo que devuelve DestinoDe) }
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
function Canon(const d: string): string;
begin
  { el destino resuelto: lo que devuelve DestinoDe para el nombre vacio no
    existe, asi que se resuelve uno real y se le saca el ultimo componente }
  Result := ExpandFileName(d);
end;

var d, afuera, n, nombre, justo: string; p, q: RawByteString; r: TResultadoExtraccion; f: TResultadoFs;
    des: TDesenlace; i: Integer; ajeno, hBueno: THash16; base: RawByteString;
const PELIGROSOS: array[0..2] of string = ('../fuera.jpg', '/etc/passwd', 'a/../../b.jpg');
      TEMPORALES: array[0..18] of string = ('ok', 'symlink', 'symlink_afuera', 'symlink_ok', 'largo', 'existe',
        'verif', 'conservar', 'peligro', 'final_afuera', 'final_afuera_x', 'colgante', 'colgante_x', 'duro',
        'duro_x', 'ajeno', 'relativo', 'corrupto_enlace', 'solowin');
begin
  celdas := 0; fallas := 0;
  if ParamCount < 1 then begin Writeln('uso: prueba_pjafs <dir_temporal>'); Halt(2); end;
  TMP := ParamStr(1);

  Writeln('--- LargoWindows: unidades UTF-16, U+FFFD por subparte maximal');
  Ch(LargoWindows('abc') = 3, 'ASCII');
  Ch(LargoWindows(#$C3#$B1) = 1, 'n con tilde: 2 bytes, 1 unidad');
  Ch(LargoWindows(#$F0#$9F#$98#$80) = 2, 'emoji: 4 bytes, 2 unidades (par subrogado)');
  Ch(LargoWindows('\\?\C:\x') = 4, 'el prefijo \\?\ no cuenta');
  Ch(LargoWindows('\\?\UNC\s\r') = 5, '\\?\UNC\s\r cuenta como \\s\r');
  Ch(LargoWindows(#$FF) = 1, 'byte invalido: 1');
  Ch(LargoWindows(#$E1#$80'x') = 2, 'secuencia cortada: 1 por la subparte + x');
  Ch(LargoWindows(#$E0#$80) = 2, 'E0 80: el segundo fuera de rango, 2 reemplazos');
  Ch(LargoWindows(#$ED#$A0#$80) = 3, 'subrogado codificado: 3 reemplazos');
  Ch(LargoWindows(#$F0#$9F#$98) = 1, 'emoji truncado al final: 1');
  Ch(LargoWindows(#$F4#$90#$80#$80) = 4, 'mayor que U+10FFFF: 4');

  Writeln('--- EmpiezaCon: por componentes, no por bytes');
  {$ifndef MSWINDOWS}
  Ch(EmpiezaCon('/tmp/a/b', '/tmp/a'), '/tmp/a/b empieza con /tmp/a');
  Ch(EmpiezaCon('/tmp/a', '/tmp/a'), 'igual');
  Ch(not EmpiezaCon('/tmp/ab', '/tmp/a'), '/tmp/ab NO empieza con /tmp/a');
  Ch(EmpiezaCon('/x', '/'), 'todo empieza con /');
  Ch(not EmpiezaCon('/tmp', '/tmp/a'), 'el padre no empieza con el hijo');
  {$else}
  Ch(EmpiezaCon('\\?\C:\a\b', '\\?\C:\a'), 'C:\a\b empieza con C:\a');
  Ch(not EmpiezaCon('\\?\C:\ab', '\\?\C:\a'), 'C:\ab NO empieza con C:\a');
  Ch(EmpiezaCon('\\?\C:\x', '\\?\C:\'), 'todo empieza con la raiz');
  {$endif}

  Writeln('--- Padre: Path::parent');
  {$ifndef MSWINDOWS}
  { Padre devolvia basura en el camino normal (faltaba Result := True): en este
    binario daba falso 1000 de 1000 llamando directo. }
  Ch(Padre('/a/b/c', q) and (q = '/a/b'), '/a/b/c -> /a/b');
  Ch(Padre('/a', q) and (q = '/'), '/a -> /');
  Ch(not Padre('/', q), '/ no tiene padre');
  Ch(not Padre('', q), 'vacio no tiene padre');
  Ch(Padre('x', q) and (q = ''), 'x -> vacio, como Path::parent');
  {$else}
  Ch(Padre('\\?\C:\a\b', q) and (q = '\\?\C:\a'), 'C:\a\b -> C:\a');
  Ch(Padre('\\?\C:\a', q) and (q = '\\?\C:\'), 'C:\a -> la raiz');
  Ch(not Padre('\\?\C:\', q), 'la raiz no tiene padre');
  Ch(Padre('\\?\UNC\srv\rec\a', q) and (q = '\\?\UNC\srv\rec\'), 'UNC: \\srv\rec\a -> \\srv\rec\');
  Ch(not Padre('\\?\UNC\srv\rec\', q), 'UNC: el recurso es la raiz');
  Ch(Padre('C:\a', q) and (q = 'C:\'), 'sin prefijo: C:\a -> C:\');
  {$endif}

  Writeln('--- control_positivo_un_nombre_normal_resuelve');
  d := Temporal('ok');
  r := DestinoDe(d, B('foto.jpg'), False, False, p);
  Ch(r.Ok, 'resuelve');
  Ch(ExtractFileName(p) = 'foto.jpg', 'el ultimo componente es foto.jpg');
  { en Windows la ruta resuelta trae \\?\ (GetFinalPathNameByHandle, como Rust) }
  if Copy(p, 1, 4) = '\\?\' then q := Copy(p, 5, MaxInt) else q := p;
  Ch(Copy(q, 1, Length(Canon(d))) = Canon(d), 'cuelga del destino resuelto');

  {$ifndef MSWINDOWS}
  Writeln('--- enlace_simbolico_que_sale_afuera_se_rechaza');
  d := Temporal('symlink'); afuera := Temporal('symlink_afuera');
  Enlace(afuera, d + '/sub');
  Ch(DestinoDe(d, B('sub/foto.jpg'), True, False, p).error = exEscapaDelDestino, 'nombre impecable sobre enlace afuera: rechaza');

  Writeln('--- enlace_simbolico_que_queda_adentro_se_acepta');
  d := Temporal('symlink_ok');
  ForceDirectories(d + '/real'); Enlace(d + '/real', d + '/sub');
  Ch(DestinoDe(d, B('sub/foto.jpg'), True, False, p).Ok, 'enlace adentro: acepta (control negativo)');
  {$endif}

  Writeln('--- ruta_muy_larga_para_windows_se_rechaza_sin_truncar');
  d := Temporal('largo');
  n := StringOfChar('a', 250) + '.jpg';
  r := DestinoDe(d, B(n), False, False, p);
  Ch((r.error = exRutaMuyLargaParaWindows) and (r.largo > MAX_PATH_WINDOWS), 'rechaza por largo: ' + r.Texto);

  Writeln('--- destino_existente_se_rechaza_salvo_que_se_pida');
  d := Temporal('existe');
  Poner(d + '/foto.jpg', 'x');
  Ch(DestinoDe(d, B('foto.jpg'), False, False, p).error = exDestinoYaExiste, 'existe: rechaza');
  Ch(DestinoDe(d, B('foto.jpg'), False, True, p).Ok, 'con sobrescribir: acepta');

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

  Writeln('--- nombres_peligrosos_no_llegan_ni_a_resolverse');
  d := Temporal('peligro');
  for i := 0 to High(PELIGROSOS) do
    Ch(DestinoDe(d, B(PELIGROSOS[i]), True, False, p).error = exNombreInvalido, PELIGROSOS[i] + ': NombreInvalido');

  { --- Defectos medidos el 2026-10-09 en la version Rust anterior. }
  {$ifndef MSWINDOWS}
  Writeln('--- enlace_final_hacia_afuera_no_se_sigue_al_sobrescribir');
  d := Temporal('final_afuera'); afuera := Temporal('final_afuera_x');
  Poner(afuera + '/victima.txt', 'original');
  Enlace(afuera + '/victima.txt', d + '/a.jpg');
  r := DestinoDe(d, B('a.jpg'), False, True, p);
  Ch(r.Ok, 'resuelve con sobrescribir');
  f := EscribirVerificado(p, B('nuevo'), H16('nuevo'), sfBorrar, True, des);
  Ch(f.Ok and (des.tipo = deVerificado), 'Verificado');
  Ch(Leer(afuera + '/victima.txt') = 'original', 'afuera intacto');
  Ch(not EsEnlace(p), 'el enlace se reemplazo');
  Ch(Leer(p) = 'nuevo', 'con el contenido nuevo');

  Writeln('--- enlace_colgante_ocupa_el_nombre');
  d := Temporal('colgante'); afuera := Temporal('colgante_x');
  Enlace(afuera + '/nuevo.txt', d + '/b.jpg');
  Ch(DestinoDe(d, B('b.jpg'), False, False, p).error = exDestinoYaExiste, 'colgante: DestinoYaExiste');
  f := EscribirVerificado(Canon(d) + '/b.jpg', B('x'), H16('x'), sfBorrar, False, des);
  Ch((not f.Ok) and (f.codigo = ESysEEXIST), 'la carrera: Io(EEXIST), ' + f.Texto);
  Ch(not Existe(afuera + '/nuevo.txt'), 'no se creo nada afuera');

  Writeln('--- enlace_duro_no_se_escribe_a_traves');
  d := Temporal('duro'); afuera := Temporal('duro_x');
  Poner(afuera + '/victima.txt', 'original');
  if fpLink(PChar(afuera + '/victima.txt'), PChar(d + '/c.jpg')) <> 0 then raise Exception.Create('link');
  r := DestinoDe(d, B('c.jpg'), False, True, p);
  f := EscribirVerificado(p, B('nuevo'), H16('nuevo'), sfBorrar, True, des);
  Ch(r.Ok and f.Ok, 'escribe');
  Ch(Leer(afuera + '/victima.txt') = 'original', 'afuera intacto');
  {$endif}

  Writeln('--- sin_sobrescribir_un_archivo_ajeno_queda_intacto');
  d := Temporal('ajeno');
  r := DestinoDe(d, B('f.jpg'), False, False, p);
  Ch(r.Ok, 'resuelve');
  Poner(p, 'del usuario');
  f := EscribirVerificado(p, B('x'), H16('x'), sfBorrar, False, des);
  Ch(not f.Ok, 'no escribe: ' + f.Texto);
  Ch(Leer(p) = 'del usuario', 'el archivo del usuario queda intacto');

  Writeln('--- el_largo_se_mide_sobre_la_ruta_resuelta');
  d := Temporal('relativo');
  base := Canon(d);
  nombre := StringOfChar('x', MAX_PATH_WINDOWS - Length(base) - 4) + '.jpg';     { 261 }
  justo := StringOfChar('x', MAX_PATH_WINDOWS - Length(base) - 5) + '.jpg';      { 260 }
  if not SetCurrentDir(ExtractFileDir(base)) then raise Exception.Create('chdir');
  r := DestinoDe(ExtractFileName(base), B(nombre), False, False, p);
  Ch((r.error = exRutaMuyLargaParaWindows) and (r.largo = MAX_PATH_WINDOWS + 1), 'relativo, 261: ' + r.Texto);
  Ch(DestinoDe(ExtractFileName(base), B(justo), False, False, q).Ok, 'relativo, 260 justo: entra');
  SetCurrentDir(TMP);

  {$ifndef MSWINDOWS}
  Writeln('--- corrupto_ocupado_por_enlace_colgante');
  d := Temporal('corrupto_enlace');
  Enlace(d + '/no_existe', d + '/g.jpg.corrupto');
  f := EscribirVerificado(d + '/g.jpg', B('x'), H16('otro'), sfConservar, False, des);
  Ch(f.Ok and (ExtractFileName(des.ruta) = 'g.jpg.corrupto.1'), 'va a .corrupto.1');
  Ch(EsEnlace(d + '/g.jpg.corrupto'), 'el enlace sigue ahi');
  {$endif}

  {$ifdef MSWINDOWS}
  Writeln('--- en Windows lo SoloWindows se rechaza al extraer (POLITICA 3.2)');
  d := Temporal('solowin');
  Ch(DestinoDe(d, B('CON.jpg'), False, False, p).error = exNombreInvalido, 'CON.jpg');
  Ch(DestinoDe(d, B('foto?.jpg'), False, False, p).error = exNombreInvalido, 'foto?.jpg');
  Ch(DestinoDe(d, B('foto.'), False, False, p).error = exNombreInvalido, 'foto.');
  Ch(DestinoDe(d, B('sub/aux'), True, False, p).error = exNombreInvalido, 'sub/aux');
  Ch(DestinoDe(d, B('foto.jpg'), False, False, p).Ok, 'control: foto.jpg pasa');
  {$else}
  Writeln('--- fuera de Windows lo SoloWindows pasa (POLITICA 3.2)');
  d := Temporal('solowin');
  Ch(DestinoDe(d, B('CON.jpg'), False, False, p).Ok, 'CON.jpg pasa en Linux');
  Ch(DestinoDe(d, B('foto?.jpg'), False, False, p).Ok, 'foto?.jpg pasa en Linux');
  {$endif}

  { arreglo declarado y no `for n in [...]`: con literales, FPC los recorta al largo del primero }
  for i := 0 to High(TEMPORALES) do BorrarArbol(IncludeTrailingPathDelimiter(TMP) + 'pjafs_' + TEMPORALES[i]);

  Writeln;
  Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if (fallas > 0) or (celdas < 40) then Halt(1);
end.
