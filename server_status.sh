#!/bin/bash

# --- Настройки цветов ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Функции оформления ---
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
}

print_info() {
    printf "${CYAN}%-20s${NC} : %s\n" "$1" "$2"
}

clear

echo -e "${BOLD}${GREEN}"
echo "   SERVER INFO DASHBOARD   "
echo -e "${NC}"
date

# --- 1. СИСТЕМА ---
print_header "СИСТЕМА"
HOSTNAME=$(hostname)
# Используем LC_ALL=C для корректной работы lsb_release
OS=$(LC_ALL=C lsb_release -d | cut -f2 | xargs)
KERNEL=$(uname -r)
UPTIME=$(uptime -p | sed 's/up //')
LAST_BOOT=$(who -b | awk '{print $3, $4}')

print_info "Hostname" "$HOSTNAME"
print_info "OS" "$OS"
print_info "Kernel" "$KERNEL"
print_info "Uptime" "$UPTIME"
print_info "Last Boot" "$LAST_BOOT"

# --- 2. CPU ---
print_header "ПРОЦЕССОР (CPU)"
# LC_ALL=C для lscpu
CPU_MODEL=$(LC_ALL=C lscpu | grep "Model name" | cut -d ':' -f2 | xargs)
CPU_CORES=$(nproc)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

print_info "Model" "$CPU_MODEL"
print_info "Cores" "$CPU_CORES"
print_info "Load Avg (1/5/15)" "$LOAD_AVG"

# --- 3. ПАМЯТЬ (RAM) ---
print_header "ОПЕРАТИВНАЯ ПАМЯТЬ"
# !!! ИСПРАВЛЕНИЕ: Принудительный английский для парсинга
FREE_DATA=$(LC_ALL=C free -m | grep "Mem:")
MEM_TOTAL=$(echo "$FREE_DATA" | awk '{print $2}')
MEM_USED=$(echo "$FREE_DATA" | awk '{print $3}')

# Защита от деления на ноль, если данные не получены
if [[ -z "$MEM_TOTAL" || "$MEM_TOTAL" -eq 0 ]]; then
    MEM_TOTAL=1
    MEM_USED=0
    MEM_PERC=0
else
    MEM_PERC=$(awk "BEGIN {printf \"%.0f\", ($MEM_USED/$MEM_TOTAL)*100}")
fi

# Визуализация бара загрузки
BAR_SIZE=20
BAR_FILLED=$(awk "BEGIN {printf \"%.0f\", ($MEM_PERC/100)*$BAR_SIZE}")
BAR_EMPTY=$(($BAR_SIZE - $BAR_FILLED))
BAR_STR=""

# Генерация полоски
if [ "$BAR_FILLED" -gt 0 ]; then
    for ((i=0; i<$BAR_FILLED; i++)); do BAR_STR="${BAR_STR}#"; done
fi
if [ "$BAR_EMPTY" -gt 0 ]; then
    for ((i=0; i<$BAR_EMPTY; i++)); do BAR_STR="${BAR_STR}."; done
fi

# Выбор цвета
if [ "$MEM_PERC" -ge 80 ]; then MEM_COLOR=$RED
elif [ "$MEM_PERC" -ge 50 ]; then MEM_COLOR=$YELLOW
else MEM_COLOR=$GREEN
fi

printf "${CYAN}%-20s${NC} : ${MEM_COLOR}[${BAR_STR}] ${MEM_PERC}%%${NC} (${MEM_USED}MB / ${MEM_TOTAL}MB)\n" "Usage"

# --- 4. ДИСКИ ---
print_header "ДИСКОВОЕ ПРОСТРАНСТВО"
printf "${BOLD}%-15s %-10s %-10s %-10s %-6s${NC}\n" "Mount" "Total" "Used" "Free" "Use%"
# Используем LC_ALL=C для df, чтобы заголовок был "Filesystem" и grep его отфильтровал
LC_ALL=C df -hP | grep -vE '^Filesystem|tmpfs|cdrom|loop|udev' | awk '{printf "%-15s %-10s %-10s %-10s %-6s\n", $6, $2, $3, $4, $5}'

# --- 5. СЕТЬ ---
print_header "СЕТЬ"
ip -4 addr | grep inet | grep -v "127.0.0.1" | awk '{print $2, $NF}' | while read ip interface; do
    printf "${CYAN}%-10s${NC} : %s\n" "$interface" "$ip"
done

if command -v curl &> /dev/null; then
    EXT_IP=$(curl -s --connect-timeout 2 ifconfig.me)
    if [ ! -z "$EXT_IP" ]; then
        print_info "External IP" "$EXT_IP"
    fi
fi

# --- 6. ТОП ПРОЦЕССОВ ---
print_header "ТОП 5 ПРОЦЕССОВ (по CPU)"
# Вывод процессов, обрезаем длинные имена команд
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6 | awk 'NR==1 {print $0} NR>1 {$3=substr($3,1,20); print $0}' | column -t

echo -e "\n${BOLD}${GREEN}=== Готово ===${NC}\n"
