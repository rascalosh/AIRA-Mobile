import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/disclaimer_banner.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          const ScreenHeader(title: 'Settings'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                const SectionTitle('About results'),
                const SizedBox(height: AppSpacing.sm),
                const DisclaimerBanner(),
                const SizedBox(height: AppSpacing.lg),
                const SectionTitle('Connection'),
                const SizedBox(height: AppSpacing.sm),
                AppSurface(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.server, size: 20, color: c.textTitle),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Image-processing API', style: theme.titleSmall),
                            const SizedBox(height: 2),
                            SelectableText(AppConfig.apiBaseUrl, style: theme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionTitle('Privacy'),
                const SizedBox(height: AppSpacing.sm),
                AppSurface(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.shieldCheck, size: 20, color: c.textTitle),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Text(
                          'Use de-identified data. Studies are listed for this session only and '
                          'are not stored on this device.',
                          style: theme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
