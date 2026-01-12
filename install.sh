#!/bin/bash
set -e

echo "[+] Instalando Marítima VPN (cópia fiel)"

apt update -y
apt install -y bash curl python3 net-tools cron iptables fail2ban

# Painel principal
install -m 755 files/maritima /usr/bin/maritima

# Dados e scripts
mkdir -p /opt/maritima
cp -a opt/* /opt/maritima/

# Permissões
chmod +x /opt/maritima/*.sh /opt/maritima/*.py 2>/dev/null || true

# Systemd
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable maritima-ws maritima-http maritima-badvpn
systemctl restart maritima-ws maritima-http maritima-badvpn

echo
echo "[✓] Marítima instalado com sucesso"
echo "Use o comando: maritima"

