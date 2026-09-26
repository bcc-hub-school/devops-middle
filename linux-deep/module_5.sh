#!/bin/bash
# Linux Deep · Модуль 5 «Networking & Debugging» · задания к занятиям 12–14 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_5.sh
#
#   bash module_5.sh list                  какие задания есть
#   sudo bash module_5.sh setup task_12    подготовить стенд и показать задание
#   sudo bash module_5.sh check task_12    проверить
#   sudo bash module_5.sh reset task_12    начать заново (стенд пересоздаётся)
#   sudo bash module_5.sh clean task_12    убрать стенд после занятия
#   bash module_5.sh task  task_12     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_12 task_13 task_14"

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
# task_12 · занятие 12 · сетевая диагностика и SSH
# ====================================================================
task_12_text() { cat <<'T'
Задание 12 (5–10 мин) · сетевая диагностика и SSH
Сервис ld-web (порт 8081) «жив, но снаружи недоступен»; вход aliya@localhost по ключу не работает.
  1. Выясните, на каком адресе слушает ld-web, и убедитесь, что по адресу
     интерфейса он не отвечает.                     sudo ss -tlnp | grep 8081, curl http://$(hostname -I | cut -d' ' -f1):8081/
  2. Сделайте ld-web доступным на всех адресах (0.0.0.0): адрес задаётся
     в /etc/default/ld-web; перезапустите сервис.   sudo nano /etc/default/ld-web, sudo systemctl restart ld-web, ss
  3. Ключ для входа под aliya лежит в ~/.ssh/ld_aliya. Снимите диагностику
     с обеих сторон: клиент и журнал сервера.       ssh -v -i ~/.ssh/ld_aliya aliya@localhost, sudo journalctl -u ssh -n 5
  4. Почините права: ~aliya/.ssh — 700, authorized_keys — 600.
                                                    sudo ls -ld /home/aliya/.ssh, sudo chmod 700 …, sudo chmod 600 …
     Проверьте себя: ssh -i ~/.ssh/ld_aliya aliya@localhost true && echo OK
T
}
task_12_user() { echo "${SUDO_USER:-root}"; }
task_12_home() { getent passwd "$(task_12_user)" | cut -d: -f6; }
task_12_cleanup() {
  unit_rm ld-web.service
  pkill -KILL -u aliya 2>/dev/null; userdel -r aliya 2>/dev/null
  rm -f /etc/default/ld-web /root/.ssh/ld_aliya /root/.ssh/ld_aliya.pub "$(task_12_home)/.ssh/ld_aliya" "$(task_12_home)/.ssh/ld_aliya.pub"
  rm -rf /opt/ld-tasks/task12; true
}
task_12_setup() {
  need_pkg openssh-server openssh-client iproute2 lsof curl; task_12_cleanup
  # (а) ld-web: python3 http.server под systemd, адрес привязки — из /etc/default/ld-web
  install -d -m 755 /opt/ld-tasks/task12/www
  echo '<h1>ld-web работает</h1>' > /opt/ld-tasks/task12/www/index.html
  printf '# ld-web: адрес и порт (перенесено со старого сервера)\nBIND=127.0.0.1\nPORT=8081\n' > /etc/default/ld-web
  cat > /etc/systemd/system/ld-web.service <<'U'
[Unit]
Description=LD web service (task 12)
After=network.target
[Service]
EnvironmentFile=/etc/default/ld-web
ExecStart=/usr/bin/python3 -m http.server ${PORT} --bind ${BIND} --directory /opt/ld-tasks/task12/www
Restart=on-failure
[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload; systemctl enable --now ld-web.service >/dev/null 2>&1
  # (б) aliya: ключ в authorized_keys есть, но права «chmod -R 777, чтобы заработало»
  useradd -m -s /bin/bash aliya
  ssh-keygen -q -t ed25519 -N '' -C ld_aliya -f /opt/ld-tasks/task12/ld_aliya
  install -d -m 777 -o aliya -g aliya /home/aliya/.ssh
  install -m 666 -o aliya -g aliya /opt/ld-tasks/task12/ld_aliya.pub /home/aliya/.ssh/authorized_keys
  # приватный ключ — студенту (~/.ssh/ld_aliya) и root (для check)
  local u h; u=$(task_12_user); h=$(task_12_home)
  install -d -m 700 -o "$u" -g "$(id -gn "$u")" "$h/.ssh"
  install -m 600 -o "$u" -g "$(id -gn "$u")" /opt/ld-tasks/task12/ld_aliya "$h/.ssh/ld_aliya"
  install -d -m 700 /root/.ssh; install -m 600 /opt/ld-tasks/task12/ld_aliya /root/.ssh/ld_aliya
  systemctl start ssh.service >/dev/null 2>&1; sleep 1; true
}
task_12_check() {
  check "/etc/default/ld-web: BIND=0.0.0.0"              bash -c 'grep -Eq "^BIND=(0\.0\.0\.0|::|\*)\s*$" /etc/default/ld-web'
  check "ld-web слушает 0.0.0.0:8081 (ss -tlnp)"          bash -c 'ss -tln | grep -Eq "(0\.0\.0\.0|\[::\]|\*):8081 "'
  check "ld-web отвечает по адресу интерфейса"            bash -c 'curl -s -m 3 "http://$(hostname -I | cut -d" " -f1):8081/" | grep -q ld-web'
  check "права: ~aliya/.ssh 700, authorized_keys 600"    bash -c '[ "$(stat -c %a /home/aliya/.ssh)" = 700 ] && [ "$(stat -c %a /home/aliya/.ssh/authorized_keys)" = 600 ]'
  check "ssh aliya@localhost по ключу проходит"           ssh -i /root/.ssh/ld_aliya -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 aliya@localhost true
  summary
}

# ====================================================================
# task_13 · занятие 13 · DNS, strace, tcpdump
# ====================================================================
task_13_text() { cat <<'T'
Задание 13 (5–10 мин) · DNS и strace: «программа не может достучаться»
Сервис ld-api слушает на 127.0.0.1:8082. Клиент /usr/local/bin/ld-client ходит к нему по имени ld-api.local
и получает таймаут. Найдите причину по трассе системных вызовов и почините.
  1. Запустите ld-client и посмотрите, в какой адрес превращается имя.      ld-client, getent hosts ld-api.local
  2. Снимите трассу клиента в файл /tmp/ld.trace и найдите в ней, какие файлы
     открыл процесс при разрешении имени и куда пошёл connect().
                                     strace -f -e trace=connect,openat -o /tmp/ld.trace ld-client
                                     grep -E '/etc/|connect' /tmp/ld.trace
  3. Запишите в /root/task13-answer.txt путь файла, из которого взялся неверный адрес.
  4. Почините этот файл: имя ld-api.local должно вести на 127.0.0.1.         sudo nano / sudo sed -i
  5. Убедитесь, что ld-client получает ответ «ld-api: OK».                   getent hosts ld-api.local, ld-client
T
}
task_13_cleanup() {
  local p; for p in $(ps -eo pid=,comm= | awk '$2=="ld-api"{print $1}'); do kill -KILL "$p" 2>/dev/null; done; sleep 0.3
  sed -i '/[[:space:]]ld-api\.local\([[:space:]]\|$\)/d' /etc/hosts 2>/dev/null
  rm -rf /opt/ld-tasks/task13 /usr/local/bin/ld-client /root/task13-answer.txt /tmp/ld.trace; true
}
task_13_setup() {
  task_13_cleanup; need_pkg strace tcpdump dnsutils curl
  install -d -m 755 /opt/ld-tasks/task13
  cat > /opt/ld-tasks/task13/ld-api <<'P'
#!/usr/bin/python3
# ld-api — учебный сервис задания 13: отвечает "ld-api: OK" на 127.0.0.1:8082
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        b = b"ld-api: OK\n"; self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", 8082), H).serve_forever()
P
  cat > /usr/local/bin/ld-client <<'C'
#!/bin/bash
# ld-client — спрашивает состояние сервиса ld-api по имени ld-api.local
curl -sS --connect-timeout 2 http://ld-api.local:8082/health || echo "ld-client: не могу достучаться до ld-api.local"
C
  chmod 755 /opt/ld-tasks/task13/ld-api /usr/local/bin/ld-client
  echo '10.255.255.1 ld-api.local' >> /etc/hosts          # поломка: неверный адрес в /etc/hosts
  setsid /opt/ld-tasks/task13/ld-api >/dev/null 2>&1 </dev/null &
  sleep 1
}
task_13_check() {
  check "трасса /tmp/ld.trace снята strace: есть openat и connect"  bash -c 'grep -q "openat(" /tmp/ld.trace && grep -q "connect(" /tmp/ld.trace'
  check "в /root/task13-answer.txt записан файл-источник адреса (/etc/hosts)" bash -c 'grep -qx "/etc/hosts" <(tr -d "[:space:]" < /root/task13-answer.txt | sed "s#/*\$##")'
  check "в /etc/hosts имя ld-api.local ведёт на 127.0.0.1"           bash -c 'grep -Eq "^[[:space:]]*127\.0\.0\.1[[:space:]]+ld-api\.local([[:space:]]|$)" /etc/hosts && ! grep -q "10\.255\.255\.1" /etc/hosts'
  check "getent hosts ld-api.local → 127.0.0.1"                        bash -c '[ "$(getent hosts ld-api.local | awk "{print \$1}")" = 127.0.0.1 ]'
  check "ld-client получает ответ «ld-api: OK»"                        bash -c 'timeout 10 /usr/local/bin/ld-client 2>/dev/null | grep -q "ld-api: OK"'
  summary
}

# ====================================================================
# task_14 · занятие 14 · путь пакета: маршрут, ARP, ip_forward, слушающий сокет
# ====================================================================
task_14_text() { cat <<'T'
Задание 14 (5–10 мин) · путь пакета на своей ВМ
На машине запущен systemd-сервис ld-echo (слушает TCP-порт 8090–8099). Ответьте на пять вопросов о своей ВМ
командами занятия и запишите ответы в /root/task14-answer.txt — по одному в строку, в этом порядке:
  1. Шлюз по умолчанию (IP-адрес).                                    ip route          (строка default via …)
  2. Интерфейс, через который уйдёт пакет к 1.1.1.1.                  ip route get 1.1.1.1   (поле dev)
  3. MAC-адрес шлюза.                                                  ip neigh          (поле lladdr; нет записи — ping -c1 шлюз)
  4. Значение net.ipv4.ip_forward (0 или 1).                           sysctl net.ipv4.ip_forward
  5. Порт, на котором слушает ld-echo.                                 sudo ss -tlnp     (столбец Local Address)
     Записать строку: echo ЗНАЧЕНИЕ | sudo tee -a /root/task14-answer.txt
T
}
task_14_cleanup() { unit_rm ld-echo.service; rm -rf /opt/ld-tasks/task14 /root/task14-answer.txt; true; }
task_14_gw()   { ip route show default 2>/dev/null | awk '{print $3; exit}'; }
task_14_dev()  { ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'; }
task_14_mac()  { local gw; gw=$(task_14_gw); [ -n "$gw" ] || return 1
                 ip neigh show "$gw" 2>/dev/null | grep -q lladdr || ping -c1 -W1 "$gw" >/dev/null 2>&1
                 ip neigh show "$gw" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") {print tolower($(i+1)); exit}}'; }
task_14_port() { ss -tlnpH 2>/dev/null | grep '"ld-echo"' | awk '{print $4}' | sed 's/.*://' | head -1; }
task_14_line() { sed -n "${1}p" /root/task14-answer.txt 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z'; }
task_14_setup() {
  task_14_cleanup; need_pkg python3 iproute2
  install -d -m 755 /opt/ld-tasks/task14/www
  echo "ld-echo: ok" > /opt/ld-tasks/task14/www/index.html
  cp "$(readlink -f /usr/bin/python3)" /opt/ld-tasks/task14/ld-echo && chmod 755 /opt/ld-tasks/task14/ld-echo   # копия python3 под именем ld-echo — так его видно в ss -p
  local port=$((8090 + RANDOM % 10)); echo "$port" > /opt/ld-tasks/task14/port
  cat > /etc/systemd/system/ld-echo.service <<U
[Unit]
Description=LD echo service (task 14)
[Service]
ExecStart=/opt/ld-tasks/task14/ld-echo -m http.server $port --bind 127.0.0.1 --directory /opt/ld-tasks/task14/www
Restart=on-failure
[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload; systemctl enable --now ld-echo.service >/dev/null 2>&1
  ping -c1 -W1 "$(task_14_gw)" >/dev/null 2>&1   # чтобы шлюз появился в ip neigh
  sleep 1; systemctl is-active ld-echo.service >/dev/null
}
task_14_check() {
  local gw dev mac fwd port; gw=$(task_14_gw); dev=$(task_14_dev); mac=$(task_14_mac); fwd=$(cat /proc/sys/net/ipv4/ip_forward); port=$(task_14_port)
  check "строка 1: шлюз по умолчанию ($gw)"              bash -c "[ -n '$gw' ] && echo '$(task_14_line 1)' | grep -qw '$gw'"
  check "строка 2: интерфейс до 1.1.1.1 ($dev)"          bash -c "[ -n '$dev' ] && echo '$(task_14_line 2)' | grep -qw '$dev'"
  check "строка 3: MAC-адрес шлюза ($mac)"               bash -c "[ -n '$mac' ] && echo '$(task_14_line 3)' | grep -q '$mac'"
  check "строка 4: net.ipv4.ip_forward = $fwd"           bash -c "[ \"\$(echo '$(task_14_line 4)' | awk '{print \$NF}')\" = '$fwd' ]"
  check "строка 5: порт ld-echo ($port)"                 bash -c "[ -n '$port' ] && echo '$(task_14_line 5)' | grep -Eq '(^|[^0-9])$port([^0-9]|\$)'"
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_5.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_5.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_5.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
