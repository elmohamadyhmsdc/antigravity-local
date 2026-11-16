import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../scaffolds/sheet_scaffold.dart';

/// A collection action asks for shared input once, then processes the snapshot.
class CollectionAction<T> {
  const CollectionAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.destructive = false,
    this.confirmation,
  });

  final String id, label;
  final IconData icon;
  final bool destructive;
  final String? confirmation;
  // False means a picker/confirmation was cancelled: keep the selection.
  final Future<bool> Function(BuildContext context, List<T> items) run;
}

List<CollectionAction<T>> mapCollectionActions<T, U>(
  List<CollectionAction<U>> actions,
  U Function(T) convert,
) => [
  for (final action in actions)
    CollectionAction<T>(
      id: action.id,
      label: action.label,
      icon: action.icon,
      destructive: action.destructive,
      confirmation: action.confirmation,
      run: (context, items) => action.run(context, items.map(convert).toList()),
    ),
];

class BatchActionFailure implements Exception {
  BatchActionFailure(this.failedIds, this.completed, this.error);
  final Set<Object> failedIds;
  final int completed;
  final Object error;

  @override
  String toString() =>
      '$completed completed · ${failedIds.length} failed: $error';
}

/// External operations can partially succeed. Keep only failed items selected.
Future<void> performBatch<T>(
  List<T> items,
  Object Function(T) idOf,
  Future<void> Function(T) action,
) async {
  final failures = <Object>{};
  Object? lastError;
  for (final item in items) {
    try {
      await action(item);
    } catch (error) {
      failures.add(idOf(item));
      lastError = error;
    }
  }
  if (failures.isNotEmpty) {
    throw BatchActionFailure(
      failures,
      items.length - failures.length,
      lastError!,
    );
  }
}

/// Selection is scoped to the displayed collection, including paginated views.
/// Long press opens actions; entering selection never executes an action.
class SelectionCollection<T> extends StatefulWidget {
  const SelectionCollection({
    super.key,
    required this.items,
    required this.idOf,
    required this.actions,
    required this.builder,
    required this.name,
    this.partial = false,
    this.onCompleted,
    this.embedded = false,
    this.onSelectionChanged,
  });

  final List<T> items;
  final Object Function(T) idOf;
  final List<CollectionAction<T>> Function(List<T>) actions;
  final Widget Function(BuildContext, CollectionSelection<T>) builder;
  final String name;
  // "All" never silently means an entire unbounded, unloaded phone library.
  final bool partial;
  final bool embedded;
  final ValueChanged<bool>? onSelectionChanged;
  final Future<void> Function()? onCompleted;

  static CollectionSelection<T> of<T>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CollectionScope<T>>()!.value;

  @override
  State<SelectionCollection<T>> createState() => _SelectionCollectionState<T>();
}

class CollectionSelection<T> {
  CollectionSelection._(this._state);
  final _SelectionCollectionState<T> _state;
  bool get active => _state._active;
  bool get busy => _state._busy;
  bool selected(T item) => _state._ids.contains(_state.widget.idOf(item));
  void toggle(T item) => _state._toggle(item);
  void start(T item) => _state._start(item);

  Future<void> menu(T item, {VoidCallback? onOpen, VoidCallback? onMore}) =>
      _state._menu([item], onOpen: onOpen, onMore: onMore);

