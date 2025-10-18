#!/usr/bin/env bash
# Limpieza total del taller (usuarios, grupos, carpetas, scripts, procesos)
set -euo pipefail

REQUIRE_ROOT() { if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

USERS=("juan" "maria" "pedro" "ana" "carlos" "sofia" "sinhome")
GROUPS=("docentes" "estudiantes" "proyecto")
DIRS=("/home/recursos" "/home/pedro_nuevo" "/proyecto")

kill_user_procs() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    # mata procesos de ese usuario (ignora errores si no tiene)
    pkill -u "$u" -9 2>/dev/null || true
  fi
}

del_user() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    # forzar eliminación de la cuenta y su home si existe
    userdel -r "$u" 2>/dev/null || true
    # por si quedó el home residual
    home_dir="$(getent passwd "$u" | cut -d: -f6 || true)"
    [ -n "${home_dir:-}" ] && [ -d "$home_dir" ] && rm -rf "$home_dir" || true
    echo "Usuario '$u' eliminado (y su home si existía)."
  else
    echo "Usuario '$u' no existe."
  fi
}

del_group() {
  local g="$1"
  if getent group "$g" >/dev/null; then
    groupdel "$g" 2>/dev/null || true
    echo "Grupo '$g' eliminado."
  else
    echo "Grupo '$g' no existe."
  fi
}

echo "==> Finalizando scripts/daemons del taller si quedaron..."
# Si quedó en background el control.sh o sleeps
[ -f /tmp/control_pid ] && { kill "$(cat /tmp/control_pid)" 2>/dev/null || true; rm -f /tmp/control_pid; }
[ -f /tmp/bg_sleep.pid ] && { kill "$(cat /tmp/bg_sleep.pid)" 2>/dev/null || true; rm -f /tmp/bg_sleep.pid; }
[ -f /tmp/bg_sleep2.pid ] && { kill -9 "$(cat /tmp/bg_sleep2.pid)" 2>/dev/null || true; rm -f /tmp/bg_sleep2.pid; }

echo "==> Matando procesos de usuarios del taller (si los hay)..."
for u in "${USERS[@]}"; do kill_user_procs "$u"; done

echo "==> Eliminando usuarios del taller..."
for u in "${USERS[@]}"; do del_user "$u"; done

echo "==> Eliminando grupos del taller..."
for g in "${GROUPS[@]}"; do del_group "$g"; done

echo "==> Borrando directorios del taller..."
for d in "${DIRS[@]}"; do [ -d "$d" ] && rm -rf "$d"; done

echo "==> Limpiando logs opcionales..."
rm -rf "$HOME/taller_linux_logs" 2>/dev/null || true
rm -f  "$HOME/taller_linux_transcript.txt" 2>/dev/null || true

echo "✅ Limpieza completa."
