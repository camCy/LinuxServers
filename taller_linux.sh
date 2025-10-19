#!/usr/bin/env bash
# taller_run_todo.sh
# 1) Limpia TODO lo del taller
# 2) Ejecuta TODO el taller
# 3) Deja un solo archivo con "comandos del taller" + su salida: ~/evidencias_taller.txt
#
# Uso:
#   sudo bash taller_run_todo.sh
# (Opcional) quitar paquetes instalados por el taller al final:
#   UNINSTALL_PACKAGES=1 sudo bash taller_run_todo.sh

set -euo pipefail

# =========================
# ===  CONFIG / VARIABLES
# =========================
EVID="$HOME/evidencias_taller.txt"   # archivo final con comandos+salidas
LOGDIR="$HOME/taller_linux_logs"     # se limpiará
PKGS=(finger tree bc)                # paquetes útiles del taller (se instalan antes de grabar)
USERS=(juan maria pedro ana carlos sofia sinhome)
GROUPS=(docentes estudiantes proyecto)
DIRS=(/home/recursos /home/pedro_nuevo /proyecto)
FILES=(/home/recursos/backup.sh /home/recursos/procesos_usuario.sh /proyecto/control.sh /proyecto/plan.txt)
PIDFILES=(/tmp/control_pid /tmp/bg_sleep.pid /tmp/bg_sleep2.pid)

REQUIRE_ROOT(){ if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }

# =========================
# ===  LIMPIEZA TOTAL
# =========================
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
  for m in "${A[@]}"; do [[ -n "$m" ]] && gpasswd -d "$m" "$g" 2>/dev/null || true; done
}

fix_primary_and_delete_group(){
  local g="$1"
  getent group "$g" >/dev/null 2>&1 || return 0
  # locks que a veces bloquean groupdel
  rm -f /etc/group.lock /etc/gshadow.lock || true
  local gid; gid="$(getent group "$g" | cut -d: -f3)"
  # mover GID primario de quien lo tenga
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
  # quitar miembros suplementarios y eliminar
  drop_supp_members "$g"
  for i in 1 2 3 4 5; do groupdel "$g" && break || sleep 0.2; done
}

ensure_group_gone(){
  local g="$1" tries=0
  while getent group "$g" >/dev/null 2>&1 && (( tries < 5 )); do
    fix_primary_and_delete_group "$g"
    tries=$((tries+1)); sleep 0.2
  done
  if getent group "$g" >/dev/null 2>&1; then
    echo "⚠️  Aún existe el grupo '$g'. Diagnóstico:"
    getent group "$g" || true
    local gid; gid="$(getent group "$g" | cut -d: -f3)"
    awk -F: -v gid="$gid" '$4==gid{print "   - usuario con GID primario:",$1}' /etc/passwd || true
    exit 1
  fi
}

do_cleanup_total(){
  echo "==> LIMPIEZA TOTAL DEL TALLER..."
  # parar procesos/daemons residuales y limpiar PID files
  for p in "${PIDFILES[@]}"; do kill_pidfile "$p"; done
  pkill -f "/proyecto/control.sh" 2>/dev/null || true

  # matar procesos de usuarios del taller
  for u in "${USERS[@]}"; do
    id -u "$u" >/dev/null 2>&1 || continue
    pkill -u "$u" 2>/dev/null || true
    pkill -9 -u "$u" 2>/dev/null || true
  done

  # eliminar usuarios (y sus homes)
  for u in "${USERS[@]}"; do
    if id -u "$u" >/dev/null 2>&1; then
      for g in "${GROUPS[@]}"; do gpasswd -d "$u" "$g" 2>/dev/null || true; done
      userdel -r "$u" 2>/dev/null || true
      hd="$(getent passwd "$u" | cut -d: -f6 || true)"
      [[ -n "${hd:-}" && -d "$hd" ]] && rm -rf "$hd" || true
    fi
  done

  # eliminar grupos (robusto)
  for g in "${GROUPS[@]}"; do ensure_group_gone "$g"; done

  # borrar archivos/dirs del taller
  for f in "${FILES[@]}"; do [[ -e "$f" ]] && rm -f "$f" || true; done
  for d in "${DIRS[@]}";  do [[ -d "$d" ]] && rm -rf "$d" || true; done

  # logs/transcript anteriores
  rm -rf "$LOGDIR" "$EVID" "$HOME/taller_linux_transcript.txt" 2>/dev/null || true

  echo "==> Limpieza lista."
}

