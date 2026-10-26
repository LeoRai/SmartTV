package com.leorai.tvtuner;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/** Все действия с телевизором. Та же логика, что в tvtool.py, но через ADB изнутри самого ТВ. */
public final class Tv {
    public interface Store {
        String get(String key);

        void put(String key, String value);
    }

    public interface Log {
        void line(String text);
    }

    public enum State { KEEP, BG, OFF }

    public static final class App {
        public final String pkg;
        public final boolean system;
        public final int ramMb;
        public final String protection;  // null, если пакет можно трогать
        public final State initial;
        public State state;
        public String label;

        App(String pkg, boolean system, int ramMb, String protection, State initial) {
            this.pkg = pkg;
            this.system = system;
            this.ramMb = ramMb;
            this.protection = protection;
            this.initial = initial;
            this.state = initial;
            this.label = pkg;
        }
    }

    // Без этих пакетов ТВ может не загрузиться, потерять картинку, пульт, HDMI или настройки.
    private static final String[] PROTECTED_PREFIXES = {
            "android", "com.android.", "com.google.android.gms", "com.google.android.gsf",
            "com.google.android.tv.remote", "com.mediatek.", "com.mstar.", "com.droidlogic.",
            "com.amlogic.", "com.realtek.", "com.hisilicon.", "com.rockchip.", "com.cvte."};
    // Приложения, которые пользователь хочет сохранить при любой чистке.
    private static final String[] KEEP_KEYWORDS = {"kinopoisk", "byedpi"};
    private static final String[] ANIM_KEYS = {
            "window_animation_scale", "transition_animation_scale", "animator_duration_scale"};
    private static final int MIN_FREE_MB_FOR_COMPILE = 500;
    private static final String TMP_APK = "/data/local/tmp/tvtuner_install.apk";

    private final AdbClient adb;
    private final Store store;
    private final Log log;
    private final String selfPkg;

    public Tv(AdbClient adb, Store store, Log log, String selfPkg) {
        this.adb = adb;
        this.store = store;
        this.log = log;
        this.selfPkg = selfPkg;
    }

    // ---------- чтение состояния ТВ ----------

    String sh(String command) throws IOException {
        return adb.shell(command).trim();
    }

    List<String> packages(String flags) throws IOException {
        List<String> result = new ArrayList<>();
        for (String line : sh("pm list packages " + flags).split("\n")) {
            line = line.trim();
            if (line.startsWith("package:")) {
                result.add(line.substring("package:".length()));
            }
        }
        Collections.sort(result);
        return result;
    }

    String homeLauncher() throws IOException {
        String[] lines = sh("cmd package resolve-activity --brief "
                + "-a android.intent.action.MAIN -c android.intent.category.HOME").split("\n");
        String last = lines[lines.length - 1].trim();
        return last.contains("/") ? last.substring(0, last.indexOf('/')) : null;
    }

    /** Пакеты, которые сейчас работают как главный экран, клавиатура, VPN или служба (Projectivy). */
    Map<String, String> criticalPackages() throws IOException {
        Map<String, String> crit = new LinkedHashMap<>();
        String launcher = homeLauncher();
        if (launcher != null) {
            crit.put(launcher, "текущий главный экран");
        }
        String ime = sh("settings get secure default_input_method");
        if (ime.contains("/")) {
            crit.put(ime.substring(0, ime.indexOf('/')), "клавиатура");
        }
        String vpn = sh("settings get secure always_on_vpn_app");
        if (!vpn.isEmpty() && !vpn.equals("null")) {
            crit.put(vpn, "обход блокировок");
        }
        for (String svc : sh("settings get secure enabled_accessibility_services").split(":")) {
            if (svc.contains("/")) {
                crit.put(svc.substring(0, svc.indexOf('/')), "служба спец. возможностей");
            }
        }
        crit.put(selfPkg, "это приложение");
        return crit;
    }

    static String protectionReason(String pkg, Map<String, String> crit) {
        if (crit.containsKey(pkg)) {
            return crit.get(pkg);
        }
        for (String p : PROTECTED_PREFIXES) {
            if (pkg.equals(p) || pkg.startsWith(p)) {
                return "системный пакет";
            }
        }
        for (String k : KEEP_KEYWORDS) {
            if (pkg.contains(k)) {
                return "нужное приложение";
            }
        }
        return null;
    }

