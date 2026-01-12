#!/bin/bash
set -e

echo "[+] Instalando Marítima VPN (instalação limpa e reproduzível)"

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
  build-essential cmake make g++

# ===== SPEEDTEST (OOKLA OFICIAL) =====
if ! command -v speedtest >/dev/null; then
  echo "[+] Instalando Speedtest"
  curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
  apt install -y speedtest
fi

# ===== XRAY =====
if ! command -v xray >/dev/null; then
  echo "[+] Instalando Xray"
  bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

mkdir -p /usr/local/etc/xray
cp opt/xray/config.json /usr/local/etc/xray/config.json

systemctl enable xray
systemctl restart xray

# ===== BADVPN (COMPILADO) =====
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
  echo "[+] Compilando BadVPN"
  cd /tmp
  rm -rf badvpn
  git clone https://github.com/ambrop72/badvpn.git
  cd badvpn
  mkdir build && cd build
  cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
  make -j$(nproc)
  cp udpgw/badvpn-udpgw /usr/local/bin/
  chmod +x /usr/local/bin/badvpn-udpgw
fi

# ===== PAINEL =====
install -m 755 files/maritima /usr/bin/maritima

mkdir -p /opt/maritima
cp -a opt/* /opt/maritima/
chmod +x /opt/maritima/*.sh /opt/maritima/*.py || true

# ===== SYSTEMD =====
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

systemctl enable \
  maritima-ws \
  maritima-http \
  maritima-badvpn

systemctl restart \
  maritima-ws \
  maritima-http \
  maritima-badvpn

echo
echo "[✓] Marítima VPN instalado com sucesso"
echo "Use o comando: maritima"

