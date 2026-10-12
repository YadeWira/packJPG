{ El esquema por trozos: lo que tiene que fallar, falla con SU error. Los
  vectores byte a byte contra el Rust estan en prueba_cripto (kat.txt). }
program prueba_cifrado;
{$I ../pja.inc}
{$ifopt R-}{$fatal prueba_cifrado: range checks ($R+) son obligatorios}{$endif}
uses SysUtils, Classes, pjacripto, pjacifrado;

var celdas, fallas: Integer;
procedure ChR(const r: TResultadoCifrado; const esperado, q: string);
begin
  Inc(celdas);
  if r.Texto = esperado then Writeln('  ', q:56, '  ok')
  else begin Inc(fallas); Writeln('  ', q:56, '  FALLA: dio ', r.Texto, ', esperaba ', esperado); end;
end;
procedure Ch(ok: Boolean; const q: string);
begin Inc(celdas); if ok then Writeln('  ', q:56, '  ok') else begin Inc(fallas); Writeln('  ', q:56, '  FALLA'); end; end;

function B(const s: RawByteString): TBytes; begin Result := nil; SetLength(Result, Length(s)); if s <> '' then Move(s[1], Result[0], Length(s)); end;
function Igual(const x, y: TBytes): Boolean;
begin Result := (Length(x) = Length(y)) and ((Length(x) = 0) or CompareMem(@x[0], @y[0], Length(x))); end;

var SAL: TSal; NB: TNonce;
function Clave(const p: RawByteString): TClave;
begin if not DerivarClave(B(p), SAL, Result).Ok then raise Exception.Create('derivar_clave'); end;
{ Tres trozos y pico, para que reordenar y truncar tengan sentido. }
function Datos: TBytes; var i: SizeInt;
begin Result := nil; SetLength(Result, TAM_TROZO * 3 + 1234); for i := 0 to High(Result) do Result[i] := i mod 251; end;
type TTrozo = record ini, lar: SizeInt; end;
function Trozos(const c: TBytes): specialize TArray<TTrozo>; var p, n: SizeInt;
begin Result := nil; p := 0; n := 0;
  while p < Length(c) do begin SetLength(Result, n + 1); Result[n].ini := p;
    Result[n].lar := 4 + (SizeInt(c[p]) or (SizeInt(c[p+1]) shl 8) or (SizeInt(c[p+2]) shl 16) or (SizeInt(c[p+3]) shl 24));
    p := p + Result[n].lar; Inc(n); end; end;

var d, ct, mal, pt, vacio: TBytes; k, otra: TClave; t: specialize TArray<TTrozo>;
    s2: TSal; a, bb, c: TNonce;
