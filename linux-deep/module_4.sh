#!/bin/bash
# Linux Deep · Модуль 4 «Performance & Resource Monitoring» · задания к занятиям 9–11 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_4.sh
#
#   bash module_4.sh list                  какие задания есть
#   sudo bash module_4.sh setup task_9    подготовить стенд и показать задание
#   sudo bash module_4.sh check task_9    проверить
#   sudo bash module_4.sh reset task_9    начать заново (стенд пересоздаётся)
#   sudo bash module_4.sh clean task_9    убрать стенд после занятия
#   bash module_4.sh task  task_9     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_9 task_10 task_11"

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
# task_9 · занятие 9 · мониторинг ресурсов: top, iostat, /proc/PID
# ====================================================================
task_9_text() { cat <<'T'
Задание 9 (5–10 мин) · мониторинг ресурсов: top, iostat, /proc/PID
На машине фоном работают два процесса стенда: один грузит CPU, другой пишет на диск.
  1. Найдите процесс, который грузит CPU, и запишите его PID в /root/task9-cpu.txt.
                                                          top (сортировка P) или top -b -n1 | head -12
  2. Найдите процесс, который пишет на диск, и запишите его PID в /root/task9-disk.txt.
                                                          iostat -xz 1 2 — диск занят; кто именно:
                                                          sudo grep -H ^write_bytes /proc/[0-9]*/io | sort -t: -k3n | tail -3
  3. Узнайте, в какой файл он пишет, и запишите полный путь в /root/task9-file.txt.
                                                          sudo ls -l /proc/PID/fd
  4. Понизьте приоритет CPU-процесса до nice 19 (не завершайте его).
                                                          sudo renice -n 19 -p PID · проверка: ps -o pid,ni,stat,comm -p PID
T
}
task_9_cleanup() {
  local p; for p in $(ps -eo pid=,comm= | awk '$2=="ld-indexer"||$2=="ld-backup"{print $1}'); do kill -KILL "$p" 2>/dev/null; done
  rm -rf /opt/ld-tasks/task9 /root/task9-cpu.txt /root/task9-disk.txt /root/task9-file.txt; true
}
task_9_setup() {
  task_9_cleanup; need_pkg sysstat; install -d -m 755 /opt/ld-tasks/task9
  printf '#!/bin/bash\nwhile :; do :; done\n' > /opt/ld-tasks/task9/ld-indexer
  cat > /opt/ld-tasks/task9/ld-backup <<'S'
#!/bin/bash
F=/opt/ld-tasks/task9/backup.bin
printf -v buf '%*s' 1048576 ''
exec 3>>"$F"
while :; do
  : > "$F"
  for _ in 1 2 3 4 5 6 7 8; do echo -n "$buf" >&3; done
  sync "$F"; sleep 0.2
done
S
  chmod 755 /opt/ld-tasks/task9/ld-indexer /opt/ld-tasks/task9/ld-backup
  setsid /opt/ld-tasks/task9/ld-indexer >/dev/null 2>&1 </dev/null &
  echo $! > /opt/ld-tasks/task9/indexer.pid
  setsid /opt/ld-tasks/task9/ld-backup  >/dev/null 2>&1 </dev/null &
  echo $! > /opt/ld-tasks/task9/backup.pid
  sleep 2
}
task_9_check() {
  check "в /root/task9-cpu.txt — PID процесса, который грузит CPU (ld-indexer)"  bash -c '[ "$(tr -d "[:space:]" < /root/task9-cpu.txt)" = "$(cat /opt/ld-tasks/task9/indexer.pid)" ]'
  check "в /root/task9-disk.txt — PID процесса, который пишет на диск (ld-backup)" bash -c '[ "$(tr -d "[:space:]" < /root/task9-disk.txt)" = "$(cat /opt/ld-tasks/task9/backup.pid)" ]'
  check "в /root/task9-file.txt — путь /opt/ld-tasks/task9/backup.bin"           grep -q '/opt/ld-tasks/task9/backup.bin' /root/task9-file.txt
  check "ld-indexer работает (не завершён)"                                       bash -c "$(declare -f alive); alive ld-indexer"
  check "у ld-indexer nice = 19"                                                  bash -c '[ "$(ps -o ni= -p "$(cat /opt/ld-tasks/task9/indexer.pid)" | tr -d " ")" = 19 ]'
  check "ld-backup работает (задание — наблюдать, не убивать)"                    bash -c "$(declare -f alive); alive ld-backup"
  summary
}

