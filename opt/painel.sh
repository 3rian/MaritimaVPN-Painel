#!/usr/bin/env bash
export TERM=xterm
set -e

BASE="/opt/maritima"
DB="$BASE/users.db"
BANNER="$BASE/banner.txt"
BACKUP_DIR="$BASE/backups"
LOGS_DIR="$BASE/logs"
CONFIG_DIR="$BASE/config"

mkdir -p "$BASE" "$BACKUP_DIR" "$LOGS_DIR" "$CONFIG_DIR"
touch "$DB" "$BANNER"

# ---------- CORES ----------
CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
GRAY='\033[1;90m'
NC='\033[0m'

# Cores especiais
BANNER_CYAN='\033[1;96m'
BANNER_BLUE='\033[1;94m'
BANNER_GREEN='\033[1;92m'
BANNER_YELLOW='\033[1;93m'
BANNER_RED='\033[1;91m'
LINE_COLOR='\033[1;90m'

# Configurações Xray
XRAY_CONFIG="/usr/local/etc/xray/config.json"
REALITY_PBK="SUA_PUBLIC_KEY_REALITY_AQUI"

pause() { read -rp "ENTER para continuar..."; }

get_ip() {
  ip=$(curl -s --max-time 3 ifconfig.me || true)
  [[ -z "$ip" ]] && ip="IP-INDEFINIDO"
  echo "$ip
}

# ================== FUNÇÕES DE SERVIÇO ==================
service_status() {
    local service_name="$1"
    
    case "$service_name" in
        "maritima-badvpn")
            if systemctl is-active "$service_name" &>/dev/null || \
               pgrep -f "badvpn-udpgw" >/dev/null || \
               ss -tulpn 2>/dev/null | grep -q ":7300"; then
                echo -e "${BANNER_GREEN}● ATIVO${NC}"
            else
                echo -e "${RED}● OFF${NC}"
            fi
            ;;
        *)
            if systemctl is-active "$service_name" &>/dev/null; then
                echo -e "${BANNER_GREEN}● ATIVO${NC}"
            else
                echo -e "${RED}● OFF${NC}"
            fi
            ;;
    esac
}

# ================== XRAY REALITY ==================
add_reality_user() {
    local uuid="$1"
    jq --arg uuid "$uuid" '
        .inbounds[0].settings.clients += [{
            "id": $uuid,
            "flow": "xtls-rprx-vision"
        }]
    ' "$XRAY_CONFIG" > /tmp/xray.tmp && mv /tmp/xray.tmp "$XRAY_CONFIG"
    systemctl restart xray
}

remove_reality_user() {
    local uuid="$1"
    jq --arg uuid "$uuid" '
        .inbounds[0].settings.clients |= map(select(.id != $uuid))
    ' "$XRAY_CONFIG" > /tmp/xray.tmp && mv /tmp/xray.tmp "$XRAY_CONFIG"
    systemctl restart xray
}

