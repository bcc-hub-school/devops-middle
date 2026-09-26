#!/bin/bash
# Linux Deep · Модуль 11 «Deep Linux Networking» · задания к занятиям 27–28 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_11.sh
#
#   bash module_11.sh list                  какие задания есть
#   sudo bash module_11.sh setup task_27    подготовить стенд и показать задание
#   sudo bash module_11.sh check task_27    проверить
#   sudo bash module_11.sh reset task_27    начать заново (стенд пересоздаётся)
#   sudo bash module_11.sh clean task_27    убрать стенд после занятия
#   bash module_11.sh task  task_27     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_27 task_28"

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
# task_27 · занятие 27 · путь пакета: маршрут, ARP, ip_forward (netns + veth)
# ====================================================================
task_27_text() { cat <<'T'
Задание 27 (5–10 мин) · маршрут, ARP и ip_forward на паре netns/veth
Стенд поднял «удалённую сеть»: netns ld-a с адресом 10.98.0.5/32 на lo, доступный через
пару veth ld-veth0 (у вас, 10.99.0.1) — ld-veth1 (в ld-a, 10.99.0.2). Основной интерфейс ВМ не трогаем.
  1. Добавьте маршрут к сети 10.98.0.0/24 через соседа 10.99.0.2.        ip route add 10.98.0.0/24 via 10.99.0.2 dev ld-veth0
  2. Включите транзит на этой машине.                                    sudo sysctl -w net.ipv4.ip_forward=1
  3. Проверьте путь: ping и решение ядра о маршруте до 10.98.0.5.        ping -c1 10.98.0.5 · ip route get 10.98.0.5
  4. Посмотрите ARP-запись соседа 10.99.0.2 и запишите её MAC первой     ip neigh show 10.99.0.2
     строкой в /root/task27-answer.txt.
  5. Второй строкой запишите имя интерфейса из ip route get 10.98.0.5.  ip route get 10.98.0.5 | awk 'NR==1{print $5}'
     Проверьте себя и сдайте: sudo bash module_11.sh check task_27
T
}
task_27_cleanup() {
  ip netns del ld-a 2>/dev/null
  ip link del ld-veth0 2>/dev/null
  ip route del 10.98.0.0/24 2>/dev/null
  if [ -f /opt/ld-tasks/task27/ip_forward.orig ]; then
    sysctl -qw net.ipv4.ip_forward="$(cat /opt/ld-tasks/task27/ip_forward.orig)"
  fi
  rm -rf /opt/ld-tasks/task27 /root/task27-answer.txt; true
}
task_27_setup() {
  need_pkg iproute2; task_27_cleanup
  install -d -m 755 /opt/ld-tasks/task27
  cat /proc/sys/net/ipv4/ip_forward > /opt/ld-tasks/task27/ip_forward.orig
  sysctl -qw net.ipv4.ip_forward=0   # чистое начальное состояние — студент включает сам (шаг 2)

  ip netns add ld-a
  ip link add ld-veth0 type veth peer name ld-veth1 netns ld-a
  ip addr add 10.99.0.1/24 dev ld-veth0
  ip link set ld-veth0 up

  ip netns exec ld-a ip link set lo up
  ip netns exec ld-a ip addr add 10.99.0.2/24 dev ld-veth1
  ip netns exec ld-a ip addr add 10.98.0.5/32 dev lo
  ip netns exec ld-a ip link set ld-veth1 up
  ip netns exec ld-a sysctl -qw net.ipv4.ip_forward=1
  ip netns exec ld-a ip route add default via 10.99.0.1

  ping -c1 -W1 10.99.0.2 >/dev/null 2>&1   # чтобы сосед появился в ip neigh к моменту задания
  true
}
task_27_mac() { ip neigh show 10.99.0.2 dev ld-veth0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") {print tolower($(i+1)); exit}}'; }
task_27_line() { sed -n "${1}p" /root/task27-answer.txt 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z'; }
task_27_check() {
  check "маршрут к 10.98.0.0/24 через 10.99.0.2 dev ld-veth0"  bash -c "ip route show 10.98.0.0/24 | grep -q 'via 10.99.0.2 dev ld-veth0'"
  check "net.ipv4.ip_forward = 1"                               bash -c '[ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ]'
  check "ping 10.98.0.5 проходит"                                ping -c1 -W2 10.98.0.5
  local mac; mac=$(task_27_mac)
  check "строка 1: MAC соседа 10.99.0.2 ($mac)"                  bash -c "[ -n '$mac' ] && [ '$(task_27_line 1)' = '$mac' ]"
  check "строка 2: интерфейс — ld-veth0"                         bash -c "[ '$(task_27_line 2)' = 'ld-veth0' ]"
  summary
}

# ====================================================================
# task_28 · занятие 28 · nftables и network namespaces
# ====================================================================
task_28_text() { cat <<'T'
Задание 28 (5-10 мин) · nftables и network namespaces
Сервис ld-shield слушает 0.0.0.0:8085 без всякой защиты. Основной интерфейс ВМ и порт 22 не трогаем —
только точечное правило на порт 8085 и учебный netns ld-lab.
  1. Создайте таблицу inet ld, цепочку input (hook input priority 0;          nft add table inet ld · nft add chain inet ld input
     policy accept) и правило: tcp dport 8085 принимать только с              '{ type filter hook input priority 0; policy accept; }'
     127.0.0.1, остальное — drop.                                             nft add rule inet ld input tcp dport 8085 ip saddr 127.0.0.1 accept
                                                                                nft add rule inet ld input tcp dport 8085 drop
  2. Проверьте: локально сервис отвечает, снаружи — таймаут.                  curl -s --max-time 3 http://127.0.0.1:8085/
                                                                                curl --max-time 3 http://<внешний IP>:8085/
  3. Создайте netns ld-lab и пару veth: ld-lab0 (у вас, 10.97.0.1/24) —        ip netns add ld-lab
     ld-lab1 (в ld-lab, 10.97.0.2/24); поднимите оба конца и lo внутри.        ip link add ld-lab0 type veth peer name ld-lab1 netns ld-lab
  4. Проверьте связь: ping из netns на хост (10.97.0.1).                      ip netns exec ld-lab ping -c1 10.97.0.1
  5. Запишите в /root/task28-answer.txt адрес интерфейса ld-lab1 внутри        ip netns exec ld-lab ip -br addr show ld-lab1
     netns (должно получиться 10.97.0.2/24).
     Проверьте себя и сдайте: sudo bash module_11.sh check task_28
T
}
task_28_cleanup() {
  ip netns del ld-lab 2>/dev/null
  ip link del ld-lab0 2>/dev/null
  nft delete table inet ld 2>/dev/null
  unit_rm ld-shield.service
  rm -rf /opt/ld-tasks/task28 /root/task28-answer.txt; true
}
task_28_setup() {
  need_pkg nftables iproute2; task_28_cleanup
  install -d -m 755 /opt/ld-tasks/task28
  cat > /etc/systemd/system/ld-shield.service <<'U'
[Unit]
Description=LD shield demo service (task 28)
[Service]
WorkingDirectory=/opt/ld-tasks/task28
ExecStart=/usr/bin/python3 -m http.server 8085 --bind 0.0.0.0
[Install]
WantedBy=multi-user.target
U
  systemctl daemon-reload
  systemctl enable --now ld-shield.service >/dev/null 2>&1
  sleep 1
  true
}
task_28_extip() {
  local ifc; ifc=$(ip -4 -o route show to default 2>/dev/null | awk '{print $5; exit}')
  [ -n "$ifc" ] || return 1
  ip -4 -o addr show dev "$ifc" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}
task_28_check() {
  check "сервис ld-shield слушает 8085"                bash -c 'ss -tln | grep -q ":8085 "'
  check "таблица inet ld с правилом на tcp dport 8085"  bash -c "nft list table inet ld 2>/dev/null | grep -q 'dport 8085'"
  check "curl с 127.0.0.1:8085 отвечает"                curl -s --max-time 3 -o /dev/null http://127.0.0.1:8085/
  local ip; ip=$(task_28_extip)
  check "curl с внешнего адреса ($ip) не проходит"      bash -c "[ -n '$ip' ] && ! curl -s --max-time 3 -o /dev/null http://$ip:8085/"
  check "netns ld-lab существует"                       bash -c "ip netns list | grep -q '^ld-lab'"
  check "ping из ld-lab на 10.97.0.1 проходит"          ip netns exec ld-lab ping -c1 -W2 10.97.0.1
  check "ответ верный: 10.97.0.2/24"                    bash -c "[ \"\$(tr -d '[:space:]' < /root/task28-answer.txt 2>/dev/null)\" = '10.97.0.2/24' ]"
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_11.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_11.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_11.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
