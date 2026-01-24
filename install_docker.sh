#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------
# Pretty logging
# -----------------------------
if [[ -t 1 ]]; then
  RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; DIM=$'\e[2m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
  RED=""; GRN=""; YLW=""; BLU=""; DIM=""; BLD=""; RST=""
fi

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log()  { echo "${DIM}[$(ts)]${RST} $*"; }
info() { log "${BLU}${BLD}INFO${RST}  $*"; }
ok()   { log "${GRN}${BLD}OK${RST}    $*"; }
warn() { log "${YLW}${BLD}WARN${RST}  $*"; }
err()  { log "${RED}${BLD}ERROR${RST} $*"; }

die() { err "$*"; exit 1; }

on_error() {
  local exit_code=$?
  local line_no=$1
  err "Скрипт упал с кодом ${exit_code} на строке ${line_no}."
  err "Проверь вывод выше. Если нужно — запусти с: bash -x $0"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# -----------------------------
# Helpers
# -----------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"; }

run() {
  # run "описание" cmd args...
  local desc=$1; shift
  info "$desc"
  "$@"
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Запусти от root: sudo bash $0"
  fi
}

detect_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64|armhf) echo "$arch" ;;
    *) die "Неподдерживаемая архитектура: $arch (docker repo поддерживает amd64/arm64/armhf)" ;;
  esac
}

detect_codename() {
  # Prefer /etc/os-release + VERSION_CODENAME; fallback to lsb_release
  local codename=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs || true)"
  fi
  [[ -n "$codename" ]] || die "Не удалось определить codename Ubuntu (например jammy/noble)."
  echo "$codename"
}

is_ubuntu() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]]
}

ensure_deps() {
  export DEBIAN_FRONTEND=noninteractive
  run "Обновляю индекс пакетов (apt update)" apt-get update -y

  run "Ставлю зависимости (ca-certificates curl gnupg lsb-release)" \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release
}

setup_repo() {
  local arch="$1"
  local codename="$2"

  run "Создаю каталог keyrings" install -m 0755 -d /etc/apt/keyrings

  # GPG key
  if [[ -f /etc/apt/keyrings/docker.gpg ]]; then
    info "Ключ Docker GPG уже существует: /etc/apt/keyrings/docker.gpg"
  else
    run "Скачиваю и устанавливаю Docker GPG key" \
      bash -c 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
    run "Выставляю права на docker.gpg" chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # Repo list
  local repo_file="/etc/apt/sources.list.d/docker.list"
  local repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable"

  if [[ -f "$repo_file" ]] && grep -Fq "$repo_line" "$repo_file"; then
    info "Docker repo уже прописан в ${repo_file}"
  else
    run "Прописываю Docker apt репозиторий (${codename}, ${arch})" \
      bash -c "echo '$repo_line' > '$repo_file'"
  fi

  run "Обновляю индекс пакетов после добавления репо" apt-get update -y
}

install_docker() {
  export DEBIAN_FRONTEND=noninteractive

  # Remove conflicting packages (official recommendation).
  # We do NOT purge containerd/runc if installed from Docker repo (but these names can collide).
  # We'll remove only known conflicting packages from Ubuntu repos, if present.
  local conflicts=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  local to_remove=()
  for p in "${conflicts[@]}"; do
    if dpkg -s "$p" >/dev/null 2>&1; then
      to_remove+=("$p")
    fi
  done

  if ((${#to_remove[@]})); then
    warn "Найдены потенциально конфликтующие пакеты: ${to_remove[*]}"
    run "Удаляю конфликтующие пакеты" apt-get remove -y "${to_remove[@]}"
  else
    info "Конфликтующие пакеты не обнаружены"
  fi

  run "Устанавливаю Docker Engine + CLI + Compose plugin" \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  run "Включаю и запускаю сервис Docker" systemctl enable --now docker
  ok "Docker установлен и запущен"
}

setup_user_group() {
  local target_user="${SUDO_USER:-}"
  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    warn "SUDO_USER не определён (возможно, ты root). Пропускаю добавление пользователя в группу docker."
    return 0
  fi

  if getent group docker >/dev/null 2>&1; then
    info "Группа docker уже существует"
  else
    run "Создаю группу docker" groupadd docker
  fi

  if id -nG "$target_user" | grep -qw docker; then
    info "Пользователь ${target_user} уже в группе docker"
  else
    run "Добавляю пользователя ${target_user} в группу docker" usermod -aG docker "$target_user"
    warn "Чтобы docker работал без sudo, перелогинься: выйди/зайди или выполни: newgrp docker"
  fi
}

post_checks() {
  info "Проверяю версии…"
  docker --version | sed "s/^/  /"
  docker compose version | sed "s/^/  /"

  info "Пробный запуск hello-world…"
  if docker run --rm hello-world >/dev/null 2>&1; then
    ok "hello-world запустился успешно"
  else
    warn "hello-world не запустился (возможны ограничения сети/прокси). Docker при этом может быть установлен корректно."
  fi
}

main() {
  require_root
  is_ubuntu || die "Этот скрипт рассчитан на Ubuntu. (ID из /etc/os-release должен быть ubuntu)"

  need_cmd apt-get
  need_cmd dpkg
  need_cmd systemctl
  need_cmd curl
  need_cmd gpg

  local arch codename
  arch="$(detect_arch)"
  codename="$(detect_codename)"

  info "Ubuntu codename: ${codename}"
  info "Архитектура: ${arch}"

  ensure_deps
  setup_repo "$arch" "$codename"
  install_docker
  setup_user_group
  post_checks

  ok "Готово. Docker + Docker Compose установлены."
}

main "$@"
