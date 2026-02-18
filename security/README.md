# SSH Telegram Alerts

Скрипт `alert_ssh.py` читает SSH-события из:
- `/var/log/important/ssh-success.log`
- `/var/log/important/auth.log`

И отправляет уведомления в Telegram в читаемом формате.

## 1) Настройка `.env`

Создайте файл `.env` рядом со скриптом:

```bash
cp .env.example .env
```

Заполните значения:

```env
BOT_TOKEN="..."
CHAT_ID="..."
API_BASE="https://api.telegram.org"
```

`BOT_TOKEN` и `CHAT_ID` обязательны.

## 2) Ручной запуск

```bash
python3 alert_ssh.py
```

Остановка: `Ctrl+C`.

## 3) Запуск как systemd service

Пример юнита (`/etc/systemd/system/telegram-ssh-forwarder.service`):

```ini
[Unit]
Description=SSH alerts to Telegram
After=network-online.target rsyslog.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/admsys/work/Ubuntu/security
ExecStart=/usr/bin/python3 /home/admsys/work/Ubuntu/security/alert_ssh.py
Restart=always
RestartSec=2
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Применение:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now telegram-ssh-forwarder.service
sudo systemctl status telegram-ssh-forwarder.service
```
