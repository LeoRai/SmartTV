#!/usr/bin/env python3
"""Ускорение и настройка Android-телевизоров (Яндекс ТВ / Android TV) через ADB.

Ничего не удаляет из системы: приложения только отключаются (pm disable-user)
или им запрещается работать в фоне, и всё возвращается командой restore.
Запуск без аргументов открывает простое меню.
"""

import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(HERE, "state", "disabled.json")
MY_PACKAGES = os.path.join(HERE, "my_packages.txt")
APK_DIR = os.path.join(HERE, "apk")
BUNDLES = (".apkm", ".apks", ".xapk")  # архивы из нескольких APK (split APK)
INSTALLABLE = (".apk",) + BUNDLES
ADB_PORT = 5555
MIN_FREE_MB_FOR_COMPILE = 500

# Пакеты, без которых телевизор может не загрузиться, потерять картинку,
# пульт, HDMI или настройки. Их нельзя отключать без --force.
PROTECTED_PREFIXES = (
    "android",
    "com.android.",
    "com.google.android.gms",
    "com.google.android.gsf",
    "com.google.android.tv.remote",
    "com.mediatek.",
    "com.mstar.",
    "com.droidlogic.",
    "com.amlogic.",
    "com.realtek.",
    "com.hisilicon.",
    "com.rockchip.",
    "com.cvte.",
)

# Приложения, которые пользователь хочет сохранить при любой чистке.
KEEP_KEYWORDS = ("kinopoisk", "byedpi")

ANIM_KEYS = ("window_animation_scale", "transition_animation_scale", "animator_duration_scale")

# Действия с пакетами: off/on — отключить/включить, bg/fg — запретить/разрешить работу в фоне.
ACTION_TEXT = {"off": "отключено", "on": "включено",
               "bg": "работа в фоне запрещена", "fg": "работа в фоне разрешена"}
# Строка в my_packages.txt без '#' — "plain", с префиксом 'bg' — "bg".
FILE_ACTIONS = {"disable": {"plain": "off", "bg": "bg"}, "enable": {"plain": "on", "bg": "fg"}}
DIRECT_ACTIONS = {"disable": "off", "enable": "on", "restrict": "bg", "allow": "fg"}


def find_adb():
    # adb рядом со скриптом (в папке platform-tools) работает без настройки PATH.
    for name in ("adb.exe", "adb"):
        path = os.path.join(HERE, name)
        if os.path.isfile(path):
            return path
    return shutil.which("adb")


ADB = find_adb()


def die(msg):
    print(f"Ошибка: {msg}", file=sys.stderr)
    sys.exit(1)


def adb(*args, serial=None, check=True):
    cmd = [ADB or "adb"]
    if serial:
        cmd += ["-s", serial]
    cmd += list(args)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        die("adb не найден. Установите Android platform-tools (см. README.md).")
    if check and res.returncode != 0:
        die(f"{' '.join(cmd)}\n{res.stderr.strip() or res.stdout.strip()}")
    return res.stdout.strip()


def shell(serial, command, check=True):
    return adb("shell", command, serial=serial, check=check)


def connected_devices():
    lines = adb("devices").splitlines()[1:]
    return [l.split()[0] for l in lines if l.strip().endswith("device")], lines


def pick_device(serial):
    if serial:
        return serial
    devices, lines = connected_devices()
    last_ip = load_state().get("_last_ip")
    if not devices and last_ip:
        adb("connect", last_ip, check=False)
        devices, lines = connected_devices()
    if not devices:
        unauthorized = [l for l in lines if "unauthorized" in l]
        if unauthorized:
            die("телевизор не разрешил подключение. Подтвердите запрос «Разрешить отладку» на экране ТВ.")
        die("телевизор не подключён. Выполните: python tvtool.py connect <IP-адрес ТВ>")
    if len(devices) > 1:
        die(f"подключено несколько устройств: {', '.join(devices)}. Укажите нужное через -s.")
    return devices[0]


_device_keys = {}


def device_key(serial):
    # IP телевизора может смениться, поэтому состояние храним по серийному номеру.
    if serial not in _device_keys:
        sn = shell(serial, "getprop ro.serialno", check=False)
        _device_keys[serial] = sn if sn and sn.lower() not in ("unknown", "0123456789abcdef") else serial
    return _device_keys[serial]


