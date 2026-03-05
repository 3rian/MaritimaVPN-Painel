
#!/usr/bin/env bash
export TERM=xterm

# ---------- CORES ----------
CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'
ORANGE='\033[38;5;208m'   # Laranja
# ou use '\033[38;5;214m' para um laranja mais claro

BANNER_CYAN='\033[1;96m'
BANNER_BLUE='\033[1;94m'
BANNER_GREEN='\033[1;92m'
BANNER_YELLOW='\033[1;93m'
BANNER_RED='\033[1;91m'
LINE_COLOR='\033[1;90m'
NC=$'\033[0m'
BANNER_CYAN=$'\033[1;96m'
BANNER_YELLOW=$'\033[1;93m'
WHITE=$'\033[1;97m'
YELLOW=$'\033[1;93m'
ORANGE='\033[38;5;208m'   # Laranja
# ou use '\033[38;5;214m' para um laranja mais claro

BASE="/opt/maritima"
DB="$BASE/users.db"
BANNER="$BASE/banner.txt"

WS_DIR="$BASE/ws"
WS_PY="$WS_DIR/wsproxy.py"
WS_PORT="2082"
NGINX_WS_PORT="8080"

XRAY_DIR="/usr/local/etc/xray"
XRAY_CFG="$XRAY_DIR/config.json"

DOM_ROOT="maritimavpn.shop"
DOM_VLESS="vless.maritimavpn.shop"
DOM_SQUID="squid.maritimavpn.shop"
DOM_WS="ws.maritimavpn.shop"





mkdir -p "$BASE"
touch "$DB" "$BANNER"

pause() { read -rp "ENTER para continuar..."; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Rode como root.${NC}"
    exit 1
  fi
}

get_ip() {
  local ip
  ip=$(curl -s --max-time 3 ifconfig.me || true)
  [[ -z "$ip" ]] && ip="IP-INDEFINIDO"
  echo "$ip"
}

service_status() {
  systemctl is-active "$1" &>/dev/null && \
  echo -e "${BANNER_GREEN}● ATIVO${NC}" || echo -e "${RED}● OFF${NC}"
}

install_pkgs() {
  need_root
  apt update -y
  apt install -y curl ca-certificates jq uuid-runtime nginx python3 lsof socat openssl
}

ensure_alias() {
  # cria /usr/local/bin/maritima (atalho para o painel)
  cat >/usr/local/bin/maritima <<'EOF'
#!/usr/bin/env bash
exec bash /root/maritima.sh
EOF
  chmod +x /usr/local/bin/maritima
}


save_self() {
  # opcional: guarda o script no /opt/maritima
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    cp -f "${BASH_SOURCE[0]}" /opt/maritima/maritima.sh
    chmod +x /opt/maritima/maritima.sh
  fi
}


# ================= STATUS VPS =================

# Função para desenhar uma linha centralizada dentro da caixa de 38 colunas
# Uso: centered_line "texto com cores (opcionais)"
centered_line() {
    local text="$1"
    # Remove códigos ANSI para calcular o comprimento visível
    local visible=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local visible_len=${#visible}
    local box_width=38
    local total_pad=$((box_width - visible_len))
    local left_pad=$((total_pad / 2))
    local right_pad=$((total_pad - left_pad))

    printf "%b║%b%*s%b%*s%b║%b\n" \
           "$BANNER_CYAN" \
           "$text" \
           $left_pad "" \
           "$BANNER_CYAN" \
           $right_pad "" \
           "$BANNER_CYAN" \
           "$NC"
}

status_vps() {
    clear

    # Cabeçalho com caixa fixa e título centralizado
    printf "%b╔══════════════════════════════════════╗%b\n" "$BANNER_CYAN" "$NC"
    centered_line "🏴‍☠️ ${BANNER_YELLOW}MARÍTIMA VPN PANEL${NC} 🏴‍☠️"
    printf "%b╚══════════════════════════════════════╝%b\n" "$BANNER_CYAN" "$NC"




local ip uptime ram disk tloc tutc ntp tz
ip="$(get_ip)"
uptime="$(uptime -p)"
ram="$(free -m | awk '/Mem:/ {print $3 "/" $2 " MB"}')"
disk="$(df -h / | awk 'NR==2 {print $3 "/" $2}')"

tloc="$(date '+%Y-%m-%d %H:%M:%S %Z')"
tutc="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
tz="$(timedatectl show -p Timezone --value 2>/dev/null)"
ntp="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"

echo -e " ${BANNER_YELLOW}🌐${NC} IP VPS   : ${BANNER_GREEN}${ip}${NC}"
echo -e " ${BANNER_YELLOW}⏱️${NC} Uptime  : ${BANNER_YELLOW}${uptime}${NC}"
echo -e " ${BANNER_YELLOW}🕒${NC} Hora    : ${BANNER_YELLOW}${tloc}${NC} | ${BANNER_YELLOW}${tutc}${NC}"
echo -e " ${BANNER_YELLOW}🗺️${NC} TZ      : ${BANNER_YELLOW}${tz:-?}${NC} | ${BANNER_YELLOW}NTP=${ntp:-?}${NC}"
echo -e " ${BANNER_YELLOW}🧠${NC} RAM     : ${BANNER_BLUE}${ram}${NC}"
echo -e " ${BANNER_YELLOW}💽${NC} Disco   : ${BANNER_BLUE}${disk}${NC}"
echo -e " ${BANNER_YELLOW}🌐${NC} WebSocket SSH : $(service_status maritima-ws)"
echo -e " ${BANNER_YELLOW}🔐${NC} XRAY REALITY  : $(service_status xray)"
echo -e " ${BANNER_YELLOW}🧩${NC} BadVPN UDPGW    : $(badvpn_label)"

pause
}

#============DROPBEAR ATIVAR/DESATIVAR/STATUS=================
dropbear_status() {
  if systemctl is-active --quiet dropbear; then
    echo "ATIVO"
  else
    echo "INATIVO"
  fi
}

dropbear_enable() {
  systemctl enable --now dropbear
  ufw allow 222/tcp
  ufw reload
}

dropbear_disable() {
  systemctl disable --now dropbear
  ufw delete allow 222/tcp 2>/dev/null || true
  ufw reload
}



#============PROTOCOLOS ATIVAR / DESATIVAR================

svc_is_active() { systemctl is-active --quiet "$1"; }
svc_label() { svc_is_active "$1" && echo -e "${GREEN}● ATIVO${NC}" || echo -e "${RED}● OFF${NC}"; }
svc_toggle() { svc_is_active "$1" && systemctl stop "$1" || systemctl start "$1"; }


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

[[ -z "$u" || -z "$p" || -z "$d" || -z "$l" ]] && { echo -e "${RED}Campos inválidos${NC}"; pause; return; }

groupadd -f vpn
useradd -M -s /bin/false -G vpn "$u" 2>/dev/null || {

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
  echo -e "${BANNER_CYAN}👥 USUÁRIOS CADASTRADOS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  [[ ! -s "$DB" ]] && { echo "Nenhum usuário."; pause; return; }

  local now
  now="$(date -u +%s)"

  while IFS=':' read -r user pass exp lim uuid; do
    [[ -z "$user" ]] && continue

    # Valida data e calcula dias restantes (UTC)
    local exp_ts days_left status
    exp_ts="$(date -u -d "$exp" +%s 2>/dev/null || echo 0)"

    if [[ "$exp_ts" -le 0 ]]; then
      days_left="?"
      status="${YELLOW}⚠️ data inválida${NC}"
    else
      days_left=$(( (exp_ts - now + 43200) / 86400 ))
      if (( days_left < 0 )); then
        status="${RED}❌ expirado${NC}"
      else
        status="${GREEN}✅ ativo${NC}"
      fi
    fi

    echo -e "👤 ${WHITE}${user}${NC} | 🔑 ${pass} | 📅 ${exp} (${YELLOW}${days_left}${NC} dias) | 🔢 lim ${lim} | ${status}"
    echo -e "   SSH: ssh://${user}:${pass}@$(get_ip):2222"
    echo -e "   UUID: ${uuid}"
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
[[ -z "$u" ]] && { echo -e "${RED}Inválido${NC}"; pause; return; }

userdel "$u" 2>/dev/null || true
sed -i "/^$u:/d" "$DB"

echo -e "${BANNER_GREEN}✅ Usuário removido${NC}"
pause
}

add_test_user() {
  clear
  echo -e "${CYAN}🧪 CRIAR USUÁRIO TESTE${NC}"
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
  
  groupadd -f vpn
  useradd -M -s /bin/false "$u" || { echo -e "${RED}Falha ao criar user${NC}"; pause; return; }
  echo "$u:$p" | chpasswd || { echo -e "${RED}Falha ao definir senha${NC}"; pause; return; }

  EXP=$(date -d "+$m minutes" +"%Y-%m-%d %H:%M") || { echo -e "${RED}Falha ao calcular validade${NC}"; pause; return; }
  UUID=$(uuidgen) || { echo -e "${RED}Falha ao gerar UUID${NC}"; pause; return; }

  echo "$u:$p:$EXP:$l:$UUID" >> "$DB" || { echo -e "${RED}Falha ao gravar no DB${NC}"; pause; return; }

  # AQUI: sincroniza o Xray logo após criar e salvar o usuário
  if ! xray_sync_clients_from_usersdb; then
    echo -e "${BANNER_RED}⚠️ Usuário teste criado, mas falhou sincronizar o Xray (link pode não conectar ainda).${NC}"
    pause
    return
  fi

  IP=$(get_ip)
  clear
  echo -e "${BANNER_GREEN}✅ USUÁRIO TESTE CRIADO${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo -e "🌐 IP: ${GREEN}$IP${NC}"
  echo -e "👤 Usuário: ${GREEN}$u${NC}"
  echo -e "🔑 Senha: ${YELLOW}$p${NC}"
  echo -e "📶 Limite: $l"
  echo -e "⏱️ Expira: ${RED}$m minutos${NC}"
  pause
}


# Adicione após funções existentes de usuários


alterar_limite() {
    clear
    echo "👤 Digite username:"
    read username
    echo "📶 Novo limite (ex: 3):"
    read limite
    
    if grep -q "^$username:" $DB; then
        sed -i "s/^$username:[^:]*:lim.*/$username:$(awk -F: "/^$username:/{print \$2}" $DB):lim $limite/" $DB
        echo "✅ Limite de $username alterado para $limite"
    else
        echo "❌ Usuário $username não encontrado"
    fi
    echo "ENTER para continuar..."
    read
}

alterar_validade() {
  clear
  echo -e "${CYAN}📅 ALTERAR VALIDADE${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  read -rp "👤 Username: " username
  [[ -z "$username" ]] && { echo -e "${RED}Inválido${NC}"; pause; return; }

  if ! grep -q "^$username:" "$DB"; then
    echo -e "${RED}❌ Usuário $username não encontrado no DB${NC}"
    pause
    return
  fi

  echo
  echo "Escolha o modo:"
  echo "1) Informar data (YYYY-MM-DD)"
  echo "2) Somar dias (+N dias)"
  echo "3) Somar horas (+N horas)"
  echo "4) Somar minutos (+N minutos)"
  read -rp "Opção: " modo

  local cur exp_ts new_ts newexp
  cur="$(awk -F: -v u="$username" '$1==u{print $3}' "$DB" | head -n1)"

  # Se a exp atual for inválida, usamos hoje como base
  exp_ts="$(date -d "$cur" +%s 2>/dev/null || date +%s)"

  case "$modo" in
    1)
      read -rp "📅 Nova expiração (YYYY-MM-DD): " newexp
      new_ts="$(date -d "$newexp" +%s 2>/dev/null)" || { echo -e "${RED}Data inválida${NC}"; pause; return; }
      newexp="$(date -d "@$new_ts" +%Y-%m-%d)"
      ;;
    2)
      read -rp "➕ Dias a adicionar (ex: 30): " add
      [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Número inválido${NC}"; pause; return; }
      new_ts="$((exp_ts + add*86400))"
      newexp="$(date -d "@$new_ts" +%Y-%m-%d)"
      ;;
    3)
      read -rp "➕ Horas a adicionar (ex: 12): " add
      [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Número inválido${NC}"; pause; return; }
      new_ts="$((exp_ts + add*3600))"
      newexp="$(date -d "@$new_ts" +%Y-%m-%d)"
      ;;
    4)
      read -rp "➕ Minutos a adicionar (ex: 90): " add
      [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Número inválido${NC}"; pause; return; }
      new_ts="$((exp_ts + add*60))"
      newexp="$(date -d "@$new_ts" +%Y-%m-%d)"
      ;;
    *)
      echo -e "${RED}Opção inválida${NC}"
      pause
      return
      ;;
  esac

  # Atualiza somente o campo 3 (EXP), preservando senha/limite/uuid
  awk -F: -v OFS=":" -v u="$username" -v ne="$newexp" '
    $1==u { $3=ne }
    { print }
  ' "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB"

  echo -e "${GREEN}✅ Validade de $username → $newexp${NC}"
  pause
}

