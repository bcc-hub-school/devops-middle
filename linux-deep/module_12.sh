#!/bin/bash
# Linux Deep · Модуль 12 «Logging & Performance Deep Dive» · задания к занятиям 29–30 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_12.sh
#
#   bash module_12.sh list                  какие задания есть
#   sudo bash module_12.sh setup task_29    подготовить стенд и показать задание
#   sudo bash module_12.sh check task_29    проверить
#   sudo bash module_12.sh reset task_29    начать заново (стенд пересоздаётся)
#   sudo bash module_12.sh clean task_29    убрать стенд после занятия
#   bash module_12.sh task  task_29     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_29 task_30"

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
# task_29 · занятие 29 · корреляция логов и метрик
# ====================================================================
task_29_text() { cat <<'T'
Задание 29 (5–10 мин) · корреляция логов и метрик
Стенд пишет /var/log/monitoring/incident.csv (метрики раз в секунду) и отправляет в
журнал сообщения о задаче с тегом ld-batch — ровно в секунды пика load1.
  1. Найдите в CSV секунду пика load1 (порог заметно выше нормы, например 3.0).
                                                   awk -F, 'NR>1 && $2>3.0 {print}' /var/log/monitoring/incident.csv
                                                   sort -t, -k2 -rn /var/log/monitoring/incident.csv | head -1
  2. Переведите время пика в окно journalctl --since/--until с запасом ±10 секунд.
                                                   date -d "$T -10 seconds" '+%Y-%m-%d %H:%M:%S'
  3. Найдите в журнале этого окна запись задачи с тегом ld-batch и её имя (job=...).
                                                   journalctl -t ld-batch --since ... --until ... -o short-iso
  4. Запишите в /root/task29-answer.txt две строки: имя задачи и время пика в формате CSV.
                                                   { echo "job=..."; echo "$T"; } | sudo tee /root/task29-answer.txt
T
}
task_29_cleanup() {
  rm -rf /opt/ld-tasks/task29 /var/log/monitoring/incident.csv /root/task29-answer.txt; true
}
task_29_setup() {
  task_29_cleanup; install -d -m 755 /opt/ld-tasks/task29 /var/log/monitoring
  local jobs=(reindex cleanup export rebuild) job peak_time csv t i load iowait mem disk
  job="${jobs[$((RANDOM % 4))]}-$(( (RANDOM % 90) + 10 ))"
  echo "job=$job" > /opt/ld-tasks/task29/job
  csv=/var/log/monitoring/incident.csv
  echo "time,load1,mem_avail_mb,io_wait,disk_used_pct" > "$csv"
  for i in $(seq 1 24); do
    t=$(date -Iseconds)
    case "$i" in
      10) load=5.30; iowait=18.4 ;;
      11) load=6.10; iowait=19.1 ;;
      12) load=5.60; iowait=17.8 ;;
      *)  load=$(printf '0.%02d' $(( (RANDOM % 30) + 30 ))); iowait=$(printf '0.%d' $((RANDOM % 5))) ;;
    esac
    mem=$(( 890 + RANDOM % 40 )); disk=$(( 61 + RANDOM % 2 ))
    echo "$t,$load,$mem,$iowait,$disk" >> "$csv"
    [ "$i" -eq 10 ] && logger -t ld-batch "job=$job start"
    [ "$i" -eq 11 ] && peak_time="$t"
    [ "$i" -eq 12 ] && logger -t ld-batch "job=$job done"
    sleep 1
  done
  echo "$peak_time" > /opt/ld-tasks/task29/peak_time
}
task_29_check() {
  check "CSV с историей метрик создан"                     test -s /var/log/monitoring/incident.csv
  check "в CSV есть строка с пиковым load1 (> 3.0)"         bash -c "awk -F, 'NR>1 && \$2>3.0' /var/log/monitoring/incident.csv | grep -q ."
  check "в /root/task29-answer.txt верное имя задачи"       bash -c '[ "$(sed -n 1p /root/task29-answer.txt | tr -d "[:space:]")" = "$(cat /opt/ld-tasks/task29/job)" ]'
  check "в /root/task29-answer.txt верное время пика"       bash -c '[ "$(sed -n 2p /root/task29-answer.txt | tr -d "[:space:]")" = "$(cat /opt/ld-tasks/task29/peak_time)" ]'
  check "в журнале есть запись job=... с тегом ld-batch"    bash -c 'journalctl -t ld-batch -o cat --no-pager | grep -qF "$(cat /opt/ld-tasks/task29/job)"'
  summary
}

