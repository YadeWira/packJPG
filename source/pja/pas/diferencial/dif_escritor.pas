{ Lo que pjaescritor.Escribir produce con cada conjunto del corpus, con el mismo
  formato que el ejemplo dif_escritor del Rust. }
program dif_escritor;
{$I pja.inc}
uses SysUtils, pjanombres, pjacripto, pjaescritor;

const DIG: array[0..15] of Char = '0123456789abcdef';
      NOMBRES_MOTIVO: array[TMotivo] of string = (
        'Vacio', 'ByteDeControl', 'SeparadorEnComponente', 'ComponentePadre', 'RutaAbsoluta',
        'LetraDeUnidad', 'DosPuntos', 'Utf8Invalido', 'ComponenteMuyLargo', 'RutaMuyLarga',
        'MuyProfunda', 'NombreReservado', 'TerminaEnPuntoOEspacio', 'CaracterIlegalEnWindows');

function ValorHex(c: Char): Integer;
begin
  case c of '0'..'9': Result := Ord(c) - 48; 'a'..'f': Result := Ord(c) - 87; 'A'..'F': Result := Ord(c) - 55;
  else raise Exception.Create('hex invalido'); end;
end;
function DeHex(const s: string): TBytes;
var i: SizeInt;
begin Result := nil; SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := (ValorHex(s[2*i+1]) shl 4) or ValorHex(s[2*i+2]); end;
function AHex(const b: TBytes): string;
var i: SizeInt;
begin SetLength(Result, 2 * Length(b));
  for i := 0 to High(b) do begin Result[2*i+1] := DIG[b[i] shr 4]; Result[2*i+2] := DIG[b[i] and 15]; end; end;
{ el mismo payload que deriva el Rust de (largo, semilla). Las semillas del
  corpus son chicas y semilla * 31 no desborda; si algun dia se agrega una
  grande, $Q+ lo hace saltar aca y el conteo de lineas corta la corrida. }
function Payload(largo: SizeInt; semilla: QWord): TBytes;
var k: SizeInt;
begin Result := nil; SetLength(Result, largo);
  for k := 0 to largo - 1 do
    Result[k] := Byte(((semilla * 31) + QWord(k) * 7) and $FF); end;

function Campo(var s: string; sep: Char): string;
var k: SizeInt;
begin k := Pos(sep, s); if k = 0 then begin Result := s; s := ''; end
  else begin Result := Copy(s, 1, k - 1); Delete(s, 1, k); end; end;

var f, o: TextFile; l, resto, e, nom: string; es: TEntradas; n, i: SizeInt;
    fl: Byte; b, hb: TBytes; av: TAvisos; r: TResultadoEscritura; a: string;
    bufIn: array[0..1 shl 20 - 1] of Byte; bufOut: array[0..65535] of Byte;
begin
  AssignFile(f, ParamStr(1)); SetTextBuf(f, bufIn, SizeOf(bufIn)); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l);
    fl := StrToInt(Campo(l, ';'));
    es := nil; n := 0; resto := l;
    while resto <> '' do begin
      e := Campo(resto, '|');
      SetLength(es, n + 1);
      nom := Campo(e, ',');         es[n].nombre := DeHex(nom);
      es[n].tam_orig := StrToQWord(Campo(e, ','));
      i := StrToInt(Campo(e, ','));
      es[n].payload := Payload(i, StrToQWord(Campo(e, ',')));
      hb := DeHex(Campo(e, ',')); Move(hb[0], es[n].hash[0], 16);
      Inc(n);
    end;
    r := Escribir(es, fl, b, av);
    if not r.Ok then WriteLn(o, r.Texto)
    else begin
      a := '';
      for i := 0 to High(av) do begin
        if i > 0 then a := a + ',';
        a := a + IntToStr(av[i].indice) + ':' + NOMBRES_MOTIVO[av[i].motivo];
      end;
      WriteLn(o, 'Ok avisos=[', a, '] ', AHex(b));
    end;
  end;
  CloseFile(f); Close(o);
end.
