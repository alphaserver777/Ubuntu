#!/usr/bin/env bash
set -e

# Скрипт установки SSH-сервера + вывод IP-адресов

# 1. Обновление списка пакетов
sudo apt update

# 2. Установка OpenSSH Server
sudo apt install -y openssh-server

# 3. Включить и запустить службу ssh
sudo systemctl enable ssh
sudo systemctl restart ssh

# 4. Разрешить SSH в UFW
#if command -v ufw >/dev/null 2>&1; then
#  sudo ufw allow OpenSSH || sudo ufw allow 22/tcp
#fi

echo "=========================================="
echo "SSH установлен и запущен успешно!"
echo "Статус службы:"
systemctl status ssh --no-pager -l
echo ""
echo "IP-адреса системы:"
echo "-------------------"
ip -4 addr show | grep inet | awk '{print $2}' | cut -d'/' -f1
echo ""
echo "Подробно по интерфейсам:"
ip addr show | grep -E '^[0-9]:.*inet ' | grep -v 127.0.0.1
echo ""
echo "Для подключения SSH используй: ssh user@IP_АДРЕС"
echo "=========================================="
