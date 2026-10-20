import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../data/models/study.dart';
import '../../studies/application/study_providers.dart';
import '../../studies/presentation/studies_status.dart';
import '../../studies/presentation/study_format.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(recentStudiesProvider);
    final recent = loaded.value ?? const <Study>[];
    final ready = recent.where(isReady).length;
    final action = recent.where(needsAction).length;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          ScreenHeader(
            title: 'Home',
            trailing: AiraIconButton(
              icon: LucideIcons.plus,
              label: 'Add study',
              onPressed: () => context.push(Routes.importStudy),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                if (!loaded.hasValue)
                  StudiesLoadState(error: loaded.error)
                else if (recent.isEmpty)
                  HeroCard(
                    label: 'Get started',
                    title: 'Add your first study',
                    meta:
                        'Import a DICOM study to review its T2W, DWI and ADC series.',
                    actionLabel: 'Add study',
                    onAction: () => context.push(Routes.importStudy),
                  )
                else
                  _LatestStudyHero(study: recent.first),
                if (loaded.hasValue) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          label: 'Studies',
                          value: '${recent.length}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: MetricCard(label: 'Ready', value: '$ready'),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: MetricCard(
                          label: 'Needs action',
                          value: '$action',
                        ),
                      ),
                    ],
                  ),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SectionTitle(
                      'Recent studies',
                      trailing: TextButton(
                        onPressed: () => context.go(Routes.studies),
                        child: const Text('See all'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final study in recent.take(3)) ...[
                      StudyRow(
                        title: studyLabel(study),
                        lines: [studyMetaLine(study)],
                        status: chipStatusFor(study),
                        onTap: () => context.push(Routes.study(study.studyId)),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                    ],
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
                const DisclaimerBanner(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestStudyHero extends StatelessWidget {
  const _LatestStudyHero({required this.study});

  final Study study;

  bool get _isNew {
    final created = study.createdAt;
    return created != null && DateTime.now().difference(created).inHours < 24;
  }

  @override
  Widget build(BuildContext context) {
    final status = chipStatusFor(study);
    final slices = sliceCount(study);
    return HeroCard(
      label: status.label,
      isNew: _isNew,
      title: studyLabel(study),
      meta: [
        modalitiesText(study),
        if (slices > 0) '$slices slices',
      ].join(' · '),
      actionLabel: 'Open study',
      onAction: () => context.push(Routes.study(study.studyId)),
    );
  }
}
