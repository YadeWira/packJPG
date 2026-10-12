{ Bateria de corrupcion del .pja: archivos validos, danados sistematicamente.

  Sin cifrar, el formato no puede detectar todo: un bit en el payload es un
  .pjg distinto, y lo delata quien decodifica, comparando el JPEG con el
  tamano y el hash declarados. Lo que si se exige es que ninguna mutacion lea
  IGUAL que el original: eso seria un byte que no significa nada, un agujero
  justo en lo que mide esta bateria.

  Cifrado, en cambio, se exige todo: cero mutaciones aceptadas.

  Los baldes tienen que sumar las celdas: sin eso, una clase nueva se cae de la
  tabla y el numero impreso sigue pareciendo razonable.

    prueba_corrupcion <directorio con .pjg> }
program prueba_corrupcion;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_corrupcion: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, pjacripto, pjacifrado, pjaformato;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:64, '  ok') else begin Inc(fallas); Writeln('  ', q:64, '  FALLA'); end; end;

function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
function Igual(const x, y: TBytes): Boolean;
begin Result := (Length(x) = Length(y)) and ((Length(x) = 0) or CompareMem(@x[0], @y[0], Length(x))); end;
function Txt(const s: RawByteString): TBytes;
begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;

type
  TCuenta = record
    celdas, rechaza, desc_distinto, payload_distinto, lee_igual: Int64;
    errores: TStringList;    { que errores salieron, y cuantas veces }
  end;

var
  original: TPja;       { lo que se lee del archivo sano }
  conClave: Boolean;    { abrir con la clave ya derivada (cifrado) }
  clave: TClave;

procedure Iniciar(var c: TCuenta);
begin
  c.celdas := 0; c.rechaza := 0; c.desc_distinto := 0; c.payload_distinto := 0; c.lee_igual := 0;
  c.errores := TStringList.Create; c.errores.Sorted := True;
end;

procedure Anotar(var c: TCuenta; e: string);
var i: Integer;
begin
  { VersionFutura(37) y VersionFutura(38) son el mismo balde; el trozo de
    Cifrado(TrozoAlterado(n)) si se conserva, dice donde fallo }
  if (Pos('(', e) > 0) and (Copy(e, 1, 8) <> 'Cifrado(') then e := Copy(e, 1, Pos('(', e)) + 'n)';
  i := c.errores.IndexOf(e);
  if i < 0 then c.errores.AddObject(e, TObject(PtrInt(1)))
  else c.errores.Objects[i] := TObject(PtrInt(c.errores.Objects[i]) + 1);
end;

{ Abre la variante y la pone en su balde. }
procedure Probar(var c: TCuenta; const datos: TBytes);
var r: TResultadoPja; p: TPja;
begin
  Inc(c.celdas);
  if conClave then r := AbrirConClave(datos, clave, p) else r := Abrir(datos, p);
  if not r.Ok then begin Inc(c.rechaza); Anotar(c, r.Texto); Exit; end;
  if (p.tam_orig <> original.tam_orig) or not CompareMem(@p.hash, @original.hash, 16) then Inc(c.desc_distinto)
  else if not Igual(p.payload, original.payload) then Inc(c.payload_distinto)
  else Inc(c.lee_igual);
end;

function Cuadra(const c: TCuenta): Boolean;
begin Result := c.rechaza + c.desc_distinto + c.payload_distinto + c.lee_igual = c.celdas; end;

procedure Imprimir(const c: TCuenta; const que: string);
var i: Integer;
begin
  Writeln(Format('  %s: %d celdas = %d rechazadas + %d descriptor distinto + %d payload distinto + %d iguales',
                 [que, c.celdas, c.rechaza, c.desc_distinto, c.payload_distinto, c.lee_igual]));
  for i := 0 to c.errores.Count - 1 do
    Writeln(Format('      %-34s %d', [c.errores[i], PtrInt(c.errores.Objects[i])]));
end;

{ ------------------------------------------------------------------------ }

{ Sin cifrar: cada bit, cada valor de los bytes de cabecera y descriptor,
  cada truncado, y agregados al final. }