    Map<String, Integer> meminfoMb() throws IOException {
        Map<String, Integer> values = new LinkedHashMap<>();
        for (String line : sh("cat /proc/meminfo").split("\n")) {
            String[] parts = line.trim().split("\\s+");
            if (parts.length >= 2 && parts[1].matches("\\d+")) {
                values.put(parts[0].replace(":", ""), (int) (Long.parseLong(parts[1]) / 1024));
            }
        }
        return values;
    }

    /** Сколько ОЗУ (МБ) занимает каждое запущенное приложение, по данным dumpsys meminfo. */
    Map<String, Integer> ramByPackage() throws IOException {
        Map<String, Integer> usage = new LinkedHashMap<>();
        Pattern row = Pattern.compile("\\s*([\\d,]+)K: (\\S+).*");
        boolean inSection = false;
        for (String line : sh("dumpsys meminfo").split("\n")) {
            if (line.contains("Total PSS by process")) {
                inSection = true;
                continue;
            }
            if (inSection) {
                Matcher m = row.matcher(line);
                if (!m.matches()) {
                    break;
                }
                String pkg = m.group(2).split(":")[0];  // процессы вида pkg:service считаем вместе
                int mb = Integer.parseInt(m.group(1).replace(",", "")) / 1024;
                Integer old = usage.get(pkg);
                usage.put(pkg, (old == null ? 0 : old) + mb);
            }
        }
        return usage;
    }

    Integer freeDataMb() throws IOException {
        String[] lines = sh("df -k /data").split("\n");
        try {
            return (int) (Long.parseLong(lines[lines.length - 1].trim().split("\\s+")[3]) / 1024);
        } catch (RuntimeException e) {
            return null;
        }
    }

    public String info() throws IOException {
        StringBuilder r = new StringBuilder();
        r.append("Модель: ").append(sh("getprop ro.product.manufacturer")).append(' ')
                .append(sh("getprop ro.product.model")).append('\n');
        r.append("Android ").append(sh("getprop ro.build.version.release")).append('\n');
        Map<String, Integer> mem = meminfoMb();
        Integer total = mem.get("MemTotal");
        Integer avail = mem.containsKey("MemAvailable") ? mem.get("MemAvailable") : mem.get("MemFree");
        r.append("ОЗУ: всего ").append(total).append(" МБ, свободно ").append(avail).append(" МБ\n");
        Integer free = freeDataMb();
        r.append("Диск: свободно ").append(free == null ? "?" : free).append(" МБ\n");
        String[] size = sh("wm size").split("\n");
        Matcher sizeMatch = Pattern.compile("(\\d+)x(\\d+)").matcher(size[size.length - 1]);
        boolean hasSize = sizeMatch.find();
        r.append("Интерфейс: ").append(hasSize ? sizeMatch.group() : "?").append('\n');
        double uptimeH = 0;
        try {
            uptimeH = Double.parseDouble(sh("cat /proc/uptime").split("\\s+")[0]) / 3600;
        } catch (RuntimeException ignored) {
        }
        r.append("Без перезагрузки: ").append(Math.round(uptimeH)).append(" ч\n");

        List<Map.Entry<String, Integer>> usage = new ArrayList<>(ramByPackage().entrySet());
        Collections.sort(usage, new Comparator<Map.Entry<String, Integer>>() {
            @Override
            public int compare(Map.Entry<String, Integer> a, Map.Entry<String, Integer> b) {
                return b.getValue() - a.getValue();
            }
        });
        if (!usage.isEmpty()) {
            r.append("\nБольше всего ОЗУ занимают:\n");
            for (Map.Entry<String, Integer> e : usage.subList(0, Math.min(8, usage.size()))) {
                r.append(String.format("%5d МБ  %s\n", e.getValue(), e.getKey()));
            }
        }
        r.append("\nИзменено этим приложением: отключено ").append(getSet("disabled").size())
                .append(", запрещён фон у ").append(getSet("restricted").size()).append('\n');

        List<String> tips = new ArrayList<>();
        if (free != null && free < 1024) {
            tips.add("Мало места на диске — это сильно тормозит ТВ. Удалите ненужное и нажмите «Ускорить».");
        }
        if (total != null && total <= 1600) {
            tips.add("Мало ОЗУ: в «Чистке приложений» отключите или ограничьте тяжёлые приложения.");
        }
        double anim;
        try {
            anim = Double.parseDouble(sh("settings get global animator_duration_scale"));
        } catch (NumberFormatException e) {
            anim = 1;
        }
        if (anim >= 1) {
            tips.add("Анимации не ускорены: нажмите «Ускорить».");
        }
        if (uptimeH > 72) {
            tips.add("ТВ давно не перезагружался: нажмите «Перезагрузить».");
        }
        if (hasSize && Integer.parseInt(sizeMatch.group(2)) > 720 && !has("resolution")) {
            tips.add("Можно попробовать «Интерфейс 720p» (эксперимент).");
        }
        if (!tips.isEmpty()) {
            r.append("\nСоветы:\n");
            for (String tip : tips) {
                r.append("• ").append(tip).append('\n');
            }
        }
        return r.toString();
    }

