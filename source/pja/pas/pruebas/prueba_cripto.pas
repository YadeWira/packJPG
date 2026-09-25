{ BLAKE3 desde Pascal contra los vectores que produjo el Rust de referencia
  (mismos que se verificaron contra la implementacion C en monocypher-kat). }
program prueba_cripto;
{$I ../pja.inc}
uses SysUtils, Classes, pjacripto;
var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:56, '  ok') else begin Inc(fallas); Writeln('  ', q:56, '  FALLA'); end; end;
function Hex(const h: THash16): string; var i: Integer;
begin Result := ''; for i := 0 to 15 do Result := Result + LowerCase(IntToHex(h[i], 2)); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead); try SetLength(Result, s.Size); if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
var d, nom, esp: string; t: TextFile; b, a1, a2: TBytes; h: THash16; i, corte: Integer;
    lanzo: Boolean;
begin
  celdas := 0; fallas := 0; d := ParamStr(1);
  AssignFile(t, d + '/blake3.txt'); Reset(t);
  while not Eof(t) do begin
    ReadLn(t, nom); esp := Copy(nom, Pos(' ', nom) + 1, 99); nom := Copy(nom, 1, Pos(' ', nom) - 1);
    b := Leer(d + '/b3_' + nom + '.bin');
    Ch(Hex(Blake3_128(b)) = esp, Format('BLAKE3-128 %s (%d B) = Rust', [nom, Length(b)]));
    { el mismo contenido partido en dos tramos tiene que dar lo mismo }
    if Length(b) > 1 then begin
      corte := Length(b) div 3;
      Ch(Hex(Blake3_128(b, 0, corte, b, corte, Length(b) - corte)) = esp,
         Format('  partido en dos tramos en %d', [corte]));
    end;
  end;
  CloseFile(t);
  { tramos de largo 0 sobre arreglos vacios: no tienen que disparar nada }
  a1 := nil; a2 := nil;
  h := Blake3_128(a1, 0, 0, a2, 0, 0);
  Ch(True, 'dos tramos vacios sobre arreglos vacios');
  { y un tramo que se pasa del arreglo SI tiene que rechazarse, antes de C }
  SetLength(a1, 10); lanzo := False;
  try h := Blake3_128(a1, 5, 6, nil, 0, 0); except on ETramoInvalido do lanzo := True; end;
  Ch(lanzo, 'tramo [5,+6) sobre 10 bytes se rechaza');
  lanzo := False;
  try h := Blake3_128(a1, -1, 2, nil, 0, 0); except on ETramoInvalido do lanzo := True; end;
  Ch(lanzo, 'inicio negativo se rechaza');
  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 10 then begin Writeln('FALLA: esperaba al menos 10 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
