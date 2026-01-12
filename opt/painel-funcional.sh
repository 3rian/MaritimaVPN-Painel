#!/usr/bin/env bash
export TERM=xterm
set -e

# ---------- CORES ----------
CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Cores para banner
BANNER_CYAN='\033[1;96m'
BANNER_BLUE='\033[1;94m'
BANNER_GREEN='\033[1;92m'
BANNER_YELLOW='\033[1;93m'
BANNER_RED='\033[1;91m'
LINE_COLOR='\033[1;90m'

BASE="/opt/maritima"
DB="$BASE/users.db"
BANNER="$BASE/banner.txt"
mkdir -p "$BASE"
touch "$DB" "$BANNER"

pause() { read -rp "ENTER para continuar..."; }

get_ip() {
  ip=$(curl -s --max-time 3 ifconfig.me || true)
  [[ -z "$ip" ]] && ip="IP-INDEFINIDO"
  echo "$ip"
}

service_status() {
  systemctl is-active "$1" &>/dev/null && \
  echo -e "${BANNER_GREEN}● ATIVO${NC}" || echo -e "${RED}● OFF${NC}"
}

# ================= STATUS VPS =================
status_vps() {
clear
echo -e "${BANNER_CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${BANNER_CYAN}║${NC}        ${BANNER_YELLOW}🏴‍☠️ MARÍTIMA VPN STATUS${NC}        ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}╚══════════════════════════════════════╝${NC}"
echo -e "${NC}"
echo -e " ${BANNER_YELLOW}🌐${NC} IP VPS   : ${BANNER_GREEN}$(get_ip)${NC}"
echo -e " ${BANNER_YELLOW}⏱️${NC} Uptime  : ${BANNER_YELLOW}$(uptime -p)${NC}"
echo -e " ${BANNER_YELLOW}🧠${NC} RAM     : ${BANNER_BLUE}$(free -m | awk '/Mem:/ {print $3 "/" $2 " MB"}')${NC}"
echo -e " ${BANNER_YELLOW}💽${NC} Disco   : ${BANNER_BLUE}$(df -h / | awk 'NR==2 {print $3 "/" $2}')${NC}"
echo -e " ${BANNER_YELLOW}🌐${NC} WebSocket SSH : $(service_status maritima-ws)"
echo -e " ${BANNER_YELLOW}🔐${NC} XRAY REALITY  : $(service_status xray)"
echo -e " ${BANNER_YELLOW}🎮${NC} BadVPN UDP    : $(service_status maritima-badvpn)"
echo -e " ${BANNER_YELLOW}🌐${NC} HTTP Proxy Banner : $(service_status maritima-http)"
pause
}

# ================= USUÁRIOS =================
add_user() {
clear
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo -e "${CYAN}📝 CRIAR NOVO USUÁRIO${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo
read -rp "Login: " u
read -rp "Senha: " p
read -rp "Dias: " d
read -rp "Limite conexões: " l

useradd -M -s /bin/false "$u" 2>/dev/null || {
  echo -e "${RED}Usuário já existe${NC}"
  pause; return
}

echo "$u:$p" | chpasswd
EXP=$(date -d "+$d days" +%Y-%m-%d)
UUID=$(uuidgen)
echo "$u:$p:$EXP:$l:$UUID" >> "$DB"

echo -e "${BANNER_GREEN}✅ Usuário criado!${NC}"
pause
}

list_users() {
clear
IP=$(get_ip)
echo -e "${CYAN}${BOLD}👥 USUÁRIOS CADASTRADOS${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

while IFS=: read -r u p e l uuid; do
  [[ -z "$u" ]] && continue
  echo -e "👤 ${GREEN}$u${NC} | 🔑 ${YELLOW}$p${NC} | 📅 $e"
  echo -e "   ${GRAY}SSH: ssh://$u:$p@$IP:22${NC}"
  echo -e "${LINE_COLOR}──────────────────────────────────────${NC}"
done < "$DB"

pause
}

