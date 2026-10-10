{ Espejo de pjacore/examples/dif_corrupcion.rs: arma el mismo contenedor desde
  los mismos .pjg reales, aplica cada celda de casos.txt y dice lo que dice
  pjaindice.LeerIndice, con el mismo formato.

    dif_corrupcion <dir_pjg> <casos.txt> }
program dif_corrupcion;
{$I pja.inc}
uses SysUtils, Classes, pjacripto, pjaindice, pjaescritor;

const DIG: array[0..15] of Char = '0123456789abcdef';
function AHex(const b: array of Byte): string;
var i: SizeInt;
begin
  SetLength(Result, 2 * Length(b));
  for i := 0 to High(b) do begin
    Result[2 * i + 1] := DIG[b[i] shr 4];
    Result[2 * i + 2] := DIG[b[i] and 15];
  end;
end;

function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;

{ El mismo contenedor que corrupcion::bateria::contenedor_real: los 6 primeros
  .pjg por nombre, tam_orig = 2 x payload. }
function ContenedorReal(const dir: string): TBytes;
var archivos: TStringList; sr: TSearchRec; e: TEntradas; av: TAvisos; i: Integer; r: TResultadoEscritura;
begin
  archivos := TStringList.Create; archivos.Sorted := True;   { mismo orden que el sort() del Rust }
  archivos.CaseSensitive := True; archivos.UseLocale := False;
  try
    if FindFirst(IncludeTrailingPathDelimiter(dir) + '*.pjg', faAnyFile, sr) = 0 then begin
      repeat archivos.Add(IncludeTrailingPathDelimiter(dir) + sr.Name); until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    if archivos.Count < 6 then raise Exception.CreateFmt('hacen falta 6 .pjg en %s', [dir]);
    e := nil; SetLength(e, 6);
    for i := 0 to 5 do begin
      e[i].payload := Leer(archivos[i]);
      e[i].nombre := nil; SetLength(e[i].nombre, Length(ExtractFileName(archivos[i])));
      Move(ExtractFileName(archivos[i])[1], e[i].nombre[0], Length(e[i].nombre));
      e[i].tam_orig := QWord(Length(e[i].payload)) * 2;
      e[i].hash := Blake3_128(e[i].payload);
    end;
  finally archivos.Free; end;
  r := Escribir(e, 0, Result, av);
  if not r.Ok then raise Exception.Create('escribir: ' + r.Texto);
end;

procedure Resellar(var c: TBytes);
var ti: QWord; h: THash16;
begin
  if Length(c) < TAM_CABECERA then Exit;
  ti := QWord(c[8]) or (QWord(c[9]) shl 8) or (QWord(c[10]) shl 16) or (QWord(c[11]) shl 24);
  if TAM_CABECERA + ti > QWord(Length(c)) then Exit;
  h := HashCabeceraIndice(c, TAM_CABECERA, ti);
  Move(h[0], c[12], 16);
end;

function Texto(const c: TContenedor): string;
var k: SizeInt;
begin
  Result := 'Ok flags=' + IntToStr(c.flags) + ' n=' + IntToStr(Length(c.miembros)) + ' ';
  for k := 0 to High(c.miembros) do
    with c.miembros[k] do
      Result := Result + AHex(nombre) + ':' + IntToStr(tam_orig) + ':' + IntToStr(tam_payload)
                + ':' + AHex(hash) + ':' + IntToStr(m_flags) + ';';
end;

var
  f, o: TextFile; l, orig, t: string; w: TStringArray; base, d: TBytes; c: TContenedor; r: TResultado;
  a: SizeInt; bufIn: array[0..1 shl 16 - 1] of Byte; bufOut: array[0..65535] of Byte;
begin
  if ParamCount <> 2 then begin Writeln(StdErr, 'uso: dif_corrupcion <dir_pjg> <casos.txt>'); Halt(2); end;
  base := ContenedorReal(ParamStr(1));
  r := LeerIndice(base, c);
  if not r.Ok then raise Exception.Create('el contenedor base no se lee: ' + r.Texto);
  orig := Texto(c);
  AssignFile(f, ParamStr(2)); SetTextBuf(f, bufIn, SizeOf(bufIn)); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l);
    w := l.Split(' ');
    if w[0] = 'base' then begin
      WriteLn(o, 'len:', Length(base), ' b3:', AHex(Blake3_128(base)));
      Continue;
    end;
    a := StrToInt64(w[1]);
    d := Copy(base, 0, Length(base));
    case w[0] of
      'x': d[a] := d[a] xor (1 shl StrToInt(w[2]));
      'r': begin d[a] := d[a] xor (1 shl StrToInt(w[2])); Resellar(d); end;
      'v': d[a] := StrToInt(w[2]);
      't': begin if (a < 0) or (a > Length(d)) then raise ERangeError.Create('t'); SetLength(d, a); end;
      'a': begin SetLength(d, Length(d) + a); FillChar(d[Length(base)], a, 0); end;
    else raise Exception.Create('celda desconocida: ' + l);
    end;
    r := LeerIndice(d, c);
    if not r.Ok then WriteLn(o, r.Texto)
    else begin
      t := Texto(c);
      if t = orig then WriteLn(o, 'igual') else WriteLn(o, t);
    end;
  end;
  CloseFile(f); Close(o);
end.
