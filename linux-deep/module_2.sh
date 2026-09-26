#!/bin/bash
# Linux Deep · Модуль 2 «Process & System Control» · задания к занятиям 4–6 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_2.sh
#
#   bash module_2.sh list                  какие задания есть
#   sudo bash module_2.sh setup task_4    подготовить стенд и показать задание
#   sudo bash module_2.sh check task_4    проверить
#   sudo bash module_2.sh reset task_4    начать заново (стенд пересоздаётся)
#   sudo bash module_2.sh clean task_4    убрать стенд после занятия
#   bash module_2.sh task  task_4     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_4 task_5 task_6"

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
# task_4 · занятие 4 · процессы и сигналы
# ====================================================================
task_4_text() { cat <<'T'
Задание 4 (5–10 мин) · процессы и сигналы
На машине работают два процесса: ld-worker и ld-stubborn.
  1. Найдите PID процесса ld-worker и запишите его в /root/task4-answer.txt.     pgrep, ps -ef
  2. Завершите ld-worker обычным сигналом TERM.                                  kill PID
  3. ld-stubborn сигнал TERM игнорирует: убедитесь в этом (grep SigIgn /proc/PID/status, kill PID —
     процесс жив), затем завершите его сигналом, который нельзя игнорировать.    kill -KILL PID
  4. Запустите в фоне команду sleep 600 с пониженным приоритетом (nice 10).       nice -n 10 sleep 600 &
     Проверьте себя: ps -o pid,ni,stat,cmd -C sleep
T
}
task_4_cleanup() {
  local p; for p in $(ps -eo pid=,comm= | awk '$2=="ld-worker"||$2=="ld-stubborn"{print $1}'); do kill -KILL "$p" 2>/dev/null; done
  for p in $(ps -eo pid=,ni=,args= | awk '$2==10 && $3=="sleep" && $4=="600"{print $1}'); do kill -KILL "$p" 2>/dev/null; done
  rm -rf /opt/ld-tasks/task4 /root/task4-answer.txt; true
}
task_4_setup() {
  task_4_cleanup; install -d -m 755 /opt/ld-tasks/task4
  printf '#!/bin/bash\nwhile :; do sleep 1; done\n'              > /opt/ld-tasks/task4/ld-worker
  printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 1; done\n' > /opt/ld-tasks/task4/ld-stubborn
  chmod 755 /opt/ld-tasks/task4/ld-worker /opt/ld-tasks/task4/ld-stubborn
  setsid /opt/ld-tasks/task4/ld-worker   >/dev/null 2>&1 </dev/null &
  echo $! > /opt/ld-tasks/task4/worker.pid
  setsid /opt/ld-tasks/task4/ld-stubborn >/dev/null 2>&1 </dev/null &
  sleep 1
}
task_4_check() {
  check "в /root/task4-answer.txt записан PID ld-worker"   bash -c '[ "$(tr -d "[:space:]" < /root/task4-answer.txt)" = "$(cat /opt/ld-tasks/task4/worker.pid)" ]'
  check "ld-worker завершён"                               bash -c "$(declare -f alive); ! alive ld-worker"
  check "ld-stubborn завершён"                             bash -c "$(declare -f alive); ! alive ld-stubborn"
  check "sleep 600 работает с nice 10"                     bash -c 'ps -eo ni=,stat=,args= | awk "\$1==10 && \$2 !~ /^Z/ && \$3==\"sleep\" && \$4==\"600\"{f=1} END{exit !f}"'
  summary
}

