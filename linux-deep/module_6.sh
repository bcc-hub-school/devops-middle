#!/bin/bash
# Linux Deep · Модуль 6 «Kernel & System Tuning» · задания к занятиям 15–16 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_6.sh
#
#   bash module_6.sh list                  какие задания есть
#   sudo bash module_6.sh setup task_15    подготовить стенд и показать задание
#   sudo bash module_6.sh check task_15    проверить
#   sudo bash module_6.sh reset task_15    начать заново (стенд пересоздаётся)
#   sudo bash module_6.sh clean task_15    убрать стенд после занятия
#   bash module_6.sh task  task_15     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_15 task_16"

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
# task_15 · занятие 15 · sysctl и ulimits
# ====================================================================
task_15_text() { cat <<'T'
Задание 15 (5–10 мин) · sysctl и ulimits
На машине занижен vm.swappiness и работает сервис ld-files, который падает в рестарт-цикл
с ошибкой «Too many open files» (в юните стоит LimitNOFILE=64).
  1. Сделайте vm.swappiness = 10 постоянной настройкой: файл /etc/sysctl.d/90-ld.conf,
     примените без перезагрузки.                                    /etc/sysctl.d/90-ld.conf, sysctl --system
  2. Поднимите ld-files.service LimitNOFILE до 4096 drop-ином,        systemctl edit ld-files.service,
     не редактируя сам юнит и не трогая limits.conf.                 [Service] LimitNOFILE=4096
  3. Перезапустите сервис и убедитесь, что он стабильно работает.     daemon-reload, restart, is-active
  4. Запишите в /root/task15-answer.txt текущий hard-лимит nofile
     процесса ld-files (значение из /proc/PID/limits).                systemctl show -p MainPID, /proc/PID/limits
T
}
task_15_cleanup() {
  unit_rm ld-files.service
  rm -f /etc/sysctl.d/90-ld.conf
  sysctl -w vm.swappiness=60 >/dev/null 2>&1
  rm -rf /opt/ld-tasks/task15 /var/tmp/ld-files /root/task15-answer.txt
  true
}
task_15_setup() {
  task_15_cleanup; need_pkg python3
  install -d -m 755 /opt/ld-tasks/task15
  install -d -m 1777 /var/tmp/ld-files
  cat > /opt/ld-tasks/task15/ld-files <<'PY'
#!/usr/bin/env python3
# Демо-приложение: держит по открытому файлу на каждую «клиентскую сессию».
import sys, time
handles = []
try:
    for i in range(200):
        handles.append(open(f"/var/tmp/ld-files/session-{i}.dat", "w"))
    print("200 сессий открыто, работаю", flush=True)
    while True:
        time.sleep(60)
except OSError as e:
    print(f"FATAL: не могу открыть файл сессии: {e}", file=sys.stderr, flush=True)
    sys.exit(1)
PY
  chmod 755 /opt/ld-tasks/task15/ld-files
  cat > /etc/systemd/system/ld-files.service <<'U'
[Unit]
Description=LD files service (task 15)
[Service]
ExecStart=/opt/ld-tasks/task15/ld-files
LimitNOFILE=64
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl enable --now ld-files.service >/dev/null 2>&1
  sleep 1
  true
}
task_15_check() {
  local pid hard
  pid=$(systemctl show -p MainPID --value ld-files.service 2>/dev/null)
  hard=""
  [ -n "$pid" ] && [ "$pid" != "0" ] && [ -r "/proc/$pid/limits" ] && hard=$(awk '/Max open files/{print $5}' "/proc/$pid/limits" 2>/dev/null)
  check "vm.swappiness = 10 (действует сейчас)"              bash -c '[ "$(sysctl -n vm.swappiness 2>/dev/null)" = "10" ]'
  check "постоянно закреплено в /etc/sysctl.d/90-ld.conf"    bash -c "grep -Eq '^[[:space:]]*vm\.swappiness[[:space:]]*=[[:space:]]*10[[:space:]]*\$' /etc/sysctl.d/90-ld.conf"
  check "LimitNOFILE ld-files поднят до 4096+ через drop-in" bash -c "v=\$(systemctl show -p LimitNOFILE --value ld-files.service 2>/dev/null); [[ \"\$v\" =~ ^[0-9]+\$ ]] && [ \"\$v\" -ge 4096 ] && [ -d /etc/systemd/system/ld-files.service.d ] && grep -rq LimitNOFILE /etc/systemd/system/ld-files.service.d"
  check "ld-files.service активен (не в рестарт-цикле)"      systemctl is-active ld-files.service
  check "в task15-answer.txt записан hard nofile ld-files"   bash -c "[ -n '$hard' ] && [ \"\$(tr -d '[:space:]' < /root/task15-answer.txt 2>/dev/null)\" = '$hard' ]"
  summary
}

