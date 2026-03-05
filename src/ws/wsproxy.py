#!/usr/bin/env python3
import json, os, pwd, grp
import socket, threading, select, sys, time
import base64, hashlib

LISTEN_ADDR = "0.0.0.0"
LISTEN_PORT = 8880
BUFLEN = 4096
TIMEOUT = 120

TARGET_HOST = "127.0.0.1"
TARGET_PORT = 2222  # SSH custom (como você está usando)

PASS = ""  # Senha WS opcional via header X-Pass
BANNER_JSON = "/opt/maritima/banner/banner.json"
VPN_GROUP = "vpn"



def find_header(data: bytes, header: bytes):
    i = data.lower().find(header.lower())
    if i == -1:
        return None
    j = data.find(b"\r\n", i)
    if j == -1:
        return None
    line = data[i:j]
    parts = line.split(b":", 1)
    if len(parts) != 2:
        return None
    return parts[1].strip().decode(errors="ignore")

def is_websocket_handshake(buf: bytes) -> bool:
    b = buf.lower()
    return (b"upgrade: websocket" in b and b"connection:" in b and b"upgrade" in b)

def ws_accept(key: str) -> str:
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    sha1 = hashlib.sha1((key + GUID).encode()).digest()
    return base64.b64encode(sha1).decode()

def ws_response(key: str) -> bytes:
    accept = ws_accept(key)
    return (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n"
        "\r\n"
    ).encode()



ANSI = {
  "red": "\033[31m", "green": "\033[32m", "yellow": "\033[33m",
  "blue": "\033[34m", "cyan": "\033[36m", "white": "\033[37m",
  "reset": "\033[0m", "bold": "\033[1m", "gray": "\033[90m"
}

def user_in_group(username: str, groupname: str) -> bool:
    try:
        gid = grp.getgrnam(groupname).gr_gid
        u = pwd.getpwnam(username)
        groups = os.getgrouplist(username, u.pw_gid)
        return gid in groups
    except Exception:
        return False

def load_banner_lines():
    try:
        with open(BANNER_JSON, "r", encoding="utf-8") as f:
            data = json.load(f)
        items = data.get("items", [])
        out = []
        for it in items:
            text = str(it.get("text", "")).strip()
            if not text:
                continue
            color = str(it.get("color", "white")).lower()
            bold = bool(it.get("bold", False))
            pre = ""
            if bold:
                pre += ANSI["bold"]
            pre += ANSI.get(color, ANSI["white"])
            out.append(pre + text + ANSI["reset"])
        return out
    except Exception:
        return []


class Conn(threading.Thread):
    def __init__(self, c):
        super().__init__(daemon=True)
        self.c = c
        self.t = None

    def run(self):
        try:
            self.c.settimeout(6)
            buf = self.c.recv(BUFLEN)
            if not buf:
                return

            ws = is_websocket_handshake(buf)

            # Responder 404 APENAS para HTTP normal (scan/health-check), não para WebSocket
            if (b"GET /" in buf or b"HEAD /" in buf or b"OPTIONS /" in buf) and not ws:
                self.c.sendall(b"HTTP/1.1 404 Not Found\r\n\r\n")
                return

            # Opcional: validar senha
            xpass = find_header(buf, b"X-Pass")
            if PASS and xpass != PASS:
                self.c.sendall(b"HTTP/1.1 400 WrongPass\r\n\r\n")
                return

            # Compat: consumir mais um pacote se cliente usa X-Split
            if b"X-Split" in buf:
                try:
                    self.c.recv(BUFLEN)
                except:
                    pass

            # Se for WS, exige Sec-WebSocket-Key e responde 101 correto
            if ws:
                wskey = find_header(buf, b"Sec-WebSocket-Key")
                if not wskey:
                    self.c.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                    return
                self.c.sendall(ws_response(wskey))

                            # Mensageiro (após handshake WS)
            try:
                for line in load_banner_lines():
                    self.c.sendall((line + "\r\n").encode())
                self.c.sendall(b"\r\n")
            except:
                pass


            # Conecta no SSH
            self.t = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=6)

            self.pipe()
        except:
            pass
        finally:
            try:
                self.c.close()
            except:
                pass
            try:
                if self.t:
                    self.t.close()
            except:
                pass

    def pipe(self):
        socks = [self.c, self.t]
        last = time.time()
        while True:
            r, _, e = select.select(socks, [], socks, 3)
            if e:
                break
            for s in r:
                data = s.recv(BUFLEN)
                if not data:
                    return
                (self.c if s is self.t else self.t).sendall(data)
                last = time.time()
            if time.time() - last > TIMEOUT:
                break

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((LISTEN_ADDR, LISTEN_PORT))
srv.listen(200)

print(f"WSProxy {LISTEN_PORT} → SSH {TARGET_PORT} ready")

while True:
    c, _ = srv.accept()
    Conn(c).start()

