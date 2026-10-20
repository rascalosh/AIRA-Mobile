import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../data/repositories/study_repository.dart';
import '../../studies/application/study_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all your data?'),
        content: const Text(
          'Every study, mask and version you uploaded is erased from the server. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(studyRepositoryProvider).deleteAllMyData();
      ref.invalidate(recentStudiesProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Your data was deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                            Text(
                              'Image-processing API',
                              style: theme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              AppConfig.apiBaseUrl,
                              style: theme.bodySmall,
                            ),
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
                      Icon(
                        LucideIcons.shieldCheck,
                        size: 20,
                        color: c.textTitle,
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Text(
                          'Use de-identified data. Studies are kept on the server for a limited time, '
                          'then deleted. Nothing is stored on this device.',
                          style: theme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AiraButton(
                  label: 'Delete all my data',
                  icon: LucideIcons.trash2,
                  variant: AiraButtonVariant.danger,
                  onPressed: () => _deleteAll(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
