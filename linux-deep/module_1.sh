#!/bin/bash
# Linux Deep · Модуль 1 «Linux Fundamentals» · задания к занятиям 1–3 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_1.sh
#
#   bash module_1.sh list                  какие задания есть
#   sudo bash module_1.sh setup task_1    подготовить стенд и показать задание
#   sudo bash module_1.sh check task_1    проверить
#   sudo bash module_1.sh reset task_1    начать заново (стенд пересоздаётся)
#   sudo bash module_1.sh clean task_1    убрать стенд после занятия
#   bash module_1.sh task  task_1     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Стенд создаёт и удаляет пользователей, файлы и пакеты.
set -u
TASKS="task_1 task_2 task_3"

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
# task_1 · занятие 1 · FHS: где что лежит
# ====================================================================
task_1_text() { cat <<'T'
Задание 1 (5 мин) · FHS
В /root/ld-task1 лежат три файла программы hello-ld. Перенесите (mv) каждый туда, где ему место по FHS:
  1. hello-ld        — исполняемый файл локального ПО      -> /usr/local/bin/
  2. hello-ld.conf   — конфигурация                         -> /etc/hello-ld/
  3. hello-ld.log    — журнал                               -> /var/log/hello-ld/
Каталоги создайте сами (mkdir). Готово, когда команда `sudo hello-ld` отвечает «hello-ld: ok».
T
}
task_1_cleanup() { rm -rf /root/ld-task1 /etc/hello-ld /var/log/hello-ld /usr/local/bin/hello-ld; }
task_1_setup() {
  task_1_cleanup; install -d -m 700 /root/ld-task1
  cat > /root/ld-task1/hello-ld <<'S'
#!/bin/bash
[ -r /etc/hello-ld/hello-ld.conf ]    || { echo "hello-ld: нет конфигурации в /etc/hello-ld/" >&2; exit 1; }
[ -e /var/log/hello-ld/hello-ld.log ] || { echo "hello-ld: нет журнала в /var/log/hello-ld/" >&2; exit 1; }
[ -w /var/log/hello-ld/hello-ld.log ] || { echo "hello-ld: нет прав на запись в журнал — запустите через sudo" >&2; exit 1; }
echo "$(date '+%F %T') run" >> /var/log/hello-ld/hello-ld.log; echo "hello-ld: ok"
S
  chmod 755 /root/ld-task1/hello-ld
  echo 'GREETING=hello' > /root/ld-task1/hello-ld.conf
  : > /root/ld-task1/hello-ld.log
}
task_1_check() {
  check "исполняемый файл: /usr/local/bin/hello-ld"   test -x /usr/local/bin/hello-ld
  check "конфигурация: /etc/hello-ld/hello-ld.conf"   test -f /etc/hello-ld/hello-ld.conf
  check "журнал: /var/log/hello-ld/hello-ld.log"      test -f /var/log/hello-ld/hello-ld.log
  check "команда hello-ld отвечает ok"                bash -c '/usr/local/bin/hello-ld | grep -q "hello-ld: ok"'
  summary
}

# ====================================================================
# task_2 · занятие 2 · пользователи, права, ACL, sudo
# ====================================================================
task_2_text() { cat <<'T'
Задание 2 (10 мин) · пользователи, права, ACL, sudo — по одному действию на тему
  1. Пользователи: создайте пользователя timur (домашний каталог, оболочка /bin/bash)
     и группу reports; добавьте timur в reports.                     useradd, groupadd, usermod -aG, id
  2. Права: создайте каталог /srv/reports — группа reports, права 770.   mkdir, chgrp, chmod, ls -ld
  3. ACL: файл /var/tmp/ld-summary.txt закрыт для всех (600).
     Дайте пользователю aliya право на чтение.                          setfacl -m, getfacl
  4. sudo: разрешите timur запускать /usr/bin/journalctl без пароля —
     файлом /etc/sudoers.d/timur.                                       visudo -f, sudo -l -U timur
T
}
task_2_cleanup() {
  rm -f /etc/sudoers.d/timur /var/tmp/ld-summary.txt; rm -rf /srv/reports
  pkill -KILL -u timur 2>/dev/null; pkill -KILL -u aliya 2>/dev/null
  userdel -r timur 2>/dev/null; userdel -r aliya 2>/dev/null; groupdel reports 2>/dev/null; true
}
task_2_setup() {
  need_pkg acl sudo; task_2_cleanup
  useradd -m -s /bin/bash aliya
  echo "Итоги квартала." > /var/tmp/ld-summary.txt; chmod 600 /var/tmp/ld-summary.txt
}
task_2_check() {
  check "пользователь timur с оболочкой /bin/bash"   bash -c '[ "$(getent passwd timur | cut -d: -f7)" = /bin/bash ]'
  check "timur состоит в группе reports"             bash -c 'id -nG timur | tr " " "\n" | grep -qx reports'
  check "/srv/reports: группа reports, права 770"    bash -c '[ "$(stat -c "%G %a" /srv/reports)" = "reports 770" ]'
  check "aliya может прочитать ld-summary.txt"       as aliya 'cat /var/tmp/ld-summary.txt'
  check "файл /etc/sudoers.d/timur без ошибок"       visudo -cf /etc/sudoers.d/timur
  check "timur: journalctl через sudo без пароля"    bash -c 'sudo -l -U timur | grep -E "NOPASSWD:.*/usr/bin/journalctl"'
  summary
}

# ====================================================================
# task_3 · занятие 3 · пакеты: apt и dpkg
# ====================================================================
task_3_text() { cat <<'T'
Задание 3 (5 мин) · пакеты (нужен интернет)
  1. Установите пакет tree.                                            apt update, apt install
  2. В файл /root/task3-answer.txt запишите две строки:
       строка 1 — установленная версия tree;                           dpkg -l tree / apt show tree
       строка 2 — имя пакета, которому принадлежит /usr/bin/passwd.    dpkg -S
  3. Запретите обновление tree (hold).                                 apt-mark hold, apt-mark showhold
T
}
task_3_cleanup() {
  apt-mark unhold tree >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq tree >/dev/null 2>&1; rm -f /root/task3-answer.txt; true
}
task_3_setup() { task_3_cleanup; }
task_3_check() {
  check "пакет tree установлен"                       bash -c 'dpkg-query -W -f="\${Status}" tree | grep -q "ok installed$"'
  check "строка 1 ответа: версия tree"                bash -c 'a=$(sed -n 1p /root/task3-answer.txt | tr -d "[:space:]"); [ -n "$a" ] && [ "$a" = "$(dpkg-query -W -f="\${Version}" tree)" ]'
  check "строка 2 ответа: владелец /usr/bin/passwd"   bash -c '[ "$(sed -n 2p /root/task3-answer.txt | tr -d "[:space:]")" = "$(dpkg -S /usr/bin/passwd | cut -d: -f1)" ]'
  check "tree поставлен на hold"                      bash -c 'apt-mark showhold | grep -qx tree'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_1.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_1.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_1.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
