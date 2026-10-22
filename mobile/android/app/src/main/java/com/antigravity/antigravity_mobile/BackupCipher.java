package com.antigravity.antigravity_mobile;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;

/** Versioned streaming backup envelope; uses only platform JCA primitives.
 * Each <=1 MiB record authenticates the header, index and length. An authenticated
 * empty final record detects truncation, including deletion of complete records.
 * No output is published until the entire input has been verified.
 */
public final class BackupCipher {
    private static final byte[] MAGIC = {'A','G','B','A','K','0','2','\n'};
    private static final int ITERATIONS = 600_000;
    private static final int CHUNK = 1024 * 1024;
    private static final int HEADER = 40; // magic + iterations + chunk + salt16 + nonce prefix8
    private static final long MAX_RECORDS = 65_536; // <=64 GiB, unique per-file nonces

    private BackupCipher() {}

    public static void transform(File source, File target, char[] password, boolean encrypt)
            throws IOException, GeneralSecurityException {
        if (password.length < 12 || password.length > 1024) {
            throw new GeneralSecurityException("Use 12–1024 characters.");
        }
        if (source.getCanonicalFile().equals(target.getCanonicalFile()) || target.exists()) {
            throw new IOException("Choose a new output file.");
        }
        final File parent = target.getCanonicalFile().getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Output directory is unavailable.");
        }
        File partial = File.createTempFile("ag-backup-", ".part", parent);
        byte[] key = null;
        try (DataInputStream input = new DataInputStream(new BufferedInputStream(new FileInputStream(source)))) {
            byte[] header;
            if (encrypt) {
                byte[] salt = new byte[16], prefix = new byte[8];
                SecureRandom random = new SecureRandom();
                random.nextBytes(salt);
                random.nextBytes(prefix);
                header = ByteBuffer.allocate(HEADER).put(MAGIC).putInt(ITERATIONS)
                        .putInt(CHUNK).put(salt).put(prefix).array();
            } else {
                header = new byte[HEADER];
                input.readFully(header);
                ByteBuffer fields = ByteBuffer.wrap(header);
                byte[] magic = new byte[MAGIC.length];
                fields.get(magic);
                if (!Arrays.equals(magic, MAGIC) || fields.getInt() != ITERATIONS || fields.getInt() != CHUNK) {
                    throw new GeneralSecurityException("Unsupported backup format.");
                }
            }
            PBEKeySpec spec = new PBEKeySpec(password, Arrays.copyOfRange(header, 16, 32), ITERATIONS, 256);
            try {
                key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            } finally { spec.clearPassword(); }
            try (FileOutputStream disk = new FileOutputStream(partial);
                 DataOutputStream output = new DataOutputStream(new BufferedOutputStream(disk))) {
                if (encrypt) output.write(header);
                boolean ended = false;
                byte[] plain = new byte[CHUNK];
                for (long index = 0; index <= MAX_RECORDS; index++) {
                    int size;
                    byte[] data;
                    if (encrypt) {
                        size = 0;
                        while (size < CHUNK) {
                            int n = input.read(plain, size, CHUNK - size);
                            if (n < 0) break;
                            size += n;
                        }
                        data = plain;
                    } else {
                        size = input.readInt();
                        if (size < 0 || size > CHUNK) throw new GeneralSecurityException("Invalid backup record.");
                        data = new byte[size + 16];
                        input.readFully(data);
                    }
                    if (index == MAX_RECORDS && size != 0) throw new IOException("Backup exceeds 64 GiB.");
                    byte[] nonce = ByteBuffer.allocate(12).put(header, 32, 8).putInt((int) index).array();
                    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                    cipher.init(encrypt ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE,
                            new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
                    cipher.updateAAD(header);
                    cipher.updateAAD(ByteBuffer.allocate(8).putInt((int) index).putInt(size).array());
                    byte[] converted = cipher.doFinal(data, 0, encrypt ? size : data.length);
                    if (encrypt) output.writeInt(size);
                    output.write(converted);
                    Arrays.fill(converted, (byte) 0);
                    if (size == 0) {
                        if (!encrypt && input.read() != -1) throw new GeneralSecurityException("Unexpected trailing data.");
                        ended = true;
                        break;
                    }
                }
                Arrays.fill(plain, (byte) 0);
                if (!ended) throw new GeneralSecurityException("Incomplete backup.");
                output.flush();
                disk.getFD().sync();
            }
            Files.move(partial.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE);
        } finally {
            if (key != null) Arrays.fill(key, (byte) 0);
            Arrays.fill(password, '\0');
            Files.deleteIfExists(partial.toPath());
        }
    }
}