begin
  celdas := 0; fallas := 0;
  FillChar(SAL, SizeOf(SAL), 7); FillChar(NB, SizeOf(NB), 3);
  d := Datos; k := Clave('secreta');

  Writeln('--- control_positivo_round_trip');
  ChR(Cifrar(k, NB, d, ct), 'Ninguno', 'cifrar');
  Ch(not CompareMem(@ct[0], @d[0], 64), 'el ciphertext no se parece al claro');
  ChR(Descifrar(k, NB, ct, pt), 'Ninguno', 'descifrar');
  Ch(Igual(pt, d), 'vuelve el mismo claro');

  Writeln('--- contrasena_incorrecta_no_llega_al_codec');
  ChR(Descifrar(Clave('otra'), NB, ct, pt), 'TrozoAlterado(0)', 'otra contrasena');
  Ch(Length(pt) = 0, 'y no sale ni un byte de claro');

  Writeln('--- un_bit_volteado_falla_el_tag');
  t := Trozos(ct); mal := Copy(ct, 0, Length(ct)); mal[t[1].ini + 10] := mal[t[1].ini + 10] xor 1;
  ChR(Descifrar(k, NB, mal, pt), 'TrozoAlterado(1)', 'un bit en el trozo 1');

  Writeln('--- sal_distinta_da_clave_distinta');
  FillChar(s2, SizeOf(s2), 9);
  ChR(DerivarClave(B('secreta'), s2, otra), 'Ninguno', 'derivar con otra sal');
  ChR(Descifrar(otra, NB, ct, pt), 'TrozoAlterado(0)', 'misma contrasena, otra sal');

  Writeln('--- dos_trozos_intercambiados_fallan_por_el_aad');
  Ch(t[0].lar = t[1].lar, 'trozos 0 y 1 del mismo largo');
  mal := Copy(ct, 0, Length(ct));
  Move(ct[t[1].ini], mal[t[0].ini], t[1].lar); Move(ct[t[0].ini], mal[t[1].ini], t[0].lar);
  ChR(Descifrar(k, NB, mal, pt), 'TrozoAlterado(0)', 'cada tag valido, el orden no');

  Writeln('--- quitar_el_ultimo_trozo_falla_por_la_marca_de_fin');
  ChR(Descifrar(k, NB, Copy(ct, 0, t[High(t)].ini), pt), 'Truncado', 'sin el ultimo trozo');

  Writeln('--- trozo_duplicado_falla_por_el_contador');
  mal := Copy(ct, t[0].ini, t[0].lar);
  mal := Concat(mal, Copy(ct, t[0].ini, t[0].lar), Copy(ct, t[2].ini, Length(ct)));
  ChR(Descifrar(k, NB, mal, pt), 'TrozoAlterado(1)', 'el trozo 0 dos veces');

  Writeln('--- nonce_distinto_por_trozo');
  a := NonceDe(NB, 0); bb := NonceDe(NB, 1); c := NonceDe(NB, 1000);
  Ch(not CompareMem(@a, @bb, TAM_NONCE), 'nonce 0 <> 1');
  Ch(not CompareMem(@bb, @c, TAM_NONCE), 'nonce 1 <> 1000');
  Ch(not CompareMem(@a, @c, TAM_NONCE), 'nonce 0 <> 1000');

  Writeln('--- nada_despues_del_ultimo_trozo');
  { Un trozo valido de mas solo lo arma quien tiene la clave; el Rust lo
    aceptaba. Aca: el ultimo trozo repetido al final, y basura de 1 a 4 B. }
  mal := Concat(Copy(ct, 0, Length(ct)), Copy(ct, t[High(t)].ini, t[High(t)].lar));
  ChR(Descifrar(k, NB, mal, pt), 'SobranTrozos', 'el ultimo trozo dos veces');
  Ch(Length(pt) = 0, 'y no sale ni un byte de claro');
  mal := Concat(Copy(ct, 0, Length(ct)), TBytes.Create(0));
  ChR(Descifrar(k, NB, mal, pt), 'SobranTrozos', 'un byte de basura al final');
  mal := Concat(Copy(ct, 0, Length(ct)), TBytes.Create(16, 0, 0, 0));
  ChR(Descifrar(k, NB, mal, pt), 'SobranTrozos', 'un largo de trozo al final, sin trozo');
  { y un archivo con el ultimo trozo marcado ANTES de tiempo: el que va
    primero ya es "ultimo" (claro de un solo trozo), el que sigue sobra }
  vacio := nil;
  Cifrar(k, NB, vacio, mal);
  mal := Concat(mal, Copy(ct, t[1].ini, t[1].lar));
  ChR(Descifrar(k, NB, mal, pt), 'SobranTrozos', 'un trozo despues de uno marcado ultimo');

  Writeln('--- vacio_es_un_trozo');
  Cifrar(k, NB, vacio, mal);
  Ch(Length(mal) = 4 + TAM_TAG, 'claro vacio -> un trozo de 20 B');
  ChR(Descifrar(k, NB, mal, pt), 'Ninguno', 'y se descifra');
  Ch(Length(pt) = 0, 'a nada');
  ChR(Descifrar(k, NB, vacio, pt), 'Truncado', 'cero trozos: falta la marca de fin');

  Writeln('--- descifrar_desde_un_desplazamiento');
  mal := Concat(TBytes.Create(1, 2, 3), Copy(ct, 0, Length(ct)));
  ChR(Descifrar(k, NB, mal, 3, pt), 'Ninguno', 'el cifrado detras de 3 bytes de otra cosa');
  Ch(Igual(pt, d), 'vuelve el mismo claro');
  ChR(Descifrar(k, NB, mal, 2, pt), 'Formato', 'arrancando un byte antes: largo absurdo');

  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 25 then begin Writeln('FALLA: esperaba al menos 25 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
