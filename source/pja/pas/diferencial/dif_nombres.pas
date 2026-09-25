{ Veredictos del pjanombres.pas para cada entrada del corpus, con el mismo
  formato que el Debug de Rust. }
program dif_nombres;
{$I pja.inc}
uses SysUtils, pjanombres;
var f: TextFile; l: string; b: TBytes; i: Integer; o: Text;
    buf: array[0..65535] of Byte;
begin
  AssignFile(f, ParamStr(1)); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, buf, SizeOf(buf));
  while not Eof(f) do begin
    ReadLn(f, l);
    SetLength(b, Length(l) div 2);
    for i := 0 to High(b) do b[i] := StrToInt('$' + Copy(l, 2 * i + 1, 2));
    WriteLn(o, Plano(b).Texto, ' ', Ruta(b).Texto);
  end;
  CloseFile(f); Close(o);
end.