#==================ALTERADOR DE LIITE DO CONTADOR DE LOGINS CRIADOS=================
PANEL_CAP_FILE="/opt/maritima/panel_capacity.txt"

get_panel_capacity() {
  [[ -f "$PANEL_CAP_FILE" ]] && cat "$PANEL_CAP_FILE" || echo 40
}

set_panel_capacity() {
  clear
  echo -e "${BANNER_CYAN}⚙️ CAPACIDADE DO PAINEL${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo "Atual: $(get_panel_capacity)"
  read -rp "Nova capacidade (ex: 80): " cap
  [[ "$cap" =~ ^[0-9]+$ ]] || { echo "Inválido"; pause; return; }
  echo "$cap" > "$PANEL_CAP_FILE"
  echo "✅ Capacidade atualizada: $cap"
  pause
}


#==================CONTADOR DE LOGINS CRIADOS===========
count_logins() {
  [[ -f "$DB" ]] || { echo 0; return; }
  awk -F: 'NF && $1!="" {c++} END{print c+0}' "$DB"
}


#==================CONTADOR DE LOGADOS=====================
SSH_PORT=2222
WS_PORTS=(80 8080 443 8443)

count_conns_in() {
  local p="$1"
  ss -Htn state established "( sport = :$p )" 2>/dev/null | wc -l
}

count_ips_in() {
  local p="$1"
  ss -Htn state established "( sport = :$p )" 2>/dev/null \
    | awk '{print $5}' \
    | awk -F: 'NF{--NF};1' \
    | sort -u | wc -l
}

show_connected() {
  clear
  echo -e "${BANNER_CYAN}👥 CONECTADOS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  local ssh_conns ssh_ips
  ssh_conns="$(count_conns_in "$SSH_PORT")"
  ssh_ips="$(count_ips_in "$SSH_PORT")"
  echo -e "${WHITE}Clientes (SSHD ${SSH_PORT}):${NC} ${YELLOW}${ssh_conns}${NC} conexões | ${YELLOW}${ssh_ips}${NC} IPs únicos"
  echo

  echo -e "${WHITE}Uso por porta (Nginx):${NC}"
  for p in "${WS_PORTS[@]}"; do
    conns="$(count_conns_in "$p")"
    ips="$(count_ips_in "$p")"
    echo -e "  Porta ${YELLOW}${p}${NC}: ${YELLOW}${conns}${NC} conexões | ${YELLOW}${ips}${NC} IPs únicos"
  done

  echo
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  pause
}







user_menu() {
    while true; do
        clear
        echo -e "${BANNER_CYAN}👥 GERENCIAR USUÁRIOS${NC}"
echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

echo -e "${CYAN}1)${NC} ${YELLOW}Criar usuário${NC}"
echo -e "${CYAN}2)${NC} ${YELLOW}Listar usuários${NC}"
echo -e "${CYAN}3)${NC} ${YELLOW}Remover usuário${NC}"
echo -e "${CYAN}4)${NC} ${YELLOW}Criar usuário ${ORANGE}TESTE${NC}"
echo -e "${CYAN}5)${NC} ${YELLOW}🔄 Alterar limite conexões${NC}"
echo -e "${CYAN}6)${NC} ${YELLOW}📅 Alterar validade login${NC}"
echo -e "${CYAN}7)${NC} ${YELLOW}👥 Mostrar conectados${NC}"
echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"

echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
echo
echo -en "${YELLOW}Opção:${NC} "
read o

        
        case $o in
            1) add_user ;;
            2) list_users ;;
            3) del_user ;;
            4) add_test_user ;;
            5) alterar_limite ;;
            6) alterar_validade ;;
            7) show_connected ;;
            0) break ;;
            *) echo "Inválido"; sleep 1 ;;
        esac
    done
}
#===============BANNER PRÉ-LOGIN================SSH=========
SSH_BANNER_FILE="/etc/ssh/banner.txt"

ssh_banner_file() {
  sshd -T 2>/dev/null | awk '/^banner /{print $2}' | head -n1
}

ssh_banner_status() {
  local f
  f="$(ssh_banner_file)"
  [[ -z "$f" || "$f" == "none" ]] && echo -e "${RED}● OFF${NC}" || echo -e "${GREEN}● ATIVO${NC} (${WHITE}${f}${NC})"
}

