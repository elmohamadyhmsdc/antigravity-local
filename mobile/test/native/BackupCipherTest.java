import com.antigravity.antigravity_mobile.BackupCipher;
import java.nio.file.*;
import java.util.Arrays;

/** Runs on the local JDK; no Android device or third-party libraries required. */
public class BackupCipherTest {
    private static final String PASSWORD = "backup password for tests only";
    private static int cases;
    private static void require(boolean value) { if (!value) throw new AssertionError(); }
    private static void reject(Path input, Path target, String password) throws Exception {
        boolean failed = false;
        try { BackupCipher.transform(input.toFile(), target.toFile(), password.toCharArray(), false); }
        catch (java.io.IOException | java.security.GeneralSecurityException expected) { failed = true; }
        require(failed && !Files.exists(target));
        cases++;
    }
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory(Path.of(args[0]), "cipher-");
        for (int length : new int[] {0, 1, 1024 * 1024, 2 * 1024 * 1024 + 123}) {
            byte[] original = new byte[length];
            for (int i = 0; i < length; i++) original[i] = (byte) (i * 31);
            Path source = root.resolve("plain-" + length), encrypted = root.resolve("encrypted-" + length), restored = root.resolve("restored-" + length);
            Files.write(source, original);
            BackupCipher.transform(source.toFile(), encrypted.toFile(), PASSWORD.toCharArray(), true);
            BackupCipher.transform(encrypted.toFile(), restored.toFile(), PASSWORD.toCharArray(), false);
            require(Arrays.equals(original, Files.readAllBytes(restored)));
            cases++;
        }
        Path valid = root.resolve("encrypted-2097275");
        byte[] bytes = Files.readAllBytes(valid);
        reject(valid, root.resolve("wrong-password"), "a different password");
        for (int position : new int[] {0, 20, 35, 44, bytes.length - 1}) {
            byte[] changed = bytes.clone(); changed[position] ^= 1;
            Path damaged = root.resolve("damaged-" + position); Files.write(damaged, changed);
            reject(damaged, root.resolve("bad-" + position), PASSWORD);
        }
        for (int size : new int[] {10, 40, bytes.length - 1, bytes.length - 20}) {
            Path truncated = root.resolve("truncated-" + size); Files.write(truncated, Arrays.copyOf(bytes, size));
            reject(truncated, root.resolve("short-" + size), PASSWORD);
        }
        Path appended = root.resolve("appended"); Files.write(appended, Arrays.copyOf(bytes, bytes.length + 1));
        reject(appended, root.resolve("trailing"), PASSWORD);
        Path another = root.resolve("another");
        BackupCipher.transform(root.resolve("plain-2097275").toFile(), another.toFile(), PASSWORD.toCharArray(), true);
        require(!Arrays.equals(bytes, Files.readAllBytes(another))); cases++;
        require(Files.list(root).noneMatch(p -> p.getFileName().toString().endsWith(".part")));
        // Preserve one vector for the independent Python AES-GCM verifier.
        System.out.println("Native backup cipher: " + cases + " cases passed. Vector directory: " + root);
    }
}
