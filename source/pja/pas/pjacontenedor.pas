{ Une el contenedor con el cifrado. Port de pjacore/src/contenedor.rs.

  Cuando FLAG_CIFRADO esta puesto, indice y payloads viajan en la misma
  secuencia de trozos: el indice no se puede leer sin haber autenticado. Ese
  orden es lo que da la seguridad, no los chequeos sueltos.

  Layout cifrado:
    magia . version . flags . kdf . reservado   (en claro, 8 bytes)
    tam_indice(4) . hash(16)                    (en claro CERO; los de verdad
                                                 van adentro del cifrado)
    sal(16) . nonce_base(24)                    (en claro)
    trozos AEAD de [ tam_indice | hash | indice | payloads ]

  tam_indice y el hash no pueden quedar en claro. El hash es
  BLAKE3(cabecera | indice) y el indice es la lista de nombres: visible, el
  archivo seria un oraculo de confirmacion -- quien sospeche que nombres hay
  adentro los tipea, calcula el hash y compara, sin contrasena. tam_indice
  deja leer cuantos miembros hay y cuan largos son sus nombres.

  Diferencias con el Rust que no cambian ninguna salida:
  - la clave derivada se borra apenas se usa (el Rust la deja en la pila);
  - sin cifrado, el archivo no se copia antes de leer el indice. }
unit pjacontenedor;

{$I pja.inc}
{$ifopt R-}{$fatal pjacontenedor: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjacontenedor: overflow checks ($Q+) son obligatorios}{$endif}

interface

uses SysUtils, pjacripto, pjacifrado, pjaindice, pjaescritor;

const
  TAM_PREFIJO_CIFRADO = TAM_SAL + TAM_NONCE;
  { Lo que queda visible de la cabecera cifrada: magia, version, flags, kdf, reservado. }
  TAM_CLARO_CABECERA = 8;
  { Lo que se muda adentro del cifrado: tam_indice(4) + hash(16). }
  TAM_SECRETO_CABECERA = TAM_CABECERA - TAM_CLARO_CABECERA;

type
  TErrorContenedor = (ecoNinguno, ecoEscritura, ecoIndice, ecoCifrado,
                      { el archivo dice estar cifrado y no se dio contrasena, o al reves }
                      ecoContrasenaFaltante, ecoContrasenaSobrante, ecoArchivoCorto);

  TResultadoContenedor = record
    err: TErrorContenedor;
    escritura: TResultadoEscritura;   { con ecoEscritura }
    indice: TResultado;               { con ecoIndice }
    cifrado: TResultadoCifrado;       { con ecoCifrado }
    function Ok: Boolean;
    function Texto: string;           { mismo texto que el Debug de Rust }
  end;

  TClaveCifrado = record
    clave: TClave;
    nonce: TNonce;
    sal: TSal;
  end;

  TAbierto = record
    contenedor: TContenedor;
    payloads: array of TBytes;        { ya en claro, en el orden del indice }
  end;

{ Sin clave: el contenedor en claro (FLAG_CIFRADO en flags da ContrasenaFaltante). }
function EscribirContenedor(const es: TEntradas; flags: Byte;
                            out bytes: TBytes; out avisos: TAvisos): TResultadoContenedor; overload;
{ Con clave: cifrado (sin FLAG_CIFRADO en flags da ContrasenaSobrante). }
function EscribirContenedor(const es: TEntradas; flags: Byte; const cc: TClaveCifrado;
                            out bytes: TBytes; out avisos: TAvisos): TResultadoContenedor; overload;

{ El orden es el de doc/FORMATO.md: cabecera, autenticar, deserializar,
  limites, nombres, y recien ahi los payloads quedan disponibles para el codec.
  Sin contrasena y con contrasena (vacia vale: es una contrasena). }
function Abrir(const datos: TBytes; out a: TAbierto): TResultadoContenedor; overload;
function Abrir(const datos: TBytes; const pass: TBytes; out a: TAbierto): TResultadoContenedor; overload;

implementation

