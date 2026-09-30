import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'tap_target.dart';

enum AiraButtonVariant { primary, secondary, danger }

/// Full-width 48dp button. Primary is indigo (periwinkle in Reading mode),
/// secondary is an outlined surface, danger is reserved for destructive
/// actions. Disabled state keeps the label readable (AA on the muted fill).
class AiraButton extends StatelessWidget {
  const AiraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AiraButtonVariant.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AiraButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final enabled = onPressed != null;

    return TapTarget(
      onTap: onPressed,
      haptic: true,
      builder: (context, pressed, focused) {
        Color bg;
        Color fg;
        Color? border;
        switch (variant) {
          case AiraButtonVariant.primary:
            bg = enabled ? (pressed ? c.primaryPressed : c.primary) : c.surfaceMuted;
            fg = enabled ? c.onPrimary : c.textSecondary;
          case AiraButtonVariant.secondary:
            bg = enabled ? (pressed ? c.infoBg : c.surface) : c.surfaceMuted;
            fg = enabled ? c.primary : c.textSecondary;
            border = c.border;
          case AiraButtonVariant.danger:
            bg = enabled
                ? (pressed ? Color.alphaBlend(const Color(0x1F000000), c.dangerFg) : c.dangerFg)
                : c.surfaceMuted;
            fg = enabled ? c.onPrimary : c.textSecondary;
        }

        final radius = BorderRadius.circular(AppRadius.md);
        final text = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
        );
        return Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: border == null ? null : Border.all(color: border),
          ),
          foregroundDecoration: focused
              ? BoxDecoration(borderRadius: radius, border: Border.all(color: c.focus, width: 2))
              : null,
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(child: text),
            ],
          ),
        );
      },
    );
  }
}