# ====================================================================
# task_16 · занятие 16 · cgroups и namespaces
# ====================================================================
task_16_text() { cat <<'T'
Задание 16 (5–10 мин) · cgroups и namespaces
На машине работает сервис ld-hog.service: растёт по памяти до ~60 МБ и держит её.
  1. Посмотрите его текущее потребление.                             systemd-cgtop -b -n2, cat memory.current
  2. Ограничьте сервис drop-ином: MemoryMax=100M и CPUQuota=20%,       systemctl edit ld-hog.service,
     не редактируя сам юнит-файл.                                     [Service] MemoryMax=100M / CPUQuota=20%
  3. Примените и убедитесь, что лимит дошёл до ядра.                  daemon-reload, restart,
     Ожидаемо: сервис будет уходить в OOM внутри cgroup и             cat .../ld-hog.service/memory.max
     перезапускаться (Restart=on-failure) — это нормально.
  4. Запишите в /root/task16-answer.txt inode PID-namespace           systemctl show -p MainPID --value ld-hog,
     процесса ld-hog.                                                 sudo readlink /proc/PID/ns/pid
T
}
task_16_cleanup() {
  unit_rm ld-hog.service
  rm -rf /opt/ld-tasks/task16 /root/task16-answer.txt
  true
}
task_16_setup() {
  task_16_cleanup; need_pkg python3
  install -d -m 755 /opt/ld-tasks/task16
  cat > /opt/ld-tasks/task16/ld-hog <<'PY'
#!/usr/bin/env python3
# Растёт по памяти до ~60 МБ и держит её, слегка грузит CPU (под MemoryMax=100M живёт спокойно)
import time
blocks = []
while True:
    if len(blocks) < 6:
        blocks.append(bytearray(10 * 1024 * 1024))
    for b in blocks:
        b[0] = (b[0] + 1) % 256
    s = sum(i * i for i in range(200000))
    time.sleep(0.2)
PY
  chmod 755 /opt/ld-tasks/task16/ld-hog
  cat > /etc/systemd/system/ld-hog.service <<'U'
[Unit]
Description=LD hog service (task 16)

[Service]
ExecStart=/opt/ld-tasks/task16/ld-hog
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl enable --now ld-hog.service >/dev/null 2>&1
  sleep 3
  true
}
task_16_check() {
  local cg="/sys/fs/cgroup/system.slice/ld-hog.service" mmax="" cmax="" expect_ns="" got_ns=""
  [ -r "$cg/memory.max" ] && mmax=$(cat "$cg/memory.max" 2>/dev/null)
  [ -r "$cg/cpu.max" ] && cmax=$(cat "$cg/cpu.max" 2>/dev/null)
  expect_ns=$(readlink /proc/1/ns/pid 2>/dev/null)
  got_ns=$(tr -d '[:space:]' < /root/task16-answer.txt 2>/dev/null)
  check "юнит ld-hog.service создан и загружен"              test -f /etc/systemd/system/ld-hog.service
  check "drop-in MemoryMax=/CPUQuota= создан"                 bash -c '[ -d /etc/systemd/system/ld-hog.service.d ] && grep -rq MemoryMax /etc/systemd/system/ld-hog.service.d && grep -rq CPUQuota /etc/systemd/system/ld-hog.service.d'
  check "memory.max cgroup ld-hog = 100M (104857600)"         bash -c "[ '$mmax' = '104857600' ]"
  check "cpu.max cgroup ld-hog = 20% периода (20000 …)"       bash -c "[ -n '$cmax' ] && [ \"\$(echo '$cmax' | awk '{print \$1}')\" = 20000 ]"
  check "в task16-answer.txt записан pid-namespace ld-hog"    bash -c "[ -n '$got_ns' ] && [ '$got_ns' = '$expect_ns' ]"
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_6.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_6.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_6.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
