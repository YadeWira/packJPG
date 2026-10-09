{ Port de las pruebas de pjacore/src/cifrado.rs (bateria 4.4 de
  doc/FORMATO.md), mas los vectores KAT del Rust: Argon2id y el cifrado por
  trozos tienen que salir BYTE A BYTE iguales, en los bordes de TAM_TROZO. }
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
function Igual(const a, b: TBytes): Boolean;
begin Result := (Length(a) = Length(b)) and ((Length(a) = 0) or CompareMem(@a[0], @b[0], Length(a))); end;
function Leer(const f: string): TBytes; var s: TFileStream;
begin s := TFileStream.Create(f, fmOpenRead); try Result := nil; SetLength(Result, s.Size);
  if s.Size > 0 then s.ReadBuffer(Result[0], s.Size); finally s.Free; end; end;
function DeHex(const s: string): TBytes; var i: SizeInt;
begin Result := nil; SetLength(Result, Length(s) div 2);
  for i := 0 to High(Result) do Result[i] := StrToInt('$' + Copy(s, 2*i+1, 2)); end;

const KAT_NOMBRES: array[0..4] of string = ('vacio', 'uno', 'trozo_justo', 'trozo_mas_uno', 'varios');
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

var d, ct, mal, pt, x: TBytes; k, otra: TClave; t: specialize TArray<TTrozo>;
    s2: TSal; a, bb, c: TNonce; kat, l, nom: string; f: TextFile; kv: TStringList;
    pass: TBytes; i: Integer;
begin
  celdas := 0; fallas := 0; kat := ParamStr(1);
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

  Writeln('--- KAT del Rust (', kat, ')');
  kv := TStringList.Create; kv.NameValueSeparator := ' ';
  AssignFile(f, kat + '/kdf.txt'); Reset(f);
  while not Eof(f) do begin ReadLn(f, l); kv.Add(l); end; CloseFile(f);
  pass := DeHex(kv.Values['pass']);
  x := DeHex(kv.Values['sal']); Move(x[0], s2[0], TAM_SAL);
  x := DeHex(kv.Values['nonce_base']); Move(x[0], a[0], TAM_NONCE);
  ChR(DerivarClave(pass, s2, otra), 'Ninguno', 'Argon2id V1');
  x := DeHex(kv.Values['clave']);
  Ch((Length(x) = 32) and CompareMem(@x[0], @otra[0], 32), 'clave Argon2id = Rust');
  kv.Free;
  { con un arreglo constante: `for nom in ['vacio', ...]` en FPC recorta los
    literales al largo del primero -- 'trozo_justo' llegaba como 'trozo' }
  for nom in KAT_NOMBRES do begin
    d := Leer(kat + '/' + nom + '.plano'); x := Leer(kat + '/' + nom + '.cifrado');
    Cifrar(otra, a, d, ct);
    Ch(Igual(ct, x), Format('cifrar %s (%d B) = Rust byte a byte', [nom, Length(d)]));
    ChR(Descifrar(otra, a, x, pt), 'Ninguno', Format('  descifrar el del Rust', []));
    Ch(Igual(pt, d), '  y vuelve el mismo claro');
  end;

  Writeln; Writeln(celdas, ' celdas, ', fallas, ' fallas');
  if celdas < 30 then begin Writeln('FALLA: esperaba al menos 30 celdas'); Halt(2); end;
  if fallas > 0 then Halt(1);
end.
