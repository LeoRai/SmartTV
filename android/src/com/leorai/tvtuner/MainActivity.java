package com.leorai.tvtuner;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.IOException;
import java.net.ConnectException;
import java.security.KeyPair;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int ADB_PORT = 5555;
    private static final int PROMPT_TIMEOUT_MS = 120000;
    private static final long GAME_LAUNCH_DELAY_MS = 6000;  // успеть прочитать проверку геймпада и сети

    private interface Job {
        void run(Tv tv) throws Exception;
    }

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private volatile boolean busy;
    // Доступны только из потока worker.
    private AdbClient adb;
    private Tv tv;

    private View mainScreen;
    private boolean appsShown;
    private TextView status;
    private TextView logView;
    private ScrollView logScroll;
    private Button firstButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mainScreen = buildMainScreen();
        setContentView(mainScreen);
        firstButton.requestFocus();
        log("ТВ Тюнер ускоряет телевизор без прошивки и root. Всё можно вернуть кнопкой «Вернуть всё как было».");
        start("Подключение", new Job() {
            @Override
            public void run(Tv tv) {
                log("Подключено. Начните с «Сделать всё автоматически», затем «Чистка приложений».");
            }
        });
    }

    @Override
    protected void onDestroy() {
        worker.shutdownNow();
        closeAdb();
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (appsShown) {
            showMain();
        } else {
            super.onBackPressed();
        }
    }

    // ---------- главный экран ----------

    private View buildMainScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setPadding(dp(32), dp(24), dp(32), dp(24));

        LinearLayout menu = new LinearLayout(this);
        menu.setOrientation(LinearLayout.VERTICAL);
        TextView title = text("ТВ Тюнер", 28);
        menu.addView(title);
        status = text("", 16);
        status.setTextColor(Color.LTGRAY);
        menu.addView(status);

        firstButton = addButton(menu, "Сделать всё автоматически", new Runnable() {
            @Override
            public void run() {
                runAuto();
            }
        });
        addButton(menu, "Чистка приложений", new Runnable() {
            @Override
            public void run() {
                openApps();
            }
        });
        addButton(menu, "Установить APK с флешки", new Runnable() {
            @Override
            public void run() {
                start("Установка с флешки", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.installFromUsb();
                    }
                });
            }
        });
        addButton(menu, "Ускорить (максимум)", new Runnable() {
            @Override
            public void run() {
                start("Ускорение", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.speedup(true);
                    }
                });
            }
        });
        addButton(menu, "Освободить память", new Runnable() {
            @Override
            public void run() {
                start("Освобождение памяти", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.boost();
                    }
                });
            }
        });
        addButton(menu, "Игровой режим (Moonlight)", new Runnable() {
            @Override
            public void run() {
                start("Игровой режим", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        String moonlight = tv.gameMode();
                        if (moonlight != null) {
                            log("Moonlight откроется через " + GAME_LAUNCH_DELAY_MS / 1000 + " секунд...");
                            launchApp(moonlight, GAME_LAUNCH_DELAY_MS);
                        }
                    }
                });
            }
        });
        addButton(menu, "Выйти из игрового режима", new Runnable() {
            @Override
            public void run() {
                start("Выход из игрового режима", new Job() {
                    @Override
                    public void run(Tv tv) {
                        launchVpn(tv.gameModeOff());
                    }
                });
            }
        });
        addButton(menu, "Обход блокировок YouTube", new Runnable() {
            @Override
            public void run() {
                start("Настройка обхода", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        launchVpn(tv.setupVpn());
                    }
                });
            }
        });
        addButton(menu, "Защищённый DNS (если YouTube не грузится)", new Runnable() {
            @Override
            public void run() {
                start("Защищённый DNS", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.secureDns();
                    }
                });
            }
        });
        addButton(menu, "Обычный DNS", new Runnable() {
            @Override
            public void run() {
                start("Обычный DNS", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.restoreDns();
                    }
                });
            }
        });
        addButton(menu, "Диагностика", new Runnable() {
            @Override
            public void run() {
                start("Диагностика", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        log(tv.info());
                    }
                });
            }
        });
        addButton(menu, "Интерфейс 720p (эксперимент)", new Runnable() {
            @Override
            public void run() {
                confirm("Интерфейс будет отрисовываться в 720p: слабому видеочипу станет легче, видео останется "
                        + "в полном разрешении. Если что-то будет выглядеть не так, нажмите «Вернуть разрешение».",
                        "Понизить разрешение", new Job() {
                            @Override
                            public void run(Tv tv) throws Exception {
                                tv.resolution720();
                            }
                        });
            }
        });
        addButton(menu, "Вернуть разрешение", new Runnable() {
            @Override
            public void run() {
                start("Возврат разрешения", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.resetResolution();
                    }
                });
            }
        });
        addButton(menu, "Вернуть всё как было", new Runnable() {
            @Override
            public void run() {
                confirm("Включить отключённые приложения, разрешить им фон, вернуть анимации и разрешение? "
                        + "Обход блокировок останется.", "Вернуть всё", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.restore();
                    }
                });
            }
        });
        addButton(menu, "Перезагрузить ТВ", new Runnable() {
            @Override
            public void run() {
                confirm("Перезагрузить телевизор?", "Перезагрузка", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.reboot();
                    }
                });
            }
        });

        ScrollView menuScroll = new ScrollView(this);
        menuScroll.addView(menu);
        root.addView(menuScroll, new LinearLayout.LayoutParams(dp(320), ViewGroup.LayoutParams.MATCH_PARENT));

        logView = text("", 16);
        logView.setPadding(dp(24), 0, 0, 0);
        logScroll = new ScrollView(this);
        logScroll.addView(logView);
        root.addView(logScroll, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return root;
    }

    private void runAuto() {
        start("Автоматическая настройка", new Job() {
            @Override
            public void run(Tv tv) throws Exception {
                log("Шаг 1 из 3: установка приложений с флешки");
                tv.installFromUsb();
                log("Шаг 2 из 3: ускорение");
                tv.speedup(true);
                log("Шаг 3 из 3: обход блокировок YouTube");
                String vpn = tv.setupVpn();
                log("Осталось: «Чистка приложений», затем «Перезагрузить ТВ».");
                launchVpn(vpn);
            }
        });
    }

    private void launchVpn(final String pkg) {
        if (pkg == null) {
            return;
        }
        log("Сейчас откроется ByeByeDPI: нажмите «Подключить» и разрешите запрос. Потом вернитесь сюда.");
        launchApp(pkg, 0);
    }

    private void launchApp(final String pkg, long delayMs) {
        ui.postDelayed(new Runnable() {
            @Override
            public void run() {
                PackageManager pm = getPackageManager();
                Intent intent = pm.getLeanbackLaunchIntentForPackage(pkg);
                if (intent == null) {
                    intent = pm.getLaunchIntentForPackage(pkg);
                }
                if (intent != null) {
                    startActivity(intent);
                } else {
                    log("Не удалось открыть " + pkg + " — запустите его из списка приложений.");
                }
            }
        }, delayMs);
    }

    // ---------- экран чистки ----------

    private void openApps() {
        start("Чтение списка приложений", new Job() {
            @Override
            public void run(Tv tv) throws Exception {
                final List<Tv.App> apps = tv.listApps();
                PackageManager pm = getPackageManager();
                for (Tv.App app : apps) {
                    try {
                        app.label = pm.getApplicationLabel(
                                pm.getApplicationInfo(app.pkg, PackageManager.MATCH_DISABLED_COMPONENTS)).toString();
                    } catch (PackageManager.NameNotFoundException ignored) {
                    }
                }
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        showApps(apps);
                    }
                });
            }
        });
    }

    private void showApps(final List<Tv.App> apps) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(32), dp(24), dp(32), dp(24));
        root.addView(text("Чистка приложений", 26));
        root.addView(text("Нажимайте на приложение, чтобы выбрать: ОСТАВИТЬ → ЗАПРЕТИТЬ ФОН → ОТКЛЮЧИТЬ. "
                + "«Запретить фон»: приложение открывается, но не висит в памяти. Сверху — самые тяжёлые. "
                + "Если сомневаетесь, выбирайте «запретить фон», а не «отключить».", 16));

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        root.addView(buttons);

        final ListView list = new ListView(this);
        final ArrayAdapter<Tv.App> adapter = new ArrayAdapter<Tv.App>(this, android.R.layout.simple_list_item_1, apps) {
            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                TextView v = (TextView) super.getView(position, convertView, parent);
                Tv.App app = getItem(position);
                v.setText(describe(app));
                v.setTextSize(18);
                v.setTextColor(app.protection != null ? Color.GRAY
                        : app.state == Tv.State.OFF ? Color.rgb(0xEF, 0x53, 0x50)
                        : app.state == Tv.State.BG ? Color.rgb(0xFF, 0xD5, 0x4F) : Color.WHITE);
                return v;
            }
        };
        list.setAdapter(adapter);
        list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                Tv.App app = apps.get(position);
                if (app.protection != null) {
                    toast("Защищено: " + app.protection);
                    return;
                }
                app.state = app.state == Tv.State.KEEP ? Tv.State.BG
                        : app.state == Tv.State.BG ? Tv.State.OFF : Tv.State.KEEP;
                adapter.notifyDataSetChanged();
            }
        });
        root.addView(list, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        addButton(buttons, "Применить", new Runnable() {
            @Override
            public void run() {
                showMain();
                start("Применение", new Job() {
                    @Override
                    public void run(Tv tv) throws Exception {
                        tv.applyApps(apps);
                    }
                });
            }
        });
        addButton(buttons, "Назад без изменений", new Runnable() {
            @Override
            public void run() {
                showMain();
            }
        });
        setContentView(root);
        appsShown = true;
        list.requestFocus();
    }

    private static String describe(Tv.App app) {
        String mark = app.protection != null ? "ЗАЩИЩЕНО: " + app.protection
                : app.state == Tv.State.OFF ? "ОТКЛЮЧИТЬ"
                : app.state == Tv.State.BG ? "ЗАПРЕТИТЬ ФОН" : "ОСТАВИТЬ";
        String name = app.label.equals(app.pkg) ? app.pkg : app.label + "  (" + app.pkg + ")";
        return "[" + mark + "]  " + name + (app.ramMb > 0 ? "  · " + app.ramMb + " МБ" : "");
    }

    private void showMain() {
        setContentView(mainScreen);
        appsShown = false;
        firstButton.requestFocus();
    }

    // ---------- выполнение действий ----------

    private void confirm(String message, final String title, final Job job) {
        new AlertDialog.Builder(this)
                .setMessage(message)
                .setPositiveButton("Да", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        start(title, job);
                    }
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void start(final String title, final Job job) {
        if (busy) {
            toast("Подождите, ещё выполняется предыдущее действие.");
            return;
        }
        busy = true;
        setStatus(title + "...");
        worker.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    job.run(connect());
                    setStatus("Готово: " + title);
                } catch (Exception e) {
                    log("Ошибка: " + explain(e));
                    setStatus("Ошибка: " + title);
                    closeAdb();
                } finally {
                    busy = false;
                }
            }
        });
    }

    private Tv connect() throws IOException {
        if (tv != null) {
            return tv;
        }
        KeyPair keys = AdbClient.loadOrCreateKey(getFilesDir());
        adb = AdbClient.connect("127.0.0.1", ADB_PORT, keys, PROMPT_TIMEOUT_MS, new AdbClient.PromptListener() {
            @Override
            public void onPrompt() {
                log("На экране появился запрос «Разрешить отладку?». Отметьте «Всегда разрешать» и нажмите «ОК».");
            }
        });
        final SharedPreferences prefs = getSharedPreferences("state", MODE_PRIVATE);
        tv = new Tv(adb, new Tv.Store() {
            @Override
            public String get(String key) {
                return prefs.getString(key, null);
            }

            @Override
            public void put(String key, String value) {
                prefs.edit().putString(key, value).apply();
            }
        }, new Tv.Log() {
            @Override
            public void line(String text) {
                log(text);
            }
        }, getPackageName());
        return tv;
    }

    private void closeAdb() {
        tv = null;
        if (adb != null) {
            try {
                adb.close();
            } catch (IOException ignored) {
            }
            adb = null;
        }
    }

    private static String explain(Exception e) {
        if (e instanceof ConnectException) {
            return "нет доступа к отладке. Включите: Настройки → Об устройстве → 7 раз нажмите «Сборка» "
                    + "(или «Версия ПО»), затем Настройки → Для разработчиков → «Отладка по сети» "
                    + "и «Отладка по USB». После этого нажмите любую кнопку ещё раз.";
        }
        if (e instanceof java.net.SocketTimeoutException) {
            return "телевизор не ответил. Если был запрос «Разрешить отладку?», нажмите «ОК» и повторите.";
        }
        return e.getMessage() != null ? e.getMessage() : e.toString();
    }

    // ---------- мелочи интерфейса ----------

    private void log(final String text) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                logView.append(text + "\n");
                logScroll.post(new Runnable() {
                    @Override
                    public void run() {
                        logScroll.fullScroll(View.FOCUS_DOWN);
                    }
                });
            }
        });
    }

    private void setStatus(final String text) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                status.setText(text);
            }
        });
    }

    private void toast(String text) {
        Toast.makeText(this, text, Toast.LENGTH_LONG).show();
    }

    private TextView text(String value, int sp) {
        TextView v = new TextView(this);
        v.setText(value);
        v.setTextSize(sp);
        v.setTextColor(Color.WHITE);
        v.setPadding(0, dp(4), 0, dp(8));
        return v;
    }

    private Button addButton(LinearLayout parent, String label, final Runnable action) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextSize(16);
        b.setAllCaps(false);
        b.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                action.run();
            }
        });
        boolean row = parent.getOrientation() == LinearLayout.HORIZONTAL;
        parent.addView(b, new LinearLayout.LayoutParams(row ? ViewGroup.LayoutParams.WRAP_CONTENT
                : ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return b;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