def protection_reason(pkg):
    if any(pkg == p or pkg.startswith(p) for p in PROTECTED_PREFIXES):
        return "системный пакет"
    if any(k in pkg for k in KEEP_KEYWORDS):
        return "нужное вам приложение"
    return None


def is_protected(pkg):
    return protection_reason(pkg) is not None


def home_launcher(serial):
    out = shell(serial, "cmd package resolve-activity --brief "
                        "-a android.intent.action.MAIN -c android.intent.category.HOME", check=False)
    last = out.splitlines()[-1] if out else ""
    return last.split("/")[0] if "/" in last else None


def critical_packages(serial):
    """Пакеты, которые сейчас используются как главный экран, клавиатура, VPN или служба (Projectivy)."""
    setting = lambda name: shell(serial, f"settings get secure {name}", check=False)
    crit = {}
    launcher = home_launcher(serial)
    if launcher:
        crit[launcher] = "текущий лаунчер"
    ime = setting("default_input_method")
    if "/" in ime:
        crit[ime.split("/")[0]] = "клавиатура"
    vpn = setting("always_on_vpn_app")
    if vpn and vpn != "null":
        crit[vpn] = "обход блокировок (VPN)"
    for svc in setting("enabled_accessibility_services").split(":"):
        if "/" in svc:
            crit[svc.split("/")[0]] = "служба спец. возможностей"
    return crit


def list_packages(serial, flag):
    out = shell(serial, f"pm list packages {flag}")
    return sorted(l[len("package:"):] for l in out.splitlines() if l.startswith("package:"))


def meminfo_mb(serial):
    values = {}
    for line in shell(serial, "cat /proc/meminfo", check=False).splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1].isdigit():
            values[parts[0].rstrip(":")] = int(parts[1]) // 1024
    return values


def ram_by_package(serial):
    """Сколько ОЗУ (МБ) занимает каждое запущенное приложение, по данным dumpsys meminfo."""
    usage = {}
    in_section = False
    for line in shell(serial, "dumpsys meminfo", check=False).splitlines():
        if "Total PSS by process" in line:
            in_section = True
            continue
        if in_section:
            m = re.match(r"\s*([\d,]+)K: (\S+)", line)
            if not m:
                break
            pkg = m.group(2).split(":")[0]  # процессы вида pkg:service считаем вместе
            usage[pkg] = usage.get(pkg, 0) + int(m.group(1).replace(",", "")) // 1024
    return usage


def free_data_mb(serial):
    lines = shell(serial, "df -k /data", check=False).splitlines()
    try:
        return int(lines[-1].split()[3]) // 1024
    except (IndexError, ValueError):
        return None


def load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def device_state(state, serial):
    key = device_key(serial)
    entry = state.get(key)
    if entry is None and serial in state:  # первая версия хранила данные по адресу ТВ
        entry = state.pop(serial)
    if isinstance(entry, list):  # ...и только списком отключённых пакетов
        entry = {"disabled": entry}
    entry = entry or {}
    for k in ("disabled", "restricted"):
        entry.setdefault(k, [])
    state[key] = entry
    return entry


def read_list(path):
    """Пакеты из my_packages.txt: [("plain"|"bg", пакет)]. Метки [..] после имени игнорируются."""
    entries = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split("#")[0].split()
            if not parts:
                continue
            if parts[0].lower() == "bg" and len(parts) > 1:
                entries.append(("bg", parts[1]))
            else:
                entries.append(("plain", parts[0]))
    return entries


def set_background(serial, pkg, allowed):
    mode = "default" if allowed else "ignore"
    for op in ("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND"):
        shell(serial, f"cmd appops set {pkg} {op} {mode}", check=False)
    if not allowed:
        shell(serial, f"am force-stop {pkg}", check=False)  # останавливаем то, что уже запущено
    got = shell(serial, f"cmd appops get {pkg} RUN_ANY_IN_BACKGROUND", check=False)
    return ("ignore" in got) != allowed


