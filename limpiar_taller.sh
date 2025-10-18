#!/usr/bin/env bash
set -euo pipefail

REQUIRE_ROOT() {
  if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta con sudo o como root."
    exit 1
  fi
}
REQUIRE_ROOT

safe_del_user() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    userdel -r "$u" || true
    echo "Usuario '$u' eliminado."
  else
    echo "Usuario '$u' no existe."
  fi
}

safe_del_group() {
  local g="$1"
  if getent group "$g" >/dev/null; then
    groupdel "$g" || true
    echo "Grupo '$g' eliminado."
  else
    echo "Grupo '$g' no existe."
  fi
}

echo "Eliminando usuarios de práctica..."
for U in juan maria pedro ana carlos sofia; do
  safe_del_user "$U"
done

echo "Eliminando grupos de práctica..."
for G in docentes estudiantes proyecto; do
  safe_del_group "$G"
done

echo "Eliminando directorios creados..."
rm -rf /home/recursos
rm -rf /proyecto

echo "Listo. Entorno limpiado."
