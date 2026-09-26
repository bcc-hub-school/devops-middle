#!/bin/bash
# Linux Deep · Модуль 10 «System Recovery» · задания к занятиям 25–26 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_10.sh
#
#   bash module_10.sh list                  какие задания есть
#   sudo bash module_10.sh setup task_25    подготовить стенд и показать задание
#   sudo bash module_10.sh check task_25    проверить
#   sudo bash module_10.sh reset task_25    начать заново (стенд пересоздаётся)
#   sudo bash module_10.sh clean task_25    убрать стенд после занятия
#   bash module_10.sh task  task_25     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_25 task_26"

# ---------- общие функции ----------
_P=0; _F=0
pass()    { _P=$((_P+1)); printf '  [ OK ] %s\n' "$1"; }
fail()    { _F=$((_F+1)); printf '  [FAIL] %s\n' "$1"; }
check()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
as()      { local u="$1"; shift; timeout 15 su -s /bin/bash "$u" -c "$*" </dev/null; }
summary() { echo; echo "ИТОГ: $_P из $((_P+_F))"; [ "$_F" -eq 0 ] && echo "Всё верно."; [ "$_F" -eq 0 ]; }
need_pkg() { local p miss=""; for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"; done
             [ -z "$miss" ] || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $miss >/dev/null; }; }

alive()   { ps -eo stat=,comm= | awk -v n="$1" '$1 !~ /^Z/ && $2==n {f=1} END{exit !f}'; }   # зомби живыми не считаем
unit_rm() { local u; for u in "$@"; do systemctl disable --now "$u" >/dev/null 2>&1; systemctl reset-failed "$u" >/dev/null 2>&1; rm -f "/etc/systemd/system/$u"; rm -rf "/etc/systemd/system/$u.d"; done
            systemctl daemon-reload; true; }