    // ---------- чистка приложений ----------

    public List<App> listApps() throws IOException {
        Set<String> system = new HashSet<>(packages("-s"));
        Map<String, String> crit = criticalPackages();
        final Map<String, Integer> ram = ramByPackage();
        Set<String> disabled = getSet("disabled");
        Set<String> restricted = getSet("restricted");
        Set<String> all = new TreeSet<>(packages("-e"));
        all.addAll(disabled);
        List<App> apps = new ArrayList<>();
        for (String pkg : all) {
            State state = disabled.contains(pkg) ? State.OFF : restricted.contains(pkg) ? State.BG : State.KEEP;
            Integer mb = ram.get(pkg);
            apps.add(new App(pkg, system.contains(pkg), mb == null ? 0 : mb, protectionReason(pkg, crit), state));
        }
        Collections.sort(apps, new Comparator<App>() {
            @Override
            public int compare(App a, App b) {
                return a.ramMb != b.ramMb ? b.ramMb - a.ramMb : a.pkg.compareTo(b.pkg);
            }
        });
        return apps;
    }

    public void applyApps(List<App> apps) throws IOException {
        Map<String, String> crit = criticalPackages();
        int changed = 0;
        for (App app : apps) {
            if (app.state == app.initial) {
                continue;
            }
            changed++;
            if (app.initial == State.OFF) {
                enable(app.pkg);
            } else if (app.initial == State.BG) {
                setBackground(app.pkg, true);
            }
            if (app.state == State.OFF) {
                disable(app.pkg, crit);
            } else if (app.state == State.BG) {
                restrict(app.pkg, crit);
            }
        }
        log.line(changed == 0 ? "Ничего не изменено." : "Готово. Изменено приложений: " + changed);
    }

    boolean disable(String pkg, Map<String, String> crit) throws IOException {
        if (refuse(pkg, crit)) {
            return false;
        }
        boolean ok = sh("pm disable-user --user 0 " + pkg).contains("new state");
        report(ok, pkg, "отключено");
        if (ok) {
            updateSet("disabled", pkg, true);
        }
        return ok;
    }

    boolean enable(String pkg) throws IOException {
        boolean ok = sh("pm enable " + pkg).contains("new state");
        report(ok, pkg, "включено");
        if (ok) {
            updateSet("disabled", pkg, false);
        }
        return ok;
    }

    boolean restrict(String pkg, Map<String, String> crit) throws IOException {
        return !refuse(pkg, crit) && setBackground(pkg, false);
    }

    boolean setBackground(String pkg, boolean allowed) throws IOException {
        String mode = allowed ? "default" : "ignore";
        for (String op : new String[]{"RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND"}) {
            sh("cmd appops set " + pkg + " " + op + " " + mode);
        }
        if (!allowed) {
            sh("am force-stop " + pkg);  // останавливаем то, что уже запущено
        }
        boolean ok = sh("cmd appops get " + pkg + " RUN_ANY_IN_BACKGROUND").contains("ignore") != allowed;
        report(ok, pkg, allowed ? "работа в фоне разрешена" : "работа в фоне запрещена");
        if (ok) {
            updateSet("restricted", pkg, !allowed);
        }
        return ok;
    }

