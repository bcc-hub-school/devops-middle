#!/bin/bash
# Linux Deep · Модуль 9 «Incident Troubleshooting Labs» · задания к занятиям 22–24 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_9.sh
#
#   bash module_9.sh list                  какие задания есть
#   sudo bash module_9.sh setup task_22    подготовить стенд и показать задание
#   sudo bash module_9.sh check task_22    проверить
#   sudo bash module_9.sh reset task_22    начать заново (стенд пересоздаётся)
#   sudo bash module_9.sh clean task_22    убрать стенд после занятия
#   bash module_9.sh task  task_22     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_22 task_23 task_24"

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
# task_22 · занятие 22 · incident lab: сервис + CPU
# ====================================================================
task_22_text() { cat <<'T'
Задание 22 (5–10 мин) · разбор двух инцидентов: сервис и CPU
На машине два инцидента: сервис ld-api не запускается, процесс ld-miner грузит CPU.
  1. Посмотрите статус и журнал ld-api, определите код ошибки.                  systemctl status ld-api,
                                                                                    journalctl -u ld-api -n 20
  2. В юните две ошибки — неверные User= и WorkingDirectory=; исправьте оба      systemctl cat ld-api,
     (пользователь и каталог должны существовать).                              правка /etc/systemd/system/ld-api.service
  3. Перечитайте конфигурацию и запустите сервис: добейтесь active (running)     systemctl daemon-reload,
     без ошибок в журнале.                                                      systemctl restart ld-api, systemctl status ld-api
  4. Найдите процесс, который ест 100% CPU, узнайте его пользователя и          top -b -n1,
     сколько он уже работает (etime).                                          ps -o pid,user,etime,args -C ld-miner
  5. Завершите этот процесс и запишите его PID и пользователя (двумя           kill PID,
     строками) в /root/task22-answer.txt.                                      printf 'PID\nUSER\n' | sudo tee /root/task22-answer.txt
T
}
task_22_cleanup() {
  local p
  for p in $(ps -eo pid=,comm= | awk '$2=="ld-api.sh"||$2=="ld-miner"{print $1}'); do kill -KILL "$p" 2>/dev/null; done
  unit_rm ld-api.service
  userdel -r ldapi 2>/dev/null
  userdel -r batch 2>/dev/null
  rm -rf /opt/ld-tasks/task22 /root/task22-answer.txt
  true
}
task_22_setup() {
  task_22_cleanup
  install -d -m 755 /opt/ld-tasks/task22

  # ---------- инцидент А: ld-api не стартует (User= и WorkingDirectory= неверные) ----------
  install -d -m 755 /opt/ld-tasks/task22/api
  printf '#!/bin/bash\nwhile :; do echo "ld-api: обрабатываю запросы"; sleep 10; done\n' > /opt/ld-tasks/task22/ld-api.sh
  chmod 755 /opt/ld-tasks/task22/ld-api.sh
  id -u ldapi >/dev/null 2>&1 || useradd -r -M -s /usr/sbin/nologin ldapi
  cat > /etc/systemd/system/ld-api.service <<'U'
[Unit]
Description=LD API service (task 22)

[Service]
Type=simple
User=ldapi-svc
WorkingDirectory=/opt/ld-tasks/task22/apiserver
ExecStart=/opt/ld-tasks/task22/ld-api.sh

[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl start ld-api.service >/dev/null 2>&1; true

  # ---------- инцидент Б: ld-miner грузит CPU (busy-loop от пользователя batch) ----------
  id -u batch >/dev/null 2>&1 || useradd -r -M -s /usr/sbin/nologin batch
  printf '#!/bin/bash\nwhile :; do :; done\n' > /opt/ld-tasks/task22/ld-miner
  chmod 755 /opt/ld-tasks/task22/ld-miner
  su -s /bin/bash batch -c 'setsid /opt/ld-tasks/task22/ld-miner >/dev/null 2>&1 </dev/null &'
  sleep 1
  pgrep -x ld-miner | head -1 > /opt/ld-tasks/task22/miner.pid
  [ -s /opt/ld-tasks/task22/miner.pid ]
}
task_22_check() {
  check "ld-api.service активен (running)"                        systemctl is-active ld-api.service
  check "WorkingDirectory юнита указывает на существующий каталог" bash -c 'd=$(systemctl show ld-api.service -p WorkingDirectory --value); [ -n "$d" ] && [ -d "$d" ]'
  check "User юнита — существующий пользователь"                  bash -c 'u=$(systemctl show ld-api.service -p User --value); [ -n "$u" ] && id -u "$u" >/dev/null 2>&1'
  check "ld-miner завершён"                                        bash -c "$(declare -f alive); ! alive ld-miner"
  check "в /root/task22-answer.txt верный PID процесса ld-miner"   bash -c '[ "$(head -1 /root/task22-answer.txt 2>/dev/null | tr -d "[:space:]")" = "$(cat /opt/ld-tasks/task22/miner.pid 2>/dev/null)" ]'
  check "в /root/task22-answer.txt указан пользователь batch"      bash -c 'sed -n 2p /root/task22-answer.txt 2>/dev/null | tr -d "[:space:]" | grep -qx batch'
  summary
}

# ====================================================================
# task_23 · занятие 23 · incident lab: память + диск
# ====================================================================
task_23_text() { cat <<'T'
Задание 23 (5–10 мин) · разбор двух инцидентов: утечка памяти и диск
На машине два инцидента: сервис ld-leak растёт по памяти, процесс ld-filler держит открытым удалённый файл в /var/tmp.
  1. Двумя замерами с интервалом докажите рост памяти ld-leak.service.       ps --sort=-rss -eo pid,rss,comm | head,
                                                                                 grep VmRSS /proc/PID/status (замер, пауза, повтор)
  2. Запишите PID ld-leak (первая строка) и перезапустите сервис —          systemctl show -p MainPID --value ld-leak,
     после restart память сброшена.                                          systemctl restart ld-leak
  3. Найдите процесс, который держит открытым удалённый (deleted) файл       lsof +L1,
     в /var/tmp — место занято, а файла в ls уже нет.                        find /proc/*/fd -lname '*(deleted)'
  4. Освободите место, не перезапуская процесс: обнулите файл через          ls -l /proc/PID/fd,
     файловый дескриптор, а не rm.                                            : > /proc/PID/fd/N
  5. Запишите PID ld-filler (вторая строка) и сдайте.                        printf 'PID1\nPID2\n' | sudo tee /root/task23-answer.txt,
                                                                                 df -h /var/tmp
T
}
task_23_cleanup() {
  local p
  for p in $(ps -eo pid=,comm= | awk '$2=="ld-leak"||$2=="ld-filler"{print $1}'); do kill -KILL -- "-$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
  unit_rm ld-leak.service
  rm -f /var/tmp/ld-filler-data
  rm -rf /opt/ld-tasks/task23 /root/task23-answer.txt
  true
}
task_23_setup() {
  task_23_cleanup
  install -d -m 755 /opt/ld-tasks/task23

  # ---------- инцидент А: ld-leak — растёт по памяти до потолка ~150 МБ и держит ----------
  cat > /opt/ld-tasks/task23/ld-leak <<'PY'
#!/usr/bin/python3
import time
CHUNK = 5 * 1024 * 1024
CEILING = 150 * 1024 * 1024
data = []
total = 0
while True:
    if total < CEILING:
        data.append(bytearray(CHUNK))
        total += CHUNK
    time.sleep(1)
PY
  chmod 755 /opt/ld-tasks/task23/ld-leak
  cat > /etc/systemd/system/ld-leak.service <<'U'
[Unit]
Description=LD leak service (task 23)

[Service]
Type=simple
ExecStart=/opt/ld-tasks/task23/ld-leak

[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl start ld-leak.service
  sleep 2
  systemctl show ld-leak.service -p MainPID --value > /opt/ld-tasks/task23/leak.pid
  [ -s /opt/ld-tasks/task23/leak.pid ]

  # ---------- инцидент Б: ld-filler держит открытым удалённый файл ~200 МБ в /var/tmp ----------
  fallocate -l 200M /var/tmp/ld-filler-data 2>/dev/null || dd if=/dev/zero of=/var/tmp/ld-filler-data bs=1M count=200 >/dev/null 2>&1
  cat > /opt/ld-tasks/task23/ld-filler <<'SH'
#!/bin/bash
exec 9<>/var/tmp/ld-filler-data
rm -f /var/tmp/ld-filler-data
while :; do sleep 3600 9<&-; done
SH
  chmod 755 /opt/ld-tasks/task23/ld-filler
  setsid /opt/ld-tasks/task23/ld-filler >/dev/null 2>&1 </dev/null &
  sleep 1
  pgrep -x ld-filler | head -1 > /opt/ld-tasks/task23/filler.pid
  [ -s /opt/ld-tasks/task23/filler.pid ]
}
task_23_check() {
  local ans1 ans2 leak_pid filler_pid cur_main deleted_kb
  ans1=$(sed -n 1p /root/task23-answer.txt 2>/dev/null | tr -d '[:space:]')
  ans2=$(sed -n 2p /root/task23-answer.txt 2>/dev/null | tr -d '[:space:]')
  leak_pid=$(cat /opt/ld-tasks/task23/leak.pid 2>/dev/null)
  filler_pid=$(cat /opt/ld-tasks/task23/filler.pid 2>/dev/null)
  cur_main=$(systemctl show ld-leak.service -p MainPID --value 2>/dev/null)
  check "в /root/task23-answer.txt верный PID ld-leak (1-я строка)"    bash -c "[ -n '$leak_pid' ] && [ '$ans1' = '$leak_pid' ]"
  check "ld-leak.service активен (running)"                            systemctl is-active ld-leak.service
  check "ld-leak.service перезапущен (MainPID изменился)"              bash -c "[ -n '$cur_main' ] && [ -n '$leak_pid' ] && [ '$cur_main' != '$leak_pid' ]"
  check "в /root/task23-answer.txt верный PID ld-filler (2-я строка)"  bash -c "[ -n '$filler_pid' ] && [ '$ans2' = '$filler_pid' ]"
  check "ld-filler жив"                                                 bash -c "$(declare -f alive); alive ld-filler"
  deleted_kb=$(ls -l /proc/"$filler_pid"/fd 2>/dev/null | awk '/\(deleted\)/{print $9}' | \
               while read -r n; do stat -L --format=%s "/proc/$filler_pid/fd/$n" 2>/dev/null; done | \
               awk '{s+=$1} END{print int((s+0)/1024)}')
  check "призрачный файл ld-filler освобождён (fd почти пуст)"          bash -c "[ ${deleted_kb:-0} -lt 1024 ]"
  summary
}

# ====================================================================
# task_24 · занятие 24 · incident lab: сеть и SSH
# ====================================================================
task_24_text() { cat <<'T'
Задание 24 (5–10 мин) · разбор двух инцидентов: сеть и SSH
На машине два инцидента: клиент ld-probe не может достучаться до ld-portal (порт 8083),
вход aliya@localhost по ключу не работает. Основной сетевой интерфейс не трогайте.
  1. Воспроизведите ld-probe, определите, куда ведёт имя ld-portal.local.       ld-probe,
                                                                                    getent hosts ld-portal.local
  2. Исправьте /etc/hosts: имя должно вести на 127.0.0.1.                       sudo nano /etc/hosts
  3. Найдите реальный порт ld-portal, сверьте с /etc/default/ld-portal,        ss -tlnp | grep 808,
     исправьте и перезапустите сервис.                                         sudo nano /etc/default/ld-portal,
                                                                                    sudo systemctl restart ld-portal
  4. Убедитесь, что ld-probe отвечает OK.                                       ld-probe
  5. aliya@localhost по ключу не пускает: найдите причину и добавьте aliya     sudo journalctl -u ssh -n 10,
     в AllowUsers (не удаляйте файл, не троньте student/ubuntu/root).          sudo sshd -T | grep -i allowusers,
                                                                                    sudo sshd -t, sudo systemctl reload ssh
T
}
task_24_user() { echo "${SUDO_USER:-root}"; }
task_24_home() { getent passwd "$(task_24_user)" | cut -d: -f6; }
task_24_cleanup() {
  unit_rm ld-portal.service
  rm -f /etc/default/ld-portal /usr/local/bin/ld-probe
  sed -i '/ld-portal\.local/d' /etc/hosts 2>/dev/null
  rm -f /etc/ssh/sshd_config.d/60-ld.conf
  sshd -t >/dev/null 2>&1 && systemctl reload ssh >/dev/null 2>&1
  pkill -KILL -u aliya 2>/dev/null
  userdel -r aliya 2>/dev/null
  local h; h=$(task_24_home)
  rm -f /root/.ssh/ld_aliya /root/.ssh/ld_aliya.pub "$h/.ssh/ld_aliya" "$h/.ssh/ld_aliya.pub" 2>/dev/null
  rm -rf /opt/ld-tasks/task24
  true
}
task_24_setup() {
  need_pkg openssh-server openssh-client iproute2 curl; task_24_cleanup

  # ---------- инцидент А: ld-probe не достучаться (hosts + порт неверные) ----------
  install -d -m 755 /opt/ld-tasks/task24/www
  echo 'OK' > /opt/ld-tasks/task24/www/index.html
  printf '# ld-portal: порт сервиса (перенесено со старого сервера)\nPORT=8084\n' > /etc/default/ld-portal
  cat > /etc/systemd/system/ld-portal.service <<'U'
[Unit]
Description=LD portal service (task 24)
After=network.target

[Service]
EnvironmentFile=/etc/default/ld-portal
ExecStart=/usr/bin/python3 -m http.server ${PORT} --bind 127.0.0.1 --directory /opt/ld-tasks/task24/www
Restart=on-failure

[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl enable --now ld-portal.service >/dev/null 2>&1

  cat > /usr/local/bin/ld-probe <<'P'
#!/bin/bash
curl -fsS -m 3 http://ld-portal.local:8083/
P
  chmod 755 /usr/local/bin/ld-probe

  sed -i '/ld-portal\.local/d' /etc/hosts
  echo '10.255.255.9 ld-portal.local' >> /etc/hosts

  # ---------- инцидент Б: AllowUsers без aliya ----------
  id -u aliya >/dev/null 2>&1 || useradd -m -s /bin/bash aliya
  ssh-keygen -q -t ed25519 -N '' -C ld_aliya -f /opt/ld-tasks/task24/ld_aliya
  install -d -m 700 -o aliya -g aliya /home/aliya/.ssh
  install -m 600 -o aliya -g aliya /opt/ld-tasks/task24/ld_aliya.pub /home/aliya/.ssh/authorized_keys

  local u h; u=$(task_24_user); h=$(task_24_home)
  install -d -m 700 -o "$u" -g "$(id -gn "$u")" "$h/.ssh"
  install -m 600 -o "$u" -g "$(id -gn "$u")" /opt/ld-tasks/task24/ld_aliya "$h/.ssh/ld_aliya"
  install -d -m 700 /root/.ssh; install -m 600 /opt/ld-tasks/task24/ld_aliya /root/.ssh/ld_aliya

  # в AllowUsers обязательно остаётся текущий пользователь — иначе можно потерять вход
  local keep; keep=$(printf '%s\n' student ubuntu root "$u" | awk '!seen[$0]++' | tr '\n' ' ')
  { echo '# ld: ограничение доступа (перенесено со старого сервера)'
    echo "AllowUsers ${keep% }"; } > /etc/ssh/sshd_config.d/60-ld.conf
  # restart, а не reload: два SIGHUP подряд (демо перед заданием + setup) sshd мог проглотить и остаться без AllowUsers
  sshd -t && systemctl restart ssh >/dev/null 2>&1
  for _ in 1 2 3 4 5; do systemctl is-active ssh >/dev/null 2>&1 && break; sleep 1; done
  sleep 1
  true
}
task_24_check() {
  check "ld-probe возвращает 0 и печатает OK" \
        bash -c 'out=$(/usr/local/bin/ld-probe 2>/dev/null); rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q OK'
  check "ld-portal слушает 127.0.0.1:8083"          bash -c 'ss -tln | grep -q "127\.0\.0\.1:8083 "'
  check "/etc/default/ld-portal: PORT=8083"          bash -c 'grep -Eq "^PORT=8083[[:space:]]*$" /etc/default/ld-portal'
  check "/etc/hosts: ld-portal.local -> 127.0.0.1"   bash -c 'getent hosts ld-portal.local | awk "{print \$1}" | grep -qx 127.0.0.1'
  check "ssh aliya@localhost по ключу проходит" \
        ssh -i /root/.ssh/ld_aliya -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 aliya@localhost true
  check "AllowUsers в drop-ине содержит aliya"       bash -c 'grep -h AllowUsers /etc/ssh/sshd_config.d/60-ld.conf 2>/dev/null | grep -qw aliya'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_9.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_9.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_9.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
