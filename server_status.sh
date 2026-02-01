#!/bin/bash

# --- Настройки цветов ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Принудительная локаль для команд парсинга
export LC_ALL=C

# --- Функции оформления ---
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
}

print_info() {
    printf "${CYAN}%-25s${NC} : %s\n" "$1" "$2"
}

print_status() {
    # $1 = Label, $2 = Value (yes/active), $3 = Desired state
    local COLOR=$RED
    if [[ "$2" == "$3" ]]; then COLOR=$GREEN; fi
    printf "${CYAN}%-25s${NC} : ${COLOR}%s${NC}\n" "$1" "$2"
}

clear
echo -e "${BOLD}${GREEN}"
echo "   FULL SERVER DIAGNOSTIC   "
echo -e "${NC}"
date

# ==============================================
# 1. СИСТЕМА
# ==============================================
print_header "1. СИСТЕМА"
HOSTNAME=$(hostname)
OS=$(lsb_release -d 2>/dev/null | cut -f2 | xargs) || OS=$(cat /etc/*release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p | sed 's/up //')

print_info "Hostname" "$HOSTNAME"
print_info "OS" "$OS"
print_info "Kernel" "$KERNEL"
print_info "Uptime" "$UPTIME"

# ==============================================
# 2. РЕСУРСЫ (CPU/RAM/DISK)
# ==============================================
print_header "2. РЕСУРСЫ"
# CPU
CPU_MODEL=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs)
CPU_CORES=$(nproc)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
print_info "CPU Model" "$CPU_MODEL"
print_info "Cores / Load" "$CPU_CORES cores / [$LOAD_AVG]"

# RAM
FREE_DATA=$(free -m | grep "Mem:")
MEM_TOTAL=$(echo "$FREE_DATA" | awk '{print $2}')
MEM_USED=$(echo "$FREE_DATA" | awk '{print $3}')
if [[ -z "$MEM_TOTAL" || "$MEM_TOTAL" -eq 0 ]]; then MEM_TOTAL=1; MEM_USED=0; fi
MEM_PERC=$(awk "BEGIN {printf \"%.0f\", ($MEM_USED/$MEM_TOTAL)*100}")

# Цвет RAM
if [ "$MEM_PERC" -ge 80 ]; then M_COL=$RED; elif [ "$MEM_PERC" -ge 50 ]; then M_COL=$YELLOW; else M_COL=$GREEN; fi
printf "${CYAN}%-25s${NC} : ${M_COL}%s%%${NC} (%sMB / %sMB)\n" "RAM Usage" "$MEM_PERC" "$MEM_USED" "$MEM_TOTAL"

# DISK (Root)
DISK_ usage=$(df -h / | tail -1 | awk '{print $5, $3, $2}')
DISK_PERC=$(echo $DISK_usage | awk '{print $1}')
DISK_DET=$(echo $DISK_usage | awk '{print $2 " / " $3}')
printf "${CYAN}%-25s${NC} : %s (%s)\n" "Disk (Root)" "$DISK_PERC" "$DISK_DET"

# ==============================================
# 3. ПОЛЬЗОВАТЕЛИ
# ==============================================
print_header "3. ПОЛЬЗОВАТЕЛИ"

# Активные пользователи (онлайн)
CURRENT_USERS=$(who | awk '{print $1}' | sort | uniq | xargs)
if [ -z "$CURRENT_USERS" ]; then CURRENT_USERS="None"; fi
print_info "Currently Online" "$CURRENT_USERS"

# Пользователи с доступом к Shell (исключая системные nologin/false)
# Ищем в /etc/passwd тех, у кого shell заканчивается на sh (bash, zsh, sh)
echo -e "${BOLD}Users with Shell Access:${NC}"
grep -E '/(bash|zsh|sh)$' /etc/passwd | cut -d: -f1 | column -x
echo ""

# ==============================================
# 4. SSH И БЕЗОПАСНОСТЬ
# ==============================================
print_header "4. SSH КОНФИГУРАЦИЯ"

# Статус сервиса
SSH_STATUS=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null)
if [ "$SSH_STATUS" == "active" ]; then 
    printf "${CYAN}%-25s${NC} : ${GREEN}ACTIVE (Running)${NC}\n" "SSH Service"
else
    printf "${CYAN}%-25s${NC} : ${RED}INACTIVE/STOPPED${NC}\n" "SSH Service"
fi

# Читаем конфиг (пытаемся найти основные параметры)
SSH_CONF="/etc/ssh/sshd_config"

if [ -r "$SSH_CONF" ]; then
    # Порт
    SSH_PORT=$(grep -E "^Port " $SSH_CONF | awk '{print $2}')
    [ -z "$SSH_PORT" ] && SSH_PORT="22 (Default)"
    
    # Root Login
    ROOT_LOGIN=$(grep -E "^PermitRootLogin " $SSH_CONF | awk '{print $2}')
    [ -z "$ROOT_LOGIN" ] && ROOT_LOGIN="prohibit-password (Default)"

    # Password Auth
    PASS_AUTH=$(grep -E "^PasswordAuthentication " $SSH_CONF | awk '{print $2}')
    [ -z "$PASS_AUTH" ] && PASS_AUTH="yes (Default)"

    # PubKey Auth
    KEY_AUTH=$(grep -E "^PubkeyAuthentication " $SSH_CONF | awk '{print $2}')
    [ -z "$KEY_AUTH" ] && KEY_AUTH="yes (Default)"

    print_info "SSH Port" "$SSH_PORT"
    
    # Логика цветов для безопасности
    # Root login лучше выключать или prohibit-password
    if [[ "$ROOT_LOGIN" == "no" || "$ROOT_LOGIN" == "prohibit-password" ]]; then RL_COL=$GREEN; else RL_COL=$RED; fi
    printf "${CYAN}%-25s${NC} : ${RL_COL}%s${NC}\n" "Permit Root Login" "$ROOT_LOGIN"

    # Вход по паролю (безопаснее выключать, если есть ключи)
    if [[ "$PASS_AUTH" == "no" ]]; then PA_COL=$GREEN; else PA_COL=$YELLOW; fi
    printf "${CYAN}%-25s${NC} : ${PA_COL}%s${NC} (no is safer)\n" "Password Auth" "$PASS_AUTH"

    # Вход по ключу
    if [[ "$KEY_AUTH" == "yes" ]]; then KA_COL=$GREEN; else KA_COL=$RED; fi
    printf "${CYAN}%-25s${NC} : ${KA_COL}%s${NC}\n" "Public Key Auth" "$KEY_AUTH"

else
    echo -e "${RED}Cannot read $SSH_CONF (Run as root/sudo to see details)${NC}"
fi

# ==============================================
# 5. УСТАНОВЛЕННОЕ ПО (User Installed)
# ==============================================
print_header "5. ПРОГРАММЫ (Manual Install)"

# Проверяем apt-mark
if command -v apt-mark &> /dev/null; then
    echo -e "${YELLOW}APT Packages (Manually installed, top 30):${NC}"
    # Показываем только установленные вручную, сортируем, ограничиваем
    apt-mark showmanual | sort | head -n 30 | column
    
    TOTAL_APT=$(apt-mark showmanual | wc -l)
    if [ "$TOTAL_APT" -gt 30 ]; then
        echo -e "... and $(($TOTAL_APT - 30)) more packages."
    fi
else
    echo "apt-mark not found (non-Debian system?)"
fi

echo ""

# Проверяем Snap
if command -v snap &> /dev/null; then
    echo -e "${YELLOW}SNAP Packages:${NC}"
    snap list | awk 'NR>1 {print $1 " (" $2 ")"}' | column
else
    echo "Snap not installed or active."
fi

# ==============================================
# 6. СЕТЬ
# ==============================================
print_header "6. СЕТЬ"
ip -4 addr | grep inet | grep -v "127.0.0.1" | awk '{print $2 " on " $NF}' | while read line; do
   print_info "Interface" "$line"
done

# ==============================================
# 7. TOP ПРОЦЕССЫ
# ==============================================
print_header "7. TOP RAM USERS"
ps -eo user,comm,%mem --sort=-%mem | head -n 6 | awk 'NR==1 {print $0} NR>1 {print $0}' | column -t

echo -e "\n${BOLD}${GREEN}=== Готово ===${NC}\n"