# ====================================================================
# task_25 · занятие 25 · загрузка и rescue (без перезагрузки ВМ!)
# ====================================================================
task_25_text() { cat <<'T'
Задание 25 (5–10 мин) · загрузка и rescue
Ничего не ломаем и не перезагружаем: только читаем состояние загрузки и правим один параметр GRUB.
Построчно запишите в /root/task25-answer.txt:
  1. Текущее ядро.                                     uname -r
  2. Значение root= из /proc/cmdline.                   cat /proc/cmdline
  3. Текущее значение GRUB_TIMEOUT (до правки).         grep GRUB_TIMEOUT /etc/default/grub
  4. Текущий default.target.                            systemctl get-default
  5. Имя самого долгого юнита при загрузке.             systemd-analyze blame | head -1
Затем сделайте GRUB_TIMEOUT равным 3 и примените:                     sudo update-grub
  Ловушка: значение задаётся не только в /etc/default/grub —           grep -r GRUB_TIMEOUT /etc/default/
  drop-in /etc/default/grub.d/*.cfg читается позже и побеждает.
  Проверьте себя: sudo grep timeout /boot/grub/grub.cfg — должно быть timeout=3.
ВМ НЕ перезагружайте и default.target НЕ меняйте — стенд должен остаться живым.
T
}
task_25_cleanup() {
  if [ -f /opt/ld-tasks/task25/grub.default.bak ]; then
    cp -a /opt/ld-tasks/task25/grub.default.bak /etc/default/grub
    if [ -d /opt/ld-tasks/task25/grub.d.bak ]; then rm -rf /etc/default/grub.d; cp -a /opt/ld-tasks/task25/grub.d.bak /etc/default/grub.d; fi
    update-grub >/dev/null 2>&1 || true
  fi
  rm -rf /opt/ld-tasks/task25 /root/task25-answer.txt
  true
}
task_25_setup() {
  task_25_cleanup
  if [ ! -f /etc/default/grub ] || ! command -v update-grub >/dev/null 2>&1; then
    echo "На этой машине нет GRUB (/etc/default/grub или update-grub) — задание 25 рассчитано на обычную ВМ с GRUB." >&2
    return 1
  fi
  install -d -m 755 /opt/ld-tasks/task25
  cp -a /etc/default/grub /opt/ld-tasks/task25/grub.default.bak
  [ -d /etc/default/grub.d ] && cp -a /etc/default/grub.d /opt/ld-tasks/task25/grub.d.bak
  {
    uname -r
    grep -oP 'root=\S+' /proc/cmdline | cut -d= -f2-
    grep -oP '^GRUB_TIMEOUT=\K.*' /etc/default/grub | tr -d '"'
    systemctl get-default
    systemd-analyze blame | head -1 | awk '{print $NF}'
  } > /opt/ld-tasks/task25/answers.ref
}
task_25_check() {
  local ans=/root/task25-answer.txt ref=/opt/ld-tasks/task25/answers.ref
  check "строка 1 = текущее ядро (uname -r)" \
        bash -c '[ "$(sed -n 1p /root/task25-answer.txt | tr -d "[:space:]")" = "$(sed -n 1p /opt/ld-tasks/task25/answers.ref)" ]'
  check "строка 2 = root= из /proc/cmdline" \
        bash -c '[ "$(sed -n 2p /root/task25-answer.txt | tr -d "[:space:]")" = "$(sed -n 2p /opt/ld-tasks/task25/answers.ref)" ]'
  check "строка 3 = исходный GRUB_TIMEOUT" \
        bash -c '[ "$(sed -n 3p /root/task25-answer.txt | tr -d "[:space:]")" = "$(sed -n 3p /opt/ld-tasks/task25/answers.ref)" ]'
  check "строка 4 = default.target" \
        bash -c '[ "$(sed -n 4p /root/task25-answer.txt | tr -d "[:space:]")" = "$(sed -n 4p /opt/ld-tasks/task25/answers.ref)" ]'
  check "строка 5 = самый долгий юнит (systemd-analyze blame)" \
        bash -c '[ "$(sed -n 5p /root/task25-answer.txt | tr -d "[:space:]")" = "$(sed -n 5p /opt/ld-tasks/task25/answers.ref)" ]'
  check "GRUB_TIMEOUT=3 применён: timeout=3 в /boot/grub/grub.cfg" \
        bash -c 'grep -Eq "timeout=3([^0-9]|$)" /boot/grub/grub.cfg'
  summary
}

# ====================================================================
# task_26 · занятие 26 · восстановление системы (без перезагрузки ВМ!)
# ====================================================================
task_26_text() { cat <<'T'
Задание 26 (5–10 мин) · восстановление системы
Ничего не перезагружаем: чиним «сломанную загрузку» прямо из работающей системы.
  1. В /etc/fstab (строка с меткой # ld-task26) — том с несуществующим UUID без nofail.
     Найдите её и обезвредьте: добавьте опцию nofail или удалите строку целиком.
                                                          findmnt --verify · nano /etc/fstab
  2. Проверьте, что система смонтирует всё без ошибок.    mount -a
  3. На loop-образе /var/tmp/ld-recover.img файловая система помечена «не чисто
     размонтированной»: найдите устройство, проверьте и почините его.
                                                          losetup -j /var/tmp/ld-recover.img ·
                                                          fsck -n /dev/loopX · fsck -y /dev/loopX
  4. Смонтируйте починенную ФС в /mnt/ld-recover.          mount /dev/loopX /mnt/ld-recover
  5. Запишите в /root/task26-answer.txt команду, которой в emergency-shell делают
     корень доступным на запись.                          mount -o remount,rw /
T
}
task_26_cleanup() {
  mountpoint -q /mnt/ld-recover 2>/dev/null && umount /mnt/ld-recover 2>/dev/null
  local dev; dev=$(losetup -j /var/tmp/ld-recover.img -O NAME --noheadings 2>/dev/null)
  [ -n "$dev" ] && losetup -d "$dev" 2>/dev/null
  rm -f /var/tmp/ld-recover.img /root/task26-answer.txt
  rm -rf /mnt/ld-recover /mnt/ld-task26-data
  if [ -f /opt/ld-tasks/task26/fstab.bak ]; then
    cp -a /opt/ld-tasks/task26/fstab.bak /etc/fstab
  fi
  rm -rf /opt/ld-tasks/task26
  true
}
task_26_setup() {
  task_26_cleanup
  install -d -m 755 /opt/ld-tasks/task26
  cp -a /etc/fstab /opt/ld-tasks/task26/fstab.bak

  # 1. Битая строка в fstab: несуществующий UUID, без nofail, с меткой-комментарием
  install -d -m 755 /mnt/ld-task26-data
  {
    echo
    echo '# ld-task26'
    echo 'UUID=de1e7ed0-0000-4000-8000-000000000026  /mnt/ld-task26-data  ext4  defaults  0  2'
  } >> /etc/fstab

  # 2. loop-образ ext4, помеченный как «не чисто размонтированный» (как в занятии 18)
  install -d -m 755 /mnt/ld-recover
  dd if=/dev/zero of=/var/tmp/ld-recover.img bs=1M count=32 status=none
  local dev; dev=$(losetup --find --show /var/tmp/ld-recover.img)
  mkfs.ext4 -q -F "$dev"
  debugfs -w -R "ssv state 0" "$dev" >/dev/null 2>&1
  true
}
task_26_check() {
  check "строка ld-task26 в /etc/fstab обезврежена (nofail или удалена)" \
    bash -c '! grep -q "# ld-task26" /etc/fstab || grep -A1 "# ld-task26" /etc/fstab | grep -q nofail'
  check "mount -a завершается без ошибок" \
    mount -a
  check "loop-образ ld-recover.img починен (tune2fs: Filesystem state: clean)" \
    bash -c 'dev=$(losetup -j /var/tmp/ld-recover.img -O NAME --noheadings 2>/dev/null); [ -n "$dev" ] && tune2fs -l "$dev" 2>/dev/null | awk -F: "/^Filesystem state/{gsub(/^[ \t]+/,\"\",\$2); exit (\$2==\"clean\")?0:1}"'
  check "починенная ФС смонтирована в /mnt/ld-recover" \
    bash -c 'want=$(losetup -j /var/tmp/ld-recover.img -O NAME --noheadings 2>/dev/null); have=$(findmnt -no SOURCE /mnt/ld-recover 2>/dev/null); [ -n "$want" ] && [ "$want" = "$have" ] && [ "$(findmnt -no FSTYPE /mnt/ld-recover 2>/dev/null)" = ext4 ]'
  check "в /root/task26-answer.txt записана команда remount,rw /" \
    bash -c "grep -Eq 'mount[[:space:]]+-o[[:space:]]+remount,rw[[:space:]]+/([[:space:]]|\$)' /root/task26-answer.txt"
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_10.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
main() {
  local action="${1:-list}" t="${2:-}"
  if [ "$action" = list ]; then
    for t in $TASKS; do printf '%-8s %s\n' "$t" "$("${t}_text" | head -1)"; done; echo; usage; return 0; fi
  case " $TASKS " in *" $t "*) ;; *) usage >&2; return 2 ;; esac
  case "$action" in
    task) "${t}_text"; return 0 ;;
    setup|check|reset|clean) ;;
    *) usage >&2; return 2 ;;
  esac
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_10.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_10.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