ssh_banner_show() {
  clear
  echo -e "${BANNER_CYAN}🪧 BANNER SSH (pré-login)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo -e "Status: $(ssh_banner_status)"
  echo
  local f; f="$(ssh_banner_file)"
  if [[ -z "$f" || "$f" == "none" ]]; then
    echo "Sem banner ativo."
  elif [[ -f "$f" ]]; then
    sed -n '1,200p' "$f"
  else
    echo "Arquivo não encontrado: $f"
  fi
  pause
}

ssh_banner_edit() {
  clear
  echo -e "${BANNER_CYAN}✏️ EDITAR BANNER SSH (pré-login)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo "Arquivo: $SSH_BANNER_FILE"
  echo
  nano "$SSH_BANNER_FILE"
  chmod 644 "$SSH_BANNER_FILE"

  if grep -qE '^\s*Banner\s+' /etc/ssh/sshd_config; then
    sed -i -E "s|^\s*Banner\s+.*$|Banner ${SSH_BANNER_FILE}|g" /etc/ssh/sshd_config
  else
    echo "Banner ${SSH_BANNER_FILE}" >> /etc/ssh/sshd_config
  fi

  sshd -t && systemctl restart ssh
  echo -e "${BANNER_GREEN}✅ Banner SSH aplicado.${NC}"
  pause
}

ssh_banner_disable() {
  clear
  echo -e "${BANNER_RED}🚫 DESATIVAR BANNER SSH (pré-login)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  if grep -qE '^\s*Banner\s+' /etc/ssh/sshd_config; then
    sed -i -E 's|^\s*Banner\s+.*$|Banner none|g' /etc/ssh/sshd_config
  else
    echo "Banner none" >> /etc/ssh/sshd_config
  fi

  sshd -t && systemctl restart ssh
  echo -e "${BANNER_GREEN}✅ Banner SSH desativado.${NC}"
  pause
}

ssh_banner_menu() {
  while true; do
    clear
    echo -e "${BANNER_CYAN}🪧 MENU BANNER SSH (pré-login)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "Status: $(ssh_banner_status)"
    echo
    echo -e "${CYAN}1)${NC} ${WHITE}Ver banner atual${NC}"
    echo -e "${CYAN}2)${NC} ${WHITE}Editar banner${NC}"
    echo -e "${CYAN}3)${NC} ${WHITE}Remover/desativar banner${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o
    case "$o" in
      1) ssh_banner_show ;;
      2) ssh_banner_edit ;;
      3) ssh_banner_disable ;;
      0) break ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}
# ================= MENSAGEIRO (BANNER APP) =================
MSG_JSON="/opt/maritima/banner/banner.json"

msg_init() {
  mkdir -p /opt/maritima/banner
  if [[ ! -f "$MSG_JSON" ]]; then
    cat > "$MSG_JSON" <<'JSON'
{
  "version": 1,
  "updated_at": "2026-02-25T00:00:00-03:00",
  "items": []
}
JSON
  fi
  chmod 644 "$MSG_JSON"
}

msg_touch() {
  jq --arg now "$(date --iso-8601=seconds)" '.updated_at=$now' "$MSG_JSON" > "${MSG_JSON}.tmp" \
    && mv "${MSG_JSON}.tmp" "$MSG_JSON"
}

msg_view() {
  msg_init
  clear
  echo -e "${CYAN}📢 MENSAGEIRO (JSON)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  jq . "$MSG_JSON" || { echo -e "${RED}JSON inválido.${NC}"; pause; return; }
  pause
}

msg_list() {
  msg_init
  clear
  echo -e "${CYAN}📃 ITENS DO MENSAGEIRO${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  jq -r '.items | to_entries[] | "\(.key)) [\(.value.size)/\(.value.color)] \(.value.text)"' "$MSG_JSON" 2>/dev/null || true
  echo
  pause
}

msg_add() {
  msg_init
  clear
  echo -e "${CYAN}➕ ADICIONAR TEXTO${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  echo "Tamanho: 1) sm  2) md  3) lg"
  read -rp "Escolha: " sz
  case "$sz" in 1) sz="sm";; 2) sz="md";; 3) sz="lg";; *) sz="md";; esac

  echo "Cor: 1) red 2) green 3) yellow 4) blue 5) cyan 6) white"
  read -rp "Escolha: " co
  case "$co" in 1) co="red";; 2) co="green";; 3) co="yellow";; 4) co="blue";; 5) co="cyan";; 6) co="white";; *) co="white";; esac

  read -rp "Negrito? (s/n): " bd
  [[ "$bd" =~ ^[sS]$ ]] && bd=true || bd=false

  read -rp "Texto: " tx
  [[ -z "$tx" ]] && { echo -e "${RED}Texto vazio.${NC}"; pause; return; }

  jq --arg text "$tx" --arg color "$co" --arg size "$sz" --argjson bold "$bd" \
     '.items += [{"text":$text,"color":$color,"size":$size,"bold":$bold}]' \
     "$MSG_JSON" > "${MSG_JSON}.tmp" && mv "${MSG_JSON}.tmp" "$MSG_JSON" || {
       echo -e "${RED}Falha ao gravar.${NC}"; pause; return;
     }

  msg_touch
  echo -e "${BANNER_GREEN}✅ Adicionado!${NC}"
  pause
}

msg_remove() {
  msg_init
  clear
  echo -e "${CYAN}🗑️ REMOVER ITEM${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  jq -r '.items | to_entries[] | "\(.key)) [\(.value.size)/\(.value.color)] \(.value.text)"' "$MSG_JSON" 2>/dev/null || true
  echo
  read -rp "Índice: " idx
  [[ "$idx" =~ ^[0-9]+$ ]] || { echo -e "${RED}Índice inválido.${NC}"; pause; return; }

  jq --argjson i "$idx" '.items |= del(.[$i])' "$MSG_JSON" > "${MSG_JSON}.tmp" \
    && mv "${MSG_JSON}.tmp" "$MSG_JSON" || { echo -e "${RED}Falha ao remover.${NC}"; pause; return; }

  msg_touch
  echo -e "${BANNER_GREEN}✅ Removido!${NC}"
  pause
}

msg_clear() {
  msg_init
  clear
  echo -e "${RED}⚠️ LIMPAR MENSAGEIRO INTEIRO${NC}"
  read -rp "Digite SIM para confirmar: " r
  [[ "$r" == "SIM" ]] || { echo "Cancelado."; pause; return; }

  jq '.items=[]' "$MSG_JSON" > "${MSG_JSON}.tmp" && mv "${MSG_JSON}.tmp" "$MSG_JSON" || {
    echo -e "${RED}Falha ao limpar.${NC}"; pause; return;
  }

  msg_touch
  echo -e "${BANNER_GREEN}✅ Mensageiro limpo!${NC}"
  pause
}

msg_edit_file() {
  msg_init
  cp -a "$MSG_JSON" "${MSG_JSON}.bak.$(date +%F-%H%M%S)"
  nano "$MSG_JSON"
  jq -e . "$MSG_JSON" >/dev/null 2>&1 || {
    echo -e "${RED}JSON inválido após edição. Restaurei backup? (manual em ${MSG_JSON}.bak.*)${NC}"
    pause
    return
  }
  msg_touch
}

mensageiro_menu() {
  while true; do
    clear
    echo -e "${CYAN}📢 MENSAGEIRO${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo "1) Visualizar JSON completo"
    echo "2) Listar itens (índices)"
    echo "3) Adicionar texto"
    echo "4) Remover item (por índice)"
    echo "5) Editar arquivo (nano)"
    echo "6) Limpar tudo"
    echo "0) Voltar"
    read -rp "Opção: " op
    case "$op" in
      1) msg_view ;;
      2) msg_list ;;
      3) msg_add ;;
      4) msg_remove ;;
      5) msg_edit_file ;;
      6) msg_clear ;;
      0) break ;;
      *) echo "Inválido"; pause ;;
    esac
  done
}




#==================================================================
run_speedtest() {
  clear
  echo -e "${CYAN}🚀 SPEEDTEST${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  if command -v speedtest >/dev/null 2>&1; then
    speedtest || true
  elif command -v speedtest-cli >/dev/null 2>&1; then
    speedtest-cli --simple || speedtest-cli || true
  else
    echo -e "${YELLOW}Speedtest não instalado.${NC}"
    echo "Instale (Ookla):"
    echo "  curl -s https://install.speedtest.net/app/cli/install.deb.sh | bash"
    echo "  apt install -y speedtest"
    echo
    echo "Ou (Python): apt install -y speedtest-cli"
  fi
  pause
}