const
  NOMBRES_ERROR: array[TErrorContenedor] of string = ('Ninguno', 'Escritura', 'Indice', 'Cifrado',
    { 'ñ' en bytes UTF-8, para no depender de la codificacion del fuente }
    'Contrase'#$C3#$B1'aFaltante', 'Contrase'#$C3#$B1'aSobrante', 'ArchivoCorto');

function TResultadoContenedor.Ok: Boolean;
begin Result := err = ecoNinguno; end;

function TResultadoContenedor.Texto: string;
begin
  case err of
    ecoEscritura: Result := NOMBRES_ERROR[err] + '(' + escritura.Texto + ')';
    ecoIndice:    Result := NOMBRES_ERROR[err] + '(' + indice.Texto + ')';
    ecoCifrado:   Result := NOMBRES_ERROR[err] + '(' + cifrado.Texto + ')';
  else
    Result := NOMBRES_ERROR[err];
  end;
end;

function ResCont(e: TErrorContenedor): TResultadoContenedor;
begin
  Result := Default(TResultadoContenedor);
  Result.err := e;
end;
function ResEscritura(const r: TResultadoEscritura): TResultadoContenedor;
begin Result := ResCont(ecoEscritura); Result.escritura := r; end;
function ResIndice(const r: TResultado): TResultadoContenedor;
begin Result := ResCont(ecoIndice); Result.indice := r; end;
function ResCifrado(const r: TResultadoCifrado): TResultadoContenedor;
begin Result := ResCont(ecoCifrado); Result.cifrado := r; end;

function EscribirInterno(const es: TEntradas; flags: Byte; conClave: Boolean; const cc: TClaveCifrado;
                         out bytes: TBytes; out avisos: TAvisos): TResultadoContenedor;
var plano, cuerpo, ct: TBytes; rw: TResultadoEscritura; rc: TResultadoCifrado;
begin
  bytes := nil;
  rw := Escribir(es, flags, plano, avisos);
  if not rw.Ok then begin avisos := nil; Exit(ResEscritura(rw)); end;

  if (flags and FLAG_CIFRADO) = 0 then begin
    if conClave then begin avisos := nil; Exit(ResCont(ecoContrasenaSobrante)); end;
    bytes := plano;
    Exit(ResCont(ecoNinguno));
  end;
  if not conClave then begin avisos := nil; Exit(ResCont(ecoContrasenaFaltante)); end;

  { Del encabezado solo sobreviven en claro los 8 bytes que hacen falta para
    identificar el archivo y saber que pide contrasena. tam_indice y el hash
    se mudan al frente del cuerpo cifrado: el cuerpo es plano[8..]. }
  cuerpo := Copy(plano, TAM_CLARO_CABECERA, Length(plano) - TAM_CLARO_CABECERA);
  rc := Cifrar(cc.clave, cc.nonce, cuerpo, ct);
  if not rc.Ok then begin avisos := nil; Exit(ResCifrado(rc)); end;
  SetLength(bytes, TAM_CABECERA + TAM_PREFIJO_CIFRADO + Length(ct));
  Move(plano[0], bytes[0], TAM_CLARO_CABECERA);
  FillChar(bytes[TAM_CLARO_CABECERA], TAM_SECRETO_CABECERA, 0);   { tam_indice y hash en cero }
  Move(cc.sal[0], bytes[TAM_CABECERA], TAM_SAL);
  Move(cc.nonce[0], bytes[TAM_CABECERA + TAM_SAL], TAM_NONCE);
  Move(ct[0], bytes[TAM_CABECERA + TAM_PREFIJO_CIFRADO], Length(ct));   { ct nunca es vacio: hay al menos un trozo }
  Result := ResCont(ecoNinguno);
end;

function EscribirContenedor(const es: TEntradas; flags: Byte;
                            out bytes: TBytes; out avisos: TAvisos): TResultadoContenedor;
var nada: TClaveCifrado;
begin
  nada := Default(TClaveCifrado);
  Result := EscribirInterno(es, flags, False, nada, bytes, avisos);
end;

function EscribirContenedor(const es: TEntradas; flags: Byte; const cc: TClaveCifrado;
                            out bytes: TBytes; out avisos: TAvisos): TResultadoContenedor;
begin
  Result := EscribirInterno(es, flags, True, cc, bytes, avisos);
end;

function AbrirInterno(const datos: TBytes; conPass: Boolean; const pass: TBytes;
                      out a: TAbierto): TResultadoContenedor;
var
  flags: Byte; ti: LongWord; hd: THash16; ri: TResultado; rc: TResultadoCifrado;
  plano, cuerpo: TBytes; sal: TSal; nonce: TNonce; clave: TClave;
  c: TContenedor; i: SizeInt; p: QWord;
begin
  a.contenedor.flags := 0; a.contenedor.miembros := nil; a.payloads := nil;

  { La cabecera se valida ANTES de mirar el bit de cifrado: sacando flags del
    byte crudo, basura con el byte 5 impar se rechazaba por "falta contrasena"
    en vez de por "no es un contenedor". De aca solo sirven magia, version,
    flags y reservado: el tam_indice de disco, con cifrado, es cero. }
  ri := LeerCabecera(datos, flags, ti, hd);
  if not ri.Ok then Exit(ResIndice(ri));

  if (flags and FLAG_CIFRADO) <> 0 then begin
    if not conPass then Exit(ResCont(ecoContrasenaFaltante));
    if Length(datos) < TAM_CABECERA + TAM_PREFIJO_CIFRADO then Exit(ResCont(ecoArchivoCorto));
    { Con cifrado esos 20 bytes tienen que estar en cero: si no se exigiera,
      serian 160 bits del archivo que no significan nada, y un bit volteado
      ahi pasaria sin que nadie lo note. }
    for i := TAM_CLARO_CABECERA to TAM_CABECERA - 1 do
      if datos[i] <> 0 then begin
        ri.err := eIndiceAlterado; ri.valor := 0;
        Exit(ResIndice(ri));
      end;
    Move(datos[TAM_CABECERA], sal[0], TAM_SAL);
    Move(datos[TAM_CABECERA + TAM_SAL], nonce[0], TAM_NONCE);

    rc := DerivarClave(pass, sal, clave);
    if not rc.Ok then begin Limpiar(clave, SizeOf(clave)); Exit(ResCifrado(rc)); end;
    { Autenticar ANTES de mirar el indice. }
    rc := Descifrar(clave, nonce, datos, TAM_CABECERA + TAM_PREFIJO_CIFRADO, cuerpo);
    Limpiar(clave, SizeOf(clave));
    if not rc.Ok then Exit(ResCifrado(rc));
    { El cuerpo empieza con los campos que se sacaron de la cabecera. Al
      reponerlos queda el mismo plano que sin cifrar, y de ahi para abajo el
      camino es uno solo. }
    if Length(cuerpo) < TAM_SECRETO_CABECERA then Exit(ResCont(ecoArchivoCorto));
    plano := nil;
    SetLength(plano, TAM_CLARO_CABECERA + Length(cuerpo));
    Move(datos[0], plano[0], TAM_CLARO_CABECERA);
    Move(cuerpo[0], plano[TAM_CLARO_CABECERA], Length(cuerpo));
    cuerpo := nil;
  end else begin
    if conPass then Exit(ResCont(ecoContrasenaSobrante));
    plano := datos;   { arreglo dinamico: comparte, no copia; aca nadie lo escribe }
  end;

  { tam_indice se lee del plano, no del disco: con cifrado el de disco es cero. }
  ri := LeerCabecera(plano, flags, ti, hd);
  if not ri.Ok then Exit(ResIndice(ri));
  { Hash de cabecera+indice, deserializar, los seis limites y los nombres. }
  ri := LeerIndice(plano, c);
  if not ri.Ok then Exit(ResIndice(ri));

  { LeerIndice ya garantizo que los payloads suman justo lo que queda del
    archivo (SumaNoCuadra). El chequeo de abajo no deberia dispararse nunca:
    esta porque Copy NO controla rango ni con $R+ -- recorta en silencio. }
  SetLength(a.payloads, Length(c.miembros));
  p := TAM_CABECERA + QWord(ti);
  for i := 0 to High(c.miembros) do begin
    if (p > QWord(Length(plano))) or (c.miembros[i].tam_payload > QWord(Length(plano)) - p) then
      raise ERangeError.CreateFmt('Abrir: payload %d fuera del archivo', [i]);
    a.payloads[i] := Copy(plano, SizeInt(p), SizeInt(c.miembros[i].tam_payload));
    p := p + c.miembros[i].tam_payload;
  end;
  a.contenedor := c;
  Result := ResCont(ecoNinguno);
end;

function Abrir(const datos: TBytes; out a: TAbierto): TResultadoContenedor;
begin
  Result := AbrirInterno(datos, False, nil, a);
end;

function Abrir(const datos: TBytes; const pass: TBytes; out a: TAbierto): TResultadoContenedor;
begin
  Result := AbrirInterno(datos, True, pass, a);
end;

end.