# ================== 1. STATUS VPS ==================
status_vps() {
    clear
    echo -e "${BANNER_CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BANNER_CYAN}║${NC}        ${BANNER_YELLOW}🏴‍☠️ MARÍTIMA VPN STATUS${NC}        ${BANNER_CYAN}║${NC}"
    echo -e "${BANNER_CYAN}╚══════════════════════════════════════╝${NC}"
    echo -e "${NC}"
    
    IP=$(get_ip)
    echo -e " ${BANNER_YELLOW}🌐${NC} IP VPS   : ${BANNER_GREEN}$IP${NC}"
    echo -e " ${BANNER_YELLOW}⏱️${NC} Uptime  : ${BANNER_YELLOW}$(uptime -p)${NC}"
    echo -e " ${BANNER_YELLOW}🧠${NC} RAM     : ${BANNER_BLUE}$(free -m | awk '/Mem:/ {print $3 "/" $2 " MB"}')${NC}"
    echo -e " ${BANNER_YELLOW}💽${NC} Disco   : ${BANNER_BLUE}$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')${NC}"
    echo -e " ${BANNER_YELLOW}🌐${NC} WebSocket SSH : $(service_status maritima-ws)"
    echo -e " ${BANNER_YELLOW}🔐${NC} XRAY REALITY  : $(service_status xray)"
    echo -e " ${BANNER_YELLOW}🎮${NC} BadVPN UDP    : $(service_status maritima-badvpn)"
    echo -e " ${BANNER_YELLOW}🌐${NC} HTTP Proxy Banner : $(service_status maritima-http)"
    
    # Conexões ativas (simples)
    CONNECTIONS=$(ss -tn 2>/dev/null | grep -c ESTABLISHED)
    echo -e " ${BANNER_YELLOW}🔗${NC} Conexões ativas : ${BANNER_GREEN}$CONNECTIONS${NC}"
    
    # Usuários cadastrados
    USER_COUNT=$(wc -l < "$DB" 2>/dev/null || echo 0)
    echo -e " ${BANNER_YELLOW}👥${NC} Usuários total : ${BANNER_GREEN}$USER_COUNT${NC}"
    
    pause
}

# ================== 2. GERENCIAR USUÁRIOS ==================
add_user() {
    clear
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${CYAN}📝 CRIAR NOVO USUÁRIO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    read -rp "Login: " u
    read -rp "Senha: " p
    read -rp "Dias (0 para vitalício): " d
    read -rp "Limite conexões: " l
    
    # Validações
    [[ -z "$u" ]] && { echo -e "${RED}Login inválido${NC}"; pause; return; }
    [[ -z "$p" ]] && { echo -e "${RED}Senha inválida${NC}"; pause; return; }
    [[ -z "$l" ]] && l=1
    
    if id "$u" &>/dev/null; then
        echo -e "${RED}Usuário já existe${NC}"
        pause; return
    fi
    
    # Cria usuário
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    
    # Gera UUID para Reality
    UUID=$(uuidgen)
    
    # Define expiração
    if [[ "$d" -eq "0" ]]; then
        EXP="NUNCA"
    else
        EXP=$(date -d "+$d days" +%Y-%m-%d)
    fi
    
    # Salva no banco
    echo "$u:$p:$EXP:$l:$UUID" >> "$DB"
    
    # Adiciona ao Xray
    add_reality_user "$UUID"
    
    echo -e "${BANNER_GREEN}✅ Usuário criado com sucesso!${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "👤 ${GREEN}$u${NC} | 🔑 ${YELLOW}$p${NC} | 📅 ${WHITE}$EXP${NC}"
    echo -e "🔐 ${GRAY}UUID: $UUID${NC}"
    
    pause
}