#=============BADVPN ATIVAR/DESATIVAR=================
badvpn_status_label() {
  if systemctl is-active --quiet badvpn-udpgw; then
    echo -e "${BANNER_GREEN}● ATIVO${NC} (${BANNER_YELLOW}127.0.0.1:7300${NC})"
  else
    echo -e "${BANNER_RED}● INATIVO${NC}"
  fi
}

badvpn_toggle() {
  if systemctl is-active --quiet badvpn-udpgw; then
    systemctl disable --now badvpn-udpgw
    echo -e "${BANNER_YELLOW}BadVPN desativado.${NC}"
  else
    systemctl enable --now badvpn-udpgw
    echo -e "${BANNER_GREEN}BadVPN ativado.${NC}"
  fi
  sleep 1
}

#============STATUS BADVPN==================
badvpn_label() {
  if systemctl is-active --quiet badvpn-udpgw; then
    echo -e "${BANNER_GREEN}● ATIVO${NC}"
  else
    echo -e "${BANNER_RED}● INATIVO${NC}"
  fi
}
#=============GERADOR LINK VLESS POR USUÁRIOS============
vless_link_pick_user() {
  local DB="/opt/maritima/users.db"
  local XRAY_CFG="/usr/local/etc/xray/config.json"
  local JQ="/usr/bin/jq"
  local HEAD="/usr/bin/head"
  local SED="/usr/bin/sed"
  local DATE="/usr/bin/date"

  [[ -f "$DB" ]] || { echo "ERRO: não achei $DB"; return 1; }
  [[ -x "$JQ" ]] || { echo "ERRO: jq não encontrado em $JQ"; return 1; }

  # Pega parâmetros do inbound VLESS+WS do Xray (path/host)
  local WS_PATH WS_HOST ENC_PATH
  WS_PATH="$("$JQ" -r '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws") | .streamSettings.wsSettings.path' "$XRAY_CFG" | "$HEAD" -n1)"
  WS_HOST="$("$JQ" -r '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws") | .streamSettings.wsSettings.headers.Host' "$XRAY_CFG" | "$HEAD" -n1)"
  [[ -n "$WS_PATH" && "$WS_PATH" != "null" ]] || { echo "ERRO: WS path não encontrado no Xray"; return 1; }
  [[ -n "$WS_HOST" && "$WS_HOST" != "null" ]] || { echo "ERRO: WS Host não encontrado no Xray"; return 1; }
  ENC_PATH="$(echo -n "$WS_PATH" | "$SED" 's|/|%2F|g')"

  # Dados públicos do seu Nginx vless-ws
  local PUBLIC_ADDR="maritimavpn.shop"
  local PUBLIC_PORT="2096"
  local SNI="maritimavpn.shop"

  clear
  echo -e "${BANNER_CYAN}🔗 GERAR LINK VLESS (POR USUÁRIO)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  # Lista numerada
  local i=0
  while IFS=: read -r user pass exp lim uuid; do
    [[ -z "$user" ]] && continue
    i=$((i+1))
    echo "[$i] $user | vence: $exp | lim: $lim | uuid: $uuid"
  done < "$DB"

  echo
  read -rp "Escolha o número do usuário: " n
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "Opção inválida"; return 1; }

  # Pega a linha escolhida
  local line
  line="$(/usr/bin/nl -ba "$DB" | /usr/bin/awk -v n="$n" '$1==n { $1=""; sub(/^ +/,""); print; exit }')"
  [[ -n "$line" ]] || { echo "Usuário não encontrado"; return 1; }

  local user pass exp lim uuid
  IFS=: read -r user pass exp lim uuid <<< "$line"

  # (Opcional) Aviso se já expirou
  if [[ -x "$DATE" ]]; then
    local today epoch_today epoch_exp
    today="$("$DATE" +%F)"
    epoch_today="$("$DATE" -d "$today" +%s 2>/dev/null || echo 0)"
    epoch_exp="$("$DATE" -d "$exp" +%s 2>/dev/null || echo 0)"
    if (( epoch_exp > 0 && epoch_today > 0 && epoch_exp < epoch_today )); then
      echo -e "${YELLOW}⚠️  Atenção: usuário expirado ($exp).${NC}"
    fi
  fi

  local remark="MARITIMA_${user}"
  local link
  link="vless://${uuid}@${PUBLIC_ADDR}:${PUBLIC_PORT}?encryption=none&security=tls&type=ws&host=${WS_HOST}&path=${ENC_PATH}&sni=${SNI}#${remark}"

  echo
  echo -e "${WHITE}${link}${NC}"
}




#==============GERADOR RÁPIDO LINKS VLESS=============
gen_vless_ws_tls_link() {
  local XRAY_CFG="/usr/local/etc/xray/config.json"

  local PUBLIC_ADDR="maritimavpn.shop"
  local PUBLIC_PORT="2096"
  local SNI="maritimavpn.shop"
  local REMARK="MARITIMA_VLESS"

  local JQ="/usr/bin/jq"
  local HEAD="/usr/bin/head"
  local SED="/usr/bin/sed"

  [[ -x "$JQ" ]]   || { echo "ERRO: jq não encontrado em $JQ"; return 1; }
  [[ -x "$HEAD" ]] || { echo "ERRO: head não encontrado em $HEAD"; return 1; }
  [[ -f "$XRAY_CFG" ]] || { echo "ERRO: não achei $XRAY_CFG"; return 1; }

  local UUID PATH HOST
  UUID="$("$JQ" -r '.inbounds[] | select(.protocol=="vless") | .settings.clients[0].id' "$XRAY_CFG" | "$HEAD" -n1)"
  PATH="$("$JQ" -r '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws") | .streamSettings.wsSettings.path' "$XRAY_CFG" | "$HEAD" -n1)"
  HOST="$("$JQ" -r '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws") | .streamSettings.wsSettings.headers.Host' "$XRAY_CFG" | "$HEAD" -n1)"

  [[ -n "$UUID" && "$UUID" != "null" ]] || { echo "ERRO: UUID não encontrado no xray json"; return 1; }
  [[ -n "$PATH" && "$PATH" != "null" ]] || { echo "ERRO: WS path não encontrado no xray json"; return 1; }
  [[ -n "$HOST" && "$HOST" != "null" ]] || { echo "ERRO: WS Host header não encontrado no xray json"; return 1; }

  local ENC_PATH
  ENC_PATH="$(echo -n "$PATH" | "$SED" 's|/|%2F|g')"

  echo "vless://${UUID}@${PUBLIC_ADDR}:${PUBLIC_PORT}?encryption=none&security=tls&type=ws&host=${HOST}&path=${ENC_PATH}&sni=${SNI}#${REMARK}"
}

#========= Função: sincronizar clients do Xray com users.db (expiração real)==============
 xray_sync_clients_from_usersdb() {
  local DB="/opt/maritima/users.db"
  local XRAY_CFG="/usr/local/etc/xray/config.json"

  local JQ="/usr/bin/jq"
  local DATE="/usr/bin/date"
  local CP="/bin/cp"
  local MV="/bin/mv"
  local MKTEMP="/usr/bin/mktemp"
  local SYSTEMCTL="/bin/systemctl"

  # Ajuste aqui: UUID do admin atual do Xray
  local ADMIN_UUID="a98b91e0-7559-4b5a-9877-b7776cb1f2c7"
  local ADMIN_EMAIL="admin@maritima"

  [[ -f "$DB" ]] || { echo "ERRO: não achei $DB"; return 1; }
  [[ -f "$XRAY_CFG" ]] || { echo "ERRO: não achei $XRAY_CFG"; return 1; }
  [[ -x "$JQ" ]] || { echo "ERRO: jq não encontrado em $JQ"; return 1; }
  [[ -x "$DATE" ]] || { echo "ERRO: date não encontrado"; return 1; }

  local epoch_now
  epoch_now="$("$DATE" +%s)" || { echo "ERRO: falha ao ler epoch atual"; return 1; }

  # Começa com admin incluso (preserva sempre)
  local clients_json
  clients_json="$("$JQ" -nc --arg id "$ADMIN_UUID" --arg email "$ADMIN_EMAIL" '[{"id":$id,"email":$email}]')"

  # Lê users.db: user:pass:exp:lim:uuid
  while IFS=: read -r user pass exp lim uuid; do
    [[ -z "$user" || -z "$exp" || -z "$uuid" ]] && continue

    # UUID básico
    [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || continue

    # Aceita exp como "YYYY-MM-DD" ou "YYYY-MM-DD HH:MM"
    # (na prática: deixa o date validar e converter)
    local epoch_exp
    epoch_exp="$("$DATE" -d "$exp" +%s 2>/dev/null || echo 0)"
    (( epoch_exp == 0 )) && continue

    # expiração precisa ser >= agora
    (( epoch_exp < epoch_now )) && continue

    # adiciona usuário
    clients_json="$(
      printf '%s' "$clients_json" \
      | "$JQ" -c --arg id "$uuid" --arg email "$user" '
          . + [{"id":$id,"email":$email}]
          | unique_by(.id)
        '
    )"
  done < "$DB"

  local count
  count="$(printf '%s' "$clients_json" | "$JQ" 'length')"

  (( count > 0 )) || { echo "ERRO: lista de clients ficou vazia (não vou aplicar)."; return 1; }

  # Backup antes de aplicar
  "$CP" -a "$XRAY_CFG" "${XRAY_CFG}.bak.$(date +%F-%H%M%S)"

  # Atualiza SOMENTE: vless + ws + port 10000
  local tmp
  tmp="$("$MKTEMP")" || return 1

  "$JQ" --argjson clients "$clients_json" '
    .inbounds |= map(
      if (.protocol=="vless" and .streamSettings.network=="ws" and .port==10000)
      then (.settings.clients = $clients)
      else .
      end
    )
  ' "$XRAY_CFG" > "$tmp" || { rm -f "$tmp"; echo "ERRO: jq falhou ao gerar novo JSON"; return 1; }

  "$JQ" -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; echo "ERRO: JSON gerado inválido"; return 1; }

  "$MV" "$tmp" "$XRAY_CFG"

  "$SYSTEMCTL" restart xray || { echo "ERRO: falhou reiniciar xray"; return 1; }

  echo "✅ Xray sincronizado. Clients no WS: $count"
}