del_user() {
clear
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo -e "${RED}🗑️ REMOVER USUÁRIO${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo
read -rp "Usuário para remover: " u

userdel "$u" 2>/dev/null || true
sed -i "/^$u:/d" "$DB"

echo -e "${BANNER_GREEN}✅ Usuário removido${NC}"
pause
}

user_menu() {
while true; do
clear
echo -e "${CYAN}${BOLD}👥 GERENCIAR USUÁRIOS${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo -e "${YELLOW}1)${NC} ${WHITE}Criar usuário${NC}"
echo -e "${YELLOW}2)${NC} ${WHITE}Listar usuários${NC}"
echo -e "${YELLOW}3)${NC} ${WHITE}Remover usuário${NC}"
echo -e "${YELLOW}4)${NC} ${WHITE}Criar usuário TESTE${NC}"
echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
read -rp "Opção: " o
case $o in
1) add_user ;;
2) list_users ;;
3) del_user ;;
4) add_test_user ;;
0) break ;;
esac
done
}

# ================= PROTOCOLOS =================
protocol_menu() {
while true; do
clear
echo -e "${CYAN}${BOLD}🌐 PROTOCOLOS DE CONEXÃO${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo -e "${YELLOW}1)${NC} ${WHITE}WebSocket SSH   : $(service_status maritima-ws)${NC}"
echo -e "${YELLOW}2)${NC} ${WHITE}XRAY REALITY    : $(service_status xray)${NC}"
echo -e "${YELLOW}3)${NC} ${WHITE}BadVPN UDP      : $(service_status maritima-badvpn)${NC}"
echo -e "${YELLOW}4)${NC} ${WHITE}HTTP Proxy      : $(service_status maritima-http)${NC}"
echo -e "${YELLOW}5)${NC} ${WHITE}Gerar links REALITY${NC}"
echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
read -rp "Opção: " p

case $p in
1) systemctl is-active maritima-ws &>/dev/null && systemctl stop maritima-ws || systemctl start maritima-ws ;;
2) systemctl is-active xray &>/dev/null && systemctl stop xray || systemctl start xray ;;
3) systemctl is-active maritima-badvpn &>/dev/null && systemctl stop maritima-badvpn || systemctl start maritima-badvpn ;;
4) systemctl is-active maritima-http &>/dev/null && systemctl stop maritima-http || systemctl start maritima-http ;;
5) reality_links ;;
0) break ;;
esac
sleep 1
done
}

reality_links() {
clear
IP=$(get_ip)
echo -e "${CYAN}${BOLD}🔐 LINKS XRAY REALITY${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

while IFS=: read -r u p e l uuid; do
  [[ -z "$u" ]] && continue
  echo -e "\n👤 ${GREEN}$u${NC}"
  echo -e "${GRAY}vless://$uuid@$IP:443?type=tcp&security=reality&sni=www.google.com#MARITIMA-$u${NC}"
  echo -e "${LINE_COLOR}──────────────────────────────────────${NC}"
done < "$DB"

pause
}

# ================= BANNER =================
banner_menu() {
while true; do
clear
echo -e "${CYAN}${BOLD}📢 BANNER HTTP INJECTOR${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo -e "${YELLOW}1)${NC} ${WHITE}Ver banner${NC}"
echo -e "${YELLOW}2)${NC} ${WHITE}Editar banner${NC}"
echo -e "${YELLOW}3)${NC} ${WHITE}Limpar banner${NC}"
echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
read -rp "Opção: " b
case $b in
1) clear; cat "$BANNER"; pause ;;
2) nano "$BANNER" ;;
3) > "$BANNER"; echo -e "${GREEN}✅ Banner limpo${NC}"; sleep 1 ;;
0) break ;;
esac
done
}

