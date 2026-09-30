import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

/// Reminds users that results are AI-assisted visualizations, not diagnoses.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  static const text =
      'AI-assisted segmentation visualization for research and image review. '
      'Not intended for diagnosis.';

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.infoBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.info, size: 16, color: c.infoFg),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