list_users() {
    clear
    IP=$(get_ip)
    TOTAL=$(wc -l < "$DB" 2>/dev/null || echo 0)
    TODAY=$(date +%Y-%m-%d)
    
    echo -e "${CYAN}${BOLD}👥 USUÁRIOS CADASTRADOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "📊 Total: ${GREEN}$TOTAL usuários${NC} | 🌐 IP: ${YELLOW}$IP${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    if [[ $TOTAL -eq 0 ]]; then
        echo -e "${GRAY}Nenhum usuário cadastrado${NC}"
    else
        ACTIVE=0
        while IFS=: read -r u p e l uuid; do
            [[ -z "$u" ]] && continue
            
            # Status
            if [[ "$e" == "TESTE" ]] || [[ "$e" == "NUNCA" ]] || [[ "$e" > "$TODAY" ]]; then
                STATUS="${BANNER_GREEN}●${NC}"
                ((ACTIVE++))
            else
                STATUS="${RED}●${NC}"
            fi
            
            echo -e "$STATUS ${GREEN}$u${NC} | 🔑 ${YELLOW}$p${NC} | 📅 ${WHITE}$e${NC}"
            echo -e "   ${GRAY}SSH: ssh://$u:$p@$IP:22${NC}"
            [[ -n "$uuid" ]] && echo -e "   ${GRAY}UUID: $uuid${NC}"
            echo -e "${LINE_COLOR}──────────────────────────────────────${NC}"
        done < "$DB"
        
        echo -e "📈 ${CYAN}ATIVOS:${NC} ${GREEN}$ACTIVE${NC} | ${RED}EXPIRADOS:${NC} $((TOTAL - ACTIVE))"
    fi
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

del_user() {
    clear
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${RED}🗑️ REMOVER USUÁRIO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    read -rp "Usuário para remover: " u
    
    LINE=$(grep "^$u:" "$DB" || true)
    UUID=$(echo "$LINE" | cut -d: -f5)
    
    if [[ -n "$LINE" ]]; then
        userdel "$u" 2>/dev/null || true
        sed -i "/^$u:/d" "$DB"
        [[ -n "$UUID" ]] && remove_reality_user "$UUID"
        echo -e "${BANNER_GREEN}✅ Usuário removido${NC}"
    else
        echo -e "${RED}Usuário não encontrado${NC}"
    fi
    
    pause
}

# ================== 2.1 GERENCIAMENTO AVANÇADO ==================
user_management() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}👥 GERENCIAMENTO AVANÇADO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Renovar usuário${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Mudar senha${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Ver detalhes${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Exportar lista${NC}"
    echo -e "${YELLOW}5)${NC} ${WHITE}Limpar expirados${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " opt
    
    case $opt in
        1) renew_user ;;
        2) change_password ;;
        3) user_details ;;
        4) export_users ;;
        5) clean_expired ;;
        0) break ;;
        *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
    esac
    done
}

