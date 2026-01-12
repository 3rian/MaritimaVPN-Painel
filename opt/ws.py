#!/usr/bin/env python3
import socket
import threading
import select
import time
import os
import sys

# CONFIGURAÇÃO
BANNER_FILE = "/opt/maritima/banner.txt"
PORT = 80
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

def send_banner_response(client_socket):
    """Envia APENAS o banner (sem upgrade para WebSocket)"""
    banner = get_banner()
    
    response = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        "Connection: close\r\n"
        "\r\n"
        f"{banner}\r\n"
        "\r\n"
        "⚓ MARÍTIMA VPN ⚓\r\n"
        "🔒 Conexão estabelecida com sucesso\r\n"
        "🌐 Use: ssh http proxy:80\r\n"
        "🔐 ou: ssh http ssl proxy:443\r\n"
    )
    
    client_socket.send(response.encode('utf-8'))
    print("[BANNER] Banner enviado")

def handle_websocket_connection(client_socket, client_addr):
    """Lida APENAS com conexões WebSocket"""
    print(f"[WS] Conexão WebSocket de {client_addr[0]}:{client_addr[1]}")
    
    try:
        data = client_socket.recv(BUFFER_SIZE)
        if not data:
            return
        
        if b"websocket" not in data.lower() and b"upgrade" not in data.lower():
            print(f"[WS] {client_addr[0]}: Não é WebSocket")
            send_banner_response(client_socket)
            return
        
        # Handshake WebSocket
        response = (
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: CWEfG0BkzUqC3aJq8L5nYQ==\r\n"
            b"Server: nginx/1.18\r\n"
            b"\r\n"
        )
        client_socket.sendall(response)
        
        # Conecta ao SSH
        ssh_socket = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
        print(f"[WS] {client_addr[0]}: Conectado ao SSH")
        
        # Proxy
        sockets = [client_socket, ssh_socket]
        while True:
            try:
                readable, _, exceptional = select.select(sockets, [], sockets, 1)
                
                if exceptional:
                    break
                    
                for sock in readable:
                    data = sock.recv(BUFFER_SIZE)
                    if not data:
                        print(f"[WS] {client_addr[0]}: Conexão fechada")
                        return
                    
                    if sock is client_socket:
                        ssh_socket.sendall(data)
                    else:
                        client_socket.sendall(data)
                        
            except (select.error, socket.error):
                break
                
    except ConnectionRefusedError:
        print(f"[ERRO] SSH local não responde")
        error_msg = "HTTP/1.1 503 Service Unavailable\r\n\r\nSSH not available"
        client_socket.sendall(error_msg.encode('utf-8'))
    except Exception as e:
        print(f"[ERRO] {client_addr[0]}: {e}")
    finally:
        try:
            client_socket.close()
        except:
            pass

def handle_client(client_socket, client_addr):
    """Decide se é HTTP (banner) ou WebSocket (proxy)"""
    print(f"[+] Conexão de {client_addr[0]}:{client_addr[1]}")
    
    try:
        client_socket.settimeout(2)
        data = client_socket.recv(BUFFER_SIZE, socket.MSG_PEEK)
        
        if not data:
            client_socket.close()
            return
        
        if b"websocket" in data.lower() or b"upgrade:" in data.lower():
            handle_websocket_connection(client_socket, client_addr)
        else:
            send_banner_response(client_socket)
            client_socket.close()
            
    except socket.timeout:
        send_banner_response(client_socket)
        client_socket.close()
    except Exception as e:
        print(f"[!] Erro: {e}")
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
        print(f"🌊 MARÍTIMA VPN - BANNER + WEBSOCKET SSH")
        print(f"📍 Porta: {PORT}")
        print(f"🔗 SSH: {SSH_HOST}:{SSH_PORT}")
        print(f"📢 Banner: {BANNER_FILE}")
        print("=" * 60)
        
        while True:
            try:
                client_socket, client_addr = server.accept()
                client_socket.settimeout(5)
                
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
    try:
        test = socket.create_connection((SSH_HOST, SSH_PORT), timeout=2)
        test.close()
        print("[✓] SSH local OK")
    except:
        print("[!] AVISO: SSH local inacessível")
    
    start_server()
