import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Slider with a leading icon + label and a right-aligned tabular value, as in
/// the Reading-mode controls ("Slice 14 / 32").
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.icon,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final IconData icon;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: c.textPrimary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            Text(valueText, style: theme.bodySmall),
          ],
        ),
        Semantics(
          label: label,
          value: valueText,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
