#!/usr/bin/env python3
"""Сборка TVTuner.apk без Android SDK: нужны только JDK (javac, jarsigner, keytool) и Python 3.

Шаги: javac (против API Android 9 из Maven Central) → dx → двоичные AndroidManifest.xml
и resources.arsc (пишем сами, без aapt2) → zip → подпись jarsigner (схема v1).
"""

import hashlib
import os
import shutil
import struct
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".cache")
BUILD = os.path.join(HERE, "build")
OUT = os.path.join(ROOT, "dist", "TVTuner.apk")
KEYSTORE = os.path.join(HERE, "keystore", "tvtuner.p12")
KEY_ALIAS, KEY_PASS = "tvtuner", "tvtuner"  # ключ нужен только чтобы обновления ставились поверх

MAVEN = "https://repo1.maven.org/maven2/"
DEPS = {
    # API Android 9 для компиляции (в APK не попадает).
    "android-all.jar": ("org/robolectric/android-all/9-robolectric-4913185-2/android-all-9-robolectric-4913185-2.jar",
                        "cf4aed5e458deb48ddc0ca92fc25156e6f478d9d5c1d948cdd1817a67ee11b32"),
    # dx — компилятор байткода Java в DEX.
    "dx.jar": ("com/jakewharton/android/repackaged/dalvik-dx/14.0.0_r21/dalvik-dx-14.0.0_r21.jar",
               "9b13bc80bf86f193f8de9c959f52a8ff83fc85a1cc552f5126f1140da9b85a36"),
}

ANDROID_NS = "http://schemas.android.com/apk/res/android"
PACKAGE_ID = 0x7f
# Атрибуты манифеста: имя -> (ID ресурса из android.R.attr, тип значения).
ATTRS = {
    "theme": (0x01010000, "ref"),
    "label": (0x01010001, "string"),
    "icon": (0x01010002, "ref"),
    "name": (0x01010003, "string"),
    "exported": (0x01010010, "bool"),
    "configChanges": (0x0101001f, "flags"),
    "minSdkVersion": (0x0101020c, "int"),
    "versionCode": (0x0101021b, "int"),
    "versionName": (0x0101021c, "string"),
    "targetSdkVersion": (0x01010270, "int"),
    "required": (0x0101028e, "bool"),
    "banner": (0x010103f2, "ref"),
}
FRAMEWORK_REFS = {"@android:style/Theme.DeviceDefault.NoActionBar": 0x01030129}
CONFIG_FLAGS = {"keyboard": 0x10, "keyboardHidden": 0x20, "navigation": 0x40, "orientation": 0x80,
                "screenLayout": 0x100, "uiMode": 0x200, "screenSize": 0x400, "smallestScreenSize": 0x800,
                "density": 0x1000}

# Типы значений Res_value.
TYPE_REFERENCE, TYPE_STRING, TYPE_INT_DEC, TYPE_INT_HEX, TYPE_INT_BOOLEAN = 0x01, 0x03, 0x10, 0x11, 0x12
NO_INDEX = 0xffffffff


