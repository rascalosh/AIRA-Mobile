import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../data/models/job.dart';
import '../../../data/models/study.dart';
import '../../../data/repositories/study_repository.dart';
import '../../studies/application/study_providers.dart';
import '../../studies/presentation/study_format.dart';
import '../../studies/presentation/study_scaffold.dart';

/// Runs the segmentation model on the server (FastAPI) and opens the result.
class SegmentationScreen extends StatelessWidget {
  const SegmentationScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Segmentation',
      builder: (context, study) => _SegmentationBody(study: study),
    );
  }
}

class _SegmentationBody extends ConsumerStatefulWidget {
  const _SegmentationBody({required this.study});

  final Study study;

  @override
  ConsumerState<_SegmentationBody> createState() => _SegmentationBodyState();
}

class _SegmentationBodyState extends ConsumerState<_SegmentationBody> {
  bool _running = false;
  String? _error;

  static const _pollEvery = Duration(seconds: 2);
  static const _giveUpAfter = Duration(minutes: 10);

  /// Starts the server-side job and polls it. Leaving the screen only stops the polling: the job keeps
  /// running, and the result is on the study the next time it is opened.
  Future<void> _run() async {
    final study = widget.study;
    final repository = ref.read(studyRepositoryProvider);
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      var job = await repository.startSegmentation(study.studyId);
      final deadline = DateTime.now().add(_giveUpAfter);
      while (!job.isDone && mounted) {
        if (DateTime.now().isAfter(deadline)) {
          throw const ApiException('Segmentation is taking longer than expected. Check the study again later.');
        }
        await Future<void>.delayed(_pollEvery);
        job = await repository.getJob(job.jobId);
      }
      if (!mounted) return;
      final segmentation = job.segmentation;
      if (job.status == JobStatus.failed || segmentation == null) {
        setState(() => _error = job.errorMessage ?? 'Segmentation could not be completed. Please try again.');
        return;
      }
      ref.read(recentStudiesProvider.notifier).upsert(study.copyWith(segmentation: segmentation));
      ref.invalidate(studyProvider(study.studyId));
      context.pushReplacement(Routes.results(study.studyId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final study = widget.study;
    final theme = Theme.of(context).textTheme;
    final have = {for (final n in study.niftiFiles) n.modality};
    final segmented = study.segmentation != null;
    final canRun = canSegment(study) && !_running;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.md),
            children: [
              const InlineAlert(
                tone: AlertTone.warning,
                title: 'Experimental model',
                message: 'This model has low validation accuracy. Treat the result as a suggestion to review, '
                    'never as a diagnosis.',
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle('Input sequences'),
              const SizedBox(height: AppSpacing.sm),
              for (final m in modelInputs) ...[
                CategoryRow(
                  title: m.apiValue,
                  subtitle: m.label,
                  status: have.contains(m) ? ChipStatus.valid : ChipStatus.missing,
                  statusLabel: have.contains(m) ? null : 'Missing',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_running) ...[
                const SizedBox(height: AppSpacing.s3),
                AppSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Segmenting', style: theme.titleSmall)),
                          const StatusChip(ChipStatus.processing),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator()),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'The server is running the model on all three sequences. This can take up to a minute.',
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.s3),
                InlineAlert(tone: AlertTone.danger, title: 'Segmentation failed', message: _error!),
              ],
              const SizedBox(height: AppSpacing.md),
              const DisclaimerBanner(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.md),
          child: segmented
              ? AiraButton(
                  label: 'View results',
                  icon: LucideIcons.layers,
                  onPressed: () => context.pushReplacement(Routes.results(study.studyId)),
                )
              : AiraButton(
                  label: _running ? 'Segmenting…' : (_error != null ? 'Retry' : 'Run AI Segmentation'),
                  icon: _error != null && !_running ? LucideIcons.refreshCw : LucideIcons.sparkles,
                  onPressed: canRun ? _run : null,
                ),
        ),
      ],
    );
  }
}