procedure BarrerClaro(const archivo: TBytes; var c: TCuenta);
var i, b, v: SizeInt; x: TBytes;
begin
  x := Copy(archivo, 0, Length(archivo));
  for i := 0 to High(archivo) do
    for b := 0 to 7 do begin
      x[i] := archivo[i] xor (1 shl b); Probar(c, x); x[i] := archivo[i];
    end;
  for i := 0 to TAM_CABECERA + TAM_DESCRIPTOR - 1 do
    for v := 0 to 255 do
      if v <> archivo[i] then begin x[i] := v; Probar(c, x); x[i] := archivo[i]; end;
  for i := 0 to High(archivo) do Probar(c, Copy(archivo, 0, i));
  for i := 1 to 64 do begin
    x := Concat(archivo, Copy(archivo, 0, i)); Probar(c, x);
  end;
end;

{ Cifrado: los 8 bytes en claro y el nonce enteros (con AbrirConClave, la
  sal no se usa: sus bits van aparte, con Argon2id); del cuerpo, los bytes
  alrededor de cada borde de trozo --largo, comienzo del cifrado, tag-- y uno
  de cada 61 en el medio. Truncados alrededor de cada borde y salteados. }
procedure BarrerCifrado(const archivo: TBytes; var c: TCuenta);
var i, b, ini, lar, k: SizeInt; x: TBytes; bordes: array of SizeInt; cerca: Boolean;
begin
  bordes := nil; i := TAM_CABECERA + TAM_PREFIJO_CIFRADO;
  while i < Length(archivo) do begin
    SetLength(bordes, Length(bordes) + 1); bordes[High(bordes)] := i;
    lar := SizeInt(archivo[i]) or (SizeInt(archivo[i + 1]) shl 8) or (SizeInt(archivo[i + 2]) shl 16)
           or (SizeInt(archivo[i + 3]) shl 24);
    i := i + 4 + lar;
  end;
  if i <> Length(archivo) then raise Exception.Create('BarrerCifrado: los trozos no cierran');
  SetLength(bordes, Length(bordes) + 1); bordes[High(bordes)] := Length(archivo);

  x := Copy(archivo, 0, Length(archivo));
  for i := 0 to High(archivo) do begin
    cerca := (i < TAM_CABECERA) or ((i >= TAM_CABECERA + TAM_SAL) and (i < TAM_CABECERA + TAM_PREFIJO_CIFRADO));
    for k := 0 to High(bordes) do
      if ((i >= bordes[k]) and (i < bordes[k] + 40)) or ((i < bordes[k]) and (i >= bordes[k] - 24)) then cerca := True;
    if (i >= TAM_CABECERA) and (i < TAM_CABECERA + TAM_SAL) then Continue;   { la sal, aparte }
    if not cerca and (i mod 61 <> 0) then Continue;
    for b := 0 to 7 do begin
      x[i] := archivo[i] xor (1 shl b); Probar(c, x); x[i] := archivo[i];
    end;
  end;
  for i := 0 to High(archivo) do begin
    cerca := i < TAM_CABECERA + TAM_PREFIJO_CIFRADO + 8;
    for k := 0 to High(bordes) do if Abs(i - bordes[k]) <= 24 then cerca := True;
    if cerca or (i mod 97 = 0) then Probar(c, Copy(archivo, 0, i));
  end;
  for i := 1 to 40 do Probar(c, Concat(archivo, Copy(archivo, TAM_CABECERA + TAM_PREFIJO_CIFRADO, i)));
  { un trozo entero repetido: el ultimo, y el primero, al final }
  ini := bordes[High(bordes) - 1];
  Probar(c, Concat(archivo, Copy(archivo, ini, Length(archivo) - ini)));
  Probar(c, Concat(archivo, Copy(archivo, bordes[0], bordes[1] - bordes[0])));
  { el primer trozo quitado, y dos trozos intercambiados }
  if Length(bordes) >= 3 then begin
    Probar(c, Concat(Copy(archivo, 0, bordes[0]), Copy(archivo, bordes[1], Length(archivo) - bordes[1])));
    if bordes[1] - bordes[0] = bordes[2] - bordes[1] then
      Probar(c, Concat(Copy(archivo, 0, bordes[0]), Copy(archivo, bordes[1], bordes[2] - bordes[1]),
                       Copy(archivo, bordes[0], bordes[1] - bordes[0]), Copy(archivo, bordes[2], Length(archivo) - bordes[2])));
  end;
end;

var
  dir: string; archivos: TStringList; sr: TSearchRec; f: string;
  pay, arch, grande: TBytes; h: THash16; sal: TSal; nonce: TNonce;
  claro, cif: TCuenta; r: TResultadoPja; p: TPja; i, rechazadas_sal: Integer;
