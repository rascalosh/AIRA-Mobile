import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

enum AlertTone { danger, warning, info }

/// Inline microcopy alert: title names the problem, body names the recovery,
/// optional [code] (e.g. `ERR-DICOM-01`) is for support.
class InlineAlert extends StatelessWidget {
  const InlineAlert({
    super.key,
    required this.tone,
    required this.title,
    required this.message,
    this.code,
    this.action,
  });

  final AlertTone tone;
  final String title;
  final String message;
  final String? code;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    final (fg, bg, icon) = switch (tone) {
      AlertTone.danger => (c.dangerFg, c.dangerBg, LucideIcons.circleAlert),
      AlertTone.warning => (c.warningFg, c.warningBg, LucideIcons.triangleAlert),
      AlertTone.info => (c.infoFg, c.infoBg, LucideIcons.info),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.titleSmall?.copyWith(color: fg)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(message, style: theme.bodyMedium?.copyWith(color: c.textPrimary)),
                  if (code != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(code!, style: theme.labelSmall?.copyWith(color: c.textSecondary)),
                  ],
                  if (action != null) ...[const SizedBox(height: AppSpacing.s3), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
