#!/bin/bash
set -ex # Включить выход при ошибке И вывод команд перед выполнением

echo "Начинаем установку AmneziaWG CLI для Ubuntu (Финальная версия с исправлением клонирования tools)..."
echo "Этот скрипт выполнит полную очистку и перенастройку репозиториев для установки AmneziaWG."
echo "Он установит Go, модуль ядра AmneziaWG через PPA, amneziawg-go, amneziawg-tools и openresolv."
echo "Он также скопирует ваш файл конфигурации из домашней директории."
echo ""

# Проверка наличия необходимых утилит
check_command() {
    if ! command -v "$1" &> /dev/null
    then
        echo "Ошибка: Команда '$1' не найдена."
        if [ "$1" == "wget" ] || [ "$1" == "git" ] || [ "$1" == "cp" ]; then
            echo "Пожалуйста, установите ее: sudo apt update && sudo apt install -y $1"
        elif [ "$1" == "make" ]; then
            echo "Пожалуйста, установите ее: sudo apt update && sudo apt install -y build-essential"
        elif [ "$1" == "systemctl" ]; then
            echo "Команда 'systemctl' является частью systemd. Пожалуйста, убедитесь, что systemd установлен и работает на вашей системе."
        elif [ "$1" == "resolvconf" ]; then
            echo "Пожалуйста, установите ее: sudo apt update && sudo apt install -y openresolv"
        fi
        exit 1
    fi
}

echo "---"
echo "Шаг 0: Предварительная глубокая очистка и подготовка системы"
echo "---"

echo "Удаление старых отчетов о сбоях DKMS (если есть)..."
sudo rm -f /var/crash/amneziawg-dkms.*.crash || true # Удаляем старые crash-отчеты

echo "Принудительное удаление существующих пакетов amneziawg и связанных файлов..."
sudo apt-get purge -y amneziawg amneziawg-dkms amneziawg-tools || true
sudo apt-get autoremove -y || true
sudo apt-get clean

echo "Очистка старых ядер для освобождения места в /boot..."
# Получаем текущую версию ядра
CURRENT_KERNEL=$(uname -r)
echo "Текущее ядро: $CURRENT_KERNEL"

# Удаляем старые пакеты ядер, кроме текущего
echo "Поиск старых ядер..."
# Добавляем || true к grep -v, чтобы избежать прерывания скрипта, если старых ядер не найдено
OLD_KERNELS=$(dpkg -l | awk '/linux-(image|headers)-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic/ {print $2}' | grep -v "$CURRENT_KERNEL" || true)
echo "Найденные старые ядра (для удаления): '$OLD_KERNELS'"

if [ -n "$OLD_KERNELS" ]; then
    echo "Выполняется удаление старых ядер: $OLD_KERNELS"
    # Используем --allow-remove-essential для удаления, если это необходимо
    sudo apt-get purge -y --allow-remove-essential $OLD_KERNELS || true
    echo "Старые ядра удалены."
else
    echo "Старых ядер для удаления не найдено. Пропускаем удаление пакетов."
fi

# Агрессивная очистка старых initrd и vmlinuz образов в /boot (даже если пакеты удалены)
echo "Выполняется агрессивная очистка старых initrd и vmlinuz образов в /boot..."
# Получаем список всех initrd.img-* и vmlinuz-* файлов
ALL_BOOT_FILES=$(find /boot -maxdepth 1 -type f \( -name 'initrd.img-*' -o -name 'vmlinuz-*' -o -name 'System.map-*' -o -name 'config-*' \) )

# Проходим по списку и удаляем файлы, которые НЕ относятся к текущему ядру
for file in $ALL_BOOT_FILES; do
    if [[ "$file" != *"$CURRENT_KERNEL"* ]]; then
        echo "Удаление старого файла: $file"
        sudo rm "$file" || true
    fi
done
# Также удаляем любые .old-dkms или другие резервные копии, которые могли остаться
sudo rm -f /boot/initrd.img-*-old-dkms || true
sudo rm -f /boot/vmlinuz-*-old-dkms || true
echo "Агрессивная очистка /boot завершена."


echo "Запуск sudo apt autoremove для удаления ненужных зависимостей (повторно)..."
sudo apt autoremove -y || true
echo "Запуск sudo apt clean для очистки кэша пакетов (повторно)..."
sudo apt clean

echo "Проверка свободного места в /boot:"
df -h /boot

echo "Попытка исправить любые прерванные установки пакетов (повторно)..."
sudo dpkg --configure -a || true # Попытаемся исправить, но не прерываем скрипт, если команда не сработает

echo "Удаление PPA AmneziaWG из списка источников..."
sudo add-apt-repository --remove -y ppa:amnezia/ppa || true
sudo rm -f /etc/apt/sources.list.d/amnezia-ubuntu-ppa-*.list || true
sudo rm -f /etc/apt/trusted.gpg.d/amnezia-ubuntu-ppa.gpg || true

