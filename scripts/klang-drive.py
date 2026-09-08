#!/usr/bin/env python3
"""Drive klang headlessly: screenshot it, click it, type into it.

Qt ships a VNC platform plugin, so the app can render to an offscreen
framebuffer that this speaks RFB to directly. No compositor, no focus stealing,
no capturing whatever else is on screen.

    scripts/klang-drive.py run wait 5 shot out.png
    scripts/klang-drive.py run wait 5 click 640 400 wait 2 shot after.png
    scripts/klang-drive.py run wait 5 rclick 640 400 wait 1 shot menu.png
    scripts/klang-drive.py run wait 5 type "hardwell" key Return wait 3 shot s.png

Commands run in order. `run` starts the app first and stops it at the end;
without it, an already-running instance on the port is used.

Limitation: Qt's VNC plugin does not translate RFB buttons 4/5 into wheel
events, so scrolling cannot be exercised here — check that by hand.
"""

from __future__ import annotations

import os
import signal
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BINARY = REPO / "target" / "debug" / "klang"
PORT = 5910          # Qt's vnc plugin serves display :N on 5900+N
SIZE = "1280x820"


class Rfb:
    """Just enough RFB 3.8 for screenshots and synthetic input."""

    def __init__(self, port: int = PORT, timeout: float = 10.0):
        deadline = time.monotonic() + timeout
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise SystemExit(f"nothing listening on port {port}")
                time.sleep(0.2)
        self.sock.settimeout(20)
        self._handshake()
        self.buttons = 0

    def _recv(self, n: int) -> bytes:
        out = b""
        while len(out) < n:
            chunk = self.sock.recv(n - len(out))
            if not chunk:
                raise SystemExit("server closed the connection")
            out += chunk
        return out

    def _handshake(self) -> None:
        version = self._recv(12)
        self.sock.sendall(version)

        # Qt speaks RFB 3.3, where the server dictates one security type as a
        # 4-byte value rather than offering a list.
        if version < b"RFB 003.007":
            if struct.unpack(">I", self._recv(4))[0] != 1:
                raise SystemExit("server wants authentication")
        else:
            count = self._recv(1)[0]
            if count == 0:
                reason = self._recv(struct.unpack(">I", self._recv(4))[0])
                raise SystemExit(f"connection refused: {reason!r}")
            types = self._recv(count)
            if 1 not in types:
                raise SystemExit(f"server wants authentication: {list(types)}")
            self.sock.sendall(bytes([1]))
            if struct.unpack(">I", self._recv(4))[0] != 0:
                raise SystemExit("security handshake failed")

        self.sock.sendall(bytes([1]))  # shared
        self.width, self.height = struct.unpack(">HH", self._recv(4))
        self._recv(16)                 # server pixel format, replaced below
        self._recv(struct.unpack(">I", self._recv(4))[0])  # desktop name

        # 32bpp true colour, big-endian, so a pixel decodes as R,G,B,pad.
        fmt = struct.pack(
            ">BBBBHHHBBB3x",
            32, 24, 1, 1,
            255, 255, 255,
            24, 16, 8,
        )
        self.sock.sendall(struct.pack(">B3x", 0) + fmt)
        self.sock.sendall(struct.pack(">BxH", 2, 1) + struct.pack(">i", 0))  # raw only

    def capture(self) -> "Image.Image":
        from PIL import Image

        self.sock.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))
        frame = Image.new("RGB", (self.width, self.height))

        while True:
            msg = self._recv(1)[0]
            if msg != 0:
                continue
            self._recv(1)
            rects = struct.unpack(">H", self._recv(2))[0]
            for _ in range(rects):
                x, y, w, h, encoding = struct.unpack(">HHHHi", self._recv(12))
                if encoding != 0:
                    raise SystemExit(f"unexpected encoding {encoding}")
                if w and h:
                    raw = self._recv(w * h * 4)
                    tile = Image.frombytes("RGBX", (w, h), raw)
                    frame.paste(tile.convert("RGB"), (x, y))
            return frame

    def move(self, x: int, y: int) -> None:
        self.sock.sendall(struct.pack(">BBHH", 5, self.buttons, x, y))

    def click(self, x: int, y: int, button: int = 1) -> None:
        mask = 1 << (button - 1)
        self.move(x, y)
        self.sock.sendall(struct.pack(">BBHH", 5, mask, x, y))
        time.sleep(0.05)
        self.sock.sendall(struct.pack(">BBHH", 5, 0, x, y))
        time.sleep(0.1)

    def key(self, name: str) -> None:
        code = KEYS.get(name)
        if code is None:
            if len(name) != 1:
                raise SystemExit(f"unknown key: {name}")
            code = ord(name)
        for down in (1, 0):
            self.sock.sendall(struct.pack(">BBxxI", 4, down, code))
            time.sleep(0.02)

    def type_text(self, text: str) -> None:
        for ch in text:
            self.key(ch)
            time.sleep(0.03)


