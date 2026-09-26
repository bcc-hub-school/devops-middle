#!/bin/bash
# Linux Deep · Модуль 13 «Security Basics for DevOps» · задания к занятиям 31–32 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_13.sh
#
#   bash module_13.sh list                  какие задания есть
#   sudo bash module_13.sh setup task_31    подготовить стенд и показать задание
#   sudo bash module_13.sh check task_31    проверить
#   sudo bash module_13.sh reset task_31    начать заново (стенд пересоздаётся)
#   sudo bash module_13.sh clean task_31    убрать стенд после занятия
#   bash module_13.sh task  task_31     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_31 task_32"

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
# task_31 · занятие 31 · пользователи, группы и sudoers
# ====================================================================
task_31_text() { cat <<'T'
Задание 31 (5–10 мин) · группы и sudoers
На машине трое: bek — обычный разработчик, лишний в группе sudo (закладка);
svc-deploy — сервисная учётка, которой нужен только перезапуск ld-web; old-dev — уволенный, учётка ещё активна.
  1. Уберите bek из группы sudo.                                   gpasswd -d bek sudo
  2. Заблокируйте old-dev: пароль и оболочку.                      usermod -L old-dev
                                                                     usermod -s /usr/sbin/nologin old-dev
  3. Создайте /etc/sudoers.d/svc-deploy — ТОЧНО одна команда без пароля:
       svc-deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart ld-web
     Права 0440.                                                   visudo -f /etc/sudoers.d/svc-deploy
                                                                     chmod 0440 /etc/sudoers.d/svc-deploy
  4. Проверьте правило: синтаксис файла и то, что реально разрешено. visudo -cf /etc/sudoers.d/svc-deploy
                                                                     sudo -l -U svc-deploy
  5. Запишите в /root/task31-answer.txt состав группы sudo ПОСЛЕ уборки (одна команда, весь вывод).
                                                                     getent group sudo > /root/task31-answer.txt
T
}
task_31_cleanup() {
  userdel -r bek       >/dev/null 2>&1
  userdel -r old-dev    >/dev/null 2>&1
  userdel svc-deploy    >/dev/null 2>&1
  rm -f /etc/sudoers.d/svc-deploy /root/task31-answer.txt
  unit_rm ld-web.service
  true
}
task_31_setup() {
  need_pkg sudo; task_31_cleanup
  useradd -m -s /bin/bash bek
  usermod -aG sudo bek                                    # закладка: лишний член sudo
  useradd -r -s /usr/sbin/nologin svc-deploy
  useradd -m -s /bin/bash old-dev                          # уволен, но учётка ещё активна
  echo "old-dev:LdTask31Pass"  | chpasswd                  # реальный пароль — иначе useradd уже «заблокирован» по умолчанию
  cat > /etc/systemd/system/ld-web.service <<'U'
[Unit]
Description=LD web (стенд занятия 31)
[Service]
Type=oneshot
ExecStart=/bin/true
U
  systemctl daemon-reload
}
task_31_check() {
  check "bek не в группе sudo"                     bash -c '! getent group sudo | cut -d: -f4 | tr "," "\n" | grep -qx bek'
  check "old-dev заблокирован (пароль и/или nologin)" bash -c \
    'passwd -S old-dev 2>/dev/null | awk "{print \$2}" | grep -q "^L" || getent passwd old-dev | cut -d: -f7 | grep -Eq "nologin|/bin/false"'
  check "sudoers.d/svc-deploy существует с правами 0440" bash -c '[ "$(stat -c %a /etc/sudoers.d/svc-deploy 2>/dev/null)" = "440" ]'
  check "файл валиден по visudo -cf"               visudo -cf /etc/sudoers.d/svc-deploy
  check "правило — точно restart ld-web без пароля" bash -c \
    "grep -Eq '^svc-deploy[[:space:]]+ALL=\(root\)[[:space:]]+NOPASSWD:[[:space:]]+/usr/bin/systemctl restart ld-web[[:space:]]*\$' /etc/sudoers.d/svc-deploy"
  check "sudo -l -U svc-deploy показывает правило"  bash -c "sudo -l -U svc-deploy 2>/dev/null | grep -q '/usr/bin/systemctl restart ld-web'"
  check "task31-answer.txt совпадает с getent group sudo" bash -c '[ -s /root/task31-answer.txt ] && [ "$(cat /root/task31-answer.txt)" = "$(getent group sudo)" ]'
  summary
}

