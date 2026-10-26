#!/usr/bin/env python3
"""Имитация adbd телевизора на Android 9 для проверки AdbClient и Tv без настоящего ТВ.

Проверяет всё, что проверяет настоящий adbd: magic и контрольные суммы пакетов, подпись токена
(RSA PKCS#1 v1.5 поверх DigestInfo SHA-1) и формат открытого ключа android_pubkey.
"""

import base64
import io
import os
import re
import socket
import struct
import threading
import zipfile

A_CNXN, A_AUTH, A_OPEN, A_OKAY, A_CLSE, A_WRTE = 0x4e584e43, 0x48545541, 0x4e45504f, 0x59414b4f, 0x45534c43, 0x45545257
SHA1_PREFIX = bytes.fromhex("3021300906052b0e03021a05000414")
CHUNK = 4096


def parse_pubkey(payload):
    """Разбирает AUTH RSAPUBLICKEY строго по формату adbd. Возвращает (n, e) или бросает ValueError."""
    if not payload.endswith(b"\0"):
        raise ValueError("ключ без завершающего нуля")
    text = payload[:-1].decode()
    b64, _, name = text.partition(" ")
    raw = base64.b64decode(b64, validate=True)
    if len(raw) != 524 or not name:
        raise ValueError(f"неверная длина ключа {len(raw)} или пустое имя")
    words, n0inv = struct.unpack_from("<II", raw)
    n = int.from_bytes(raw[8:264], "little")
    rr = int.from_bytes(raw[264:520], "little")
    e = struct.unpack_from("<I", raw, 520)[0]
    if words != 64:
        raise ValueError("размер модуля не 2048 бит")
    if (n0inv * n) % 2**32 != 2**32 - 1:
        raise ValueError("n0inv неверен")
    if rr != pow(2, 4096, n):
        raise ValueError("rr неверен")
    return n, e


def verify(sig, token, key):
    n, e = key
    k = (n.bit_length() + 7) // 8
    em = pow(int.from_bytes(sig, "big"), e, n).to_bytes(k, "big")
    tail = b"\0" + SHA1_PREFIX + token
    return em == b"\0\1" + b"\xff" * (k - 3 - len(tail) + 1) + tail