#=============MENU DE PROTOCOLOS===========
protocols_menu() {
  while true; do
    clear
    echo -e "${ORANGE}🧩 MENU PROTOCOLOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${ORANGE}1)${NC} ${CYAN}WebSocket SSH${NC} : $(svc_label maritima-ws)"
    echo -e "${ORANGE}2)${NC} ${CYAN}Xray (Reality)${NC}: $(svc_label xray)"
    echo -e "${ORANGE}3)${NC} ${YELLOW}Mostrar portas por serviço${NC}"
    echo -e "${ORANGE}4)${NC} ${YELLOW}Alterar porta do WebSocket${NC}"
    echo -e "${ORANGE}5)${NC} ${YELLOW}Alterar Portas Nginx${NC}"
    echo -e "${ORANGE}6)${NC} ${YELLOW}BADVPN (Ativar/Desativar) : $(badvpn_status_label)${NC}"
    echo -e "${ORANGE}7)${NC} ${PURPLE}🔗 Link VLESS WS TLS (rápido)${NC}"
    echo -e "${ORANGE}8)${NC} ${PURPLE}👥 Link VLESS por usuário${NC}"
    echo -e "${ORANGE}9)${NC} ${YELLOW}🔄 Sincronizar Xray (validade)${NC}"
    echo -e "${ORANGE}10)${NC} ${YELLOW}Dropbear (porta 222) - (dropbear_status)${NC}"
    echo -e "${ORANGE}11)${NC} ${YELLOW}Alterar porta VLESS-WS TLS (Nginx vhost)${NC}"
    echo -e "${RED}0)${NC} Voltar"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

    read -rp "Opção: " o

    case "$o" in
  1) svc_toggle maritima-ws; pause ;;
  2) svc_toggle xray; pause ;;
  3) show_ports_by_service; pause ;;
  4) ws_change_port ;;
  5) nginx_ports_total_menu ;;
  6) badvpn_toggle ;;

  7)
    clear
    echo -e "${BANNER_CYAN}🔗 LINK VLESS WS TLS (RÁPIDO)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    out="$(gen_vless_ws_tls_link 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo -e "${RED}❌ Falhou gerar link.${NC}"
      echo -e "${YELLOW}${out}${NC}"
      pause
      continue
    fi
    echo
    echo -e "${WHITE}${out}${NC}"
    echo
    pause
    ;;

  8)
    clear
    echo -e "${BANNER_CYAN}👥 LINK VLESS (POR USUÁRIO)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    vless_link_pick_user
    echo
    pause
    ;;

  9)
    clear
    echo -e "${BANNER_CYAN}🔄 SINCRONIZAR XRAY (VALIDADE)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    xray_sync_clients_from_usersdb
    echo
    pause
    ;;

  10)
    clear
  echo "Dropbear está: $(dropbear_status)"
  echo "1) Ativar Dropbear (222)"
  echo "2) Desativar Dropbear (222)"
  read -rp "Opção: " dpop
  case "$dpop" in
    1) dropbear_enable ;;
    2) dropbear_disable ;;
  esac
  read -rp "Enter para voltar..." _
  ;;

  11) vlessws_port_manage ;;



  0) break ;;
  *) echo "Inválido"; sleep 1 ;;
esac

  done
}

#=============ALTERAR PORTAS NGINX VLESS =================
vlessws_port_manage() {
  local conf="/etc/nginx/sites-available/vless-ws"
  [[ -f "$conf" ]] || { echo "Arquivo não existe: $conf"; pause; return 1; }

  _detect_vlessws_port() {
    awk '$1=="listen" && $0 ~ /ssl/ && $0 !~ /\\[::\\]/ {p=$2; gsub(";","",p); print p; exit}' "$conf"
  }

  _ufw_allow_port() {
    local p="$1"
    ufw allow "${p}/tcp" >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
  }

  _ufw_delete_allow_port() {
    local p="$1"
    ufw delete allow "${p}/tcp" >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
  }

  _nginx_remove_listen_port() {
    local p="$1"
    cp -a "$conf" "${conf}.bak.$(date +%F_%H%M%S)"

    # Remove linhas listen IPv4/IPv6 que tenham ssl e usem a porta alvo
    sed -E -i \
      -e "/^[[:space:]]*listen[[:space:]]+${p}[[:space:]]+ssl([[:space:]]+http2)?[[:space:]]*;/d" \
      -e "/^[[:space:]]*listen[[:space:]]+\\[::\\]:${p}[[:space:]]+ssl([[:space:]]+http2)?[[:space:]]*;/d" \
      "$conf"

    nginx -t || { echo "ERRO: nginx -t falhou. Revertendo..."; cp -a "${conf}.bak."* "$conf"; return 1; }
    systemctl reload nginx
  }

  _nginx_change_listen_port() {
    local oldp="$1" newp="$2"
    cp -a "$conf" "${conf}.bak.$(date +%F_%H%M%S)"

    sed -E -i \
      -e "s/^([[:space:]]*listen[[:space:]]+)${oldp}(([[:space:]]+ssl)([[:space:]]+http2)?[[:space:]]*;)/\\1${newp}\\2/" \
      -e "s/^([[:space:]]*listen[[:space:]]+\\[::\\]:)${oldp}(([[:space:]]+ssl)([[:space:]]+http2)?[[:space:]]*;)/\\1${newp}\\2/" \
      "$conf"

    nginx -t || { echo "ERRO: nginx -t falhou. Revertendo..."; cp -a "${conf}.bak."* "$conf"; return 1; }
    systemctl reload nginx
  }

  while true; do
    local current_port op
    current_port="$(_detect_vlessws_port)"
    [[ -n "$current_port" ]] || current_port="(não detectado)"

    clear
    echo -e "${BANNER_CYAN}🔧 VLESS-WS TLS (NGINX) - GERENCIAR PORTA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo "Vhost: $conf"
    echo "Porta atual (detectada): $current_port"
    echo
    echo "1) Adicionar/Liberar porta no UFW (sem mexer no Nginx)"
    echo "2) Remover porta do UFW (opcional: remover do Nginx também)"
    echo "3) Trocar porta do Nginx (listen) + liberar no UFW (recomendado)"
    echo "0) Voltar"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " op

    case "$op" in
      1)
        local p
        read -rp "Qual porta liberar no UFW (ex: 2096) (ENTER cancela): " p
        [[ -z "$p" ]] && continue
        [[ "$p" =~ ^[0-9]+$ ]] && (( p>=1 && p<=65535 )) || { echo "Porta inválida."; pause; continue; }

        _ufw_allow_port "$p"
        echo "OK: UFW allow ${p}/tcp aplicado."
        pause
        ;;
      2)
        local p ans rm_ng
        read -rp "Qual porta remover do UFW (ex: 2096) (ENTER cancela): " p
        [[ -z "$p" ]] && continue
        [[ "$p" =~ ^[0-9]+$ ]] && (( p>=1 && p<=65535 )) || { echo "Porta inválida."; pause; continue; }

        read -rp "Confirmar remover ${p}/tcp do UFW? (s/N): " ans
        if [[ "$ans" =~ ^[sS]$ ]]; then
          _ufw_delete_allow_port "$p"
          echo "OK: removido ${p}/tcp do UFW."
        else
          echo "Cancelado."
          pause
          continue
        fi

        read -rp "Remover também do Nginx (apagar listen ${p} ssl)? (s/N): " rm_ng
        if [[ "$rm_ng" =~ ^[sS]$ ]]; then
          _nginx_remove_listen_port "$p" && echo "OK: removi listen ${p} do vhost e recarreguei nginx."
        fi
        pause
        ;;
      3)
        local oldp newp ans
        oldp="$(_detect_vlessws_port)"
        [[ -n "$oldp" ]] || { echo "Não consegui detectar a porta atual no vhost."; pause; continue; }

        read -rp "Nova porta para o Nginx (listen) (ENTER cancela): " newp
        [[ -z "$newp" ]] && continue
        [[ "$newp" =~ ^[0-9]+$ ]] && (( newp>=1 && newp<=65535 )) || { echo "Porta inválida."; pause; continue; }
        [[ "$newp" == "$oldp" ]] && { echo "Já está na porta $newp."; pause; continue; }

        if ss -ltn "( sport = :$newp )" | grep -q LISTEN; then
          echo "Atenção: já existe algo ouvindo em $newp:"
          ss -ltnp "( sport = :$newp )"
          read -rp "Continuar mesmo assim e tentar trocar o listen? (s/N): " ans
          [[ "$ans" =~ ^[sS]$ ]] || { echo "Cancelado."; pause; continue; }
        fi

        _nginx_change_listen_port "$oldp" "$newp" || { pause; continue; }

        _ufw_allow_port "$newp"
        echo "OK: Nginx listen trocado ${oldp} -> ${newp} e UFW liberado ${newp}/tcp."

        read -rp "Remover do UFW a porta antiga ${oldp}/tcp? (s/N): " ans
        if [[ "$ans" =~ ^[sS]$ ]]; then
          _ufw_delete_allow_port "$oldp"
          echo "OK: removido ${oldp}/tcp do UFW."
        fi
        pause
        ;;
      0) return 0 ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}





