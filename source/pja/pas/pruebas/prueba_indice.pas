{ Port de las pruebas de pjacore/src/indice.rs (baterias 4.1 y 4.2 de
  doc/FORMATO.md), mas las tres del arreglo de duplicados cuadraticos. }
program prueba_indice;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_indice: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, pjacripto, pjaindice;   { sin DateUtils: es otro paquete de FPC, y GetTickCount64 alcanza }

var celdas, fallas: Integer;
procedure ChR(const r: TResultado; const esperado, q: string);
begin
  Inc(celdas);
  if r.Texto = esperado then Writeln('  ', q:56, '  ok')
  else begin Inc(fallas); Writeln('  ', q:56, '  FALLA: dio ', r.Texto, ', esperaba ', esperado); end;
end;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:56, '  ok') else begin Inc(fallas); Writeln('  ', q:56, '  FALLA'); end; end;

procedure PonU16(var b: TBytes; i: SizeInt; v: LongWord); begin b[i] := v and $FF; b[i+1] := (v shr 8) and $FF; end;
procedure PonU32(var b: TBytes; i: SizeInt; v: LongWord); var k: Integer; begin for k := 0 to 3 do b[i+k] := (v shr (8*k)) and $FF; end;
procedure PonU64(var b: TBytes; i: SizeInt; v: QWord); var k: Integer; begin for k := 0 to 7 do b[i+k] := (v shr (8*k)) and $FF; end;
function B(const s: RawByteString): TBytes; begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;

procedure Resellar(var c: TBytes);
var ti: LongWord; h: THash16;
begin
  ti := LongWord(c[8]) or (LongWord(c[9]) shl 8) or (LongWord(c[10]) shl 16) or (LongWord(c[11]) shl 24);
  h := HashCabeceraIndice(c, TAM_CABECERA, ti);
  Move(h[0], c[12], 16);
end;

{ Mismo `armar` que el Rust: N miembros con payloads de `tam`. }
function Armar(const nombres: array of RawByteString; tam: QWord; flags: Byte): TBytes;
var idx: TBytes; i, p: SizeInt; n: RawByteString;
begin
  idx := nil; SetLength(idx, 4); PonU32(idx, 0, Length(nombres));
  for i := 0 to High(nombres) do begin
    n := nombres[i]; p := Length(idx); SetLength(idx, p + 2 + Length(n) + 33);
    PonU16(idx, p, Length(n)); if n <> '' then Move(n[1], idx[p+2], Length(n));
    PonU64(idx, p + 2 + Length(n), tam * 2);        { tam_orig }
    PonU64(idx, p + 10 + Length(n), tam);           { tam_payload }
    FillChar(idx[p + 18 + Length(n)], 17, 0);       { hash + m_flags }
  end;
  Result := nil; SetLength(Result, TAM_CABECERA + Length(idx) + tam * Length(nombres));
  FillChar(Result[0], Length(Result), 0);
  Move(MAGIA[0], Result[0], 4); Result[4] := VERSION; Result[5] := flags;
  PonU32(Result, 8, Length(idx)); Move(idx[0], Result[TAM_CABECERA], Length(idx));
  Resellar(Result);
end;

function M(const n: RawByteString; orig, pay: QWord): TMiembro;
begin Result.nombre := B(n); Result.tam_orig := orig; Result.tam_payload := pay; FillChar(Result.hash, 16, 0); Result.m_flags := 0; end;

var c: TBytes; ct: TContenedor; fl: Byte; ti: LongWord; hd: THash16; ms: TMiembros;
    i: Integer; t0: QWord; seg: Double; vacio: TBytes;
