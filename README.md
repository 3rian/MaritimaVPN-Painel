# Use este comando abaixo para que possa chamar o painel com o comando "maritima".
 chmod +x /root/maritima.sh
 ln -sf /root/maritima.sh /usr/local/bin/maritima
 hash -r

# Comando para instalar certificado
sudo certbot --nginx -d SEU DOMINIO AQUI
# MaritimaVPN-Painel
Painel Admin MarítimaVPN SSH
# Marítima VPN Painel

Painel de gerenciamento SSH / VPN com:
- Controle de usuários
- Expiração automática
- Sincronização forçada
- Proxy HTTP, WebSocket, Xray
- Segurança e manutenção


## Instalação
```bash
wget -O install.sh https://raw.githubusercontent.com/3rian/MaritimaVPN-Painel/master/install.sh
chmod +x install.sh
sudo ./install.sh
