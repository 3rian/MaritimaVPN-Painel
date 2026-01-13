#!/bin/bash
set -e

echo "[+] Instalando Marítima VPN (instalador oficial)"

# ===== ROOT =====
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root"
  exit 1
fi

# ===== BASE =====
apt update -y
apt install -y \
  curl wget git nano unzip \
  python3 python3-pip \
  openssh-server \
  net-tools iptables iptables-persistent \
  cron fail2ban \
  sqlite3

# ===== SPEEDTEST (OFICIAL OOKLA) =====
if ! command -v speedtest >/dev/null; then
  echo "[+] Instalando Speedtest (Ookla)"
  curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
  apt install -y speedtest
fi

# ===== XRAY =====
if ! command -v xray >/dev/null; then
  echo "[+] Instalando Xray"
  bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

systemctl enable xray
systemctl restart xray

# ===== BADVPN =====
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
  echo "[+] Instalando BadVPN"
  wget -O /usr/local/bin/badvpn-udpgw \
    https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw
  chmod +x /usr/local/bin/badvpn-udpgw
fi

# ===== PAINEL =====
install -m 755 files/maritima /usr/bin/maritima

mkdir -p /opt/maritima
cp -a opt/* /opt/maritima/

# ===== PERMISSÕES =====
chmod +x /opt/maritima/*.sh /opt/maritima/*.py || true
touch /opt/maritima/users.db
chown -R root:root /opt/maritima
chmod 600 /opt/maritima/users.db

# ===== SYSTEMD =====
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

systemctl enable maritima-ws maritima-http maritima-badvpn
systemctl restart maritima-ws maritima-http maritima-badvpn

echo
echo "[✓] Marítima VPN instalado com sucesso"
echo "Execute: maritima"
