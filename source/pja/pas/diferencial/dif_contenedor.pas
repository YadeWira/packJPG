{ Lo que pjacontenedor dice de cada linea del corpus del ejemplo
  dif_contenedor del Rust, con el mismo formato. }
program dif_contenedor;
{$I pja.inc}
uses SysUtils, Classes, pjacripto, pjacifrado, pjanombres, pjaindice, pjaescritor, pjacontenedor;

const DIG: array[0..15] of Char = '0123456789abcdef';
function ValorHex(c: Char): Integer;
begin case c of '0'..'9': Result := Ord(c) - 48; 'a'..'f': Result := Ord(c) - 87;
  else raise Exception.Create('hex invalido'); end; end;
function DeHex(const s: string): TBytes; var i: SizeInt;
begin Result := nil; SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := (ValorHex(s[2*i+1]) shl 4) or ValorHex(s[2*i+2]); end;
function AHex(const b: array of Byte): string; var i: SizeInt;
begin SetLength(Result, 2 * Length(b));
  for i := 0 to High(b) do begin Result[2*i+1] := DIG[b[i] shr 4]; Result[2*i+2] := DIG[b[i] and 15]; end; end;
function Payload(largo: SizeInt; semilla: QWord): TBytes; var k: SizeInt;
begin Result := nil; SetLength(Result, largo);
  for k := 0 to largo - 1 do Result[k] := Byte(((semilla * 31) + QWord(k) * 7) and $FF); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
procedure Pon(var b: TBytes; v: QWord; n: Integer); var k, l: SizeInt;
begin l := Length(b); SetLength(b, l + n); for k := 0 to n - 1 do b[l + k] := Byte((v shr (8 * k)) and $FF); end;
procedure PonB(var b: TBytes; const x: TBytes); var l: SizeInt;
begin l := Length(b); SetLength(b, l + Length(x)); if Length(x) > 0 then Move(x[0], b[l], Length(x)); end;

{ Los mismos nombres de motivo que el Debug de Rust, como en dif_escritor. }
function TextoMotivo(m: TMotivo): string;
begin WriteStr(Result, m); Delete(Result, 1, 1); end;

procedure Resellar(var c: TBytes); var ti: LongWord; h: THash16;
begin
  if Length(c) < TAM_CABECERA then Exit;
  ti := LongWord(c[8]) or (LongWord(c[9]) shl 8) or (LongWord(c[10]) shl 16) or (LongWord(c[11]) shl 24);
  if Int64(TAM_CABECERA) + ti > Length(c) then Exit;
  h := HashCabeceraIndice(c, TAM_CABECERA, ti); Move(h[0], c[12], 16);
end;
function Mutar(const base: TBytes; const ops: TStringArray; desde: Integer): TBytes;
var i, p: SizeInt; l: Int64;
  function N(k: Integer): Int64; begin Result := StrToInt64(ops[i + k]); end;
begin
  Result := Copy(base, 0, Length(base)); i := desde;
  while i <= High(ops) do
    case ops[i] of
      'id': Inc(i);
      'x': begin p := N(1); if p < Length(Result) then Result[p] := Result[p] xor Byte(N(2)); Inc(i, 3); end;
      't': begin l := N(1); if l < Length(Result) then SetLength(Result, l); Inc(i, 2); end;
      'a': begin l := Length(Result); SetLength(Result, l + N(1)); FillChar(Result[l], N(1), 0); Inc(i, 2); end;
      'w': begin p := N(1); if p < Length(Result) then Result[p] := Byte(N(2)); Inc(i, 3); end;
      'h': begin Resellar(Result); Inc(i); end;
    else raise Exception.Create('op ' + ops[i]);
    end;
end;

var f, o: TextFile; l, dir, sAv: string; w, es, campos: TStringArray; r: TResultadoContenedor;
    cc: TClaveCifrado; x, b, s, pass: TBytes; ent: TEntradas; av: TAvisos; a: TAbierto;
    k: SizeInt; m: TMiembro; bufOut: array[0..65535] of Byte;
begin
  dir := ParamStr(1);
  AssignFile(f, dir + '/corpus.txt'); Reset(f);
  Assign(o, ''); Rewrite(o); SetTextBuf(o, bufOut, SizeOf(bufOut));
  while not Eof(f) do begin
    ReadLn(f, l); w := l.Split(' ');
    case w[0] of
      'K': begin
             x := DeHex(w[2]); Move(x[0], cc.sal[0], TAM_SAL);
             x := DeHex(w[3]); Move(x[0], cc.nonce[0], TAM_NONCE);
             if not DerivarClave(DeHex(w[1]), cc.sal, cc.clave).Ok then raise Exception.Create('K');
           end;
      'E': begin
             ent := nil;
             if (Length(w) >= 4) and (w[3] <> '') then begin
               es := w[3].Split('|'); SetLength(ent, Length(es));
               for k := 0 to High(es) do begin
                 campos := es[k].Split(',');
                 ent[k].nombre := DeHex(campos[0]);
                 ent[k].payload := Payload(StrToInt(campos[1]), StrToQWord(campos[2]));
                 ent[k].tam_orig := QWord(Length(ent[k].payload)) * 2;
                 ent[k].hash := Blake3_128(ent[k].payload);
               end;
             end;
             if w[2] = '1' then r := EscribirContenedor(ent, StrToInt(w[1]), cc, b, av)
             else r := EscribirContenedor(ent, StrToInt(w[1]), b, av);
             if not r.Ok then WriteLn(o, r.Texto)
             else begin
               sAv := '';
               for k := 0 to High(av) do begin
                 if k > 0 then sAv := sAv + ',';
                 sAv := sAv + IntToStr(av[k].indice) + ':' + TextoMotivo(av[k].motivo);
               end;
               WriteLn(o, 'Ok avisos=[', sAv, '] len:', Length(b), ' b3:', AHex(Blake3_128(b)));
             end;
           end;
      'A': begin
             x := Mutar(Leer(dir + '/' + w[1]), w, 3);
             case w[2] of
               '-': r := Abrir(x, a);
               '~': r := Abrir(x, TBytes(nil), a);
             else begin pass := DeHex(w[2]); r := Abrir(x, pass, a); end;
             end;
             if not r.Ok then WriteLn(o, r.Texto)
             else begin
               s := nil; SetLength(s, 1); s[0] := a.contenedor.flags;
               for k := 0 to High(a.contenedor.miembros) do begin
                 m := a.contenedor.miembros[k];
                 Pon(s, Length(m.nombre), 2); PonB(s, m.nombre);
                 Pon(s, m.tam_orig, 8); Pon(s, m.tam_payload, 8);
                 x := nil; SetLength(x, 16); Move(m.hash[0], x[0], 16); PonB(s, x);
                 Pon(s, m.m_flags, 1);
                 Pon(s, Length(a.payloads[k]), 8); PonB(s, a.payloads[k]);
               end;
               WriteLn(o, 'Ok n:', Length(a.contenedor.miembros), ' flags:', a.contenedor.flags,
                       ' b3:', AHex(Blake3_128(s)));
             end;
           end;
    end;
  end;
  CloseFile(f); Close(o);
end.
