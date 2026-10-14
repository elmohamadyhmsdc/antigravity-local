import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'library_providers.dart';
import 'providers.dart';

/// Where the app opens (null = Home when paired, Welcome otherwise). Tests start on a link.
final initialLocationProvider = Provider<String?>((ref) => null);

/// The router follows the session: pairing moves on to the permissions screen, forgetting the
/// PC (or a revoked pairing) returns to Welcome.
final routerProvider = Provider<GoRouter>((ref) {
  final paired = ValueNotifier<bool>(ref.read(sessionProvider) != null);
  ref.listen(sessionProvider, (_, next) => paired.value = next != null);
  final router = createRouter(
    isPaired: () => paired.value,
    refresh: paired,
    initialLocation: ref.read(initialLocationProvider),
  );
  ref.onDispose(() {
    router.dispose();
    paired.dispose();
  });
  return router;
});

/// Whether a scan that was running when the app died resumes by itself at start-up (tests turn it off).
final autoResumeScanProvider = Provider<bool>((ref) => true);

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    if (ref.read(autoResumeScanProvider)) {
      // a scan is persistent: if the app was killed mid-scan, carry on where it stopped
      Future<void>.microtask(() {
        if (mounted && ref.read(sessionProvider) != null) {
          ref.read(scanEngineProvider).resumeIfInterrupted();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

/// Shown instead of the app when the encrypted database cannot be opened (never silently
/// falls back to an unencrypted or empty database - that would hide data loss).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.startupErrorTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.startupErrorBody),
                    const SizedBox(height: 12),
                    SelectableText('$error', key: const Key('startup-error')),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
