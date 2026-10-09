{ Port de las pruebas de pjacore/src/contenedor.rs, sobre .pjg reales del
  corpus (los genera `make pja-corpus`), ordenados por nombre como en el Rust. }
program prueba_contenedor;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_contenedor: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, pjacripto, pjacifrado, pjaindice, pjaescritor, pjacontenedor;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:60, '  ok') else begin Inc(fallas); Writeln('  ', q:60, '  FALLA'); end; end;
procedure ChR(const r: TResultadoContenedor; const esperado, q: string);
begin
  Inc(celdas);
  if r.Texto = esperado then Writeln('  ', q:60, '  ok')
  else begin Inc(fallas); Writeln('  ', q:60, '  FALLA: dio ', r.Texto, ', esperaba ', esperado); end;
end;

function B(const s: RawByteString): TBytes; begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;
function Igual(const a, b: TBytes): Boolean;
begin Result := (Length(a) = Length(b)) and ((Length(a) = 0) or CompareMem(@a[0], @b[0], Length(a))); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead or fmShareDenyNone); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
{ Aparece `aguja` en algun lugar de `pajar`? }
function Contiene(const pajar: TBytes; const aguja: array of Byte): Boolean; var i: SizeInt;
begin
  Result := False;
  if Length(aguja) = 0 then Exit(True);
  for i := 0 to Length(pajar) - Length(aguja) do
    if CompareMem(@pajar[i], @aguja[0], Length(aguja)) then Exit(True);
end;

var archivos: TStringList;
function Reales(n: Integer): TEntradas; var i: Integer;
begin
  if archivos.Count < n then raise Exception.CreateFmt('el corpus tiene %d .pjg y la prueba necesita %d', [archivos.Count, n]);
  Result := nil; SetLength(Result, n);
  for i := 0 to n - 1 do begin
    Result[i].payload := Leer(archivos[i]);
    Result[i].nombre := B(ExtractFileName(archivos[i]));
    Result[i].tam_orig := QWord(Length(Result[i].payload)) * 2;
    Result[i].hash := Blake3_128(Result[i].payload);
  end;
end;

var SAL: TSal; NB: TNonce;
function CC(const pass: RawByteString): TClaveCifrado;
begin
  Result.sal := SAL; Result.nonce := NB;
  if not DerivarClave(B(pass), SAL, Result.clave).Ok then raise Exception.Create('derivar');
end;
function TodosIguales(const a: TAbierto; const e: TEntradas): Boolean; var i: Integer;
begin
  Result := Length(a.payloads) = Length(e);
  if Result then for i := 0 to High(e) do Result := Result and Igual(a.payloads[i], e[i].payload);
end;

var dir: string; sr: TSearchRec; e: TEntradas; claro, cif, m: TBytes; av: TAvisos; a: TAbierto;
    fl: Byte; ti: LongWord; hClaro, hRe: THash16; ct: TContenedor; ri: TResultado;
    k: TClaveCifrado; i, bit, rechazadas, cuenta: Integer; malo: Byte; h: THash16;
