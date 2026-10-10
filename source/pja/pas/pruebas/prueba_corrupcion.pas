{ Port de la bateria de pjacore/src/corrupcion.rs: un contenedor valido armado
  con .pjg reales, danado sistematicamente.

  Con la invariante que faltaba en todos los barridos: los baldes suman la
  cuenta de celdas, y una celda saltada hace fallar la corrida. Las cuentas se
  imprimen con el mismo formato que el Debug del Rust, para compararlas a ojo;
  la comparacion celda por celda la hace diferencial/dif_corrupcion. }
program prueba_corrupcion;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_corrupcion: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, pjacripto, pjaindice, pjaescritor;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:60, '  ok') else begin Inc(fallas); Writeln('  ', q:60, '  FALLA'); end; end;

function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;

type
  TCuenta = record celdas, rechaza, lee_igual, lee_distinto, saltadas: SizeInt; end;

{ Los baldes tienen que sumar las celdas. Sin esto, una clase nueva se cae de
  la tabla y el numero impreso sigue pareciendo razonable. }
function Cuadra(const c: TCuenta): Boolean;
begin Result := c.rechaza + c.lee_igual + c.lee_distinto + c.saltadas = c.celdas; end;

function Debug(const c: TCuenta): string;
begin
  Result := Format('Cuenta { celdas: %d, rechaza: %d, lee_igual: %d, lee_distinto: %d, saltadas: %d }',
                   [c.celdas, c.rechaza, c.lee_igual, c.lee_distinto, c.saltadas]);
end;

function IgualesB(const a, b: TBytes): Boolean;
begin Result := (Length(a) = Length(b)) and ((Length(a) = 0) or CompareMem(@a[0], @b[0], Length(a))); end;

function IgualesM(const a, b: TMiembro): Boolean;
begin
  Result := IgualesB(a.nombre, b.nombre) and (a.tam_orig = b.tam_orig) and (a.tam_payload = b.tam_payload)
            and CompareMem(@a.hash, @b.hash, SizeOf(a.hash)) and (a.m_flags = b.m_flags);
end;

{ a.flags == b.flags && a.miembros == b.miembros }
function Iguales(const a, b: TContenedor): Boolean; var i: SizeInt;
begin
  Result := (a.flags = b.flags) and (Length(a.miembros) = Length(b.miembros));
  if Result then for i := 0 to High(a.miembros) do
    if not IgualesM(a.miembros[i], b.miembros[i]) then Exit(False);
end;

var archivos: TStringList;
procedure ContenedorReal(out bytes: TBytes; out c: TContenedor);
var e: TEntradas; av: TAvisos; i: Integer; r: TResultadoEscritura; n: string; ri: TResultado;
begin
  if archivos.Count < 6 then raise Exception.CreateFmt('el corpus tiene %d .pjg y la prueba necesita 6', [archivos.Count]);
  e := nil; SetLength(e, 6);
  for i := 0 to 5 do begin
    e[i].payload := Leer(archivos[i]);
    n := ExtractFileName(archivos[i]);
    e[i].nombre := nil; SetLength(e[i].nombre, Length(n)); Move(n[1], e[i].nombre[0], Length(n));
    e[i].tam_orig := QWord(Length(e[i].payload)) * 2;
    e[i].hash := Blake3_128(e[i].payload);
  end;
  r := Escribir(e, 0, bytes, av);
  if not r.Ok then raise Exception.Create('escribir: ' + r.Texto);
  ri := LeerIndice(bytes, c);
  if not ri.Ok then raise Exception.Create('leer_indice del contenedor real: ' + ri.Texto);
end;

function Region(p, finIndice: SizeInt): string;
begin
  if p < 4 then Result := 'magia' else if p = 4 then Result := 'version' else if p = 5 then Result := 'flags'
  else if p < 8 then Result := 'reservado' else if p < 12 then Result := 'tam_indice'
  else if p < 28 then Result := 'hash_indice' else if p < finIndice then Result := 'indice' else Result := 'payload';
end;

procedure ContarLectura(const d: TBytes; const orig: TContenedor; var c: TCuenta; p, bit, finIndice: SizeInt);
var leido: TContenedor;
begin
  if not LeerIndice(d, leido).Ok then Inc(c.rechaza)
  else if Iguales(orig, leido) then Inc(c.lee_igual)
  else begin
    Inc(c.lee_distinto);
    Writeln('  LEE_DISTINTO en ', Region(p, finIndice), ' offset ', p, ' bit ', bit);
  end;