def apply_actions(serial, actions, force=False):
    state = load_state()
    dev = device_state(state, serial)
    crit = critical_packages(serial) if any(act in ("off", "bg") for act, _ in actions) else {}
    for act, pkg in actions:
        if act in ("off", "bg") and not force:
            reason = crit.get(pkg) or protection_reason(pkg)
            if reason:
                print(f"  пропуск {pkg}: {reason} (защищён, нужен --force)")
                continue
        if act in ("off", "on"):
            verb = "enable" if act == "on" else "disable-user --user 0"
            out = shell(serial, f"pm {verb} {pkg}", check=False)
            ok = "new state" in out
            detail = ACTION_TEXT[act] if ok else (out.splitlines()[-1] if out else "нет ответа")
        else:
            ok = set_background(serial, pkg, allowed=(act == "fg"))
            detail = ACTION_TEXT[act] if ok else "не удалось (пакет не найден или старый Android)"
        print(f"  {'OK  ' if ok else 'FAIL'} {pkg}: {detail}")
        if ok:
            key = "disabled" if act in ("off", "on") else "restricted"
            items = set(dev[key])
            (items.add if act in ("off", "bg") else items.discard)(pkg)
            dev[key] = sorted(items)
    save_state(state)


def user_disabled_packages(serial):
    """Отключённые пользователем (enabled=3). Отключённое производителем не трогаем."""
    return [pkg for pkg in list_packages(serial, "-d")
            if "enabled=3" in shell(serial, f"dumpsys package {pkg} | grep -o 'enabled=[0-9]'", check=False)]


def set_animations(serial, value):
    state = load_state()
    dev = device_state(state, serial)
    if "anim" not in dev:  # заводские значения запоминаем один раз, чтобы вернуть их в restore
        dev["anim"] = {k: shell(serial, f"settings get global {k}", check=False) for k in ANIM_KEYS}
    for k in ANIM_KEYS:
        shell(serial, f"settings put global {k} {value}")
    save_state(state)
    print(f"  скорость анимаций: {value} (1 — заводская, 0 — без анимаций)")


def restore_animations(serial):
    state = load_state()
    original = device_state(state, serial).pop("anim", None) or {}
    for k in ANIM_KEYS:
        v = original.get(k, "null")
        shell(serial, f"settings delete global {k}" if v in ("", "null") else f"settings put global {k} {v}",
              check=False)
    save_state(state)
    print("  анимации возвращены к заводским")


def compile_targets(serial):
    """Приложения, которыми реально пользуются: установленные вами, Кинопоиск и главный экран."""
    restricted = set(device_state(load_state(), serial)["restricted"])
    targets = set(list_packages(serial, "-3 -e"))
    targets |= {p for p in list_packages(serial, "-e") if any(k in p for k in KEEP_KEYWORDS)}
    launcher = home_launcher(serial)
    if launcher and launcher != "android":
        targets.add(launcher)
    return sorted(targets - restricted)


def compile_apps(serial, packages):
    free = free_data_mb(serial)
    if free is not None and free < MIN_FREE_MB_FOR_COMPILE:
        print(f"  компиляция пропущена: на диске свободно всего {free} МБ")
        return
    packages = packages or compile_targets(serial)
    print(f"  полная компиляция {len(packages)} приложений (может занять несколько минут)...")
    for pkg in packages:
        out = shell(serial, f"cmd package compile -m speed -f {pkg}", check=False)
        print(f"  {'OK  ' if 'Success' in out else 'FAIL'} {pkg}")


def boost(serial):
    before = meminfo_mb(serial).get("MemAvailable")
    shell(serial, "am kill-all", check=False)
    time.sleep(2)
    after = meminfo_mb(serial).get("MemAvailable")
    if before is not None and after is not None:
        print(f"  свободно ОЗУ: {before} → {after} МБ")


def reset_resolution(serial):
    shell(serial, "wm size reset")
    shell(serial, "wm density reset")
    state = load_state()
    device_state(state, serial).pop("resolution", None)
    save_state(state)
    print("  разрешение интерфейса возвращено к заводскому")


# ---------- команды ----------

def cmd_connect(a):
    target = a.ip if ":" in a.ip else f"{a.ip}:{ADB_PORT}"
    out = adb("connect", target, check=False)
    print(out)
    if "connected" not in out:
        die("не удалось подключиться. Проверьте IP и что на ТВ включена «Отладка по сети».")
    state = load_state()
    state["_last_ip"] = target  # в следующий раз подключимся сами
    save_state(state)
    print("Если на экране ТВ появился запрос — нажмите «Разрешить» (лучше с галочкой «Всегда»).")


