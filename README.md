# devops-middle

Скрипты заданий курсов DevOps уровня middle.

## linux-deep

Курс «Linux Deep» — 13 модулей, 32 занятия. На каждое занятие одно короткое задание (5–10 минут). Задания собраны в скрипт модуля `linux-deep/module_N.sh`.

### Как пользоваться

```bash
curl -fsSLO https://raw.githubusercontent.com/bcc-hub-school/devops-middle/main/linux-deep/module_1.sh

bash module_1.sh list              # список заданий модуля
bash module_1.sh task task_1       # текст задания
sudo bash module_1.sh setup task_1 # развернуть стенд
sudo bash module_1.sh check task_1 # проверить решение
sudo bash module_1.sh reset task_1 # начать заново (стенд пересоздаётся)
sudo bash module_1.sh clean task_1 # убрать стенд после занятия
```

### Что нужно

- Одноразовая ВМ Ubuntu 24.04 с `systemd` и `sudo` (не контейнер — часть заданий поднимает юниты, loop-устройства, netns).
- Интернет для `apt` (скрипты сами доставляют недостающие пакеты; задание 3 — про `apt`).
- Модули 7 и 10 создают образы дисков в `/var/tmp` (до ~1 ГБ суммарно), `clean` их удаляет.

> **Внимание.** Скрипты меняют систему: создают пользователей, юниты, loop-устройства, network namespaces, правила sudo и nftables. Запускать только на одноразовой учебной ВМ (Ubuntu 24.04), не на рабочей машине. `clean` убирает стенд занятия, `reset` пересоздаёт его.

### Модули и задания

| Модуль | Скрипт | Занятия | Задания |
|---|---|---|---|
| 1 · Linux Fundamentals | `module_1.sh` | 1–3 | task_1 FHS · task_2 пользователи, права, ACL, sudo · task_3 пакеты |
| 2 · Процессы и systemd | `module_2.sh` | 4–6 | task_4 процессы и сигналы · task_5 systemd · task_6 cron и timers |
| 3 · Логи | `module_3.sh` | 7–8 | task_7 journald · task_8 logrotate |
| 4 · Производительность | `module_4.sh` | 9–11 | task_9 мониторинг ресурсов · task_10 узкие места и load average · task_11 сервер тормозит |
| 5 · Сеть и диагностика | `module_5.sh` | 12–14 | task_12 сеть и SSH · task_13 DNS и strace · task_14 путь пакета |
| 6 · Ядро и изоляция | `module_6.sh` | 15–16 | task_15 sysctl и ulimits · task_16 cgroups и namespaces |
| 7 · Диски и файловые системы | `module_7.sh` | 17–19 | task_17 диск и монтирование · task_18 иноды и fsck · task_19 LVM basics |
| 8 · Bash и автоматизация | `module_8.sh` | 20–21 | task_20 скрипт проверки юнитов · task_21 обработка ошибок |
| 9 · Разбор инцидентов | `module_9.sh` | 22–24 | task_22 сервис и CPU · task_23 память и диск · task_24 сеть и SSH |
| 10 · Загрузка и восстановление | `module_10.sh` | 25–26 | task_25 загрузка и rescue · task_26 восстановление системы |
| 11 · Сеть: маршрутизация и фильтр | `module_11.sh` | 27–28 | task_27 маршрут, ARP, ip_forward · task_28 nftables и netns |
| 12 · Наблюдаемость | `module_12.sh` | 29–30 | task_29 корреляция логов и метрик · task_30 поиск узкого места |
| 13 · Безопасность | `module_13.sh` | 31–32 | task_31 группы и sudoers · task_32 права и SSH hardening |

Модули 4–13 разворачивают стенды с loop-устройствами, cgroups, network namespaces и правкой sudoers — им нужен root и одноразовая ВМ.
