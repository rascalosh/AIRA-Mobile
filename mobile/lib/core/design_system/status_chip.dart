import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

enum ChipStatus {
  completed('Completed', LucideIcons.check),
  processing('Processing', LucideIcons.loaderCircle),
  ready('Ready to segment', LucideIcons.info),
  valid('Valid', LucideIcons.check),
  converted('Converted', LucideIcons.check),
  missing('Missing modality', LucideIcons.triangleAlert),
  invalid('Invalid DICOM', LucideIcons.circleAlert),
  failed('Failed', LucideIcons.circleAlert),
  draft('Draft', LucideIcons.minus),
  notStarted('Not started', LucideIcons.minus);

  const ChipStatus(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Process status. Always icon + text, never colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});

  final ChipStatus status;

  /// Overrides the default label, e.g. "Uploading 62%".
  final String? label;

  (Color fg, Color bg) _colors(AiraColors c) => switch (status) {
        ChipStatus.completed || ChipStatus.valid || ChipStatus.converted => (c.successFg, c.successBg),
        ChipStatus.processing || ChipStatus.ready => (c.infoFg, c.infoBg),
        ChipStatus.missing => (c.warningFg, c.warningBg),
        ChipStatus.invalid || ChipStatus.failed => (c.dangerFg, c.dangerBg),
        ChipStatus.draft || ChipStatus.notStarted => (c.neutralFg, c.neutralBg),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors(context.aira);
    final text = label ?? status.label;
    return Semantics(
      label: 'Status: $text',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 14, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class NewBadge extends StatelessWidget {
  const NewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(
        'NEW',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c.onPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}
