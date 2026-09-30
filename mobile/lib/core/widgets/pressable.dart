import 'package:flutter/material.dart';

/// Returns [normal], or [Duration.zero] when the platform has "reduce
/// motion" turned on — every custom implicit animation in the design system
/// (this widget's press-scale, the segmented control's sliding indicator,
/// the bottom nav's selection pill) should be driven through this instead of
/// a bare [Duration] literal.
Duration motionDuration(BuildContext context, Duration normal) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return reduceMotion ? Duration.zero : normal;
}

/// Wraps [child] with a subtle scale-down micro-interaction on press.
///
/// The design system's custom flat surfaces (see `AppSurface`) have no
/// built-in Material press feedback, so interactive ones use this instead of
/// an [InkWell] ripple — a quieter, hand-tuned response that fits a flat,
/// bordered visual language.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: motionDuration(context, const Duration(milliseconds: 120)),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
