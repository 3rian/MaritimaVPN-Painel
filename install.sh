#!/bin/bash
set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[INSTALADOR]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# Verificar root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root."
fi

# Verificar Ubuntu
if ! grep -qi "ubuntu" /etc/os-release; then
    error "Este instalador foi desenvolvido para Ubuntu."
fi

# Variáveis
REPO_URL="https://github.com/3rian/MaritimaVPN-Painel.git"
BRANCH="master"  # Altere para 'main' se necessário
TEMP_DIR="/tmp/maritima-painel"
DOMAIN="maritimavpn.shop"  # Altere para seu domínio real, se desejar
USE_LETSENCRYPT=false       # Mude para true se quiser certificado real

# Perguntar ao usuário se quer usar Let's Encrypt
read -p "Deseja configurar certificado SSL com Let's Encrypt (requer domínio válido)? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    USE_LETSENCRYPT=true
    read -p "Digite seu domínio (ex: maritimavpn.shop): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        error "Domínio não pode estar vazio."
    fi
fi

log "Iniciando instalação do Marítima VPN Panel..."

# Atualizar pacotes
log "Atualizando lista de pacotes..."
apt update

# Instalar dependências
log "Instalando dependências (nginx, python3, pip, certbot, git)..."
apt install -y curl wget git unzip nginx python3 python3-pip certbot

# Instalar Xray
log "Instalando Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Instalar dependências Python (se houver)
if [[ -f "src/ws/requirements.txt" ]]; then
    pip3 install -r src/ws/requirements.txt
else
    # Se não houver requirements, instale apenas flask (comum)
    pip3 install flask
fi

# Clonar o repositório na branch especificada
log "Baixando painel da branch $BRANCH..."
rm -rf "$TEMP_DIR"
git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR"

# Criar diretórios de destino
mkdir -p /opt/maritima/{ws,banner}
mkdir -p /var/www/fallback

# Fazer backup de arquivos existentes (se houver)
backup_dir="/root/maritima-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
log "Fazendo backup de configurações atuais em $backup_dir"
[[ -f /etc/nginx/nginx.conf ]] && cp /etc/nginx/nginx.conf "$backup_dir/"
[[ -d /etc/nginx/conf.d ]] && cp -r /etc/nginx/conf.d "$backup_dir/"
[[ -d /etc/nginx/sites-available ]] && cp -r /etc/nginx/sites-available "$backup_dir/"
[[ -f /etc/ssh/sshd_config ]] && cp /etc/ssh/sshd_config "$backup_dir/"
[[ -f /usr/local/etc/xray/config.json ]] && cp /usr/local/etc/xray/config.json "$backup_dir/"

# Copiar arquivos do painel para os locais corretos
log "Copiando configurações..."
cp "$TEMP_DIR"/scripts/maritima.sh /root/maritima.sh && chmod +x /root/maritima.sh
cp "$TEMP_DIR"/data/users.db /opt/maritima/users.db 2>/dev/null || touch /opt/maritima/users.db
cp "$TEMP_DIR"/src/ws/wsproxy.py /opt/maritima/ws/
cp "$TEMP_DIR"/configs/systemd/maritima-ws.service /etc/systemd/system/
cp "$TEMP_DIR"/configs/nginx/nginx.conf /etc/nginx/nginx.conf
cp "$TEMP_DIR"/configs/nginx/conf.d/sshws-multi.conf /etc/nginx/conf.d/
cp "$TEMP_DIR"/configs/nginx/sites-available/vless-ws /etc/nginx/sites-available/
cp "$TEMP_DIR"/configs/ssh/sshd_config /etc/ssh/sshd_config
cp "$TEMP_DIR"/configs/ssh/banner.txt /etc/ssh/
cp "$TEMP_DIR"/configs/xray/config.json /usr/local/etc/xray/config.json
cp "$TEMP_DIR"/src/banner/banner.json /opt/maritima/banner/

# Criar link simbólico para o site do Nginx (se não existir)
ln -sf /etc/nginx/sites-available/vless-ws /etc/nginx/sites-enabled/

# Gerar UUIDs para o Xray (substituir placeholders)
log "Gerando UUIDs para o Xray..."
UUID1=$(cat /proc/sys/kernel/random/uuid)
UUID2=$(cat /proc/sys/kernel/random/uuid)
UUID3=$(cat /proc/sys/kernel/random/uuid)
UUID4=$(cat /proc/sys/kernel/random/uuid)

sed -i "s/CHANGE_UUID/$UUID1/g" /usr/local/etc/xray/config.json
# Se houver múltiplos placeholders (CHANGE_UUID_1, etc.), use sed com mais cuidado.
# Exemplo:
# sed -i "s/CHANGE_UUID_1/$UUID1/g" /usr/local/etc/xray/config.json
# sed -i "s/CHANGE_UUID_2/$UUID2/g" /usr/local/etc/xray/config.json

# Página de fallback simples
cat > /var/www/fallback/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Serviço Temporário</title></head>
<body><h1>Em manutenção</h1></body>
</html>
EOF

# Configurar SSL
if [[ "$USE_LETSENCRYPT" == true ]]; then
    log "Obtendo certificado Let's Encrypt para $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN" || warn "Falha ao obter certificado. Usando autoassinado."
else
    log "Gerando certificado SSL autoassinado..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/selfsigned.key \
        -out /etc/nginx/ssl/selfsigned.crt \
        -subj "/C=BR/ST=SP/L=SaoPaulo/O=Maritima/CN=$DOMAIN"
fi

# Ajustar permissões
chmod 600 /opt/maritima/users.db
chown -R www-data:www-data /var/www/fallback

# Testar configuração do Nginx
nginx -t || error "Configuração do Nginx inválida."

# Recarregar serviços
log "Iniciando serviços..."
systemctl daemon-reload
systemctl enable nginx xray maritima-ws
systemctl restart nginx xray maritima-ws
systemctl restart sshd

# Limpeza
rm -rf "$TEMP_DIR"

log "Instalação concluída com sucesso!"
log "UUIDs gerados (salve-os em local seguro):"
echo -e "${YELLOW}Cliente 1: $UUID1"
echo "Cliente 2: $UUID2"
echo "Cliente 3: $UUID3"
echo "Cliente 4: $UUID4${NC}"
warn "Caso tenha usado certificado autoassinado, os clientes precisarão aceitá-lo ou usar 'Insecure'."
