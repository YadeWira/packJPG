{ Lo que pjacifrado dice de cada caso del corpus del ejemplo dif_cifrado del
  Rust, con el mismo formato. Las mutaciones son las mismas operaciones. }
program dif_cifrado;
{$I pja.inc}
uses SysUtils, Classes, pjacripto, pjacifrado;

const DIG: array[0..15] of Char = '0123456789abcdef';
function ValorHex(c: Char): Integer;
begin case c of '0'..'9': Result := Ord(c) - 48; 'a'..'f': Result := Ord(c) - 87;
  else raise Exception.Create('hex invalido'); end; end;
function DeHex(const s: string): TBytes;
var i: SizeInt;
begin Result := nil; SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := (ValorHex(s[2*i+1]) shl 4) or ValorHex(s[2*i+2]); end;
function AHex(const b: array of Byte): string;
var i: SizeInt;
begin SetLength(Result, 2 * Length(b));
  for i := 0 to High(b) do begin Result[2*i+1] := DIG[b[i] shr 4]; Result[2*i+2] := DIG[b[i] and 15]; end; end;
function Payload(largo: SizeInt; semilla: QWord): TBytes;
var k: SizeInt;
begin Result := nil; SetLength(Result, largo);
  for k := 0 to largo - 1 do Result[k] := Byte(((semilla * 31) + QWord(k) * 7) and $FF); end;
function B3(const b: TBytes): string; begin Result := AHex(Blake3_128(b)); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;

type TTrozo = record ini, lar: SizeInt; end;
function Trozos(const c: TBytes): specialize TArray<TTrozo>;
var p, l, n: SizeInt;
begin
  Result := nil; n := 0; p := 0;
  while p + 4 <= Length(c) do begin
    l := SizeInt(c[p]) or (SizeInt(c[p+1]) shl 8) or (SizeInt(c[p+2]) shl 16) or (SizeInt(c[p+3]) shl 24);
    if (l < 0) or (Int64(p) + 4 + l > Length(c)) then Break;
    SetLength(Result, n + 1); Result[n].ini := p; Result[n].lar := 4 + l; Inc(n); p := p + 4 + l;
  end;
end;
procedure Agregar(var c: TBytes; const b: TBytes; ini, n: SizeInt);
var k: SizeInt; begin k := Length(c); SetLength(c, k + n); if n > 0 then Move(b[ini], c[k], n); end;

function Mutar(const base: TBytes; const op: TStringArray; desde: Integer): TBytes;
var t: specialize TArray<TTrozo>; i, j, k, q, cut: SizeInt; v: LongWord; m: Byte;
  function N(x: Integer): Int64; begin Result := StrToInt64(op[desde + x]); end;
begin
  t := Trozos(base); Result := nil;
  case op[desde] of
    'id': Result := Copy(base, 0, Length(base));
    'x': begin Result := Copy(base, 0, Length(base)); i := N(1); m := N(2);
           if i < Length(Result) then Result[i] := Result[i] xor m; end;
    't': begin cut := N(1); if cut > Length(base) then cut := Length(base); Result := Copy(base, 0, cut); end;
    'a': begin Result := Copy(base, 0, Length(base)); k := Length(Result); SetLength(Result, k + N(1));
           FillChar(Result[k], N(1), 0); end;
    's': begin i := N(1); j := N(2);
           for k := 0 to High(t) do begin
             if k = i then q := j else if k = j then q := i else q := k;
             Agregar(Result, base, t[q].ini, t[q].lar); end; end;
    'd': begin i := N(1);
           for k := 0 to High(t) do begin Agregar(Result, base, t[k].ini, t[k].lar);
             if k = i then Agregar(Result, base, t[k].ini, t[k].lar); end; end;
    'r': begin i := N(1); for k := 0 to High(t) do if k <> i then Agregar(Result, base, t[k].ini, t[k].lar); end;
    'p': begin Result := Copy(base, 0, Length(base)); i := N(1); v := LongWord(N(2));
           if i <= High(t) then for k := 0 to 3 do Result[t[i].ini + k] := Byte((v shr (8 * k)) and $FF); end;
  else raise Exception.Create('op desconocida ' + op[desde]);
  end;
end;

var f, o: TextFile; l, dir: string; w: TStringArray; r: TResultadoCifrado;
    clave: TClave; nb: TNonce; sal: TSal; ct, pt, x: TBytes;
    bufOut: array[0..65535] of Byte;
begin
  dir := ParamStr(1);
  AssignFile(f, dir + '/corpus.txt'); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l); w := l.Split(' ');
    case w[0] of
      'K': begin
             x := DeHex(w[2]); Move(x[0], sal[0], TAM_SAL);
             r := DerivarClave(DeHex(w[1]), sal, clave);
             if r.Ok then WriteLn(o, AHex(clave)) else WriteLn(o, r.Texto);
           end;
      'C': begin
             x := DeHex(w[1]); Move(x[0], clave[0], 32); x := DeHex(w[2]); Move(x[0], nb[0], TAM_NONCE);
             Cifrar(clave, nb, Payload(StrToInt(w[3]), StrToQWord(w[4])), ct);
             WriteLn(o, 'len:', Length(ct), ' b3:', B3(ct));
           end;
      'D': begin
             x := DeHex(w[2]); Move(x[0], clave[0], 32); x := DeHex(w[3]); Move(x[0], nb[0], TAM_NONCE);
             ct := Mutar(Leer(dir + '/' + w[1]), w, 4);
             r := Descifrar(clave, nb, ct, pt);
             if r.Ok then WriteLn(o, 'Ok len:', Length(pt), ' b3:', B3(pt)) else WriteLn(o, r.Texto);
           end;
    end;
  end;
  CloseFile(f); Close(o);
end.