def cmd_info(a):
    s = pick_device(a.serial)
    prop = lambda k: shell(s, f"getprop {k}", check=False)
    print(f"Устройство:   {prop('ro.product.manufacturer')} {prop('ro.product.model')}")
    print(f"Платформа:    {prop('ro.product.board') or prop('ro.board.platform')}")
    print(f"Android:      {prop('ro.build.version.release')} (SDK {prop('ro.build.version.sdk')})")
    print(f"Прошивка:     {prop('ro.build.display.id')}")
    print(f"Лаунчер:      {home_launcher(s) or 'не определён'}")

    mem = meminfo_mb(s)
    total, avail = mem.get("MemTotal"), mem.get("MemAvailable", mem.get("MemFree"))
    low_ram = " (система в режиме low_ram)" if prop("ro.config.low_ram") == "true" else ""
    print(f"ОЗУ:          всего {total} МБ, свободно {avail} МБ{low_ram}")
    free = free_data_mb(s)
    print(f"Диск:         свободно {free if free is not None else '?'} МБ")
    last_line = lambda cmd: (shell(s, cmd, check=False).splitlines() or [""])[-1]
    size = re.search(r"(\d+)x(\d+)", last_line("wm size"))  # последняя строка — действующий размер
    density = re.search(r"(\d+)\s*$", last_line("wm density"))
    print(f"Интерфейс:    {size.group(0) if size else '?'}, плотность {density.group(1) if density else '?'}")
    try:
        uptime_h = float(shell(s, "cat /proc/uptime", check=False).split()[0]) / 3600
    except (IndexError, ValueError):
        uptime_h = 0
    print(f"Работает без перезагрузки: {uptime_h:.0f} ч")

    usage = sorted(ram_by_package(s).items(), key=lambda kv: -kv[1])[:10]
    if usage:
        print("\nБольше всего ОЗУ занимают:")
        for pkg, mb in usage:
            print(f"  {mb:>5} МБ  {pkg}")

    dev = device_state(load_state(), s)
    print(f"\nИзменено этим скриптом: отключено {len(dev['disabled'])}, "
          f"запрещён фон у {len(dev['restricted'])}")

    try:
        anim_fast = float(shell(s, "settings get global animator_duration_scale", check=False)) < 1
    except ValueError:
        anim_fast = False
    tips = []
    if free is not None and free < 1024:
        tips.append("Мало места на диске — это сильно тормозит ТВ. Удалите ненужное и запустите speedup.")
    if total and total <= 1600:
        tips.append("Мало ОЗУ: отключите или запретите фон (bg) тяжёлым приложениям из списка выше.")
    if not anim_fast:
        tips.append("Анимации не ускорены: python tvtool.py speedup --max")
    if uptime_h > 72:
        tips.append("ТВ давно не перезагружался: python tvtool.py reboot")
    if size and int(size.group(2)) > 720 and "resolution" not in dev:
        tips.append("Можно понизить разрешение интерфейса: python tvtool.py resolution 720 (эксперимент)")
    if tips:
        print("\nСоветы:")
        for tip in tips:
            print(f"  • {tip}")


def cmd_scan(a):
    s = pick_device(a.serial)
    enabled = list_packages(s, "-e")
    system = set(list_packages(s, "-s"))
    crit = critical_packages(s)
    usage = ram_by_package(s)
    dev = device_state(load_state(), s)
    path = a.output or MY_PACKAGES
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# Включённые приложения ТВ ({s}), снято {now}\n")
        f.write("# Сверху — те, что сейчас занимают больше всего памяти.\n#\n")
        f.write("#   уберите '#' в начале строки   -> приложение будет ОТКЛЮЧЕНО;\n")
        f.write("#   замените '#' на 'bg'          -> приложение останется, но не будет работать в фоне;\n")
        f.write("#   строку без изменений          -> ничего не меняется.\n")
        f.write("# Затем выполните: python tvtool.py apply  (или пункт меню «Применить my_packages.txt»)\n")
        f.write("# Строки с [ЗАЩИЩЁН] трогать не нужно: без них пропадёт картинка, пульт, HDMI и т. п.\n\n")
        for pkg in sorted(enabled, key=lambda p: (-usage.get(p, 0), p)):
            tags = ["системный" if pkg in system else "пользовательский"]
            if usage.get(pkg):
                tags.append(f"{usage[pkg]} МБ ОЗУ")
            if pkg in crit:
                tags.append(f"ЗАЩИЩЁН: {crit[pkg]}")
            elif is_protected(pkg):
                tags.append("ЗАЩИЩЁН")
            prefix = "bg" if pkg in dev["restricted"] else "#"
            f.write(f"{prefix} {pkg:<58} [{', '.join(tags)}]\n")
        if dev["disabled"]:
            f.write("\n# Уже отключены этим скриптом (вернуть: python tvtool.py enable <пакет>):\n")
            for pkg in dev["disabled"]:
                f.write(f"#   {pkg}\n")
    print(f"Найдено {len(enabled)} включённых пакетов. Список сохранён в {path}")


