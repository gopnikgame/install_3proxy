#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="3proxy"
BIN_PATH="/usr/local/bin/3proxy"
CFG_DIR="/etc/3proxy"
CFG_PATH="/etc/3proxy/3proxy.cfg"
LOG_DIR="/var/log/3proxy"
PID_DIR="/run/3proxy"
SRC_DIR="/opt/3proxy"

DEFAULT_HTTP_PORT="8080"
DEFAULT_SOCKS_PORT="1080"
DEFAULT_USER="proxyuser"

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Запусти от root: sudo $0"
    exit 1
  fi
}

port_is_busy() {
  local port="$1"
  ss -ltnup 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\])${port}$"
}

show_busy_ports() {
  echo
  echo "Занятые TCP-порты:"
  ss -ltnp 2>/dev/null | awk 'NR>1 {print $4}' | sed 's/.*://' | grep -E '^[0-9]+$' | sort -n | uniq | tr '\n' ' '
  echo
  echo
}

ask_free_port() {
  local label="$1"
  local default_port="$2"
  local selected_port=""

  while true; do
    read -rp "$label порт [$default_port]: " selected_port
    selected_port="${selected_port:-$default_port}"

    if ! [[ "$selected_port" =~ ^[0-9]+$ ]]; then
      echo "Ошибка: порт должен быть числом."
      continue
    fi

    if (( selected_port < 1 || selected_port > 65535 )); then
      echo "Ошибка: порт должен быть от 1 до 65535."
      continue
    fi

    if port_is_busy "$selected_port"; then
      echo "Порт $selected_port уже занят."
      show_busy_ports
      continue
    fi

    echo "$selected_port"
    return
  done
}

install_dependencies() {
  apt update
  apt install -y \
    build-essential \
    git \
    curl \
    ufw \
    iproute2 \
    openssl
}

install_3proxy_binary() {
  mkdir -p /opt

  if [[ ! -d "$SRC_DIR" ]]; then
    git clone https://github.com/3proxy/3proxy.git "$SRC_DIR"
  else
    cd "$SRC_DIR"
    git pull || true
  fi

  cd "$SRC_DIR"
  make -f Makefile.Linux

  install -m 755 bin/3proxy "$BIN_PATH"
}

write_config() {
  local proxy_user="$1"
  local proxy_pass="$2"
  local http_port="$3"
  local socks_port="$4"

  mkdir -p "$CFG_DIR" "$LOG_DIR" "$PID_DIR"

  cat > "$CFG_PATH" <<EOF
daemon
pidfile ${PID_DIR}/3proxy.pid

nscache 65536
timeouts 1 5 30 60 180 1800 15 60

log ${LOG_DIR}/3proxy.log D
logformat "L%Y-%m-%d %H:%M:%S %U %C:%c %R:%r %O %I %h %T"

auth strong
users ${proxy_user}:CL:${proxy_pass}

allow ${proxy_user}

proxy -n -p${http_port}
socks -p${socks_port}

flush
EOF

  chmod 600 "$CFG_PATH"
}

