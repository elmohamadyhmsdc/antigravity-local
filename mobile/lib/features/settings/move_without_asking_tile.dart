import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/media_organizer.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';

/// One switch in Android's settings decides whether organizing a big library needs a human: with "All files
/// access" granted, person folders live in the top-level "Your Gallery" folder (outside DCIM), each photo's
/// .json is written beside it and photos move with no sheet at all, also in the background. This shows its
/// state and opens that page.
class MoveWithoutAskingTile extends ConsumerStatefulWidget {
  const MoveWithoutAskingTile({super.key});

  @override
  ConsumerState<MoveWithoutAskingTile> createState() =>
      _MoveWithoutAskingTileState();
}

class _MoveWithoutAskingTileState extends ConsumerState<MoveWithoutAskingTile>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(); // back from the system page
    }
  }

  Future<void> _refresh() async {
    final bridge = ref.read(mediaOrganizerBridgeProvider);
    final granted = bridge is AndroidMediaOrganizer
        ? await bridge.hasAllFilesAccess()
        : true;
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final granted = _granted ?? false;
    return ListTile(
      key: const Key('settings-move-without-asking'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        granted ? Icons.check_circle_outline : Icons.shield_outlined,
      ),
      title: Text(l10n.moveWithoutAskingTitle),
      subtitle: Text(
        granted ? l10n.moveWithoutAskingOn : l10n.moveWithoutAskingOff,
      ),
      onTap: granted
          ? null
          : () async {
              final bridge = ref.read(mediaOrganizerBridgeProvider);
              if (bridge is AndroidMediaOrganizer) {
                await bridge.requestAllFilesAccess();
              }
            },
    );
  }
}