begin
  celdas := 0; fallas := 0;
  Writeln('--- el_control_positivo_un_contenedor_valido_se_lee');
  c := Armar(['a.jpg', 'b.jpg'], 100, 0);
  ChR(LeerIndice(c, ct), 'Ninguno', 'un contenedor valido se lee');
  Ch(Length(ct.miembros) = 2, '2 miembros');
  Ch((Length(ct.miembros) = 2) and (Length(ct.miembros[0].nombre) = 5) and (ct.miembros[0].nombre[0] = Ord('a')), 'el primero es a.jpg');

  Writeln('--- bateria_4_1_cabecera');
  c := Armar(['a.jpg'], 100, 0); c[0] := Ord('X');  ChR(LeerCabecera(c, fl, ti, hd), 'NoEsContenedor', 'magia cambiada');
  c := Armar(['a.jpg'], 100, 0); c[4] := 99;        ChR(LeerCabecera(c, fl, ti, hd), 'VersionFutura(99)', 'version 99');
  c := Armar(['a.jpg'], 100, 0); c[4] := 2;         ChR(LeerCabecera(c, fl, ti, hd), 'VersionFutura(2)', 'version 2 (la trampa version/VERSION)');
  c := Armar(['a.jpg'], 100, 0); c[6] := 1;         ChR(LeerCabecera(c, fl, ti, hd), 'ReservadoNoCero', 'byte kdf sin cifrado');
  c := Armar(['a.jpg'], 100, 0); c[5] := $80;       ChR(LeerCabecera(c, fl, ti, hd), 'FlagDesconocido', 'flag 0x80');
  vacio := nil;                                      ChR(LeerCabecera(vacio, fl, ti, hd), 'ArchivoCorto', 'archivo vacio');
  SetLength(c, 27); FillChar(c[0], 27, 0);           ChR(LeerCabecera(c, fl, ti, hd), 'ArchivoCorto', '27 bytes');
  c := Armar(['a.jpg'], 100, 0); PonU32(c, 8, $FFFFFFFF); ChR(LeerCabecera(c, fl, ti, hd), 'IndiceNoEntra', 'tam_indice = 0xFFFFFFFF');

  Writeln('--- bateria_4_2_indice');
  c := Armar(['a.jpg'], 100, 0); PonU32(c, TAM_CABECERA, $FFFFFFFF); Resellar(c);
  ChR(LeerIndice(c, ct), 'DemasiadosMiembros(4294967295)', 'count = u32::MAX');
  c := Armar(['a.jpg'], 100, 0); PonU32(c, TAM_CABECERA, 10000); Resellar(c);
  ChR(LeerIndice(c, ct), 'CountImposible', 'count 10.000 en archivo chico');
  c := Armar(['a.jpg'], 100, 0); SetLength(c, Length(c) + 1); c[High(c)] := 0;
  ChR(LeerIndice(c, ct), 'SumaNoCuadra', 'un byte de mas');
  c := Armar(['a.jpg'], 0, 0);           ChR(LeerIndice(c, ct), 'PayloadFueraDeRango(0)', 'payload de 0');
  c := Armar(['a.jpg', 'a.jpg'], 100, 0); ChR(LeerIndice(c, ct), 'NombreDuplicado(1)', 'nombre duplicado');
  c := Armar(['../x.jpg'], 100, 0);      ChR(LeerIndice(c, ct), 'NombreInvalido(0)', 'nombre invalido');

  Writeln('--- el_hash_del_indice_detecta_un_bit_alterado');
  c := Armar(['a.jpg', 'b.jpg'], 100, 0);
  ChR(LeerIndice(c, ct), 'Ninguno', 'control positivo');
  c[TAM_CABECERA + 6] := c[TAM_CABECERA + 6] xor $20;
  ChR(LeerIndice(c, ct), 'IndiceAlterado', 'un bit en el nombre');
  Resellar(c);
  ChR(LeerIndice(c, ct), 'Ninguno', 'resellado se lee: el chequeo mira el indice');

  Writeln('--- la_suma_no_desborda_antes_de_comparar');
  ms := nil; SetLength(ms, 2); ms[0] := M('a', High(QWord), 100); ms[1] := M('b', High(QWord), 100);
  ChR(Validar(ms, 0, 1000, 50), 'Desborde', 'dos tam_orig = u64::MAX');

  Writeln('--- la_suma_del_limite_3_no_da_la_vuelta');
  SetLength(ms, 1); ms[0] := M('a', 1, High(QWord) - 10);
  ChR(Validar(ms, 0, High(QWord), 50), 'Desborde', 'payload + indice + cabecera > u64::MAX');

  Writeln('--- el_duplicado_se_reporta_en_el_mismo_indice');
  SetLength(ms, 5); ms[0] := M('a',100,100); ms[1] := M('b',100,100); ms[2] := M('c',100,100);
  ms[3] := M('b',100,100); ms[4] := M('a',100,100);
  ChR(Validar(ms, 0, QWord(1) shl 40, 50), 'NombreDuplicado(3)', '[a b c b a] -> el primero con repetido: 3');

  Writeln('--- los_duplicados_no_son_cuadraticos');
  SetLength(ms, 200000);
  for i := 0 to High(ms) do ms[i] := M('aaaa' + Format('%.8d', [i]), 100, 100);
  t0 := GetTickCount64; ChR(Validar(ms, 0, QWord(1) shl 40, 50), 'SumaNoCuadra', '200.000 nombres distintos llegan al limite 3');
  seg := (GetTickCount64 - t0) / 1000;
  Ch(seg < 10, Format('  y tardan %.2f s (tope 10)', [seg]));

  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 25 then begin Writeln('FALLA: esperaba al menos 25 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
