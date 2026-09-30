import 'package:flutter/material.dart';
import '../../../core/design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../core/widgets/status_views.dart';
import '../../studies/presentation/study_scaffold.dart';

/// Screen 4 — Segmentation. Runs the existing pre-trained model through the
/// backend's ML API adapter; wired up in Phase 3.
class SegmentationScreen extends StatelessWidget {
  const SegmentationScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Segmentation',
      builder: (context, study) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const DisclaimerBanner(),
          const SizedBox(height: AppSpacing.md),
          const SizedBox(
            height: 176,
            child: PlaceholderPanel(
              icon: LucideIcons.sparkles,
              title: 'AI-assisted segmentation',
              subtitle:
                  'The backend sends the converted NIfTI volumes to the existing ML model API '
                  'and returns a segmentation mask. Available in Phase 3.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppSurface(
            radius: AppRadius.md,
            child: Row(
              children: [
                Icon(LucideIcons.layers, size: 18, color: context.aira.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Input volumes', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        study.niftiFiles.isEmpty
                            ? 'None — convert the study first'
                            : study.niftiFiles.map((n) => n.modality.apiValue).join(' + '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const AiraButton(label: 'Run AI Segmentation', icon: LucideIcons.sparkles),
        ],
      ),
    );
  }
}
