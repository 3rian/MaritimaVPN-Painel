#!/usr/bin/env bash
export TERM=xterm
set -euo pipefail
declare -a USERS


# ---------- CORES ----------
CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
GRAY='\033[1;90m'
BLACK='\033[1;30m'
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

pause() { 
    echo
    read -rp "$(echo -e "${YELLOW}Pressione ENTER para continuar...${NC}")" 
    echo
}

get_ip() {
    local ip
    ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "")
    [[ -z "$ip" ]] && ip="IP-INDEFINIDO"
    echo "$ip"
}

service_status() {
    if systemctl is-active "$1" &>/dev/null; then
        echo -e "${BANNER_GREEN}● ATIVO${NC}"
    else
        echo -e "${RED}● OFF${NC}"
    fi
}

# ================== FUNÇÕES DE EXPIRAÇÃO ==================

# Calcula dias restantes
calculate_days_left() {
    local exp_date="$1"
    local today
    
    if [[ "$exp_date" == "NUNCA" ]]; then
        echo "∞"
        return
    fi
    
    if [[ "$exp_date" == "TESTE" ]]; then
        echo "TESTE"
        return
    fi
    
    # Para datas no formato YYYY-MM-DD
    if [[ "$exp_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        today=$(date +%Y-%m-%d)
        
        # Converter para timestamp
        local exp_seconds
        local today_seconds
        exp_seconds=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
        today_seconds=$(date -d "$today" +%s 2>/dev/null || echo 0)
        
        if [[ $exp_seconds -eq 0 ]] || [[ $today_seconds -eq 0 ]]; then
            echo "?"
            return
        fi
        
        local diff=$(( (exp_seconds - today_seconds) / 86400 ))
        
        if [[ $diff -lt 0 ]]; then
            echo "0"
        else
            echo "$diff"
        fi
        return
    fi
    
    echo "?"
}

# Verifica e limpa usuários expirados
cleanup_expired_users() {
    local today
    today=$(date +%Y-%m-%d)
    
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        return
    fi
    
    # Criar arquivo temporário
    local temp_file
    temp_file="${DB}.temp"
    
    > "$temp_file"
    
    while IFS=: read -r u p e l uuid; do
        # Pular linhas vazias
        [[ -z "$u" ]] && continue
        
        # Verificar se está expirado
        local remove=0
        
        if [[ "$e" == "TESTE" ]] && [[ "$uuid" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
            # Usuário TESTE com data/hora específica
            local exp_seconds
            exp_seconds=$(date -d "$uuid" +%s 2>/dev/null || echo 0)
            local now_seconds
            now_seconds=$(date +%s)
            
            if [[ $exp_seconds -gt 0 ]] && [[ $now_seconds -ge $exp_seconds ]]; then
                remove=1
            fi
        elif [[ "$e" != "NUNCA" ]] && [[ "$e" != "TESTE" ]]; then
            # Usuário normal com data de expiração
            if [[ "$e" < "$today" ]]; then
                remove=1
            fi
        fi
        
        if [[ $remove -eq 1 ]]; then
            # Remover usuário expirado
            userdel "$u" 2>/dev/null || true
            pkill -u "$u" 2>/dev/null || true
            echo -e "${YELLOW}Removido: $u (expirado)${NC}"
        else
            # Manter usuário
            echo "$u:$p:$e:$l:$uuid" >> "$temp_file"
        fi
        
    done < "$DB"
    
    # Substituir arquivo original
    if [[ -f "$temp_file" ]]; then
        mv "$temp_file" "$DB"
        rm -f "$temp_file"
    fi
}

# ================= STATUS VPS =================
status_vps() {
    cleanup_expired_users
    clear
    echo -e "${BANNER_CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BANNER_CYAN}║${NC}        ${BANNER_YELLOW}🏴‍☠️ MARÍTIMA VPN STATUS${NC}        ${BANNER_CYAN}║${NC}"
    echo -e "${BANNER_CYAN}╚══════════════════════════════════════╝${NC}"
    echo -e "${NC}"
    echo -e " ${BANNER_YELLOW}🌐${NC} IP VPS   : ${BANNER_GREEN}$(get_ip)${NC}"
    echo -e " ${BANNER_YELLOW}⏱️${NC} Uptime  : ${BANNER_YELLOW}$(uptime -p | sed 's/up //')${NC}"
    echo -e " ${BANNER_YELLOW}🧠${NC} RAM     : ${BANNER_BLUE}$(free -m | awk '/Mem:/ {printf "%.1f/%.1f MB (%.1f%%)", $3, $2, $3/$2*100}')${NC}"
    echo -e " ${BANNER_YELLOW}💽${NC} Disco   : ${BANNER_BLUE}$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')${NC}"
    echo -e " ${BANNER_YELLOW}🌐${NC} WebSocket SSH : $(service_status maritima-ws)"
    echo -e " ${BANNER_YELLOW}🔐${NC} XRAY REALITY  : $(service_status xray)"
    echo -e " ${BANNER_YELLOW}🎮${NC} BadVPN UDP    : $(service_status maritima-badvpn)"
    echo -e " ${BANNER_YELLOW}🌐${NC} HTTP Proxy Banner : $(service_status maritima-http)"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
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
    [[ -z "$u" ]] && { echo -e "${RED}Login não pode ser vazio${NC}"; pause; return; }
    
    if id "$u" &>/dev/null; then
        echo -e "${RED}Usuário já existe${NC}"
        pause
        return
    fi
    
    read -rp "Senha: " p
    [[ -z "$p" ]] && { echo -e "${RED}Senha não pode ser vazia${NC}"; pause; return; }
    
    read -rp "Dias (0=vitalício): " d
    if ! [[ "$d" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Digite um número válido${NC}"
        pause
        return
    fi
    
    read -rp "Limite conexões: " l
    if ! [[ "$l" =~ ^[0-9]+$ ]] || [[ "$l" -lt 1 ]]; then
        echo -e "${RED}Limite inválido (mínimo 1)${NC}"
        pause
        return
    fi
    
    # Criar usuário
    if useradd -M -s /bin/false "$u" 2>/dev/null; then
        echo "$u:$p" | chpasswd
        echo -e "${GREEN}✅ Usuário criado no sistema${NC}"
    else
        echo -e "${RED}Erro ao criar usuário${NC}"
        pause
        return
    fi
    
    # Definir expiração
    if [[ "$d" -eq 0 ]]; then
        EXP="NUNCA"
    else
        EXP=$(date -d "+$d days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d -d "+$d days")
    fi
    
    # Gerar UUID
    if command -v uuidgen &>/dev/null; then
        UUID=$(uuidgen)
    else
        UUID="uuid-$(date +%s)-$RANDOM"
    fi
    
    # Salvar no banco de dados
    echo "$u:$p:$EXP:$l:$UUID" >> "$DB"
    
    echo -e "${BANNER_GREEN}✅ Usuário criado com sucesso!${NC}"
    echo -e "📅 Expiração: ${YELLOW}$EXP${NC}"
    if [[ "$d" -gt 0 ]]; then
        echo -e "⏳ Dias restantes: ${GREEN}$d${NC}"
    fi
    pause
}

list_users() {
    cleanup_expired_users
    clear
    
    echo -e "${CYAN}${BOLD}👥 USUÁRIOS CADASTRADOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    # Verificar se há usuários
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        echo -e "${YELLOW}Nenhum usuário cadastrado${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        pause
        return
    fi
    
    IP=$(get_ip)
    local total=0
    
    while IFS=: read -r u p e l uuid || [[ -n "$u" ]]; do
        # Ignorar linhas vazias
        [[ -z "$u" ]] && continue
        ((total++))
        
        # Calcular dias restantes
        days_left=$(calculate_days_left "$e")
        
        # Determinar cor e ícone baseado no status
        if [[ "$e" == "NUNCA" ]]; then
            status_color="$GREEN"
            status_icon="✅"
            status_text="VITALÍCIO"
        elif [[ "$e" == "TESTE" ]]; then
            status_color="$YELLOW"
            status_icon="🧪"
            status_text="TESTE"
        elif [[ "$days_left" == "0" ]]; then
            status_color="$RED"
            status_icon="❌"
            status_text="EXPIRADO"
        else
            status_color="$GREEN"
            status_icon="✅"
            status_text="$days_left dias"
        fi
        
        # Mostrar informações
        echo -e "${status_icon} ${GREEN}$u${NC}"
        echo -e "   🔑 ${YELLOW}$p${NC}"
        echo -e "   📅 ${status_color}$e${NC}"
        echo -e "   ⏳ ${status_color}$status_text${NC}"
        echo -e "   📶 Limite: ${WHITE}$l conexões${NC}"
        echo -e "   🌐 ${GRAY}ssh://$u:$p@$IP:22${NC}"
        echo -e "${LINE_COLOR}──────────────────────────────────────${NC}"
        
    done < "$DB"
    
    echo -e "${BANNER_CYAN}📊 Total: $total usuário(s)${NC}"
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
    
    if [[ -z "$u" ]]; then
        echo -e "${RED}Digite um nome de usuário${NC}"
        pause
        return
    fi
    
    # Verificar se existe
    if ! id "$u" &>/dev/null; then
        echo -e "${YELLOW}Usuário não existe no sistema${NC}"
        
        # Verificar se está no banco de dados
        if grep -q "^$u:" "$DB" 2>/dev/null; then
            echo -e "${YELLOW}Removendo do banco de dados...${NC}"
            sed -i "/^$u:/d" "$DB"
            echo -e "${GREEN}✅ Removido do banco de dados${NC}"
        fi
        
        pause
        return
    fi
    
    # Confirmar remoção
    echo
    read -rp "Tem certeza que deseja remover '$u'? (s/n): " confirm
    
    if [[ "$confirm" == "s" ]] || [[ "$confirm" == "S" ]]; then
        # Remover do sistema
        userdel "$u" 2>/dev/null && echo -e "${GREEN}✅ Usuário removido do sistema${NC}"
        
        # Derrubar conexões
        pkill -u "$u" 2>/dev/null && echo -e "${YELLOW}Conexões ativas encerradas${NC}"
        
        # Remover do banco de dados
        sed -i "/^$u:/d" "$DB" && echo -e "${GREEN}✅ Removido do banco de dados${NC}"
        
        echo -e "${BANNER_GREEN}✅ Usuário completamente removido${NC}"
    else
        echo -e "${YELLOW}Operação cancelada${NC}"
    fi
    
    pause
}

change_limit() {
    clear
    echo -e "${CYAN}${BOLD}📶 ALTERAR LIMITE DE CONEXÕES${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Listar usuários
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        echo -e "${YELLOW}Nenhum usuário cadastrado${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        pause
        return
    fi
    
    echo -e "${YELLOW}Lista de usuários:${NC}"
    echo
    
    local i=1
    declare -A users_map
    
    while IFS=: read -r u p e l uuid || [[ -n "$u" ]]; do
        [[ -z "$u" ]] && continue
        echo -e "${YELLOW}[$i]${NC} ${GREEN}$u${NC} (limite atual: $l)"
        users_map[$i]="$u:$l"
        ((i++))
    done < "$DB"
    
    echo -e "${YELLOW}[0]${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    read -rp "Selecione o usuário: " opt
    
    if [[ "$opt" == "0" ]]; then
        return
    fi
    
    if ! [[ "$opt" =~ ^[0-9]+$ ]] || [[ -z "${users_map[$opt]}" ]]; then
        echo -e "${RED}Opção inválida${NC}"
        pause
        return
    fi
    
    # Extrair usuário e limite atual
    IFS=: read -r selected_user current_limit <<< "${users_map[$opt]}"
    
    echo
    echo -e "Usuário selecionado: ${GREEN}$selected_user${NC}"
    echo -e "Limite atual: ${YELLOW}$current_limit${NC}"
    echo
    
    read -rp "Novo limite de conexões: " new_limit
    
    if ! [[ "$new_limit" =~ ^[0-9]+$ ]] || [[ "$new_limit" -lt 1 ]]; then
        echo -e "${RED}Limite inválido (mínimo 1)${NC}"
        pause
        return
    fi
    
    # Atualizar no banco de dados
    # Recuperar dados reais do usuário
LINE=$(grep "^$selected_user:" "$DB")
IFS=: read -r u p e l uuid <<< "$LINE"

# Atualizar no banco de dados
sed -i "s|^$u:.*|$u:$p:$e:$new_limit:$uuid|" "$DB"

echo -e "${GREEN}✅ Limite alterado para $new_limit conexões${NC}"

    
    pause
}

change_password() {
    clear
    echo -e "${CYAN}${BOLD}🔑 ALTERAR SENHA DO USUÁRIO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Listar usuários
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        echo -e "${YELLOW}Nenhum usuário cadastrado${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        pause
        return
    fi
    
    echo -e "${YELLOW}Lista de usuários:${NC}"
    echo
    
    local i=1
    declare -A users_map
    
    while IFS=: read -r u p e l uuid || [[ -n "$u" ]]; do
        [[ -z "$u" ]] && continue
        echo -e "${YELLOW}[$i]${NC} ${GREEN}$u${NC}"
        users_map[$i]="$u:$p"
        ((i++))
    done < "$DB"
    
    echo -e "${YELLOW}[0]${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    read -rp "Selecione o usuário: " opt
    
    if [[ "$opt" == "0" ]]; then
        return
    fi
    
    if ! [[ "$opt" =~ ^[0-9]+$ ]] || [[ -z "${users_map[$opt]}" ]]; then
        echo -e "${RED}Opção inválida${NC}"
        pause
        return
    fi
    
    # Extrair usuário
    IFS=: read -r selected_user old_pass <<< "${users_map[$opt]}"
    
    echo
    echo -e "Usuário selecionado: ${GREEN}$selected_user${NC}"
    echo
    
    read -rp "Nova senha: " new_pass1
    read -rp "Confirmar senha: " new_pass2
    
    if [[ -z "$new_pass1" ]] || [[ ${#new_pass1} -lt 4 ]]; then
        echo -e "${RED}Senha muito curta (mínimo 4 caracteres)${NC}"
        pause
        return
    fi
    
    if [[ "$new_pass1" != "$new_pass2" ]]; then
        echo -e "${RED}Senhas não conferem${NC}"
        pause
        return
    fi
    
    # Alterar senha no sistema
    if echo "$selected_user:$new_pass1" | chpasswd 2>/dev/null; then
        echo -e "${GREEN}✅ Senha alterada no sistema${NC}"
    else
        echo -e "${RED}Erro ao alterar senha no sistema${NC}"
        pause
        return
    fi
    
    # Atualizar no banco de dados
    if sed -i "s/^$selected_user:$old_pass:/$selected_user:$new_pass1:/" "$DB" 2>/dev/null; then
        echo -e "${GREEN}✅ Senha atualizada no banco de dados${NC}"
    fi
    
    # Encerrar conexões ativas
    pkill -u "$selected_user" 2>/dev/null && echo -e "${YELLOW}Conexões ativas encerradas${NC}"
    
    pause
}

change_expiration() {
    clear
    echo -e "${CYAN}${BOLD}📅 ALTERAR DATA DE EXPIRAÇÃO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    # Listar usuários
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        echo -e "${YELLOW}Nenhum usuário cadastrado${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        pause
        return
    fi
    
    echo -e "${YELLOW}Lista de usuários:${NC}"
    echo
    
    local i=1
    declare -A users_map
    
    while IFS=: read -r u p e l uuid || [[ -n "$u" ]]; do
        [[ -z "$u" ]] && continue
        days_left=$(calculate_days_left "$e")
        
        if [[ "$e" == "NUNCA" ]]; then
            status="VITALÍCIO"
            color="$GREEN"
        elif [[ "$e" == "TESTE" ]]; then
            status="TESTE"
            color="$YELLOW"
        elif [[ "$days_left" == "0" ]]; then
            status="EXPIRADO"
            color="$RED"
        else
            status="$days_left dias"
            color="$GREEN"
        fi
        
        echo -e "${YELLOW}[$i]${NC} ${GREEN}$u${NC} - ${color}$status${NC}"
        users_map[$i]="$u:$e:$p:$l:$uuid"
        ((i++))
    done < "$DB"
    
    echo -e "${YELLOW}[0]${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    read -rp "Selecione o usuário: " opt
    
    if [[ "$opt" == "0" ]]; then
        return
    fi
    
    if ! [[ "$opt" =~ ^[0-9]+$ ]] || [[ -z "${users_map[$opt]}" ]]; then
        echo -e "${RED}Opção inválida${NC}"
        pause
        return
    fi
    
    # Extrair dados do usuário
    IFS=: read -r selected_user current_exp pass limit uuid <<< "${users_map[$opt]}"
    
    clear
    echo -e "${CYAN}${BOLD}📅 ALTERAR DATA DE EXPIRAÇÃO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "Usuário: ${GREEN}$selected_user${NC}"
    echo -e "Expiração atual: ${YELLOW}$current_exp${NC}"
    echo
    
    echo -e "${WHITE}Formas de definir nova data:${NC}"
    echo -e "  ${YELLOW}30${NC}           - Adiciona 30 dias"
    echo -e "  ${YELLOW}2024-12-31${NC}   - Data específica (AAAA-MM-DD)"
    echo -e "  ${YELLOW}0${NC}            - Vitalício (NUNCA)"
    echo -e "  ${YELLOW}teste 60${NC}     - Conta TESTE por 60 minutos"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    read -rp "Nova data/dias: " input
    
    local new_exp
    local new_uuid="$uuid"
    
    case $input in
        0)
            new_exp="NUNCA"
            ;;
        "teste "*)
            local minutes=${input#teste }
            if [[ "$minutes" =~ ^[0-9]+$ ]]; then
                new_exp="TESTE"
                new_uuid=$(date -d "+$minutes minutes" +"%Y-%m-%d %H:%M")
            else
                echo -e "${RED}Minutos inválidos${NC}"
                pause
                return
            fi
            ;;
        *)
            if [[ "$input" =~ ^[0-9]+$ ]]; then
                # Número de dias
                new_exp=$(date -d "+$input days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d -d "+$input days")
            elif [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                # Data no formato AAAA-MM-DD
                new_exp="$input"
            else
                echo -e "${RED}Formato inválido${NC}"
                pause
                return
            fi
            ;;
    esac
    
    # Atualizar no banco de dados
    if sed -i "s/^$selected_user:$pass:$current_exp:$limit:$uuid/$selected_user:$pass:$new_exp:$limit:$new_uuid/" "$DB" 2>/dev/null; then
        echo -e "${GREEN}✅ Data de expiração alterada para: $new_exp${NC}"
        
        # Se estava expirado e agora não está, reativar
        if [[ "$current_exp" != "NUNCA" ]] && [[ "$current_exp" != "TESTE" ]]; then
            local old_days=$(calculate_days_left "$current_exp")
            if [[ "$old_days" == "0" ]]; then
                echo "$selected_user:$pass" | chpasswd 2>/dev/null && echo -e "${GREEN}✅ Usuário reativado${NC}"
            fi
        fi
    else
        echo -e "${RED}Erro ao alterar data${NC}"
    fi
    
    pause
}

add_test_user() {
    clear
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${CYAN}🧪 CRIAR USUÁRIO TESTE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo
    
    read -rp "Login teste: " u
    [[ -z "$u" ]] && { echo -e "${RED}Login não pode ser vazio${NC}"; pause; return; }
    
    if id "$u" &>/dev/null; then
        echo -e "${RED}Usuário já existe${NC}"
        pause
        return
    fi
    
    read -rp "Senha: " p
    [[ -z "$p" ]] && { echo -e "${RED}Senha não pode ser vazia${NC}"; pause; return; }
    
    read -rp "Limite conexões: " l
    if ! [[ "$l" =~ ^[0-9]+$ ]] || [[ "$l" -lt 1 ]]; then
        echo -e "${RED}Limite inválido (mínimo 1)${NC}"
        pause
        return
    fi
    
    read -rp "Validade (minutos): " m
    if ! [[ "$m" =~ ^[0-9]+$ ]] || [[ "$m" -lt 1 ]]; then
        echo -e "${RED}Validade inválida (mínimo 1 minuto)${NC}"
        pause
        return
    fi
    
    # Criar usuário
    if useradd -M -s /bin/false "$u" 2>/dev/null; then
        echo "$u:$p" | chpasswd
        echo -e "${GREEN}✅ Usuário criado no sistema${NC}"
    else
        echo -e "${RED}Erro ao criar usuário${NC}"
        pause
        return
    fi
    
    # Configurar como TESTE
    EXP="TESTE"
    EXPIRE_TIME=$(date -d "+$m minutes" +"%Y-%m-%d %H:%M")
    
    # Gerar UUID
    if command -v uuidgen &>/dev/null; then
        UUID=$(uuidgen)
    else
        UUID="teste-$(date +%s)-$RANDOM"
    fi
    
    # Salvar no banco de dados
    echo "$u:$p:$EXP:$l:$EXPIRE_TIME" >> "$DB"
    
    echo -e "${BANNER_GREEN}✅ USUÁRIO TESTE CRIADO!${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "👤 Login: ${GREEN}$u${NC}"
    echo -e "🔑 Senha: ${YELLOW}$p${NC}"
    echo -e "📶 Limite: ${WHITE}$l conexões${NC}"
    echo -e "⏱️  Validade: ${RED}$m minutos${NC}"
    echo -e "⏰ Expira em: ${YELLOW}$EXPIRE_TIME${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    pause
}

# ================= MENU USUÁRIOS =================
user_menu() {
    while true; do
        cleanup_expired_users
        clear
        
        echo -e "${CYAN}${BOLD}👥 GERENCIAR USUÁRIOS${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        echo -e "${YELLOW}1)${NC} ${WHITE}Criar usuário${NC}"
        echo -e "${YELLOW}2)${NC} ${WHITE}Listar usuários${NC}"
        echo -e "${YELLOW}3)${NC} ${WHITE}Remover usuário${NC}"
        echo -e "${YELLOW}4)${NC} ${WHITE}Criar usuário TESTE${NC}"
        echo -e "${YELLOW}5)${NC} ${WHITE}Limpar expirados${NC}"
        echo -e "${YELLOW}6)${NC} ${WHITE}Alterar limite${NC}"
        echo -e "${YELLOW}7)${NC} ${WHITE}Alterar senha${NC}"
        echo -e "${YELLOW}8)${NC} ${WHITE}Alterar data de expiração${NC}"
        echo -e "${RED}0)${NC} ${WHITE}Voltar ao menu principal${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        
        read -rp "Opção: " o
        
        case $o in
            1) add_user ;;
            2) list_users ;;
            3) del_user ;;
            4) add_test_user ;;
            5) cleanup_expired_users; echo -e "${GREEN}✅ Limpeza concluída${NC}"; sleep 2 ;;
            6) change_limit ;;
            7) change_password ;;
            8) change_expiration ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
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
            1) 
                if systemctl is-active maritima-ws &>/dev/null; then
                    systemctl stop maritima-ws
                    echo -e "${YELLOW}WebSocket SSH parado${NC}"
                else
                    systemctl start maritima-ws
                    echo -e "${GREEN}WebSocket SSH iniciado${NC}"
                fi
                sleep 1
                ;;
            2)
                if systemctl is-active xray &>/dev/null; then
                    systemctl stop xray
                    echo -e "${YELLOW}XRAY REALITY parado${NC}"
                else
                    systemctl start xray
                    echo -e "${GREEN}XRAY REALITY iniciado${NC}"
                fi
                sleep 1
                ;;
            3)
                if systemctl is-active maritima-badvpn &>/dev/null; then
                    systemctl stop maritima-badvpn
                    echo -e "${YELLOW}BadVPN UDP parado${NC}"
                else
                    systemctl start maritima-badvpn
                    echo -e "${GREEN}BadVPN UDP iniciado${NC}"
                fi
                sleep 1
                ;;
            4)
                if systemctl is-active maritima-http &>/dev/null; then
                    systemctl stop maritima-http
                    echo -e "${YELLOW}HTTP Proxy parado${NC}"
                else
                    systemctl start maritima-http
                    echo -e "${GREEN}HTTP Proxy iniciado${NC}"
                fi
                sleep 1
                ;;
            5) reality_links ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
        esac
    done
}

