{ Lo que dice pjaindice.LeerIndice de cada contenedor del corpus, con el mismo
  formato que el ejemplo dif_indice del Rust. }
program dif_indice;
{$I pja.inc}
uses SysUtils, pjacripto, pjaindice;

function ValorHex(c: Char): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
  else raise Exception.Create('hex invalido');
  end;
end;

function DeHex(const s: string): TBytes;
var i: SizeInt;
begin
  SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do
    Result[i] := (ValorHex(s[2 * i + 1]) shl 4) or ValorHex(s[2 * i + 2]);
end;

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

var
  f, o: TextFile; l, linea: string; c: TContenedor; r: TResultado; k: SizeInt;
  bufIn: array[0..1 shl 20 - 1] of Byte; bufOut: array[0..65535] of Byte;
begin
  AssignFile(f, ParamStr(1)); SetTextBuf(f, bufIn, SizeOf(bufIn)); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l);
    r := LeerIndice(DeHex(l), c);
    if not r.Ok then WriteLn(o, r.Texto)
    else begin
      linea := 'Ok flags=' + IntToStr(c.flags) + ' n=' + IntToStr(Length(c.miembros)) + ' ';
      for k := 0 to High(c.miembros) do
        with c.miembros[k] do
          linea := linea + AHex(nombre) + ':' + IntToStr(tam_orig) + ':' + IntToStr(tam_payload)
                   + ':' + AHex(hash) + ':' + IntToStr(m_flags) + ';';
      WriteLn(o, linea);
    end;
  end;
  CloseFile(f); Close(o);
end.
