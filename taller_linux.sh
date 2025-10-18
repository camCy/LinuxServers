#!/usr/bin/env bash
# Taller de comandos Linux - Modo "yo tecleo" (versión limpia)
# Ejecutar: sudo ./taller_linux_guiado_clean.sh
set -euo pipefail

# ========= Config =========
LOGDIR="$HOME/taller_linux_logs"
mkdir -p "$LOGDIR"

REQUIRE_ROOT() { if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

REAL_USER="${SUDO_USER:-$USER}"
HOSTNAME_SHOW="$(hostname -s || echo debian)"
PROMPT_COLOR="\e[1;32m"
RESET_COLOR="\e[0m"
TYPE_SPEED="${TYPE_SPEED:-0.01}"  # 0.005-0.02

# === Helpers de GUIA ===
typewrite() {
  local str="$1"
  local i
  for ((i=0; i<${#str}; i++)); do
    printf "%s" "${str:$i:1}"
    sleep "$TYPE_SPEED"
  done
}

show_prompt_and_cmd() {
  local cmd="$1"
  printf "${PROMPT_COLOR}%s@%s${RESET_COLOR}:%s$ " "$REAL_USER" "$HOSTNAME_SHOW" "~"
  typewrite "$cmd"
  printf "\n"
}

RUN() {
  # Muestra y ejecuta el mismo comando
  local cmd="$1"
  local log="${2:-}"
  show_prompt_and_cmd "$cmd"
  read -rp "➡️  (Enter) para ejecutar…"
  set +e
  if [[ -n "$log" ]]; then
    bash -lc "$cmd" 2>&1 | tee -a "$LOGDIR/$log"
  else
    bash -lc "$cmd"
  fi
  local rc=$?
  set -e
  echo
  return $rc
}

# Muestra un comando "bonito" pero ejecuta otro real (oculto)
RUN_CLEAN() {
  local display_cmd="$1"   # lo que se muestra
  local exec_cmd="$2"      # lo que se ejecuta
  local log="${3:-}"       # log opcional
  show_prompt_and_cmd "$display_cmd"
  read -rp "➡️  (Enter) para ejecutar…"
  set +e
  if [[ -n "$log" ]]; then
    bash -lc "$exec_cmd" 2>&1 | tee -a "$LOGDIR/$log"
  else
    bash -lc "$exec_cmd"
  fi
  local rc=$?
  set -e
  echo
  return $rc
}

STEP() { echo -e "\n\n==============================\n🧪 $1\n=============================="; }
NOTE() { echo -e "💡 $1"; }

# ================== Inicio ==================
STEP "0) Preparación: actualizar e instalar utilidades"
RUN "apt-get update -y" "apt.log"
RUN "DEBIAN_FRONTEND=noninteractive apt-get install -y finger tree" "apt.log"

# ===== ADMINISTRACIÓN DE USUARIOS Y GRUPOS =====
STEP "1) Crear usuarios: juan, maria, pedro"
RUN_CLEAN "adduser juan   # (password: juan)" \
          "adduser --disabled-password --gecos '' juan && echo 'juan:juan' | chpasswd" "1_usuarios.txt"
RUN_CLEAN "adduser maria  # (password: maria)" \
          "adduser --disabled-password --gecos '' maria && echo 'maria:maria' | chpasswd" "1_usuarios.txt"
RUN_CLEAN "adduser pedro  # (password: pedro)" \
          "adduser --disabled-password --gecos '' pedro && echo 'pedro:pedro' | chpasswd" "1_usuarios.txt"
RUN "id juan && id maria && id pedro" "1_verificacion.txt"

STEP "2) Crear grupos docentes y estudiantes"
RUN "groupadd docentes" "2_grupos.txt"
RUN "groupadd estudiantes" "2_grupos.txt"
RUN "getent group docentes && getent group estudiantes" "2_grupos.txt"

STEP "3) Agregar usuarios a grupos"
RUN "usermod -aG docentes juan" "3_grupos_user.txt"
RUN "usermod -aG estudiantes maria" "3_grupos_user.txt"
RUN "usermod -aG estudiantes pedro" "3_grupos_user.txt"
RUN "id juan && id maria && id pedro" "3_verificacion.txt"

STEP "4) Usuario sin carpeta personal"
RUN_CLEAN "useradd -M sinhome  # (password: sinhome)" \
          "useradd -M sinhome && echo 'sinhome:sinhome' | chpasswd" "4_sinhome.txt"
RUN "getent passwd sinhome" "4_sinhome.txt"

STEP "5) Cambiar shell de 'juan' a /bin/sh"
RUN "usermod -s /bin/sh juan" "5_shell.txt"
RUN "getent passwd juan" "5_shell.txt"

STEP "6) Cambiar HOME de 'pedro' a /home/pedro_nuevo"
RUN "mkdir -p /home/pedro_nuevo && usermod -d /home/pedro_nuevo -m pedro" "6_home.txt"
RUN "ls -ld /home/pedro_nuevo" "6_home.txt"

STEP "7) Bloquear y desbloquear 'maria'"
RUN "usermod -L maria && passwd -S maria" "7_bloq.txt"
RUN "usermod -U maria && passwd -S maria" "7_bloq.txt"

STEP "8) Eliminar 'sinhome'"
RUN "id sinhome || true" "8_del_sinhome.txt"
RUN "userdel -r sinhome || true" "8_del_sinhome.txt"

STEP "9) Consultar info de 'juan' (id / finger)"
RUN "id juan" "9_id_finger.txt"
RUN "finger juan" "9_id_finger.txt"

# ===== PERMISOS Y ARCHIVOS =====
STEP "10) Estructura /home/recursos/{documentos,imagenes,scripts}"
RUN "mkdir -p /home/recursos/{documentos,imagenes,scripts}" "10_tree.txt"
RUN "tree -d /home/recursos || ls -lR /home/recursos" "10_tree.txt"

STEP "11) Crear archivos de prueba"
RUN "touch /home/recursos/documentos/info.txt" "11_archivos.txt"
RUN "touch /home/recursos/scripts/instalar.sh" "11_archivos.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "11_archivos.txt"

STEP "12) Propietarios"
RUN "chown juan:docentes /home/recursos/documentos/info.txt" "12_prop.txt"
RUN "chown pedro:estudiantes /home/recursos/scripts/instalar.sh" "12_prop.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "12_prop.txt"

STEP "13) Permisos específicos"
RUN "chmod 640 /home/recursos/documentos/info.txt" "13_perm.txt"
RUN "chmod 750 /home/recursos/scripts/instalar.sh" "13_perm.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "13_perm.txt"

STEP "14) Cambios con notación simbólica"
RUN "chmod u+x,g-w,o-r /home/recursos/scripts/instalar.sh" "14_perm_simb.txt"
RUN "ls -l /home/recursos/scripts" "14_perm_simb.txt"

STEP "15) chgrp recursivo y chmod recursivo"
RUN "chgrp -R docentes /home/recursos/documentos" "15_chgrp.txt"
RUN "chmod -R 755 /home/recursos" "15_chmodR.txt"
RUN "ls -lR /home/recursos | head -n 50" "15_lsR.txt"

STEP "16) umask y verificación"
RUN "umask 027; touch /home/recursos/nuevo_archivo.txt" "16_umask.txt"
RUN "ls -l /home/recursos/nuevo_archivo.txt" "16_umask.txt"

STEP "17) Script /home/recursos/backup.sh"
RUN_CLEAN "cat > /home/recursos/backup.sh" \
          "bash -lc 'cat >/home/recursos/backup.sh <<EOF
#!/bin/bash
echo \"Respaldo completado\"
EOF'" "17_backup.txt"
RUN "chmod +x /home/recursos/backup.sh" "17_backup.txt"
RUN "/home/recursos/backup.sh" "17_backup.txt"

# ===== PROCESOS =====
STEP "18) ps aux y filtrado"
RUN "ps aux | head -n 20" "18_ps.txt"
RUN "ps aux | grep bash | grep -v grep" "18_ps.txt"

STEP "19) kill normal y forzado (demo con sleep)"
RUN_CLEAN "sleep 120 &  # (capturar PID y ver estado)" \
          "bash -lc 'sleep 120 & echo BG_PID=\$!; echo \$BG_PID > /tmp/bg_sleep.pid; ps -p \$BG_PID -o pid,comm,etime'" "19_kill.txt"
RUN "kill \$(cat /tmp/bg_sleep.pid) || true" "19_kill.txt"
RUN_CLEAN "sleep 300 &  # (demo SIGKILL)" \
          "bash -lc 'sleep 300 & echo \$! > /tmp/bg_sleep2.pid; true'" "19_kill.txt"
RUN "kill -9 \$(cat /tmp/bg_sleep2.pid) || true" "19_kill.txt"

STEP "20) top batch (para captura)"
RUN "top -b -n1 | head -n 20" "20_top.txt"

STEP "21) Script procesos_usuario.sh"
RUN_CLEAN "cat > /home/recursos/procesos_usuario.sh" \
          "bash -lc 'cat >/home/recursos/procesos_usuario.sh <<EOF
#!/bin/bash
ps -u \"\$USER\"
EOF'" "21_proc_user.txt"
RUN "chmod +x /home/recursos/procesos_usuario.sh" "21_proc_user.txt"
RUN "su - $REAL_USER -c /home/recursos/procesos_usuario.sh || /home/recursos/procesos_usuario.sh" "21_proc_user.txt"

# ===== DESAFÍO FINAL =====
STEP "Desafío final: usuarios, grupo proyecto y control.sh"
RUN_CLEAN "adduser ana     # (password: ana)" \
          "adduser --disabled-password --gecos '' ana && echo 'ana:ana' | chpasswd" "DF_users.txt"
RUN_CLEAN "adduser carlos  # (password: carlos)" \
          "adduser --disabled-password --gecos '' carlos && echo 'carlos:carlos' | chpasswd" "DF_users.txt"
RUN_CLEAN "adduser sofia   # (password: sofia)" \
          "adduser --disabled-password --gecos '' sofia && echo 'sofia:sofia' | chpasswd" "DF_users.txt"

RUN "groupadd proyecto" "DF_proyecto.txt"
RUN "usermod -aG proyecto ana && usermod -aG proyecto carlos && usermod -aG proyecto sofia" "DF_proyecto.txt"
RUN "mkdir -p /proyecto && chmod 770 /proyecto && chown root:proyecto /proyecto" "DF_proyecto.txt"

RUN_CLEAN "cat > /proyecto/control.sh" \
          "bash -lc 'cat >/proyecto/control.sh <<EOF
#!/bin/bash
LOG=\"/proyecto/usuarios_conectados.log\"
who | tee -a \"\$LOG\"
EOF'" "DF_control.txt"
RUN "chmod +x /proyecto/control.sh" "DF_control.txt"
RUN "/proyecto/control.sh & echo \$! > /tmp/control_pid && ps -p \$(cat /tmp/control_pid) -o pid,comm,etime" "DF_control.txt"
RUN "kill \$(cat /tmp/control_pid) || true" "DF_control.txt"
RUN "ls -l /proyecto && tail -n +1 -v /proyecto/usuarios_conectados.log 2>/dev/null || true" "DF_control.txt"

echo -e "\n✅ Listo. Evidencias en: $LOGDIR"
NOTE "Para grabar toda la sesión en un transcript:\n  script -a ~/taller_linux_transcript.txt -c 'sudo ./taller_linux_guiado_clean.sh'"
