{ Port de las pruebas de pjacore/src/nombres.rs, celda por celda, mas los bordes
  de UTF-8. Cada celda se cuenta: el codigo de salida solo no dice cuantas
  corrieron. }
program prueba_nombres;

{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_nombres: range checks ($R+) son obligatorios}{$endif}

uses
  SysUtils, pjalimites, pjanombres;

var
  celdas, fallas: Integer;

function B(const s: RawByteString): TBytes;
begin
  { RawByteString: sin transcodificacion. Los literales de abajo son bytes. }
  SetLength(Result, Length(s));
  if Length(s) > 0 then Move(s[1], Result[0], Length(s));
end;

function Repetir(const s: RawByteString; n: Integer): RawByteString;
var i: Integer;
begin
  Result := '';
  for i := 1 to n do Result := Result + s;
end;

procedure Ch(const obtenido, esperado: TVeredicto; const q: string);
begin
  Inc(celdas);
  if obtenido.Igual(esperado) then
    Writeln('  ', q:58, '  ok')
  else begin
    Inc(fallas);
    Writeln('  ', q:58, '  FALLA: dio ', obtenido.Texto, ', esperaba ', esperado.Texto);
  end;
end;

procedure ChB(v, esperado: Boolean; const q: string);
begin
  Inc(celdas);
  if v = esperado then Writeln('  ', q:58, '  ok')
  else begin Inc(fallas); Writeln('  ', q:58, '  FALLA'); end;
end;

function R(m: TMotivo): TVeredicto; begin Result := TVeredicto.Rechazo(m); end;
function W(m: TMotivo): TVeredicto; begin Result := TVeredicto.SoloWindows(m); end;
function OK: TVeredicto; begin Result := TVeredicto.Ok; end;

var
  a255, a256, acent128, acent127: RawByteString;