# ====================================================================
# task_5 · занятие 5 · systemd: юниты
# ====================================================================
task_5_text() { cat <<'T'
Задание 5 (10 мин) · systemd
  1. Программа /usr/local/bin/ld-hello-svc уже лежит на месте. Создайте для неё юнит
     /etc/systemd/system/ld-hello.service:
         [Unit]
         Description=LD hello service
         [Service]
         ExecStart=/usr/local/bin/ld-hello-svc
         [Install]
         WantedBy=multi-user.target
  2. Перечитайте конфигурацию, запустите сервис и включите автозапуск.
                                     systemctl daemon-reload, systemctl enable --now ld-hello, systemctl status ld-hello
  3. Сервис ld-broken не запускается. Найдите причину и почините юнит (сама программа исправна).
                                     systemctl status ld-broken, journalctl -u ld-broken -n 5,
                                     systemctl cat ld-broken, ls /usr/local/bin/ | grep ld-,
                                     правка /etc/systemd/system/ld-broken.service, daemon-reload, start
T
}
task_5_cleanup() { unit_rm ld-hello.service ld-broken.service; rm -f /usr/local/bin/ld-hello-svc /usr/local/bin/ld-broken-svc; }
task_5_setup() {
  task_5_cleanup
  printf '#!/bin/bash\nwhile :; do echo "ld-hello: работаю"; sleep 30; done\n'  > /usr/local/bin/ld-hello-svc
  printf '#!/bin/bash\nwhile :; do echo "ld-broken: работаю"; sleep 30; done\n' > /usr/local/bin/ld-broken-svc
  chmod 755 /usr/local/bin/ld-hello-svc /usr/local/bin/ld-broken-svc
  cat > /etc/systemd/system/ld-broken.service <<'U'
[Unit]
Description=LD broken service (task 5)
[Service]
ExecStart=/usr/local/bin/ld-brokn-svc
[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload; systemctl start ld-broken.service >/dev/null 2>&1; true
}
task_5_check() {
  check "юнит ld-hello.service создан"                  test -f /etc/systemd/system/ld-hello.service
  check "ld-hello запущен (active)"                     systemctl is-active ld-hello.service
  check "ld-hello включён в автозапуск (enabled)"       systemctl is-enabled ld-hello.service
  check "ld-broken запущен (active)"                    systemctl is-active ld-broken.service
  check "ld-broken запускает /usr/local/bin/ld-broken-svc" bash -c 'systemctl show ld-broken.service -p ExecStart | grep -q "path=/usr/local/bin/ld-broken-svc "'
  summary
}

# ====================================================================
# task_6 · занятие 6 · cron и systemd timers
# ====================================================================
task_6_text() { cat <<'T'
Задание 6 (10 мин) · cron и timers. Скрипт /usr/local/bin/ld-report дописывает строку в /var/tmp/ld-report.log.
  1. cron: в crontab своего пользователя добавьте запуск /usr/local/bin/ld-report каждый день в 02:30.
                                                          crontab -e, crontab -l      строка: 30 2 * * * команда
  2. timer: создайте два юнита в /etc/systemd/system/:
       ld-report.service            ld-report.timer
         [Service]                    [Timer]
         Type=oneshot                 OnCalendar=*:0/5
         ExecStart=/usr/local/bin/ld-report      Persistent=true
                                      [Install]
                                      WantedBy=timers.target
     OnCalendar=*:0/5 — «каждые 5 минут»; проверить выражение: systemd-analyze calendar "*:0/5"
  3. Включите и запустите таймер (не сервис).             systemctl daemon-reload, systemctl enable --now ld-report.timer
  4. Посмотрите, когда следующий запуск, и выполните задачу один раз вручную.
                                                          systemctl list-timers ld-report.timer, systemctl start ld-report.service
T
}
task_6_user() { echo "${SUDO_USER:-root}"; }
task_6_cleanup() {
  unit_rm ld-report.timer ld-report.service
  local u; u=$(task_6_user); crontab -l -u "$u" 2>/dev/null | grep -v '/usr/local/bin/ld-report' | crontab -u "$u" - 2>/dev/null
  rm -f /usr/local/bin/ld-report /var/tmp/ld-report.log; true
}
task_6_setup() {
  need_pkg cron; task_6_cleanup
  printf '#!/bin/bash\necho "$(date "+%%F %%T") report" >> /var/tmp/ld-report.log\n' > /usr/local/bin/ld-report
  chmod 755 /usr/local/bin/ld-report
}
task_6_check() {
  local u; u=$(task_6_user)
  check "crontab пользователя $u: ld-report каждый день в 02:30" bash -c "crontab -l -u $u | grep -Eq '^[[:space:]]*30[[:space:]]+0?2[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+/usr/local/bin/ld-report'"
  check "ld-report.service: Type=oneshot"               bash -c 'systemctl show ld-report.service -p Type | grep -qx Type=oneshot'
  check "ld-report.timer включён (enabled)"             systemctl is-enabled ld-report.timer
  check "ld-report.timer запущен (active)"              systemctl is-active ld-report.timer
  check "расписание таймера — каждые 5 минут"            bash -c 'systemctl show ld-report.timer -p TimersCalendar | grep -q "\*:00/5:00"'
  check "задача выполнялась: в /var/tmp/ld-report.log есть строка" test -s /var/tmp/ld-report.log
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_2.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_2.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_2.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