renew_user() {
    clear
    echo -e "${CYAN}${BOLD}🔄 RENOVAR USUÁRIO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    read -rp "Usuário: " u
    LINE=$(grep "^$u:" "$DB" || true)
    
    if [[ -z "$LINE" ]]; then
        echo -e "${RED}Usuário não encontrado${NC}"
        pause
        return
    fi
    
    IFS=: read -r user pass old_exp limit uuid <<< "$LINE"
    
    echo -e "\n👤 Usuário: ${GREEN}$user${NC}"
    echo -e "📅 Expira atual: ${YELLOW}$old_exp${NC}"
    
    read -rp "Adicionar quantos dias? (0=vitalício) " days
    
    if [[ "$days" -eq "0" ]]; then
        new_exp="NUNCA"
    elif [[ "$old_exp" == "NUNCA" ]]; then
        new_exp=$(date -d "+$days days" +%Y-%m-%d)
    elif [[ "$old_exp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        new_exp=$(date -d "$old_exp + $days days" +%Y-%m-%d 2>/dev/null || date -d "+$days days" +%Y-%m-%d)
    else
        new_exp=$(date -d "+$days days" +%Y-%m-%d)
    fi
    
    # Atualiza
    sed -i "/^$u:/c\\$user:$pass:$new_exp:$limit:$uuid" "$DB"
    
    echo -e "\n${GREEN}✅ Usuário renovado!${NC}"
    echo -e "📅 Nova data: ${BANNER_GREEN}$new_exp${NC}"
    
    pause
}

change_password() {
    clear
    echo -e "${CYAN}${BOLD}🔑 MUDAR SENHA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    read -rp "Usuário: " u
    LINE=$(grep "^$u:" "$DB" || true)
    
    if [[ -z "$LINE" ]]; then
        echo -e "${RED}Usuário não encontrado${NC}"
        pause
        return
    fi
    
    IFS=: read -r user old_pass exp limit uuid <<< "$LINE"
    
    echo -e "\n👤 Usuário: ${GREEN}$user${NC}"
    read -rp "Nova senha: " new_pass
    read -rp "Confirmar: " confirm_pass
    
    if [[ "$new_pass" != "$confirm_pass" ]]; then
        echo -e "${RED}Senhas não conferem${NC}"
        pause
        return
    fi
    
    # Altera senha
    echo "$user:$new_pass" | chpasswd
    sed -i "/^$u:/c\\$user:$new_pass:$exp:$limit:$uuid" "$DB"
    
    echo -e "\n${GREEN}✅ Senha alterada!${NC}"
    pause
}

user_details() {
    clear
    read -rp "Usuário: " u
    
    LINE=$(grep "^$u:" "$DB" || true)
    if [[ -z "$LINE" ]]; then
        echo -e "${RED}Usuário não encontrado${NC}"
        pause
        return
    fi
    
    IFS=: read -r user pass exp limit uuid <<< "$LINE"
    IP=$(get_ip)
    
    echo -e "${CYAN}${BOLD}📋 DETALHES DO USUÁRIO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "👤 ${GREEN}$user${NC}"
    echo -e "🔑 Senha: ${YELLOW}$pass${NC}"
    echo -e "📅 Expira: ${WHITE}$exp${NC}"
    echo -e "📶 Limite: ${WHITE}$limit conexões${NC}"
    [[ -n "$uuid" ]] && echo -e "🔐 UUID: ${GRAY}$uuid${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}Links:${NC}"
    echo -e "SSH: ${GRAY}ssh://$user:$pass@$IP:22${NC}"
    echo -e "WebSocket: ${GRAY}http://$IP:80${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    pause
}

export_users() {
    clear
    echo -e "${CYAN}${BOLD}📤 EXPORTAR USUÁRIOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    BACKUP_FILE="$BACKUP_DIR/users_$(date +%Y%m%d_%H%M%S).txt"
    cp "$DB" "$BACKUP_FILE"
    
    echo -e "✅ Exportado para: ${GREEN}$BACKUP_FILE${NC}"
    echo -e "📊 Total: ${YELLOW}$(wc -l < "$DB") usuários${NC}"
    
    pause
}

clean_expired() {
    clear
    echo -e "${CYAN}${BOLD}🧹 LIMPAR USUÁRIOS EXPIRADOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    TODAY=$(date +%Y-%m-%d)
    COUNT=0
    
    while IFS=: read -r u p e l uuid; do
        [[ -z "$u" ]] && continue
        
        if [[ "$e" != "TESTE" ]] && [[ "$e" != "NUNCA" ]] && [[ "$e" < "$TODAY" ]]; then
            userdel "$u" 2>/dev/null
            [[ -n "$uuid" ]] && remove_reality_user "$uuid"
            sed -i "/^$u:/d" "$DB"
            echo -e "❌ Removido: ${RED}$u${NC}"
            ((COUNT++))
        fi
    done < "$DB"
    
    echo -e "\n${GREEN}✅ Limpeza concluída!${NC}"
    echo -e "🗑️  Removidos: ${YELLOW}$COUNT usuários${NC}"
    
    pause
}

# ================== 3. PROTOCOLOS ==================
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
    echo -e "${YELLOW}6)${NC} ${WHITE}Testar portas${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " p
    
    case $p in
        1) systemctl is-active maritima-ws &>/dev/null && \
           systemctl stop maritima-ws || systemctl start maritima-ws ;;
        2) systemctl is-active xray &>/dev/null && \
           systemctl stop xray || systemctl start xray ;;
        3) systemctl is-active maritima-badvpn &>/dev/null && \
           systemctl stop maritima-badvpn || systemctl start maritima-badvpn ;;
        4) systemctl is-active maritima-http &>/dev/null && \
           systemctl stop maritima-http || systemctl start maritima-http ;;
        5) reality_links ;;
        6) test_ports ;;
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
        echo -e "${GRAY}vless://$uuid@$IP:443?encryption=none&security=reality&sni=www.google.com&fp=chrome&pbk=$REALITY_PBK&type=tcp#MARITIMA-$u${NC}"
        echo -e "${LINE_COLOR}──────────────────────────────────────${NC}"
    done < "$DB"
    
    pause
}

