#!/usr/bin/env python3
"""Проверка AdbClient и Tv против имитации adbd. Нужен только JDK и Python 3.

Дополнительно, если установлен пакет adb-shell (pip install adb-shell rsa), сверяет имитацию
с независимой реализацией клиента ADB, чтобы имитация не «подыгрывала» нашему клиенту.
"""

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fake_adbd import FakeAdbd, FakeTv, parse_pubkey  # noqa: E402

failures = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        failures.append(what)


def java(classes, *args):
    env = dict(os.environ, JAVA_TOOL_OPTIONS="")
    res = subprocess.run(["java", "-cp", classes, "TvTest", *map(str, args)],
                         capture_output=True, text=True, env=env, timeout=120)
    if res.returncode != 0:
        print(res.stdout, res.stderr)
    return res.stdout


def main():
    tmp = tempfile.mkdtemp()
    classes = os.path.join(tmp, "classes")
    src = os.path.join(HERE, "..", "src", "com", "leorai", "tvtuner")
    subprocess.run(["javac", "-encoding", "UTF-8", "-d", classes, os.path.join(src, "AdbClient.java"),
                    os.path.join(src, "Tv.java"), os.path.join(HERE, "TvTest.java")],
                   check=True, env=dict(os.environ, JAVA_TOOL_OPTIONS=""))
    keydir = os.path.join(tmp, "key")
    os.makedirs(keydir)

    print("Первое подключение и полный сценарий:")
    tv = FakeTv()
    adbd = FakeAdbd(tv)
    out = java(classes, adbd.port, keydir, "full")
    log = "\n".join(l for l in out.splitlines() if l.startswith("LOG"))
    check("PROMPTED true" in out, "новый ключ: ТВ показал запрос разрешения")
    check(adbd.prompts == 1 and not adbd.errors, f"протокол без ошибок (ошибки: {adbd.errors})")
    check("ОЗУ: всего 1185 МБ, свободно 244 МБ" in out, "диагностика читает память")
    check("146 МБ  com.yandex.tv.home" in out and " 107 МБ  com.vendor.ads" in out, "топ по ОЗУ (процессы pkg:service сложены)")
    check("APP com.yandex.tv.home KEEP 146 текущий главный экран" in out, "главный экран защищён")
    check("APP com.yandex.keyboard KEEP 0 клавиатура" in out, "клавиатура защищена")
    check("APP ru.kinopoisk.tv KEEP 0 нужное приложение" in out, "Кинопоиск защищён")
    check("APP com.leorai.tvtuner KEEP 0 это приложение" in out, "приложение не трогает само себя")
    check("APP com.vendor.oldsetup" not in out, "отключённое производителем не показывается")
    check("пропуск com.yandex.tv.home" in log, "ядро отказалось отключать главный экран")
    check("AFTER com.vendor.ads OFF" in out and "AFTER com.amediateka.tv BG" in out, "отметки применились")
    check(tv.pkgs["com.yandex.tv.home"][1] == 0, "главный экран остался включён")
    compiled = [c.split()[-1] for c in tv.log if c.startswith("cmd package compile")]
    check("com.leorai.tvtuner" not in compiled and "com.amediateka.tv" not in compiled
          and "ru.kinopoisk.tv" in compiled and "com.yandex.tv.home" in compiled,
          f"компилируются нужные приложения: {compiled}")
    check("Свободно ОЗУ: 244 → 410 МБ" in log, "освобождение памяти")
    installs = [c for c in tv.log if "pm install" in c]
    check(len(installs) == 2 and not any("TVTuner" in c for c in installs), "с флешки ставятся APK, кроме самого установщика")
    check(any("'/storage/1234-ABCD/apk/SmartTube Beta.apk'" in c for c in installs), "путь с пробелом экранирован")
    check(tv.split_installs == [["0_base.apk", "1_split_config.armeabi_v7a.apk", "2_split_config.xhdpi.apk"]],
          f"архив .apkm поставлен одной сессией без части для чужого процессора: {tv.split_installs}")
    check("✗" not in log.split("Установка ByeByeDPI")[1].split("VPN")[0] if "Установка ByeByeDPI" in log else False,
          "все установки с флешки прошли успешно")
    check(not any("readme.txt" in c for c in tv.log), "посторонние файлы на флешке не трогаются")
    check("VPN io.github.romanvht.byedpi" in out, "найден установленный ByeDPI")
    check("GAME com.limelight" in out, "игровой режим нашёл Moonlight")
    check("Геймпад: Wireless Controller" in log, "найден геймпад, пульт геймпадом не считается")
    check("Wi-Fi 2,4 ГГц" in log and "Сигнал слабый" in log, "предупреждение про 2,4 ГГц и слабый сигнал")
    check("io.github.romanvht.byedpi" in tv.stopped and "Обход блокировок приостановлен" in log,
          "ByeDPI приостановлен на время игры")
    check("com.amediateka.tv" in tv.stopped and "com.limelight" not in tv.stopped
          and "com.spocky.projengmenu" not in tv.stopped and "com.yandex.tv.home" not in tv.stopped,
          f"закрыты лишние приложения, Moonlight, Projectivy и главный экран не тронуты: {sorted(tv.stopped)}")
    check("GAMEOFF io.github.romanvht.byedpi" in out and "GAMEOFF2 null" in out, "выход из игрового режима возвращает ByeDPI один раз")
    check("anim=" in out and "resolution=1" in out and "disabled=com.vendor.ads," in out, "изменения сохранены для отката")
    check(tv.pkgs["com.vendor.ads"][1] == 0, "после отката реклама снова включена")
    check(tv.appops.get("com.amediateka.tv/RUN_ANY_IN_BACKGROUND") == "default", "после отката фон разрешён")
    check(tv.settings.get("global/animator_duration_scale") == "1.0"
          and "global/window_animation_scale" not in tv.settings, "анимации вернулись к заводским значениям")
    check(not tv.wm, "разрешение сброшено")
    check(tv.settings.get("secure/always_on_vpn_app") == "io.github.romanvht.byedpi", "обход блокировок остался после отката")
    check("disabled=, " in out.split("STORE_AFTER_RESTORE")[1] or "disabled=}" in out.split("STORE_AFTER_RESTORE")[1]
          or "disabled=," in out.split("STORE_AFTER_RESTORE")[1], "после отката список отключённых пуст")
    check("DONE" in out, "перезагрузка не считается ошибкой")

    print("Повторное подключение тем же ключом:")
    out = java(classes, adbd.port, keydir, "reconnect")
    check("PROMPTED false" in out and "MODEL SMART-TV-43" in out and adbd.prompts == 1,
          "сохранённый ключ принят без нового запроса")

    print("Пользователь отклонил запрос:")
    rejecting = FakeAdbd(FakeTv(), accept_keys=False)
    newkey = os.path.join(tmp, "key2")
    os.makedirs(newkey)
    out = java(classes, rejecting.port, newkey, "reconnect")
    check("CONNECT_FAILED" in out, "отказ на ТВ превращается в понятную ошибку")

    try:
        from adb_shell.adb_device import AdbDeviceTcp
        from adb_shell.auth.keygen import keygen
        from adb_shell.auth.sign_pythonrsa import PythonRSASigner
    except ImportError:
        print("adb-shell не установлен — сверка с независимым клиентом пропущена")
    else:
        print("Сверка имитации с независимым клиентом adb-shell:")
        key = os.path.join(tmp, "adbkey")
        keygen(key)
        with open(key + ".pub", "rb") as f:
            pub = f.read()
        check(parse_pubkey(pub.strip() + b"\0") is not None, "ключ adb-shell проходит ту же проверку формата")
        with open(key) as f:
            priv = f.read()
        signer = PythonRSASigner(pub.decode(), priv)
        other = FakeAdbd(FakeTv())
        dev = AdbDeviceTcp("127.0.0.1", other.port, default_transport_timeout_s=9.0)
        dev.connect(rsa_keys=[signer], auth_timeout_s=5)
        check(dev.shell("getprop ro.product.model").strip() == "SMART-TV-43" and not other.errors,
              f"adb-shell работает с имитацией (ошибки: {other.errors})")
        dev.close()

    print(f"\n{'ВСЁ ХОРОШО' if not failures else f'ОШИБОК: {len(failures)}'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
