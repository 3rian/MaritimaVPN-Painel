#!/bin/bash
set -e

echo "[+] Instalando Marítima VPN (cópia fiel de produção)"

# ===== ROOT =====
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root"
  exit 1
fi

# ===== PACOTES BASE =====
apt update -y
apt install -y \
  curl wget git nano unzip \
  python3 python3-pip \
  openssh-server \
  net-tools iptables iptables-persistent \
  cron fail2ban \
  speedtest-cli

# ===== XRAY (OFICIAL) =====
if ! command -v xray >/dev/null; then
  echo "[+] Instalando Xray"
  bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

systemctl enable xray
systemctl restart xray || true

# ===== DIRETÓRIOS =====
mkdir -p /opt/maritima

# ===== ARQUIVOS =====
cp files/maritima /usr/bin/maritima
chmod +x /usr/bin/maritima

cp -r opt/* /opt/maritima/

chmod +x /opt/maritima/*.sh
chmod +x /opt/maritima/*.py

# ===== SYSTEMD =====
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

systemctl enable maritima-ws maritima-http maritima-badvpn || true
systemctl restart maritima-ws maritima-http maritima-badvpn || true

# ===== FINAL =====
echo "=================================="
echo " Marítima VPN instalado com sucesso"
echo " Comando: maritima"
echo "=================================="