test_ports() {
    clear
    echo -e "${CYAN}${BOLD}🔍 TESTAR PORTAS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    IP=$(get_ip)
    PORTS=("22" "80" "443" "7300" "3128" "1194")
    
    for port in "${PORTS[@]}"; do
        timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo -e "✅ Porta ${GREEN}$port${NC} aberta"
        else
            echo -e "❌ Porta ${RED}$port${NC} fechada"
        fi
    done
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== 4. BANNER ==================
banner_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}📢 BANNER HTTP INJECTOR${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Ver banner${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Editar banner${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Limpar banner${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Testar banner${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " b
    case $b in
        1) clear; cat "$BANNER"; pause ;;
        2) nano "$BANNER" ;;
        3) > "$BANNER"; echo -e "${GREEN}✅ Banner limpo${NC}"; sleep 1 ;;
        4) echo -e "${YELLOW}Testando...${NC}"; curl -s http://localhost:80 2>/dev/null | head -10; pause ;;
        0) break ;;
    esac
    done
}

# ================== 5. SPEED TEST ==================
speed_test() {
    clear
    echo -e "${CYAN}${BOLD}🚀 TESTE DE VELOCIDADE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Iniciando teste...${NC}"
    echo
    
    # Verifica se speedtest está instalado
    if ! command -v speedtest &> /dev/null; then
        echo -e "${RED}Instalando speedtest-cli...${NC}"
        apt update && apt install -y speedtest-cli 2>/dev/null || \
        curl -s https://install.speedtest.net/app/cli/install.deb.sh | sudo bash && \
        apt install -y speedtest 2>/dev/null
    fi
    
    if command -v speedtest &> /dev/null; then
        speedtest --accept-license --accept-gdpr --simple
    else
        echo -e "${RED}Não foi possível executar o teste${NC}"
        echo -e "Instale manualmente: apt install speedtest-cli"
    fi
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== 6. MONITORAMENTO TEMPO REAL ==================
monitor() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}👁️ MONITORAMENTO EM TEMPO REAL${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Data/hora
    echo -e "🕐 ${WHITE}$(date '+%d/%m/%Y %H:%M:%S')${NC}"
    
    # Conexões ativas
    echo -e "\n${YELLOW}🔗 CONEXÕES ATIVAS:${NC}"
    echo -e "SSH:     $(ss -tn sport = :22 state established 2>/dev/null | wc -l)"
    echo -e "WebSocket: $(ss -tn sport = :80 state established 2>/dev/null | wc -l)"
    echo -e "Reality:  $(ss -tn sport = :443 state established 2>/dev/null | wc -l)"
    
    # Uso de recursos
    echo -e "\n${YELLOW}📊 RECURSOS:${NC}"
    echo -e "CPU:     $(top -bn1 | grep "Cpu(s)" | awk '{print $2"%"}')"
    echo -e "RAM:     $(free -m | awk '/Mem:/ {printf "%.1f%%", $3/$2*100}')"
    echo -e "Disco:   $(df -h / | awk 'NR==2 {print $5}')"
    
    # Usuários online
    echo -e "\n${YELLOW}👤 USUÁRIOS ONLINE:${NC}"
    who | awk '{print "  "$1" ("$2")"}' | head -5
    
    # Logs recentes
    echo -e "\n${YELLOW}📝 ÚLTIMAS CONEXÕES:${NC}"
    journalctl -u maritima-ws -n 3 --no-pager 2>/dev/null | grep -i "conexão\|connected" | tail -2 || \
    echo "  Nenhum log recente"
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}R${NC} Recarregar | ${RED}Q${NC} Sair"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Aguarda input
    read -t 5 -n 1 -r key
    case $key in
        q|Q) break ;;
        *) sleep 2 ;;
    esac
    done
}