# Проверяем и обеспечиваем наличие строк 'deb-src' в sources.list
echo "Полное пересоздание /etc/apt/sources.list для гарантии наличия deb-src..."
# Получаем кодовое имя текущего релиза Ubuntu
UBUNTU_RELEASE=$(lsb_release -cs)
echo "Значение UBUNTU_RELEASE: '${UBUNTU_RELEASE}'" # Debugging line

# Создаем резервную копию текущего sources.list
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup_$(date +%Y%m%d%H%M%S)

# Создаем новый sources.list с базовыми репозиториями и deb-src
echo "Создаем новый /etc/apt/sources.20250729.list с гарантированными deb-src записями..."
sudo sh -c "cat > /etc/apt/sources.20250729.list << EOF
# Основные репозитории
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${UBUNTU_RELEASE}-security main restricted universe multiverse

# Репозитории с исходными кодами (необходимы для DKMS)
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE} main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_RELEASE}-backports main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu ${UBUNTU_RELEASE}-security main restricted universe multiverse
EOF"
sudo mv /etc/apt/sources.20250729.list /etc/apt/sources.list
echo "Файл /etc/apt/sources.list успешно обновлен."
echo "Содержимое нового /etc/apt/sources.list:"
sudo cat /etc/apt/sources.list # Добавлен вывод содержимого
echo "--- Конец содержимого sources.list ---"

echo "Обновление списка пакетов после изменения sources.list..."
sudo apt update

echo "---"
echo "Шаг 1: Установка основных зависимостей и Go"
echo "---"

check_command "wget"
check_command "git"
check_command "make" # make обычно идет с build-essential
check_command "cp" # cp - это базовая утилита
check_command "systemctl" # Добавлена проверка для systemctl

# 1. Установка Go
echo "1. Установка Go..."
GO_VERSION="go1.24.3.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/$GO_VERSION"
GO_INSTALL_DIR="/usr/local"

# Проверяем, установлен ли Go в /usr/local/go
if [ -d "${GO_INSTALL_DIR}/go" ]; then
    echo "Go уже установлен в ${GO_INSTALL_DIR}/go. Пропускаем установку Go."
else
    echo "Загрузка Go с $GO_URL..."
    wget "$GO_URL" -O /tmp/"$GO_VERSION"
    echo "Распаковка Go в $GO_INSTALL_DIR..."
    sudo tar -C "$GO_INSTALL_DIR" -xzf /tmp/"$GO_VERSION"
    rm /tmp/"$GO_VERSION" # Удаляем временный файл
    echo "Go успешно установлен в $GO_INSTALL_DIR/go."
fi

# Устанавливаем переменные окружения Go для текущей сессии скрипта
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Проверка версии Go
echo "Проверка версии Go:"
if command -v go &> /dev/null
then
    go version
else
    echo "Ошибка: Go не был установлен корректно. Пожалуйста, проверьте логи выше."
    exit 1
fi
echo ""

# Установка openresolv для resolvconf
echo "Установка openresolv (для resolvconf)..."
sudo apt install -y openresolv
check_command "resolvconf" # Проверяем, что resolvconf теперь доступен
echo "openresolv успешно установлен."
echo ""

echo "---"
echo "Шаг 2: Установка модуля ядра AmneziaWG через PPA"
echo "---"

# Переустановка initramfs-tools и linux-headers для исключения повреждений
echo "Переустановка initramfs-tools и linux-headers для обеспечения целостности..."
# Используем reinstall, а не purge, чтобы не удалять их полностью до установки amneziawg
sudo apt install --reinstall -y initramfs-tools linux-headers-"$(uname -r)"

echo "Установка необходимых пакетов для PPA (software-properties-common, python3-launchpadlib, gnupg2, linux-headers)..."
sudo apt install -y software-properties-common python3-launchpadlib gnupg2 linux-headers-"$(uname -r)"

echo "Добавление PPA:amnezia/ppa..."
sudo add-apt-repository -y ppa:amnezia/ppa

# Явно раскомментируем deb-src в файле PPA
PPA_SOURCES_FILE="/etc/apt/sources.list.d/amnezia-ubuntu-ppa-${UBUNTU_RELEASE}.list"
if [ -f "$PPA_SOURCES_FILE" ]; then
    echo "Раскомментируем deb-src в файле PPA: $PPA_SOURCES_FILE"
    sudo sed -i '/^# deb-src/s/^# //g' "$PPA_SOURCES_FILE" || true
else
    echo "ВНИМАНИЕ: Файл PPA источников '$PPA_SOURCES_FILE' не найден. Возможно, deb-src не будет включен."
fi

echo "Обновление списка пакетов после добавления PPA и раскомментирования deb-src..."
sudo apt update

echo "Установка пакета amneziawg (который включает модуль ядра)..."
sudo apt install -y amneziawg

# Проверка наличия модуля ядра после установки через PPA
if lsmod | grep -q amneziawg; then
    echo "Модуль ядра amneziawg успешно загружен (установлен через PPA)."
