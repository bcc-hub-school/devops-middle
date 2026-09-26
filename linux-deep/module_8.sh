#!/bin/bash
# Linux Deep · Модуль 8 «Bash for DevOps Automation» · задания к занятиям 20–21 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_8.sh
#
#   bash module_8.sh list                  какие задания есть
#   sudo bash module_8.sh setup task_20    подготовить стенд и показать задание
#   sudo bash module_8.sh check task_20    проверить
#   sudo bash module_8.sh reset task_20    начать заново (стенд пересоздаётся)
#   sudo bash module_8.sh clean task_20    убрать стенд после занятия
#   bash module_8.sh task  task_20     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_20 task_21"

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
# task_20 · занятие 20 · bash: основы скриптов, условия и циклы
# ====================================================================
task_20_text() { cat <<'T'
Задание 20 (5–10 мин) · bash: скрипт проверки юнитов
Напишите /usr/local/bin/ld-check-svc.sh — проверяет статус systemd-юнитов.
  1. Shebang bash и право на выполнение.                                   #!/bin/bash · chmod +x
  2. Без аргументов — usage-сообщение в stderr и выход с кодом 2.          if [ "$#" -eq 0 ]; then … >&2; exit 2; fi
  3. Для каждого имени юнита из аргументов напечатать "имя: active" или    for u in "$@"; do
     "имя: inactive" (по systemctl is-active).                              systemctl is-active --quiet "$u"
  4. В конце вернуть 0, если все юниты активны, иначе 1.                   накопить флаг в цикле; exit "$флаг"
T
}
task_20_cleanup() {
  rm -f /usr/local/bin/ld-check-svc.sh
  rm -rf /opt/ld-tasks/task20
  true
}
task_20_setup() {
  task_20_cleanup
  need_pkg cron
  systemctl enable --now cron  >/dev/null 2>&1
  systemctl enable --now ssh   >/dev/null 2>&1
  install -d -m 755 /opt/ld-tasks/task20
}
task_20_check() {
  check "/usr/local/bin/ld-check-svc.sh существует и исполняем" test -x /usr/local/bin/ld-check-svc.sh
  check "shebang — bash"                                        bash -c 'head -1 /usr/local/bin/ld-check-svc.sh | grep -Eq "^#!.*bash"'
  check "два активных юнита: строки active и код 0"              bash -c 'out=$(/usr/local/bin/ld-check-svc.sh cron ssh 2>/dev/null); c=$?; echo "$out" | grep -qx "cron: active" && echo "$out" | grep -qx "ssh: active" && [ "$c" -eq 0 ]'
  check "несуществующий юнит: inactive и код 1"                  bash -c 'out=$(/usr/local/bin/ld-check-svc.sh ld-no-such-unit 2>/dev/null); c=$?; echo "$out" | grep -qx "ld-no-such-unit: inactive" && [ "$c" -eq 1 ]'
  check "без аргументов: usage в stderr и код 2"                 bash -c '/usr/local/bin/ld-check-svc.sh >/tmp/task20-out 2>/tmp/task20-err; c=$?; r=1; [ -s /tmp/task20-err ] && [ ! -s /tmp/task20-out ] && [ "$c" -eq 2 ] && r=0; rm -f /tmp/task20-out /tmp/task20-err; exit $r'
  summary
}

# ====================================================================
# task_21 · занятие 21 · обработка ошибок и автоматизация (set -euo pipefail, trap)
# ====================================================================
task_21_text() { cat <<'T'
Задание 21 (5–10 мин) · обработка ошибок и автоматизация
Каталог с данными уже лежит в /opt/ld-tasks/task21/data. Напишите /usr/local/bin/ld-backup.sh —
скрипт бэкапа каталога, переданного первым аргументом.
  1. Первая строка после шебанга — set -euo pipefail.                      set -euo pipefail
  2. Если каталога-аргумента не существует — сообщение в stderr и exit 2.   [ -d "$1" ] || { echo … >&2; exit 2; }
  3. Временный файл — mktemp /tmp/ld-backup.XXXXXX, уборка — trap … EXIT.   tmp=$(mktemp /tmp/ld-backup.XXXXXX); trap 'rm -f "$tmp"' EXIT
  4. Архив — /var/backups/ld/<имя каталога>-<дата-время>.tar.gz.            tar czf "$tmp" -C "$(dirname "$1")" "$(basename "$1")"; mv "$tmp" …
  5. Не больше 3 архивов одного каталога — старые удалите.                 ls -t …-*.tar.gz | tail -n +4 | xargs -r rm -f --
     Запустите скрипт 3 раза с паузой (sudo bash ld-backup.sh /opt/ld-tasks/task21/data; sleep 2 — и ещё раз) и проверьте.
T
}
task_21_cleanup() {
  rm -f /usr/local/bin/ld-backup.sh
  rm -rf /opt/ld-tasks/task21 /var/backups/ld
  rm -f /tmp/ld-backup.*
  true
}
task_21_setup() {
  task_21_cleanup
  install -d -m 755 /opt/ld-tasks/task21/data
  printf 'ld task 21: sample file one\n' > /opt/ld-tasks/task21/data/readme.txt
  printf 'ld task 21: sample file two\n' > /opt/ld-tasks/task21/data/notes.txt
  install -d -m 755 /var/backups/ld
}
task_21_check() {
  check "скрипт /usr/local/bin/ld-backup.sh существует и исполняем" test -x /usr/local/bin/ld-backup.sh
  check "в скрипте есть set -euo pipefail"                          grep -Eq 'set +-euo pipefail' /usr/local/bin/ld-backup.sh
  check "в скрипте есть trap"                                       grep -q 'trap' /usr/local/bin/ld-backup.sh
  check "3 запуска подряд дают 1..3 валидных архива" bash -c '
    for i in 1 2 3; do
      /usr/local/bin/ld-backup.sh /opt/ld-tasks/task21/data >/dev/null || exit 1
      sleep 1.5
    done
    n=$(ls /var/backups/ld/data-*.tar.gz 2>/dev/null | wc -l)
    [ "$n" -ge 1 ] && [ "$n" -le 3 ] || exit 1
    for f in /var/backups/ld/data-*.tar.gz; do tar -tzf "$f" >/dev/null 2>&1 || exit 1; done
  '
  check "ротация: после ещё 2 запусков архивов не больше 3" bash -c '
    for i in 1 2; do
      /usr/local/bin/ld-backup.sh /opt/ld-tasks/task21/data >/dev/null || exit 1
      sleep 1.5
    done
    n=$(ls /var/backups/ld/data-*.tar.gz 2>/dev/null | wc -l)
    [ "$n" -le 3 ]
  '
  check "несуществующий каталог: код 2 и ничего не создано" bash -c '
    before=$(ls /var/backups/ld/data-*.tar.gz 2>/dev/null | wc -l)
    /usr/local/bin/ld-backup.sh /opt/ld-tasks/task21/no-such-dir >/dev/null 2>&1
    rc=$?
    after=$(ls /var/backups/ld/data-*.tar.gz 2>/dev/null | wc -l)
    [ "$rc" -eq 2 ] && [ "$before" -eq "$after" ]
  '
  check "во /tmp не осталось временных файлов скрипта" bash -c '! ls /tmp/ld-backup.* >/dev/null 2>&1'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_8.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_8.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_8.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