def cmd_packages(a):
    s = pick_device(a.serial)
    if a.file:
        if not os.path.isfile(a.file):
            die(f"файл {a.file} не найден. Сначала выполните: python tvtool.py scan")
        mapping = FILE_ACTIONS["enable" if a.cmd == "enable" else "disable"]
        actions = [(mapping[kind], pkg) for kind, pkg in read_list(a.file)]
    else:
        actions = [(DIRECT_ACTIONS[a.cmd], pkg) for pkg in a.packages]
    if not actions:
        die("не указано ни одного пакета.")
    apply_actions(s, actions, a.force)


def cmd_restore(a):
    s = pick_device(a.serial)
    dev = device_state(load_state(), s)
    # Подстраховка: если файл состояния потерян, включаем всё, что отключено пользователем.
    disabled = dev["disabled"] or user_disabled_packages(s)
    actions = [("on", p) for p in disabled] + [("fg", p) for p in dev["restricted"]]
    if actions:
        apply_actions(s, actions)
    else:
        print("  отключённых и ограниченных приложений нет")
    restore_animations(s)
    if dev.get("resolution"):
        reset_resolution(s)
    print("Готово. Перезагрузите ТВ: python tvtool.py reboot")


def cmd_speedup(a):
    s = pick_device(a.serial)
    if a.undo:
        restore_animations(s)
        return
    set_animations(s, "0" if a.no_anim or a.max else "0.5")
    print("  очистка кэша приложений...")
    shell(s, "pm trim-caches 999G", check=False)
    print("  фоновая оптимизация приложений (может занять несколько минут)...")
    shell(s, "cmd package bg-dexopt-job", check=False)
    if a.max:
        compile_apps(s, [])
        boost(s)
    print("Готово. Перезагрузите ТВ: python tvtool.py reboot")


def cmd_compile(a):
    compile_apps(pick_device(a.serial), a.packages)


def cmd_boost(a):
    boost(pick_device(a.serial))


def cmd_resolution(a):
    s = pick_device(a.serial)
    if a.mode == "reset":
        reset_resolution(s)
        return
    size = re.search(r"Physical size: (\d+)x(\d+)", shell(s, "wm size"))
    dens = re.search(r"Physical density: (\d+)", shell(s, "wm density"))
    if not size or not dens:
        die("не удалось узнать разрешение экрана.")
    w, h, d = int(size.group(1)), int(size.group(2)), int(dens.group(1))
    if h <= 720:
        print(f"Интерфейс уже работает в {w}x{h}, понижать нечего.")
        return
    # Меняем размер и плотность в одной пропорции, чтобы всё осталось того же размера.
    new_w, new_d = round(w * 720 / h / 2) * 2, round(d * 720 / h)
    shell(s, f"wm size {new_w}x720")
    shell(s, f"wm density {new_d}")
    state = load_state()
    device_state(state, s)["resolution"] = f"{new_w}x720, плотность {new_d}"
    save_state(state)
    print(f"Интерфейс: {w}x{h} → {new_w}x720. Видео по-прежнему выводится в полном разрешении.")
    print("Проверьте меню, приложения, HDMI и антенну. Если что-то не так: python tvtool.py resolution reset")