    private boolean refuse(String pkg, Map<String, String> crit) {
        String reason = protectionReason(pkg, crit);
        if (reason != null) {
            log.line("  пропуск " + pkg + ": " + reason);
        }
        return reason != null;
    }

    private void report(boolean ok, String pkg, String what) {
        log.line((ok ? "  ✓ " : "  ✗ ") + pkg + (ok ? ": " + what : ": не удалось"));
    }

    // ---------- ускорение ----------

    public void speedup(boolean max) throws IOException {
        setAnimations(max ? "0" : "0.5");
        log.line("Очистка кэша приложений...");
        sh("pm trim-caches 999G");
        log.line("Оптимизация приложений (может занять несколько минут)...");
        sh("cmd package bg-dexopt-job");
        if (max) {
            compile();
            boost();
        }
        log.line("Ускорение завершено. Для полного эффекта перезагрузите ТВ.");
    }

    void setAnimations(String value) throws IOException {
        if (!has("anim")) {  // заводские значения запоминаем один раз, чтобы потом вернуть
            StringBuilder original = new StringBuilder();
            for (String k : ANIM_KEYS) {
                original.append(k).append('=').append(sh("settings get global " + k)).append(';');
            }
            store.put("anim", original.toString());
        }
        for (String k : ANIM_KEYS) {
            sh("settings put global " + k + " " + value);
        }
        log.line("Скорость анимаций: " + value + " (1 — заводская, 0 — без анимаций)");
    }

    void restoreAnimations() throws IOException {
        Map<String, String> original = new LinkedHashMap<>();
        String saved = store.get("anim");
        if (saved != null) {
            for (String pair : saved.split(";")) {
                int eq = pair.indexOf('=');
                if (eq > 0) {
                    original.put(pair.substring(0, eq), pair.substring(eq + 1));
                }
            }
        }
        for (String k : ANIM_KEYS) {
            String v = original.containsKey(k) ? original.get(k) : "null";
            sh(v.isEmpty() || v.equals("null") ? "settings delete global " + k : "settings put global " + k + " " + v);
        }
        store.put("anim", "");
        log.line("Анимации возвращены к заводским.");
    }

    List<String> compileTargets() throws IOException {
        Set<String> targets = new TreeSet<>(packages("-3 -e"));
        for (String pkg : packages("-e")) {
            for (String k : KEEP_KEYWORDS) {
                if (pkg.contains(k)) {
                    targets.add(pkg);
                }
            }
        }
        String launcher = homeLauncher();
        if (launcher != null && !launcher.equals("android")) {
            targets.add(launcher);
        }
        targets.removeAll(getSet("restricted"));
        targets.remove(selfPkg);  // компиляция может перезапустить само приложение
        return new ArrayList<>(targets);
    }

    public void compile() throws IOException {
        Integer free = freeDataMb();
        if (free != null && free < MIN_FREE_MB_FOR_COMPILE) {
            log.line("Компиляция пропущена: на диске свободно всего " + free + " МБ.");
            return;
        }
        List<String> targets = compileTargets();
        log.line("Полная компиляция " + targets.size() + " приложений (может занять несколько минут)...");
        for (String pkg : targets) {
            report(sh("cmd package compile -m speed -f " + pkg).contains("Success"), pkg, "скомпилировано");
        }
    }