# ====================================================================
# task_30 · занятие 30 · методика поиска узкого места (load average)
# ====================================================================
task_30_text() { cat <<'T'
Задание 30 (5–10 мин) · методика поиска узкого места
На машине запущен один процесс ld-worker. Имя нейтральное — по нему не видно,
во что он упирается: CPU, память или диск. Определите тип методикой из занятия.
  1. Проверьте, есть ли очередь вообще.                          uptime; nproc
  2. По vmstat определите ветку: r>nproc — CPU; b>0 и wa высокий —
     I/O; si/so не нули или available мал — память.               vmstat 1 3; free -h
  3. Спуститесь до процесса: кто ест CPU, у кого большой RSS.      top -b -n1 -o %CPU | head
                                                                    ps -eo pid,stat,%cpu,rss,comm --sort=-rss | head
  4. Если похоже на диск — подтвердите двумя замерами /proc/PID/io.
                                                                    sudo cat /proc/PID/io; sleep 1; sudo cat /proc/PID/io
  5. Запишите в /root/task30-answer.txt тип (cpu|memory|io) и PID
     двумя строками, затем завершите процесс.                     kill PID
T
}
task_30_cleanup() {
  local p; for p in $(pgrep -x ld-worker 2>/dev/null); do kill -KILL "$p" 2>/dev/null; done
  rm -rf /opt/ld-tasks/task30 /var/tmp/ld-worker-io.dat /root/task30-answer.txt; true
}
task_30_setup() {
  task_30_cleanup; need_pkg python3
  install -d -m 755 /opt/ld-tasks/task30
  ln -sf "$(command -v python3)" /opt/ld-tasks/task30/ld-worker
  local kinds=(cpu memory io) kind
  kind="${kinds[$((RANDOM % 3))]}"
  [ -f /opt/ld-tasks/.task30-kind ] && kind=$(cat /opt/ld-tasks/.task30-kind)   # фиксированный вариант (для записи роликов)
  case "$kind" in
    cpu)
      cat > /opt/ld-tasks/task30/prog.py <<'PY'
while True:
    pass
PY
      ;;
    memory)
      cat > /opt/ld-tasks/task30/prog.py <<'PY'
import time
buf = bytearray(300 * 1024 * 1024)     # держим ~300 МБ реальной памяти
for i in range(0, len(buf), 4096):
    buf[i] = 1                          # трогаем каждую страницу, иначе RSS не вырастет
while True:
    time.sleep(3600)
PY
      ;;
    io)
      cat > /opt/ld-tasks/task30/prog.py <<'PY'
import os, mmap, time
path = "/var/tmp/ld-worker-io.dat"
size = 1024 * 1024
buf = mmap.mmap(-1, size)               # странично-выровненный буфер для O_DIRECT
buf.write(b"0" * size)
flags = os.O_WRONLY | os.O_CREAT | os.O_DIRECT | os.O_SYNC
try:
    fd = os.open(path, flags, 0o600)
except OSError:                          # O_DIRECT не поддержан файловой системой — не критично для задания
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_SYNC, 0o600)
while True:
    try:
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, buf)
    except OSError:
        time.sleep(0.2)
PY
      ;;
  esac
  echo "$kind" > /opt/ld-tasks/task30/kind
  setsid /opt/ld-tasks/task30/ld-worker /opt/ld-tasks/task30/prog.py >/dev/null 2>&1 </dev/null &
  echo $! > /opt/ld-tasks/task30/worker.pid
  sleep 1
}
task_30_check() {
  check "стенд подготовлен: тип узкого места записан"      test -s /opt/ld-tasks/task30/kind
  check "файл ответа создан"                                test -s /root/task30-answer.txt
  check "в /root/task30-answer.txt верный тип узкого места" bash -c '[ "$(sed -n 1p /root/task30-answer.txt | tr -d "[:space:]")" = "$(cat /opt/ld-tasks/task30/kind)" ]'
  check "в /root/task30-answer.txt верный PID"               bash -c '[ "$(sed -n 2p /root/task30-answer.txt | tr -d "[:space:]")" = "$(cat /opt/ld-tasks/task30/worker.pid)" ]'
  check "процесс ld-worker завершён"                        bash -c "$(declare -f alive); ! alive ld-worker"
  check "PID из файла ответа больше не существует"          bash -c 'p=$(cat /opt/ld-tasks/task30/worker.pid 2>/dev/null); [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_12.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_12.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_12.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