# ====================================================================
# task_10 · занятие 10 · узкие места и load average
# ====================================================================
task_10_text() { cat <<'T'
Задание 10 (5–10 мин) · узкие места и load average
На машине работают три процесса: ld-svc-a, ld-svc-b, ld-svc-c. Один грузит CPU, второй держит
память, третий пишет на диск. Ничего не убивайте и не останавливайте — это задача диагностики.
  1. Посмотрите load average и число CPU. Запишите строку nproc=<число>     uptime, nproc, cat /proc/loadavg
     в /root/task10-answer.txt.
  2. Кто из трёх грузит CPU? Допишите строку cpu=<имя процесса>.             top -b -n1 | head -12,
                                                                             ps -eo pid,stat,%cpu,comm --sort=-%cpu | head
  3. Кто держит память? Допишите строку mem=<имя процесса>.                  free -h, ps -eo pid,rss,comm --sort=-rss | head
  4. Кто пишет на диск? Допишите строку io=<имя процесса>.                   vmstat 1 3, ps -eo pid,stat,comm | grep ld-svc,
                                                                             sudo cat /proc/PID/io
     Проверьте себя: cat /root/task10-answer.txt — четыре строки: nproc=, cpu=, mem=, io=
T
}
task_10_cleanup() {
  local p; for p in $(ps -eo pid=,comm= | awk '$2 ~ /^ld-svc-[abc]$/ {print $1}'); do kill -KILL "$p" 2>/dev/null; done
  rm -rf /opt/ld-tasks/task10 /root/task10-answer.txt; true
}
task_10_setup() {
  need_pkg python3 procps sysstat; task_10_cleanup; install -d -m 700 /opt/ld-tasks/task10
  local d=/opt/ld-tasks/task10 n
  # a — писатель на диск: синхронные записи мимо кэша в один и тот же файл (процесс почти всегда в D)
  cat > "$d/svc-a.py" <<'P'
import os, mmap
p = "/opt/ld-tasks/task10/data"
try:
    f = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_DIRECT | os.O_SYNC, 0o600)
except OSError:
    f = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_SYNC, 0o600)
b = mmap.mmap(-1, 65536)
b.write(b"x" * 65536)
while True:
    for _ in range(64):
        os.write(f, b)
    os.lseek(f, 0, 0)
P
  # b — CPU-хог: пустой цикл на одном ядре
  printf 'while True:\n    pass\n' > "$d/svc-b.py"
  # c — «пожиратель памяти»: держит ~300 МБ (ВМ 2 ГБ — этого достаточно, чтобы увидеть по RSS и available)
  printf 'import time\nb = b"x" * (300 * 1024 * 1024)\nwhile True:\n    time.sleep(60)\n' > "$d/svc-c.py"
  # имя процесса (comm) берётся из имени файла, который запускают: символические ссылки на python3
  for n in a b c; do
    ln -s /usr/bin/python3 "$d/ld-svc-$n"
    setsid "$d/ld-svc-$n" "$d/svc-$n.py" >/dev/null 2>&1 </dev/null &
  done
  sleep 2
}
task_10_check() {
  local f=/root/task10-answer.txt
  check "в $f записано nproc=$(nproc)"                  bash -c "grep -Eiq '^[[:space:]]*nproc[[:space:]]*=[[:space:]]*$(nproc)[[:space:]]*$' $f"
  check "cpu= — процесс, который грузит CPU"            bash -c "grep -Eiq '^[[:space:]]*cpu[[:space:]]*=[[:space:]]*ld-svc-b[[:space:]]*$' $f"
  check "mem= — процесс, который держит память"         bash -c "grep -Eiq '^[[:space:]]*mem[[:space:]]*=[[:space:]]*ld-svc-c[[:space:]]*$' $f"
  check "io= — процесс, который пишет на диск"          bash -c "grep -Eiq '^[[:space:]]*io[[:space:]]*=[[:space:]]*ld-svc-a[[:space:]]*$' $f"
  check "все три процесса живы (ничего не убито)"       bash -c '[ "$(ps -eo comm= | grep -cx "ld-svc-[abc]")" -eq 3 ]'
  summary
}