end;

const BITS: array[0..2] of Byte = (0, 3, 7);
var dir: string; sr: TSearchRec; base, d: TBytes; orig, ctl: TContenedor; c: TCuenta;
    fl: Byte; ti: LongWord; h: THash16; finIndice, p, k, paso: SizeInt; bit: Byte;
    posiciones, cortes: array of SizeInt;
begin
  celdas := 0; fallas := 0; dir := ParamStr(1);
  archivos := TStringList.Create; archivos.Sorted := True;   { mismo orden que el sort() del Rust }
  archivos.CaseSensitive := True; archivos.UseLocale := False;
  if FindFirst(IncludeTrailingPathDelimiter(dir) + '*.pjg', faAnyFile, sr) = 0 then begin
    repeat archivos.Add(IncludeTrailingPathDelimiter(dir) + sr.Name); until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  if archivos.Count < 6 then begin Writeln('FALLA: hacen falta 6 .pjg en "', dir, '" (make pja-corpus)'); Halt(2); end;

  Writeln('--- corrupcion_de_un_bit_en_todo_el_contenedor');
  ContenedorReal(base, orig);
  Ch(LeerCabecera(base, fl, ti, h).Ok, 'leer la cabecera del contenedor real');
  finIndice := TAM_CABECERA + SizeInt(ti);
  { La fila conocida: el contenedor intacto se lee. }
  Ch(LeerIndice(base, ctl).Ok and Iguales(orig, ctl), 'control positivo: el intacto se lee igual');

  { Un bit dado vuelta en cada byte de la cabecera y del indice, y en una
    muestra del payload. }
  posiciones := nil;
  for p := 0 to finIndice - 1 do begin SetLength(posiciones, Length(posiciones) + 1); posiciones[High(posiciones)] := p; end;
  p := finIndice;
  while p < Length(base) do begin
    SetLength(posiciones, Length(posiciones) + 1); posiciones[High(posiciones)] := p; Inc(p, 9973);
  end;

  c := Default(TCuenta);
  for p in posiciones do
    for bit in BITS do begin
      Inc(c.celdas);
      d := Copy(base, 0, Length(base));
      d[p] := d[p] xor (1 shl bit);
      ContarLectura(d, orig, c, p, bit, finIndice);
    end;
  Writeln('  ', Debug(c));
  Ch(c.celdas = 3 * Length(posiciones), Format('%d posiciones x 3 bits = %d celdas', [Length(posiciones), c.celdas]));
  Ch(Cuadra(c), 'los baldes suman las celdas');
  Ch(c.saltadas = 0, 'ninguna celda se cayo de la tabla');
  { El Rust solo lo imprime; aca se exige: con el hash sobre cabecera e indice,
    leer algo distinto sin rechazar haria falta una colision. }
  Ch(c.lee_distinto = 0, Format('lee_distinto = %d (integridad del indice)', [c.lee_distinto]));
  { Los que se leen igual son bits en el payload, que leer_indice no mira. }
  Ch(c.lee_igual <= 3 * (Length(posiciones) - finIndice), Format('lee_igual = %d, todos en el payload', [c.lee_igual]));

  Writeln('--- truncacion_en_cada_region');
  c := Default(TCuenta);
  cortes := nil;
  for k := 0 to 63 do begin SetLength(cortes, Length(cortes) + 1); cortes[High(cortes)] := k; end;
  paso := Length(base) div 40; k := 64;
  while k < Length(base) do begin
    SetLength(cortes, Length(cortes) + 1); cortes[High(cortes)] := k; Inc(k, paso);
  end;
  for k in cortes do begin
    Inc(c.celdas);
    d := Copy(base, 0, k);
    if not LeerIndice(d, ctl).Ok then Inc(c.rechaza)
    else Inc(c.lee_distinto);   { leer un truncado es fallo }
  end;
  Writeln('  truncacion: ', Debug(c));
  Ch(Cuadra(c), 'los baldes suman las celdas');
  Ch(c.lee_distinto = 0, 'un contenedor truncado nunca debe leerse');
  Ch(c.rechaza = Length(cortes), Format('%d de %d cortes rechazados', [c.rechaza, Length(cortes)]));

  archivos.Free;
  Writeln;
  Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if (fallas > 0) or (celdas < 10) then Halt(1);
end.