# ====================================================================
# task_32 · занятие 32 · права доступа и SSH hardening (финал курса)
# ====================================================================
task_32_text() { cat <<'T'
Задание 32 (5–10 мин) · права доступа и SSH hardening
Стенд /srv/ld-app: config.yml (666) и каталог uploads (777) — «наследство» chmod -R 777.
  1. Приведите config.yml к правам 640, владелец root:ldapp.            chown root:ldapp config.yml
                                                                          chmod 640 config.yml
  2. Приведите uploads к правам 2770 (SGID), владелец ldapp:ldapp.      chown ldapp:ldapp uploads
                                                                          chmod 2770 uploads
  3. Найдите и почините ОСТАВШИЕСЯ world-writable файлы в /srv/ld-app.  find /srv/ld-app -perm -o+w
                                                                          chmod o-w файл
  4. Создайте /etc/ssh/sshd_config.d/50-ld-hardening.conf:
       PermitRootLogin no
       PasswordAuthentication no
       MaxAuthTries 3
     Проверьте синтаксис и перечитайте sshd.                            sudo sshd -t
                                                                          sudo systemctl reload ssh
     Ловушка: файлы sshd_config.d читаются по алфавиту, побеждает ПЕРВОЕ    ls /etc/ssh/sshd_config.d/
     значение. Если рядом есть 50-cloud-init.conf с PasswordAuthentication   sshd -T | grep -i passwordauth
     yes — назовите свой файл 10-ld-hardening.conf. Сверяйтесь по sshd -T.
     Внимание: PasswordAuthentication no отключит вход по паролю — держите
     открытой текущую сессию и убедитесь, что у вас есть ключ.
  5. Запишите в /root/task32-answer.txt вывод sshd -T | grep -i permitrootlogin.
                                                                          sshd -T | grep -i permitrootlogin > /root/task32-answer.txt
T
}
task_32_cleanup() {
  rm -f /etc/ssh/sshd_config.d/*-ld-hardening.conf
  sshd -t >/dev/null 2>&1 && systemctl reload ssh >/dev/null 2>&1
  rm -rf /srv/ld-app /root/task32-answer.txt
  userdel ldapp >/dev/null 2>&1
  groupdel ldapp >/dev/null 2>&1
  true
}
task_32_setup() {
  need_pkg openssh-server; task_32_cleanup
  groupadd -f ldapp
  useradd -r -g ldapp -s /usr/sbin/nologin ldapp 2>/dev/null || true
  install -d -m 755 /srv/ld-app
  install -d -m 777 /srv/ld-app/uploads
  printf 'db_password: Sup3rS3cret!\n' > /srv/ld-app/config.yml
  chmod 666 /srv/ld-app/config.yml
  printf 'заметка от коллеги\n' > /srv/ld-app/uploads/note.txt
  chmod 666 /srv/ld-app/uploads/note.txt                    # ещё один world-writable файл, который надо найти самому
  sshd -t >/dev/null 2>&1
}
task_32_check() {
  check "config.yml: права 640"                    bash -c '[ "$(stat -c %a /srv/ld-app/config.yml 2>/dev/null)" = "640" ]'
  check "config.yml: владелец root:ldapp"           bash -c '[ "$(stat -c %U:%G /srv/ld-app/config.yml 2>/dev/null)" = "root:ldapp" ]'
  check "uploads: права 2770 (SGID)"                bash -c '[ "$(stat -c %a /srv/ld-app/uploads 2>/dev/null)" = "2770" ]'
  check "uploads: владелец ldapp:ldapp"             bash -c '[ "$(stat -c %U:%G /srv/ld-app/uploads 2>/dev/null)" = "ldapp:ldapp" ]'
  check "в /srv/ld-app не осталось world-writable"  bash -c '[ -z "$(find /srv/ld-app -perm -o+w 2>/dev/null)" ]'
  check "drop-in sshd_config.d/NN-ld-hardening.conf есть и sshd -t проходит" bash -c \
    'ls /etc/ssh/sshd_config.d/*-ld-hardening.conf >/dev/null 2>&1 && sshd -t'
  check "sshd -T: permitrootlogin no, passwordauthentication no, maxauthtries 3" bash -c \
    'out=$(sshd -T 2>/dev/null); grep -qx "permitrootlogin no" <<<"$out" && grep -qx "passwordauthentication no" <<<"$out" && grep -qx "maxauthtries 3" <<<"$out"'
  check "task32-answer.txt: permitrootlogin no"     bash -c \
    'tr -d "[:space:]" < /root/task32-answer.txt 2>/dev/null | grep -qi "^permitrootloginno$"'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_13.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_13.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_13.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