# ================= SPEED TEST =================
speed_test() {
    clear
    echo -e "${CYAN}${BOLD}🚀 TESTE DE VELOCIDADE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Iniciando teste...${NC}"
    echo
    if command -v speedtest &>/dev/null; then
        speedtest --accept-license --accept-gdpr --simple
    else
        echo "Instalando speedtest..."
        apt update && apt install -y speedtest-cli 2>/dev/null
        speedtest --accept-license --accept-gdpr --simple 2>/dev/null || echo "Teste falhou"
    fi
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================= USUÁRIO TESTE =================
add_test_user() {
    clear
    echo -e "${CYAN}${BOLD}🧪 CRIAR USUÁRIO TESTE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Login teste: " u
    [[ -z "$u" ]] && { echo -e "${RED}Login inválido${NC}"; pause; return; }
    if id "$u" &>/dev/null; then
        echo -e "${RED}Usuário já existe${NC}"; pause; return
    fi
    read -rp "Senha: " p
    [[ -z "$p" ]] && { echo -e "${RED}Senha inválida${NC}"; pause; return; }
    read -rp "Limite conexões: " l; [[ -z "$l" ]] && l=1
    read -rp "Validade (minutos): " m
    [[ -z "$m" ]] && { echo -e "${RED}Tempo inválido${NC}"; pause; return; }
    
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    EXP=$(date -d "+$m minutes" +"%Y-%m-%d %H:%M")
    echo "$u:$p:TESTE:$l:$EXP" >> "$DB"
    
    IP=$(get_ip)
    clear
    echo -e "${BANNER_GREEN}${BOLD}✅ USUÁRIO TESTE CRIADO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "🌐 IP: ${GREEN}$IP${NC}"
    echo -e "👤 Usuário: ${GREEN}$u${NC}"
    echo -e "🔑 Senha: ${YELLOW}$p${NC}"
    echo -e "📶 Limite: $l"
    echo -e "⏱️ Expira: ${RED}$m minutos${NC}"
    pause
}

# ================= MENU PRINCIPAL =================
while true; do
clear

echo -e "${BANNER_CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BANNER_CYAN}║${NC} ${BLACK}🏴‍☠️${WHITE}☠️${BANNER_RED}👿${NC} ${BANNER_CYAN}MARÍTIMA VPN PAINEL${NC} ${BANNER_RED}👿${WHITE}☠️${BLACK}🏴‍☠️${NC} ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BANNER_CYAN}║${NC} ${BANNER_YELLOW}Status${NC} ${BANNER_CYAN}|${NC} ${BANNER_YELLOW}Xray${NC} ${BANNER_CYAN}|${NC} ${BANNER_YELLOW}WebSocket${NC} ${BANNER_CYAN}|${NC} ${BANNER_YELLOW}BadVPN${NC} ${BANNER_CYAN}|${NC} ${BANNER_YELLOW}Proxy${NC} ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "${NC}"
echo -e "${BANNER_CYAN}══════════════════════════════${NC}"
echo -e "${YELLOW}1)${NC} ${CYAN}🏴‍☠️${NC} ${WHITE}Usuários${NC}"
echo -e "${YELLOW}2)${NC} ${BLUE}🌐${NC} ${WHITE}Protocolos${NC}"
echo -e "${YELLOW}3)${NC} ${GREEN}📊${NC} ${WHITE}Status${NC}"
echo -e "${YELLOW}4)${NC} ${PURPLE}📢${NC} ${WHITE}Banner${NC}"
echo -e "${YELLOW}5)${NC} ${RED}🚀${NC} ${WHITE}Speed Test${NC}"
echo -e "${RED}0)${NC} ${BANNER_RED}👿${NC} ${WHITE}Sair${NC}"
echo -e "${BANNER_CYAN}══════════════════════════════${NC}"
read -rp "Opção: " op

case $op in
    1) user_menu ;;
    2) protocol_menu ;;
    3) status_vps ;;
    4) banner_menu ;;
    5) speed_test ;;
    0) clear; echo -e "${GREEN}Até logo! 👋${NC}"; exit 0 ;;
    *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
esac
done
