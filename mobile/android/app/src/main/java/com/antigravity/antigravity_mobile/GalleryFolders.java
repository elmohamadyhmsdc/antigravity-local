package com.antigravity.antigravity_mobile;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

/** Shared-storage roots created by the gallery organizer. The roots themselves stay in place. */
final class GalleryFolders {
    private final List<File> roots = new ArrayList<>(2);

    GalleryFolders(File volume) {
        File parent = canonical(volume);
        if (parent != null) {
            roots.add(new File(parent, "Your Gallery"));
            roots.add(new File(parent, "DCIM/Your Gallery"));
        }
    }

    int pruneEmpty() {
        int removed = 0;
        for (File root : roots) {
            if (!isRealDirectory(root)) continue;
            List<File> folders = new ArrayList<>();
            folders.add(root);
            for (int i = 0; i < folders.size(); i++) {
                File folder = folders.get(i);
                File[] children = isRealDirectory(folder) ? folder.listFiles() : null;
                if (children == null) continue;
                for (File child : children) {
                    if (isRealDirectory(child)) folders.add(child);
                }
            }
            // Descendants were appended after their parents. Removing them first can empty a parent.
            for (int i = folders.size() - 1; i > 0; i--) {
                if (removeEmptyDirectory(folders.get(i))) removed++;
            }
        }
        return removed;
    }

    void pruneVacated(File folder) {
        File root = containingRoot(folder);
        if (root == null) return;
        while (!root.equals(folder) && removeEmptyDirectory(folder)) {
            folder = folder.getParentFile();
        }
    }

    boolean contains(File folder) {
        return containingRoot(folder) != null;
    }

    private File containingRoot(File folder) {
        if (!isRealDirectory(folder)) return null;
        for (File root : roots) {
            if (folder.toPath().startsWith(root.toPath())) return root;
        }
        return null;
    }

    private static boolean isRealDirectory(File folder) {
        return folder != null && folder.isDirectory() && folder.equals(canonical(folder));
    }

    private static boolean removeEmptyDirectory(File folder) {
        if (!isRealDirectory(folder)) return false;
        try {
            // Nonrecursive removal fails if the directory contains a file, even one just added.
            return Files.deleteIfExists(folder.toPath());
        } catch (IOException | SecurityException error) {
            return false;
        }
    }

    private static File canonical(File file) {
        try {
            return file.getCanonicalFile();
        } catch (IOException | SecurityException error) {
            return null;
        }
    }
}
