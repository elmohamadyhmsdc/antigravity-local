import 'package:flutter/material.dart';

/// Shared hierarchy for the discovery tools, using the app's existing palette.
class DiscoveryIntro extends StatelessWidget {
  const DiscoveryIntro({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.count,
  });
  final String title, description;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: theme.textTheme.headlineSmall),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DiscoverySearch extends StatefulWidget {
  const DiscoverySearch({
    super.key,
    required this.hint,
    required this.onChanged,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  State<DiscoverySearch> createState() => _DiscoverySearchState();
}

class _DiscoverySearchState extends State<DiscoverySearch> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value.trim().toLowerCase());
      },
    ),
  );
}