# ====================================================================
# task_11 · занятие 11 · сервер тормозит: базовая методика диагностики
# ====================================================================
task_11_text() { cat <<'T'
Задание 11 (5–10 мин) · сервер тормозит
Машина стала медленной. Пройдите пять шагов методики, найдите причину и почините её.
  1. Есть ли перегрузка и какой ресурс: load average против числа ядер,   uptime, nproc, vmstat 1 3
     колонки r / us / sy / wa / si so.
  2. Найдите процесс, который грузит CPU, и запишите его PID первой        top -b -n1 -o %CPU | head
     строкой в /root/task11-answer.txt.
  3. Выясните, из какого юнита systemd он запущен, и допишите имя юнита    ps -o pid,ppid,args -p PID,
     второй строкой в тот же файл.                                        cat /proc/PID/cgroup, systemctl status PID
  4. Найдите причину в конфигурации юнита и почините её: рабочих           systemctl cat ЮНИТ,
     процессов должно быть не больше числа ядер (nproc).                  правка файла из EnvironmentFile=
  5. Перезапустите сервис и убедитесь, что нагрузка ушла.                  systemctl restart ЮНИТ, uptime, top -b -n1
T
}
task_11_cleanup() {
  unit_rm ld-busy.service
  local p; for p in $(ps -eo pid=,comm= | awk '$2=="ld-busy-worker"||$2=="ld-busy"{print $1}'); do kill -KILL "$p" 2>/dev/null; done
  rm -rf /opt/ld-tasks/task11 /etc/default/ld-busy /root/task11-answer.txt; true
}
task_11_setup() {
  task_11_cleanup; install -d -m 755 /opt/ld-tasks/task11
  printf '#!/bin/bash\nwhile :; do :; done\n' > /opt/ld-tasks/task11/ld-busy-worker
  printf '#!/bin/bash\n: "${WORKERS:=1}"\necho "ld-busy: запускаю $WORKERS рабочих процессов"\nfor ((i=1; i<=WORKERS; i++)); do /opt/ld-tasks/task11/ld-busy-worker & done\nwait\n' > /opt/ld-tasks/task11/ld-busy
  chmod 755 /opt/ld-tasks/task11/ld-busy /opt/ld-tasks/task11/ld-busy-worker
  printf '# ld-busy: настройки сервиса\n# WORKERS — число рабочих процессов. Не больше числа ядер (nproc).\nWORKERS=8\n' > /etc/default/ld-busy
  printf '[Unit]\nDescription=LD busy service (task 11)\n[Service]\nEnvironmentFile=/etc/default/ld-busy\nExecStart=/opt/ld-tasks/task11/ld-busy\nRestart=always\n' > /etc/systemd/system/ld-busy.service
  systemctl daemon-reload; systemctl start ld-busy.service; sleep 1
  ps -eo pid=,comm= | awk '$2=="ld-busy-worker"||$2=="ld-busy"{print $1}' > /opt/ld-tasks/task11/pids
  systemctl show ld-busy.service -p MainPID --value > /opt/ld-tasks/task11/mainpid
  [ -s /opt/ld-tasks/task11/pids ]
}
task_11_check() {
  check "в /root/task11-answer.txt первой строкой — PID процесса ld-busy"  bash -c 'p=$(head -1 /root/task11-answer.txt | tr -d "[:space:]"); [ -n "$p" ] && grep -qx "$p" /opt/ld-tasks/task11/pids'
  check "в /root/task11-answer.txt указан юнит ld-busy.service"            bash -c 'grep -Eq "^[[:space:]]*ld-busy(\.service)?[[:space:]]*$" /root/task11-answer.txt'
  check "в /etc/default/ld-busy WORKERS не больше числа ядер"              bash -c 'w=$(grep -E "^WORKERS=" /etc/default/ld-busy | tail -1 | tr -dc "0-9"); [ -n "$w" ] && [ "$w" -ge 1 ] && [ "$w" -le "$(nproc)" ]'
  check "ld-busy.service перезапущен и работает (active)"                  bash -c '[ "$(systemctl show ld-busy.service -p MainPID --value)" != "$(cat /opt/ld-tasks/task11/mainpid)" ] && systemctl is-active ld-busy.service'
  check "рабочих процессов ld-busy-worker не больше числа ядер"            bash -c 'n=$(ps -eo comm= | grep -cx ld-busy-worker); [ "$n" -ge 1 ] && [ "$n" -le "$(nproc)" ]'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_4.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_4.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_4.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
