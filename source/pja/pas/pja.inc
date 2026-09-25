{ pja.inc — opciones comunes de toda la capa Pascal del contenedor.

  Todas las unidades lo incluyen, y despues de incluirlo cada una verifica que
  la proteccion de rango y de desborde este prendida: si alguien la saca de
  aca, la unidad no compila.

  Por que no alcanza con poner $R+: medido el 25/09/2026,
    - $R+ controla indices de ARREGLOS. Los accesos por puntero (p[i] con
      p: PByte) NO se controlan: leen fuera de rango sin ningun error. Por eso
      toda la validacion trabaja sobre arreglos, nunca sobre punteros.
    - con $Q+, `for i := 0 to n - 1` con n sin signo y n = 0 lanza
      EIntOverflow. Largos e indices van con signo (SizeInt), y los recorridos
      usan High(arreglo), que en un arreglo vacio vale -1. }

{$mode objfpc}
{$H+}
{$R+}
{$Q+}
{$modeswitch advancedrecords}