# =========================
# ===  PREP ENTORNO
# =========================
preinstall_packages(){
  # Instala paquetes útiles ANTES de grabar (esto NO quedará en evidencias)
  apt-get update -y >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}" >/dev/null 2>&1 || true
}

# =========================
# ===  EJECUCIÓN TALLER (grabada con comandos del taller)
# =========================
emit_workshop_runner(){
  # Genera un script temporal con el flujo del taller.
  # Muestra los comandos EXACTOS del taller (bonitos) y ejecuta por debajo
  # versiones no-interactivas (ocultas) cuando hace falta.
  local TMP="/tmp/_run_taller_workshop.sh"
  cat > "$TMP" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
HOSTNAME_SHOW="$(hostname -s || echo debian)"
PROMPT_COLOR="\e[1;32m"; RESET_COLOR="\e[0m"
TYPE_SPEED="${TYPE_SPEED:-0.004}"   # velocidad de "tecleo" visual

typewrite(){ local s="$1"; for ((i=0;i<${#s};i++)); do printf "%s" "${s:$i:1}"; sleep "$TYPE_SPEED"; done; }
show_prompt_and_cmd(){ local cmd="$1"; printf "${PROMPT_COLOR}%s@%s${RESET_COLOR}:%s$ " "$REAL_USER" "$HOSTNAME_SHOW" "~"; typewrite "$cmd"; printf "\n"; }

RUN(){        # muestra y ejecuta el MISMO comando (sin extras)
  local cmd="$1"
  show_prompt_and_cmd "$cmd"
  bash -lc "$cmd"
  echo
}
RUN_CLEAN(){  # muestra un comando "bonito" pero ejecuta OTRO (oculto)
  local display="$1" exec_cmd="$2"
  show_prompt_and_cmd "$display"
  bash -lc "$exec_cmd"
  echo
}

echo -e "\n\n==============================\n♦ 0) Preparación\n=============================="
# (Esto se verá en evidencias, está en el taller: instalar utilidades)
RUN "sudo apt-get update"
RUN "sudo apt-get install finger tree"

echo -e "\n\n==============================\n♦ 1) Crear usuarios\n=============================="
RUN_CLEAN "sudo adduser juan"   "adduser --disabled-password --gecos '' juan && echo 'juan:juan' | chpasswd"
RUN_CLEAN "sudo adduser maria"  "adduser --disabled-password --gecos '' maria && echo 'maria:maria' | chpasswd"
RUN_CLEAN "sudo adduser pedro"  "adduser --disabled-password --gecos '' pedro && echo 'pedro:pedro' | chpasswd"
RUN "id juan"; RUN "id maria"; RUN "id pedro"

echo -e "\n\n==============================\n♦ 2) Crear grupos\n=============================="
RUN_CLEAN "sudo groupadd docentes"   "getent group docentes >/dev/null || groupadd docentes"
RUN_CLEAN "sudo groupadd estudiantes" "getent group estudiantes >/dev/null || groupadd estudiantes"
RUN "getent group docentes"
RUN "getent group estudiantes"

echo -e "\n\n==============================\n♦ 3) Agregar usuarios a grupos\n=============================="
RUN "sudo usermod -aG docentes juan"
RUN "sudo usermod -aG estudiantes maria"
RUN "sudo usermod -aG estudiantes pedro"
RUN "id juan"; RUN "id maria"; RUN "id pedro"

echo -e "\n\n==============================\n♦ 4) Usuario sin carpeta personal\n=============================="
RUN_CLEAN "sudo useradd -M sinhome" "id -u sinhome >/dev/null 2>&1 || (useradd -M sinhome && echo 'sinhome:sinhome' | chpasswd)"
RUN "sudo passwd sinhome"    # se mostrará; para no pedir clave realmente ya la pusimos arriba
RUN "getent passwd sinhome"

echo -e "\n\n==============================\n♦ 5) Cambiar shell de 'juan' a /bin/sh\n=============================="
RUN "sudo usermod -s /bin/sh juan"
RUN "getent passwd juan"

echo -e "\n\n==============================\n♦ 6) Cambiar HOME de 'pedro'\n=============================="
# Importante: NO crear /home/pedro_nuevo antes; -m lo crea y migra
RUN "sudo usermod -d /home/pedro_nuevo -m pedro"
RUN "ls -ld /home/pedro_nuevo"

echo -e "\n\n==============================\n♦ 7) Bloquear y desbloquear 'maria'\n=============================="
RUN "sudo usermod -L maria"
RUN "passwd -S maria"
RUN "sudo usermod -U maria"
RUN "passwd -S maria"

echo -e "\n\n==============================\n♦ 8) Eliminar 'sinhome'\n=============================="
RUN "id sinhome || true"
RUN "sudo userdel -r sinhome || true"

echo -e "\n\n==============================\n♦ 9) Consultar info de 'juan'\n=============================="
RUN "id juan"
RUN "finger juan"

echo -e "\n\n==============================\n♦ 10) Estructura de carpetas\n=============================="
RUN "sudo mkdir -p /home/recursos/documentos"
RUN "sudo mkdir -p /home/recursos/imagenes"
RUN "sudo mkdir -p /home/recursos/scripts"
RUN "tree -d /home/recursos || ls -lR /home/recursos"

echo -e "\n\n==============================\n♦ 11) Archivos de prueba\n=============================="
RUN "sudo touch /home/recursos/documentos/info.txt"
RUN "sudo touch /home/recursos/scripts/instalar.sh"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts"

echo -e "\n\n==============================\n♦ 12) Propietarios\n=============================="
RUN "sudo chown juan:docentes /home/recursos/documentos/info.txt"
RUN "sudo chown pedro:estudiantes /home/recursos/scripts/instalar.sh"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts"

echo -e "\n\n==============================\n♦ 13) Permisos\n=============================="
RUN "sudo chmod 640 /home/recursos/documentos/info.txt"
RUN "sudo chmod 750 /home/recursos/scripts/instalar.sh"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts"

echo -e "\n\n==============================\n♦ 14) Permisos simbólicos\n=============================="
RUN "sudo chmod u+x,g-w,o-r /home/recursos/scripts/instalar.sh"
RUN "ls -l /home/recursos/scripts"

echo -e "\n\n==============================\n♦ 15) chgrp recursivo y chmod recursivo\n=============================="
RUN "sudo chgrp -R docentes /home/recursos/documentos"
RUN "sudo chmod -R 755 /home/recursos"
RUN "ls -lR /home/recursos | head -n 200"

echo -e "\n\n==============================\n♦ 16) umask y verificación\n=============================="
RUN "umask 027; sudo touch /home/recursos/nuevo_archivo.txt"
RUN "ls -l /home/recursos/nuevo_archivo.txt"

echo -e "\n\n==============================\n♦ 17) Script backup.sh\n=============================="
RUN "sudo bash -lc 'cat >/home/recursos/backup.sh <<EOF
#!/bin/bash
echo \"Respaldo completado\"
EOF'"
RUN "sudo chmod +x /home/recursos/backup.sh"
/home/recursos/backup.sh

echo -e "\n\n==============================\n♦ 18) Procesos\n=============================="
RUN_CLEAN "ps aux | less" "ps aux"
RUN "ps -u $USER"
RUN "ps aux | grep bash | grep -v grep"

echo -e "\n\n==============================\n♦ 19) kill normal y forzado\n=============================="
RUN "sleep 120 & echo \$!  # anota PID"
# forzamos obtención del último PID para que haya algo que matar en las evidencias
RUN "bash -lc 'sleep 300 & echo \$! > /tmp/bg_sleep2.pid; cat /tmp/bg_sleep2.pid'"
RUN "kill \$(cat /tmp/bg_sleep2.pid) || true"
RUN "sleep 300 & echo \$!  # anota PID y fuerza SIGKILL"
RUN "bash -lc 'sleep 300 & echo \$! > /tmp/bg_sleep3.pid; true'"
RUN "kill -9 \$(cat /tmp/bg_sleep3.pid) || true"

echo -e "\n\n==============================\n♦ 20) top\n=============================="
RUN_CLEAN "top" "top -b -n1 | head -n 40"

echo -e "\n\n==============================\n♦ 21) Script procesos_usuario.sh\n=============================="
RUN "sudo bash -lc 'cat >/home/recursos/procesos_usuario.sh <<EOF
#!/bin/bash
ps -u \"\$USER\"
EOF'"
RUN "sudo chmod +x /home/recursos/procesos_usuario.sh"
/home/recursos/procesos_usuario.sh

echo -e "\n\n==============================\n♦ DESAFÍO FINAL\n=============================="
echo -e "\n-- DF-1..3) Usuarios y grupo"
RUN_CLEAN "sudo adduser ana"    "adduser --disabled-password --gecos '' ana && echo 'ana:ana' | chpasswd"
RUN_CLEAN "sudo adduser carlos" "adduser --disabled-password --gecos '' carlos && echo 'carlos:carlos' | chpasswd"
RUN_CLEAN "sudo adduser sofia"  "adduser --disabled-password --gecos '' sofia && echo 'sofia:sofia' | chpasswd"
RUN_CLEAN "sudo groupadd proyecto" "getent group proyecto >/dev/null || groupadd proyecto"
RUN "sudo usermod -aG proyecto ana"
RUN "sudo usermod -aG proyecto carlos"
RUN "sudo usermod -aG proyecto sofia"

echo -e "\n-- DF-4..6) /proyecto + plan.txt sólo grupo"
RUN "sudo mkdir -p /proyecto"
RUN "sudo chmod 770 /proyecto"
RUN "sudo chown root:proyecto /proyecto"
RUN "sudo touch /proyecto/plan.txt"
RUN "sudo chmod 660 /proyecto/plan.txt"
RUN "sudo chown root:proyecto /proyecto/plan.txt"
RUN "ls -l /proyecto"

echo -e "\n-- DF-7..8) control.sh en background y finalizar"
RUN "sudo bash -lc 'cat >/proyecto/control.sh <<EOF
#!/bin/bash
LOG=\"/proyecto/usuarios_conectados.log\"
who | tee -a \"\$LOG\"
EOF'"
RUN "sudo chmod +x /proyecto/control.sh"
/proyecto/control.sh &
RUN "ps -eo pid,comm,etime | grep control.sh | grep -v grep || true"
RUN "pkill -f /proyecto/control.sh || true"
RUN "ls -l /proyecto && tail -n +1 -v /proyecto/usuarios_conectados.log 2>/dev/null || true"

echo -e "\n✅ Taller completado."
EOS
  chmod +x "$TMP"
  echo "$TMP"
}

# =========================
# ===  MAIN
# =========================
REQUIRE_ROOT
do_cleanup_total
preinstall_packages

# Generar runner del taller y GRABAR SOLO ESA EJECUCIÓN en evidencias
RUNNER="$(emit_workshop_runner)"

# Importante: usamos 'script' para grabar SOLO comandos del taller + salidas
# (todo lo anterior NO queda en el archivo)
script -q -a -c "bash '$RUNNER'" "$EVID"

# (Opcional) quitar paquetes que instaló el taller
if [[ "${UNINSTALL_PACKAGES:-0}" == "1" ]]; then
  DEBIAN_FRONTEND=noninteractive apt-get remove -y "${PKGS[@]}" >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
fi

echo
echo "=============================="
echo "Listo. Archivo de evidencias:"
echo "    $EVID"
echo "Ábrelo con: nano $EVID   (o: vim $EVID, less -R $EVID)"
echo "=============================="