KEYS = {
    "Return": 0xFF0D, "Enter": 0xFF0D, "Tab": 0xFF09, "Escape": 0xFF1B,
    "BackSpace": 0xFF08, "Delete": 0xFFFF, "Home": 0xFF50, "End": 0xFF57,
    "PageUp": 0xFF55, "PageDown": 0xFF56, "Left": 0xFF51, "Up": 0xFF52,
    "Right": 0xFF53, "Down": 0xFF54, "Space": 0x20,
}


def port_is_free(port: int = PORT) -> bool:
    with socket.socket() as s:
        return s.connect_ex(("127.0.0.1", port)) != 0


def launch() -> subprocess.Popen:
    if not BINARY.exists():
        raise SystemExit(f"not built: {BINARY}")
    # A stale instance would keep the port and silently serve an old build.
    if not port_is_free():
        subprocess.run(["pkill", "-x", "klang"], check=False)
        deadline = time.monotonic() + 5
        while not port_is_free():
            if time.monotonic() > deadline:
                raise SystemExit(f"port {PORT} still busy; kill it by hand")
            time.sleep(0.2)
    env = {
        **os.environ,
        "QT_QPA_PLATFORM": f"vnc:size={SIZE}:port={PORT}",
        # Set KLANG_CONFIG_DIR before running to drive a fresh profile.
        # The VNC plugin has no compositor, so the app must draw its own chrome.
        "QT_QPA_FONTDIR": os.environ.get("QT_QPA_FONTDIR", "/usr/share/fonts"),
    }
    return subprocess.Popen(
        [str(BINARY)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args:
        print(__doc__)
        return 2

    proc = None
    if args[0] == "run":
        args = args[1:]
        proc = launch()
        time.sleep(3)

    vnc = Rfb()
    print(f"connected: {vnc.width}x{vnc.height}")

    try:
        i = 0
        while i < len(args):
            cmd = args[i]
            if cmd == "shot":
                path = Path(args[i + 1]); i += 2
                vnc.capture().save(path)
                print(f"shot {path}")
            elif cmd == "click":
                x, y = int(args[i + 1]), int(args[i + 2]); i += 3
                vnc.click(x, y)
                print(f"click {x},{y}")
            elif cmd == "rclick":
                x, y = int(args[i + 1]), int(args[i + 2]); i += 3
                vnc.click(x, y, button=3)
                print(f"rclick {x},{y}")
            elif cmd == "key":
                vnc.key(args[i + 1]); i += 2
            elif cmd == "type":
                vnc.type_text(args[i + 1]); i += 2
            elif cmd == "wait":
                time.sleep(float(args[i + 1])); i += 2
            else:
                raise SystemExit(f"unknown command: {cmd}")
    finally:
        if proc is not None:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            err = proc.stderr.read().decode(errors="replace") if proc.stderr else ""
            interesting = [
                line for line in err.splitlines()
                if "qml" in line.lower() or "TypeError" in line or "Unable" in line
            ]
            if interesting:
                print("\nQML output:")
                print("\n".join(interesting[:20]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
