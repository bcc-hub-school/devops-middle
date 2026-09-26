#!/bin/bash
# Linux Deep · Модуль 3 «Logging & Observability Basics» · задания к занятиям 7–8 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_3.sh
#
#   bash module_3.sh list                  какие задания есть
#   sudo bash module_3.sh setup task_7    подготовить стенд и показать задание
#   sudo bash module_3.sh check task_7    проверить
#   sudo bash module_3.sh reset task_7    начать заново (стенд пересоздаётся)
#   sudo bash module_3.sh clean task_7    убрать стенд после занятия
#   bash module_3.sh task  task_7     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_7 task_8"

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
# task_7 · занятие 7 · journald и анализ журналов
# ====================================================================
task_7_text() { cat <<'T'
Задание 7 (5–10 мин) · journald
  1. Отправьте в журнал своё сообщение с тегом student.        logger -t student "привет, журнал"
     Найдите его:                                              journalctl -t student -n 1
  2. Сервис ld-notes пишет в журнал. Среди его сообщений есть ошибка (приоритет err) с кодом вида E-1234.
     Найдите самую свежую и запишите её код в /root/task7-answer.txt.    journalctl -u ld-notes -p err -n 1
  3. Ограничьте размер журнала: создайте /etc/systemd/journald.conf.d/size.conf
         [Journal]
         SystemMaxUse=200M
     и перезапустите journald.                                 systemctl restart systemd-journald, journalctl --disk-usage
T
}
task_7_cleanup() {
  unit_rm ld-notes.service
  rm -f /usr/local/bin/ld-notes /etc/systemd/journald.conf.d/size.conf /root/task7-answer.txt; rm -rf /opt/ld-tasks/task7; true
}
task_7_setup() {
  task_7_cleanup; install -d -m 700 /opt/ld-tasks/task7
  local code="E-$(( (RANDOM % 9000) + 1000 ))"; echo "$code" > /opt/ld-tasks/task7/code; date +%s > /opt/ld-tasks/task7/since
  cat > /usr/local/bin/ld-notes <<S
#!/bin/bash
echo "ld-notes: запуск"
echo "<6>ld-notes: загружено 12 заметок"
echo "<4>ld-notes: медленный ответ диска"
echo "<3>ld-notes: не удалось сохранить заметку, код $code"
echo "<6>ld-notes: повторная попытка успешна"
while :; do sleep 60; echo "<6>ld-notes: работаю"; done
S
  chmod 755 /usr/local/bin/ld-notes
  printf '[Unit]\nDescription=LD notes (task 7)\n[Service]\nExecStart=/usr/local/bin/ld-notes\n' > /etc/systemd/system/ld-notes.service
  systemctl daemon-reload; systemctl start ld-notes.service; sleep 1
}
task_7_check() {
  check "в журнале есть ваше сообщение с тегом student"   bash -c 'journalctl -t student --since "@$(cat /opt/ld-tasks/task7/since)" -o cat --no-pager | grep -q .'
  check "в /root/task7-answer.txt верный код ошибки"      bash -c '[ "$(tr -d "[:space:]" < /root/task7-answer.txt)" = "$(cat /opt/ld-tasks/task7/code)" ]'
  check "drop-in /etc/systemd/journald.conf.d/size.conf"   test -f /etc/systemd/journald.conf.d/size.conf
  check "действует SystemMaxUse=200M"                      bash -c 'systemd-analyze cat-config systemd/journald.conf | grep -Eq "^SystemMaxUse=200M[[:space:]]*$"'
  check "journald работает после перезапуска"              systemctl is-active systemd-journald
  summary
}

# ====================================================================
# task_8 · занятие 8 · logrotate
# ====================================================================
task_8_text() { cat <<'T'
Задание 8 (5–10 мин) · logrotate
Приложение пишет в /var/log/ld-app/app.log, ротации у него нет.
  1. Создайте /etc/logrotate.d/ld-app:
         /var/log/ld-app/*.log {
             daily
             rotate 3
             compress
             missingok
             notifempty
         }
  2. Проверьте конфигурацию «всухую» — ничего не меняя.       logrotate -d /etc/logrotate.d/ld-app
  3. Выполните ротацию принудительно и посмотрите результат.  logrotate -f /etc/logrotate.d/ld-app, ls -l /var/log/ld-app/
  4. Когда logrotate запускается сам?                         systemctl list-timers logrotate.timer
T
}
task_8_cleanup() { rm -rf /var/log/ld-app /etc/logrotate.d/ld-app; [ -f /var/lib/logrotate/status ] && sed -i '\|/var/log/ld-app/|d' /var/lib/logrotate/status; true; }
task_8_setup() {
  need_pkg logrotate; task_8_cleanup; install -d -m 755 /var/log/ld-app
  local i; for i in $(seq 1 200); do echo "$(date '+%F %T') ld-app: запрос $i обработан"; done > /var/log/ld-app/app.log
}
task_8_check() {
  check "конфигурация /etc/logrotate.d/ld-app создана"     test -f /etc/logrotate.d/ld-app
  check "logrotate -d проходит без ошибок"                 bash -c 'out=$(logrotate -d /etc/logrotate.d/ld-app 2>&1) && ! grep -qi "error" <<<"$out"'
  check "в конфигурации: rotate 3 и compress"              bash -c 'grep -Eq "^[[:space:]]*rotate[[:space:]]+3[[:space:]]*$" /etc/logrotate.d/ld-app && grep -Eq "^[[:space:]]*compress[[:space:]]*$" /etc/logrotate.d/ld-app'
  check "ротация выполнена: есть app.log.1.gz"             bash -c 'ls /var/log/ld-app/app.log.1.gz /var/log/ld-app/app.log.1 2>/dev/null | grep -q .'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_3.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_3.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_3.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
