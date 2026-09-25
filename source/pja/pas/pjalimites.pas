{ Limites del contenedor. Los numeros salen de doc/POLITICA.md, donde cada uno
  dice de donde viene. Port de pjacore/src/limites.rs. }
unit pjalimites;

{$I pja.inc}
{$ifopt R-}{$fatal pjalimites: range checks ($R+) son obligatorios}{$endif}
{$ifopt Q-}{$fatal pjalimites: overflow checks ($Q+) son obligatorios}{$endif}

interface

const
  { Tope absoluto de miembros. Acota antes de reservar el indice: un u32 crudo
    serian 4.294.967.295 entradas. }
  MAX_MIEMBROS = 1048576;

  { Bytes minimos que ocupa una entrada del indice. Sirve para descartar un
    count imposible contra el tamano real del archivo. }
  MIN_BYTES_ENTRADA = 32;

  { Cabecera .pjg minima; ningun payload puede ser mas chico. }
  MIN_PAYLOAD = 12;

  { Igual que PJG_MAX_BLOWUP_RATIO en el codec. Medido: la expansion real
    jpg/pjg va de 1,08x a 2,14x, asi que 500 es tope de ultimo recurso. }
  MAX_RATIO_EXPANSION = 500;

  { Presupuesto agregado por defecto. Un timelapse de 240 cuadros de 20 MB son
    4,8 GB legitimos, asi que heredar los 256 MB por archivo romperia el caso
    real. 0 = sin limite. }
  PRESUPUESTO_POR_DEFECTO = QWord(8) * 1024 * 1024 * 1024;

  { Limites de nombres. Son BYTES, no caracteres: medido, 255 caracteres
    acentuados son 510 bytes y el sistema de archivos los rechaza. }
  MAX_BYTES_COMPONENTE = 255;
  MAX_BYTES_RUTA       = 1024;
  MAX_PROFUNDIDAD      = 32;

implementation

end.
