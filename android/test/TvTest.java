import com.leorai.tvtuner.AdbClient;
import com.leorai.tvtuner.Tv;

import java.io.File;
import java.io.IOException;
import java.security.KeyPair;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Прогон AdbClient и Tv против fake_adbd.py: java TvTest <порт> <папка ключа> full|reconnect|reject */
public class TvTest {
    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(args[0]);
        KeyPair keys = AdbClient.loadOrCreateKey(new File(args[1]));
        final boolean[] prompted = {false};
        AdbClient adb;
        try {
            adb = AdbClient.connect("127.0.0.1", port, keys, 5000, () -> prompted[0] = true);
        } catch (IOException e) {
            System.out.println("CONNECT_FAILED " + e.getMessage());
            return;
        }
        System.out.println("PROMPTED " + prompted[0]);
        if (!args[2].equals("full")) {
            System.out.println("MODEL " + adb.shell("getprop ro.product.model").trim());
            adb.close();
            return;
        }
        final Map<String, String> store = new HashMap<>();
        Tv tv = new Tv(adb, new Tv.Store() {
            public String get(String key) {
                return store.get(key);
            }

            public void put(String key, String value) {
                store.put(key, value);
            }
        }, line -> System.out.println("LOG " + line), "com.leorai.tvtuner");

        System.out.println("INFO\n" + tv.info());
        List<Tv.App> apps = tv.listApps();
        for (Tv.App app : apps) {
            System.out.println("APP " + app.pkg + " " + app.state + " " + app.ramMb + " " + app.protection);
            if (app.pkg.equals("com.vendor.ads")) {
                app.state = Tv.State.OFF;
            } else if (app.pkg.equals("com.amediateka.tv")) {
                app.state = Tv.State.BG;
            } else if (app.pkg.equals("com.yandex.tv.home")) {
                app.state = Tv.State.OFF;  // интерфейс так не даст, но ядро тоже должно отказать
            }
        }
        tv.applyApps(apps);
        for (Tv.App app : tv.listApps()) {
            System.out.println("AFTER " + app.pkg + " " + app.state);
        }
        tv.speedup(true);
        tv.installFromUsb();
        System.out.println("VPN " + tv.setupVpn());
        System.out.println("GAME " + tv.gameMode());
        System.out.println("GAMEOFF " + tv.gameModeOff());
        System.out.println("GAMEOFF2 " + tv.gameModeOff());
        System.out.println("DNS " + tv.secureDns());
        tv.resolution720();
        System.out.println("STORE " + new java.util.TreeMap<>(store));
        tv.restore();
        System.out.println("STORE_AFTER_RESTORE " + new java.util.TreeMap<>(store));
        tv.reboot();
        System.out.println("DONE");
    }
}