reality_links() {
    cleanup_expired_users
    clear
    
    echo -e "${CYAN}${BOLD}🔐 LINKS XRAY REALITY${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    
    if [[ ! -f "$DB" ]] || [[ ! -s "$DB" ]]; then
        echo -e "${YELLOW}Nenhum usuário cadastrado${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        pause
        return
    fi
    
    IP=$(get_ip)
    
    while IFS=: read -r u p e l uuid || [[ -n "$u" ]]; do
        [[ -z "$u" ]] && continue
        
        days_left=$(calculate_days_left "$e")
        
        if [[ "$e" != "NUNCA" ]] && [[ "$e" != "TESTE" ]] && [[ "$days_left" == "0" ]]; then
            echo -e "\n❌ ${RED}$u (EXPIRADO)${NC}"
            echo -e "   ${GRAY}Conta expirada - renove para gerar link${NC}"
        else
            echo -e "\n✅ ${GREEN}$u${NC}"
            echo -e "   ${WHITE}$e${NC} ${GRAY}($days_left)${NC}"
            
            # Verificar se UUID é válido para link
            if [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                echo -e "   ${GRAY}vless://$uuid@$IP:443?type=tcp&security=reality&sni=www.google.com#MARITIMA-$u${NC}"
            else
                echo -e "   ${YELLOW}UUID inválido para gerar link${NC}"
            fi
        fi
        
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
            1) 
                clear
                if [[ -s "$BANNER" ]]; then
                    echo -e "${CYAN}Conteúdo do banner:${NC}"
                    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
                    cat "$BANNER"
                else
                    echo -e "${YELLOW}Banner vazio${NC}"
                fi
                echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
                pause
                ;;
            2) 
                if command -v nano &>/dev/null; then
                    nano "$BANNER"
                elif command -v vi &>/dev/null; then
                    vi "$BANNER"
                else
                    echo -e "${RED}Editor de texto não encontrado${NC}"
                    sleep 2
                fi
                ;;
            3) 
                > "$BANNER"
                echo -e "${GREEN}✅ Banner limpo${NC}"
                sleep 1
                ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida${NC}"; sleep 1 ;;
        esac
    done
}