# ===================== ALTERAR PORTAS NGINX=======================
# ===================== PORTAS NGINX (TOTAL) + MIGRAÇÃO =====================
NGX_EXTRA_DIR="/etc/nginx/conf.d"
NGX_EXTRA_PREFIX="sshws-extra-"

NGX_MULTI_FILE="/etc/nginx/conf.d/sshws-multi.conf"
NGX_SERVER_NAME="maritimavpn.shop ws.maritimavpn.shop"
NGX_UPSTREAM_IP="127.0.0.1"
NGX_UPSTREAM_PORT="8880"
NGX_TLS_CERT="/etc/letsencrypt/live/maritimavpn.shop/fullchain.pem"
NGX_TLS_KEY="/etc/letsencrypt/live/maritimavpn.shop/privkey.pem"

nginx_reload_safe() { nginx -t && systemctl reload nginx; }  # seguro

is_port_valid() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1>=1 && $1<=65535 )); }

# IMPORTANT: aqui é newline REAL '\n', não '\\n'
uniq_sort_ports() { tr ' ' '\n' | sed '/^$/d' | sort -n | uniq | xargs; }  # [web:126]

ngx_get_ports() {
  local mode="$1"  # http|https
  [[ -f "$NGX_MULTI_FILE" ]] || { echo ""; return; }

  if [[ "$mode" == "http" ]]; then
    # listen 80; / listen 8080;
    awk '$1=="listen" && $2 ~ /^[0-9]+;$/ {p=$2; gsub(";","",p); print p}' "$NGX_MULTI_FILE" | xargs
  else
    # listen 443 ssl ...
    awk '
      $1=="listen" && $2 ~ /^[0-9]+;?$/ {
        p=$2; gsub(";","",p);
        if ($0 ~ /[[:space:]]ssl([[:space:]]|;|$)/) print p
      }
    ' "$NGX_MULTI_FILE" | xargs
  fi
}

ngx_listen_runtime_ports_nginx() {
  ss -ltnp 2>/dev/null \
    | awk '/LISTEN/ && /nginx/ {print $4}' \
    | awk -F: '{print $NF}' \
    | sort -n | uniq
}

ngx_render_multi_conf() {
  local http_ports="$1" https_ports="$2"
  local http_blocks="" https_blocks=""

  for p in $http_ports; do
    http_blocks+=$'server {\n'
    http_blocks+="    listen ${p};"$'\n'
    http_blocks+="    server_name ${NGX_SERVER_NAME};"$'\n\n'
    http_blocks+=$'    location / {\n'
    http_blocks+=$'        proxy_pass http://sshws_backend;\n'
    http_blocks+=$'        proxy_http_version 1.1;\n'
    http_blocks+=$'        proxy_set_header Upgrade $http_upgrade;\n'
    http_blocks+=$'        proxy_set_header Connection $connection_upgrade;\n'
    http_blocks+=$'        proxy_set_header Host $host;\n'
    http_blocks+=$'        proxy_set_header X-Real-IP $remote_addr;\n'
    http_blocks+=$'        proxy_read_timeout 86400s;\n'
    http_blocks+=$'    }\n'
    http_blocks+=$'}\n\n'
  done

  for p in $https_ports; do
    https_blocks+=$'server {\n'
    https_blocks+="    listen ${p} ssl http2;"$'\n'
    https_blocks+="    server_name ${NGX_SERVER_NAME};"$'\n\n'
    https_blocks+="    ssl_certificate ${NGX_TLS_CERT};"$'\n'
    https_blocks+="    ssl_certificate_key ${NGX_TLS_KEY};"$'\n\n'
    https_blocks+=$'    location / {\n'
    https_blocks+=$'        proxy_pass http://sshws_backend;\n'
    https_blocks+=$'        proxy_http_version 1.1;\n'
    https_blocks+=$'        proxy_set_header Upgrade $http_upgrade;\n'
    https_blocks+=$'        proxy_set_header Connection $connection_upgrade;\n'
    https_blocks+=$'        proxy_set_header Host $host;\n'
    https_blocks+=$'        proxy_set_header X-Real-IP $remote_addr;\n'
    https_blocks+=$'        proxy_read_timeout 86400s;\n'
    https_blocks+=$'    }\n'
    https_blocks+=$'}\n\n'
  done

  cat > "$NGX_MULTI_FILE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream sshws_backend {
    server ${NGX_UPSTREAM_IP}:${NGX_UPSTREAM_PORT};
}

# Managed by Marítima VPN panel
# HTTP ports:  ${http_ports}
# HTTPS ports: ${https_ports}

${http_blocks}${https_blocks}
EOF
}

ngx_list_extra_files() {
  ls -1 "${NGX_EXTRA_DIR}/${NGX_EXTRA_PREFIX}"*.conf 2>/dev/null | sort
}

ngx_migrate_remove_extras() {
  local extras
  extras="$(ngx_list_extra_files)"
  [[ -z "$extras" ]] && return 0

  echo
  echo -e "${YELLOW}⚠️  Encontrei configs antigas (extras):${NC}"
  echo "$extras" | awk '{print "• " $0}'
  echo
  read -rp "Remover essas extras agora? (s/N): " c
  [[ "$c" =~ ^[sS]$ ]] || return 0

  local bk="/root/backup-nginx-extras-$(date +%F-%H%M%S).tar.gz"
  tar -czf "$bk" -C "$NGX_EXTRA_DIR" $(echo "$extras" | xargs -n1 basename)
  echo -e "${WHITE}Backup:${NC} $bk"

  echo "$extras" | xargs -r rm -f
  echo -e "${GREEN}✅ Extras removidas.${NC}"
}

nginx_ports_total_list() {
  clear
  echo -e "${BANNER_CYAN}🌐 PORTAS NGINX (TOTAL)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  local http_ports https_ports
  http_ports="$(ngx_get_ports http)";   http_ports="${http_ports:-80 8080}"
  https_ports="$(ngx_get_ports https)"; https_ports="${https_ports:-443}"

  http_ports="$(printf "%s\n" "$http_ports" | uniq_sort_ports)"
  https_ports="$(printf "%s\n" "$https_ports" | uniq_sort_ports)"

  echo -e "${WHITE}Config (arquivo):${NC} ${YELLOW}${NGX_MULTI_FILE}${NC}"
  echo -e "• HTTP : ${YELLOW}${http_ports}${NC}"
  echo -e "• HTTPS: ${YELLOW}${https_ports}${NC}"
  echo

  echo -e "${WHITE}Runtime (ss -ltnp | nginx):${NC}"
  ngx_listen_runtime_ports_nginx | awk '{print "• " $1}'
  echo

  local extras
  extras="$(ngx_list_extra_files)"
  if [[ -n "$extras" ]]; then
    echo -e "${YELLOW}⚠️  Ainda existem extras antigas:${NC}"
    echo "$extras" | awk '{print "• " $0}'
    echo
  fi

  pause
}

