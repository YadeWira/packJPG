{ Limites del formato. Los numeros salen de doc/POLITICA.md, donde cada uno
  dice de donde viene. }
unit pjalimites;

{$I pja.inc}
{$ifopt R-}{$fatal pjalimites: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjalimites: overflow checks ($Q+) son obligatorios}{$endif}

interface

const
  { Cabecera .pjg minima; ningun payload puede ser mas chico. }
  MIN_PAYLOAD = 12;

  { Igual que PJG_MAX_BLOWUP_RATIO en el codec. Medido: la expansion real
    jpg/pjg va de 1,08x a 2,14x, asi que 500 es tope de ultimo recurso: lo que
    importa es que el tamano declarado permite rechazar ANTES de decodificar. }
  MAX_RATIO_EXPANSION = 500;

implementation

end.
