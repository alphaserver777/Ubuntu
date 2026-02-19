# Централизованный сбор логов (Germany)

## Что сделано

Сейчас используется центральный сервер `Germany` как приемник важных логов от:
- `Germany` (локальные события)
- `x-disk` (NixOS клиент)
- `zomro` (Ubuntu клиент)
- `uk-vpn` (Ubuntu клиент, включая Docker)
- `france` / другие подключенные хосты (по той же схеме)

Логи пишутся в единый каталог:
- `/var/log/important`

Без деления на `remote-*` и `local-*`: все события в общих файлах, источник определяется по полям хоста/IP в строке.

---

## Стандарт формата логов

Для `important`-логов на `Germany` используется единый формат времени:
- `RFC3339`
- пример: `2026-02-19T16:55:06.131639+03:00`

Шаблон записи в `rsyslog`:

```rsyslog
template(name="ImportantFmt" type="string"
  string="%timegenerated:::date-rfc3339% %fromhost-ip% %HOSTNAME% %syslogtag%%msg%\n")
```

Это сделано для:
- корректной сортировки по времени в `lnav`
- удобной корреляции событий между серверами
- стабильного машинного парсинга

---

## Какие файлы логов ведутся на Germany

- `/var/log/important/auth.log`  
  Auth/Authpriv события (`warning` и выше)
- `/var/log/important/kernel.log`  
  `kern` события (`warning` и выше)
- `/var/log/important/systemd-fail.log`  
  Падения/ошибки systemd unit'ов по шаблонам
- `/var/log/important/ssh-success.log`  
  Успешные SSH-входы (`Accepted ...`)
- `/var/log/important/libvirt-events.log`  
  События жизненного цикла VM (libvirt hook)
- `/var/log/important/docker-containers.log`  
  Логи контейнеров Docker (через syslog-драйвер)
- `/var/log/important/dockerd.log`  
  События демона Docker
- `/var/log/important/critical.log`  
  Глобальные `critical/alert/emergency`
- `/var/log/important/telegram-ssh-forwarder.log`  
  Сервис отправки SSH-алертов в Telegram (служебный лог)

---

## Как устроен сбор (pipeline)

1. На клиентах (`x-disk`, `zomro`, `uk-vpn`, и т.д.) `rsyslog` фильтрует важные события.
2. Клиенты пересылают их на `Germany` по TCP/514 (`omfwd`).
3. На `Germany` включен прием TCP syslog (`imtcp`).
4. На `Germany` правила маршрутизируют события в файлы `/var/log/important/*.log`.
5. Отдельный Python-сервис читает `ssh-success.log` и шлет алерты в Telegram.

---

## Ключевые конфиги

### Germany
- `/etc/rsyslog.d/11-remote-receive.conf`  
  Включение приема TCP:
  ```rsyslog
  module(load="imtcp")
  input(type="imtcp" port="514")
  ```
- `/etc/rsyslog.d/10-important.conf`  
  Основная маршрутизация в `/var/log/important/*` + единый шаблон `ImportantFmt`.

### x-disk (NixOS)
- Модуль: `nixos-config/nixos/modules/rsyslog-forwarding.nix`
- Используются очереди `linkedList`, дисковый буфер, бесконечный retry:
  - `action.resumeRetryCount="-1"`
  - `queue.maxDiskSpace="1g"`
  - `queue.saveOnShutdown="on"`
  - `global(workDirectory="/var/spool/rsyslog")`

Это обеспечивает устойчивость при сетевых сбоях (логи не теряются при краткосрочном обрыве связи).

---

## Как определяется, в какой файл писать событие

Решает **только сервер Germany** по своим правилам `rsyslog`:
- по `facility` (`auth/authpriv`, `kern`)
- по `severity`
- по `programname` (`sshd`, `systemd`, `dockerd`, `docker-container`, `libvirt-hook`)
- по содержимому сообщения (`Accepted`, `Failed with result`, и т.п.)

Клиент определяет только:
- какие события отправлять
- куда отправлять (`Germany:514/tcp`)

Окончательная классификация/запись в файл — на стороне приемника (`Germany`).

---

## Проверка работы

### Проверка пересылки с клиента
```bash
logger -p authpriv.err "XDISK_FORWARD_TEST auth"
logger -p user.crit "XDISK_FORWARD_TEST crit"
```

На `Germany`:
```bash
grep -Rsn "XDISK_FORWARD_TEST" /var/log/important
```

### Проверка SSH успехов
```bash
tail -n 50 /var/log/important/ssh-success.log
```

### Проверка сервиса Telegram-алертов
```bash
tail -n 100 /var/log/important/telegram-ssh-forwarder.log
```

---

## Важные замечания

- Если в одном файле смешаны старые строки с разными форматами времени, `lnav` может отображать их неидеально.
- После унификации формата лучше сделать ротацию/очистку конкретного файла (с бэкапом), чтобы остался один формат.
- Если `docker-containers.log` пустой — проверьте, что контейнеры реально запущены и имеют `log-driver=syslog` или настроенную пересылку в syslog.
