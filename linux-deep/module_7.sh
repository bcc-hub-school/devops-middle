#!/bin/bash
# Linux Deep · Модуль 7 «Storage & Disk Troubleshooting» · задания к занятиям 17–19 (по 5–10 минут, базовые команды)
#
#   curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_7.sh
#
#   bash module_7.sh list                  какие задания есть
#   sudo bash module_7.sh setup task_17    подготовить стенд и показать задание
#   sudo bash module_7.sh check task_17    проверить
#   sudo bash module_7.sh reset task_17    начать заново (стенд пересоздаётся)
#   sudo bash module_7.sh clean task_17    убрать стенд после занятия
#   bash module_7.sh task  task_17     ещё раз показать текст задания
#
# ВНИМАНИЕ: только на учебной ВМ (Ubuntu 24.04). Нужен systemd (обычная ВМ, не контейнер). Стенд создаёт и удаляет сервисы, процессы и файлы.
set -u
TASKS="task_17 task_18 task_19"

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
# task_17 · занятие 17 · использование диска и монтирование
# ====================================================================
task_17_text() { cat <<'T'
Задание 17 (5–10 мин) · диск и монтирование
Стенд создал файл-образ /var/tmp/ld-disk.img (уже отформатирован в ext4) и каталог /var/tmp/ld-junk с «мусором».
  1. Смонтируйте образ в /mnt/ld-data.                                          lsblk -f · losetup -j /var/tmp/ld-disk.img
  2. Узнайте UUID диска и добавьте строку в /etc/fstab: точка /mnt/ld-data,
     тип ext4, опции defaults,nofail, в конце строки — маркер # ld-task17.      blkid /dev/loopX
  3. Проверьте строку без перезагрузки.                                        findmnt --verify · umount /mnt/ld-data && mount -a
  4. В /var/tmp/ld-junk найдите самый большой подкаталог.                      du -xsh /var/tmp/ld-junk/*/ | sort -h
  5. Запишите его имя в /root/task17-answer.txt и сдайте.                      echo имя | sudo tee /root/task17-answer.txt
T
}
task_17_cleanup() {
  mountpoint -q /mnt/ld-data 2>/dev/null && umount /mnt/ld-data 2>/dev/null
  local dev; dev=$(losetup -j /var/tmp/ld-disk.img -O NAME --noheadings 2>/dev/null)
  [ -n "$dev" ] && losetup -d "$dev" 2>/dev/null
  sed -i '/# ld-task17/d' /etc/fstab 2>/dev/null
  rm -f /var/tmp/ld-disk.img /root/task17-answer.txt
  rm -rf /var/tmp/ld-junk /mnt/ld-data
  true
}
task_17_setup() {
  task_17_cleanup
  install -d -m 755 /mnt/ld-data
  dd if=/dev/zero of=/var/tmp/ld-disk.img bs=1M count=64 status=none
  local dev; dev=$(losetup --find --show /var/tmp/ld-disk.img)
  mkfs.ext4 -q "$dev"
  install -d -m 755 /var/tmp/ld-junk/alpha /var/tmp/ld-junk/beta /var/tmp/ld-junk/gamma
  dd if=/dev/zero of=/var/tmp/ld-junk/alpha/file.bin bs=1M count=4  status=none
  dd if=/dev/zero of=/var/tmp/ld-junk/beta/file.bin  bs=1M count=32 status=none
  dd if=/dev/zero of=/var/tmp/ld-junk/gamma/file.bin bs=1M count=12 status=none
  true
}
task_17_check() {
  check "/mnt/ld-data смонтирован файловой системой ext4" \
    bash -c 'findmnt -no FSTYPE /mnt/ld-data 2>/dev/null | grep -qx ext4'
  check "смонтирован именно диск-образ ld-disk.img" \
    bash -c 'want=$(losetup -j /var/tmp/ld-disk.img -O NAME --noheadings 2>/dev/null); have=$(findmnt -no SOURCE /mnt/ld-data 2>/dev/null); [ -n "$want" ] && [ "$want" = "$have" ]'
  check "в /etc/fstab строка по UUID с nofail и маркером # ld-task17" \
    bash -c 'dev=$(losetup -j /var/tmp/ld-disk.img -O NAME --noheadings 2>/dev/null); uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null); [ -n "$uuid" ] && grep -Eq "^UUID=$uuid[[:space:]]+/mnt/ld-data[[:space:]]+ext4[[:space:]]+[^[:space:]]*nofail[^[:space:]]*[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]*# ld-task17" /etc/fstab'
  check "findmnt --verify не находит ошибок в fstab" findmnt --verify
  check "в /root/task17-answer.txt записан самый большой подкаталог" \
    bash -c '[ "$(tr -d "[:space:]" < /root/task17-answer.txt 2>/dev/null)" = "beta" ]'
  summary
}

# ====================================================================
# task_18 · занятие 18 · иноды и fsck
# ====================================================================
task_18_text() { cat <<'T'
Задание 18 (5–10 мин) · иноды и fsck
Стенд создал две отдельные файловые системы через loop-образы: ФС A (мало инодов,
смонтирована в /mnt/ld-inodes, каталог cache/tmp забит файлами) и ФС B (помечена
как «не чисто размонтированная», пока не смонтирована).
  1. Найдите каталог на ФС A, который съел иноды, и удалите его файлы.           df -i /mnt/ld-inodes ·
                                                                                   for d in /mnt/ld-inodes/cache/*; do find $d -xdev|wc -l; done
  2. Освободите не менее половины инодов ФС A.                                   df -i /mnt/ld-inodes
  3. На ФС B fsck -n покажет проблему: найдите устройство и почините его.         losetup -j /var/tmp/ld-badfs.img ·
                                                                                   fsck -n /dev/loopX · fsck -y /dev/loopX
  4. Смонтируйте починенную ФС B в /mnt/ld-fix.                                  mount /dev/loopX /mnt/ld-fix
  5. Запишите общее число инодов ФС A (df -i, столбец Inodes) в /root/task18-answer.txt.
T
}
task_18_cleanup() {
  mountpoint -q /mnt/ld-fix 2>/dev/null && umount /mnt/ld-fix 2>/dev/null
  mountpoint -q /mnt/ld-inodes 2>/dev/null && umount /mnt/ld-inodes 2>/dev/null
  local dev
  dev=$(losetup -j /var/tmp/ld-inodes.img -O NAME --noheadings 2>/dev/null); [ -n "$dev" ] && losetup -d "$dev" 2>/dev/null
  dev=$(losetup -j /var/tmp/ld-badfs.img  -O NAME --noheadings 2>/dev/null); [ -n "$dev" ] && losetup -d "$dev" 2>/dev/null
  rm -f /var/tmp/ld-inodes.img /var/tmp/ld-badfs.img /root/task18-answer.txt
  rm -rf /mnt/ld-inodes /mnt/ld-fix
  true
}
task_18_setup() {
  task_18_cleanup
  install -d -m 755 /mnt/ld-inodes /mnt/ld-fix

  # ФС A: мало инодов, каталог cache/tmp забиваем до отказа
  dd if=/dev/zero of=/var/tmp/ld-inodes.img bs=1M count=64 status=none
  local devA; devA=$(losetup --find --show /var/tmp/ld-inodes.img)
  mkfs.ext4 -q -N 2048 "$devA"
  mount "$devA" /mnt/ld-inodes
  install -d -m 755 /mnt/ld-inodes/cache/tmp
  local i=0
  while : ; do
    printf '' > "/mnt/ld-inodes/cache/tmp/f$i" 2>/dev/null || break
    i=$((i + 1))
  done

  # ФС B: своя, поменьше, помечаем суперблок как «не чисто размонтированный»
  dd if=/dev/zero of=/var/tmp/ld-badfs.img bs=1M count=32 status=none
  local devB; devB=$(losetup --find --show /var/tmp/ld-badfs.img)
  mkfs.ext4 -q -F "$devB"
  debugfs -w -R "ssv state 0" "$devB" >/dev/null 2>&1
  true
}
task_18_check() {
  check "на ФС A освобождено не менее половины инодов" \
    bash -c 'read f t < <(df --output=iavail,itotal /mnt/ld-inodes 2>/dev/null | tail -1); [ -n "$t" ] && [ "$t" -gt 0 ] && awk -v f="$f" -v t="$t" "BEGIN{exit !(f/t>=0.5)}"'
  check "каталог cache/tmp вычищен (не забит мусором)" \
    bash -c '[ "$(find /mnt/ld-inodes/cache/tmp -type f 2>/dev/null | wc -l)" -lt 200 ]'
  check "ФС B починена: tune2fs -l показывает Filesystem state: clean" \
    bash -c 'dev=$(losetup -j /var/tmp/ld-badfs.img -O NAME --noheadings 2>/dev/null); [ -n "$dev" ] && tune2fs -l "$dev" 2>/dev/null | awk -F: "/^Filesystem state/{gsub(/^[ \t]+/,\"\",\$2); exit (\$2==\"clean\")?0:1}"'
  check "починенная ФС B смонтирована в /mnt/ld-fix" \
    bash -c 'want=$(losetup -j /var/tmp/ld-badfs.img -O NAME --noheadings 2>/dev/null); have=$(findmnt -no SOURCE /mnt/ld-fix 2>/dev/null); [ -n "$want" ] && [ "$want" = "$have" ] && [ "$(findmnt -no FSTYPE /mnt/ld-fix 2>/dev/null)" = ext4 ]'
  check "в /root/task18-answer.txt записано общее число инодов ФС A" \
    bash -c 'want=$(df --output=itotal /mnt/ld-inodes 2>/dev/null | tail -1 | tr -d "[:space:]"); have=$(tr -d "[:space:]" < /root/task18-answer.txt 2>/dev/null); [ -n "$want" ] && [ "$want" = "$have" ]'
  summary
}

# ====================================================================
# task_19 · занятие 19 · LVM basics
# ====================================================================
task_19_text() {
  local devs d1 d2
  devs=$(cat /opt/ld-tasks/task19/devices 2>/dev/null)
  d1=$(printf '%s\n' "$devs" | sed -n 1p); d2=$(printf '%s\n' "$devs" | sed -n 2p)
  cat <<T
Задание 19 (5–10 мин) · LVM basics
Стенд подготовил два пустых loop-устройства: $d1 и $d2 (пул на 512M вместе).
  1. Создайте физические тома на обоих устройствах.                          pvcreate $d1 $d2
  2. Объедините их в группу ldvg.                                             vgcreate ldvg $d1 $d2
  3. Создайте том data на 200M, отформатируйте в ext4                        lvcreate -L 200M -n data ldvg
     и смонтируйте в /mnt/ld-lvm.                                             mkfs.ext4 /dev/ldvg/data · mount
  4. Расширьте том на +100M вместе с файловой системой,                      lvextend -L +100M -r /dev/ldvg/data
     не размонтируя его.
  5. Запишите итоговый размер тома в /root/task19-answer.txt и сдайте.       lvs --noheadings -o lv_size ldvg/data
T
}
task_19_cleanup() {
  mountpoint -q /mnt/ld-lvm 2>/dev/null && umount /mnt/ld-lvm 2>/dev/null
  lvremove -f /dev/ldvg/data >/dev/null 2>&1
  vgremove -f ldvg >/dev/null 2>&1
  local f dev
  for f in /var/tmp/ld-lvm-1.img /var/tmp/ld-lvm-2.img; do
    dev=$(losetup -j "$f" -O NAME --noheadings 2>/dev/null | tr -d '[:space:]')
    [ -n "$dev" ] && pvremove -ff -y "$dev" >/dev/null 2>&1
    [ -n "$dev" ] && losetup -d "$dev" >/dev/null 2>&1
  done
  rm -f /var/tmp/ld-lvm-1.img /var/tmp/ld-lvm-2.img /root/task19-answer.txt
  rm -rf /opt/ld-tasks/task19 /mnt/ld-lvm
  true
}
task_19_setup() {
  need_pkg lvm2
  task_19_cleanup
  install -d -m 755 /opt/ld-tasks/task19
  dd if=/dev/zero of=/var/tmp/ld-lvm-1.img bs=1M count=256 status=none
  dd if=/dev/zero of=/var/tmp/ld-lvm-2.img bs=1M count=256 status=none
  local l1 l2
  l1=$(losetup --find --show /var/tmp/ld-lvm-1.img)
  l2=$(losetup --find --show /var/tmp/ld-lvm-2.img)
  printf '%s\n%s\n' "$l1" "$l2" > /opt/ld-tasks/task19/devices
  true
}
task_19_check() {
  check "PV созданы на обоих loop-устройствах стенда" bash -c '
    f1=/var/tmp/ld-lvm-1.img; f2=/var/tmp/ld-lvm-2.img
    d1=$(losetup -j "$f1" -O NAME --noheadings 2>/dev/null | tr -d "[:space:]")
    d2=$(losetup -j "$f2" -O NAME --noheadings 2>/dev/null | tr -d "[:space:]")
    [ -n "$d1" ] && [ -n "$d2" ] || exit 1
    list=$(pvs --noheadings -o pv_name 2>/dev/null | sed "s/^[[:space:]]*//;s/[[:space:]]*\$//")
    printf "%s\n" "$list" | grep -qx "$d1" && printf "%s\n" "$list" | grep -qx "$d2"'
  check "группа ldvg объединяет оба физических тома" bash -c '
    vgs --noheadings -o vg_name 2>/dev/null | grep -qw ldvg || exit 1
    n=$(pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk "\$NF==\"ldvg\"{c++} END{print c+0}")
    [ "$n" -ge 2 ]'
  check "том data ≥ 290M и смонтирован в /mnt/ld-lvm" bash -c '
    findmnt -no SOURCE /mnt/ld-lvm 2>/dev/null | grep -Eq "ldvg-data|/dev/ldvg/data" || exit 1
    sz=$(lvs --noheadings --units m --nosuffix -o lv_size ldvg/data 2>/dev/null | tr -d "[:space:]")
    awk -v s="$sz" "BEGIN{exit !(s+0>=290)}"'
  check "файловая система на томе расширена (df ≥ 250M)" bash -c '
    sz=$(df -m --output=size /mnt/ld-lvm 2>/dev/null | tail -1 | tr -d "[:space:]")
    [ -n "$sz" ] && [ "$sz" -ge 250 ]'
  check "в /root/task19-answer.txt записан итоговый размер тома" bash -c '
    want=$(lvs --noheadings -o lv_size ldvg/data 2>/dev/null | tr -d "[:space:]")
    have=$(tr -d "[:space:]" < /root/task19-answer.txt 2>/dev/null)
    [ -n "$want" ] && [ "$want" = "$have" ]'
  summary
}

# ---------- диспетчер ----------
usage() { echo "Использование: [sudo] bash module_7.sh <list|task|setup|check|reset|clean> [task_N]"; echo "Задания: $TASKS"; }
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
  [ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo bash module_7.sh $action $t" >&2; return 1; }
  grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || echo "Предупреждение: проверено на Ubuntu 24.04, у вас другая система." >&2
  case "$action" in
    setup|reset) "${t}_setup" </dev/null || { echo "Ошибка подготовки стенда" >&2; return 1; }
                 echo "Стенд готов."; echo; "${t}_text"; echo; echo "Проверка: sudo bash module_7.sh check $t" ;;
    check)       "${t}_check" </dev/null ;;
    clean)       "${t}_cleanup" </dev/null; echo "Стенд $t убран." ;;
  esac
}
main "$@"   # вызов последней строкой: оборванная загрузка ничего не выполнит
