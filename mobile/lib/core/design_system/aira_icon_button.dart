import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'tap_target.dart';

/// Icon-only button. The hit area is always 48dp; [filled] draws a 40dp
/// muted tile inside it (the Figma icon-button look). [label] is required so
/// screen readers have a name.
class AiraIconButton extends StatelessWidget {
  const AiraIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final enabled = onPressed != null;
    final fg = color ?? (enabled ? c.textTitle : c.textSecondary.withValues(alpha: 0.5));

    return Tooltip(
      message: label,
      child: TapTarget(
        onTap: onPressed,
        semanticLabel: label,
        builder: (context, pressed, focused) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: filled ? (pressed ? c.border : c.surfaceMuted) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: focused ? Border.all(color: c.focus, width: 2) : null,
                ),
                child: Icon(icon, size: 22, color: fg),
              ),
            ),
          );
        },
      ),
    );
  }
}
