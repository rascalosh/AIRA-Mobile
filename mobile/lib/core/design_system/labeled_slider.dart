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
    this.marks = const {},
    this.markColor,
  });

  final IconData icon;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;

  /// Slider values (e.g. slice indexes) to flag with a bar on the track.
  final Set<int> marks;

  /// Colour of the marks; defaults to the segmentation cyan.
  final Color? markColor;
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
              trackShape: marks.isEmpty
                  ? null
                  : _MarkedTrackShape(
                      marks: marks,
                      min: min,
                      max: max,
                      color: markColor ?? SegColors.cyan,
                    ),
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

/// The usual rounded track, plus a short bar at each marked value (drawn under the thumb).
class _MarkedTrackShape extends RoundedRectSliderTrackShape {
  const _MarkedTrackShape({
    required this.marks,
    required this.min,
    required this.max,
    required this.color,
  });

  final Set<int> marks;
  final double min;
  final double max;
  final Color color;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()..color = color;
    for (final mark in marks) {
      final t = max == min ? 0.0 : ((mark - min) / (max - min)).clamp(0.0, 1.0);
      final bar = Rect.fromCenter(
        center: Offset(track.left + track.width * t, track.center.dy),
        width: 4,
        height: 14,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)),
        paint,
      );
    }
  }
}
