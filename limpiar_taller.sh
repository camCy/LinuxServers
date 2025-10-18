#!/usr/bin/env bash
# Limpieza TOTAL del taller (usuarios, grupos, directorios, scripts, logs, PIDs)
set -euo pipefail

REQUIRE_ROOT() { if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

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
PKGS=(finger tree bc)

echo "==> Iniciando limpieza completa del taller..."

# --- 1. Matar procesos residuales ---
for p in "${TMP_PIDS[@]}"; do
  [[ -f "$p" ]] || continue
  pid=$(cat "$p" 2>/dev/null || true)
  [[ -n "${pid:-}" ]] && { kill "$pid" 2>/dev/null || true; kill -9 "$pid" 2>/dev/null || true; }
  rm -f "$p"
done
pkill -f "/proyecto/control.sh" 2>/dev/null || true

# --- 2. Matar procesos de usuarios del taller ---
for u in "${USERS[@]}"; do
  id -u "$u" >/dev/null 2>&1 || continue
  pkill -u "$u" 2>/dev/null || true
  pkill -9 -u "$u" 2>/dev/null || true
done

# --- 3. Quitar usuarios (y homes) ---
for u in "${USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    echo "Eliminando usuario $u..."
    # Quitar membresías suplementarias a los grupos del taller
    for g in "${GROUPS[@]}"; do gpasswd -d "$u" "$g" 2>/dev/null || true; done
    # Borrar usuario y su home
    userdel -r "$u" 2>/dev/null || true
    home_dir=$(getent passwd "$u" | cut -d: -f6 || true)
    [[ -n "${home_dir:-}" && -d "$home_dir" ]] && rm -rf "$home_dir" || true
  fi
done

# --- 4. Eliminar grupos ---
for g in "${GROUPS[@]}"; do
  if getent group "$g" >/dev/null; then
    echo "Eliminando grupo $g..."
    # Detectar GID y usuarios con grupo primario igual
    gid=$(getent group "$g" | cut -d: -f3)
    awk -F: -v gid="$gid" '$4==gid {print $1}' /etc/passwd | while read -r u; do
      [[ -z "$u" ]] && continue
      # cambiar grupo primario a uno homónimo o a "users"
      if getent group "$u" >/dev/null 2>&1; then
        usermod -g "$u" "$u" 2>/dev/null || true
      elif getent group users >/dev/null 2>&1; then
        usermod -g users "$u" 2>/dev/null || true
      else
        groupadd "$u" 2>/dev/null || true
        usermod -g "$u" "$u" 2>/dev/null || true
      fi
    done
    # Quitar miembros suplementarios
    members=$(getent group "$g" | awk -F: '{print $4}')
    IFS=',' read -r -a arr <<< "${members:-}"
    for m in "${arr[@]}"; do
      [[ -z "$m" ]] && continue
      gpasswd -d "$m" "$g" 2>/dev/null || true
    done
    groupdel "$g" 2>/dev/null || true
    getent group "$g" >/dev/null && echo "⚠️  No se pudo borrar grupo $g, revísalo manualmente."
  fi
done

# --- 5. Borrar archivos y directorios ---
for f in "${FILES[@]}"; do [[ -e "$f" ]] && rm -f "$f" || true; done
for d in "${DIRS[@]}"; do [[ -d "$d" ]] && rm -rf "$d" || true; done

# --- 6. Logs y transcript ---
rm -rf "$LOGS_DIR" "$TRANSCRIPT" 2>/dev/null || true

# --- 7. (Opcional) Desinstalar paquetes ---
if [[ "${UNINSTALL_PACKAGES:-0}" == "1" ]]; then
  echo "Desinstalando paquetes del taller..."
  apt-get remove -y "${PKGS[@]}" >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
else
  echo "Paquetes $PKGS se mantienen instalados (usa UNINSTALL_PACKAGES=1 para quitarlos)."
fi

echo "✅ Limpieza completada sin rastros."