begin
  celdas := 0; fallas := 0; dir := ParamStr(1);
  archivos := TStringList.Create; archivos.Sorted := True;
  if FindFirst(dir + '/*.pjg', faAnyFile, sr) = 0 then begin
    repeat archivos.Add(dir + '/' + sr.Name); until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  Ch(archivos.Count >= 5, Format('corpus: %d .pjg reales', [archivos.Count]));

  Writeln('--- sin cifrar, cada .pjg del corpus');
  Iniciar(claro); conClave := False;
  for f in archivos do begin
    pay := Leer(f); h := Blake3_128(pay);
    if not Escribir(pay, h, 2 * Length(pay), arch).Ok then raise Exception.Create('escribir ' + f);
    if not Abrir(arch, original).Ok then raise Exception.Create('abrir ' + f);
    BarrerClaro(arch, claro);
  end;
  Imprimir(claro, 'sin cifrar');
  Ch(Cuadra(claro), 'los baldes suman las celdas');
  Ch(claro.celdas > 300000, Format('%d celdas (cada bit de 10 archivos, mas valores y truncados)', [claro.celdas]));
  Ch(claro.lee_igual = 0, 'NINGUNA mutacion lee igual que el original');
  Ch(claro.rechaza > 0, 'control: hay rechazos');
  Ch(claro.desc_distinto > 0, 'control: hay descriptores distintos (los detecta quien verifica)');
  Ch(claro.payload_distinto > 0, 'control: hay payloads distintos (los detecta quien verifica)');

  Writeln('--- cifrado: un .pjg real, y un payload de 3 trozos y pico');
  Iniciar(cif); conClave := True;
  FillChar(sal, SizeOf(sal), $11); FillChar(nonce, SizeOf(nonce), $22);
  if not DerivarClave(Txt('clave de la bateria'), sal, clave).Ok then raise Exception.Create('derivar');
  grande := nil; SetLength(grande, 3 * TAM_TROZO + 777);
  for i := 0 to High(grande) do grande[i] := Byte((i * 7 + i div 251) and $FF);
  for i := 0 to 1 do begin
    if i = 0 then pay := Leer(archivos[archivos.Count div 2]) else pay := grande;
    h := Blake3_128(pay);
    if not EscribirCon(pay, h, 2 * Length(pay), Txt('clave de la bateria'), sal, nonce, arch).Ok then
      raise Exception.Create('escribir cifrado');
    if not AbrirConClave(arch, clave, original).Ok then raise Exception.Create('abrir cifrado');
    BarrerCifrado(arch, cif);
  end;
  Imprimir(cif, 'cifrado');
  Ch(Cuadra(cif), 'los baldes suman las celdas');
  Ch(cif.celdas > 20000, Format('%d celdas', [cif.celdas]));
  Ch((cif.desc_distinto = 0) and (cif.payload_distinto = 0) and (cif.lee_igual = 0),
     'NINGUNA mutacion del cifrado se acepta');
  Ch(cif.errores.IndexOf('Cifrado(SobranTrozos)') >= 0, 'control: los agregados dan SobranTrozos');
  Ch(cif.errores.IndexOf('Cifrado(Truncado)') >= 0, 'control: los cortes en borde dan Truncado');

  { La sal no entra en AbrirConClave: sus bits, con la contrasena de verdad.
    Cada uno cuesta un Argon2id; ocho alcanzan para ver que todos cambian la
    clave (un bit de la sal que no la cambiara seria el agujero). }
  rechazadas_sal := 0;
  for i := 0 to 7 do begin
    pay := Copy(arch, 0, Length(arch));
    pay[TAM_CABECERA + 2 * i] := pay[TAM_CABECERA + 2 * i] xor (1 shl i);
    r := Abrir(pay, Txt('clave de la bateria'), p);
    if r.Texto = 'Cifrado(TrozoAlterado(0))' then Inc(rechazadas_sal);
  end;
  Ch(rechazadas_sal = 8, Format('8 bits de la sal, %d dan otra clave', [rechazadas_sal]));
  r := Abrir(arch, Txt('clave de la bateria'), p);
  Ch(r.Ok and Igual(p.payload, grande), 'control: la sal sana, con la contrasena, abre');

  claro.errores.Free; cif.errores.Free; archivos.Free;
  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 14 then begin Writeln('FALLA: esperaba al menos 14 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
