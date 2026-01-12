#!/usr/bin/env python3
import socket
import threading
import select
import time
import os
import sys

# CONFIGURAÇÃO
BANNER_FILE = "/opt/maritima/banner.txt"
PORT = 80  # Mantém na 80 (ou 443 para SSL)
SSH_HOST = "127.0.0.1"
SSH_PORT = 22
BUFFER_SIZE = 16384
TIMEOUT = 30

# Banner padrão
DEFAULT_BANNER = """┌─────────────────────────────────────┐
│  🚢  ACESSO AUTORIZADO  🚢          │
│                                     │
│  👁️  MONITORAMENTO ATIVO  👁️       │
│                                     │
│  ❌ TORRENT = 🚫 BAN 🚫             │
│                                     │
│       ⚓ MARÍTIMA VPN ⚓             │
└─────────────────────────────────────┘

✅ CONEXÃO SSH WEB SOCKET
🔧 Porta: 80/443
📶 Status: ATIVO
⚠️  Monitoramento em tempo real"""

def get_banner():
    """Lê banner do arquivo"""
    if os.path.exists(BANNER_FILE):
        try:
            with open(BANNER_FILE, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if content:
                    return content
        except:
            pass
    return DEFAULT_BANNER

def send_initial_response(client_socket):
    """Envia resposta inicial que parece HTTP normal"""
    banner = get_banner()
    
    # Resposta que parece HTTP normal (para furar DPI)
    response = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html\r\n"
        "Cache-Control: no-cache\r\n"
        "Pragma: no-cache\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "<!DOCTYPE html>\r\n"
        "<html><head><title>Loading...</title></head>\r\n"
        "<body>\r\n"
        "<pre style='font-family: monospace;'>\r\n"
        f"{banner}\r\n"
        "\r\n"
        "Iniciando conexão segura...\r\n"
        "</pre>\r\n"
        "<script>\r\n"
        "// Simula carregamento normal\r\n"
        "setTimeout(function() {\r\n"
        "  document.body.innerHTML += '<br>✓ Conexão estabelecida';\r\n"
        "}, 1000);\r\n"
        "</script>\r\n"
        "</body></html>\r\n"
    )
    
    client_socket.send(response.encode('utf-8'))
    time.sleep(1)  # Pequena pausa para o banner ser lido

def handle_websocket_upgrade(client_socket):
    """Faz upgrade para WebSocket de forma discreta"""
    try:
        # Recebe requisição
        data = client_socket.recv(BUFFER_SIZE)
        if not data:
            return False
        
        # Verifica se é WebSocket (pode estar oculto em HTTP normal)
        if b"websocket" in data.lower() or b"upgrade" in data.lower():
            # Responde handshake WebSocket
            response = (
                b"HTTP/1.1 101 Switching Protocols\r\n"
                b"Upgrade: websocket\r\n"
                b"Connection: Upgrade\r\n"
                b"Sec-WebSocket-Accept: CWEfG0BkzUqC3aJq8L5nYQ==\r\n"
                b"Server: nginx/1.18\r\n"  # Disfarça como nginx
                b"\r\n"
            )
            client_socket.sendall(response)
            return True
        
        # Se não for WebSocket, pode ser reconexão
        elif b"GET /" in data or b"POST /" in data:
            # Envia página de redirecionamento discreta
            redirect = (
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: text/html\r\n"
                b"\r\n"
                b"<html><body>"
                b"<script>location.reload();</script>"
                b"</body></html>"
            )
            client_socket.sendall(redirect)
            return False
            
    except:
        pass
    return False

def proxy_ssh_traffic(client_socket):
    """Proxy entre WebSocket e SSH"""
    try:
        # Conecta ao SSH local
        ssh_socket = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
        
        # Proxy bidirecional
        sockets = [client_socket, ssh_socket]
        while True:
            try:
                readable, _, exceptional = select.select(sockets, [], sockets, 1)
                
                if exceptional:
                    break
                    
                for sock in readable:
                    data = sock.recv(BUFFER_SIZE)
                    if not data:
                        return
                    
                    # Encaminha dados
                    if sock is client_socket:
                        ssh_socket.sendall(data)
                    else:
                        client_socket.sendall(data)
                        
            except (select.error, socket.error):
                break
                
    except ConnectionRefusedError:
        print(f"[ERRO] SSH local não responde em {SSH_HOST}:{SSH_PORT}")
    except Exception as e:
        print(f"[ERRO] Proxy: {e}")
    finally:
        try:
            client_socket.close()
        except:
            pass

def handle_client(client_socket, client_addr):
    """Processa cliente: Banner → WebSocket → SSH"""
    print(f"[+] Cliente: {client_addr[0]}:{client_addr[1]}")
    
    try:
        # 1. Envia banner inicial (disfarçado como HTTP)
        send_initial_response(client_socket)
        
        # 2. Aguarda upgrade para WebSocket
        print(f"[*] Aguardando WebSocket de {client_addr[0]}")
        
        # 3. Tenta fazer upgrade
        if handle_websocket_upgrade(client_socket):
            print(f"[✓] WebSocket estabelecido com {client_addr[0]}")
            
            # 4. Inicia proxy SSH
            proxy_ssh_traffic(client_socket)
            
        else:
            # Cliente não fez upgrade, apenas mostrou banner
            print(f"[i] Banner mostrado para {client_addr[0]}")
            client_socket.close()
            
    except Exception as e:
        print(f"[!] Erro com {client_addr[0]}: {e}")
        try:
            client_socket.close()
        except:
            pass

def start_server():
    """Inicia servidor principal"""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    server.settimeout(5)
    
    try:
        server.bind(("0.0.0.0", PORT))
        server.listen(500)
        
        print("=" * 60)
        print(f"SERVIDOR BANNER + WEBSOCKET SSH")
        print(f"Porta: {PORT} → SSH: {SSH_HOST}:{SSH_PORT}")
        print(f"Banner: {BANNER_FILE}")
        print("=" * 60)
        
        while True:
            try:
                client_socket, client_addr = server.accept()
                client_socket.settimeout(TIMEOUT)
                
                # Inicia thread para cliente
                thread = threading.Thread(
                    target=handle_client,
                    args=(client_socket, client_addr),
                    daemon=True
                )
                thread.start()
                
            except socket.timeout:
                continue
            except KeyboardInterrupt:
                print("\n[!] Servidor interrompido")
                break
                
    except Exception as e:
        print(f"[ERRO FATAL] {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Verifica se SSH local está acessível
    try:
        test_socket = socket.create_connection((SSH_HOST, SSH_PORT), timeout=2)
        test_socket.close()
        print("[✓] SSH local está acessível")
    except:
        print("[!] AVISO: SSH local não está respondendo")
        print(f"[!] Verifique: ssh {SSH_HOST} -p {SSH_PORT}")
    
    start_server()
