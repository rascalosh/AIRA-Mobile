import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../data/models/study.dart';
import 'study_format.dart';
import 'study_scaffold.dart';

/// Study detail: status, summary metrics, modality validation and the entry
/// points to the viewer and segmentation.
class StudyDetailScreen extends StatelessWidget {
  const StudyDetailScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Study detail',
      builder: (context, study) => _DetailBody(study: study),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.study});

  final Study study;

  static const _expected = [MriModality.t2w, MriModality.dwi, MriModality.adc];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final missing = missingForModel(study);
    final canRun = canSegment(study);
    final segmented = study.segmentation != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.md,
            ),
            children: [
              _SummaryCard(study: study),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s3),
                InlineAlert(
                  tone: AlertTone.warning,
                  title: 'Missing modality',
                  message:
                      'The model needs ${modelInputs.map((m) => m.apiValue).join(', ')}. '
                      'This study is missing ${missing.map((m) => m.apiValue).join(' and ')}.',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AiraButton(
                label: 'Open MRI Viewer',
                icon: LucideIcons.layers,
                variant: AiraButtonVariant.secondary,
                onPressed: study.isConverted
                    ? () => context.push(Routes.viewer(study.studyId))
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle('Modalities'),
              const SizedBox(height: AppSpacing.sm),
              for (final m in _expected) ...[
                _ModalityRow(study: study, modality: m),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
              const DisclaimerBanner(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.sm,
            AppSpacing.screenH,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segmented)
                AiraButton(
                  label: 'View results',
                  icon: LucideIcons.layers,
                  onPressed: () => context.push(Routes.results(study.studyId)),
                )
              else
                AiraButton(
                  label: 'Run AI Segmentation',
                  icon: LucideIcons.sparkles,
                  onPressed: canRun
                      ? () => context.push(Routes.segmentation(study.studyId))
                      : null,
                ),
              if (!segmented && !canRun)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    missing.isNotEmpty
                        ? 'Add the missing sequences to enable segmentation.'
                        : 'Available once the study is converted.',
                    style: theme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.study});

  final Study study;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    final date = formatDate(study.createdAt);
    final slices = sliceCount(study);
    final seriesCount = study.series.isNotEmpty
        ? study.series.length
        : study.niftiFiles.length;
    final converted = study.isConverted;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(chipStatusFor(study)),
              const Spacer(),
              if (date != null) Text(date, style: theme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Metric(label: 'Series', value: '$seriesCount'),
              ),
              Expanded(
                child: _Metric(
                  label: 'Slices',
                  value: slices > 0 ? '$slices' : '–',
                ),
              ),
              const Expanded(
                child: _Metric(label: 'Plane', value: 'Axial'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label: converted
                ? 'Upload and conversion complete, segmentation pending'
                : 'Conversion pending',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            i == 0 ||
                                (i == 1 && converted) ||
                                (i == 2 && study.segmentation != null)
                            ? c.primary
                            : c.infoBg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            study.segmentation != null
                ? 'Segmentation complete. Review the result before use.'
                : converted
                ? 'Upload and conversion complete. Next step: segmentation.'
                : 'Uploaded. Conversion has not finished yet.',
            style: theme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: theme.headlineLarge),
      ],
    );
  }
}

class _ModalityRow extends StatelessWidget {
  const _ModalityRow({required this.study, required this.modality});

  final Study study;
  final MriModality modality;

  @override
  Widget build(BuildContext context) {
    NiftiFile? volume;
    for (final n in study.niftiFiles) {
      if (n.modality == modality) volume = n;
    }
    final present = study.modalities.contains(modality);
    if (!present) {
      return CategoryRow(
        title: modality.apiValue,
        subtitle: modality.label,
        status: ChipStatus.missing,
        statusLabel: 'Not found',
      );
    }
    final slices = volume != null && volume.shape.length >= 3
        ? volume.shape[2]
        : null;
    return CategoryRow(
      title: modality.apiValue,
      subtitle: [
        modality.label,
        if (slices != null) '$slices slices',
      ].join(' · '),
      status: volume != null ? ChipStatus.converted : ChipStatus.processing,
      statusLabel: volume != null ? null : 'Pending',
    );
  }
}
