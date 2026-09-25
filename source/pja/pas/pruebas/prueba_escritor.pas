{ Port de las pruebas de pjacore/src/escritor.rs, mas el round-trip con .pjg
  reales (directorio en el primer parametro). }
program prueba_escritor;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_escritor: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, pjalimites, pjanombres, pjacripto, pjaindice, pjaescritor;

var celdas, fallas: Integer;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:60, '  ok') else begin Inc(fallas); Writeln('  ', q:60, '  FALLA'); end; end;
procedure ChT(const obtenido, esperado, q: string);
begin Inc(celdas); if obtenido = esperado then Writeln('  ', q:60, '  ok')
  else begin Inc(fallas); Writeln('  ', q:60, '  FALLA: dio ', obtenido, ', esperaba ', esperado); end; end;
function B(const s: RawByteString): TBytes; begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;
function Relleno(n: SizeInt; v: Byte): TBytes; begin Result := nil; SetLength(Result, n); if n > 0 then FillChar(Result[0], n, v); end;
function Ent(const n: RawByteString; const p: TBytes): TEntrada;
begin Result.nombre := B(n); Result.tam_orig := QWord(Length(p)) * 2; Result.payload := p; FillChar(Result.hash, 16, 7); end;
function Igual(const a, b: TBytes): Boolean;
begin Result := (Length(a) = Length(b)) and ((Length(a) = 0) or CompareMem(@a[0], @b[0], Length(a))); end;
function Tramo(const x: TBytes; ini, n: QWord): TBytes; begin Result := Copy(x, SizeInt(ini), SizeInt(n)); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead); try Result := nil; SetLength(Result, s.Size); if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;

var es: TEntradas; bytes: TBytes; av: TAvisos; c: TContenedor; fl: Byte; ti: LongWord; hd: THash16;
    offs: TDesplazamientos; a, bb: TBytes; i, n, total: SizeInt; t0: QWord; sr: TSearchRec; dir: string;
    rutas: array of string; h: THash16; todoIgual: Boolean;