nginx_ports_total_menu() {
  local http_ports https_ports
  http_ports="$(ngx_get_ports http)";   http_ports="${http_ports:-80 8080}"
  https_ports="$(ngx_get_ports https)"; https_ports="${https_ports:-443}"

  http_ports="$(printf "%s\n" "$http_ports" | uniq_sort_ports)"
  https_ports="$(printf "%s\n" "$https_ports" | uniq_sort_ports)"

  while true; do
    clear
    echo -e "${BANNER_CYAN}🌐 PORTAS NGINX (TOTAL)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${WHITE}HTTP :${NC} ${YELLOW}${http_ports}${NC}"
    echo -e "${WHITE}HTTPS:${NC} ${YELLOW}${https_ports}${NC}"
    echo
    echo -e "${CYAN}1)${NC} ${WHITE}Adicionar porta (HTTP/HTTPS)${NC}"
    echo -e "${CYAN}2)${NC} ${WHITE}Remover porta (HTTP/HTTPS)${NC}"
    echo -e "${CYAN}3)${NC} ${WHITE}Listar (config + runtime)${NC}"
    echo -e "${CYAN}4)${NC} ${WHITE}Migrar (remover extras antigas)${NC}"
    echo -e "${CYAN}5)${NC} ${WHITE}Aplicar (nginx -t && reload)${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o

    case "$o" in
      1)
        read -rp "Tipo (1=HTTP, 2=HTTPS): " t
        read -rp "Porta (1-65535): " p
        is_port_valid "$p" || { echo "Porta inválida"; pause; continue; }

        if [[ "$t" == "1" ]]; then
          http_ports="$(printf "%s\n" "$http_ports $p" | uniq_sort_ports)"
        elif [[ "$t" == "2" ]]; then
          https_ports="$(printf "%s\n" "$https_ports $p" | uniq_sort_ports)"
        else
          echo "Tipo inválido"; pause; continue
        fi
        ;;
      2)
        read -rp "Tipo (1=HTTP, 2=HTTPS): " t
        read -rp "Porta a remover: " p
        is_port_valid "$p" || { echo "Porta inválida"; pause; continue; }

        if [[ "$t" == "1" ]]; then
          http_ports="$(printf "%s\n" "$http_ports" | tr ' ' '\n' | awk -v rm="$p" '$1!=rm' | uniq_sort_ports)"
        elif [[ "$t" == "2" ]]; then
          https_ports="$(printf "%s\n" "$https_ports" | tr ' ' '\n' | awk -v rm="$p" '$1!=rm' | uniq_sort_ports)"
        else
          echo "Tipo inválido"; pause; continue
        fi

        if [[ -z "$http_ports" && -z "$https_ports" ]]; then
          echo "Você removeu todas as portas; cancelado."
          http_ports="80 8080"; https_ports="443"
          pause
        fi
        ;;
      3) nginx_ports_total_list ;;
      4)
        clear
        echo -e "${BANNER_CYAN}🧹 MIGRAR NGINX (REMOVER EXTRAS)${NC}"
        echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
        ngx_migrate_remove_extras
        echo
        pause
        ;;
      5)
        if ! echo "$https_ports" | tr ' ' '\n' | grep -qx "443"; then
          echo -e "${YELLOW}⚠️  443 NÃO está em HTTPS do Nginx.${NC}"
          echo "Isso é o que você quer quando vai liberar a 443 para o VLESS."
          echo "Só confirme que você terá outra porta pro painel (ex.: 8443)."
          read -rp "Confirmar aplicar? (s/N): " c
          [[ "$c" =~ ^[sS]$ ]] || { echo "Cancelado"; pause; continue; }
        fi

        if [[ -n "$(ngx_list_extra_files)" ]]; then
          echo -e "${YELLOW}⚠️  Ainda existem extras antigas. Recomendo migrar/remover antes.${NC}"
          read -rp "Remover extras agora antes de aplicar? (s/N): " c2
          [[ "$c2" =~ ^[sS]$ ]] && ngx_migrate_remove_extras
        fi

        ngx_render_multi_conf "$http_ports" "$https_ports"
        if nginx_reload_safe; then
          echo -e "${GREEN}✅ Aplicado:${NC} $NGX_MULTI_FILE"
        else
          echo -e "${RED}❌ nginx -t falhou; não recarreguei.${NC}"
          echo "Veja: nginx -T | tail -n 120"
        fi
        pause
        ;;
      0) break ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}







#================MOSTRAR PORTAS E NEGAR PORTAS EM USO===============
# retorna "8880" do ExecStart do maritima-ws
ws_current_port() {
  systemctl show -p ExecStart --value maritima-ws 2>/dev/null \
    | grep -oE 'wsproxy\.py [0-9]+' | awk '{print $2}' | head -n1
}

# mostra todas as portas LISTEN de um "comando" (ex: sshd, nginx, python3)
ports_by_cmd() {
  local cmd="$1"
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
    | awk -v c="$cmd" '$1==c {print $9}' \
    | sed -E 's/.*:([0-9]+).*/\1/' \
    | sort -n | uniq | tr '\n' ' '
}

show_ports_by_service() {
  clear
  echo -e "${CYAN}📌 PORTAS POR SERVIÇO${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"

  local wsport; wsport="$(ws_current_port)"
  echo -e "${GREEN}SSH (sshd)${NC}         : ${YELLOW}$(ports_by_cmd sshd)${NC}"
  echo -e "${GREEN}Nginx${NC}              : ${YELLOW}$(ports_by_cmd nginx)${NC}"
  echo -e "${GREEN}Maritima WS (python3)${NC}: ${YELLOW}${wsport:-?}${NC} (unit: maritima-ws)"
  echo -e "${GREEN}Xray${NC}               : ${YELLOW}$(ports_by_cmd xray)${NC}"
  echo -e "${GREEN}Squid${NC}              : ${YELLOW}$(ports_by_cmd squid)${NC}"

  echo
  echo -e "${LINE_COLOR}— LISTEN geral (ss -ltnp) —${NC}"
  ss -ltnp 2>/dev/null | head -n 30
}


#==================Trocar a porta do maritima-ws (systemd unit)================
port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

ws_change_port() {
  clear
  local unit="/etc/systemd/system/maritima-ws.service"
  local cur; cur="$(ws_current_port)"
  echo -e "${YELLOW}🔧 ALTERAR PORTA - Maritima WS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo -e "Atual: ${GREEN}${cur:-?}${NC}"
  read -rp "Nova porta (1-65535): " newp

  [[ "$newp" =~ ^[0-9]+$ ]] || { echo "Porta inválida"; pause; return; }
  (( newp>=1 && newp<=65535 )) || { echo "Porta inválida"; pause; return; }

  if port_in_use "$newp"; then
    echo -e "${RED}❌ Porta $newp já está em uso. Operação negada.${NC}"
    lsof -nP -iTCP:"$newp" -sTCP:LISTEN 2>/dev/null || true
    pause
    return
  fi

  sed -i -E "s|(ExecStart=.*/wsproxy\\.py) [0-9]+|\\1 ${newp}|" "$unit"

  systemctl daemon-reload
  systemctl restart maritima-ws

  echo -e "${GREEN}✅ Porta alterada para $newp e serviço reiniciado.${NC}"
  pause
}

#===============Bloquear / liberar torrent (UFW)===========
torrent_block_on() {
  clear
  echo -e "${BANNER_RED}⛔ BLOQUEAR TORRENT (UFW)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo "Aplicando regras (portas comuns 6881-6999 TCP/UDP)..."
  ufw deny 6881:6999/tcp >/dev/null 2>&1 || true
  ufw deny 6881:6999/udp >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
  echo "✅ Bloqueio aplicado."
  pause
}

torrent_block_off() {
  clear
  echo -e "${BANNER_GREEN}✅ LIBERAR TORRENT (UFW)${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo "Removendo regras 6881-6999 TCP/UDP..."
  ufw delete deny 6881:6999/tcp >/dev/null 2>&1 || true
  ufw delete deny 6881:6999/udp >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
  echo "✅ Regras removidas."
  pause
}

#================Reiniciar serviços (rápido)================
restart_services_menu() {
  while true; do
    clear
    echo -e "${BANNER_CYAN}🔄 REINICIAR SERVIÇOS${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${CYAN}1)${NC} nginx"
    echo -e "${CYAN}2)${NC} maritima-ws"
    echo -e "${CYAN}3)${NC} ssh"
    echo -e "${CYAN}4)${NC} xray"
    echo -e "${CYAN}5)${NC} Reiniciar TODOS"
    echo -e "${RED}0)${NC} Voltar"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o
    case "$o" in
      1) systemctl restart nginx; pause ;;
      2) systemctl restart maritima-ws; pause ;;
      3) systemctl restart ssh; pause ;;
      4) systemctl restart xray; pause ;;
      5) systemctl restart nginx maritima-ws ssh xray; pause ;;
      0) break ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}

