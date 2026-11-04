import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class RefaceOption {
  const RefaceOption(this.value, this.title, this.summary, this.description);
  final String value, title, summary, description;
}

/// What a finishing step does to the picture. The model's own name is only a footnote in its description.
String restorerName(String value, AppLocalizations l10n) => switch (value) {
  'none' => l10n.restorerNone,
  'gpen_bfr_512' => l10n.restorerNatural,
  'gpen_bfr_1024' => l10n.restorerExtraSharp,
  'codeformer' => l10n.restorerRebuild,
  'gfpgan_1.4' => l10n.restorerSmooth,
  'restoreformer_plus_plus' => l10n.restorerAlternative,
  _ => value,
};

/// The quality choices. [takes] maps a profile to how long it would take for this request ("about 40 s"),
/// shown right in the choice so nobody has to guess what Fast or Most detail costs.
List<RefaceOption> qualityOptions(
  AppLocalizations l10n, {
  Map<String, String> takes = const {},
}) {
  RefaceOption option(
    String value,
    String title,
    String summary,
    String description,
  ) {
    final time = takes[value];
    return RefaceOption(
      value,
      title,
      time == null ? summary : '$summary · ${l10n.refaceTakes(time)}',
      time == null ? description : '$description\n${l10n.refaceTakes(time)}.',
    );
  }

  return [
    option(
      'fast',
      l10n.refaceFast,
      l10n.refaceFastSummary,
      l10n.refaceFastDescription,
    ),
    option(
      'balanced',
      l10n.refaceBalanced,
      l10n.refaceBalancedSummary,
      l10n.refaceBalancedDescription,
    ),
    option(
      'detail',
      l10n.refaceDetail,
      l10n.refaceDetailSummary,
      l10n.refaceDetailDescription,
    ),
  ];
}

List<RefaceOption> restorationOptions(
  AppLocalizations l10n,
  List<String> models,
  String? automatic,
) => [
  RefaceOption(
    'auto',
    l10n.restorerAuto,
    automatic == null
        ? l10n.refaceAutoSummary
        : l10n.refaceAutoStartsWith(restorerName(automatic, l10n)),
    l10n.refaceAutoDescription,
  ),
  RefaceOption(
    'none',
    l10n.restorerNone,
    l10n.refaceOffSummary,
    l10n.refaceOffDescription,
  ),
  for (final model in models)
    switch (model) {
      'gpen_bfr_512' => RefaceOption(
        model,
        restorerName(model, l10n),
        l10n.refaceGpen512Summary,
        l10n.refaceGpen512Description,
      ),
      'gpen_bfr_1024' => RefaceOption(
        model,
        restorerName(model, l10n),
        l10n.refaceGpen1024Summary,
        l10n.refaceGpen1024Description,
      ),
      'codeformer' => RefaceOption(
        model,
        restorerName(model, l10n),
        l10n.refaceCodeformerSummary,
        l10n.refaceCodeformerDescription,
      ),
      'gfpgan_1.4' => RefaceOption(
        model,
        restorerName(model, l10n),
        l10n.refaceGfpganSummary,
        l10n.refaceGfpganDescription,
      ),
      'restoreformer_plus_plus' => RefaceOption(
        model,
        restorerName(model, l10n),
        l10n.refaceRestoreformerSummary,
        l10n.refaceRestoreformerDescription,
      ),
      _ => RefaceOption(
        model,
        model,
        l10n.refaceOtherModelSummary,
        l10n.refaceOtherModelDescription,
      ),
    },
];

/// Short selected labels; full purpose/tradeoff text is readable in the menu.
class RefaceOptionPicker extends StatelessWidget {
  const RefaceOptionPicker({
    super.key,
    required this.fieldKey,
    required this.descriptionKey,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final Key fieldKey, descriptionKey;
  final String label, value;
  final List<RefaceOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = options.firstWhere((option) => option.value == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: fieldKey,
          initialValue: value,
          isExpanded: true,
          itemHeight: null,
          menuMaxHeight: 420,
          decoration: InputDecoration(labelText: label),
          selectedItemBuilder: (_) => [
            for (final option in options)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  option.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        option.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Text(
            selected.description,
            key: descriptionKey,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
