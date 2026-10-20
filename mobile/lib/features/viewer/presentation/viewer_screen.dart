import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../core/widgets/nifti_slice_view.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../../studies/presentation/study_scaffold.dart';
import '../application/slice_providers.dart';

/// MRI viewer (Reading mode): every slice of the converted NIfTI volume for
/// each available modality, with slice navigation, pinch zoom/pan and
/// double-tap zoom.
class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'MRI Viewer',
      reading: true,
      actionsBuilder: (context, study) => [
        AiraIconButton(
          icon: LucideIcons.info,
          label: 'Series details',
          onPressed: () => _showDetails(context, study),
        ),
      ],
      builder: (context, study) => _ViewerBody(study: study),
    );
  }

  void _showDetails(BuildContext context, Study study) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.aira.surface,
      builder: (context) {
        final theme = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Series details', style: theme.titleMedium),
                const SizedBox(height: AppSpacing.s3),
                for (final n in study.niftiFiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            n.modality.apiValue,
                            style: theme.titleSmall,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            n.shape.join(' × '),
                            style: theme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${n.voxelSpacing.map((v) => v.toStringAsFixed(2)).join(' × ')} mm',
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Pinch to zoom, drag to pan, double-tap to zoom in or reset.',
                  style: theme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                const DisclaimerBanner(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ViewerBody extends ConsumerStatefulWidget {
  const _ViewerBody({required this.study});

  final Study study;

  @override
  ConsumerState<_ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends ConsumerState<_ViewerBody> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;
  late MriModality _modality;
  int _slice = 0;

  List<NiftiFile> get _volumes => widget.study.niftiFiles;

  NiftiFile? get _volume {
    for (final v in _volumes) {
      if (v.modality == _modality) return v;
    }
    return null;
  }

  /// Slices along the last spatial axis (axial after dicom2nifti reorientation).
  int get _sliceCount =>
      (_volume?.shape.length ?? 0) >= 3 ? _volume!.shape[2] : 1;

  double get _zoom => _transform.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _modality = _volumes.isNotEmpty ? _volumes.first.modality : MriModality.t2w;
    _slice = _sliceCount ~/ 2;
    _prefetchNeighbors();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _select(MriModality modality) {
    setState(() {
      _modality = modality;
      _slice = _sliceCount ~/ 2;
    });
    _prefetchNeighbors();
  }

  void _step(int delta) => _setSlice(_slice + delta);

  void _setSlice(int value) {
    final next = value.clamp(0, _sliceCount - 1);
    if (next == _slice) return;
    HapticFeedback.selectionClick();
    setState(() => _slice = next);
    _prefetchNeighbors();
  }

  /// Warms the cache for the next/previous slice so scrubbing feels
  /// instant: by the time the user reaches a neighboring slice it has
  /// usually already finished loading.
  void _prefetchNeighbors() {
    final resourceId = _volume?.resourceId;
    if (resourceId == null) return;
    for (final neighbor in [_slice - 1, _slice + 1]) {
      if (neighbor >= 0 && neighbor < _sliceCount) {
        ref
            .read(
              sliceProvider(
                SliceRequest(resourceId: resourceId, index: neighbor),
              ).future,
            )
            .ignore();
      }
    }
  }

  /// Double-tap toggles between fit and 2x centred on the tap point.
  void _toggleZoom() {
    if (_zoom > 1.01) {
      _transform.value = Matrix4.identity();
    } else {
      final p = _doubleTapAt;
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2)
        ..setEntry(0, 3, -p.dx)
        ..setEntry(1, 3, -p.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.study.isConverted) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: PlaceholderPanel(
          icon: LucideIcons.hourglass,
          title: 'Study not converted',
          subtitle:
              'Finish uploading and converting the study before viewing it.',
        ),
      );
    }

    final c = context.aira;
    final available = {for (final v in _volumes) v.modality};
    const modalities = [MriModality.t2w, MriModality.dwi, MriModality.adc];
    final volume = _volume;

    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: AiraColors.reading.background,
            child: volume == null
                ? const PlaceholderPanel(
                    icon: LucideIcons.image,
                    title: 'No volume for this modality',
                    subtitle: 'This series has no converted NIfTI volume.',
                    dark: true,
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                        onDoubleTap: _toggleZoom,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 1,
                          maxScale: 8,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: NiftiSliceView(
                                resourceId: volume.resourceId,
                                index: _slice,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.md,
                        top: AppSpacing.sm,
                        child: _ViewportLabel(
                          'Slice ${_slice + 1} / $_sliceCount',
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.md,
                        top: AppSpacing.sm,
                        child: _ViewportLabel('${_modality.apiValue} · Axial'),
                      ),
                      Positioned(
                        left: AppSpacing.md,
                        bottom: AppSpacing.sm,
                        child: ListenableBuilder(
                          listenable: _transform,
                          builder: (context, _) => _ViewportLabel(
                            'Zoom ${_zoom.toStringAsFixed(1)}×',
                          ),
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.xs,
                        bottom: 0,
                        child: ListenableBuilder(
                          listenable: _transform,
                          builder: (context, _) => AnimatedOpacity(
                            duration: motionDuration(
                              context,
                              const Duration(milliseconds: 160),
                            ),
                            opacity: _zoom > 1.01 ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: _zoom <= 1.01,
                              child: AiraIconButton(
                                icon: LucideIcons.rotateCcw,
                                label: 'Reset zoom',
                                filled: true,
                                onPressed: () =>
                                    _transform.value = Matrix4.identity(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        Container(
          color: c.background,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiraSegmentedControl<MriModality>(
                value: _modality,
                onChanged: _select,
                disabled: {
                  for (final m in modalities)
                    if (!available.contains(m)) m,
                },
                options: [for (final m in modalities) (m, m.apiValue)],
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                children: [
                  AiraIconButton(
                    icon: LucideIcons.chevronLeft,
                    label: 'Previous slice',
                    onPressed: _slice > 0 ? () => _step(-1) : null,
                  ),
                  Expanded(
                    child: LabeledSlider(
                      icon: LucideIcons.layers,
                      label: 'Slice',
                      valueText: '${_slice + 1} / $_sliceCount',
                      value: _slice.toDouble(),
                      min: 0,
                      max: (_sliceCount - 1).clamp(1, 1 << 20).toDouble(),
                      divisions: _sliceCount > 1 ? _sliceCount - 1 : null,
                      onChanged: _sliceCount > 1
                          ? (v) => _setSlice(v.round())
                          : null,
                    ),
                  ),
                  AiraIconButton(
                    icon: LucideIcons.chevronRight,
                    label: 'Next slice',
                    onPressed: _slice < _sliceCount - 1 ? () => _step(1) : null,
                  ),
                ],
              ),
              // Once the AI segmentation has run there is nothing left to start here: Results shows it.
              if (widget.study.segmentation == null) ...[
                const SizedBox(height: AppSpacing.sm),
                AiraButton(
                  label: 'Run AI Segmentation',
                  icon: LucideIcons.sparkles,
                  onPressed: () =>
                      context.push(Routes.segmentation(widget.study.studyId)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewportLabel extends StatelessWidget {
  const _ViewportLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: context.aira.textPrimary),
      ),
    );
  }
}
