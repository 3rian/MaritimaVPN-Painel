#!/bin/bash
set -e

# =========================
# ROOT CHECK
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root"
  exit 1
fi


# ===== BASE =====
=======
# =========================
# PACOTES BASE
# =========================
>>>>>>> fix: instalador completo e funcional (xray, badvpn, speedtest)
apt update -y
apt install -y \
  curl wget git nano unzip \
  python3 python3-pip \
  openssh-server \
  net-tools iptables iptables-persistent \
  cron fail2ban \
<<<<<<< HEAD
  sqlite3

# ===== SPEEDTEST (OFICIAL OOKLA) =====
if ! command -v speedtest >/dev/null; then
  echo "[+] Instalando Speedtest (Ookla)"
=======
  build-essential cmake make g++

# =========================
# SPEEDTEST (OOKLA OFICIAL)
# =========================
echo "[+] Configurando Speedtest (Ookla)"

apt remove -y speedtest-cli || true
rm -f /usr/bin/speedtest || true

if ! command -v speedtest >/dev/null; then
>>>>>>> fix: instalador completo e funcional (xray, badvpn, speedtest)
  curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
  apt install -y speedtest
fi

# ===== XRAY =====
=======
# =========================
# XRAY (OFICIAL)
# =========================
>>>>>>> fix: instalador completo e funcional (xray, badvpn, speedtest)
if ! command -v xray >/dev/null; then
  echo "[+] Instalando Xray"
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
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
=======
# =========================
# BADVPN UDPGW
# =========================
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
  echo "[+] Compilando BadVPN UDPGW"

  cd /tmp
  rm -rf badvpn
  git clone https://github.com/ambrop72/badvpn.git
  cd badvpn
  mkdir build
  cd build

  cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
  make -j$(nproc)
  install -m 755 udpgw/badvpn-udpgw /usr/local/bin/badvpn-udpgw
fi

cd /

# =========================
# PAINEL MARÍTIMA
# =========================
echo "[+] Instalando painel Marítima"

install -m 755 files/maritima /usr/bin/maritima

mkdir -p /opt/maritima
cp -a opt/* /opt/maritima/

chmod +x /opt/maritima/*.sh /opt/maritima/*.py 2>/dev/null || true

# =========================
# SYSTEMD
# =========================
echo "[+] Configurando serviços systemd"
>>>>>>> fix: instalador completo e funcional (xray, badvpn, speedtest)

cp systemd/*.service /etc/systemd/system/

systemctl daemon-reexec
systemctl daemon-reload


systemctl enable maritima-ws maritima-http maritima-badvpn
systemctl restart maritima-ws maritima-http maritima-badvpn

echo
echo "[✓] Marítima VPN instalado com sucesso"
echo "Execute: maritima"
=======
systemctl enable \
  maritima-ws \
  maritima-http \
  maritima-badvpn

systemctl restart \
  maritima-ws \
  maritima-http \
  maritima-badvpn

# =========================
# FINAL
# =========================
echo
echo "[✓] Marítima VPN instalado com sucesso"
echo "Comando principal: maritima"
echo
# fix: instalador completo e funcional (xray, badvpn, speedtest)