begin
  celdas := 0; fallas := 0;

  Writeln('--- round_trip_lo_que_se_escribe_se_lee_igual');
  a := Relleno(100, 1); bb := Relleno(250, 2);
  es := nil; SetLength(es, 2); es[0] := Ent('a.jpg', a); es[1] := Ent('b.jpg', bb);
  ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', 'escribir');
  Ch(Length(av) = 0, 'sin avisos');
  ChT(LeerIndice(bytes, c).Texto, 'Ninguno', 'lo que escribimos se lee');
  Ch((Length(c.miembros) = 2) and Igual(c.miembros[0].nombre, B('a.jpg')), '2 miembros, el primero a.jpg');
  Ch((c.miembros[0].tam_payload = 100) and (c.miembros[1].tam_payload = 250), 'tam_payload 100 y 250');
  Ch(c.miembros[0].hash[5] = 7, 'hash conservado');
  LeerCabecera(bytes, fl, ti, hd); offs := Desplazamientos(c, ti);
  Ch(Igual(Tramo(bytes, offs[0], 100), a) and Igual(Tramo(bytes, offs[1], 250), bb),
     'los payloads salen byte por byte donde dice el indice');

  Writeln('--- round_trip_con_rutas_y_unicode');
  a := Relleno(64, 9); SetLength(es, 2);
  es[0] := Ent('2026/enero/'#$C3#$B1'and'#$C3#$BA'.jpg', a); es[1] := Ent('2026/enero/'#$E5#$86#$99#$E7#$9C#$9F'.jpg', a);
  ChT(Escribir(es, FLAG_RUTAS, bytes, av).Texto, 'Ninguno', 'escribir con rutas');
  ChT(LeerIndice(bytes, c).Texto, 'Ninguno', 'se lee');
  Ch(Igual(c.miembros[0].nombre, es[0].nombre) and Igual(c.miembros[1].nombre, es[1].nombre), 'nombres UTF-8 intactos');

  Writeln('--- avisa_pero_escribe_lo_que_solo_rompe_en_windows');
  a := Relleno(32, 3); SetLength(es, 2); es[0] := Ent('foto?.jpg', a); es[1] := Ent('CON.jpg', a);
  ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', 'escribe');
  Ch((Length(av) = 2) and (av[0].motivo = mCaracterIlegalEnWindows) and (av[1].motivo = mNombreReservado), 'dos avisos, en orden');
  ChT(LeerIndice(bytes, c).Texto, 'Ninguno', 'y el contenedor es valido');

  Writeln('--- no_escribe_lo_que_no_podria_leer (lo que SI chequea)');
  a := Relleno(32, 1);
  SetLength(es, 1); es[0] := Ent('../x.jpg', a); ChT(Escribir(es, FLAG_RUTAS, bytes, av).Texto, 'NombreInvalido(0)', '../x.jpg');
  SetLength(es, 2); es[0] := Ent('a.jpg', a); es[1] := Ent('a.jpg', a); ChT(Escribir(es, 0, bytes, av).Texto, 'NombreDuplicado(1)', 'duplicado');
  SetLength(es, 1); es[0] := Ent('a.jpg', Relleno(4, 0)); ChT(Escribir(es, 0, bytes, av).Texto, 'PayloadFueraDeRango(0)', 'payload de 4 B');

  Writeln('--- CONOCIDO, pendiente de decision: escribe lo que el lector rechaza');
  { Esta prueba PASA mientras el defecto exista. Cuando se decida el arreglo va
    a FALLAR, y hay que cambiarla a conciencia: no borrarla. }
  SetLength(es, 1); es[0] := Ent('foto.jpg', Relleno(18000000, 7));
  es[0].tam_orig := QWord(8) * 1024 * 1024 * 1024 + 1;
  ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', 'backup de 8 GiB + 1: escribir dice Ok');
  ChT(LeerIndice(bytes, c).Texto, 'PresupuestoExcedido', '  ...y leer lo rechaza');

  Writeln('--- contenedor_vacio_es_valido_y_se_lee');
  es := nil;
  ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', 'escribir vacio');
  ChT(LeerIndice(bytes, c).Texto, 'Ninguno', 'leer vacio');
  Ch(Length(c.miembros) = 0, '0 miembros');

  Writeln('--- el_duplicado_se_reporta_en_el_mismo_indice');
  a := Relleno(32, 1); SetLength(es, 5);
  es[0] := Ent('a', a); es[1] := Ent('b', a); es[2] := Ent('c', a); es[3] := Ent('b', a); es[4] := Ent('a', a);
  ChT(Escribir(es, 0, bytes, av).Texto, 'NombreDuplicado(3)', '[a b c b a] -> 3');

  Writeln('--- los_duplicados_no_son_cuadraticos');
  a := Relleno(12, 0); SetLength(es, 200000);
  for i := 0 to High(es) do es[i] := Ent('aaaa' + Format('%.8d', [i]) + '.jpg', a);
  t0 := GetTickCount64; ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', '200.000 nombres distintos');
  Ch((GetTickCount64 - t0) < 10000, Format('  en %.2f s (tope 10)', [(GetTickCount64 - t0) / 1000]));

  Writeln('--- demasiados miembros (el Rust no lo prueba: se chequea antes de todo)');
  es := nil; SetLength(es, MAX_MIEMBROS + 1);
  ChT(Escribir(es, 0, bytes, av).Texto, 'DemasiadosMiembros', '1.048.577 entradas');
  SetLength(es, 0);

  Writeln('--- round_trip_con_pjg_reales');
  dir := ParamStr(1); rutas := nil;
  if (dir = '') or (FindFirst(IncludeTrailingPathDelimiter(dir) + '*.pjg', faAnyFile, sr) <> 0) then begin
    Inc(celdas); Inc(fallas); Writeln('  FALLA: no hay .pjg en "', dir, '" (make pja-corpus)'); end
  else begin
    repeat SetLength(rutas, Length(rutas) + 1); rutas[High(rutas)] := sr.Name; until FindNext(sr) <> 0;
    FindClose(sr);
    n := Length(rutas); SetLength(es, n);
    for i := 0 to n - 1 do begin
      es[i].nombre := B(rutas[i]); es[i].payload := Leer(IncludeTrailingPathDelimiter(dir) + rutas[i]);
      es[i].tam_orig := QWord(Length(es[i].payload)) * 2; es[i].hash := Blake3_128(es[i].payload);
    end;
    Ch(n >= 10, Format('al menos 10 .pjg reales (hay %d)', [n]));
    ChT(Escribir(es, 0, bytes, av).Texto, 'Ninguno', 'escribir los .pjg reales');
    ChT(LeerIndice(bytes, c).Texto, 'Ninguno', 'leerlos');
    LeerCabecera(bytes, fl, ti, hd); offs := Desplazamientos(c, ti);
    todoIgual := Length(c.miembros) = n; total := 0;
    for i := 0 to n - 1 do begin
      a := Tramo(bytes, offs[i], c.miembros[i].tam_payload); h := Blake3_128(a);
      if not Igual(a, es[i].payload) or not CompareMem(@h[0], @c.miembros[i].hash[0], 16) then todoIgual := False;
      total := total + Length(a);
    end;
    Ch(todoIgual, Format('%d miembros, %d bytes, byte-exactos y con hash', [n, total]));
    Ch(Length(bytes) - total < 4096, Format('sobrecarga del contenedor: %d bytes', [Length(bytes) - total]));
  end;

  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 30 then begin Writeln('FALLA: esperaba al menos 30 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
