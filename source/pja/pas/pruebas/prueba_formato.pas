{ El formato .pja: ida y vuelta con .pjg reales, cada error con SU nombre, y
  que el escritor y el lector acepten y rechacen exactamente lo mismo.

    prueba_formato <directorio con .pjg> }
program prueba_formato;
{$I ../pja.inc}
uses SysUtils, Classes, pjalimites, pjacripto, pjacifrado, pjaformato;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:62, '  ok') else begin Inc(fallas); Writeln('  ', q:62, '  FALLA'); end; end;
procedure ChR(const r: TResultadoPja; const esperado, q: string);
begin
  Inc(celdas);
  if r.Texto = esperado then Writeln('  ', q:62, '  ok')
  else begin Inc(fallas); Writeln('  ', q:62, '  FALLA: dio ', r.Texto, ', esperaba ', esperado); end;
end;

function Txt(const s: RawByteString): TBytes;
begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;
function Igual(const x, y: TBytes): Boolean;
begin Result := (Length(x) = Length(y)) and ((Length(x) = 0) or CompareMem(@x[0], @y[0], Length(x))); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
function Relleno(n: SizeInt; v: Byte): TBytes;
begin Result := nil; SetLength(Result, n); if n > 0 then FillChar(Result[0], n, v); end;
function ConByte(const x: TBytes; i: SizeInt; v: Byte): TBytes;
begin Result := Copy(x, 0, Length(x)); Result[i] := v; end;

{ Un .pja sin cifrar armado a mano, sin pasar por el escritor: para que el
  lector vea descriptores que el escritor se niega a producir. }
function AMano(tamOrig: QWord; const hash: THash16; const payload: TBytes): TBytes;
var k: Integer;
begin
  Result := nil; SetLength(Result, TAM_CABECERA + TAM_DESCRIPTOR + Length(payload));
  for k := 0 to 3 do Result[k] := MAGIA[k];
  Result[4] := VERSION;
  for k := 0 to 7 do Result[8 + k] := Byte((tamOrig shr (8 * k)) and $FF);
  Move(hash[0], Result[16], 16);
  if Length(payload) > 0 then Move(payload[0], Result[32], Length(payload));
end;

const
  LARGOS_BORDE: array[0..4] of Integer = (MIN_PAYLOAD, TAM_TROZO - 33, TAM_TROZO - 32, TAM_TROZO - 31, 2 * TAM_TROZO);
var
  dir: string; archivos: TStringList; sr: TSearchRec; f: string;
  pay, b, c, otro, vacio: TBytes; h, h2: THash16; p: TPja; cif: Boolean;
  sal: TSal; nonce: TNonce; clave: TClave; r, rw: TResultadoPja;
  i, n, k, simetricos: Integer; cuerpo, ct: TBytes;
  casos: array of record tam_orig: QWord; largo: SizeInt; esperado: string; end;