class FakeTv:
    """Состояние телевизора и ответы на shell-команды (как в Android 9 / Яндекс ТВ)."""

    def __init__(self):
        # [системный, состояние: 0 — включён, 2 — отключён производителем, 3 — пользователем, сторонний]
        self.pkgs = {
            "android": [1, 0, 0], "com.android.systemui": [1, 0, 0], "com.mediatek.tvinput": [1, 0, 0],
            "com.yandex.tv.home": [1, 0, 0], "ru.kinopoisk.tv": [1, 0, 0], "com.yandex.keyboard": [1, 0, 0],
            "com.vendor.ads": [1, 0, 0], "com.vendor.games": [1, 0, 0], "com.amediateka.tv": [0, 0, 1],
            "com.vendor.oldsetup": [1, 2, 0], "com.leorai.tvtuner": [0, 0, 1], "com.limelight": [0, 0, 1],
        }
        self.settings = {"secure/default_input_method": "com.yandex.keyboard/.Ime",
                         "secure/enabled_accessibility_services": "com.spocky.projengmenu/.Override",
                         "global/animator_duration_scale": "1.0"}
        self.appops, self.wm, self.log = {}, {}, []
        self.killed = False
        self.stopped = set()
        self.dot_blocked = {"dns.google"}
        bundle = io.BytesIO()
        with zipfile.ZipFile(bundle, "w") as z:  # так устроен .apkm с APKMirror
            for name in ("base.apk", "split_config.armeabi_v7a.apk", "split_config.arm64_v8a.apk",
                         "split_config.xhdpi.apk"):
                z.writestr(name, os.urandom(6000) + name.encode())
            z.writestr("info.json", "{}")
            z.writestr("icon.png", b"png")
        self.files = {"/storage/1234-ABCD/apk/Projectivy Launcher.apkm": bundle.getvalue()}
        self.usb = ["/storage/1234-ABCD/apk/ByeByeDPI.apk", "/storage/1234-ABCD/apk/SmartTube Beta.apk",
                    "/storage/1234-ABCD/apk/TVTuner.apk", "/storage/1234-ABCD/apk/readme.txt",
                    *self.files]
        self.sessions, self.split_installs = {}, []

    def exec(self, c, stdin):
        """Сервис exec: двоичный вывод и, для install-write, данные из stdin."""
        self.log.append("exec:" + c)
        m = re.match(r"cat '(.+)'$", c)
        if m:
            return self.files[m.group(1)]
        m = re.match(r"cmd package install-write -S (\d+) (\d+) (\S+) -$", c)
        if m and int(m.group(1)) == len(stdin) and m.group(2) in self.sessions:
            self.sessions[m.group(2)]["parts"][m.group(3)] = stdin
            return f"Success: streamed {len(stdin)} bytes\n".encode()
        return b"Error: bad exec\n"

    def shell(self, c):
        self.log.append(c)
        w = c.split()
        if c.startswith("getprop"):
            return {"ro.product.model": "SMART-TV-43", "ro.product.manufacturer": "TEST",
                    "ro.build.version.release": "9", "ro.product.cpu.abilist": "armeabi-v7a,armeabi"}.get(w[1], "") + "\n"
        if "resolve-activity" in c:
            return "priority=0 preferredOrder=0\ncom.yandex.tv.home/.HomeActivity\n"
        if w[0] == "settings":
            key = f"{w[2]}/{w[3]}"
            if w[1] == "get":
                return self.settings.get(key, "null") + "\n"
            if w[1] == "put":
                self.settings[key] = w[4]
            elif w[1] == "delete":
                self.settings.pop(key, None)
            return ""
        if c.startswith("pm list packages"):
            flags = w[3:]
            res = [p for p, (sysp, en, third) in self.pkgs.items()
                   if not ("-e" in flags and en) and not ("-d" in flags and not en)
                   and not ("-s" in flags and not sysp) and not ("-3" in flags and not third)]
            return "".join(f"package:{p}\n" for p in res)
        if w[:2] in (["pm", "disable-user"], ["pm", "enable"]):
            p = w[-1]
            if p not in self.pkgs:
                return f"Error: Unknown package: {p}\n"
            self.pkgs[p][1] = 3 if w[1] == "disable-user" else 0
            return f"Package {p} new state: {'disabled-user' if w[1] == 'disable-user' else 'enabled'}\n"
        if c.startswith("dumpsys package"):
            return f"enabled={self.pkgs[w[2]][1]}\n"
        if c == "cat /proc/meminfo":
            return f"MemTotal:        1214000 kB\nMemFree:          60000 kB\nMemAvailable:    {420000 if self.killed else 250000} kB\n"
        if c == "cat /proc/uptime":
            return "400000.12 900000.00\n"
        if c == "dumpsys meminfo":
            return ("Applications Memory Usage (in Kilobytes):\n\nTotal PSS by process:\n"
                    "    190,345K: system (pid 900)\n    150,100K: com.yandex.tv.home (pid 1500 / activities)\n"
                    "     80,000K: com.vendor.ads (pid 2000)\n     30,000K: com.vendor.ads:push (pid 2001)\n"
                    "     60,000K: com.amediateka.tv (pid 2100)\n     40,000K: com.limelight (pid 2200)\n"
                    "     35,000K: com.spocky.projengmenu (pid 2300)\n\nTotal PSS by OOM adjustment:\n")
        if c == "df -k /data":
            return "Filesystem     1K-blocks    Used Available Use% Mounted on\n/dev/block/dm-1 5000000 4300000 700000 86% /data\n"
        if w[0] == "wm":
            kind = w[1]
            if len(w) == 2:
                phys = "1920x1080" if kind == "size" else "320"
                over = f"\nOverride {kind}: {self.wm[kind]}" if kind in self.wm else ""
                return f"Physical {kind}: {phys}{over}\n"
            if w[2] == "reset":
                self.wm.pop(kind, None)
            else:
                self.wm[kind] = w[2]
            return ""
        if w[:3] == ["cmd", "appops", "set"]:
            if w[3] not in self.pkgs:
                return "Error: Unknown package\n"
            self.appops[f"{w[3]}/{w[4]}"] = w[5]
            return ""
        if w[:3] == ["cmd", "appops", "get"]:
            mode = self.appops.get(f"{w[3]}/{w[4]}", "default")
            return "No operations.\n" if mode == "default" else f"{w[4]}: {mode}; time=+1m ago\n"
        if c == "am kill-all":
            self.killed = True
            return ""
        if c.startswith("cmd package compile"):
            return "Success\n" if w[-1] in self.pkgs else "Failure: package not found\n"
        m = re.match(r"cmd package install-create -r -S (\d+)$", c)
        if m:
            sid = str(77 + len(self.sessions))
            self.sessions[sid] = {"total": int(m.group(1)), "parts": {}}
            return f"Success: created install session [{sid}]\n"
        m = re.match(r"cmd package install-(commit|abandon) (\d+)$", c)
        if m:
            session = self.sessions.pop(m.group(2))
            if m.group(1) == "abandon":
                return "Success\n"
            if sum(map(len, session["parts"].values())) != session["total"]:
                return "Failure [INSTALL_FAILED_INVALID_APK: size mismatch]\n"
            with zipfile.ZipFile(io.BytesIO(next(iter(self.files.values())))) as z:
                if any(z.read(name.split("_", 1)[1]) != data for name, data in session["parts"].items()):
                    return "Failure [INSTALL_FAILED_INVALID_APK: corrupted split]\n"
            self.split_installs.append(sorted(session["parts"]))
            self.pkgs["com.spocky.projengmenu"] = [0, 0, 1]
            return "Success\n"
        if c.startswith("for f in /storage/*/apk/*;"):
            return "".join(p + "\n" for p in self.usb)
        m = re.match(r"cp '(.+)' (\S+) && pm install -r \2; rm -f \2$", c)
        if m:
            name = os.path.basename(m.group(1)).lower()
            pkg = "io.github.romanvht.byedpi" if "byedpi" in name else "com.teamsmart.videomanager.tv"
            self.pkgs[pkg] = [0, 0, 1]
            return "Success\n"
        if c.startswith("am force-stop"):
            self.stopped.add(w[-1])
            return ""
        if c in ("pm trim-caches 999G", "cmd package bg-dexopt-job"):
            return ""
        if c.startswith("ping "):
            # Провайдер подменяет обычный DNS для YouTube; DNS-over-TLS к dns.google заблокирован.
            host = w[-1]
            private = self.settings.get("global/private_dns_specifier") \
                if self.settings.get("global/private_dns_mode") == "hostname" else None
            ok = private not in self.dot_blocked if private else not any(
                y in host for y in ("youtube", "ytimg", "googleapis"))
            return (f"PING {host} (142.250.74.14) 56(84) bytes of data.\n\n--- {host} ping statistics ---\n"
                    "1 packets transmitted, 0 received, 100% packet loss, time 0ms\n") if ok else f"ping: unknown host {host}\n"
        if c.startswith("pidof"):
            return "4321\n" if w[1] in self.pkgs and w[1] not in self.stopped else ""
        if c == "dumpsys input":
            return ("INPUT MANAGER (dumpsys input)\n\nInput Reader State:\n  Device -1: Virtual\n    Sources: 0x00000301\n"
                    "  Device 3: TV Remote\n    Sources: 0x00000301\n"
                    "  Device 7: Wireless Controller\n    IsExternal: true\n    Sources: 0x01000511\n")
        if c == "cat /sys/class/net/eth0/operstate 2>/dev/null":
            return ""
        if c == "dumpsys wifi | grep -m 1 mWifiInfo":
            return ("mWifiInfo SSID: Home, BSSID: aa:bb:cc, Supplicant state: COMPLETED, RSSI: -76, "
                    "Link speed: 72Mbps, Frequency: 2437MHz, Net ID: 0\n")
        return f"/system/bin/sh: {w[0]}: not found\n"