    public void boost() throws IOException {
        Integer before = meminfoMb().get("MemAvailable");
        sh("am kill-all");
        try {
            Thread.sleep(2000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        Integer after = meminfoMb().get("MemAvailable");
        log.line(before != null && after != null
                ? "Свободно ОЗУ: " + before + " → " + after + " МБ" : "Фоновые процессы остановлены.");
    }

    // ---------- приложения с флешки и обход блокировок ----------

    /** APK и архивы из папки apk в корне флешки. Сам установщик пропускаем, чтобы не перезапустить себя. */
    public List<String> usbApks() throws IOException {
        List<String> result = new ArrayList<>();
        for (String line : sh("for f in /storage/*/apk/*; do [ -f \"$f\" ] && echo \"$f\"; done").split("\n")) {
            line = line.trim();
            String name = line.substring(line.lastIndexOf('/') + 1).toLowerCase();
            if ((name.endsWith(".apk") || isBundle(name)) && !name.contains("tvtuner")) {
                result.add(line);
            }
        }
        return result;
    }

    /** Архивы из нескольких APK (split APK): .apkm с APKMirror, .apks, .xapk. */
    static boolean isBundle(String name) {
        return name.endsWith(".apkm") || name.endsWith(".apks") || name.endsWith(".xapk");
    }

    public int installFromUsb() throws IOException {
        List<String> apks = usbApks();
        if (apks.isEmpty()) {
            log.line("На флешке нет папки apk с APK-файлами.");
            return 0;
        }
        int installed = 0;
        for (String path : apks) {
            String name = path.substring(path.lastIndexOf('/') + 1);
            log.line("Установка " + name + "...");
            String out = isBundle(name.toLowerCase()) ? installBundle(path)
                    : sh("cp " + quote(path) + " " + TMP_APK + " && pm install -r " + TMP_APK + "; rm -f " + TMP_APK);
            boolean ok = out.contains("Success");
            if (ok) {
                installed++;
            }
            String[] lines = out.split("\n");
            log.line(ok ? "  ✓ установлено" : "  ✗ " + lines[lines.length - 1]);
        }
        return installed;
    }

    /** Ставит split APK так же, как adb install-multiple: одна сессия, части передаются через stdin. */
    String installBundle(String path) throws IOException {
        Map<String, byte[]> parts = new LinkedHashMap<>();
        Set<String> abis = new HashSet<>();
        for (String abi : sh("getprop ro.product.cpu.abilist").split(",")) {
            abis.add(abi.trim().replace('-', '_'));
        }
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(adb.exec("cat " + quote(path), null)))) {
            for (ZipEntry e; (e = zip.getNextEntry()) != null; ) {
                String name = e.getName().substring(e.getName().lastIndexOf('/') + 1);
                if (!name.endsWith(".apk") || isForeignAbi(name, abis)) {
                    continue;  // части для чужого процессора ТВ не нужны
                }
                ByteArrayOutputStream data = new ByteArrayOutputStream();
                byte[] buf = new byte[65536];
                for (int n; (n = zip.read(buf)) > 0; ) {
                    data.write(buf, 0, n);
                }
                parts.put(name, data.toByteArray());
            }
        }
        if (parts.isEmpty()) {
            return "в архиве нет APK (файл повреждён или зашифрован)";
        }
        long total = 0;
        for (byte[] p : parts.values()) {
            total += p.length;
        }
        Matcher session = Pattern.compile("\\[(\\d+)]").matcher(sh("cmd package install-create -r -S " + total));
        if (!session.find()) {
            return "не удалось начать установку";
        }
        String id = session.group(1);
        int index = 0;
        for (Map.Entry<String, byte[]> part : parts.entrySet()) {
            String out = new String(adb.exec("cmd package install-write -S " + part.getValue().length + " " + id
                    + " " + (index++) + "_" + part.getKey().replaceAll("[^A-Za-z0-9._-]", "_") + " -",
                    part.getValue()), StandardCharsets.UTF_8);
            if (!out.contains("Success")) {
                sh("cmd package install-abandon " + id);
                return out.trim().isEmpty() ? "не удалось передать " + part.getKey() : out.trim();
            }
        }
        return sh("cmd package install-commit " + id);
    }

    private static boolean isForeignAbi(String apkName, Set<String> deviceAbis) {
        if (deviceAbis.contains("")) {
            return false;  // список процессоров неизвестен: ставим всё
        }
        for (String abi : new String[]{"arm64_v8a", "armeabi_v7a", "armeabi", "x86_64", "x86"}) {
            if (apkName.contains("config." + abi + ".") || apkName.equals(abi + ".apk")) {
                return !deviceAbis.contains(abi);
            }
        }
        return false;
    }

