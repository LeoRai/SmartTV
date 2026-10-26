#!/usr/bin/env python3
"""Ускорение и настройка Android-телевизоров (Novex на Яндекс ТВ / Android TV) через ADB.

Ничего не удаляет из системы: приложения только отключаются (pm disable-user)
и в любой момент возвращаются командой restore.
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(HERE, "state", "disabled.json")
ADB_PORT = 5555

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

SPEED_SETTINGS = {
    "window_animation_scale": "0.5",
    "transition_animation_scale": "0.5",
    "animator_duration_scale": "0.5",
}


def die(msg):
    print(f"Ошибка: {msg}", file=sys.stderr)
    sys.exit(1)


def adb(*args, serial=None, check=True):
    cmd = ["adb"]
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


def pick_device(serial):
    if serial:
        return serial
    lines = adb("devices").splitlines()[1:]
    devices = [l.split()[0] for l in lines if l.strip().endswith("device")]
    if not devices:
        unauthorized = [l for l in lines if "unauthorized" in l]
        if unauthorized:
            die("телевизор не разрешил подключение. Подтвердите запрос «Разрешить отладку» на экране ТВ.")
        die("телевизор не подключён. Выполните: python tvtool.py connect <IP-адрес ТВ>")
    if len(devices) > 1:
        die(f"подключено несколько устройств: {', '.join(devices)}. Укажите нужное через -s.")
    return devices[0]


# Приложения, которые пользователь хочет сохранить при любой чистке.
KEEP_KEYWORDS = ("kinopoisk",)


def is_protected(pkg):
    return (any(pkg == p or pkg.startswith(p) for p in PROTECTED_PREFIXES)
            or any(k in pkg for k in KEEP_KEYWORDS))


def home_launcher(serial):
    out = shell(serial, "cmd package resolve-activity --brief "
                        "-a android.intent.action.MAIN -c android.intent.category.HOME", check=False)
    last = out.splitlines()[-1] if out else ""
    return last.split("/")[0] if "/" in last else None


def list_packages(serial, flag):
    out = shell(serial, f"pm list packages {flag}")
    return sorted(l[len("package:"):] for l in out.splitlines() if l.startswith("package:"))


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


def read_list(path):
    with open(path, encoding="utf-8") as f:
        # Берём только имя пакета: метки вида [системный] после него игнорируются.
        return [l.split("#")[0].split()[0] for l in f if l.split("#")[0].strip()]


# ---------- команды ----------

def cmd_connect(a):
    target = a.ip if ":" in a.ip else f"{a.ip}:{ADB_PORT}"
    out = adb("connect", target, check=False)
    print(out)
    if "connected" not in out:
        die("не удалось подключиться. Проверьте IP и что на ТВ включена «Отладка по сети».")
    print("Если на экране ТВ появился запрос — нажмите «Разрешить» (лучше с галочкой «Всегда»).")


def cmd_info(a):
    s = pick_device(a.serial)
    prop = lambda k: shell(s, f"getprop {k}", check=False)
    print(f"Устройство:   {prop('ro.product.manufacturer')} {prop('ro.product.model')}")
    print(f"Платформа:    {prop('ro.product.board') or prop('ro.board.platform')}")
    print(f"Android:      {prop('ro.build.version.release')} (SDK {prop('ro.build.version.sdk')})")
    print(f"Прошивка:     {prop('ro.build.display.id')}")
    print(f"Лаунчер:      {home_launcher(s) or 'не определён'}")
    mem = shell(s, "cat /proc/meminfo", check=False).splitlines()[:3]
    print("Память:       " + "; ".join(" ".join(m.split()) for m in mem))
    print("Хранилище /data:")
    print(shell(s, "df -h /data", check=False))
    print(f"Отключено этим скриптом: {len(load_state().get(s, []))} пакетов")


def cmd_scan(a):
    s = pick_device(a.serial)
    enabled = list_packages(s, "-e")
    system = set(list_packages(s, "-s"))
    launcher = home_launcher(s)
    path = a.output or os.path.join(HERE, "my_packages.txt")
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# Включённые приложения ТВ ({s}), снято {now}\n")
        f.write("# Чтобы ОТКЛЮЧИТЬ приложение, уберите '#' в начале его строки,\n")
        f.write("# затем выполните: python tvtool.py disable -f my_packages.txt\n")
        f.write("# Строки с [ЗАЩИЩЁН] трогать не нужно: это система, картинка, пульт, HDMI.\n\n")
        for pkg in enabled:
            tags = []
            if pkg in system:
                tags.append("системный")
            if pkg == launcher:
                tags.append("ТЕКУЩИЙ ЛАУНЧЕР")
            if is_protected(pkg):
                tags.append("ЗАЩИЩЁН")
            f.write(f"# {pkg:<60} [{', '.join(tags) or 'пользовательский'}]\n")
    print(f"Найдено {len(enabled)} включённых пакетов. Список сохранён в {path}")


def change_packages(a, enable):
    s = pick_device(a.serial)
    pkgs = read_list(a.file) if a.file else a.packages
    if not pkgs:
        die("не указано ни одного пакета.")
    launcher = home_launcher(s)
    state = load_state()
    done = set(state.get(s, []))
    for pkg in pkgs:
        if not enable:
            if pkg == launcher and not a.force:
                print(f"  пропуск {pkg}: это текущий лаунчер — сначала поставьте другой.")
                continue
            if is_protected(pkg) and not a.force:
                print(f"  пропуск {pkg}: защищённый системный пакет (нужен --force).")
                continue
        verb = "enable" if enable else "disable-user --user 0"
        out = shell(s, f"pm {verb} {pkg}", check=False)
        ok = "new state" in out
        print(f"  {'OK  ' if ok else 'FAIL'} {pkg}: {out.splitlines()[-1] if out else 'нет ответа'}")
        if ok:
            (done.discard if enable else done.add)(pkg)
    state[s] = sorted(done)
    save_state(state)


def cmd_restore(a):
    s = pick_device(a.serial)
    pkgs = load_state().get(s, [])
    if not pkgs:
        # Подстраховка: если файл состояния потерян, включаем всё, что отключено.
        pkgs = list_packages(s, "-d")
    if not pkgs:
        print("Отключённых приложений нет.")
        return
    a.packages, a.file = pkgs, None
    change_packages(a, enable=True)


def cmd_speedup(a):
    s = pick_device(a.serial)
    values = {k: "1" for k in SPEED_SETTINGS} if a.undo else SPEED_SETTINGS
    if a.no_anim and not a.undo:
        values = {k: "0" for k in SPEED_SETTINGS}
    for key, val in values.items():
        shell(s, f"settings put global {key} {val}")
        print(f"  {key} = {val}")
    if not a.undo:
        print("  очистка кэша приложений...")
        shell(s, "pm trim-caches 999G", check=False)
        print("  фоновая оптимизация приложений (может занять несколько минут)...")
        shell(s, "cmd package bg-dexopt-job", check=False)
    print("Готово. Перезагрузите ТВ: python tvtool.py reboot")


def cmd_install(a):
    s = pick_device(a.serial)
    for apk in a.apks:
        if not os.path.isfile(apk):
            print(f"  FAIL {apk}: файл не найден")
            continue
        out = adb("install", "-r", apk, serial=s, check=False)
        print(f"  {'OK  ' if 'Success' in out else 'FAIL'} {os.path.basename(apk)}: {out.splitlines()[-1] if out else ''}")


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


def cmd_reboot(a):
    adb("reboot", serial=pick_device(a.serial))
    print("Телевизор перезагружается.")


def main():
    p = argparse.ArgumentParser(description="Ускорение Android-телевизора через ADB (безопасно, обратимо).")
    p.add_argument("-s", "--serial", help="адрес устройства, если подключено несколько")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("connect", help="подключиться к ТВ по Wi-Fi/LAN")
    c.add_argument("ip")
    c.set_defaults(func=cmd_connect)

    sub.add_parser("info", help="модель, версия Android, память").set_defaults(func=cmd_info)

    c = sub.add_parser("scan", help="сохранить список приложений в файл для редактирования")
    c.add_argument("-o", "--output")
    c.set_defaults(func=cmd_scan)

    for name, enable in (("disable", False), ("enable", True)):
        c = sub.add_parser(name, help=f"{'включить' if enable else 'отключить'} приложения")
        c.add_argument("packages", nargs="*")
        c.add_argument("-f", "--file", help="файл со списком пакетов (как после scan)")
        c.add_argument("--force", action="store_true", help="разрешить системные пакеты (опасно)")
        c.set_defaults(func=lambda a, e=enable: change_packages(a, e))

    c = sub.add_parser("restore", help="включить обратно всё, что было отключено")
    c.set_defaults(func=cmd_restore, force=False)

    c = sub.add_parser("speedup", help="ускорить анимации, очистить кэш, оптимизировать приложения")
    c.add_argument("--no-anim", action="store_true", help="полностью выключить анимации")
    c.add_argument("--undo", action="store_true", help="вернуть стандартные анимации")
    c.set_defaults(func=cmd_speedup)

    c = sub.add_parser("install", help="установить APK-файлы")
    c.add_argument("apks", nargs="+")
    c.set_defaults(func=cmd_install)

    c = sub.add_parser("vpn", help="запускать обход блокировок (ByeDPI) при включении ТВ")
    c.add_argument("package", nargs="?", help="пакет VPN-приложения (по умолчанию ищется ByeDPI)")
    c.add_argument("--off", action="store_true", help="убрать автозапуск")
    c.set_defaults(func=cmd_vpn)

    sub.add_parser("reboot", help="перезагрузить ТВ").set_defaults(func=cmd_reboot)

    a = p.parse_args()
    if a.cmd == "disable" and a.file and not os.path.isfile(a.file):
        die(f"файл {a.file} не найден")
    a.func(a)


if __name__ == "__main__":
    if not shutil.which("adb"):
        die("adb не найден. Установите Android platform-tools и добавьте в PATH (см. README.md).")
    main()
