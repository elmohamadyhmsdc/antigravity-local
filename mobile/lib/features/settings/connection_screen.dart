import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/api_exception.dart';
import '../../data/platform/lan_network.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../onboarding/pairing_controller.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});
  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen>
    with WidgetsBindingObserver {
  final _host = TextEditingController(),
      _port = TextEditingController(text: '8443');
  List<LanInterface> _interfaces = const [];
  List<LanEndpoint> _found = const [];
  var _busy = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    final saved = ref.read(sessionProvider);
    _host.text = saved?.host ?? '';
    _port.text = '${saved?.port ?? 8443}';
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rows = await ref.read(lanNetworkProvider).interfaces();
      if (mounted) setState(() => _interfaces = rows);
    } on Object {
      /* Diagnostics remain available without interface access. */
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).connectionFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(LanEndpoint endpoint) async {
    final saved = ref.read(sessionProvider);
    if (saved == null) {
      if (mounted) {
        context.push(
          Uri(
            path: Routes.manual,
            queryParameters: {
              'host': endpoint.host,
              'port': '${endpoint.port}',
            },
          ).toString(),
        );
      }
      return;
    }
    final verified = await ref.read(endpointVerifierProvider)(saved, endpoint);
    final moved = await ref
        .read(sessionProvider.notifier)
        .relocate(saved, verified.session);
    if (!mounted) return;
    if (!moved) {
      throw ApiException.badResponse(
        'The pairing changed; check the current PC again.',
      );
    }
    _host.text = endpoint.host;
    _port.text = '${endpoint.port}';
    ref.invalidate(serverStatusProvider);
    setState(() => _notice = AppLocalizations.of(context).connectionRestored);
  }

  Future<void> _find() => _run(() async {
    await _refresh();
    final saved = ref.read(sessionProvider);
    final found = await ref
        .read(lanNetworkProvider)
        .discover(serverId: saved?.serverId);
    if (!mounted) return;
    setState(() => _found = found);
    if (found.isEmpty) {
      setState(
        () => _notice = AppLocalizations.of(context).connectionNothingFound,
      );
    } else if (saved != null) {
      for (final endpoint in found) {
        try {
          await _connect(endpoint);
          return;
        } on ApiException catch (error) {
          if (error.isUnauthorized) rethrow;
        }
      }
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).connectionVerifyFailed,
        );
      }
    }
  });
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final saved = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.connectionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.connectionIntro),
          const SizedBox(height: 16),
          if (saved != null)
            Text(
              '${saved.name} · ${saved.host}:${saved.port}',
              key: const Key('connection-current'),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('connection-find'),
            onPressed: _busy ? null : _find,
            icon: const Icon(Icons.search),
            label: Text(l.connectionFind),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                key: const Key('connection-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_notice!),
            ),
          for (final endpoint in _found)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                endpoint.name ?? endpoint.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(endpoint.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _run(() => _connect(endpoint)),
            ),
          const Divider(height: 32),
          TextField(
            controller: _host,
            key: const Key('connection-host'),
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.manualHostLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            key: const Key('connection-port'),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.manualPortLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('connection-test'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    if (validateHost(_host.text) != null ||
                        validatePort(_port.text) != null) {
                      throw ApiException.badResponse(
                        l.connectionInvalidAddress,
                      );
                    }
                    await _connect(
                      LanEndpoint(
                        _host.text.trim(),
                        int.parse(_port.text.trim()),
                      ),
                    );
                  }),
            child: Text(
              saved == null ? l.connectionPairAtAddress : l.connectionTest,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.connectionPhoneAddresses,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_interfaces.isEmpty) Text(l.connectionNoLan),
          for (final interface in _interfaces)
            Text('${interface.address}/${interface.prefix}'),
          const SizedBox(height: 24),
          Text(
            l.connectionPhoneHotspotTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l.connectionPhoneHotspot),
          const SizedBox(height: 16),
          Text(
            l.connectionPcHotspotTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l.connectionPcHotspot),
          const SizedBox(height: 16),
          Text(
            l.connectionRouterTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l.connectionRouter),
          const SizedBox(height: 16),
          Text(
            l.connectionUsbTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l.connectionUsb),
          const SizedBox(height: 8),
          SelectableText(
            'adb reverse tcp:${saved?.port ?? 8443} tcp:${saved?.port ?? 8443}',
          ),
          const SizedBox(height: 16),
          Text(
            l.connectionPinSafety,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