# ================== 7. BACKUP & RESTAURAÇÃO ==================
backup_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}💾 BACKUP & RESTAURAÇÃO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Criar backup agora${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Restaurar backup${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Listar backups${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Agendar backup${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " b
    case $b in
        1) create_backup ;;
        2) restore_backup ;;
        3) list_backups ;;
        4) schedule_backup ;;
        0) break ;;
    esac
    done
}

create_backup() {
    clear
    echo -e "${CYAN}${BOLD}💾 CRIANDO BACKUP${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # Cria backup
    tar -czf "$BACKUP_FILE" \
        "$DB" \
        "$BANNER" \
        /etc/ssh/sshd_config \
        /usr/local/etc/xray/config.json \
        /etc/systemd/system/maritima-*.service \
        2>/dev/null
    
    if [[ -f "$BACKUP_FILE" ]]; then
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "✅ ${GREEN}Backup criado!${NC}"
        echo -e "📁 Arquivo: ${YELLOW}$BACKUP_FILE${NC}"
        echo -e "📦 Tamanho: ${WHITE}$SIZE${NC}"
    else
        echo -e "${RED}❌ Falha ao criar backup${NC}"
    fi
    
    pause
}

list_backups() {
    clear
    echo -e "${CYAN}${BOLD}📋 LISTA DE BACKUPS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    if ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null; then
        echo -e "\n${GREEN}Backups encontrados:${NC}"
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  "$9" ("$5")"}'
    else
        echo -e "${GRAY}Nenhum backup encontrado${NC}"
    fi
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== 8. SEGURANÇA ==================
security_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}🔒 SEGURANÇA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Ver logs de acesso${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Bloquear IP${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Listar IPs bloqueados${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Desbloquear IP${NC}"
    echo -e "${YELLOW}5)${NC} ${WHITE}Mudar porta SSH${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " s
    case $s in
        1) view_logs ;;
        2) block_ip ;;
        3) list_blocked ;;
        4) unblock_ip ;;
        5) change_ssh_port ;;
        0) break ;;
    esac
    done
}

view_logs() {
    clear
    echo -e "${CYAN}${BOLD}📝 LOGS DE ACESSO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    echo -e "${YELLOW}Últimas tentativas SSH:${NC}"
    journalctl -u ssh --no-pager -n 20 | grep -i "failed\|accepted" | tail -10
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== 9. OTIMIZAÇÃO ==================
optimize_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}⚡ OTIMIZAÇÃO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Limpar cache${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Otimizar memória${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Verificar updates${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Reparar permissões${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o
    case $o in
        1) clear_cache ;;
        2) optimize_memory ;;
        3) check_updates ;;
        4) fix_permissions ;;
        0) break ;;
    esac
    done
}

clear_cache() {
    clear
    echo -e "${CYAN}${BOLD}🧹 LIMPANDO CACHE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    sync
    echo 3 > /proc/sys/vm/drop_caches
    apt clean
    apt autoclean
    
    echo -e "${GREEN}✅ Cache limpo!${NC}"
    pause
}

# ================== 10. RELATÓRIOS ==================
reports_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}📈 RELATÓRIOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Relatório diário${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Top usuários${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Estatísticas gerais${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " r
    case $r in
        1) daily_report ;;
        2) top_users ;;
        3) general_stats ;;
        0) break ;;
    esac
    done
}

