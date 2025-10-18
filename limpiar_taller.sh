#!/usr/bin/env bash
# Limpieza TOTAL del taller "taller_linux_guiado_clean.sh"
# Borra: usuarios, grupos, dirs, archivos, logs, PIDs, y (opcional) paquetes instalados.
# Uso:
#   sudo bash taller_linux_cleanup_strict.sh
#   UNINSTALL_PACKAGES=1 sudo bash taller_linux_cleanup_strict.sh   # para desinstalar finger tree bc

set -euo pipefail

REQUIRE_ROOT() { if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

# === Objetos creados por el taller ===
USERS=(juan maria pedro ana carlos sofia sinhome)
GROUPS=(docentes estudiantes proyecto)
DIRS=(/home/recursos /home/pedro_nuevo /proyecto)
FILES=(
  /home/recursos/backup.sh
  /home/recursos/procesos_usuario.sh
  /proyecto/control.sh
  /proyecto/plan.txt
)
TMP_PIDS=(/tmp/control_pid /tmp/bg_sleep.pid /tmp/bg_sleep2.pid)
LOGS_DIR="$HOME/taller_linux_logs"
TRANSCRIPT="$HOME/taller_linux_transcript.txt"

PKGS=(finger tree bc)   # paquetes que instaló el taller

echo "==> Iniciando limpieza total del taller..."

# 1) Detener procesos y limpiar PIDs temporales
echo "-- Deteniendo procesos residuales..."
for p in "${TMP_PIDS[@]}"; do
  if [[ -f "$p" ]]; then
    pid="$(cat "$p" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]]; then
      kill "$pid" 2>/dev/null || true
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$p"
  fi
done

# Además, intenta matar procesos que el taller pudo dejar:
# - sleeps iniciados por root (no siempre detectables por nombre)
# - el control.sh si quedó en background
pkill -f "/proyecto/control.sh" 2>/dev/null || true

# 2) Matar procesos de los usuarios del taller (si existen)
echo "-- Matando procesos de usuarios del taller (si los hay)..."
for u in "${USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    pkill -u "$u" 2>/dev/null || true
    pkill -9 -u "$u" 2>/dev/null || true
  fi
done

# 3) Eliminar usuarios (con sus homes si quedaran)
echo "-- Eliminando usuarios del taller..."
for u in "${USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    # intentar removal completo
    userdel -r "$u" 2>/dev/null || true
    # borrar home residual si aún existe
    home_dir="$(getent passwd "$u" | cut -d: -f6 || true)"
    if [[ -n "${home_dir:-}" && -d "$home_dir" ]]; then
      rm -rf "$home_dir" || true
    fi
    echo "   · Usuario '$u' eliminado."
  else
    echo "   · Usuario '$u' no existe (ok)."
  fi
done

# 4) Eliminar grupos
echo "-- Eliminando grupos del taller..."
for g in "${GROUPS[@]}"; do
  if getent group "$g" >/dev/null; then
    groupdel "$g" 2>/dev/null || true
    echo "   · Grupo '$g' eliminado."
  else
    echo "   · Grupo '$g' no existe (ok)."
  fi
done

# 5) Borrar archivos individuales (si las carpetas siguen, se borran luego también)
echo "-- Borrando archivos creados por el taller..."
for f in "${FILES[@]}"; do
  [[ -e "$f" ]] && rm -f "$f" || true
done

# 6) Borrar directorios completos del taller
echo "-- Borrando directorios del taller..."
for d in "${DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    # pequeño guard para evitar locuras
    case "$d" in
      /home/recursos|/home/pedro_nuevo|/proyecto)
        rm -rf "$d" || true
        echo "   · Directorio '$d' eliminado."
        ;;
      *)
        echo "   ! Directorio '$d' no reconocido, omitiendo por seguridad."
        ;;
    esac
  else
    echo "   · Directorio '$d' no existe (ok)."
  fi
done

# 7) Limpiar logs y transcript
echo "-- Limpiando logs y transcript..."
rm -rf "$LOGS_DIR" 2>/dev/null || true
rm -f  "$TRANSCRIPT" 2>/dev/null || true

# 8) (Opcional) Desinstalar paquetes que instaló el taller
if [[ "${UNINSTALL_PACKAGES:-0}" == "1" ]]; then
  echo "-- Desinstalando paquetes del taller: ${PKGS[*]} ..."
  set +e
  apt-get remove -y "${PKGS[@]}" 2>/dev/null
  apt-get autoremove -y 2>/dev/null
  set -e
else
  echo "-- Paquetes 'finger', 'tree' y 'bc' se mantienen instalados (UNINSTALL_PACKAGES=1 para quitarlos)."
fi

echo "✅ Limpieza completa: sistema sin rastros del taller."
