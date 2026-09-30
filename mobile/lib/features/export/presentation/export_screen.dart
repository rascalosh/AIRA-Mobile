import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_surface.dart';
import '../../studies/presentation/study_scaffold.dart';

/// Screen 6 — Export. Options are listed; implemented in Phase 5.
class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key, required this.studyId});

  final String studyId;

  static const _options = [
    (LucideIcons.image, 'Overlay PNG', 'Current slice with segmentation overlay'),
    (LucideIcons.fileText, 'Report', 'Summary of study, series and AI-assisted result'),
    (LucideIcons.box, 'Mask NIfTI', 'Segmentation mask volume (.nii.gz)'),
    (LucideIcons.table, 'Features CSV / JSON', 'Optional extracted features'),
  ];

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Export',
      builder: (context, study) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final (icon, title, subtitle) in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Opacity(
                opacity: 0.45,
                child: AppSurface(
                  radius: AppRadius.md,
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: context.aira.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.clock, size: 18, color: context.aira.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Export becomes available once segmentation results exist.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