#==============Reiniciar a VPS (com confirmação)===================
reboot_vps_now() {
  clear
  echo -e "${BANNER_RED}🧨 REINICIAR VPS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  read -rp "Tem certeza? Digite REBOOT para confirmar: " x
  [[ "$x" == "REBOOT" ]] || { echo "Cancelado."; pause; return; }
  systemctl reboot
}

#=============Sincronizar usuários (hook)====================
sync_users_now() {
  clear
  echo -e "${BANNER_CYAN}🔁 SINCRONIZAR USUÁRIOS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  if declare -F sync_users >/dev/null 2>&1; then
    sync_users
    echo "✅ Sync executado."
  else
    echo "⚠️ Função sync_users não existe ainda. Diga o que você quer sincronizar (somente users.db -> Linux? ou também Xray?)."
  fi
  pause
}

#=============Mostrar “arquivos principais do painel”====================
show_panel_paths() {
  clear
  echo -e "${BANNER_CYAN}📁 ARQUIVOS PRINCIPAIS${NC}"
  echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
  echo "/root/maritima.sh"
  echo "/opt/maritima/users.db"
  echo "/opt/maritima/ws/wsproxy.py"
  echo "/etc/systemd/system/maritima-ws.service"
  echo "/etc/nginx/conf.d/sshws-multi.conf"
  echo "/etc/nginx/nginx.conf"
  echo "/etc/ssh/sshd_config"
  echo "/etc/ssh/banner.txt"
  echo "/etc/nginx/sites-available/vless-ws"
  echo "/usr/local/etc/xray/config.json"
  echo
  pause
}
#===============Submenu Manutenção/Segurança==================
maintenance_menu() {
  while true; do
    clear
    echo -e "${BANNER_CYAN}🛡️ MANUTENÇÃO / SEGURANÇA${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "${CYAN}1)${RED} ⛔ Proibir torrent"
    echo -e "${CYAN}2)${GREEN} ✅ Liberar torrent"
    echo -e "${CYAN}3)${BLUE} 🔄 Reiniciar serviços"
    echo -e "${CYAN}4)${ORANGE} 🧨 Reiniciar VPS"
    echo -e "${CYAN}5)${WHITE} ⚙️ Alterar capacidade (contador /40)"
    echo -e "${CYAN}6)${PURPLE} 🔁 Sincronizar usuários"
    echo -e "${CYAN}7)${CYAN} 📁 Mostrar caminhos do painel"
    echo -e "${RED}0)${NC} Voltar"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o
    case "$o" in
      1) torrent_block_on ;;
      2) torrent_block_off ;;
      3) restart_services_menu ;;
      4) reboot_vps_now ;;
      5) set_panel_capacity ;;
      6) sync_users_now ;;
      7) show_panel_paths ;;
      0) break ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}
#==========AUTO MENU===========
AUTO_MENU_RC="/root/.bashrc"
AUTO_MENU_TAG_BEGIN="# MARITIMA_AUTO_MENU_BEGIN"
AUTO_MENU_TAG_END="# MARITIMA_AUTO_MENU_END"

auto_menu_status() {
  if grep -qF "$AUTO_MENU_TAG_BEGIN" "$AUTO_MENU_RC" 2>/dev/null; then
    echo -e "${GREEN}● ATIVO${NC}"
  else
    echo -e "${RED}● OFF${NC}"
  fi
}

auto_menu_enable() {
  # Remove bloco antigo (se existir) e adiciona novamente
  sed -i "/$AUTO_MENU_TAG_BEGIN/,/$AUTO_MENU_TAG_END/d" "$AUTO_MENU_RC" 2>/dev/null || true

  cat >> "$AUTO_MENU_RC" <<'EOF'

# MARITIMA_AUTO_MENU_BEGIN
# Auto-abre o painel ao logar via SSH (somente em shell interativo)
if [ -n "$PS1" ] && [ -z "$MARITIMA_AUTO_MENU" ]; then
  export MARITIMA_AUTO_MENU=1
  if [ -x /root/maritima.sh ]; then
    /root/maritima.sh
    exit
  fi
fi
# MARITIMA_AUTO_MENU_END
EOF

  echo "✅ Auto menu ativado (próximo login abre o painel)."
  pause
}

auto_menu_disable() {
  sed -i "/$AUTO_MENU_TAG_BEGIN/,/$AUTO_MENU_TAG_END/d" "$AUTO_MENU_RC" 2>/dev/null || true
  echo "✅ Auto menu desativado."
  pause
}

auto_menu_menu() {
  while true; do
    clear
    echo -e "${BANNER_CYAN}⚡ AUTO MENU (LOGIN SSH)${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    echo -e "Status: $(auto_menu_status)"
    echo
    echo -e "${CYAN}1)${NC} ${WHITE}Ativar auto menu${NC}"
    echo -e "${CYAN}2)${NC} ${WHITE}Desativar auto menu${NC}"
    echo -e "${RED}0)${NC} ${WHITE}Voltar${NC}"
    echo -e "${LINE_COLOR}══════════════════════════════════════${NC}"
    read -rp "Opção: " o
    case "$o" in
      1) auto_menu_enable ;;
      2) auto_menu_disable ;;
      0) break ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}



#===============MENU PRINCIPAL=======================

draw_title_box() {
    local text="$1"
    # Remove códigos ANSI para calcular comprimento visível
    local visible_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_len=${#visible_text}
    # Largura interna = texto + 2 espaços (um antes, um depois)
    local inner_width=$((text_len + 2))

    # Linha superior
    printf "%b╔" "$BANNER_CYAN"
    printf "═%.0s" $(seq 1 $inner_width)
    printf "╗%b\n" "$NC"

    # Linha do meio (com o texto e espaços)
    printf "%b║ %b%b %b║%b\n" \
           "$BANNER_CYAN" \
           "$text" \
           "$BANNER_CYAN" \
           "$BANNER_CYAN" \
           "$NC"

    # Linha inferior
    printf "%b╚" "$BANNER_CYAN"
    printf "═%.0s" $(seq 1 $inner_width)
    printf "╝%b\n" "$NC"
}

main_menu() {
  while true; do
    clear

   draw_title_box "${BANNER_BLUE}☠️ MARÍTIMA VPN PANEL ☠️${NC}"

    #======================STATUS PROTOCOLOS==================
    wsport="$(ws_current_port)"
    printf "%bWebSocket:%b %s %b(porta %b%s%b)%b\n" \
      "$ORANGE" "$NC" "$(svc_label maritima-ws)" "$WHITE" "$YELLOW" "${wsport:-?}" "$WHITE" "$NC"

    logins="$(count_logins)"
    cap="$(get_panel_capacity)"
    printf "%bLogins criados:%b %b%s%b%b/%s%b\n" \
      "$ORANGE" "$NC" "$YELLOW" "$logins" "$NC" "$PURPLE" "$cap" "$NC"

    # Linha decorativa
    printf "%b════════════════════════════%b\n" "$BANNER_CYAN" "$NC"

    # Opções do menu (número amarelo, texto ciano)
    printf "%b1)%b %bMenu de usuários%b\n"           "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b2)%b %bMenu de protocolos%b\n"         "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b3)%b %bStatus da VPS%b\n"              "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b4)%b %bBanner SSH (pré-login)%b\n"     "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b5)%b %bBanner SSH (Mensageiro)%b\n"     "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b6)%b %bSpeed test%b\n"                  "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b7)%b %bManutenção / Segurança%b\n"      "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b8)%b %bAuto menu (login SSH)%b\n"       "$BANNER_YELLOW" "$NC" "$WHITE" "$NC"
    printf "%b0)%b %bSair%b\n"                         "$BANNER_RED" "$NC" "$WHITE" "$NC"

    # Linha decorativa final
    printf "%b════════════════════════════%b\n" "$BANNER_CYAN" "$NC"


    read -rp "Opção: " opt
    echo

    case "$opt" in
      1) user_menu ;;
      2) protocols_menu ;;
      3) status_vps ;;
      4) ssh_banner_menu ;;
      5) mensageiro_menu ;;
      6) run_speedtest ;;
      7) maintenance_menu ;;
      8) auto_menu_menu ;;
      0) exit 0 ;;
      *) echo "Inválido"; sleep 1 ;;
    esac
  done
}

main_menu