  /// Wraps existing cards without replacing their normal controls.
  Widget tile(
    T item, {
    required Widget child,
    VoidCallback? onOpen,
    VoidCallback? onLongPress,
  }) => Semantics(
    selected: active ? selected(item) : null,
    child: GestureDetector(
      key: Key('${_state.widget.name}-item-${_state.widget.idOf(item)}'),
      behavior: HitTestBehavior.opaque,
      onTap: active ? () => toggle(item) : null,
      onLongPress: () => active
          ? toggle(item)
          : onLongPress != null
          ? onLongPress()
          : menu(item, onOpen: onOpen),
      child: Stack(
        children: [
          IgnorePointer(ignoring: active, child: child),
          if (active)
            PositionedDirectional(
              top: 4,
              end: 4,
              child: Material(
                color: Theme.of(_state.context).colorScheme.surface,
                shape: const CircleBorder(),
                child: Checkbox(
                  key: Key(
                    '${_state.widget.name}-check-${_state.widget.idOf(item)}',
                  ),
                  value: selected(item),
                  onChanged: busy ? null : (_) => toggle(item),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _CollectionScope<T> extends InheritedWidget {
  const _CollectionScope({required this.value, required super.child});
  final CollectionSelection<T> value;
  @override
  bool updateShouldNotify(_CollectionScope<T> oldWidget) => true;
}

class _SelectionCollectionState<T> extends State<SelectionCollection<T>> {
  final _ids = <Object>{};
  bool _active = false;
  bool _busy = false;
  String? _running;
  late final _selection = CollectionSelection<T>._(this);
  List<T> get _chosen =>
      widget.items.where((item) => _ids.contains(widget.idOf(item))).toList();

  @override
  void didUpdateWidget(SelectionCollection<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) {
      final available = widget.items.map(widget.idOf).toSet();
      _ids.retainAll(available);
    }
  }

  void _start(T item) {
    if (_busy) return;
    setState(() {
      _active = true;
      _ids.add(widget.idOf(item));
    });
    widget.onSelectionChanged?.call(true);
  }

  void _toggle(T item) {
    if (_busy) return;
    setState(() {
      _active = true;
      final id = widget.idOf(item);
      if (!_ids.remove(id)) _ids.add(id);
    });
    widget.onSelectionChanged?.call(true);
  }

  void _close() {
    setState(() {
      _active = false;
      _ids.clear();
    });
    widget.onSelectionChanged?.call(false);
  }

  void _enter() {
    setState(() => _active = true);
    widget.onSelectionChanged?.call(true);
  }

  Future<void> _run(CollectionAction<T> action, List<T> items) async {
    if (_busy) return;
    final snapshot = List<T>.unmodifiable(items);
    if (action.confirmation != null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${action.label} (${snapshot.length})'),
          content: Text(action.confirmation!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action.label),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _running = action.label;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final completed = await action.run(context, snapshot);
      if (completed) await widget.onCompleted?.call();
      if (mounted && completed) {
        _close();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).bulkCompleted(snapshot.length),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        if (error is BatchActionFailure) {
          try {
            await widget.onCompleted?.call();
          } catch (_) {
            // Keep the actionable failures even when refreshing also fails.
          }
          if (!mounted) return;
          setState(() {
            _active = true;
            _ids
              ..clear()
              ..addAll(error.failedIds);
          });
          widget.onSelectionChanged?.call(true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).peopleActionError('$error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _running = null;
        });
      }
    }
  }

  Future<void> _menu(
    List<T> items, {
    VoidCallback? onOpen,
    VoidCallback? onMore,
  }) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final available = widget.actions(items);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => SheetScaffold(
        title: l.selectedCount(items.length),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOpen != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(l.bulkOpen),
                onTap: () => Navigator.pop(context, 'open'),
              ),
            if (!_active)
              ListTile(
                key: Key('${widget.name}-select-multiple'),
                leading: const Icon(Icons.checklist),
                title: Text(l.peopleAction('selection')),
                onTap: () => Navigator.pop(context, 'select'),
              ),
            for (final action in available)
              ListTile(
                key: Key('${widget.name}-action-${action.id}'),
                leading: Icon(
                  action.icon,
                  color: action.destructive
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(action.label),
                onTap: () => Navigator.pop(context, action.id),
              ),
            if (onMore != null)
              ListTile(
                leading: const Icon(Icons.more_horiz),
                title: Text(l.peopleAction('more')),
                onTap: () => Navigator.pop(context, 'more'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'select') {
      setState(() {
        _active = true;
        _ids.addAll(items.map(widget.idOf));
      });
      widget.onSelectionChanged?.call(true);
    } else if (choice == 'open') {
      onOpen?.call();
    } else if (choice == 'more') {
      onMore?.call();
    } else {
      final action = available
          .where((action) => action.id == choice)
          .firstOrNull;
      if (action != null) await _run(action, items);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_active && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: _CollectionScope<T>(
        value: _selection,
        child: Column(
          children: [
            if (widget.items.isNotEmpty || _active)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (_active) ...[
                      IconButton(
                        key: Key('${widget.name}-selection-close'),
                        tooltip: l.clearSelection,
                        onPressed: _busy ? null : _close,
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text(
                          l.selectedCount(_ids.length),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: Key('${widget.name}-selection-options'),
                        enabled: !_busy,
                        onSelected: (action) => setState(() {
                          final visible = widget.items.map(widget.idOf).toSet();
                          if (action == 'all') {
                            _ids.addAll(visible);
                          }
                          if (action == 'invert') {
                            final next = visible.difference(_ids);
                            _ids
                              ..clear()
                              ..addAll(next);
                          }
                          if (action == 'none') _ids.clear();
                        }),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'all',
                            child: Text(
                              widget.partial
                                  ? l.bulkSelectLoaded(widget.items.length)
                                  : l.selectAll,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'invert',
                            child: Text(l.peopleAction('invert')),
                          ),
                          PopupMenuItem(
                            value: 'none',
                            child: Text(l.clearSelection),
                          ),
                        ],
                        icon: const Icon(Icons.select_all),
                      ),
                    ] else ...[
                      const Spacer(),
                      Flexible(
                        child: TextButton.icon(
                          key: Key('${widget.name}-select'),
                          onPressed: _enter,
                          icon: const Icon(Icons.checklist, size: 18),
                          label: Text(
                            l.peopleAction('selection'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (widget.embedded)
              AbsorbPointer(
                absorbing: _busy,
                child: Builder(
                  builder: (context) => widget.builder(context, _selection),
                ),
              )
            else
              Expanded(
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: Builder(
                    builder: (context) => widget.builder(context, _selection),
                  ),
                ),
              ),
            if (_active || _busy)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _busy
                        ? Semantics(
                            liveRegion: true,
                            child: Row(
                              children: [
                                const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(_running ?? l.reviewSaving),
                                ),
                              ],
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: Key('${widget.name}-actions'),
                              onPressed:
                                  _ids.isEmpty ||
                                      widget.actions(_chosen).isEmpty
                                  ? null
                                  : () => _menu(_chosen),
                              icon: const Icon(Icons.more_horiz),
                              label: Text(l.bulkActions(_ids.length)),
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
