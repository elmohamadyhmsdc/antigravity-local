import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'activity_pill.dart';

/// Observer that tracks whether any [PopupRoute] (dialog, bottom sheet, popup menu) is active.
class AppPopupObserver extends NavigatorObserver {
  AppPopupObserver({this.onPopupChanged});

  final VoidCallback? onPopupChanged;
  int _popupCount = 0;

  bool get hasPopup => _popupCount > 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popupCount++;
      onPopupChanged?.call();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popupCount = (_popupCount - 1).clamp(0, 9999);
      onPopupChanged?.call();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popupCount = (_popupCount - 1).clamp(0, 9999);
      onPopupChanged?.call();
    }
  }
}

/// Global host for [ActivityPill] on interior screens, placed below [child]
/// and above any bottom padding. Automatically hides itself on root tab screens
/// (which are handled directly by AppShell), onboarding, viewers, flows,
/// and when the on-screen keyboard is open.
class ActivityPillHost extends StatefulWidget {
  const ActivityPillHost({
    super.key,
    required this.child,
    this.router,
    this.popupObserver,
  });

  final Widget child;
  final GoRouter? router;
  final AppPopupObserver? popupObserver;

  @override
  State<ActivityPillHost> createState() => _ActivityPillHostState();
}

class _ActivityPillHostState extends State<ActivityPillHost> {
  @override
  void initState() {
    super.initState();
    widget.router?.routerDelegate.addListener(_handleStateChange);
  }

  @override
  void didUpdateWidget(covariant ActivityPillHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router?.routerDelegate.removeListener(_handleStateChange);
      widget.router?.routerDelegate.addListener(_handleStateChange);
    }
  }

  @override
  void dispose() {
    widget.router?.routerDelegate.removeListener(_handleStateChange);
    super.dispose();
  }

  void _handleStateChange() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  bool _shouldShowPill(BuildContext context) {
    // 1. Keyboard open
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight > 0) return false;

    // 2. Route check
    final path = widget.router?.routerDelegate.currentConfiguration.uri.path;
    if (path == null) return true;

    // Root tabs (AppShell handles them directly)
    if (path == '/' ||
        path == '/library' ||
        path == '/people' ||
        path == '/explore' ||
        path == '/discover' ||
        path == '/studio') {
      return false;
    }

    // Onboarding
    if (path == '/welcome' ||
        path == '/pair' ||
        path.startsWith('/pair/') ||
        path == '/permissions') {
      return false;
    }

    // Viewer
    if (path.startsWith('/media')) {
      return false;
    }

    // Activity center itself
    if (path == '/activity' ||
        path.startsWith('/activity/') ||
        path == '/jobs' ||
        path.startsWith('/jobs/')) {
      return false;
    }

    // Flows
    if (path == '/studio/reface' ||
        path == '/studio/generate' ||
        path == '/studio/train' ||
        path == '/studio/datasets/new' ||
        path == '/restyle' ||
        path == '/merge' ||
        path.startsWith('/merge/')) {
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final showPill = _shouldShowPill(context);
    final hasPopup = widget.popupObserver?.hasPopup ?? false;

    if (!showPill) {
      return widget.child;
    }

    return Column(
      children: [
        Expanded(child: widget.child),
        ActivityPill(
          enabled: !hasPopup,
          onTap: () {
            if (widget.router != null) {
              widget.router!.push('/activity');
            } else {
              GoRouter.of(context).push('/activity');
            }
          },
        ),
      ],
    );
  }
}