begin
  celdas := 0; fallas := 0; dir := ParamStr(1);
  archivos := TStringList.Create; archivos.Sorted := True;
  if FindFirst(dir + '/*.pjg', faAnyFile, sr) = 0 then begin
    repeat archivos.Add(dir + '/' + sr.Name); until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  Ch(archivos.Count >= 5, Format('corpus: %d .pjg reales', [archivos.Count]));
  FillChar(sal, SizeOf(sal), $5A); FillChar(nonce, SizeOf(nonce), $C3);

  Writeln('--- ida y vuelta, sin cifrar y cifrado, con cada .pjg del corpus');
  for f in archivos do begin
    pay := Leer(f); h := Blake3_128(pay);
    ChR(Escribir(pay, h, 3 * Length(pay), b), 'Ninguno', ExtractFileName(f) + ': escribir');
    Ch(Length(b) = LargoEscrito(Length(pay), False), '  mide lo que anuncia LargoEscrito');
    r := Abrir(b, p);
    Ch(r.Ok and not p.cifrado and (p.tam_orig = QWord(3 * Length(pay))) and CompareMem(@p.hash, @h, 16)
       and Igual(p.payload, pay), '  y vuelve igual: tam_orig, hash, payload');
  end;
  { Cifrar los diez cuesta diez Argon2id; dos alcanzan para la ida y vuelta,
    con el payload mas chico y el mas grande. }
  for i := 0 to 1 do begin
    if i = 0 then f := archivos[0] else f := archivos[archivos.Count - 1];
    pay := Leer(f); h := Blake3_128(pay);
    ChR(EscribirCon(pay, h, 2 * Length(pay), Txt('clave'), sal, nonce, b), 'Ninguno',
        ExtractFileName(f) + ': escribir cifrado');
    Ch(Length(b) = LargoEscrito(Length(pay), True), '  mide lo que anuncia LargoEscrito');
    r := Abrir(b, Txt('clave'), p);
    Ch(r.Ok and p.cifrado and (p.tam_orig = QWord(2 * Length(pay))) and CompareMem(@p.hash, @h, 16)
       and Igual(p.payload, pay), '  y vuelve igual con la contrasena');
  end;
  pay := Leer(archivos[0]); h := Blake3_128(pay);

  Writeln('--- el cifrado no deja nada en claro mas que los 8 bytes de cabecera');
  EscribirCon(pay, h, 2 * Length(pay), Txt('clave'), sal, nonce, c);
  Escribir(pay, h, 2 * Length(pay), b);
  k := 0;
  for i := 0 to Length(c) - 16 do
    if CompareMem(@c[i], @pay[0], 16) or CompareMem(@c[i], @h[0], 16) then Inc(k);
  Ch(k = 0, 'ni el hash ni el comienzo del payload aparecen en el cifrado');
  Ch((c[5] and FLAG_CIFRADO) <> 0, 'el bit de cifrado esta en la cabecera en claro');
  Ch(CompareMem(@c[TAM_CABECERA], @sal[0], TAM_SAL) and CompareMem(@c[TAM_CABECERA + TAM_SAL], @nonce[0], TAM_NONCE),
     'sal y nonce en claro detras de la cabecera');
  { Escribir con contrasena usa sal y nonce del sistema: dos veces lo mismo da
    dos archivos distintos. }
  ChR(Escribir(pay, h, 2 * Length(pay), Txt('clave'), b), 'Ninguno', 'escribir cifrado con sal del sistema');
  ChR(Escribir(pay, h, 2 * Length(pay), Txt('clave'), otro), 'Ninguno', '  otra vez');
  Ch((Length(b) = Length(otro)) and not Igual(b, otro), '  mismo largo, bytes distintos');
  { cada uno por separado: comparados juntos, uno aleatorio alcanza para que
    el bloque difiera, y una sal fija pasaba (lo mostro un mutante) }
  Ch(not CompareMem(@b[TAM_CABECERA], @otro[TAM_CABECERA], TAM_SAL), '  sales distintas');
  Ch(not CompareMem(@b[TAM_CABECERA + TAM_SAL], @otro[TAM_CABECERA + TAM_SAL], TAM_NONCE), '  nonces distintos');
  r := Abrir(otro, Txt('clave'), p);
  Ch(r.Ok and Igual(p.payload, pay), '  y abre');

  Writeln('--- cabecera: cada error con su nombre');
  Escribir(pay, h, 2 * Length(pay), b);
  for n := 0 to TAM_CABECERA - 1 do begin
    ChR(Abrir(Copy(b, 0, n), p), 'ArchivoCorto', Format('%d bytes', [n]));
  end;
  ChR(Abrir(ConByte(b, 0, Ord('X')), p), 'NoEsPja', 'magia: primer byte');
  ChR(Abrir(ConByte(b, 3, $02), p), 'NoEsPja', 'magia: el $01 del final');
  ChR(Abrir(ConByte(b, 4, 3), p), 'VersionFutura(3)', 'version 3');
  ChR(Abrir(ConByte(b, 4, 255), p), 'VersionFutura(255)', 'version 255');
  ChR(Abrir(ConByte(b, 4, 1), p), 'VersionVieja(1)', 'version 1 (el contenedor descartado)');
  ChR(Abrir(ConByte(b, 4, 0), p), 'VersionVieja(0)', 'version 0');
  for k := 1 to 7 do
    ChR(Abrir(ConByte(b, 5, 1 shl k), p), 'FlagDesconocido', Format('flag bit %d', [k]));
  ChR(Abrir(ConByte(b, 6, 1), p), 'ReservadoNoCero', 'kdf distinto de 0 sin cifrado');
  ChR(Abrir(ConByte(b, 7, 1), p), 'ReservadoNoCero', 'reservado');
  ChR(Abrir(ConByte(c, 6, 1), Txt('clave'), p), 'PerfilKdfDesconocido(1)', 'perfil de kdf 1, cifrado');
  ChR(Abrir(ConByte(c, 7, 1), Txt('clave'), p), 'ReservadoNoCero', 'reservado, cifrado');
  { basura con el byte 5 impar: "no es un .pja", no "falta contrasena" }
  ChR(Abrir(Relleno(200, $41), p), 'NoEsPja', 'basura 0x41');
  ChR(Abrir(Relleno(200, $01), p), 'NoEsPja', 'basura 0x01 (flag de cifrado prendido)');
  ChR(Examinar(c, cif), 'Ninguno', 'Examinar el cifrado');
  Ch(cif, '  dice que pide contrasena');
  ChR(Examinar(b, cif), 'Ninguno', 'Examinar el sin cifrar');
  Ch(not cif, '  dice que no');
  ChR(Examinar(Copy(c, 0, TAM_CABECERA), cif), 'Ninguno', 'Examinar con solo los 8 bytes');
  ChR(Examinar(ConByte(b, 4, 3), cif), 'VersionFutura(3)', 'Examinar una version futura');

  Writeln('--- contrasenas');
  ChR(Abrir(c, p), 'Contrase'#$C3#$B1'aFaltante', 'cifrado sin contrasena');
  ChR(Abrir(b, Txt('clave'), p), 'Contrase'#$C3#$B1'aSobrante', 'sin cifrar con contrasena');
  ChR(Abrir(c, Txt('otra'), p), 'Cifrado(TrozoAlterado(0))', 'contrasena equivocada');
  Ch((Length(p.payload) = 0) and (p.tam_orig = 0), '  y no queda nada leido');
  ChR(Abrir(c, Txt('clav'), p), 'Cifrado(TrozoAlterado(0))', 'un caracter menos');
  vacio := nil;
  ChR(EscribirCon(pay, h, 2 * Length(pay), vacio, sal, nonce, otro), 'Ninguno', 'cifrar con contrasena VACIA');
  ChR(Abrir(otro, vacio, p), 'Ninguno', '  abre con la vacia: es una contrasena');
  ChR(Abrir(otro, p), 'Contrase'#$C3#$B1'aFaltante', '  y sin contrasena, falta');
  ChR(Abrir(ConByte(c, TAM_CABECERA, c[TAM_CABECERA] xor 1), Txt('clave'), p), 'Cifrado(TrozoAlterado(0))',
      'un bit de la sal: otra clave');
  ChR(Abrir(ConByte(c, TAM_CABECERA + TAM_SAL, c[TAM_CABECERA + TAM_SAL] xor 1), Txt('clave'), p),
      'Cifrado(TrozoAlterado(0))', 'un bit del nonce');
  ChR(Abrir(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO - 1), Txt('clave'), p), 'ArchivoCorto',
      'cifrado sin el ultimo byte del nonce');
  ChR(Abrir(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO), Txt('clave'), p), 'Cifrado(Truncado)',
      'cifrado sin ningun trozo');

  Writeln('--- la copia de la cabecera adentro del cifrado');
  { Solo la puede romper quien tiene la clave: se arma el cuerpo a mano. }
  if not DerivarClave(Txt('clave'), sal, clave).Ok then raise Exception.Create('derivar');
  ChR(AbrirConClave(c, clave, p), 'Ninguno', 'AbrirConClave abre el cifrado');
  Ch(Igual(p.payload, pay), '  con el mismo payload');
  Escribir(pay, h, 2 * Length(pay), cuerpo);         { cabecera + descriptor + payload, sin cifrar }
  for k := 0 to TAM_CABECERA - 1 do begin
    otro := Copy(cuerpo, 0, Length(cuerpo));
    otro[5] := FLAG_CIFRADO;                         { la copia correcta de una cabecera cifrada }
    otro[k] := otro[k] xor $10;
    Cifrar(clave, nonce, otro, ct);
    otro := Concat(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO), ct);
    ChR(AbrirConClave(otro, clave, p), 'CabeceraAlterada', Format('copia con el byte %d distinto', [k]));
  end;
  otro := Copy(cuerpo, 0, TAM_CABECERA - 1); Cifrar(clave, nonce, otro, ct);
  otro := Concat(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO), ct);
  ChR(AbrirConClave(otro, clave, p), 'CabeceraAlterada', 'cuerpo cifrado de 7 bytes');
  otro := Copy(cuerpo, 0, TAM_CABECERA); otro[5] := FLAG_CIFRADO; Cifrar(clave, nonce, otro, ct);
  otro := Concat(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO), ct);
  ChR(AbrirConClave(otro, clave, p), 'ArchivoCorto', 'cuerpo cifrado con la copia y sin descriptor');
  ChR(AbrirConClave(b, clave, p), 'Contrase'#$C3#$B1'aSobrante', 'AbrirConClave sobre uno sin cifrar');

  Writeln('--- descriptor: los bordes, en el escritor Y en el lector');
  { Cada caso se pide al escritor y se arma a mano para el lector: tienen que
    dar el MISMO veredicto. Es la regla que el contenedor anterior rompia. }
  SetLength(casos, 12);
  casos[0].tam_orig := 0;     casos[0].largo := 100; casos[0].esperado := 'TamOrigInvalido';
  casos[1].tam_orig := 1;     casos[1].largo := 100; casos[1].esperado := 'Ninguno';
  casos[2].tam_orig := 50000; casos[2].largo := 100; casos[2].esperado := 'Ninguno';
  casos[3].tam_orig := 50001; casos[3].largo := 100; casos[3].esperado := 'RatioExcedido';
  casos[4].tam_orig := 100;   casos[4].largo := MIN_PAYLOAD - 1; casos[4].esperado := 'PayloadFueraDeRango';
  casos[5].tam_orig := 100;   casos[5].largo := MIN_PAYLOAD; casos[5].esperado := 'Ninguno';
  casos[6].tam_orig := 0;     casos[6].largo := 0; casos[6].esperado := 'PayloadFueraDeRango';
  casos[7].tam_orig := MIN_PAYLOAD * MAX_RATIO_EXPANSION;     casos[7].largo := MIN_PAYLOAD; casos[7].esperado := 'Ninguno';
  casos[8].tam_orig := MIN_PAYLOAD * MAX_RATIO_EXPANSION + 1; casos[8].largo := MIN_PAYLOAD; casos[8].esperado := 'RatioExcedido';
  casos[9].tam_orig := QWord(High(Int64));     casos[9].largo := 100;  casos[9].esperado := 'RatioExcedido';
  casos[10].tam_orig := QWord(High(Int64)) + 1; casos[10].largo := 100; casos[10].esperado := 'TamOrigInvalido';
  casos[11].tam_orig := High(QWord);           casos[11].largo := 100; casos[11].esperado := 'TamOrigInvalido';
  simetricos := 0;
  for i := 0 to High(casos) do begin
    otro := Relleno(casos[i].largo, $AB);
    rw := Escribir(otro, h, casos[i].tam_orig, b);
    r := Abrir(AMano(casos[i].tam_orig, h, otro), p);
    ChR(rw, casos[i].esperado, Format('escribir tam_orig %u, payload %d', [casos[i].tam_orig, casos[i].largo]));
    ChR(r, casos[i].esperado, '  y el lector, lo mismo');
    if rw.Texto = r.Texto then Inc(simetricos);
    if not rw.Ok then Ch(Length(b) = 0, '  y el escritor no entrega nada');
  end;
  Ch(simetricos = Length(casos), Format('escritor y lector coinciden en %d de %d', [simetricos, Length(casos)]));
  { Lo mismo con cifrado: el escritor valida ANTES de derivar. }
  ChR(EscribirCon(Relleno(100, 1), h, 0, Txt('x'), sal, nonce, b), 'TamOrigInvalido', 'cifrado: tam_orig 0');
  ChR(EscribirCon(Relleno(100, 1), h, 50001, Txt('x'), sal, nonce, b), 'RatioExcedido', 'cifrado: ratio');
  ChR(Escribir(Relleno(5, 1), h, 10, Txt('x'), b), 'PayloadFueraDeRango', 'cifrado con sal del sistema: payload chico');
  { un descriptor malo ADENTRO del cifrado, armado con la clave }
  otro := AMano(0, h, Relleno(100, 1)); otro[5] := FLAG_CIFRADO; Cifrar(clave, nonce, otro, ct);
  otro := Concat(Copy(c, 0, TAM_CABECERA + TAM_PREFIJO_CIFRADO), ct);
  ChR(AbrirConClave(otro, clave, p), 'TamOrigInvalido', 'cifrado y autenticado, con tam_orig 0');
  Ch((p.tam_orig = 0) and (Length(p.payload) = 0), '  y el rechazo no deja nada leido');
  otro := AMano(50001, h, Relleno(100, 1));
  r := Abrir(otro, p);
  Ch((not r.Ok) and (p.tam_orig = 0) and (Length(p.payload) = 0), 'sin cifrar: el rechazo tampoco deja nada');

  Writeln('--- el hash es solo un dato');
  { El formato no recalcula nada sobre el payload: el hash es del JPEG, y lo
    verifica quien decodifica. Cualquier valor se guarda y vuelve. }
  FillChar(h2, SizeOf(h2), $FF);
  Escribir(pay, h2, 2 * Length(pay), b);
  r := Abrir(b, p);
  Ch(r.Ok and CompareMem(@p.hash, @h2, 16), 'un hash de todos 0xFF vuelve igual');

  Writeln('--- LargoEscrito');
  Ch(LargoEscrito(0, False) = TAM_CABECERA + TAM_DESCRIPTOR, 'payload 0 sin cifrar');
  Ch(LargoEscrito(0, True) = TAM_CABECERA + TAM_PREFIJO_CIFRADO + TAM_CABECERA + TAM_DESCRIPTOR + 20, 'payload 0 cifrado: un trozo');
  Ch(LargoEscrito(TAM_TROZO - 32, True) = TAM_CABECERA + TAM_PREFIJO_CIFRADO + TAM_TROZO + 20, 'claro de un trozo justo');
  Ch(LargoEscrito(TAM_TROZO - 31, True) = TAM_CABECERA + TAM_PREFIJO_CIFRADO + TAM_TROZO + 1 + 40, 'un byte mas: dos trozos');
  Ch(LargoEscrito(-1, False) = -1, 'largo negativo');
  { arreglo constante, no `in [..]`: eso arma un CONJUNTO, de bytes }
  for n in LARGOS_BORDE do begin
    EscribirCon(Relleno(n, 7), h, n, Txt('x'), sal, nonce, b);
    Ch(Length(b) = LargoEscrito(n, True), Format('  cifrado de %d B mide lo anunciado', [n]));
  end;

  archivos.Free;
  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 100 then begin Writeln('FALLA: esperaba al menos 100 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