else
    echo "ВНИМЕНИЕ: Модуль ядра amneziawg не удалось загрузить после установки через PPA. Возможно, потребуется перезагрузка."
    echo "Пожалуйста, проверьте логи командой 'sudo dmesg | grep amneziawg' и 'sudo journalctl -xe'."
    echo "Также проверьте лог сборки DKMS: 'sudo cat /var/lib/dkms/amneziawg/1.0.0/build/make.log'"
fi
echo ""

echo "---"
echo "Шаг 3: Установка amneziawg-go (пользовательская реализация)"
echo "---"

AMNEZIAWG_GO_REPO="https://github.com/amnezia-vpn/amneziawg-go.git"
AMNEZIAWG_GO_DIR="amneziawg-go"

if [ -d "$AMNEZIAWG_GO_DIR" ]; then
    echo "Директория '$AMNEZIAWG_GO_DIR' уже существует. Обновляем репозиторий..."
    (cd "$AMNEZIAWG_GO_DIR" && git pull)
else
    echo "Клонирование репозитория amneziawg-go..."
    git clone "$AMNEZIAWG_GO_REPO"
fi

echo "Сборка amneziawg-go..."
(cd "$AMNEZIAWG_GO_DIR" && make)

echo "Перемещение amneziawg-go в /usr/local/bin/..."
sudo mv "$AMNEZIAWG_GO_DIR/amneziawg-go" /usr/local/bin/
sudo chmod +x /usr/local/bin/amneziawg-go
echo "amneziawg-go успешно установлен."
echo ""

echo "---"
echo "Шаг 4: Установка amneziawg-tools"
echo "---"

AMNEZIAWG_TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"
AMNEZIAWG_TOOLS_DIR="amneziawg-tools"

if [ -d "$AMNEZIAWG_TOOLS_DIR" ]; then
    echo "Директория '$AMNEZIAWG_TOOLS_DIR' уже существует. Обновляем репозиторий..."
    (cd "$AMNEZIAWG_TOOLS_DIR" && git pull)
else
    echo "Клонирование репозитория amneziawg-tools..."
    # Исправлена ошибка: использование переменной с URL, а не с именем директории
    git clone "$AMNEZIAWG_TOOLS_REPO"
fi

echo "Сборка и установка amneziawg-tools..."
(cd "$AMNEZIAWG_TOOLS_DIR/src" && make && sudo make install)
echo "amneziawg-tools успешно установлен."
echo ""

echo "---"
echo "Шаг 5: Настройка файла конфигурации"
echo "---"

echo "Создаем необходимую директорию: /etc/amnezia/amneziawg/"
sudo mkdir -p /etc/amnezia/amneziawg/
echo "Директория /etc/amnezia/amneziawg/ создана."
echo ""

CONFIG_SOURCE_PATH="$HOME/srv-home.conf"
CONFIG_DEST_PATH="/etc/amnezia/amneziawg/wg0.conf"

if [ -f "$CONFIG_SOURCE_PATH" ]; then
    echo "Копируем файл конфигурации '$CONFIG_SOURCE_PATH' в '$CONFIG_DEST_PATH'..."
    sudo cp "$CONFIG_SOURCE_PATH" "$CONFIG_DEST_PATH"
    echo "Файл конфигурации скопирован."
    echo ""
    echo "ВНИМАНИЕ: Вам НЕОБХОДИМО отредактировать скопированный файл '$CONFIG_DEST_PATH'."
    echo "Замените все 'YOUR_...' заполнители вашими реальными данными VPN (ключами, IP-адресами и т.д.)."
    echo "Пример команды для редактирования: sudo nano $CONFIG_DEST_PATH"
else
    echo "Ошибка: Файл '$CONFIG_SOURCE_PATH' не найден в вашей домашней директории."
    echo "Пожалуйста, убедитесь, что этот файл существует и содержит шаблон вашей конфигурации."
    exit 1 # Выходим, так как файл конфигурации не был найден/скопирован
fi

echo "После создания и сохранения файла конфигурации вы можете перейти к тестированию и включению при загрузке."
echo "=================================================================================="
echo ""

echo "---"
echo "Шаг 6: Тестовое соединение (ручные шаги)"
echo "---"
echo "После того как ваш файл /etc/amnezia/amneziawg/wg0.conf будет правильно настроен:"
echo "Чтобы подключить VPN: sudo awg-quick up wg0"
echo "Затем проверьте IP: ip route show && curl ifconfig.me"
echo ""
echo "Чтобы отключить VPN: sudo awg-quick down wg0"
echo "Затем проверьте IP: ip route show && curl ifconfig.me"
echo ""

echo "---"
echo "Шаг 7: Включение при загрузке (ручные шаги)"
echo "---"
echo "Чтобы включить автоматический запуск AmneziaWG при загрузке (после настройки файла конфигурации):"
echo "sudo systemctl enable awg-quick@wg0.service"
echo "sudo systemctl start awg-quick@wg0.service"
echo ""

echo "Скрипт установки AmneziaWG CLI завершен. Пожалуйста, следуйте ручным шагам для настройки конфигурации и тестирования."

