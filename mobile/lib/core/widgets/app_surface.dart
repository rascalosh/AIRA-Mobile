import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'pressable.dart';

/// A flat, bordered container: the design system's replacement for the
/// default elevated [Card]. Separation from the background comes from a
/// hairline border and the surface fill, never a drop shadow.
///
/// Defaults to the card radius ([AppRadius.lg]); pass a smaller one for a
/// chip-like element.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.radius = AppRadius.lg,
    this.fill = true,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool fill;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.border),
      ),
      child: child,
    );
    if (onTap == null) return container;
    return Pressable(onTap: onTap, scale: 0.98, child: container);
  }
}
