#!/usr/bin/env bash
set -e

# Удобный вывод
log() { echo -e "\e[1;32m[INFO]\e[0m $*"; }
err() { echo -e "\e[1;31m[ERR ]\e[0m $*" >&2; }

if [[ $EUID -ne 0 ]]; then
  err "Запустите скрипт от root, например: sudo $0"
  exit 1
fi

log "Обновление списка пакетов..."
apt-get update -y

log "Установка зависимостей (build-essential, dkms, linux-headers)..."
apt-get install -y build-essential dkms linux-headers-$(uname -r)

# Точка монтирования
MNT_DIR=/mnt/vboxadditions

log "Создание точки монтирования ${MNT_DIR}..."
mkdir -p "$MNT_DIR"

# Определяем устройство CD с дополнениями
log "Поиск CD‑привода с образом Guest Additions..."
DEV=$(lsblk -o NAME,TYPE | awk '$2=="rom"{print "/dev/"$1; exit}')

if [[ -z "$DEV" ]]; then
  err "CD‑привод не найден. В меню VirtualBox выберите:
  Devices -> Insert Guest Additions CD image...
  затем запустите скрипт повторно."
  exit 1
fi

log "Монтирование ${DEV} в ${MNT_DIR}..."
mount -r -t iso9660 "$DEV" "$MNT_DIR"

if [[ ! -f "${MNT_DIR}/VBoxLinuxAdditions.run" ]]; then
  err "VBoxLinuxAdditions.run не найден на смонтированном диске.
  Убедитесь, что вставлен правильный ISO с Guest Additions."
  umount "$MNT_DIR" || true
  exit 1
fi

log "Запуск установщика VBoxLinuxAdditions.run (без X11)..."
sh "${MNT_DIR}/VBoxLinuxAdditions.run" --nox11 || {
  err "Ошибка установки Guest Additions. Проверьте лог /var/log/VBox*.log"
  umount "$MNT_DIR" || true
  exit 1
}

log "Отмонтирование CD..."
umount "$MNT_DIR"

log "VirtualBox Guest Additions установлены. Рекомендуется перезагрузить систему:"
echo "  reboot"
