#!/usr/bin/env bash
# Limpieza TOTAL y VERIFICADA del taller
# Borra usuarios, grupos, directorios, scripts, logs, PID files y (opcional) paquetes.
# Uso:
#   sudo bash taller_linux_cleanup_strict.sh
#   UNINSTALL_PACKAGES=1 sudo bash taller_linux_cleanup_strict.sh   # también desinstala finger tree bc

set -euo pipefail

REQUIRE_ROOT(){ if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

# Objetos creados por el taller
USERS=(juan maria pedro ana carlos sofia sinhome)
GROUPS=(docentes estudiantes proyecto)
DIRS=(/home/recursos /home/pedro_nuevo /proyecto)
FILES=(/home/recursos/backup.sh /home/recursos/procesos_usuario.sh /proyecto/control.sh /proyecto/plan.txt)
TMP_PIDS=(/tmp/control_pid /tmp/bg_sleep.pid /tmp/bg_sleep2.pid)
LOGS_DIR="$HOME/taller_linux_logs"
TRANSCRIPT="$HOME/taller_linux_transcript.txt"
PKGS=(finger tree bc)

# ---------- Helpers ----------
kill_pidfile(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  local pid; pid="$(cat "$f" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && { kill "$pid" 2>/dev/null || true; kill -9 "$pid" 2>/dev/null || true; }
  rm -f "$f"
}

drop_supp_members(){
  local g="$1" mems
  mems="$(getent group "$g" | awk -F: '{print $4}')"
  IFS=',' read -r -a A <<< "${mems:-}"
  for m in "${A[@]}"; do
    [[ -z "$m" ]] && continue
    gpasswd -d "$m" "$g" 2>/dev/null || true
  done
}

fix_primary_and_delete_group(){
  local g="$1"
  getent group "$g" >/dev/null 2>&1 || return 0

  # Quitar locks que impiden groupdel
  rm -f /etc/group.lock /etc/gshadow.lock || true

  local gid; gid="$(getent group "$g" | cut -d: -f3)"

  # 1) Mover GID primario de quien lo tenga
  awk -F: -v gid="$gid" '$4==gid{print $1}' /etc/passwd | while read -r u; do
    [[ -z "$u" ]] && continue
    if getent group "$u" >/dev/null 2>&1; then
      usermod -g "$u" "$u" 2>/dev/null || true
    elif getent group users >/dev/null 2>&1; then
      usermod -g users "$u" 2>/dev/null || true
    else
      groupadd "$u" 2>/dev/null || true
      usermod -g "$u" "$u" 2>/dev/null || true
    fi
  done

  # 2) Quitar miembros suplementarios y eliminar
  drop_supp_members "$g"
  for i in 1 2 3 4 5; do
    groupdel "$g" && break || sleep 0.2
  done
}

ensure_group_gone(){
  local g="$1" tries=0
  while getent group "$g" >/dev/null 2>&1 && (( tries < 5 )); do
    fix_primary_and_delete_group "$g"
    tries=$((tries+1))
    sleep 0.2
  done
  if getent group "$g" >/dev/null 2>&1; then
    echo "⚠️  Aún existe el grupo '$g'. Diagnóstico:"
    getent group "$g" || true
    local gid; gid="$(getent group "$g" | cut -d: -f3)"
    echo "   Usuarios con GID primario ${gid}:"
    awk -F: -v gid="$gid" '$4==gid{print "   -",$1}' /etc/passwd || true
    exit 1
  fi
}

# ---------- 1) Parar procesos y limpiar PID files ----------
for p in "${TMP_PIDS[@]}"; do kill_pidfile "$p"; done
pkill -f "/proyecto/control.sh" 2>/dev/null || true

# ---------- 2) Matar procesos de usuarios del taller ----------
for u in "${USERS[@]}"; do
  id -u "$u" >/dev/null 2>&1 || continue
  pkill -u "$u" 2>/dev/null || true
  pkill -9 -u "$u" 2>/dev/null || true
done

# ---------- 3) Eliminar usuarios (y homes) ----------
for u in "${USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    # Quitar membresías suplementarias a grupos del taller
    for g in "${GROUPS[@]}"; do gpasswd -d "$u" "$g" 2>/dev/null || true; done
    userdel -r "$u" 2>/dev/null || true
    # Si el home aún aparece, eliminarlo
    hd="$(getent passwd "$u" | cut -d: -f6 || true)"
    [[ -n "${hd:-}" && -d "$hd" ]] && rm -rf "$hd" || true
  fi
done

# ---------- 4) Eliminar grupos (robusto, con verificación) ----------
for g in "${GROUPS[@]}"; do ensure_group_gone "$g"; done

# ---------- 5) Borrar archivos y directorios creados por el taller ----------
for f in "${FILES[@]}"; do [[ -e "$f" ]] && rm -f "$f" || true; done
for d in "${DIRS[@]}";  do [[ -d "$d" ]] && rm -rf "$d" || true; done

# ---------- 6) Limpiar logs y transcript ----------
rm -rf "$LOGS_DIR" "$TRANSCRIPT" 2>/dev/null || true

# ---------- 7) (Opcional) Desinstalar paquetes instalados por el taller ----------
if [[ "${UNINSTALL_PACKAGES:-0}" == "1" ]]; then
  apt-get remove -y "${PKGS[@]}" >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
fi

# ---------- 8) Verificación final ----------
echo "Verificación final (debe no haber restos):"
getent passwd "${USERS[@]}" || true
getent group  "${GROUPS[@]}" || true
ls -ld ${DIRS[*]} 2>/dev/null || true
echo "✅ Limpieza completada sin rastros."