    public String findByeDpi() throws IOException {
        for (String pkg : packages("-e")) {
            if (pkg.toLowerCase().contains("byedpi")) {
                return pkg;
            }
        }
        return null;
    }

    /** ByeDPI будет запускаться вместе с телевизором. Возвращает пакет или null, если его нет. */
    public String setupVpn() throws IOException {
        String pkg = findByeDpi();
        if (pkg == null) {
            log.line("ByeByeDPI не установлен. Положите его APK в папку apk на флешке.");
            return null;
        }
        sh("settings put secure always_on_vpn_app " + pkg);
        // Без lockdown: если обход упадёт, интернет не пропадёт полностью.
        sh("settings put secure always_on_vpn_lockdown 0");
        log.line("Обход блокировок будет запускаться вместе с ТВ (" + pkg + ").");
        return pkg;
    }

    // ---------- разрешение, откат, перезагрузка ----------

    public void resolution720() throws IOException {
        Matcher size = Pattern.compile("Physical size: (\\d+)x(\\d+)").matcher(sh("wm size"));
        Matcher dens = Pattern.compile("Physical density: (\\d+)").matcher(sh("wm density"));
        if (!size.find() || !dens.find()) {
            log.line("Не удалось узнать разрешение экрана.");
            return;
        }
        int w = Integer.parseInt(size.group(1));
        int h = Integer.parseInt(size.group(2));
        int d = Integer.parseInt(dens.group(1));
        if (h <= 720) {
            log.line("Интерфейс уже работает в " + w + "x" + h + ", понижать нечего.");
            return;
        }
        // Размер и плотность меняем в одной пропорции, чтобы всё осталось того же размера.
        int newW = Math.round(w * 720f / h / 2) * 2;
        int newD = Math.round(d * 720f / h);
        sh("wm size " + newW + "x720");
        sh("wm density " + newD);
        store.put("resolution", "1");
        log.line("Интерфейс: " + w + "x" + h + " → " + newW + "x720. Видео по-прежнему в полном разрешении.");
        log.line("Проверьте меню, приложения, HDMI и антенну. Если что-то не так — «Вернуть разрешение».");
    }

    public void resetResolution() throws IOException {
        sh("wm size reset");
        sh("wm density reset");
        store.put("resolution", "");
        log.line("Разрешение интерфейса возвращено к заводскому.");
    }

    public void restore() throws IOException {
        Set<String> disabled = getSet("disabled");
        if (disabled.isEmpty()) {
            // Подстраховка: включаем отключённое пользователем (enabled=3), но не производителем.
            for (String pkg : packages("-d")) {
                if (sh("dumpsys package " + pkg + " | grep -o 'enabled=[0-9]'").contains("enabled=3")) {
                    disabled.add(pkg);
                }
            }
        }
        for (String pkg : disabled) {
            enable(pkg);
        }
        for (String pkg : getSet("restricted")) {
            setBackground(pkg, true);
        }
        restoreAnimations();
        if (has("resolution")) {
            resetResolution();
        }
        log.line("Всё возвращено. Перезагрузите ТВ.");
    }

    public void reboot() {
        log.line("Перезагрузка...");
        try {
            adb.service("reboot:");
        } catch (IOException ignored) {
            // ТВ уходит в перезагрузку и сам рвёт соединение — это не ошибка
        }
    }

    // ---------- хранение того, что изменено ----------

    private boolean has(String key) {
        String v = store.get(key);
        return v != null && !v.isEmpty();
    }

    private Set<String> getSet(String key) {
        Set<String> result = new TreeSet<>();
        String v = store.get(key);
        if (v != null) {
            for (String p : v.split(",")) {
                if (!p.isEmpty()) {
                    result.add(p);
                }
            }
        }
        return result;
    }

    private void updateSet(String key, String pkg, boolean add) {
        Set<String> set = getSet(key);
        if (add) {
            set.add(pkg);
        } else {
            set.remove(pkg);
        }
        StringBuilder joined = new StringBuilder();
        for (String p : set) {
            joined.append(p).append(',');
        }
        store.put(key, joined.toString());
    }

    private static String quote(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }
}
