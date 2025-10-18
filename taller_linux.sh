#!/usr/bin/env bash
set -euo pipefail

# === Configuración ===
LOGDIR="$HOME/taller_linux_logs"
mkdir -p "$LOGDIR"

PAUSE() {
  echo
  read -rp "➡️  Toma la captura y presiona Enter para continuar..."
  echo
}

STEP() {
  echo -e "\n\n=============================="
  echo "🧪 $1"
  echo "=============================="
}

REQUIRE_ROOT() {
  if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse con sudo o como root."
    exit 1
  fi
}

REQUIRE_ROOT

# Utilidad para evitar errores si ya existen
ensure_group() {
  local g="$1"
  if getent group "$g" >/dev/null; then
    echo "Grupo '$g' ya existe."
  else
    groupadd "$g"
    echo "Grupo '$g' creado."
  fi
}

ensure_user_adduser() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    echo "Usuario '$u' ya existe."
  else
    # adduser interactivo -> usamos no-interactivo con --disabled-password y luego seteamos clave
    adduser --disabled-password --gecos "" "$u"
    echo "$u:$u" | chpasswd
    echo "Usuario '$u' creado (password = nombre de usuario)."
  fi
}

ensure_user_useradd_nohome() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    echo "Usuario '$u' ya existe."
  else
    useradd -M "$u"
    echo "$u:$u" | chpasswd
    echo "Usuario '$u' creado SIN home (password = nombre de usuario)."
  fi
}

# ===== Pre requisitos =====
STEP "0) Preparación del entorno (paquetes y contexto)"
echo "Instalando 'finger' para el punto 10..."
apt-get update -y >>"$LOGDIR/apt.log" 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y finger >>"$LOGDIR/apt.log" 2>&1
echo "Listo. Logs en $LOGDIR/apt.log"
PAUSE

# ===== ADMINISTRACIÓN DE USUARIOS Y GRUPOS =====
STEP "1) Crear tres usuarios (juan, maria, pedro) con adduser"
ensure_user_adduser juan
ensure_user_adduser maria
ensure_user_adduser pedro
echo "Verificación:"
id juan | tee "$LOGDIR/1_id_juan.txt"
id maria | tee "$LOGDIR/1_id_maria.txt"
id pedro | tee "$LOGDIR/1_id_pedro.txt"
PAUSE

STEP "2) Crear grupos 'docentes' y 'estudiantes'"
ensure_group docentes
ensure_group estudiantes
echo "Verifica con: getent group docentes/estudiantes"
getent group docentes | tee "$LOGDIR/2_docentes.txt"
getent group estudiantes | tee "$LOGDIR/2_estudiantes.txt"
PAUSE

STEP "3) Asignar usuarios a grupos"
usermod -aG docentes juan
usermod -aG estudiantes maria
usermod -aG estudiantes pedro
echo "Verificación de pertenencia a grupos:"
id juan | tee "$LOGDIR/3_juan.txt"
id maria | tee "$LOGDIR/3_maria.txt"
id pedro | tee "$LOGDIR/3_pedro.txt"
PAUSE

STEP "4) Crear usuario sin carpeta personal (sinhome) con useradd -M"
ensure_user_useradd_nohome sinhome
echo "Verifica que no tenga /home:"
getent passwd sinhome | tee "$LOGDIR/4_sinhome_passwd.txt"
PAUSE

STEP "5) Asignar contraseña a 'sinhome'"
echo "Reasignando contraseña no interactiva: sinhome:sinhome"
echo "sinhome:sinhome" | chpasswd
echo "Hecho."
PAUSE

STEP "6) Cambiar shell de login de 'juan' a /bin/sh"
usermod -s /bin/sh juan
getent passwd juan | tee "$LOGDIR/6_juan_shell.txt"
PAUSE

STEP "7) Modificar directorio home de 'pedro' -> /home/pedro_nuevo"
# Creamos carpeta si no existe y migramos contenido si hubiera
mkdir -p /home/pedro_nuevo
usermod -d /home/pedro_nuevo -m pedro
ls -ld /home/pedro_nuevo | tee "$LOGDIR/7_home_pedro.txt"
PAUSE

STEP "8) Bloquear y desbloquear usuario 'maria'"
usermod -L maria
passwd -S maria | tee "$LOGDIR/8_maria_bloq.txt"
PAUSE
usermod -U maria
passwd -S maria | tee "$LOGDIR/8_maria_desbloq.txt"
PAUSE

