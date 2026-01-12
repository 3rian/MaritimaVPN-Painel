#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import socket
import threading
import select
import time

# ================= CONFIG =================
BIND_IP = "0.0.0.0"
PORT = 8080
BUF_SIZE = 65536
TIMEOUT = 60
DEFAULT_HOST = ("127.0.0.1", 22)

HTTP_RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\n\r\n"
# =========================================


def load_banner():
    try:
        with open("/opt/maritima/banner.txt", "rb") as f:
            return f.read() + b"\r\n"
    except:
        return b""


BANNER = load_banner()


class ClientHandler(threading.Thread):
    def __init__(self, client):
        super().__init__(daemon=True)
        self.client = client
        self.target = None

    def run(self):
        try:
            data = self.client.recv(BUF_SIZE)
            if not data:
                return

            host, port = self.parse_host(data)

            # Conecta no destino SSH
            self.target = socket.create_connection((host, port), timeout=10)

            # PRIMEIRO: resposta HTTP
            self.client.sendall(HTTP_RESPONSE)

            # SEGUNDO: banner (já dentro do túnel)
            if BANNER:
                self.client.sendall(BANNER)

            # Inicia ponte
            self.bridge()

        except:
            pass
        finally:
            self.close()

    def parse_host(self, data):
        host = DEFAULT_HOST[0]
        port = DEFAULT_HOST[1]

        for line in data.split(b"\r\n"):
            if line.lower().startswith(b"x-real-host:"):
                value = line.split(b":", 1)[1].strip().decode()
                if ":" in value:
                    host, port = value.split(":", 1)
                    port = int(port)
                else:
                    host = value
                break

        return host, port

    def bridge(self):
        sockets = [self.client, self.target]
        idle = 0

        while True:
            r, _, _ = select.select(sockets, [], [], 3)
            if not r:
                idle += 1
                if idle > TIMEOUT:
                    break
                continue

            for s in r:
                data = s.recv(BUF_SIZE)
                if not data:
                    return
                if s is self.client:
                    self.target.sendall(data)
                else:
                    self.client.sendall(data)

    def close(self):
        for s in (self.client, self.target):
            try:
                if s:
                    s.close()
            except:
                pass


class ProxyServer:
    def start(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((BIND_IP, PORT))
            s.listen(200)
            print(f"[HTTP-SSH] Rodando na porta {PORT}")

            while True:
                client, _ = s.accept()
                ClientHandler(client).start()


if __name__ == "__main__":
    ProxyServer().start()

