#!/bin/bash

# Установка Docker и Docker Compose (автоматическая)
# Требуется: Ubuntu 20.04/22.04, root/sudo

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Данные для нового пользователя-администратора
NEW_ADMIN_USERNAME="admsys" # Можете изменить это имя на любое другое
NEW_ADMIN_PASSWORD="12345678"

# Проверка прав root/sudo
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Ошибка: Скрипт должен быть запущен с правами root или через sudo!${NC}" >&2
  exit 1
fi

## Добавление нового пользователя-администратора

echo -e "${YELLOW}Попытка добавления нового пользователя-администратора '${NEW_ADMIN_USERNAME}'...${NC}"

# Проверяем, существует ли пользователь
if id "$NEW_ADMIN_USERNAME" &>/dev/null; then
    echo -e "${GREEN}Пользователь '${NEW_ADMIN_USERNAME}' уже существует.${NC}"
else
    # Создаем пользователя без домашней директории и без запроса пароля
    # (пароль будет установлен через chpasswd)
    adduser --disabled-password --gecos "" "$NEW_ADMIN_USERNAME"
    echo -e "${GREEN}Пользователь '${NEW_ADMIN_USERNAME}' создан.${NC}"
fi

# Добавляем пользователя в группу 'sudo' для получения административных прав
usermod -aG sudo "$NEW_ADMIN_USERNAME"
echo -e "${GREEN}Пользователь '${NEW_ADMIN_USERNAME}' добавлен в группу 'sudo' (административные права).${NC}"

# Устанавливаем пароль для нового пользователя
# ВНИМАНИЕ: Использование chpasswd для неинтерактивной установки пароля
# Крайне небезопасно для продакшен-систем, так как пароль в открытом виде будет в скрипте.
# Используйте только для тестовых сред, осознавая риски.
echo "$NEW_ADMIN_USERNAME:$NEW_ADMIN_PASSWORD" | chpasswd

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Пароль '${NEW_ADMIN_PASSWORD}' для пользователя '${NEW_ADMIN_USERNAME}' успешно установлен.${NC}"
else
    echo -e "${RED}Ошибка при установке пароля для пользователя '${NEW_ADMIN_USERNAME}'. Возможно, chpasswd не найдена или возникла другая проблема.${NC}"
fi

echo "root:$NEW_ADMIN_PASSWORD" | chpasswd

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Пароль '${NEW_ADMIN_PASSWORD}' для пользователя 'root' успешно установлен.${NC}"
else
    echo -e "${RED}Ошибка при установке пароля для пользователя 'root'. Возможно, chpasswd не найдена или возникла другая проблема.${NC}"
fi



## Установка системных компонентов и Docker

# Обновление системы
echo -e "${YELLOW}Обновление пакетов...${NC}"
apt update # && apt upgrade -y

# Установка Московского времени
echo -e "${YELLOW}Установка Московского времени...${NC}"
timedatectl set-timezone Europe/Moscow

# Установка SSH-сервера
#echo -e "${YELLOW}Установка openssh-server...${NC}"
#apt install -y openssh-server

## Настройка SSH для разрешения входа root

echo -e "${YELLOW}Разрешение входа root по SSH (НЕБЕЗОПАСНО ДЛЯ ПРОДАКШЕНА!)...${NC}"

# Создаем резервную копию оригинального файла sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Изменяем PermiRootLogin на yes, если он существует, или добавляем, если нет
# Используем sed для замены строки или добавления, если ее нет.
# Вариант 1: Заменить существующую строку
sed -i 's/^#*PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin forced-commands-only/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
# Вариант 2: Если строка не найдена, добавить ее (например, в конец файла)
if ! grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

# Проверяем, что аутентификация по паролю разрешена
# Это обычно PasswordAuthentication yes или #PasswordAuthentication yes
sed -i 's/^#*PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
if ! grep -q "PasswordAuthentication" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# Перезапускаем службу SSH, чтобы применить изменения
systemctl restart ssh
echo -e "${GREEN}Вход root по SSH разрешен. (ОЧЕНЬ ВАЖНО: Это делает ваш сервер менее безопасным).${NC}"

## Установка Docker и Docker Compose (продолжение)

# Установка Docker (если не установлен)
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}Установка Docker...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  echo -e "${GREEN}Docker успешно установлен и запущен.${NC}"
else
  echo -e "${GREEN}Docker уже установлен.${NC}"
fi

# Установка Docker Compose (если не установлен)
# Используем плагин Docker Compose, который является рекомендуемым способом установки.
if ! command -v docker-compose &> /dev/null; then
  echo -e "${YELLOW}Установка Docker Compose (plugin)...${NC}"
  apt install -y docker-compose-plugin
  echo -e "${GREEN}Docker Compose успешно установлен.${NC}"
else
  echo -e "${GREEN}Docker Compose уже установлен.${NC}"
fi

echo -e "${GREEN}Все необходимые компоненты (Docker и Docker Compose) установлены.${NC}"
echo -e "Install name and mail for Git"
git config --global user.email "maksim.ilonov@yandex.ru"
git config --global user.name "crypto_mrx"