daily_report() {
    clear
    IP=$(get_ip)
    DATE=$(date '+%d/%m/%Y')
    
    echo -e "${CYAN}${BOLD}📅 RELATÓRIO DIÁRIO - $DATE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Informações básicas
    echo -e "🌐 IP: ${YELLOW}$IP${NC}"
    echo -e "🕐 Gerado em: ${WHITE}$(date '+%H:%M:%S')${NC}"
    
    # Estatísticas de usuários
    TOTAL=$(wc -l < "$DB" 2>/dev/null || echo 0)
    TODAY=$(date +%Y-%m-%d)
    ACTIVE=0
    TEST=0
    
    while IFS=: read -r u p e l uuid; do
        [[ -z "$u" ]] && continue
        if [[ "$e" == "TESTE" ]]; then
            ((TEST++))
        elif [[ "$e" == "NUNCA" ]] || [[ "$e" > "$TODAY" ]]; then
            ((ACTIVE++))
        fi
    done < "$DB"
    
    echo -e "\n${YELLOW}👥 USUÁRIOS:${NC}"
    echo -e "Total: ${WHITE}$TOTAL${NC}"
    echo -e "Ativos: ${GREEN}$ACTIVE${NC}"
    echo -e "Teste: ${BLUE}$TEST${NC}"
    echo -e "Expirados: ${RED}$((TOTAL - ACTIVE - TEST))${NC}"
    
    # Status serviços
    echo -e "\n${YELLOW}🔧 SERVIÇOS:${NC}"
    echo -e "WebSocket: $(service_status maritima-ws)"
    echo -e "Xray Reality: $(service_status xray)"
    echo -e "BadVPN: $(service_status maritima-badvpn)"
    
    # Conexões
    echo -e "\n${YELLOW}🔗 CONEXÕES:${NC}"
    echo -e "Ativas: ${WHITE}$(ss -tn state established 2>/dev/null | wc -l)${NC}"
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== 11. SISTEMA ==================
system_menu() {
    while true; do
    clear
    echo -e "${CYAN}${BOLD}🖥️ SISTEMA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1)${NC} ${WHITE}Informações do sistema${NC}"
    echo -e "${YELLOW}2)${NC} ${WHITE}Reiniciar serviços${NC}"
    echo -e "${YELLOW}3)${NC} ${WHITE}Atualizar painel${NC}"
    echo -e "${YELLOW}4)${NC} ${WHITE}Reiniciar VPS${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " s
    case $s in
        1) system_info ;;
        2) restart_services ;;
        3) update_panel ;;
        4) reboot_vps ;;
        0) break ;;
    esac
    done
}