# ================= SPEED TEST =================
speed_test() {
    clear
    echo -e "${CYAN}🚀 TESTE DE VELOCIDADE${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo

    if ! command -v speedtest &>/dev/null; then
        echo "Instalando speedtest..."
        apt update -y >/dev/null 2>&1
        apt install -y speedtest >/dev/null 2>&1
    fi

    speedtest --accept-license --accept-gdpr --format=human-readable

    echo
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "ENTER para continuar..."
}





# ================= MENU PRINCIPAL =================
while true; do
    cleanup_expired_users
    
    clear
   echo -e "${BANNER_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BANNER_CYAN}║${NC}                                                      ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}          ${BANNER_RED}    _____${NC}                           ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}          ${BANNER_RED}   |     |__    __${NC}                   ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}          ${BANNER_RED}   |  🏴‍☠️  |  |  |${NC}    ${BANNER_YELLOW}MARÍTIMA VPN${NC}   ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}          ${BANNER_RED}   |_____|  |__|${NC}                     ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}          ${BANNER_RED}     ||        ||${NC}                     ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}║${NC}                                                      ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BANNER_CYAN}║${NC}  ${BANNER_GREEN}▶ ATIVO${NC}  ${BANNER_CYAN}│${NC}  ${BANNER_BLUE}☠️ XRAY${NC}  ${BANNER_CYAN}│${NC}  ${BANNER_PURPLE}⚓ WS${NC}  ${BANNER_CYAN}║${NC}"
echo -e "${BANNER_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
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
        0) 
            clear
            echo -e "${GREEN}Até logo! 👋${NC}"
            echo
            exit 0
            ;;
        *) 
            echo -e "${RED}Opção inválida${NC}"
            sleep 1
            ;;
    esac
done
