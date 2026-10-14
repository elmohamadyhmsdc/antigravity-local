import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/privacy_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

final privacyServiceProvider = Provider<PrivacyService>(
  (ref) => const AndroidPrivacyService(),
);
final appLockEnabledProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals('privacy.app_lock')))
      .watchSingleOrNull()
      .map((row) => row?.value == 'true');
});

class LockSession extends Notifier<bool> {
  @override
  bool build() => false;
  void unlock() => state = true;
  void lock() => state = false;
}

final lockSessionProvider = NotifierProvider<LockSession, bool>(
  LockSession.new,
);

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_busy &&
        mounted) {
      ref.read(lockSessionProvider.notifier).lock();
    }
  }

  Future<void> _unlock() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref
          .read(privacyServiceProvider)
          .authenticate(l.appLockTitle, l.unlockBody);
      if (mounted) {
        if (ok) ref.read(lockSessionProvider.notifier).unlock();
        setState(() => _error = ok ? null : l.unlockFailed);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(appLockEnabledProvider);
    final l = AppLocalizations.of(context);
    final locked =
        setting.isLoading ||
        setting.hasError ||
        (setting.value == true && !ref.watch(lockSessionProvider));
    return Stack(
      children: [
        Offstage(offstage: locked, child: widget.child),
        if (locked)
          Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        l.appLockTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_error != null) Text(_error!),
                      if (setting.hasError) Text('${setting.error}'),
                      const SizedBox(height: 16),
                      if (setting.isLoading)
                        const CircularProgressIndicator()
                      else
                        FilledButton(
                          key: const Key('unlock-app'),
                          onPressed: _busy ? null : _unlock,
                          child: Text(l.unlockApp),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Route leases keep FLAG_SECURE enabled while any private viewer remains mounted.
class SensitiveSurface extends ConsumerStatefulWidget {
  const SensitiveSurface({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SensitiveSurface> createState() => _SensitiveSurfaceState();
}

class _SensitiveSurfaceState extends ConsumerState<SensitiveSurface> {
  static int _leases = 0;
  late final PrivacyService _service;
  @override
  void initState() {
    super.initState();
    _service = ref.read(privacyServiceProvider);
    _leases++;
    _service.secure(true);
  }

  @override
  void dispose() {
    _leases--;
    if (_leases == 0) _service.secure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
