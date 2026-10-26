package com.leorai.tvtuner;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;

import javax.crypto.Cipher;

/**
 * Минимальный клиент протокола ADB. Приложение подключается к adbd самого телевизора
 * (127.0.0.1:5555) и получает те же права, что и компьютер с adb: выполняет shell-команды.
 */
public final class AdbClient implements Closeable {
    private static final int A_CNXN = 0x4e584e43;
    private static final int A_AUTH = 0x48545541;
    private static final int A_OPEN = 0x4e45504f;
    private static final int A_OKAY = 0x59414b4f;
    private static final int A_CLSE = 0x45534c43;
    private static final int A_WRTE = 0x45545257;
    private static final int AUTH_TOKEN = 1;
    private static final int AUTH_SIGNATURE = 2;
    private static final int AUTH_RSAPUBLICKEY = 3;
    private static final int VERSION = 0x01000000;
    private static final int MAX_PAYLOAD = 4096;
    private static final int KEY_BITS = 2048;
    // adbd проверяет подпись токена как подпись SHA-1-хеша, поэтому токен идёт после DigestInfo SHA-1.
    private static final byte[] SHA1_DIGEST_INFO = {
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};

    /** Вызывается, когда на экране ТВ появился запрос «Разрешить отладку?». */
    public interface PromptListener {
        void onPrompt();
    }

    private static final class Message {
        int command, arg0, arg1;
        byte[] data;
    }

    private final Socket socket;
    private final DataInputStream in;
    private final OutputStream out;
    private int nextLocalId = 1;

    private AdbClient(Socket socket) throws IOException {
        this.socket = socket;
        this.in = new DataInputStream(socket.getInputStream());
        this.out = socket.getOutputStream();
    }

    public static AdbClient connect(String host, int port, KeyPair keys, int promptTimeoutMs,
                                    PromptListener listener) throws IOException {
        Socket socket = new Socket();
        try {
            socket.connect(new InetSocketAddress(host, port), 5000);
            socket.setTcpNoDelay(true);
            AdbClient client = new AdbClient(socket);
            client.handshake(keys, promptTimeoutMs, listener);
            return client;
        } catch (IOException | RuntimeException e) {
            socket.close();
            throw e;
        }
    }

    private void handshake(KeyPair keys, int promptTimeoutMs, PromptListener listener) throws IOException {
        socket.setSoTimeout(10000);
        send(A_CNXN, VERSION, MAX_PAYLOAD, "host::\0".getBytes(StandardCharsets.UTF_8));
        boolean sentSignature = false;
        boolean sentKey = false;
        while (true) {
            Message m = read();
            if (m.command == A_CNXN) {
                socket.setSoTimeout(0);  // команды вроде компиляции могут молчать минутами
                return;
            }
            if (m.command != A_AUTH || m.arg0 != AUTH_TOKEN) {
                throw new IOException("неожиданный ответ adbd: " + Integer.toHexString(m.command));
            }
            if (!sentSignature) {
                send(A_AUTH, AUTH_SIGNATURE, 0, sign(keys.getPrivate(), m.data));
                sentSignature = true;
            } else if (!sentKey) {
                // Ключ ещё не разрешён: отправляем его, телевизор покажет запрос пользователю.
                send(A_AUTH, AUTH_RSAPUBLICKEY, 0, publicKeyPayload((RSAPublicKey) keys.getPublic(), "tvtuner@tv"));
                sentKey = true;
                socket.setSoTimeout(promptTimeoutMs);
                if (listener != null) {
                    listener.onPrompt();
                }
            } else {
                throw new IOException("подключение отклонено на телевизоре");
            }
        }
    }

    /** Выполняет команду в shell телевизора и возвращает её вывод (stdout и stderr вместе). */
    public synchronized String shell(String command) throws IOException {
        return service("shell:" + command);
    }

    public synchronized String service(String name) throws IOException {
        int localId = nextLocalId++;
        send(A_OPEN, localId, 0, (name + "\0").getBytes(StandardCharsets.UTF_8));
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        int remoteId = 0;
        while (true) {
            Message m = read();
            if (m.arg1 != localId) {
                continue;  // хвосты прошлых потоков
            }
            if (m.command == A_OKAY) {
                remoteId = m.arg0;
            } else if (m.command == A_WRTE) {
                remoteId = m.arg0;
                result.write(m.data);
                send(A_OKAY, localId, remoteId, new byte[0]);
            } else if (m.command == A_CLSE) {
                if (remoteId != 0) {
                    send(A_CLSE, localId, remoteId, new byte[0]);
                }
                return new String(result.toByteArray(), StandardCharsets.UTF_8);
            }
        }
    }