begin
  celdas := 0; fallas := 0;

  Writeln('--- control: la proteccion de rango esta prendida');
  Inc(celdas);
  {$ifopt R+} Writeln('  ', 'R+ activo':58, '  ok'); {$else} Inc(fallas); Writeln('  R+ APAGADO  FALLA'); {$endif}

  Writeln('--- peligro_se_rechaza_siempre');
  Ch(Ruta(B('../../etc/passwd')),  R(mComponentePadre), '../../etc/passwd');
  Ch(Ruta(B('/etc/passwd')),       R(mRutaAbsoluta),    '/etc/passwd');
  Ch(Ruta(B('C:\Windows\x')),      R(mLetraDeUnidad),   'C:\Windows\x');
  Ch(Ruta(B('a/../../b')),         R(mComponentePadre), 'a/../../b');
  Ch(Plano(B('foto.jpg:carga')),   R(mDosPuntos),       'foto.jpg:carga');
  Ch(Plano(B('con'#0'nulo')),      R(mByteDeControl),   'con\0nulo');
  Ch(Plano(B('salto'#10'linea')),  R(mByteDeControl),   'salto\nlinea');
  Ch(Plano(B(#$FF#$FE)),           R(mUtf8Invalido),    '\xff\xfe');
  Ch(Plano(B('')),                 R(mVacio),           '(vacio)');

  Writeln('--- el_limite_es_en_bytes_no_en_caracteres');
  a255 := StringOfChar('a', 255); a256 := StringOfChar('a', 256);
  acent128 := Repetir(#$C3#$A1, 128); acent127 := Repetir(#$C3#$A1, 127);
  Ch(Plano(B(a255)), OK, '255 x "a"');
  Ch(Plano(B(a256)), R(mComponenteMuyLargo), '256 x "a"');
  ChB(Length(acent128) = 256, True, '128 x "a con tilde" son 256 bytes');
  Ch(Plano(B(acent128)), R(mComponenteMuyLargo), '128 acentuados (256 B)');
  ChB(Length(acent127) = 254, True, '127 x "a con tilde" son 254 bytes');
  Ch(Plano(B(acent127)), OK, '127 acentuados (254 B)');

  Writeln('--- profundidad_y_largo_total');
  Ch(Ruta(B(Repetir('a/', 33) + 'f.jpg')),  R(mMuyProfunda), '"a/" x 33 + f.jpg');
  Ch(Ruta(B(Repetir('a/', 600) + 'f.jpg')), R(mRutaMuyLarga), '"a/" x 600 + f.jpg');

  Writeln('--- incompatible_con_windows_pero_legal_en_linux');
  Ch(Plano(B('CON.jpg')),      W(mNombreReservado),        'CON.jpg');
  Ch(Plano(B('nul.JPG')),      W(mNombreReservado),        'nul.JPG');
  Ch(Plano(B('LPT9')),         W(mNombreReservado),        'LPT9');
  Ch(Plano(B('archivo.jpg ')), W(mTerminaEnPuntoOEspacio), '"archivo.jpg " (espacio final)');
  Ch(Plano(B('archivo.')),     W(mTerminaEnPuntoOEspacio), 'archivo.');
  Ch(Plano(B('archivo .jpg')), OK,                         '"archivo .jpg" (espacio en el medio)');
  Ch(Plano(B('foto?.jpg')),    W(mCaracterIlegalEnWindows), 'foto?.jpg');
  Ch(Plano(B('a<b>.jpg')),     W(mCaracterIlegalEnWindows), 'a<b>.jpg');

  Writeln('--- lo_que_pasa_sin_objecion');
  Ch(Plano(B(#$C3#$B1'and'#$C3#$BA'.jpg')), OK, 'nandu.jpg (con ene y u acentuada)');
  Ch(Plano(B(#$E5#$86#$99#$E7#$9C#$9F'.jpg')), OK, '(dos kanji).jpg');
  Ch(Plano(B('foto 1 (a).jpg')), OK, 'foto 1 (a).jpg');
  Ch(Ruta(B('2026/enero/foto.jpg')), OK, '2026/enero/foto.jpg');

  Writeln('--- control_negativo_el_validador_discrimina');
  Ch(Plano(B('normal.jpg')), OK, 'normal.jpg');
  ChB(Plano(B('normal.jpg')).Igual(Plano(B('../x'))), False, 'normal.jpg y ../x dan veredictos distintos');

  Writeln('--- UTF-8 estricto (tabla 3-7 de Unicode), bordes');
  ChB(Utf8Valido(B('')), True, 'vacio');
  ChB(Utf8Valido(B(#$7F)), True, 'U+007F');
  ChB(Utf8Valido(B(#$C2#$80)), True, 'U+0080, el primer 2 bytes');
  ChB(Utf8Valido(B(#$C0#$80)), False, 'C0 80: sobrelargo');
  ChB(Utf8Valido(B(#$C1#$BF)), False, 'C1 BF: sobrelargo');
  ChB(Utf8Valido(B(#$E0#$80#$80)), False, 'E0 80 80: sobrelargo de 3');
  ChB(Utf8Valido(B(#$E0#$A0#$80)), True, 'E0 A0 80 = U+0800');
  ChB(Utf8Valido(B(#$ED#$9F#$BF)), True, 'ED 9F BF = U+D7FF, justo antes de sustitutos');
  ChB(Utf8Valido(B(#$ED#$A0#$80)), False, 'ED A0 80 = U+D800, sustituto');
  ChB(Utf8Valido(B(#$ED#$BF#$BF)), False, 'ED BF BF = U+DFFF, sustituto');
  ChB(Utf8Valido(B(#$EE#$80#$80)), True, 'EE 80 80 = U+E000');
  ChB(Utf8Valido(B(#$F0#$80#$80#$80)), False, 'F0 80 80 80: sobrelargo de 4');
  ChB(Utf8Valido(B(#$F0#$90#$80#$80)), True, 'F0 90 80 80 = U+10000');
  ChB(Utf8Valido(B(#$F4#$8F#$BF#$BF)), True, 'F4 8F BF BF = U+10FFFF, el ultimo');
  ChB(Utf8Valido(B(#$F4#$90#$80#$80)), False, 'F4 90 80 80 > U+10FFFF');
  ChB(Utf8Valido(B(#$F5#$80#$80#$80)), False, 'F5: nunca valido');
  ChB(Utf8Valido(B(#$80)), False, 'continuacion suelta');
  ChB(Utf8Valido(B(#$C3)), False, 'truncado: falta la continuacion');
  ChB(Utf8Valido(B(#$E2#$82)), False, 'truncado de 3');
  ChB(Utf8Valido(B(#$F8#$88#$80#$80#$80)), False, 'forma de 5 bytes');

  Writeln;
  Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 50 then begin Writeln('FALLA: esperaba al menos 50 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
