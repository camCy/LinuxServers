#!/usr/bin/env bash
# Limpieza TOTAL del taller (robusto con eliminación de miembros de grupos y GID primario)
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

# ---- helpers ----
drop_supp_members() {
  local grp="$1"
  local members
  members="$(getent group "$grp" | awk -F: '{print $4}')"
  IFS=',' read -r -a arr <<< "${members:-}"
  for u in "${arr[@]}"; do
    [[ -z "$u" ]] && continue
    gpasswd -d "$u" "$grp" 2>/dev/null || true
  done
}

fix_primary_gid_and_groupdel() {
  local grp="$1"
  local gid
  gid="$(getent group "$grp" | cut -d: -f3)"
  # Cambia grupo primario para quien lo tenga = gid del grupo
  if [[ -n "${gid:-}" ]]; then
    while IFS=: read -r u _ _ ugid _; do
      if [[ "$ugid" == "$gid" ]]; then
        # Elige nuevo grupo primario: el grupo homónimo del usuario si existe; si no, 'users'
        if getent group "$u" >/dev/null 2>&1; then
          usermod -g "$u" "$u" 2>/dev/null || true
        elif getent group users >/dev/null 2>&1; then
          usermod -g users "$u" 2>/dev/null || true
        else
          # última opción: crea grupo homónimo
          groupadd "$u" 2>/dev/null || true
          usermod -g "$u" "$u" 2>/dev/null || true
        end
      fi
    done < <(getent passwd)
  fi
  # Quita miembros suplementarios y elimina
  drop_supp_members "$grp"
  groupdel "$grp" 2>/dev/null || true
}

echo "==> Parando procesos y limpiando PIDs temporales..."
for p in "${TMP_PIDS[@]}"; do
  [[ -f "$p" ]] || continue
  pid="$(cat "$p" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && { kill "$pid" 2>/dev/null || true; kill -9 "$pid" 2>/dev/null || true; }
  rm -f "$p"
done
pkill -f "/proyecto/control.sh" 2>/dev/null || true

echo "==> Matando procesos de usuarios del taller (si hay)..."
for u in "${USERS[@]}"; do
  id -u "$u" >/dev/null 2>&1 || continue
  pkill -u "$u" 2>/dev/null || true
  pkill -9 -u "$u" 2>/dev/null || true
done

echo "==> Eliminando usuarios del taller..."
for u in "${USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    # Quita membresías suplementarias a los grupos del taller
    for g in "${GROUPS[@]}"; do
      gpasswd -d "$u" "$g" 2>/dev/null || true
    done
    # Elimina usuario (y home si existe)
    userdel -r "$u" 2>/dev/null || true
    # Borra home residual si quedó
    home_dir="$(getent passwd "$u" | cut -d: -f6 || true)"
    [[ -n "${home_dir:-}" && -d "$home_dir" ]] && rm -rf "$home_dir" || true
    echo "   · Usuario '$u' eliminado."
  else
    echo "   · Usuario '$u' no existe (ok)."
  fi
done

echo "==> Eliminando grupos del taller..."
for g in "${GROUPS[@]}"; do
  if getent group "$g" >/dev/null 2>&1; then
    fix_primary_gid_and_groupdel "$g"
    if getent group "$g" >/dev/null 2>&1; then
      echo "   ! Advertencia: no se pudo eliminar el grupo '$g'. Revisa /etc/group."
    else
      echo "   · Grupo '$g' eliminado."
    fi
  else
    echo "   · Grupo '$g' no existe (ok)."
  fi
done

echo "==> Borrando archivos del taller..."
for f in "${FILES[@]}"; do
  [[ -e "$f" ]] && rm -f "$f" || true
done

echo "==> Borrando directorios del taller..."
for d in "${DIRS[@]}"; do
  case "$d" in
    /home/recursos|/home/pedro_nuevo|/proyecto)
      [[ -d "$d" ]] && rm -rf "$d" || true
      echo "   · $d eliminado (si existía)."
      ;;
    *) echo "   ! Omite '$d' por seguridad." ;;
  esac
done

echo "==> Limpiando logs/transcript..."
rm -rf "$LOGS_DIR" 2>/dev/null || true
rm -f  "$TRANSCRIPT" 2>/dev/null || true

if [[ "${UNINSTALL_PACKAGES:-0}" == "1" ]]; then
  echo "==> Desinstalando paquetes del taller: ${PKGS[*]} ..."
  set +e
  apt-get remove -y "${PKGS[@]}" 2>/dev/null
  apt-get autoremove -y 2>/dev/null
  set -e
else
  echo "==> Paquetes se mantienen instalados (UNINSTALL_PACKAGES=1 para quitarlos)."
fi

echo "✅ Limpieza completa."
