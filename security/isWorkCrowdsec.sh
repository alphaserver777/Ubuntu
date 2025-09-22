#!/bin/bash

# Функция для вывода заголовка
function print_header {
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Проверка статуса CrowdSec
print_header "Проверка статуса CrowdSec"
sudo systemctl status crowdsec

# Проверка логов
print_header "Проверка логов CrowdSec"
sudo journalctl -u crowdsec -n 20 --no-pager

# Проверка конфигурации
print_header "Проверка конфигурации CrowdSec"
cat /etc/crowdsec/config.yaml | head -n 20

# Проверка сценариев
print_header "Проверка сценариев CrowdSec"
sudo cscli scenarios list

# Проверка решений
print_header "Проверка решений CrowdSec"
sudo cscli decisions list

# Проверка iptables (если используется)
print_header "Проверка правил iptables"
sudo iptables -L

# Проверка nftables (если используется)
print_header "Проверка правил nftables"
sudo nft list ruleset

# Проверка обновлений
#print_header "Проверка обновлений CrowdSec"
#sudo apt update && sudo apt list --upgradable | grep crowdsec

echo "Проверка завершена."
