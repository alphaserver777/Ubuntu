#!/usr/bin/env python3
import datetime as dt
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(SCRIPT_DIR, '.env')
SERVICE_LOG_FILE = '/var/log/important/telegram-ssh-forwarder.log'
LOG_FILES = [
    '/var/log/important/ssh-success.log',
    '/var/log/important/auth.log',
]

PATTERNS = [
    {
        'name': 'Accepted',
        'emoji': '🔓',
        'regex': re.compile(r'^(?P<ts>\S+)\s+(?P<server_ip>\S+)\s+(?P<server_name>\S+)\s+sshd(?:\[\d+\])?:\s+Accepted\s+(?P<auth_type>\w+)\s+for\s+(?P<username>\S+)\s+from\s+(?P<client_ip>\S+)\s+port\s+(?P<port>\d+)')
    },
    {
        'name': 'Failed',
        'emoji': '❌',
        'regex': re.compile(r'^(?P<ts>\S+)\s+(?P<server_ip>\S+)\s+(?P<server_name>\S+)\s+sshd(?:\[\d+\])?:\s+Failed\s+password\s+for\s+(?:invalid user\s+)?(?P<username>\S+)\s+from\s+(?P<client_ip>\S+)\s+port\s+(?P<port>\d+)')
    },
    {
        'name': 'SessionOpened',
        'emoji': '🔓',
        'regex': re.compile(r'^(?P<ts>\S+)\s+(?P<server_ip>\S+)\s+(?P<server_name>\S+)\s+.*session opened for user (?P<username>\S+)')
    },
    {
        'name': 'SessionClosed',
        'emoji': '🚪',
        'regex': re.compile(r'^(?P<ts>\S+)\s+(?P<server_ip>\S+)\s+(?P<server_name>\S+)\s+.*session closed for user (?P<username>\S+)')
    },
]


def load_env_file(path):
    data = {}
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                if line.startswith('export '):
                    line = line[len('export '):]
                k, v = line.split('=', 1)
                data[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return data


def load_config():
    return load_env_file(ENV_FILE)


def service_log(message, *, error=False):
    ts = dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S%z')
    level = 'ERROR' if error else 'INFO'
    line = f'{ts} [{level}] {message}'
    try:
        with open(SERVICE_LOG_FILE, 'a', encoding='utf-8') as f:
            f.write(line + '\n')
    except Exception:
        pass
    print(line, file=sys.stderr if error else sys.stdout, flush=True)


def fmt_time(iso_ts):
    try:
        return dt.datetime.fromisoformat(iso_ts).strftime('%b %d %H:%M:%S')
    except Exception:
        return iso_ts


def parse_event(line):
    for p in PATTERNS:
        m = p['regex'].search(line)
        if not m:
            continue
        g = m.groupdict()
        status = p['name']
        auth_type = g.get('auth_type', 'N/A')
        if status == 'Failed' and auth_type == 'N/A':
            auth_type = 'password'
        return {
            'emoji': p['emoji'],
            'time': fmt_time(g.get('ts', 'N/A')),
            'status': status,
            'server_name': g.get('server_name', 'N/A'),
            'server_ip': g.get('server_ip', 'N/A'),
            'username': g.get('username', 'N/A'),
            'client_ip': g.get('client_ip', 'N/A'),
            'auth_type': auth_type,
            'port': g.get('port', 'N/A'),
            'details': line,
        }
    return None


def format_message(ev):
    return (
        f"{ev['emoji']} Новое событие SSH:\n"
        f"⏰ Время: {ev['time']}\n"
        f"🖥️ Сервер: {ev['server_name']}\n"
        f"📡 IP сервера: {ev['server_ip']}\n"
        f"🔑 Статус: {ev['status']}\n"
        f"👨 User: {ev['username']}\n"
        f"🌍 IP: {ev['client_ip']}\n"
        f"🔒 Метод: {ev['auth_type']}\n"
        f"🔌 Порт: {ev['port']}\n"
        f"ℹ️ Подробности: {ev['details']}"
    )


def send_telegram(bot_token, chat_id, api_base, text):
    url = f"{api_base}/bot{bot_token}/sendMessage"
    payload = urllib.parse.urlencode({
        'chat_id': chat_id,
        'text': text,
        'disable_web_page_preview': 'true',
    }).encode('utf-8')
    req = urllib.request.Request(url, data=payload, method='POST')
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def main():
    cfg = load_config()
    bot_token = cfg.get('BOT_TOKEN', '')
    chat_id = cfg.get('CHAT_ID', '')
    api_base = cfg.get('API_BASE', 'https://api.telegram.org')

    if not bot_token or not chat_id:
        service_log('BOT_TOKEN/CHAT_ID not set in .env', error=True)
        return 1

    service_log(f'service started; watching files: {", ".join(LOG_FILES)}')
    cmd = ['tail', '-n', '0', '-F'] + LOG_FILES
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)

    try:
        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.strip()
            if not line or line.startswith('==>'):
                continue
            ev = parse_event(line)
            if not ev:
                continue
            service_log(
                f'event matched status={ev["status"]} server={ev["server_name"]} '
                f'user={ev["username"]} client_ip={ev["client_ip"]}'
            )
            msg = format_message(ev)
            try:
                send_telegram(bot_token, chat_id, api_base, msg)
                service_log(
                    f'telegram sent status={ev["status"]} server={ev["server_name"]} '
                    f'user={ev["username"]} client_ip={ev["client_ip"]}'
                )
            except Exception as e:
                service_log(f'telegram send failed: {e}', error=True)
    finally:
        proc.terminate()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
