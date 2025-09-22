import re
import sys
import subprocess
import requests
import logging
from datetime import datetime

# Конфигурация Telegram
TELEGRAM_TOKEN = '7096335364:AAEhZiJzIeW3SZ3gkyj0wtgKX1ons6DM0uI'
CHAT_ID = '1864831807'

# Путь к лог-файлу SSH
LOG_FILE = '/var/log/auth.log'
LOG_FILENAME = '/var/log/ssh_monitor.log'

# Настройка логирования
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')

class SSHEvent:
    def __init__(self, time_str, username, client_ip, port, status, auth_type, details=""):
        self.time = time_str.strip()
        self.username = username.strip()
        self.client_ip = client_ip.strip()
        self.port = port.strip()
        self.status = status.strip()
        self.auth_type = auth_type.strip()
        self.details = details.strip()

    def __str__(self):
        return (f"SSH Event:\n"
                f"Time: {self.time}\n"
                f"Username: {self.username}\n"
                f"IP: {self.client_ip}\n"
                f"Port: {self.port}\n"
                f"Status: {self.status}\n"
                f"Auth Type: {self.auth_type}\n"
                f"Details: {self.details}\n")


def send_telegram_message(event: SSHEvent):
    emoji_map = {
        "Accepted": "✅",
        "Failed": "❌",
        "Invalid": "⚠️",
        "Closed": "🚪",
        "Disconnected": "🔌",
        "AuthFailure": "🔒",
        "SessionOpened": "🔓",
        "SessionClosed": "🚪",
        "Error": "❗"
    }
    emoji = emoji_map.get(event.status, "⚠️")
    
    message = (f"{emoji} Новое событие SSH:\n"
               f"⏰ Время: {event.time}\n"
               f"🔑 Статус: {event.status}\n"
               f"👨 User: {event.username}\n"
               f"🌍 IP: {event.client_ip}\n"
               f"🔒 Метод: {event.auth_type}\n"
               f"🔌 Порт: {event.port}\n"
               f"ℹ️ Подробности: {event.details}")
    
    try:
        response = requests.get(
            f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
            params={'chat_id': CHAT_ID, 'text': message, 'parse_mode': 'HTML'},
            timeout=10
        )
        if response.ok:
            logging.info(f"✅ Уведомление успешно отправлено: {event.time} | {event.status}")
        else:
            logging.error(f"❌ Ошибка отправки уведомления: {response.status_code} - {response.text}")
    except requests.exceptions.RequestException as e:
        logging.error(f"❌ Ошибка соединения с Telegram: {str(e)}")


def parse_ssh_line(line: str) -> SSHEvent or None:
    line = line.strip().replace('\t', ' ').replace('  ', ' ')
    
    patterns = [
        {  # Успешный вход
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* sshd\[\d+\]: Accepted (?P<auth_type>\w+) for (?P<username>\S+) from (?P<client_ip>\S+) port (?P<port>\d+)'),
            'status': 'Accepted'
        },
        {  # Неудачный вход
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* sshd\[\d+\]: Failed password for (invalid user )?(?P<username>\S+) from (?P<client_ip>\S+) port (?P<port>\d+)'),
            'status': 'Failed'
        },
        {  # Сессия открыта
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* pam_unix\(sshd:session\): session opened for user (?P<username>\S+)'),
            'status': 'SessionOpened',
            'auth_type': 'PAM'
        },
        {  # Сессия закрыта
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* pam_unix\(sshd:session\): session closed for user (?P<username>\S+)'),
            'status': 'SessionClosed',
            'auth_type': 'PAM'
        },
        {  # Новый сеанс systemd-logind
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* systemd-logind\[\d+\]: New session \d+ of user (?P<username>\S+)'),
            'status': 'SessionOpened'
        },
        {  # Сессия закрыта systemd-logind
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* systemd-logind\[\d+\]: Session \d+ logged out. Waiting for processes to exit.'),
            'status': 'SessionClosed'
        },
        {  # Отключение клиента
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* sshd\[\d+\]: Received disconnect from (?P<client_ip>\S+) port (?P<port>\d+):'),
            'status': 'Disconnected'
        },
        {  # Ошибки SSH
            'pattern': re.compile(r'(?P<time>\w+ \d+ \d+:\d+:\d+) .* sshd\[\d+\]: error: (?P<details>.+)'),
            'status': 'Error'
        }
    ]

    for rule in patterns:
        match = rule['pattern'].search(line)
        if match:
            groups = match.groupdict()
            return SSHEvent(
                time_str=groups['time'],
                username=groups.get('username', 'N/A'),
                client_ip=groups.get('client_ip', 'N/A'),
                port=groups.get('port', 'N/A'),
                status=rule['status'],
                auth_type=rule.get('auth_type', 'N/A'),
                details=line
            )
    
    logging.warning(f"⚠️ Не распознана строка: {line}")
    return None


def follow_log_file(log_file: str):
    try:
        logging.info(f"Начало отслеживания файла: {log_file}")
        process = subprocess.Popen(['tail', '-n', '0', '-F', log_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        
        for line in iter(process.stdout.readline, ''):
            yield line.strip()
    except KeyboardInterrupt:
        process.terminate()
        logging.info("Скрипт остановлен пользователем")
        sys.exit(0)
    except Exception as e:
        logging.critical(f"Критическая ошибка: {str(e)}")
        sys.exit(1)


def main():
    logging.info("🚀 Скрипт SSH Monitor запущен")
    for line in follow_log_file(LOG_FILE):
        event = parse_ssh_line(line)
        if event:
            logging.info(f"Обработано событие: {event.time} | {event.status}")
            send_telegram_message(event)

if __name__ == "__main__":
    main()