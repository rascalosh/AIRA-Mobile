import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../widgets/pressable.dart';

/// Segmented control with a sliding selection pill. In Standard mode the pill
/// is a white surface on a muted track; in Reading mode it is the periwinkle
/// primary. Every segment is 48dp tall.
class AiraSegmentedControl<T> extends StatelessWidget {
  const AiraSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.disabled = const {},
  });

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Segments that are shown but cannot be selected (e.g. a missing modality).
  final Set<T> disabled;

  static const _inset = 4.0;
  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pillColor = dark ? c.primary : c.surface;
    final selectedFg = dark ? c.onPrimary : c.textTitle;
    final selected = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    final radius = BorderRadius.circular(AppRadius.md);

    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: radius),
      child: LayoutBuilder(
        builder: (context, box) {
          final segmentWidth = box.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: motionDuration(context, const Duration(milliseconds: 220)),
                curve: Curves.easeOutCubic,
                left: segmentWidth * selected,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(AppRadius.md - 2),
                    border: dark ? null : Border.all(color: c.border),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        enabled: !disabled.contains(options[i].$1),
                        selected: i == selected,
                        label: options[i].$2,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i == selected || disabled.contains(options[i].$1)) return;
                            HapticFeedback.selectionClick();
                            onChanged(options[i].$1);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: motionDuration(context, const Duration(milliseconds: 220)),
                              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                                    color: i == selected
                                        ? selectedFg
                                        : disabled.contains(options[i].$1)
                                            ? c.textSecondary.withValues(alpha: 0.45)
                                            : c.textSecondary,
                                  ),
                              child: Text(options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