STEP "9) Eliminar usuario 'sinhome' y su home (no tiene home)"
# Si existe, eliminar
if id -u sinhome >/dev/null 2>&1; then
  userdel -r sinhome || true
  echo "Usuario 'sinhome' eliminado."
else
  echo "Usuario 'sinhome' ya no existe."
fi
PAUSE

STEP "10) Consultar info de 'juan' con id y finger"
id juan | tee "$LOGDIR/10_id_juan.txt"
finger juan | tee "$LOGDIR/10_finger_juan.txt"
PAUSE

# ===== PERMISOS Y PROPIEDAD DE ARCHIVOS =====
STEP "11) Crear estructura de carpetas /home/recursos/{documentos,imagenes,scripts}"
mkdir -p /home/recursos/{documentos,imagenes,scripts}
tree -d /home/recursos || ls -lR /home/recursos | tee "$LOGDIR/11_tree.txt"
PAUSE

STEP "12) Crear archivos de prueba"
touch /home/recursos/documentos/info.txt
touch /home/recursos/scripts/instalar.sh
ls -l /home/recursos/documentos /home/recursos/scripts | tee "$LOGDIR/12_ls.txt"
PAUSE

STEP "13) Asignar propietarios a los archivos"
chown juan:docentes /home/recursos/documentos/info.txt
chown pedro:estudiantes /home/recursos/scripts/instalar.sh
ls -l /home/recursos/documentos /home/recursos/scripts | tee "$LOGDIR/13_propietarios.txt"
PAUSE

STEP "14) Dar permisos específicos (640 y 750)"
chmod 640 /home/recursos/documentos/info.txt
chmod 750 /home/recursos/scripts/instalar.sh
ls -l /home/recursos/documentos /home/recursos/scripts | tee "$LOGDIR/14_permisos.txt"
PAUSE

STEP "15) Cambiar permisos usando letras u+x,g-w,o-r en instalar.sh"
chmod u+x,g-w,o-r /home/recursos/scripts/instalar.sh
ls -l /home/recursos/scripts | tee "$LOGDIR/15_permisos_letras.txt"
PAUSE

STEP "16) Comprobar permisos con ls -l"
ls -l /home/recursos/documentos | tee "$LOGDIR/16_doc.txt"
ls -l /home/recursos/scripts | tee "$LOGDIR/16_scripts.txt"
PAUSE

STEP "17) Cambiar grupo propietario de /home/recursos/documentos a 'docentes' (recursivo)"
chgrp -R docentes /home/recursos/documentos
ls -l /home/recursos/documentos | tee "$LOGDIR/17_chgrp.txt"
PAUSE

STEP "18) Aplicar permisos recursivos 755 a /home/recursos"
chmod -R 755 /home/recursos
ls -lR /home/recursos | tee "$LOGDIR/18_chmodR.txt"
PAUSE

STEP "19) Establecer umask 027 y verificar"
umask 027
touch /home/recursos/nuevo_archivo.txt
ls -l /home/recursos/nuevo_archivo.txt | tee "$LOGDIR/19_umask.txt"
PAUSE

STEP "20) Crear script backup.sh y hacerlo ejecutable"
cat >/home/recursos/backup.sh <<'EOF'
#!/bin/bash
echo "Respaldo completado"
EOF
chmod +x /home/recursos/backup.sh
ls -l /home/recursos/backup.sh | tee "$LOGDIR/20_backup_ls.txt"
echo "Ejecución:"
/home/recursos/backup.sh | tee "$LOGDIR/20_backup_out.txt"
PAUSE

# ===== GESTIÓN DE PROCESOS =====
STEP "21) Mostrar todos los procesos (ps aux | less) -> se usará 'head' para no abrir pager"
ps aux | tee "$LOGDIR/21_ps_aux.txt"
head -n 20 "$LOGDIR/21_ps_aux.txt"
PAUSE

STEP "22) Mostrar procesos del usuario actual (ps -u \$USER)"
su - "$SUDO_USER" -c 'ps -u $USER' | tee "$LOGDIR/22_ps_user.txt" || ps -u "$SUDO_USER" | tee "$LOGDIR/22_ps_user.txt"
PAUSE

STEP "23) Identificar PID de bash con grep"
ps aux | grep bash | grep -v grep | tee "$LOGDIR/23_grep_bash.txt"
PAUSE