def cmd_install(a):
    s = pick_device(a.serial)
    if not a.apks:
        os.makedirs(APK_DIR, exist_ok=True)
    apks = []
    for path in a.apks or [APK_DIR]:
        apks += sorted(f for f in glob.glob(os.path.join(path, "*")) if f.lower().endswith(INSTALLABLE)
                       ) if os.path.isdir(path) else [path]
    if not apks:
        die(f"APK-файлы не найдены. Положите их в папку {APK_DIR}")
    for apk in apks:
        if not os.path.isfile(apk):
            print(f"  FAIL {apk}: файл не найден")
            continue
        if apk.lower().endswith(BUNDLES):
            out = install_bundle(s, apk)
        else:
            out = adb("install", "-r", apk, serial=s, check=False)
        print(f"  {'OK  ' if 'Success' in out else 'FAIL'} {os.path.basename(apk)}: {out.splitlines()[-1] if out else ''}")


def install_bundle(serial, path):
    """Архив из нескольких APK (.apkm с APKMirror, .apks, .xapk) ставим как adb install-multiple."""
    abis = {x.strip().replace("-", "_") for x in shell(serial, "getprop ro.product.cpu.abilist", check=False).split(",")}
    known = ("arm64_v8a", "armeabi_v7a", "armeabi", "x86_64", "x86")
    with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(path) as z:
        parts = []
        for name in z.namelist():
            base = os.path.basename(name)
            abi = next((k for k in known if f"config.{k}." in base or base == f"{k}.apk"), None)
            if not base.endswith(".apk") or (abi and "" not in abis and abi not in abis):
                continue  # части для чужого процессора ТВ не нужны
            target = os.path.join(tmp, f"{len(parts)}_{base}")
            with open(target, "wb") as f:
                f.write(z.read(name))
            parts.append(target)
        if not parts:
            return "в архиве нет APK (файл повреждён или зашифрован)"
        return adb("install-multiple", "-r", *parts, serial=serial, check=False)


def cmd_vpn(a):
    s = pick_device(a.serial)
    if a.off:
        shell(s, "settings delete secure always_on_vpn_app", check=False)
        print("Автозапуск VPN отключён.")
        return
    pkg = a.package
    if not pkg:
        found = [p for p in list_packages(s, "-e") if "byedpi" in p.lower()]
        if len(found) != 1:
            die("укажите пакет VPN-приложения явно" if found else
                "ByeDPI не найден. Установите APK: python tvtool.py install ByeByeDPI.apk")
        pkg = found[0]
    shell(s, f"settings put secure always_on_vpn_app {pkg}")
    # Без lockdown: если обход упадёт, интернет не пропадёт полностью.
    shell(s, "settings put secure always_on_vpn_lockdown 0", check=False)
    print(f"{pkg} будет запускаться вместе с телевизором.")
    print("Один раз откройте приложение на ТВ, нажмите «Подключить» и разрешите VPN-запрос.")


def find_package(serial, *keywords):
    return next((p for p in list_packages(serial, "-e") if any(k in p.lower() for k in keywords)), None)


def launch(serial, pkg):
    for category in ("LEANBACK_LAUNCHER", "LAUNCHER"):
        out = shell(serial, f"monkey -p {pkg} -c android.intent.category.{category} 1", check=False)
        if "Events injected: 1" in out:
            return True
    print(f"  не удалось открыть {pkg} — запустите его из списка приложений на ТВ")
    return False


def gamepads(serial):
    """Подключённые геймпады по данным dumpsys input (источник GAMEPAD или JOYSTICK)."""
    result, device = [], None
    for line in shell(serial, "dumpsys input", check=False).splitlines():
        m = re.match(r"\s*Device -?\d+: (.+)$", line)
        if m:
            device = m.group(1).strip()
            continue
        m = re.match(r"\s*Sources: 0x([0-9a-fA-F]+)", line)
        if device and m:
            sources = int(m.group(1), 16)
            if sources & 0x401 == 0x401 or sources & 0x01000010 == 0x01000010:
                result.append(device)
            device = None
    return result


