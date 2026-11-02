import 'package:flutter/material.dart';

class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
    this.initialPosition = 0.5,
    this.beforeLabel = 'Before',
    this.afterLabel = 'After',
    this.showLabels = true,
    this.showSliderControl = true,
  });

  final Widget before;
  final Widget after;
  final double initialPosition;
  final String beforeLabel;
  final String afterLabel;
  final bool showLabels;
  final bool showSliderControl;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  late double _position;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition.clamp(0.0, 1.0);
  }

  void _handleDrag(DragUpdateDetails details, BoxConstraints constraints) {
    if (constraints.maxWidth <= 0) return;
    setState(() {
      _position = (_position + details.delta.dx / constraints.maxWidth).clamp(
        0.0,
        1.0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final splitX = width * _position;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onHorizontalDragUpdate: (d) => _handleDrag(d, constraints),
              child: Stack(
                children: [
                  // After widget (full background)
                  widget.after,
                  // Before widget (clipped to splitX)
                  ClipRect(
                    clipper: _HorizontalSplitClipper(splitX),
                    child: widget.before,
                  ),
                  // Divider line
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: splitX - 1.5,
                    child: Container(width: 3, color: Colors.white),
                  ),
                  // Handle icon in center
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: splitX - 14,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.compare_arrows,
                          size: 18,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  // Badges
                  if (widget.showLabels) ...[
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.beforeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.afterLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.showSliderControl) ...[
              Slider(
                value: _position,
                onChanged: (v) => setState(() => _position = v),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  const _HorizontalSplitClipper(this.splitX);
  final double splitX;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, splitX, size.height);
  }

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) {
    return oldClipper.splitX != splitX;
  }
}
