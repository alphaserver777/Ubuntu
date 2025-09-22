#!/bin/bash 
# Установка 1Panel на Ubuntu (автоматическая) 
# Требуется: Ubuntu 20.04/22.04, root/sudo 

set -e 
# Цвета для вывода 
RED='\033[0;31m' 
GREEN='\033[0;32m' 
YELLOW='\033[0;33m' 
NC='\033[0m'

# Установка 1Panel
echo -e "${YELLOW}Загрузка и установка 1Panel...${NC}"
curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o /tmp/1panel_install.sh && bash /tmp/1panel_install.sh

# Очистка
rm -f /tmp/1panel_install.sh

# Получение данных для доступа
IP=$(hostname -I | awk '{print $1}')
PASSWORD=$(grep "password" /usr/local/1panel/logs/install.log | awk -F "'" '{print $2}')

echo -e "\n${GREEN}Установка завершена!${NC}"
echo -e "Доступ к панели: ${YELLOW}http://${IP}:12345${NC}"
echo -e "Логин: ${YELLOW}admin${NC}"
echo -e "Пароль: ${YELLOW}${PASSWORD}${NC}"
echo -e "\nСохраните эти данные в безопасное место!"