    @Override
    public void close() throws IOException {
        socket.close();
    }

    private Message read() throws IOException {
        byte[] header = new byte[24];
        in.readFully(header);
        ByteBuffer b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        Message m = new Message();
        m.command = b.getInt();
        m.arg0 = b.getInt();
        m.arg1 = b.getInt();
        int length = b.getInt();
        b.getInt();  // контрольная сумма
        if ((m.command ^ 0xffffffff) != b.getInt() || length < 0 || length > (1 << 20)) {
            throw new IOException("повреждённый пакет ADB");
        }
        m.data = new byte[length];
        in.readFully(m.data);
        return m;
    }

    private void send(int command, int arg0, int arg1, byte[] data) throws IOException {
        int checksum = 0;
        for (byte x : data) {
            checksum += x & 0xff;
        }
        ByteBuffer b = ByteBuffer.allocate(24 + data.length).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(command).putInt(arg0).putInt(arg1).putInt(data.length).putInt(checksum)
                .putInt(command ^ 0xffffffff).put(data);
        synchronized (out) {
            out.write(b.array());
            out.flush();
        }
    }

    static byte[] sign(PrivateKey key, byte[] token) throws IOException {
        try {
            Cipher cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
            cipher.init(Cipher.ENCRYPT_MODE, key);
            cipher.update(SHA1_DIGEST_INFO);
            return cipher.doFinal(token);
        } catch (GeneralSecurityException e) {
            throw new IOException("не удалось подписать токен ADB", e);
        }
    }

    /** Открытый ключ в формате Android (android_pubkey), base64 + имя, как в файле adbkey.pub. */
    static byte[] publicKeyPayload(RSAPublicKey key, String name) {
        BigInteger n = key.getModulus();
        BigInteger r32 = BigInteger.ONE.shiftLeft(32);
        BigInteger n0inv = n.mod(r32).modInverse(r32).negate().mod(r32);
        BigInteger rr = BigInteger.ONE.shiftLeft(KEY_BITS).modPow(BigInteger.valueOf(2), n);
        ByteBuffer b = ByteBuffer.allocate(4 + 4 + KEY_BITS / 8 * 2 + 4).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(KEY_BITS / 32).putInt(n0inv.intValue());
        putLittleEndian(b, n);
        putLittleEndian(b, rr);
        b.putInt(key.getPublicExponent().intValue());
        String text = Base64.getEncoder().encodeToString(b.array()) + " " + name + "\0";
        return text.getBytes(StandardCharsets.UTF_8);
    }

    private static void putLittleEndian(ByteBuffer b, BigInteger value) {
        byte[] be = value.toByteArray();
        for (int i = 0; i < KEY_BITS / 8; i++) {
            b.put(i < be.length ? be[be.length - 1 - i] : 0);
        }
    }

    /** Ключ храним в папке приложения: тогда «Всегда разрешать» на ТВ срабатывает и в следующий раз. */
    public static KeyPair loadOrCreateKey(File dir) throws IOException {
        File priv = new File(dir, "adbkey");
        File pub = new File(dir, "adbkey.pub");
        try {
            KeyFactory factory = KeyFactory.getInstance("RSA");
            if (priv.isFile() && pub.isFile()) {
                return new KeyPair(factory.generatePublic(new X509EncodedKeySpec(readAll(pub))),
                        factory.generatePrivate(new PKCS8EncodedKeySpec(readAll(priv))));
            }
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(KEY_BITS);
            KeyPair keys = generator.generateKeyPair();
            writeAll(priv, keys.getPrivate().getEncoded());
            writeAll(pub, keys.getPublic().getEncoded());
            return keys;
        } catch (GeneralSecurityException e) {
            throw new IOException("не удалось создать ключ ADB", e);
        }
    }

    private static byte[] readAll(File file) throws IOException {
        byte[] data = new byte[(int) file.length()];
        try (DataInputStream s = new DataInputStream(new FileInputStream(file))) {
            s.readFully(data);
        }
        return data;
    }

    private static void writeAll(File file, byte[] data) throws IOException {
        try (FileOutputStream s = new FileOutputStream(file)) {
            s.write(data);
        }
    }
}