STEP "24) Finalizar un proceso normal (demo con 'sleep 120' en background)"
sleep 120 &
SPID=$!
echo "sleep lanzado con PID=$SPID"
ps -p "$SPID" -o pid,comm,etime | tee "$LOGDIR/24_sleep_ps.txt"
kill "$SPID"
echo "kill normal enviado. Verifica estado:"
ps -p "$SPID" -o pid,comm,etime || echo "Proceso $SPID finalizado."
PAUSE

STEP "25) Forzar cierre (kill -9) de un proceso bloqueado (simulación con sleep 300)"
sleep 300 &
SPID2=$!
echo "sleep lanzado con PID=$SPID2"
kill -9 "$SPID2" || true
echo "kill -9 enviado."
ps -p "$SPID2" -o pid,comm,etime || echo "Proceso $SPID2 finalizado con SIGKILL."
PAUSE

STEP "26) Ejecutar proceso en segundo plano y listar jobs"
# Jobs solo funciona en shell interactiva; evidenciamos con '&' y 'jobs' equivalente:
sleep 300 &
echo "Segundo plano lanzado (sleep 300). PID=$!"
jobs || echo "(Nota: 'jobs' no siempre muestra en shell no-interactiva)"
PAUSE

STEP "27) Traer proceso al frente (fg %1) - demostración alternativa"
echo "En shell no-interactiva 'fg' no aplica. Muestra nota y captura."
echo "Para captura: En una terminal interactiva usar: sleep 300 & ; jobs ; fg %1"
PAUSE

STEP "28) Suspender y reanudar (Ctrl+Z; bg %1) - explicación"
echo "En shell no-interactiva no se puede enviar Ctrl+Z. Para tu evidencia:"
echo "Ejemplo interactivo:"
echo "  1) Ejecuta: yes > /dev/null"
echo "  2) Presiona: Ctrl+Z (suspende)"
echo "  3) Ejecuta: bg %1 (reanuda en segundo plano)"
echo "  4) Ejecuta: kill %1 (finaliza)"
PAUSE

STEP "29) Consultar uso de CPU y memoria: top (usaremos top -b -n1 para captura)"
top -b -n1 | head -n 20 | tee "$LOGDIR/29_top.txt"
PAUSE

STEP "30) Crear script procesos_usuario.sh y hacerlo ejecutable"
cat >/home/recursos/procesos_usuario.sh <<'EOF'
#!/bin/bash
ps -u "$USER"
EOF
chmod +x /home/recursos/procesos_usuario.sh
echo "Ejecución:"
su - "$SUDO_USER" -c '/home/recursos/procesos_usuario.sh' | tee "$LOGDIR/30_procesos_user.txt" || /home/recursos/procesos_usuario.sh | tee "$LOGDIR/30_procesos_user.txt"
PAUSE

# ===== DESAFÍO FINAL =====
STEP "Desafío Final (1-8)"
# 1) Usuarios ana, carlos, sofia
ensure_user_adduser ana
ensure_user_adduser carlos
ensure_user_adduser sofia

# 2) Grupo 'proyecto'
ensure_group proyecto

# 3) Asignar usuarios al grupo
usermod -aG proyecto ana
usermod -aG proyecto carlos
usermod -aG proyecto sofia

# 4) Carpeta /proyecto con permisos 770
mkdir -p /proyecto
chmod 770 /proyecto

# 5) Propietario root:proyecto
chown root:proyecto /proyecto

# 6) Crear plan.txt editable solo por el grupo
touch /proyecto/plan.txt
chown root:proyecto /proyecto/plan.txt
chmod 660 /proyecto/plan.txt

# 7) Script control.sh: usuarios conectados -> log
cat >/proyecto/control.sh <<'EOF'
#!/bin/bash
LOG="/proyecto/usuarios_conectados.log"
who | tee -a "$LOG"
EOF
chmod +x /proyecto/control.sh

# 8) Ejecutar en segundo plano y luego finalizar con ps/kill
/proyecto/control.sh &
CPID=$!
echo "control.sh corriendo en background. PID=$CPID"
ps -p "$CPID" -o pid,comm,etime | tee "$LOGDIR/DF_ps_control.txt"
kill "$CPID" || true
sleep 1
ps -p "$CPID" -o pid,comm,etime || echo "control.sh ($CPID) finalizado."
echo "Estructura final:"
ls -l /proyecto | tee "$LOGDIR/DF_ls_proyecto.txt"

echo -e "\n✅ Taller completado. Evidencias en: $LOGDIR"

#ejecución: sudo bash taller_linux.sh