system_info() {
    clear
    echo -e "${CYAN}${BOLD}🖥️ INFORMAÇÕES DO SISTEMA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Sistema
    echo -e "${YELLOW}SISTEMA:${NC}"
    echo -e "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo -e "  Kernel: $(uname -r)"
    echo -e "  Uptime: $(uptime -p | sed 's/up //')"
    
    # Hardware
    echo -e "\n${YELLOW}HARDWARE:${NC}"
    echo -e "  CPU: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    echo -e "  Núcleos: $(nproc)"
    echo -e "  RAM: $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
    echo -e "  Disco: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    
    # Rede
    echo -e "\n${YELLOW}REDE:${NC}"
    echo -e "  IP: $(get_ip)"
    echo -e "  Hostname: $(hostname)"
    
    # Temperatura (se disponível)
    if command -v sensors &> /dev/null; then
        TEMP=$(sensors | grep -i "core" | head -1 | awk '{print $3}')
        echo -e "  Temperatura: $TEMP"
    fi
    
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================== USUÁRIO TESTE ==================
add_test_user() {
    clear
    echo -e "${CYAN}${BOLD}🧪 CRIAR USUÁRIO TESTE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    mkdir -p /opt/maritima/test
    
    read -rp "Login teste: " u
    [[ -z "$u" ]] && { echo -e "${RED}Login inválido${NC}"; pause; return; }
    
    if id "$u" &>/dev/null; then
        echo -e "${RED}Usuário já existe${NC}"
        pause; return
    fi
    
    read -rp "Senha: " p
    [[ -z "$p" ]] && { echo -e "${RED}Senha inválida${NC}"; pause; return; }
    
    read -rp "Limite conexões: " l
    [[ -z "$l" ]] && l=1
    
    read -rp "Validade (minutos): " m
    [[ -z "$m" ]] && { echo -e "${RED}Tempo inválido${NC}"; pause; return; }
    
    EXP=$(date -d "+$m minutes" +"%Y-%m-%d %H:%M")
    
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    
    echo "$u:$p:TESTE:$l:$EXP" >> "$DB"
    
    # Script de remoção automática
    cat > /opt/maritima/test/$u.sh << EOF
#!/bin/bash
sleep $((m * 60))
pkill -u $u 2>/dev/null
userdel --force $u 2>/dev/null
sed -i '/^$u:/d' "$DB"
rm -f /opt/maritima/test/$u.sh
EOF
    
    chmod +x /opt/maritima/test/$u.sh
    nohup /bin/bash /opt/maritima/test/$u.sh >/dev/null 2>&1 &
    
    IP=$(get_ip)
    
    clear
    echo -e "${BANNER_GREEN}${BOLD}✅ USUÁRIO TESTE CRIADO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "🌐 IP: ${GREEN}$IP${NC}"
    echo -e "👤 Usuário: ${GREEN}$u${NC}"
    echo -e "🔑 Senha: ${YELLOW}$p${NC}"
    echo -e "📶 Limite: $l"
    echo -e "⏱️ Expira: ${RED}$m minutos${NC}"
    echo -e "${YELLOW}⚠ Após o tempo, será removido automaticamente${NC}"
    
    pause
}

# ================== MENU PRINCIPAL ==================
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
echo -e "${YELLOW}6)${NC} ${YELLOW}👁️${NC} ${WHITE}Monitoramento${NC}"
echo -e "${YELLOW}7)${NC} ${CYAN}💾${NC} ${WHITE}Backup${NC}"
echo -e "${YELLOW}8)${NC} ${RED}🔒${NC} ${WHITE}Segurança${NC}"
echo -e "${YELLOW}9)${NC} ${GREEN}⚡${NC} ${WHITE}Otimização${NC}"
echo -e "${YELLOW}10)${NC} ${BLUE}📈${NC} ${WHITE}Relatórios${NC}"
echo -e "${YELLOW}11)${NC} ${PURPLE}🖥️${NC} ${WHITE}Sistema${NC}"
echo -e "${RED}0)${NC} ${BANNER_RED}👿${NC} ${WHITE}Sair${NC}"
echo -e "${BANNER_CYAN}══════════════════════════════${NC}"
read -rp "Opção: " op

case $op in
    1) 
        while true; do
        clear
        echo -e "${CYAN}${BOLD}👥 USUÁRIOS${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        echo -e "${YELLOW}1)${NC} ${WHITE}Criar usuário${NC}"
        echo -e "${YELLOW}2)${NC} ${WHITE}Listar usuários${NC}"
        echo -e "${YELLOW}3)${NC} ${WHITE}Remover usuário${NC}"
        echo -e "${YELLOW}4)${NC} ${WHITE}Criar usuário TESTE${NC}"
        echo -e "${YELLOW}5)${NC} ${WHITE}Gerenciamento avançado${NC}"
        echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        read -rp "Opção: " u
        case $u in
            1) add_user ;;
            2) list_users ;;
            3) del_user ;;
            4) add_test_user ;;
            5) user_management ;;
            0) break ;;
        esac
        done
        ;;
    2) protocol_menu ;;
    3) status_vps ;;
    4) banner_menu ;;
    5) speed_test ;;
    6) monitor ;;
    7) backup_menu ;;
    8) security_menu ;;
    9) optimize_menu ;;
    10) reports_menu ;;
    11) system_menu ;;
    0) clear; echo -e "${GREEN}Até logo! 👋${NC}"; exit 0 ;;
    *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
esac
done