def fetch(name):
    path, sha = DEPS[name]
    dest = os.path.join(CACHE, name)
    if not os.path.isfile(dest):
        os.makedirs(CACHE, exist_ok=True)
        for delay in (0, 5, 15, 30, 60):  # Maven Central иногда отвечает 429
            time.sleep(delay)
            try:
                print(f"скачиваю {name}...")
                urllib.request.urlretrieve(MAVEN + path, dest + ".part")
                break
            except OSError as e:
                print(f"  не получилось ({e}), повтор")
        else:
            sys.exit(f"не удалось скачать {name}")
        os.replace(dest + ".part", dest)
    with open(dest, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != sha:
            os.remove(dest)
            sys.exit(f"{name}: контрольная сумма не совпала, файл удалён")
    return dest


def run(*cmd):
    env = dict(os.environ, JAVA_TOOL_OPTIONS="")
    res = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if res.returncode != 0:
        sys.exit(f"{' '.join(cmd[:2])}...\n{res.stdout}{res.stderr}")


# ---------- двоичные форматы Android (ResChunk) ----------

def chunk(type_, header, body):
    """ResChunk_header + остаток заголовка + тело."""
    return struct.pack("<HHI", type_, 8 + len(header), 8 + len(header) + len(body)) + header + body


def string_pool(strings):
    """ResStringPool в UTF-16."""
    offsets, data = b"", b""
    for s in strings:
        encoded = s.encode("utf-16-le")
        length = len(encoded) // 2
        if length > 0x7fff:
            raise ValueError("слишком длинная строка")
        offsets += struct.pack("<I", len(data))
        data += struct.pack("<H", length) + encoded + b"\0\0"
    data += b"\0" * (-len(data) % 4)
    header = struct.pack("<IIIII", len(strings), 0, 0, 28 + len(offsets), 0)
    return chunk(0x0001, header, offsets + data)


class Strings:
    def __init__(self, first=()):
        self.items = list(first)

    def __call__(self, s):
        if s not in self.items:
            self.items.append(s)
        return self.items.index(s)


def binary_manifest(source, resources):
    tree = ET.parse(source)
    nodes = []

    def walk(el):
        nodes.append(el)
        for child in el:
            walk(child)

    walk(tree.getroot())
    # Сначала имена атрибутов с ID ресурса: их индексы должны совпадать с картой ресурсов.
    used = sorted({k.split("}")[1] for el in nodes for k in el.attrib if k.startswith("{")},
                  key=lambda n: ATTRS[n][0])
    pool = Strings(used)
    pool("android")
    pool(ANDROID_NS)

    def value(attr, raw):
        if attr is None:
            return pool(raw), TYPE_STRING, pool(raw)
        kind = ATTRS[attr][1]
        if kind == "string":
            return pool(raw), TYPE_STRING, pool(raw)
        if kind == "int":
            return NO_INDEX, TYPE_INT_DEC, int(raw)
        if kind == "bool":
            return NO_INDEX, TYPE_INT_BOOLEAN, 0xffffffff if raw == "true" else 0
        if kind == "flags":
            return NO_INDEX, TYPE_INT_HEX, sum(CONFIG_FLAGS[f] for f in raw.split("|"))
        if raw in FRAMEWORK_REFS:
            return NO_INDEX, TYPE_REFERENCE, FRAMEWORK_REFS[raw]
        return NO_INDEX, TYPE_REFERENCE, resources[raw]

    package = tree.getroot().get("package")
    body = b""
    line = 1
    ns_node = struct.pack("<II", line, NO_INDEX) + struct.pack("<II", pool("android"), pool(ANDROID_NS))

    def element(el, depth):
        nonlocal body, line
        attrs = []
        for key, raw in el.attrib.items():
            if key.startswith("{"):
                name = key.split("}")[1]
                if name == "name" and el.tag == "activity" and raw.startswith("."):
                    raw = package + raw
                ident = ATTRS[name][0]
                attrs.append((ident, pool(ANDROID_NS), pool(name), value(name, raw)))
            else:
                attrs.append((0, NO_INDEX, pool(key), value(None, raw)))
        attrs.sort(key=lambda a: a[0])  # Android ищет атрибуты по возрастанию ID ресурса
        attr_bytes = b"".join(struct.pack("<IIIHBBI", ns, name, rv[0], 8, 0, rv[1], rv[2])
                              for _, ns, name, rv in attrs)
        line += 1
        ext = struct.pack("<IIHHHHHH", NO_INDEX, pool(el.tag), 20, 20, len(attrs), 0, 0, 0)
        body += chunk(0x0102, struct.pack("<II", line, NO_INDEX), ext + attr_bytes)
        for child in el:
            element(child, depth + 1)
        body += chunk(0x0103, struct.pack("<II", line, NO_INDEX), struct.pack("<II", NO_INDEX, pool(el.tag)))

    element(tree.getroot(), 0)
    body = chunk(0x0100, ns_node[:8], ns_node[8:]) + body + chunk(0x0101, ns_node[:8], ns_node[8:])
    res_map = chunk(0x0180, b"", b"".join(struct.pack("<I", ATTRS[n][0]) for n in used))
    return chunk(0x0003, b"", string_pool(pool.items) + res_map + body)


def resource_table(package, drawables):
    """resources.arsc с одним типом drawable. drawables — отсортированные имена файлов без .png."""
    paths = [f"res/drawable/{d}.png" for d in drawables]
    type_pool = string_pool(["drawable"])
    key_pool = string_pool(drawables)
    name = package.encode("utf-16-le").ljust(256, b"\0")
    pkg_header = struct.pack("<I", PACKAGE_ID) + name + struct.pack(
        "<IIIII", 288, 1, 288 + len(type_pool), len(drawables), 0)
    count = len(drawables)
    spec = chunk(0x0202, struct.pack("<BBHI", 1, 0, 0, count), b"\0" * 4 * count)
    config = struct.pack("<I", 64) + b"\0" * 60
    entries = b"".join(struct.pack("<HHI", 8, 0, i) + struct.pack("<HBBI", 8, 0, TYPE_STRING, i)
                       for i in range(count))
    offsets = b"".join(struct.pack("<I", 16 * i) for i in range(count))
    type_header = struct.pack("<BBHII", 1, 0, 0, count, 8 + 12 + 64 + len(offsets)) + config
    type_chunk = chunk(0x0201, type_header, offsets + entries)
    package_chunk = chunk(0x0200, pkg_header, type_pool + key_pool + spec + type_chunk)
    return chunk(0x0002, struct.pack("<I", 1), string_pool(paths) + package_chunk)


# ---------- сборка ----------

def main():
    android_all, dx = fetch("android-all.jar"), fetch("dx.jar")
    shutil.rmtree(BUILD, ignore_errors=True)
    classes = os.path.join(BUILD, "classes")
    os.makedirs(classes)
    sources = [os.path.join(dp, f) for dp, _, files in os.walk(os.path.join(HERE, "src")) for f in files
               if f.endswith(".java")]
    print("компиляция Java...")
    run("javac", "--release", "8", "-encoding", "UTF-8", "-Xlint:all,-options", "-Werror",
        "-cp", android_all, "-d", classes, *sources)
    print("перевод в DEX...")
    dex = os.path.join(BUILD, "classes.dex")
    run("java", "-cp", dx, "com.android.dx.command.Main", "--dex", "--min-sdk-version=26",
        f"--output={dex}", classes)

    package = ET.parse(os.path.join(HERE, "AndroidManifest.xml")).getroot().get("package")
    drawables = sorted(f[:-4] for f in os.listdir(os.path.join(HERE, "res", "drawable")) if f.endswith(".png"))
    resources = {f"@drawable/{d}": (PACKAGE_ID << 24) | (1 << 16) | i for i, d in enumerate(drawables)}
    manifest = binary_manifest(os.path.join(HERE, "AndroidManifest.xml"), resources)
    arsc = resource_table(package, drawables)

    unsigned = os.path.join(BUILD, "unsigned.apk")
    stamp = (2024, 1, 1, 0, 0, 0)

    def add(z, name, data, compress):
        info = zipfile.ZipInfo(name, stamp)
        info.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
        z.writestr(info, data)

    with zipfile.ZipFile(unsigned, "w") as z:
        add(z, "AndroidManifest.xml", manifest, True)
        with open(dex, "rb") as f:
            add(z, "classes.dex", f.read(), True)
        add(z, "resources.arsc", arsc, False)
        for d in drawables:
            with open(os.path.join(HERE, "res", "drawable", d + ".png"), "rb") as f:
                add(z, f"res/drawable/{d}.png", f.read(), False)

    if not os.path.isfile(KEYSTORE):
        os.makedirs(os.path.dirname(KEYSTORE), exist_ok=True)
        run("keytool", "-genkeypair", "-keystore", KEYSTORE, "-storetype", "PKCS12", "-alias", KEY_ALIAS,
            "-storepass", KEY_PASS, "-keypass", KEY_PASS, "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "36500", "-dname", "CN=TV Tuner")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    print("подпись...")
    run("jarsigner", "-keystore", KEYSTORE, "-storetype", "PKCS12", "-storepass", KEY_PASS,
        "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256", "-signedjar", OUT, unsigned, KEY_ALIAS)
    print(f"готово: {OUT} ({os.path.getsize(OUT) // 1024} КБ)")


if __name__ == "__main__":
    main()
