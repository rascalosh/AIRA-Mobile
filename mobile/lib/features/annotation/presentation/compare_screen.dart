import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/mask_overlay_view.dart';
import '../../../core/widgets/nifti_slice_view.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../../studies/presentation/study_scaffold.dart';
import '../application/annotation_providers.dart';
import '../data/annotation_repository.dart';
import 'widgets/version_picker.dart';

/// Compare two versions of the mask (default: the AI mask against the latest correction): side by side, or as a
/// difference overlay, with Dice, IoU and the volume change.
class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Compare masks',
      subtitle: 'AI vs corrected',
      reading: true,
      builder: (context, study) => _CompareBody(study: study),
    );
  }
}

class _CompareBody extends ConsumerStatefulWidget {
  const _CompareBody({required this.study});

  final Study study;

  @override
  ConsumerState<_CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends ConsumerState<_CompareBody> {
  String? _a;
  String? _b;
  int? _slice;
  var _difference = true;

  NiftiFile? get _t2w => widget.study.niftiFiles
      .where((n) => n.modality == MriModality.t2w)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final id = widget.study.studyId;
    final t2w = _t2w;
    final loaded = ref.watch(maskVersionsProvider(id));
    final versions = loaded.value;

    if (versions == null) {
      return loaded.hasError
          ? ErrorView(
              message: 'Could not load the mask versions.',
              onRetry: () => ref.invalidate(maskVersionsProvider(id)),
            )
          : const LoadingView(message: 'Loading versions…');
    }
    if (versions.length < 2 || t2w == null) {
      return const EmptyState(
        icon: LucideIcons.gitCompare,
        title: 'Nothing to compare yet',
        message:
            'Save a correction from the mask editor to compare it with the AI mask.',
      );
    }

    final a = versions.firstWhere(
      (v) => v.versionId == _a,
      orElse: () => versions.first,
    );
    final b = versions.firstWhere(
      (v) => v.versionId == _b,
      orElse: () => versions.last,
    );
    final count = t2w.shape.length >= 3 ? t2w.shape[2] : 1;
    final marks = {...a.slicesWithMask, ...b.slicesWithMask, ...b.editedSlices};
    final slice =
        (_slice ??
                (b.editedSlices.firstOrNull ?? marks.firstOrNull ?? count ~/ 2))
            .clamp(0, count - 1);

    return Column(
      children: [
        Expanded(
          child: _difference
              ? _Pane(
                  t2w: t2w,
                  slice: slice,
                  child: _DifferenceOverlay(
                    a: a.versionId,
                    b: b.versionId,
                    slice: slice,
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: _Captioned(
                        caption: 'A · ${a.name}',
                        child: _Pane(
                          t2w: t2w,
                          slice: slice,
                          child: MaskOverlayView(
                            maskResourceId: a.versionId,
                            index: slice,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _Captioned(
                        caption: 'B · ${b.name}',
                        child: _Pane(
                          t2w: t2w,
                          slice: slice,
                          child: MaskOverlayView(
                            maskResourceId: b.versionId,
                            index: slice,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        _Panel(
          versions: versions,
          a: a,
          b: b,
          studyId: id,
          difference: _difference,
          slice: slice,
          sliceCount: count,
          marks: marks,
          onMode: (v) => setState(() => _difference = v),
          onA: (v) => setState(() => _a = v),
          onB: (v) => setState(() => _b = v),
          onSlice: (v) => setState(() => _slice = v),
        ),
      ],
    );
  }
}

/// The T2W slice with something drawn over it.
class _Pane extends StatelessWidget {
  const _Pane({required this.t2w, required this.slice, required this.child});

  final NiftiFile t2w;
  final int slice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AiraColors.reading.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NiftiSliceView(resourceId: t2w.resourceId, index: slice),
          Opacity(opacity: 0.7, child: child),
        ],
      ),
    );
  }
}

class _Captioned extends StatelessWidget {
  const _Captioned({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: AppSpacing.sm,
          top: AppSpacing.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              caption,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.aira.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Only-in-A (amber), only-in-B (cyan) and in-both (faint) pixels.
class _DifferenceOverlay extends ConsumerWidget {
  const _DifferenceOverlay({
    required this.a,
    required this.b,
    required this.slice,
  });

  final String a;
  final String b;
  final int slice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(differenceImageProvider((a, b, slice)))) {
      AsyncData(:final value) => RawImage(
        image: value,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({
    required this.versions,
    required this.a,
    required this.b,
    required this.studyId,
    required this.difference,
    required this.slice,
    required this.sliceCount,
    required this.marks,
    required this.onMode,
    required this.onA,
    required this.onB,
    required this.onSlice,
  });

  final List<MaskVersion> versions;
  final MaskVersion a;
  final MaskVersion b;
  final String studyId;
  final bool difference;
  final int slice;
  final int sliceCount;
  final Set<int> marks;
  final ValueChanged<bool> onMode;
  final ValueChanged<String> onA;
  final ValueChanged<String> onB;
  final ValueChanged<int> onSlice;

  static String _count(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.aira;
    final theme = Theme.of(context).textTheme;
    final result = ref.watch(
      compareProvider((studyId, a.versionId, b.versionId)),
    );
    final r = result.value;

    return Container(
      color: colors.background,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.sm,
          AppSpacing.screenH,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiraSegmentedControl<bool>(
              value: difference,
              onChanged: onMode,
              options: const [(false, 'Side by side'), (true, 'Difference')],
            ),
            if (difference) ...[
              const SizedBox(height: AppSpacing.s3),
              const Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _Key(color: SegColors.amber, text: 'Only in A'),
                  _Key(color: SegColors.cyan, text: 'Only in B'),
                  _Key(color: Color(0xFFE8EAF2), text: 'In both'),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.s3),
            Text('A', style: theme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            VersionPicker(
              versions: versions,
              selectedId: a.versionId,
              onSelected: onA,
            ),
            const SizedBox(height: AppSpacing.s3),
            Text('B', style: theme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            VersionPicker(
              versions: versions,
              selectedId: b.versionId,
              onSelected: onB,
            ),
            const SizedBox(height: AppSpacing.md),
            if (result.hasError)
              const InlineAlert(
                tone: AlertTone.warning,
                title: 'Could not compare',
                message:
                    'The metrics could not be loaded. Check your connection and try again.',
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Dice',
                      value: r == null ? '–' : r.dice.toStringAsFixed(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: MetricCard(
                      label: 'IoU',
                      value: r == null ? '–' : r.iou.toStringAsFixed(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Volume change',
                      value: r == null
                          ? '–'
                          : '${r.volumeDeltaMl >= 0 ? '+' : ''}${r.volumeDeltaMl.toStringAsFixed(2)}',
                      unit: 'mL',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: MetricCard(
                      label: 'Voxels changed',
                      value: r == null ? '–' : _count(r.changedVoxels),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            LabeledSlider(
              icon: LucideIcons.layers,
              label: 'Slice',
              valueText: '${slice + 1} / $sliceCount',
              value: slice.toDouble(),
              min: 0,
              max: (sliceCount - 1).clamp(1, 1 << 20).toDouble(),
              divisions: sliceCount > 1 ? sliceCount - 1 : null,
              marks: marks,
              onChanged: sliceCount > 1 ? (v) => onSlice(v.round()) : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'These numbers show how much was corrected relative to A, not clinical accuracy.',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
