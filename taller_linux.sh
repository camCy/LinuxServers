#!/usr/bin/env bash
# Taller de comandos Linux - Modo "yo tecleo"
# - Limpia la pantalla SOLO al final de cada punto
# - Enter silencioso al final de cada punto (sin mostrar mensaje)
# - Muestra salida completa de los comandos
# Ejecutar: sudo ./taller_linux_guiado_clean.sh

set -euo pipefail
set -m  # habilita control de trabajos para jobs/bg/fg en shell no interactiva

# ========= Config =========
LOGDIR="$HOME/taller_linux_logs"
mkdir -p "$LOGDIR"

REQUIRE_ROOT() { if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo o como root."; exit 1; fi; }
REQUIRE_ROOT

REAL_USER="${SUDO_USER:-$USER}"
HOSTNAME_SHOW="$(hostname -s || echo debian)"
PROMPT_COLOR="\e[1;32m"
RESET_COLOR="\e[0m"
TYPE_SPEED="${TYPE_SPEED:-0.01}"  # 0.005-0.02 recomendado

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

# Ejecuta en la MISMA shell (eval), así jobs/bg/fg funcionan
RUN() {
  local cmd="$1"
  local log="${2:-}"
  show_prompt_and_cmd "$cmd"
  set +e
  if [[ -n "$log" ]]; then
    eval "$cmd" 2>&1 | tee -a "$LOGDIR/$log"
  else
    eval "$cmd"
  fi
  local rc=$?
  set -e
  echo
  return $rc
}

# Muestra un comando “bonito” pero ejecuta otro real (oculto) en la MISMA shell
RUN_CLEAN() {
  local display_cmd="$1"   # lo que se muestra
  local exec_cmd="$2"      # lo que se ejecuta realmente
  local log="${3:-}"
  show_prompt_and_cmd "$display_cmd"
  set +e
  if [[ -n "$log" ]]; then
    eval "$exec_cmd" 2>&1 | tee -a "$LOGDIR/$log"
  else
    eval "$exec_cmd"
  fi
  local rc=$?
  set -e
  echo
  return $rc
}

STEP_BEGIN() { 
  echo -e "\n\n=============================="
  echo "🧪 $1"
  echo "=============================="
}
STEP_END() {
  # Espera silenciosa a Enter (sin mensaje), luego limpia y sigue
  read -rs
  clear
}

NOTE() { echo -e "💡 $1"; }

# ================== Inicio ==================

STEP_BEGIN "0) Preparación: actualizar e instalar utilidades"
RUN "apt-get update -y" "apt.log"
RUN "DEBIAN_FRONTEND=noninteractive apt-get install -y finger tree bc" "apt.log"
STEP_END

# ===== ADMINISTRACIÓN DE USUARIOS Y GRUPOS =====

STEP_BEGIN "1) Crear usuarios: juan, maria, pedro"
RUN_CLEAN "adduser juan   # (password: juan)" \
          "adduser --disabled-password --gecos '' juan && echo 'juan:juan' | chpasswd" "1_usuarios.txt"
RUN_CLEAN "adduser maria  # (password: maria)" \
          "adduser --disabled-password --gecos '' maria && echo 'maria:maria' | chpasswd" "1_usuarios.txt"
RUN_CLEAN "adduser pedro  # (password: pedro)" \
          "adduser --disabled-password --gecos '' pedro && echo 'pedro:pedro' | chpasswd" "1_usuarios.txt"
RUN "id juan && id maria && id pedro" "1_verificacion.txt"
STEP_END

STEP_BEGIN "2) Crear grupos docentes y estudiantes"
RUN "groupadd docentes" "2_grupos.txt"
RUN "groupadd estudiantes" "2_grupos.txt"
RUN "getent group docentes && getent group estudiantes" "2_grupos.txt"
STEP_END

STEP_BEGIN "3) Agregar usuarios a grupos"
RUN "usermod -aG docentes juan" "3_grupos_user.txt"
RUN "usermod -aG estudiantes maria" "3_grupos_user.txt"
RUN "usermod -aG estudiantes pedro" "3_grupos_user.txt"
RUN "id juan && id maria && id pedro" "3_verificacion.txt"
STEP_END

STEP_BEGIN "4) Usuario sin carpeta personal"
# Mostramos passwd sugerido en taller, pero ejecutamos chpasswd oculto
RUN_CLEAN "useradd -M sinhome  # (password: sinhome)" \
          "useradd -M sinhome && echo 'sinhome:sinhome' | chpasswd" "4_sinhome.txt"
RUN "getent passwd sinhome" "4_sinhome.txt"
STEP_END

STEP_BEGIN "5) Cambiar shell de 'juan' a /bin/sh"
RUN "usermod -s /bin/sh juan" "5_shell.txt"
RUN "getent passwd juan" "5_shell.txt"
STEP_END

STEP_BEGIN "6) Cambiar HOME de 'pedro' a /home/pedro_nuevo"
RUN "mkdir -p /home/pedro_nuevo" "6_home.txt"
RUN "usermod -d /home/pedro_nuevo -m pedro" "6_home.txt"
RUN "ls -ld /home/pedro_nuevo" "6_home.txt"
STEP_END

STEP_BEGIN "7) Bloquear y desbloquear 'maria'"
RUN "usermod -L maria" "7_bloq.txt"
RUN "passwd -S maria" "7_bloq.txt"
RUN "usermod -U maria" "7_bloq.txt"
RUN "passwd -S maria" "7_bloq.txt"
STEP_END

STEP_BEGIN "8) Eliminar 'sinhome'"
RUN "id sinhome || true" "8_del_sinhome.txt"
RUN "userdel -r sinhome || true" "8_del_sinhome.txt"
STEP_END

STEP_BEGIN "9) Consultar info de 'juan' (id / finger)"
RUN "id juan" "9_id_finger.txt"
RUN "finger juan" "9_id_finger.txt"
STEP_END

# ===== PERMISOS Y ARCHIVOS =====

STEP_BEGIN "10) Estructura /home/recursos/{documentos,imagenes,scripts}"
RUN "mkdir -p /home/recursos/{documentos,imagenes,scripts}" "10_tree.txt"
RUN "tree -d /home/recursos || ls -lR /home/recursos" "10_tree.txt"
STEP_END

STEP_BEGIN "11) Crear archivos de prueba"
RUN "touch /home/recursos/documentos/info.txt" "11_archivos.txt"
RUN "touch /home/recursos/scripts/instalar.sh" "11_archivos.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "11_archivos.txt"
STEP_END

STEP_BEGIN "12) Propietarios"
RUN "chown juan:docentes /home/recursos/documentos/info.txt" "12_prop.txt"
RUN "chown pedro:estudiantes /home/recursos/scripts/instalar.sh" "12_prop.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "12_prop.txt"
STEP_END

STEP_BEGIN "13) Permisos específicos"
RUN "chmod 640 /home/recursos/documentos/info.txt" "13_perm.txt"
RUN "chmod 750 /home/recursos/scripts/instalar.sh" "13_perm.txt"
RUN "ls -l /home/recursos/documentos /home/recursos/scripts" "13_perm.txt"
STEP_END

STEP_BEGIN "14) Cambios con notación simbólica"
RUN "chmod u+x,g-w,o-r /home/recursos/scripts/instalar.sh" "14_perm_simb.txt"
RUN "ls -l /home/recursos/scripts" "14_perm_simb.txt"
STEP_END

STEP_BEGIN "15) chgrp recursivo y chmod recursivo"
RUN "chgrp -R docentes /home/recursos/documentos" "15_chgrp.txt"
RUN "chmod -R 755 /home/recursos" "15_chmodR.txt"
RUN "ls -lR /home/recursos" "15_lsR.txt"
STEP_END

STEP_BEGIN "16) umask y verificación"
RUN "umask 027; touch /home/recursos/nuevo_archivo.txt" "16_umask.txt"
RUN "ls -l /home/recursos/nuevo_archivo.txt" "16_umask.txt"
STEP_END

STEP_BEGIN "17) Script /home/recursos/backup.sh"
RUN_CLEAN "cat > /home/recursos/backup.sh" \
          "cat >/home/recursos/backup.sh <<'EOF'
#!/bin/bash
echo \"Respaldo completado\"
EOF" "17_backup.txt"
RUN "chmod +x /home/recursos/backup.sh" "17_backup.txt"
RUN "/home/recursos/backup.sh" "17_backup.txt"
STEP_END

# ===== PROCESOS =====

STEP_BEGIN "18) ps aux y filtrado"
# El taller pide: ps aux | less; mostramos literal pero ejecutamos sin pager
RUN_CLEAN "ps aux | less" "ps aux" "18_ps.txt"
RUN "ps aux | grep bash | grep -v grep" "18_ps.txt"
STEP_END

STEP_BEGIN "19) kill normal y forzado (demo con sleep)"
RUN "sleep 120 & BG_PID=$!; echo \$BG_PID > /tmp/bg_sleep.pid; ps -p \$BG_PID -o pid,comm,etime" "19_kill.txt"
RUN "kill \$(cat /tmp/bg_sleep.pid) || true" "19_kill.txt"
RUN "sleep 300 & echo \$! > /tmp/bg_sleep2.pid" "19_kill.txt"
RUN "kill -9 \$(cat /tmp/bg_sleep2.pid) || true" "19_kill.txt"
STEP_END

STEP_BEGIN "20) top batch"
RUN "top -b -n1" "20_top.txt"
STEP_END

STEP_BEGIN "21) Script procesos_usuario.sh"
RUN_CLEAN "cat > /home/recursos/procesos_usuario.sh" \
          "cat >/home/recursos/procesos_usuario.sh <<'EOF'
#!/bin/bash
ps -u \"\$USER\"
EOF" "21_proc_user.txt"
RUN "chmod +x /home/recursos/procesos_usuario.sh" "21_proc_user.txt"
RUN "/home/recursos/procesos_usuario.sh" "21_proc_user.txt"
STEP_END

# ===== DESAFÍO FINAL =====

STEP_BEGIN "DF-1..3) Usuarios ana, carlos, sofia y grupo proyecto"
RUN_CLEAN "adduser ana     # (password: ana)" \
          "adduser --disabled-password --gecos '' ana && echo 'ana:ana' | chpasswd" "DF_users.txt"
RUN_CLEAN "adduser carlos  # (password: carlos)" \
          "adduser --disabled-password --gecos '' carlos && echo 'carlos:carlos' | chpasswd" "DF_users.txt"
RUN_CLEAN "adduser sofia   # (password: sofia)" \
          "adduser --disabled-password --gecos '' sofia && echo 'sofia:sofia' | chpasswd" "DF_users.txt"
RUN "groupadd proyecto" "DF_proyecto.txt"
RUN "usermod -aG proyecto ana && usermod -aG proyecto carlos && usermod -aG proyecto sofia" "DF_proyecto.txt"
STEP_END

STEP_BEGIN "DF-4..6) Carpeta /proyecto, permisos, y plan.txt solo grupo"
RUN "mkdir -p /proyecto" "DF_proyecto.txt"
RUN "chmod 770 /proyecto" "DF_proyecto.txt"
RUN "chown root:proyecto /proyecto" "DF_proyecto.txt"
# DF-6 pendiente del PDF: plan.txt 660 y root:proyecto
RUN "touch /proyecto/plan.txt" "DF_proyecto.txt"
RUN "chmod 660 /proyecto/plan.txt" "DF_proyecto.txt"
RUN "chown root:proyecto /proyecto/plan.txt" "DF_proyecto.txt"
RUN "ls -l /proyecto" "DF_proyecto.txt"
STEP_END

STEP_BEGIN "DF-7..8) control.sh en background y finalizar"
RUN_CLEAN "cat > /proyecto/control.sh" \
          "cat >/proyecto/control.sh <<'EOF'
#!/bin/bash
LOG=\"/proyecto/usuarios_conectados.log\"
who | tee -a \"\$LOG\"
EOF" "DF_control.txt"
RUN "chmod +x /proyecto/control.sh" "DF_control.txt"
RUN "/proyecto/control.sh & echo \$! > /tmp/control_pid; ps -p \$(cat /tmp/control_pid) -o pid,comm,etime" "DF_control.txt"
RUN "kill \$(cat /tmp/control_pid) || true" "DF_control.txt"
RUN "ls -l /proyecto && tail -n +1 -v /proyecto/usuarios_conectados.log 2>/dev/null || true" "DF_control.txt"
STEP_END

echo -e "\n✅ Taller completado. Evidencias en: $LOGDIR"
echo -e "💡 Sugerencia: si deseas transcript completo:\n  script -a ~/taller_linux_transcript.txt -c 'sudo ./taller_linux_guiado_clean.sh'"