def network_report(serial):
    if shell(serial, "cat /sys/class/net/eth0/operstate 2>/dev/null", check=False) == "up":
        return "Сеть: кабель — лучший вариант для игр."
    wifi = shell(serial, "dumpsys wifi | grep -m 1 mWifiInfo", check=False)
    freq, rssi = re.search(r"Frequency: (\d+)MHz", wifi), re.search(r"RSSI: (-?\d+)", wifi)
    if not freq:
        return "Сеть: не удалось определить. Для игр лучше кабель или Wi-Fi 5 ГГц."
    weak = " Сигнал слабый — поставьте роутер ближе или подключите кабель." if rssi and int(rssi.group(1)) < -70 else ""
    return ("Сеть: Wi-Fi 5 ГГц — подходит для игр." if int(freq.group(1)) >= 4900
            else "Сеть: Wi-Fi 2,4 ГГц — возможны рывки. Подключите ТВ к сети 5 ГГц или кабелем.") + weak


def cmd_game(a):
    s = pick_device(a.serial)
    state = load_state()
    dev = device_state(state, s)
    if a.off:
        vpn = dev.pop("game_vpn", None)
        save_state(state)
        if not vpn:
            print("Обход блокировок не приостанавливался — возвращать нечего.")
            return
        print("Открываю ByeByeDPI: нажмите на ТВ «Подключить». Или перезагрузите ТВ — обход включится сам.")
        launch(s, vpn)
        return

    moonlight = find_package(s, "limelight", "moonlight")
    if not moonlight:
        die("Moonlight не установлен. Положите его APK в папку apk и выполните: python tvtool.py install")
    pads = gamepads(s)
    print(f"Геймпад: {', '.join(pads)}" if pads else
          "Геймпад не найден: подключите его в Настройки → Пульты и аксессуары или кабелем в USB.")
    print(network_report(s))

    # VPN пропускает через себя и домашнюю сеть, из-за этого стрим тормозит или не идёт совсем.
    vpn = find_package(s, "byedpi")
    if vpn and shell(s, f"pidof {vpn}", check=False):
        shell(s, f"am force-stop {vpn}", check=False)
        dev["game_vpn"] = vpn
        save_state(state)
        print("Обход блокировок приостановлен на время игры. Вернуть: python tvtool.py game --off")

    crit = critical_packages(s)
    third_party = set(list_packages(s, "-3"))
    before = meminfo_mb(s).get("MemAvailable")
    closed = [p for p in ram_by_package(s) if p in third_party and p not in (moonlight, vpn) and p not in crit]
    for pkg in closed:
        shell(s, f"am force-stop {pkg}", check=False)
    shell(s, "am kill-all", check=False)
    time.sleep(2)
    after = meminfo_mb(s).get("MemAvailable")
    print(f"Закрыто приложений: {len(closed)}" + (f" ({', '.join(closed)})" if closed else ""))
    if before is not None and after is not None:
        print(f"Свободно ОЗУ: {before} → {after} МБ")
    print("Совет: в настройках изображения ТВ выберите режим «Игра» — он убирает обработку картинки и задержку.")
    print("В Moonlight: 1080p, 60 FPS, битрейт 15–20 Мбит/с, кодек H.264 (если всё плавно — можно HEVC).")
    print("Запускаю Moonlight...")
    launch(s, moonlight)


def cmd_reboot(a):
    adb("reboot", serial=pick_device(a.serial))
    print("Телевизор перезагружается.")