write_systemd_service() {
  cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=forking
ExecStart=${BIN_PATH} ${CFG_PATH}
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=${PID_DIR}/3proxy.pid
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

open_ufw_port() {
  local port="$1"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${port}/tcp" || true
  fi
}

remove_ufw_port() {
  local port="$1"

  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "${port}/tcp" || true
  fi
}

get_current_ports() {
  if [[ -f "$CFG_PATH" ]]; then
    grep -E '^(proxy|socks)' "$CFG_PATH" | grep -oP '\-p\K[0-9]+' || true
  fi
}

generate_credentials() {
  PROXY_USER="proxy_$(openssl rand -hex 3)"
  PROXY_PASS="$(openssl rand -base64 24 | tr -d '=+/')"

  echo
  echo "Сгенерированы учетные данные:"
  echo "Логин : $PROXY_USER"
  echo "Пароль: $PROXY_PASS"
  echo
}

manual_credentials() {
  read -rp "Логин прокси [$DEFAULT_USER]: " PROXY_USER
  PROXY_USER="${PROXY_USER:-$DEFAULT_USER}"

  while true; do
    read -rsp "Пароль прокси: " PROXY_PASS
    echo

    if [[ -n "$PROXY_PASS" ]]; then
      break
    fi

    echo "Пароль не может быть пустым."
  done
}

setup_credentials() {
  read -rp "Сгенерировать логин/пароль автоматически? [Y/n]: " gen_creds
  gen_creds="${gen_creds:-Y}"

  if [[ "$gen_creds" =~ ^[YyДд]$ ]]; then
    generate_credentials
  else
    manual_credentials
  fi
}

install_or_reconfigure() {
  echo
  echo "=== Установка / перенастройка 3proxy ==="

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo "Обнаружен установленный 3proxy."

    read -rp "Перенастроить его? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[YyДд]$ ]]; then
      echo "Отменено."
      exit 0
    fi

    systemctl stop "$SERVICE_NAME" || true
  fi

  show_busy_ports

  setup_credentials

  HTTP_PORT="$(ask_free_port "HTTP proxy" "$DEFAULT_HTTP_PORT")"
  SOCKS_PORT="$(ask_free_port "SOCKS5 proxy" "$DEFAULT_SOCKS_PORT")"

  if [[ "$HTTP_PORT" == "$SOCKS_PORT" ]]; then
    echo "Ошибка: HTTP и SOCKS5 не могут использовать один и тот же порт."
    exit 1
  fi

  install_dependencies
  install_3proxy_binary
  write_config "$PROXY_USER" "$PROXY_PASS" "$HTTP_PORT" "$SOCKS_PORT"
  write_systemd_service

  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  open_ufw_port "$HTTP_PORT"
  open_ufw_port "$SOCKS_PORT"

  SERVER_IP="$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')"

  echo
  echo "===================================="
  echo "3proxy успешно установлен"
  echo "===================================="
  echo

  echo "HTTP Proxy:"
  echo "http://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${HTTP_PORT}"
  echo

  echo "SOCKS5 Proxy:"
  echo "socks5://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${SOCKS_PORT}"
  echo

  echo "Проверка:"
  echo "curl -x http://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${HTTP_PORT} https://api.ipify.org"
  echo
}

remove_3proxy() {
  echo
  echo "=== Удаление 3proxy ==="

  CURRENT_PORTS="$(get_current_ports || true)"

  read -rp "Удалить 3proxy? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[YyДд]$ ]]; then
    echo "Отменено."
    exit 0
  fi

  systemctl stop "$SERVICE_NAME" || true
  systemctl disable "$SERVICE_NAME" || true

  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"

  systemctl daemon-reload

  rm -rf "$CFG_DIR"
  rm -rf "$LOG_DIR"
  rm -f "$BIN_PATH"

  if [[ -n "${CURRENT_PORTS:-}" ]]; then
    read -rp "Удалить правила UFW? [y/N]: " remove_fw

    if [[ "$remove_fw" =~ ^[YyДд]$ ]]; then
      for port in $CURRENT_PORTS; do
        remove_ufw_port "$port"
      done
    fi
  fi

  echo
  echo "3proxy удален."
  echo
}

status_3proxy() {
  echo
  echo "=== Статус 3proxy ==="
  echo

  systemctl status "$SERVICE_NAME" --no-pager || true

  echo
  echo "Слушающие порты:"
  ss -ltnp | grep 3proxy || true

  echo
}

main_menu() {
  echo
  echo "===================================="
  echo "3proxy Manager"
  echo "===================================="
  echo
  echo "1) Установить / перенастроить"
  echo "2) Удалить"
  echo "3) Статус"
  echo "0) Выход"
  echo

  read -rp "Выбор: " action

  case "$action" in
    1)
      install_or_reconfigure
      ;;
    2)
      remove_3proxy
      ;;
    3)
      status_3proxy
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Неизвестное действие."
      exit 1
      ;;
  esac
}

require_root
main_menu
