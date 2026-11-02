import 'package:flutter/material.dart';
import '../../data/api/dtos/analyze.dart';

/// Interactive draggable & resizable ROI selection overlay.
class RoiSelectionOverlay extends StatefulWidget {
  const RoiSelectionOverlay({
    super.key,
    required this.fittedSize,
    this.initialBBox,
    required this.onChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final Size fittedSize;
  final BBox? initialBBox;
  final ValueChanged<BBox> onChanged;
  final ValueChanged<BBox> onConfirm;
  final VoidCallback onCancel;

  @override
  State<RoiSelectionOverlay> createState() => _RoiSelectionOverlayState();
}

class _RoiSelectionOverlayState extends State<RoiSelectionOverlay> {
  late Rect _rect;

  @override
  void initState() {
    super.initState();
    final init = widget.initialBBox;
    if (init != null) {
      _rect = Rect.fromLTWH(
        init.x * widget.fittedSize.width,
        init.y * widget.fittedSize.height,
        init.w * widget.fittedSize.width,
        init.h * widget.fittedSize.height,
      );
    } else {
      final w = widget.fittedSize.width * 0.5;
      final h = widget.fittedSize.height * 0.5;
      final x = (widget.fittedSize.width - w) / 2;
      final y = (widget.fittedSize.height - h) / 2;
      _rect = Rect.fromLTWH(x, y, w, h);
    }
  }

  BBox get _normalizedBBox {
    final fw = widget.fittedSize.width > 0 ? widget.fittedSize.width : 1.0;
    final fh = widget.fittedSize.height > 0 ? widget.fittedSize.height : 1.0;
    return BBox(
      x: (_rect.left / fw).clamp(0.0, 1.0),
      y: (_rect.top / fh).clamp(0.0, 1.0),
      w: (_rect.width / fw).clamp(0.01, 1.0),
      h: (_rect.height / fh).clamp(0.01, 1.0),
    );
  }

  void _updateRect(Rect next) {
    const minSize = 24.0;
    final clamped = Rect.fromLTRB(
      next.left.clamp(0.0, widget.fittedSize.width - minSize),
      next.top.clamp(0.0, widget.fittedSize.height - minSize),
      next.right.clamp(minSize, widget.fittedSize.width),
      next.bottom.clamp(minSize, widget.fittedSize.height),
    );
    if (clamped.width >= minSize && clamped.height >= minSize) {
      setState(() => _rect = clamped);
      widget.onChanged(_normalizedBBox);
    }
  }

  Widget _buildHandle(
    String id,
    Alignment alignment,
    void Function(Offset delta) onDrag,
  ) {
    const handleSize = 28.0;
    double left = 0;
    double top = 0;

    if (alignment == Alignment.topLeft) {
      left = _rect.left - handleSize / 2;
      top = _rect.top - handleSize / 2;
    } else if (alignment == Alignment.topCenter) {
      left = _rect.center.dx - handleSize / 2;
      top = _rect.top - handleSize / 2;
    } else if (alignment == Alignment.topRight) {
      left = _rect.right - handleSize / 2;
      top = _rect.top - handleSize / 2;
    } else if (alignment == Alignment.centerRight) {
      left = _rect.right - handleSize / 2;
      top = _rect.center.dy - handleSize / 2;
    } else if (alignment == Alignment.bottomRight) {
      left = _rect.right - handleSize / 2;
      top = _rect.bottom - handleSize / 2;
    } else if (alignment == Alignment.bottomCenter) {
      left = _rect.center.dx - handleSize / 2;
      top = _rect.bottom - handleSize / 2;
    } else if (alignment == Alignment.bottomLeft) {
      left = _rect.left - handleSize / 2;
      top = _rect.bottom - handleSize / 2;
    } else if (alignment == Alignment.centerLeft) {
      left = _rect.left - handleSize / 2;
      top = _rect.center.dy - handleSize / 2;
    }

    return Positioned(
      left: left,
      top: top,
      width: handleSize,
      height: handleSize,
      child: GestureDetector(
        key: Key('roi-handle-$id'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.amber,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Semi-transparent box & body drag
        Positioned(
          left: _rect.left,
          top: _rect.top,
          width: _rect.width,
          height: _rect.height,
          child: GestureDetector(
            key: const Key('roi-box'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              final next = _rect.shift(details.delta);
              final maxLeft = widget.fittedSize.width - _rect.width;
              final maxTop = widget.fittedSize.height - _rect.height;
              final clamped = Rect.fromLTWH(
                next.left.clamp(0.0, maxLeft > 0 ? maxLeft : 0.0),
                next.top.clamp(0.0, maxTop > 0 ? maxTop : 0.0),
                _rect.width,
                _rect.height,
              );
              _updateRect(clamped);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                border: Border.all(color: Colors.amber, width: 2),
              ),
            ),
          ),
        ),

        // Corner & Edge Handles
        _buildHandle(
          'tl',
          Alignment.topLeft,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left + d.dx,
              _rect.top + d.dy,
              _rect.right,
              _rect.bottom,
            ),
          ),
        ),
        _buildHandle(
          't',
          Alignment.topCenter,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left,
              _rect.top + d.dy,
              _rect.right,
              _rect.bottom,
            ),
          ),
        ),
        _buildHandle(
          'tr',
          Alignment.topRight,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left,
              _rect.top + d.dy,
              _rect.right + d.dx,
              _rect.bottom,
            ),
          ),
        ),
        _buildHandle(
          'r',
          Alignment.centerRight,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left,
              _rect.top,
              _rect.right + d.dx,
              _rect.bottom,
            ),
          ),
        ),
        _buildHandle(
          'br',
          Alignment.bottomRight,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left,
              _rect.top,
              _rect.right + d.dx,
              _rect.bottom + d.dy,
            ),
          ),
        ),
        _buildHandle(
          'b',
          Alignment.bottomCenter,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left,
              _rect.top,
              _rect.right,
              _rect.bottom + d.dy,
            ),
          ),
        ),
        _buildHandle(
          'bl',
          Alignment.bottomLeft,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left + d.dx,
              _rect.top,
              _rect.right,
              _rect.bottom + d.dy,
            ),
          ),
        ),
        _buildHandle(
          'l',
          Alignment.centerLeft,
          (d) => _updateRect(
            Rect.fromLTRB(
              _rect.left + d.dx,
              _rect.top,
              _rect.right,
              _rect.bottom,
            ),
          ),
        ),

        // Bottom action buttons
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const Key('roi-cancel'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('roi-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => widget.onConfirm(_normalizedBBox),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