class FakeAdbd:
    def __init__(self, tv, accept_keys=True, port=0):
        self.tv, self.accept_keys = tv, accept_keys
        self.trusted, self.prompts, self.connections, self.errors = [], 0, 0, []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self):
        while True:
            conn, _ = self.sock.accept()
            threading.Thread(target=self._session, args=(conn,), daemon=True).start()

    @staticmethod
    def _read(f):
        header = f.read(24)
        if len(header) < 24:
            raise EOFError
        cmd, a0, a1, length, checksum, magic = struct.unpack("<6I", header)
        data = f.read(length)
        if magic != cmd ^ 0xffffffff:
            raise ValueError("неверный magic")
        if sum(data) & 0xffffffff != checksum:
            raise ValueError("неверная контрольная сумма")  # adbd версии 0x01000000 её проверяет
        return cmd, a0, a1, data

    @staticmethod
    def _send(conn, cmd, a0, a1, data=b""):
        conn.sendall(struct.pack("<6I", cmd, a0, a1, len(data), sum(data) & 0xffffffff, cmd ^ 0xffffffff) + data)

    def _session(self, conn):
        f = conn.makefile("rb")
        try:
            cmd, version, maxdata, data = self._read(f)
            assert cmd == A_CNXN and data.startswith(b"host::"), "первым должен быть CNXN"
            token = os.urandom(20)
            self._send(conn, A_AUTH, 1, 0, token)
            while True:
                cmd, a0, a1, data = self._read(f)
                assert cmd == A_AUTH, "до авторизации ждём только AUTH"
                if a0 == 2 and any(verify(data, token, k) for k in self.trusted):
                    break
                if a0 == 2:
                    token = os.urandom(20)
                    self._send(conn, A_AUTH, 1, 0, token)
                elif a0 == 3:
                    key = parse_pubkey(data)
                    self.prompts += 1  # здесь настоящий ТВ показывает «Разрешить отладку?»
                    if not self.accept_keys:
                        conn.close()
                        return
                    self.trusted.append(key)
                    break
            self.connections += 1
            self._send(conn, A_CNXN, 0x01000000, CHUNK, b"device::ro.product.name=tv;\0")
            next_id = 100
            while True:
                cmd, a0, a1, data = self._read(f)
                if cmd != A_OPEN:
                    continue
                local, remote = a0, next_id
                next_id += 1
                service = data.rstrip(b"\0").decode()
                if service == "reboot:":
                    conn.close()
                    return
                self._send(conn, A_OKAY, remote, local)
                kind, _, command = service.partition(":")
                if kind == "exec":
                    stdin = b""
                    size = re.search(r"install-write -S (\d+)", command)
                    while size and len(stdin) < int(size.group(1)):
                        cmd, a0, a1, data = self._read(f)
                        assert (cmd, a0, a1) == (A_WRTE, local, remote), "ждём данные stdin"
                        assert len(data) <= CHUNK, "пакет больше согласованного размера"
                        stdin += data
                        self._send(conn, A_OKAY, remote, local)
                    out = self.tv.exec(command, stdin)
                else:
                    out = self.tv.shell(command).encode()
                for i in range(0, len(out), CHUNK):
                    self._send(conn, A_WRTE, remote, local, out[i:i + CHUNK])
                    cmd, a0, a1, _ = self._read(f)
                    assert (cmd, a0, a1) == (A_OKAY, local, remote), "после WRTE клиент должен ответить OKAY"
                self._send(conn, A_CLSE, remote, local)
                cmd, a0, a1, _ = self._read(f)
                assert (cmd, a0, a1) == (A_CLSE, local, remote), "клиент должен закрыть поток в ответ"
        except EOFError:
            pass
        except Exception as e:  # noqa: BLE001 — любая ошибка протокола должна попасть в тест
            self.errors.append(repr(e))
        finally:
            conn.close()


if __name__ == "__main__":
    # Отдельный запуск: имитация ТВ на порту 5555, как у настоящего adbd (для проверки интерфейса).
    import sys
    import time
    server = FakeAdbd(FakeTv(), port=int(sys.argv[1]) if len(sys.argv) > 1 else 5555)
    print("fake adbd on", server.port, flush=True)
    while True:
        time.sleep(1)
        for e in server.errors:
            print("ERROR", e, flush=True)
        server.errors.clear()