def main(argv=None):
    p = argparse.ArgumentParser(description="Ускорение Android-телевизора через ADB (безопасно, обратимо).",
                                epilog="Без аргументов открывается меню.")
    p.add_argument("-s", "--serial", help="адрес устройства, если подключено несколько")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("connect", help="подключиться к ТВ по Wi-Fi/LAN")
    c.add_argument("ip")
    c.set_defaults(func=cmd_connect)

    sub.add_parser("info", help="диагностика: память, диск, что занимает ОЗУ, советы").set_defaults(func=cmd_info)

    c = sub.add_parser("scan", help="сохранить список приложений в my_packages.txt для разметки")
    c.add_argument("-o", "--output")
    c.set_defaults(func=cmd_scan)

    c = sub.add_parser("apply", help="применить разметку из my_packages.txt")
    c.add_argument("file", nargs="?", default=MY_PACKAGES)
    c.add_argument("--force", action="store_true", help="разрешить защищённые пакеты (опасно)")
    c.set_defaults(func=cmd_packages, packages=[])

    for name, help_text in (("disable", "отключить приложения"), ("enable", "включить приложения"),
                            ("restrict", "запретить приложениям работать в фоне"),
                            ("allow", "снова разрешить приложениям работать в фоне")):
        c = sub.add_parser(name, help=help_text)
        c.add_argument("packages", nargs="*")
        if name in ("disable", "enable"):
            c.add_argument("-f", "--file", help="файл со списком пакетов (как после scan)")
        if name in ("disable", "restrict"):
            c.add_argument("--force", action="store_true", help="разрешить защищённые пакеты (опасно)")
        c.set_defaults(func=cmd_packages, file=None, force=False)

    sub.add_parser("restore", help="вернуть всё как было: приложения, фон, анимации, разрешение"
                   ).set_defaults(func=cmd_restore)

    c = sub.add_parser("speedup", help="ускорить анимации, очистить кэш, оптимизировать приложения")
    c.add_argument("--max", action="store_true",
                   help="максимум: без анимаций, полная компиляция приложений, очистка ОЗУ")
    c.add_argument("--no-anim", action="store_true", help="полностью выключить анимации")
    c.add_argument("--undo", action="store_true", help="вернуть заводские анимации")
    c.set_defaults(func=cmd_speedup)

    c = sub.add_parser("compile", help="полностью скомпилировать приложения для быстрого запуска")
    c.add_argument("packages", nargs="*", help="по умолчанию: ваши приложения, Кинопоиск, главный экран")
    c.set_defaults(func=cmd_compile)

    sub.add_parser("boost", help="освободить ОЗУ перед просмотром").set_defaults(func=cmd_boost)

    c = sub.add_parser("resolution", help="понизить разрешение интерфейса до 720p (эксперимент)")
    c.add_argument("mode", choices=["720", "reset"])
    c.set_defaults(func=cmd_resolution)

    c = sub.add_parser("install", help="установить APK-файлы (по умолчанию все из папки apk)")
    c.add_argument("apks", nargs="*")
    c.set_defaults(func=cmd_install)

    c = sub.add_parser("vpn", help="запускать обход блокировок (ByeDPI) при включении ТВ")
    c.add_argument("package", nargs="?", help="пакет VPN-приложения (по умолчанию ищется ByeDPI)")
    c.add_argument("--off", action="store_true", help="убрать автозапуск")
    c.set_defaults(func=cmd_vpn)

    c = sub.add_parser("game", help="игровой режим: подготовить ТВ и запустить Moonlight")
    c.add_argument("--off", action="store_true", help="выйти из игрового режима (вернуть обход блокировок)")
    c.set_defaults(func=cmd_game)

    sub.add_parser("reboot", help="перезагрузить ТВ").set_defaults(func=cmd_reboot)

    a = p.parse_args(argv)
    a.func(a)


MENU = (
    ("Подключиться к телевизору", None),
    ("Диагностика: память, диск, что тормозит", ["info"]),
    ("Быстрое ускорение (безопасно)", ["speedup"]),
    ("Максимальное ускорение", ["speedup", "--max"]),
    ("Создать список приложений (my_packages.txt)", ["scan"]),
    ("Применить my_packages.txt", ["apply"]),
    ("Освободить память перед просмотром", ["boost"]),
    ("Установить все APK из папки apk", ["install"]),
    ("Перезагрузить телевизор", ["reboot"]),
    ("Вернуть всё как было", ["restore"]),
    ("Игровой режим (Moonlight)", ["game"]),
    ("Выйти из игрового режима", ["game", "--off"]),
)


def menu():
    while True:
        print("\n=== Ускорение телевизора ===")
        for i, (title, _) in enumerate(MENU, 1):
            print(f"  {i:>2}. {title}")
        print("   0. Выход")
        choice = input("Выберите пункт: ").strip()
        if choice == "0":
            return
        if not choice.isdigit() or not 1 <= int(choice) <= len(MENU):
            continue
        args = MENU[int(choice) - 1][1]
        if args is None:
            ip = input("IP-адрес ТВ (Настройки → Об устройстве → Статус): ").strip()
            if not ip:
                continue
            args = ["connect", ip]
        try:
            main(args)
        except SystemExit:  # ошибка уже напечатана, возвращаемся в меню
            pass


if __name__ == "__main__":
    try:
        main() if len(sys.argv) > 1 else menu()
    except KeyboardInterrupt:
        print()