const MALOS: array[0..2] of Byte = (1, 2, 255);
begin
  celdas := 0; fallas := 0; dir := ParamStr(1);
  FillChar(SAL, SizeOf(SAL), 5); FillChar(NB, SizeOf(NB), 6);
  archivos := TStringList.Create; archivos.Sorted := True;   { mismo orden que el sort() del Rust }
  archivos.CaseSensitive := True; archivos.UseLocale := False;
  if FindFirst(IncludeTrailingPathDelimiter(dir) + '*.pjg', faAnyFile, sr) = 0 then begin
    repeat archivos.Add(IncludeTrailingPathDelimiter(dir) + sr.Name); until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  if archivos.Count < 8 then begin Writeln('FALLA: hacen falta 8 .pjg en "', dir, '" (make pja-corpus)'); Halt(2); end;

  Writeln('--- el_cifrado_no_deja_confirmar_los_nombres');
  e := Reales(4);
  { control positivo: sin cifrar, el hash declarado ESTA en el archivo }
  ChR(EscribirContenedor(e, 0, claro, av), 'Ninguno', 'control: escribir en claro');
  Ch(LeerCabecera(claro, fl, ti, hClaro).Ok, 'control: leer la cabecera en claro');
  hRe := HashCabeceraIndice(claro, TAM_CABECERA, ti);
  Ch(CompareMem(@hClaro, @hRe, 16), 'control: sin cifrar el hash se verifica de afuera');
  Ch(Contiene(claro, hRe), 'control: y aparece literal en el archivo');
  { el caso real }
  k := CC('correcta');
  ChR(EscribirContenedor(e, FLAG_CIFRADO, k, cif, av), 'Ninguno', 'escribir cifrado');
  Ch(not Contiene(cif, hRe), 'cifrado, el hash del indice no aparece');
  cuenta := 0;
  for i := TAM_CLARO_CABECERA to TAM_CABECERA - 1 do if cif[i] <> 0 then Inc(cuenta);
  Ch(cuenta = 0, 'tam_indice y hash en cero en disco');
  Ch(LeerCabecera(cif, fl, ti, h).Ok and (ti = 0), 'tam_indice en claro vale 0');
  ChR(Abrir(cif, B('correcta'), a), 'Ninguno', 'abre con la contrasena');
  Ch((Length(a.contenedor.miembros) = 4) and TodosIguales(a, e), '4 miembros, payloads iguales');

  Writeln('--- el_perfil_de_kdf_se_valida');
  e := Reales(3); k := CC('pass');
  EscribirContenedor(e, FLAG_CIFRADO, k, cif, av); EscribirContenedor(e, 0, claro, av);
  ChR(Abrir(cif, B('pass'), a), 'Ninguno', 'control cifrado');
  ChR(Abrir(claro, a), 'Ninguno', 'control en claro');
  Ch(cif[6] = 0, 'V1 se escribe como 0'); Ch(claro[6] = 0, 'sin cifrado el byte va en 0');
  for malo in MALOS do begin
    m := Copy(cif, 0, Length(cif)); m[6] := malo;
    ChR(Abrir(m, B('pass'), a), 'Indice(PerfilKdfDesconocido(' + IntToStr(malo) + '))', Format('perfil %d se rechaza por nombre', [malo]));
  end;
  m := Copy(claro, 0, Length(claro)); m[6] := 1;
  ChR(Abrir(m, a), 'Indice(ReservadoNoCero)', 'sin cifrado el byte sigue siendo reservado');

  Writeln('--- los_campos_mudados_deben_estar_en_cero');
  ChR(Abrir(cif, B('pass'), a), 'Ninguno', 'control: intacto abre');
  cuenta := 0; rechazadas := 0;
  for i := TAM_CLARO_CABECERA to TAM_CABECERA - 1 do
    for bit := 0 to 7 do begin
      Inc(cuenta); m := Copy(cif, 0, Length(cif)); m[i] := m[i] xor (1 shl bit);
      if not Abrir(m, B('pass'), a).Ok then Inc(rechazadas);
    end;
  Ch(cuenta = 160, '20 bytes x 8 bits = 160 celdas');
  Ch(rechazadas = cuenta, Format('%d de %d bits rechazados', [rechazadas, cuenta]));

  Writeln('--- round_trip_cifrado_con_pjg_reales');
  e := Reales(8); k := CC('contrase'#$C3#$B1'a de prueba');
  ChR(EscribirContenedor(e, FLAG_CIFRADO, k, cif, av), 'Ninguno', 'escribir 8 .pjg cifrados');
  ri := LeerIndice(cif, ct);
  Ch(not ri.Ok, 'el indice cifrado no se deserializa en claro');
  cuenta := 0;
  for i := 0 to High(e) do if Contiene(cif, e[i].nombre) then Inc(cuenta);
  Ch(cuenta = 0, 'ningun nombre queda visible');
  ChR(Abrir(cif, B('contrase'#$C3#$B1'a de prueba'), a), 'Ninguno', 'abrir');
  Ch(Length(a.contenedor.miembros) = 8, '8 miembros');
  cuenta := 0;
  for i := 0 to High(e) do begin
    h := Blake3_128(a.payloads[i]);
    if Igual(a.payloads[i], e[i].payload) and CompareMem(@h, @a.contenedor.miembros[i].hash, 16) then Inc(cuenta);
  end;
  Ch(cuenta = 8, 'los 8 byte-exactos y con su hash');

  Writeln('--- round_trip_sin_cifrar_sigue_andando');
  e := Reales(5);
  EscribirContenedor(e, 0, claro, av);
  ChR(Abrir(claro, a), 'Ninguno', 'abrir en claro');
  Ch((Length(a.payloads) = 5) and TodosIguales(a, e), '5 payloads iguales');

  Writeln('--- contrasena_incorrecta_no_llega_al_indice');
  e := Reales(4); k := CC('buena');
  EscribirContenedor(e, FLAG_CIFRADO, k, cif, av);
  ChR(Abrir(cif, B('mala'), a), 'Cifrado(TrozoAlterado(0))', 'contrasena mala');
  Ch(Length(a.payloads) = 0, 'y no sale ningun payload');

  Writeln('--- contrasena_faltante_y_sobrante');
  e := Reales(3); k := CC('x');
  EscribirContenedor(e, FLAG_CIFRADO, k, cif, av);
  ChR(Abrir(cif, a), 'Contrase'#$C3#$B1'aFaltante', 'cifrado sin contrasena');
  EscribirContenedor(e, 0, claro, av);
  ChR(Abrir(claro, B('x'), a), 'Contrase'#$C3#$B1'aSobrante', 'en claro con contrasena');
  ChR(EscribirContenedor(e, FLAG_CIFRADO, m, av), 'Contrase'#$C3#$B1'aFaltante', 'escribir cifrado sin clave');
  Ch(Length(m) = 0, '  y no devuelve bytes');

  Writeln('--- un_bit_en_el_cuerpo_cifrado_no_llega_al_codec');
  e := Reales(4); k := CC('x');
  EscribirContenedor(e, FLAG_CIFRADO, k, cif, av);
  i := TAM_CABECERA + TAM_SAL + TAM_NONCE + 40; cif[i] := cif[i] xor 1;
  Ch(Pos('Cifrado(TrozoAlterado(', Abrir(cif, B('x'), a).Texto) = 1, 'un bit en el cuerpo -> TrozoAlterado');

  Writeln('--- rutas_y_unicode_cifrados');
  e := Reales(2);
  e[0].nombre := B('2026/enero/'#$C3#$B1'and'#$C3#$BA'.jpg'); e[1].nombre := B('2026/enero/'#$E5#$86#$99#$E7#$9C#$9F'.jpg');
  ChR(EscribirContenedor(e, FLAG_CIFRADO or FLAG_RUTAS, k, cif, av), 'Ninguno', 'escribir con rutas y unicode');
  Ch(Length(av) = 0, 'sin avisos');
  ChR(Abrir(cif, B('x'), a), 'Ninguno', 'abrir');
  Ch(Igual(a.contenedor.miembros[0].nombre, e[0].nombre), 'el nombre vuelve igual');

  Writeln('--- (Pascal) contrasena vacia: es una contrasena, no "ninguna"');
  e := Reales(2); k := CC('');
  EscribirContenedor(e, FLAG_CIFRADO, k, cif, av);
  ChR(Abrir(cif, TBytes(nil), a), 'Ninguno', 'cifrado con "" abre con ""');
  ChR(Abrir(cif, a), 'Contrase'#$C3#$B1'aFaltante', 'y sin contrasena falta');

  archivos.Free;
  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 40 then begin Writeln('FALLA: esperaba al menos 40 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
