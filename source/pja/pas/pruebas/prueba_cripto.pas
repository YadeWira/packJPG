{ La cripto en C desde Pascal, contra los vectores congelados del Rust de
  referencia (kat.txt): BLAKE3-128 en los bordes de bloque y de trozo,
  Argon2id V1, y el cifrado por trozos byte a byte. Mas el generador del
  sistema, que no tiene vector posible: se prueba que entregue y que no
  repita. }
program prueba_cripto;
{$I ../pja.inc}
uses SysUtils, Classes, pjacripto, pjacifrado;
var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:58, '  ok') else begin Inc(fallas); Writeln('  ', q:58, '  FALLA'); end; end;
function Hex(const x: array of Byte): string; var i: Integer;
begin Result := ''; for i := 0 to High(x) do Result := Result + LowerCase(IntToHex(x[i], 2)); end;
function DeHex(const s: string): TBytes; var i: SizeInt;
begin Result := nil; SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := StrToInt('$' + Copy(s, 2*i+1, 2)); end;
{ El mismo patron que kat_cripto.rs: xorshift32 sin periodo corto, para que un
  corrimiento de un byte se note. }
function Patron(n: SizeInt; semilla: LongWord): TBytes; var x: LongWord; i: SizeInt;
begin
  Result := nil; SetLength(Result, n); x := semilla;
  for i := 0 to n - 1 do begin
    x := x xor (x shl 13); x := x xor (x shr 17); x := x xor (x shl 5);
    Result[i] := Byte(x shr 3);
  end;
end;

var kat: TStringList; l: string; campos: TStringArray; i, n: Integer;
    pass, d, ct, pt, x, y: TBytes; sal: TSal; nb: TNonce; clave: TClave; lanzo: Boolean;
    h: THash16; nkdf, ncif, nb3, corte: Integer; vistos: TStringList; r: array[0..31] of Byte;
begin
  celdas := 0; fallas := 0; nkdf := 0; ncif := 0; nb3 := 0;
  kat := TStringList.Create; kat.LoadFromFile(ParamStr(1));
  for l in kat do begin
    if (l = '') or (l[1] = '#') then Continue;
    campos := l.Split(' ');
    if campos[0] = 'kdf' then begin
      Inc(nkdf);
      pass := DeHex(campos[1]);
      x := DeHex(campos[2]); Move(x[0], sal[0], TAM_SAL);
      x := DeHex(campos[3]); Move(x[0], nb[0], TAM_NONCE);
      Ch(DerivarClave(pass, sal, clave).Ok, 'Argon2id V1 deriva');
      Ch(Hex(clave) = campos[4], 'clave Argon2id = Rust');
    end else if campos[0] = 'cif' then begin
      Inc(ncif);
      n := StrToInt(campos[1]);
      d := Patron(n, $9E3779B9 xor LongWord(n));
      Cifrar(clave, nb, d, ct);
      Ch((Length(ct) = StrToInt(campos[2])) and (Hex(Blake3_128(ct)) = campos[3]),
         Format('cifrar %d B = Rust byte a byte', [n]));
      if campos[4] <> '-' then Ch(Hex(ct) = campos[4], '  y entero, comparado byte a byte');
      Ch(Descifrar(clave, nb, ct, pt).Ok and (Length(pt) = n) and ((n = 0) or CompareMem(@pt[0], @d[0], n)),
         '  descifrar devuelve el claro');
    end else if campos[0] = 'b3' then begin
      Inc(nb3);
      n := StrToInt(campos[1]);
      d := Patron(n, $1234567 xor LongWord(n));
      Ch(Hex(Blake3_128(d)) = campos[2], Format('BLAKE3-128 %d B = Rust', [n]));
      { el mismo contenido partido en dos tramos tiene que dar lo mismo }
      if n > 1 then begin
        corte := n div 3;
        Ch(Hex(Blake3_128(d, 0, corte, d, corte, n - corte)) = campos[2],
           Format('  partido en dos tramos en %d', [corte]));
      end;
    end;
  end;
  kat.Free;
  Ch((nkdf = 1) and (ncif >= 8) and (nb3 >= 12), Format('fixture leido: %d kdf, %d cif, %d b3', [nkdf, ncif, nb3]));

  { tramos de largo 0 sobre arreglos vacios: no tienen que disparar nada }
  x := nil; y := nil;
  h := Blake3_128(x, 0, 0, y, 0, 0);
  Ch(Hex(h) = 'af1349b9f5f9a1a6a0404dea36dcc949', 'dos tramos vacios = BLAKE3 de nada');
  { y un tramo que se pasa del arreglo SI tiene que rechazarse, antes de C }
  SetLength(x, 10); lanzo := False;
  try h := Blake3_128(x, 5, 6, nil, 0, 0); except on ETramoInvalido do lanzo := True; end;
  Ch(lanzo, 'tramo [5,+6) sobre 10 bytes se rechaza');
  lanzo := False;
  try h := Blake3_128(x, -1, 2, nil, 0, 0); except on ETramoInvalido do lanzo := True; end;
  Ch(lanzo, 'inicio negativo se rechaza');

  { Aleatorio: entrega, cubre todo el pedido y no repite. 32 bytes en cero
    tienen probabilidad 2^-256; mil pedidos iguales, menos. }
  vistos := TStringList.Create; vistos.Sorted := True; vistos.Duplicates := dupIgnore;
  lanzo := True;
  for i := 1 to 1000 do begin
    if not Aleatorio(r, SizeOf(r)) then lanzo := False;
    vistos.Add(Hex(r));
  end;
  Ch(lanzo, 'Aleatorio entrega 1000 veces');
  Ch(vistos.Count = 1000, Format('1000 pedidos de 32 B, %d distintos', [vistos.Count]));
  FillChar(r, SizeOf(r), 0); Aleatorio(r[31], 1);
  n := 0; for i := 0 to 30 do if r[i] <> 0 then Inc(n);
  Ch(n = 0, 'un pedido de 1 B no escribe fuera de el');
  vistos.Free;

  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 40 then begin Writeln('FALLA: esperaba al menos 40 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
