import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/pressable.dart';

/// Shared press/focus behaviour for custom controls: scale-down on press
/// (respecting reduce-motion), a keyboard-activatable focus node, and merged
/// semantics. The [builder] receives the pressed and focused state so the
/// control can restyle itself (`primaryPressed`, focus ring).
class TapTarget extends StatefulWidget {
  const TapTarget({
    super.key,
    required this.onTap,
    required this.builder,
    this.scale = 0.97,
    this.semanticLabel,
    this.haptic = false,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool pressed, bool focused) builder;
  final double scale;

  /// Overrides the label read by screen readers (icon-only controls).
  final String? semanticLabel;
  final bool haptic;

  @override
  State<TapTarget> createState() => _TapTargetState();
}

class _TapTargetState extends State<TapTarget> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  void _activate() {
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: enabled ? _activate : null,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _activate : null,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? widget.scale : 1.0,
            duration: motionDuration(context, const Duration(milliseconds: 120)),
            curve: Curves.easeOutCubic,
            child: widget.builder(context, _pressed, _focused),
          ),
        ),
      ),
    );
  }
}
