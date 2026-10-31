import 'package:flutter/material.dart';

/// A tappable strip inviting a short review: "Help improve your groups · 12 questions" on People,
/// "Review 8 photos" inside a person.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      if (body != null)
                        Text(
                          body!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
