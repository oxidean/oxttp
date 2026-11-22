#!/usr/bin/env python3
"""Scripted one-shot-per-connection HTTP server for the golden harness.

Usage: golden-server.py <port-file> <script>...
Each script arg is one connection's response: `STATUS REASON\nHeader: v\n\nbody`
(\\n escapes decoded) or `<ECHO>` (200 + request bytes as body). Serves len(scripts)
connections then exits; port written to port-file on bind.
"""
import socket, sys, threading, time, re

def serve(scripts, port_file):
    l = socket.socket()
    l.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    l.bind(("127.0.0.1", 0)); l.listen(8)
    open(port_file, "w").write(str(l.getsockname()[1]))
    l.settimeout(30)
    for script in scripts:
        try:
            c, _ = l.accept()
        except socket.timeout:
            break
        c.settimeout(10)
        try:
            req = b""
            while b"\r\n\r\n" not in req:
                d = c.recv(65536)
                if not d: break
                req += d
            m = re.search(rb"content-length: *(\d+)", req, re.I)
            need = int(m.group(1)) if m else 0
            head_end = req.index(b"\r\n\r\n") + 4
            while len(req) - head_end < need:
                d = c.recv(65536)
                if not d: break
                req += d
            if script == "<ECHO>":
                body = req
                resp = b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
            elif script.startswith("<SLEEP:"):
                ms = int(script[7:script.index(">")])
                time.sleep(ms / 1000.0)
                resp = script[script.index(">")+1:].replace("\\n", "\r\n").encode()
                resp = b"HTTP/1.1 " + resp
            else:
                resp = b"HTTP/1.1 " + script.replace("\\n", "\r\n").encode()
            c.sendall(resp)
        finally:
            c.close()
    l.close()

if __name__ == "__main__":
    serve(sys.argv[2:], sys.argv[1])
