#!/usr/bin/env python3
"""Minimal msgpack-rpc client for Neovim (stdlib only).

Usage: nvrpc.py SOCKET TIMEOUT METHOD [JSON_PARAMS]
Prints the result as JSON. Exit codes: 0 ok, 1 RPC error, 2 timeout,
3 connection failed.

Exists because `nvim --server --remote-expr` can only call nvim_eval, which
Neovim queues while it waits for input (pending key sequence, prompt,
getchar()). "Fast" API functions such as nvim_get_mode are answered even then,
so this is how `nv` tells "waiting for input" apart from "busy/hung".
"""
import json
import socket
import struct
import sys


def pack(o):
    if o is None:
        return b"\xc0"
    if o is True:
        return b"\xc3"
    if o is False:
        return b"\xc2"
    if isinstance(o, int):
        if 0 <= o < 128:
            return bytes([o])
        if -32 <= o < 0:
            return struct.pack("b", o)
        return b"\xd3" + struct.pack(">q", o)
    if isinstance(o, float):
        return b"\xcb" + struct.pack(">d", o)
    if isinstance(o, str):
        b = o.encode()
        n = len(b)
        if n < 32:
            return bytes([0xA0 | n]) + b
        return b"\xdb" + struct.pack(">I", n) + b
    if isinstance(o, (list, tuple)):
        n = len(o)
        head = bytes([0x90 | n]) if n < 16 else b"\xdd" + struct.pack(">I", n)
        return head + b"".join(pack(x) for x in o)
    if isinstance(o, dict):
        n = len(o)
        head = bytes([0x80 | n]) if n < 16 else b"\xdf" + struct.pack(">I", n)
        return head + b"".join(pack(k) + pack(v) for k, v in o.items())
    raise TypeError(f"cannot pack {type(o)}")


class NeedMore(Exception):
    pass


def unpack(buf, i=0):
    """Decode one object from buf at i; return (obj, next_i)."""
    def take(n):
        nonlocal i
        if i + n > len(buf):
            raise NeedMore
        s = buf[i:i + n]
        i += n
        return s

    t = take(1)[0]
    if t <= 0x7F:
        return t, i
    if t >= 0xE0:
        return t - 256, i
    if 0x80 <= t <= 0x8F:
        return _map(buf, i, t & 0x0F)
    if 0x90 <= t <= 0x9F:
        return _arr(buf, i, t & 0x0F)
    if 0xA0 <= t <= 0xBF:
        return take(t & 0x1F).decode(errors="replace"), i
    simple = {0xC0: None, 0xC2: False, 0xC3: True}
    if t in simple:
        return simple[t], i
    fmt = {0xCC: ">B", 0xCD: ">H", 0xCE: ">I", 0xCF: ">Q",
           0xD0: ">b", 0xD1: ">h", 0xD2: ">i", 0xD3: ">q",
           0xCA: ">f", 0xCB: ">d"}
    if t in fmt:
        f = fmt[t]
        return struct.unpack(f, take(struct.calcsize(f)))[0], i
    lens = {0xD9: ">B", 0xDA: ">H", 0xDB: ">I",       # str
            0xC4: ">B", 0xC5: ">H", 0xC6: ">I"}       # bin
    if t in lens:
        f = lens[t]
        n = struct.unpack(f, take(struct.calcsize(f)))[0]
        data = take(n)
        return (data.decode(errors="replace") if t >= 0xD9 else data.hex()), i
    if t in (0xDC, 0xDD, 0xDE, 0xDF):
        f = ">H" if t in (0xDC, 0xDE) else ">I"
        n = struct.unpack(f, take(struct.calcsize(f)))[0]  # advances i first
        return (_arr if t <= 0xDD else _map)(buf, i, n)
    # ext types: Neovim uses these for Buffer/Window/Tabpage handles
    fixext = {0xD4: 1, 0xD5: 2, 0xD6: 4, 0xD7: 8, 0xD8: 16}
    if t in fixext:
        take(1)
        data = take(fixext[t])
        v, _ = unpack(data, 0)
        return v, i
    if t in (0xC7, 0xC8, 0xC9):
        f = {0xC7: ">B", 0xC8: ">H", 0xC9: ">I"}[t]
        n = struct.unpack(f, take(struct.calcsize(f)))[0]
        take(1)
        v, _ = unpack(take(n), 0)
        return v, i
    raise ValueError(f"unknown msgpack type 0x{t:02x}")


def _arr(buf, i, n):
    out = []
    for _ in range(n):
        v, i = unpack(buf, i)
        out.append(v)
    return out, i


def _map(buf, i, n):
    out = {}
    for _ in range(n):
        k, i = unpack(buf, i)
        v, i = unpack(buf, i)
        out[str(k)] = v
    return out, i


def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 1
    try:
        path, timeout, method = sys.argv[1], float(sys.argv[2]), sys.argv[3]
        params = json.loads(sys.argv[4]) if len(sys.argv) > 4 else []
    except ValueError as e:
        print(f"bad arguments: {e}", file=sys.stderr)
        return 1

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(path)
    except OSError as e:
        print(f"connect failed: {e}", file=sys.stderr)
        return 3
    msgid = 1
    try:
        s.sendall(pack([0, msgid, method, params]))
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                print("connection closed", file=sys.stderr)
                return 3
            buf += chunk
            i = 0
            while True:
                try:
                    msg, i2 = unpack(buf, i)
                except NeedMore:
                    break
                i = i2
                # [1, msgid, error, result]; skip notifications/requests
                if isinstance(msg, list) and len(msg) == 4 and msg[0] == 1 and msg[1] == msgid:
                    if msg[2] is not None:
                        print(json.dumps(msg[2]), file=sys.stderr)
                        return 1
                    print(json.dumps(msg[3]))
                    return 0
            buf = buf[i:]
    except socket.timeout:
        return 2


if __name__ == "__main__":
    sys.exit(main())
