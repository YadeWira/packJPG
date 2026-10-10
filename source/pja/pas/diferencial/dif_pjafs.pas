{ Espejo de pjafs/examples/dif_pjafs.rs: corre los casos contra el arbol de
  escenarios ya preparado y vuelca lo mismo, con el mismo formato.

    dif_pjafs <raiz> <casos.txt> }
program dif_pjafs;
{$I pja.inc}
uses SysUtils, pjacripto, pjanombres, pjafs;

function ValorHex(c: Char): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
  else raise Exception.Create('hex invalido');
  end;
end;
function DeHex(const s: string): TBytes;
var i: SizeInt;
begin
  Result := nil;
  if s = '-' then Exit;
  SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := (ValorHex(s[2 * i + 1]) shl 4) or ValorHex(s[2 * i + 2]);
end;
function HexCad(const s: string): RawByteString;
var b: TBytes;
begin
  b := DeHex(s); Result := '';
  SetLength(Result, Length(b));
  if Length(b) > 0 then Move(b[0], Result[1], Length(b));
end;
const DIG: array[0..15] of Char = '0123456789abcdef';
function AHex(const b: array of Byte): string;
var i: SizeInt;
begin
  SetLength(Result, 2 * Length(b));
  for i := 0 to High(b) do begin Result[2 * i + 1] := DIG[b[i] shr 4]; Result[2 * i + 2] := DIG[b[i] and 15]; end;
end;
function AHexS(const s: RawByteString): string;
var b: TBytes;
begin
  b := nil; SetLength(b, Length(s));
  if s <> '' then Move(s[1], b[0], Length(s));
  Result := AHex(b);
end;

var raiz: RawByteString;
{ La ruta con la raiz reemplazada por R; en hex si no es UTF-8. }
function Rel(const p: RawByteString): string;
var b: RawByteString; t: TBytes;
begin
  if Copy(p, 1, Length(raiz)) = raiz then b := 'R' + Copy(p, Length(raiz) + 1, MaxInt) else b := p;
  t := nil; SetLength(t, Length(b));
  if b <> '' then Move(b[1], t[0], Length(b));
  if Utf8Valido(t) then Result := b else Result := 'hex:' + AHexS(b);
end;

function Datos(const semilla: string): TBytes;
var n, i: SizeInt;
begin
  n := StrToInt(semilla); Result := nil; SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := Byte(i * 31 + n);
end;

function Ext(const r: TResultadoExtraccion; const p: RawByteString): string;
begin if r.Ok then Result := 'Ok ' + Rel(p) else Result := r.Texto; end;

function Escribir(const p: RawByteString; const semilla, ok, si, sobr: string): string;
var d: TBytes; esperado: THash16; des: TDesenlace; r: TResultadoFs; sf: TSiFalla; otra: TBytes;
begin
  d := Datos(semilla);
  if ok = '1' then esperado := Blake3_128(d)
  else begin otra := nil; SetLength(otra, 9); Move(PChar('otra cosa')^, otra[0], 9); esperado := Blake3_128(otra); end;
  if si = 'C' then sf := sfConservar else sf := sfBorrar;
  r := EscribirVerificado(p, d, esperado, sf, sobr = '1', des);
  if not r.Ok then Exit(r.Texto);
  case des.tipo of
    deVerificado: Result := 'Verificado(' + Rel(des.ruta) + ')';
    deBorrado: Result := 'Borrado(' + AHex(des.esperado) + ',' + AHex(des.obtenido) + ')';
    deConservado: Result := 'Conservado(' + Rel(des.ruta) + ',' + AHex(des.esperado) + ',' + AHex(des.obtenido) + ')';
  end;
end;

function Unir(const a, b: RawByteString): RawByteString;
begin
  { Path::join: un b absoluto reemplaza todo; con b vacio deja la barra final,
    que realpath tolera igual }
  if (b <> '') and (b[1] = '/') then Exit(b);
  Result := a + '/' + b;
end;

var
  f, o: TextFile; l: string; w: TStringArray; base, dest, p: RawByteString; r: TResultadoExtraccion; s: string;
  bufIn: array[0..65535] of Byte; bufOut: array[0..65535] of Byte;
begin
  if ParamCount <> 2 then begin Writeln(StdErr, 'uso: dif_pjafs <raiz> <casos.txt>'); Halt(2); end;
  raiz := ParamStr(1);
  AssignFile(f, ParamStr(2)); SetTextBuf(f, bufIn, SizeOf(bufIn)); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l);
    w := l.Split(' ');
    base := Unir(raiz, w[1]);
    case w[0] of
      'D', 'C': begin
        if w[0] = 'C' then begin
          if not SetCurrentDir(base) then raise Exception.Create('chdir ' + base);
          dest := HexCad(w[2]);
        end else dest := Unir(base, HexCad(w[2]));
        r := DestinoDe(dest, DeHex(w[3]), w[4] = '1', w[5] = '1', p);
        if w[0] = 'C' then SetCurrentDir('/');
        s := Ext(r, p);
      end;
      'W': begin
        r := DestinoDe(Unir(base, HexCad(w[2])), DeHex(w[3]), w[4] = '1', w[5] = '1', p);
        s := Ext(r, p);
        if r.Ok then s := s + ' -> ' + Escribir(p, w[6], w[7], w[8], w[5]);
      end;
      'X': s := Escribir(Unir(base, HexCad(w[2])), w[4], w[5], w[6], w[3]);
    else raise Exception.Create('caso desconocido: ' + l);
    end;
    WriteLn(o, s);
  end;
  CloseFile(f); Close(o);
end.
