import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/app_database.dart';
import '../../data/index/index_loader.dart';
import '../../data/repositories/app_settings.dart';
import '../../domain/backup/backup_service.dart';
import '../../data/platform/backup_crypto.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/empty_state.dart';
import 'password_dialog.dart';

/// S26 - the phone holds the ONLY copy of the library, so this is where it is protected: export one
/// `.agbackup` file (share sheet / Files), restore it later, replacing the library.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  BackupProgress? _progress;
  String? _message;
  var _busy = false;
  var _encrypt = true;

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final encrypted = _encrypt;
    final password = encrypted
        ? await backupPassword(context, creating: true)
        : null;
    if (!mounted || (encrypted && password == null)) return;
    final service = ref.read(backupServiceProvider);
    final settings = ref.read(appSettingsProvider);
    final tracker = ref.read(jobTrackerProvider);
    final engine = ref.read(scanEngineProvider);
    final scanWasRunning = engine.isRunning;
    bool? wasActive;
    File? plaintext;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await engine.pauseAndWait();
      wasActive = await tracker.suspendForMaintenance();
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/backups');
      if (await dir.exists()) await dir.delete(recursive: true);
      var file = await service.export(
        dir,
        recordBackup: false,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (encrypted) {
        plaintext = file;
        final target = File(
          '${file.path.substring(0, file.path.length - backupExtension.length)}encrypted.$backupExtension',
        );
        if (mounted) {
          setState(() => _progress = const BackupProgress('encrypting', 0, 0));
        }
        await ref.read(backupCryptoProvider).encrypt(file, target, password!);
        file = target;
        await plaintext.delete();
        plaintext = null;
      }
      if (!mounted) return;
      final shared = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: l10n.backupShareSubject,
        ),
      );
      if (shared.status == ShareResultStatus.dismissed) {
        if (mounted) setState(() => _message = l10n.backupShareCancelled);
      } else {
        await settings.setLastBackupAt(DateTime.now());
        if (mounted) setState(() => _message = l10n.backupDone);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _message = l10n.backupFailed('$e'));
    } finally {
      try {
        if (plaintext != null && await plaintext.exists()) {
          await plaintext.delete();
        }
      } finally {
        if (wasActive != null) tracker.resumeAfterMaintenance(wasActive);
        if (scanWasRunning) unawaited(engine.start(enumerate: false));
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
      }
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(backupServiceProvider);
    final tracker = ref.read(jobTrackerProvider);
    bool? wasActive;
    final picked = await FilePicker.pickFile(
      dialogTitle: l10n.restoreFromBackup,
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    var file = File(path);
    Directory? decrypted;
    try {
      if (await AndroidBackupCrypto.isEncrypted(file)) {
        if (!mounted) return;
        final password = await backupPassword(context, creating: false);
        if (password == null || !mounted) return;
        setState(() {
          _busy = true;
          _progress = const BackupProgress('decrypting', 0, 0);
        });
        decrypted = await (await getTemporaryDirectory()).createTemp(
          'ag-restore-',
        );
        // File pickers can return external paths; native crypto accepts private files only.
        final encryptedInput = await file.copy(
          '${decrypted.path}/encrypted.agbackup',
        );
        final target = File('${decrypted.path}/backup.zip');
        await ref
            .read(backupCryptoProvider)
            .decrypt(encryptedInput, target, password);
        file = target;
      }
      final info = await service.inspect(file);
      if (!mounted) return;
      final ok = await confirm(
        context,
        title: l10n.restoreConfirmTitle,
        body: l10n.restoreConfirmBody(
          DateFormat.yMMMd().add_Hm().format(info.createdAt),
          info.people,
          info.faces,
          info.photos,
        ),
        confirmLabel: l10n.restore,
        cancelLabel: l10n.cancel,
        destructive: true,
      );
      if (!ok || !mounted) return;
      setState(() {
        _busy = true;
        _message = null;
      });
      final engine = ref.read(scanEngineProvider);
      await engine.pauseAndWait();
      wasActive = await tracker.suspendForMaintenance();
      await service.restore(
        file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // everything on screen was read from the old library
      final index = ref.read(embeddingIndexProvider);
      if (index is LazyEmbeddingIndex) await index.reload();
      ref.invalidate(peopleProvider);
      if (mounted) {
        setState(() => _message = l10n.restoreDone(info.people, info.faces));
      }
    } on BackupException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _message = l10n.backupFailed('$e'));
    } finally {
      try {
        if (decrypted != null && await decrypted.exists()) {
          await decrypted.delete(recursive: true);
        }
      } finally {
        if (wasActive != null) tracker.resumeAfterMaintenance(wasActive);
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final stats = ref.watch(libraryStatsProvider).value ?? const LibraryStats();
    final last = settings.lastBackupAt;
    final text = Theme.of(context).textTheme;
    final progress = _progress;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.backupIntro, style: text.bodyMedium),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const Key('last-backup'),
              leading: Icon(
                last == null && !stats.isEmpty
                    ? Icons.warning_amber_rounded
                    : Icons.event_available,
              ),
              title: Text(
                last == null
                    ? l10n.neverBackedUp
                    : l10n.lastBackup(DateFormat.yMMMd().add_Hm().format(last)),
              ),
              subtitle: Text(
                l10n.backupLibrarySummary(
                  stats.people,
                  stats.faces,
                  stats.photos,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('backup-encryption'),
            contentPadding: EdgeInsets.zero,
            value: _encrypt,
            title: Text(l10n.backupEncryption),
            subtitle: Text(
              _encrypt ? l10n.backupEncryptionHint : l10n.backupPlaintextHint,
            ),
            onChanged: _busy ? null : (v) => setState(() => _encrypt = v),
          ),
          FilledButton.icon(
            key: const Key('backup-export'),
            icon: const Icon(Icons.upload_file),
            label: Text(l10n.backupNow),
            onPressed: _busy || stats.isEmpty ? null : _export,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('backup-restore'),
            icon: const Icon(Icons.download),
            label: Text(l10n.restoreFromBackup),
            onPressed: _busy ? null : _restore,
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress.total > 0 ? progress.done / progress.total : null,
            ),
            const SizedBox(height: 6),
            Text(switch (progress.stage) {
              'database' => l10n.backupStageDatabase,
              'crops' => l10n.backupStageCrops,
              'restoring' => l10n.backupStageRestoring,
              'encrypting' => l10n.backupStageEncrypting,
              'decrypting' => l10n.backupStageDecrypting,
              _ => l10n.backupStageFinishing,
            }, style: text.bodySmall),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              key: const Key('backup-message'),
              style: text.bodyMedium,
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.backupWhatIsIncluded, style: text.titleSmall),
          const SizedBox(height: 4),
          Text(l10n.backupWhatIsIncludedBody, style: text.bodySmall),
          const SizedBox(height: 12),
          Text(l10n.backupKeepSafe, style: text.bodySmall),
        ],
      ),
    );
  }
}
