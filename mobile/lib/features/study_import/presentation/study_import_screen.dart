import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../data/models/study.dart';
import '../../../data/repositories/study_repository.dart';
import '../application/study_import_controller.dart';

class StudyImportScreen extends ConsumerWidget {
  const StudyImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyImportControllerProvider);
    final controller = ref.read(studyImportControllerProvider.notifier);
    final theme = Theme.of(context).textTheme;
    final study = state.study;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: AiraIconButton(
            icon: LucideIcons.arrowLeft,
            label: 'Back',
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add study', style: theme.titleMedium?.copyWith(color: context.aira.textTitle)),
            Text('Step 1 of 2 · Upload', style: theme.bodySmall),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
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
                  _PickerCard(state: state, onPick: controller.pickFiles, onClear: controller.clearFiles),
                  if (state.files.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s3),
                    _FileListCard(state: state, onRemove: controller.removeFile),
                  ],
                  if (state.phase != ImportPhase.selecting) ...[
                    const SizedBox(height: AppSpacing.s3),
                    _ProgressCard(state: state),
                  ],
                  if (study != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ValidationSection(study: study),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(LucideIcons.shieldCheck, size: 16, color: context.aira.textSecondary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Use de-identified data. Studies are not stored on this device.',
                          style: theme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.md),
              child: _BottomAction(state: state, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Dashed drop-zone card. DICOM files rarely have an extension, so the
/// picker accepts any file; a .zip of the study folder also works.
class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.state, required this.onPick, required this.onClear});

  final StudyImportState state;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    final locked = state.isBusy || state.study != null;
    final hasFiles = state.files.isNotEmpty;

    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: c.primary.withValues(alpha: 0.45), radius: AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(color: c.infoBg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
              child: Icon(LucideIcons.cloudUpload, size: 26, color: c.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasFiles ? 'Files selected' : 'Choose MRI study files',
              style: theme.titleMedium?.copyWith(color: c.textTitle),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Select every DICOM file of one study (T2W, DWI, ADC), or a .zip of the study folder.',
              style: theme.bodyMedium?.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AiraButton(
                    label: hasFiles ? 'Add more files' : 'Choose files',
                    icon: LucideIcons.folder,
                    variant: AiraButtonVariant.secondary,
                    onPressed: locked ? null : onPick,
                  ),
                ),
                if (hasFiles && !locked) ...[
                  const SizedBox(width: AppSpacing.sm),
                  AiraIconButton(
                    icon: LucideIcons.trash2,
                    label: 'Clear selection',
                    filled: true,
                    onPressed: onClear,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

class _FileListCard extends StatelessWidget {
  const _FileListCard({required this.state, required this.onRemove});

  final StudyImportState state;
  final ValueChanged<LocalFile> onRemove;

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final shown = state.files.take(_maxShown).toList();
    final removable = !state.isBusy && state.study == null;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${state.files.length} files · ${_formatBytes(state.totalBytes)}', style: theme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final file in shown)
            _FileRow(file: file, onRemove: removable ? () => onRemove(file) : null),
          if (state.files.length > _maxShown)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('+ ${state.files.length - _maxShown} more', style: theme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final LocalFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(
            file.name.toLowerCase().endsWith('.zip') ? LucideIcons.fileArchive : LucideIcons.file,
            size: 18,
            color: c.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.bodyMedium),
                Text(_formatBytes(file.size), style: theme.bodySmall),
              ],
            ),
          ),
          if (onRemove != null)
            AiraIconButton(icon: LucideIcons.x, label: 'Remove ${file.name}', onPressed: onRemove),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});

  final StudyImportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    if (state.phase == ImportPhase.error) {
      return InlineAlert(
        tone: AlertTone.danger,
        title: 'Import failed',
        message: state.errorMessage ?? 'Something went wrong. Check your connection and try again.',
      );
    }

    final (title, chip) = switch (state.phase) {
      ImportPhase.uploading => (
          'Uploading',
          StatusChip(ChipStatus.processing, label: '${(state.uploadProgress * 100).round()}%'),
        ),
      ImportPhase.converting => ('Converting DICOM to NIfTI', const StatusChip(ChipStatus.processing)),
      _ => ('Study ready', const StatusChip(ChipStatus.completed)),
    };
    final active = state.phase == ImportPhase.uploading || state.phase == ImportPhase.converting;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.titleSmall)),
              chip,
            ],
          ),
          if (active) ...[
            const SizedBox(height: AppSpacing.s3),
            Semantics(
              label: title,
              value: state.phase == ImportPhase.uploading ? '${(state.uploadProgress * 100).round()} percent' : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: state.phase == ImportPhase.uploading ? state.uploadProgress : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Modality validation: which of T2W / DWI / ADC the backend found.
class _ValidationSection extends StatelessWidget {
  const _ValidationSection({required this.study});

  final Study study;

  static const _expected = [MriModality.t2w, MriModality.dwi, MriModality.adc];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Modality validation'),
        const SizedBox(height: AppSpacing.sm),
        for (final m in _expected) ...[
          _row(m),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (study.skippedFiles > 0)
          Text('${study.skippedFiles} files skipped (not MR DICOM images).', style: theme.bodySmall),
      ],
    );
  }

  Widget _row(MriModality m) {
    final images = study.series.where((s) => s.modality == m).fold(0, (sum, s) => sum + s.numInstances);
    final found = study.modalities.contains(m);
    return CategoryRow(
      title: m.apiValue,
      subtitle: found && images > 0 ? '$images images' : null,
      status: found ? ChipStatus.valid : ChipStatus.missing,
      statusLabel: found ? null : 'Missing',
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.state, required this.controller});

  final StudyImportState state;
  final StudyImportController controller;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case ImportPhase.uploading:
        return AiraButton(
          label: 'Cancel upload',
          variant: AiraButtonVariant.secondary,
          onPressed: controller.cancelUpload,
        );
      case ImportPhase.converting:
        return const AiraButton(label: 'Converting…');
      case ImportPhase.done:
        return AiraButton(
          label: 'Continue',
          icon: LucideIcons.arrowRight,
          onPressed: () => context.pushReplacement(Routes.study(state.study!.studyId)),
        );
      case ImportPhase.error:
        return AiraButton(label: 'Retry', icon: LucideIcons.refreshCw, onPressed: controller.uploadAndConvert);
      case ImportPhase.selecting:
        return AiraButton(
          label: 'Upload & convert',
          icon: LucideIcons.upload,
          onPressed: state.files.isEmpty ? null : controller.uploadAndConvert,
        );
    }
  }
}
