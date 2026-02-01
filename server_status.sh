#!/bin/bash

# --- Настройки цветов ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Принудительная локаль
export LC_ALL=C

# --- Функции ---
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
}

print_info() {
    printf "${CYAN}%-25s${NC} : %s\n" "$1" "$2"
}

# Очистка экрана
clear
echo -e "${BOLD}${GREEN}"
echo "   ULTIMATE SERVER AUDIT   "
echo -e "${NC}"
date

# ==============================================
# 1. СИСТЕМА И РЕСУРСЫ
# ==============================================
print_header "1. СИСТЕМА И ЗДОРОВЬЕ"
HOSTNAME=$(hostname)
OS=$(lsb_release -d 2>/dev/null | cut -f2 | xargs) || OS=$(cat /etc/*release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

print_info "Hostname" "$HOSTNAME"
print_info "OS" "$OS"
print_info "Uptime" "$UPTIME"
print_info "Load Average" "$LOAD"

# Проверка OOM (Out of Memory) убийств в логах
OOM_CHECK=$(grep -i "killed process" /var/log/syslog 2>/dev/null | tail -n 1)
if [ -n "$OOM_CHECK" ]; then
    echo -e "${RED}WARNING: OOM Killer detected recently!${NC}"
    echo "Last kill: $OOM_CHECK"
else
    print_info "OOM Killer Status" "${GREEN}No recent kills detected${NC}"
fi

# Проверка упавших сервисов
FAILED_SERVICES=$(systemctl list-units --state=failed --no-legend --plain)
if [ -n "$FAILED_SERVICES" ]; then
    echo -e "${RED}FAILED SYSTEMD SERVICES:${NC}"
    echo "$FAILED_SERVICES"
else
    print_info "System Services" "${GREEN}All services healthy${NC}"
fi

# ==============================================
# 2. ПАМЯТЬ И ДИСКИ
# ==============================================
print_header "2. ПАМЯТЬ И ДИСК"
# RAM
FREE_DATA=$(free -m | grep "Mem:")
MEM_TOTAL=$(echo "$FREE_DATA" | awk '{print $2}')
MEM_USED=$(echo "$FREE_DATA" | awk '{print $3}')
[ -z "$MEM_TOTAL" ] && MEM_TOTAL=1
MEM_PERC=$(awk "BEGIN {printf \"%.0f\", ($MEM_USED/$MEM_TOTAL)*100}")

if [ "$MEM_PERC" -ge 85 ]; then M_COL=$RED; elif [ "$MEM_PERC" -ge 50 ]; then M_COL=$YELLOW; else M_COL=$GREEN; fi
printf "${CYAN}%-25s${NC} : ${M_COL}%s%%${NC} (%sMB / %sMB)\n" "RAM Usage" "$MEM_PERC" "$MEM_USED" "$MEM_TOTAL"

# DISK
df -hP | grep -vE '^Filesystem|tmpfs|cdrom|loop|udev' | awk '{printf "%-25s : %s / %s (%s)\n", $6, $3, $2, $5}'

# ==============================================
# 3. СЕТЬ И БЕЗОПАСНОСТЬ
# ==============================================
print_header "3. СЕТЬ И FIREWALL"

# IP
ip -4 addr | grep inet | grep -v "127.0.0.1" | awk '{print $2 " (" $NF ")"}' | while read line; do
   print_info "Internal IP" "$line"
done

# Внешний IP
if command -v curl &> /dev/null; then
    EXT_IP=$(curl -s --connect-timeout 2 ifconfig.me)
    [ ! -z "$EXT_IP" ] && print_info "External IP" "$EXT_IP"
fi

echo ""
# UFW Status
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | grep "Status" | awk '{print $2}')
    if [ "$UFW_STATUS" == "active" ]; then
        print_info "Firewall (UFW)" "${GREEN}ACTIVE${NC}"
        echo -e "${BOLD}Open Rules:${NC}"
        sudo ufw status numbered | head -n 10
    else
        print_info "Firewall (UFW)" "${RED}INACTIVE${NC}"
    fi
else
    print_info "Firewall" "UFW not installed"
fi

# ==============================================
# 4. ОТКРЫТЫЕ ПОРТЫ
# ==============================================
print_header "4. СЛУШАЮЩИЕ ПОРТЫ (Listening)"
# Показывает TCP порты, которые слушает сервер
if command -v ss &> /dev/null; then
    echo -e "${BOLD}Port  Process${NC}"
    sudo ss -tulnp | grep LISTEN | awk '{print $5, $7}' | sed 's/users:(("//g' | sed 's/".*//g' | sort -u | column -t
else
    echo "ss command not found"
fi

# ==============================================
# 5. SSH КОНФИГУРАЦИЯ
# ==============================================
print_header "5. SSH AUDIT"
SSH_CONF="/etc/ssh/sshd_config"
if [ -r "$SSH_CONF" ]; then
    PORT=$(grep -E "^Port " $SSH_CONF | awk '{print $2}')
    ROOT=$(grep -E "^PermitRootLogin " $SSH_CONF | awk '{print $2}')
    PASS=$(grep -E "^PasswordAuthentication " $SSH_CONF | awk '{print $2}')
    
    [ -z "$PORT" ] && PORT="22 (Default)"
    [ -z "$ROOT" ] && ROOT="prohibit-password (Default)"
    
    print_info "SSH Port" "$PORT"
    
    if [[ "$ROOT" == "no" || "$ROOT" == "prohibit-password" ]]; then 
        print_info "Root Login" "${GREEN}$ROOT${NC}"
    else 
        print_info "Root Login" "${RED}$ROOT${NC}"
    fi

    if [[ "$PASS" == "no" ]]; then 
        print_info "Password Auth" "${GREEN}DISABLED (Secure)${NC}"
    else 
        print_info "Password Auth" "${YELLOW}ENABLED${NC}"
    fi
else
    echo "Cannot read sshd_config (Run with sudo)"
fi

# ==============================================
# 6. DOCKER (Если есть)
# ==============================================
if command -v docker &> /dev/null; then
    print_header "6. DOCKER CONTAINERS"
    if sudo docker info >/dev/null 2>&1; then
        RUNNING=$(sudo docker ps -q | wc -l)
        TOTAL=$(sudo docker ps -aq | wc -l)
        print_info "Containers" "${GREEN}$RUNNING running${NC} / $TOTAL total"
        if [ "$RUNNING" -gt 0 ]; then
            echo -e "\n${BOLD}Running Containers:${NC}"
            sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | awk 'NR>1 {print $0}' | head -n 5
        fi
    else
        echo "Docker installed but daemon not accessible (permission denied?)"
    fi
fi

# ==============================================
# 7. ПОСЛЕДНЯЯ АКТИВНОСТЬ
# ==============================================
print_header "7. ПОСЛЕДНИЕ ВХОДЫ (Last 3)"
last -n 3 -a | head -n 3 | awk '{printf "%-10s %-10s %-20s %s\n", $1, $2, $3, $NF}'

echo -e "\n${BOLD}${GREEN}=== Готово ===${NC}\n"
