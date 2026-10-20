import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/mask_overlay_view.dart';
import '../../../core/widgets/nifti_slice_view.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../../annotation/application/annotation_providers.dart';
import '../../annotation/data/annotation_repository.dart';
import '../../annotation/presentation/widgets/version_picker.dart';
import '../../studies/application/study_providers.dart';
import '../../studies/presentation/study_format.dart';
import '../../studies/presentation/study_scaffold.dart';

/// Result viewer (Reading mode): Original / Mask / Overlay.
/// Original, Mask and Overlay share one slice on the T2W grid, which is the grid the mask lives on. The mask shown
/// is the selected version (AI or a correction); Edit mask and Compare start from here.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Results',
      subtitle: 'AI-assisted segmentation',
      reading: true,
      builder: (context, study) => _ResultsBody(study: study),
    );
  }
}

/// What the viewport and panel need to know about the mask being shown.
class _ShownMask {
  const _ShownMask({
    required this.versionId,
    required this.label,
    required this.volumeMl,
    required this.slices,
  });

  final String versionId;
  final String label;
  final double volumeMl;
  final List<int> slices;

  factory _ShownMask.fromVersion(MaskVersion v) => _ShownMask(
    versionId: v.versionId,
    label: v.labels.values.firstOrNull ?? 'Segmentation',
    volumeMl: v.volumeMl,
    slices: v.slicesWithMask,
  );

  factory _ShownMask.fromAi(SegmentationInfo s) => _ShownMask(
    versionId: s.resourceId,
    label: s.label,
    volumeMl: s.volumeMl,
    slices: s.slicesWithMask,
  );
}

class _ResultsBody extends ConsumerStatefulWidget {
  const _ResultsBody({required this.study});

  final Study study;

  @override
  ConsumerState<_ResultsBody> createState() => _ResultsBodyState();
}

class _ResultsBodyState extends ConsumerState<_ResultsBody>
    with SingleTickerProviderStateMixin {
  static const _original = 0, _overlay = 2;

  late final TabController _tabs = TabController(length: 3, vsync: this);
  double _opacity = 0.4;
  bool _showMask = true;

  /// The version the user picked; null means the latest.
  String? _versionId;

  // Open on the first slice that has mask; with none, on the middle slice.
  late int _slice = switch (widget.study.segmentation?.slicesWithMask) {
    final marks? when marks.isNotEmpty => marks.first.clamp(0, _sliceCount - 1),
    _ => _sliceCount ~/ 2,
  };

  /// T2W is the anatomical reference and the mask's grid; fall back to whatever was converted.
  NiftiFile? get _volume {
    final files = widget.study.niftiFiles;
    if (files.isEmpty) return null;
    return files.firstWhere(
      (f) => f.modality == MriModality.t2w,
      orElse: () => files.first,
    );
  }

  int get _sliceCount =>
      (_volume?.shape.length ?? 0) >= 3 ? _volume!.shape[2] : 1;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _setSlice(int value) {
    final next = value.clamp(0, _sliceCount - 1);
    if (next == _slice) return;
    HapticFeedback.selectionClick();
    setState(() => _slice = next);
  }

  MaskVersion? _selected(List<MaskVersion>? versions) {
    if (versions == null || versions.isEmpty) return null;
    return versions.firstWhere(
      (v) => v.versionId == _versionId,
      orElse: () => versions.last,
    );
  }

  _ShownMask? _shown(List<MaskVersion>? versions) {
    final version = _selected(versions);
    if (version != null) return _ShownMask.fromVersion(version);
    final ai = widget.study.segmentation;
    return ai == null ? null : _ShownMask.fromAi(ai);
  }

  Future<void> _edit() async {
    final id = widget.study.studyId;
    await context.push(Routes.edit(id));
    if (!mounted) return;
    // Back from the editor: pick up any version it saved and show the newest.
    ref.invalidate(maskVersionsProvider(id));
    ref.invalidate(studyProvider(id));
    setState(() => _versionId = null);
  }

  @override
  Widget build(BuildContext context) {
    final versions = ref
        .watch(maskVersionsProvider(widget.study.studyId))
        .value;
    final mask = _shown(versions);

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Original'),
            Tab(text: 'Mask'),
            Tab(text: 'Overlay'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _viewport(
                mask,
                (v, m) =>
                    NiftiSliceView(resourceId: v.resourceId, index: _slice),
              ),
              _viewport(
                mask,
                (v, m) => ColoredBox(
                  color: AiraColors.reading.background,
                  child: MaskOverlayView(
                    maskResourceId: m!.versionId,
                    index: _slice,
                  ),
                ),
                needsMask: true,
              ),
              _viewport(
                mask,
                showImageWhenEmpty: true,
                (v, m) => Stack(
                  fit: StackFit.expand,
                  children: [
                    NiftiSliceView(resourceId: v.resourceId, index: _slice),
                    Opacity(
                      opacity: _showMask ? _opacity : 0,
                      child: MaskOverlayView(
                        maskResourceId: m!.versionId,
                        index: _slice,
                      ),
                    ),
                  ],
                ),
                needsMask: true,
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => _panel(context, mask, versions),
        ),
      ],
    );
  }

  Widget _viewport(
    _ShownMask? mask,
    Widget Function(NiftiFile volume, _ShownMask? mask) build, {
    bool needsMask = false,
    bool showImageWhenEmpty = false,
  }) {
    final volume = _volume;
    if (volume == null) {
      return const PlaceholderPanel(
        icon: LucideIcons.image,
        title: 'No volume',
        subtitle: 'Convert the study to view it.',
        dark: true,
      );
    }
    if (needsMask && mask == null) {
      return EmptyState(
        icon: LucideIcons.sparkles,
        title: 'No segmentation yet',
        message: 'Run the AI segmentation to see the mask here.',
        action: AiraButton(
          label: 'Run AI Segmentation',
          expand: false,
          onPressed: () => context.pushReplacement(
            Routes.segmentation(widget.study.studyId),
          ),
        ),
      );
    }
    if (needsMask && mask!.volumeMl <= 0) {
      // Nothing is marked: say so instead of showing a blank screen.
      if (!showImageWhenEmpty) {
        return const EmptyState(
          icon: LucideIcons.searchX,
          title: 'No lesion marked',
          message:
              'This version has no marked area. You can add one with Edit mask.',
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          build(volume, mask),
          const Align(alignment: Alignment.topCenter, child: _NoLesionNotice()),
        ],
      );
    }
    return build(volume, mask);
  }

  Widget _panel(
    BuildContext context,
    _ShownMask? mask,
    List<MaskVersion>? versions,
  ) {
    final c = context.aira;
    final tab = _tabs.index;
    if (_volume == null) return const SizedBox.shrink();
    final showMask = tab != _original && mask != null;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    final selected = _selected(versions);

    return Container(
      color: c.background,
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.sm,
          AppSpacing.screenH,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMask && versions != null && versions.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: VersionPicker(
                  versions: versions,
                  selectedId: selected!.versionId,
                  onSelected: (id) => setState(() => _versionId = id),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (showMask)
              _Legend(
                label: mask.label,
                volumeMl: mask.volumeMl,
                slices: mask.slices,
              ),
            Row(
              children: [
                AiraIconButton(
                  icon: LucideIcons.chevronLeft,
                  label: 'Previous slice',
                  onPressed: _slice > 0 ? () => _setSlice(_slice - 1) : null,
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
                    marks: showMask ? {...mask.slices} : const {},
                    onChanged: _sliceCount > 1
                        ? (v) => _setSlice(v.round())
                        : null,
                  ),
                ),
                AiraIconButton(
                  icon: LucideIcons.chevronRight,
                  label: 'Next slice',
                  onPressed: _slice < _sliceCount - 1
                      ? () => _setSlice(_slice + 1)
                      : null,
                ),
              ],
            ),
            if (tab == _overlay && mask != null)
              Row(
                children: [
                  AiraIconButton(
                    icon: _showMask ? LucideIcons.eye : LucideIcons.eyeOff,
                    label: _showMask ? 'Hide mask' : 'Show mask',
                    onPressed: () => setState(() => _showMask = !_showMask),
                  ),
                  Expanded(
                    child: LabeledSlider(
                      icon: LucideIcons.droplet,
                      label: 'Mask opacity',
                      valueText: '${(_opacity * 100).round()}%',
                      value: _opacity,
                      min: 0,
                      max: 1,
                      onChanged: _showMask
                          ? (v) => setState(() => _opacity = v)
                          : null,
                    ),
                  ),
                ],
              ),
            if (showMask && versions != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AiraButton(
                      label: 'Edit mask',
                      icon: LucideIcons.pencil,
                      variant: AiraButtonVariant.secondary,
                      onPressed: _edit,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AiraButton(
                      label: 'Compare',
                      icon: LucideIcons.gitCompare,
                      variant: AiraButtonVariant.secondary,
                      onPressed: versions.length > 1
                          ? () => context.push(
                              Routes.compare(widget.study.studyId),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoLesionNotice extends StatelessWidget {
  const _NoLesionNotice();

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'No lesion marked in this version',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.volumeMl,
    required this.slices,
  });

  final String label;
  final double volumeMl;
  final List<int> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: SegColors.cyan.withValues(alpha: SegColors.fillAlpha),
              border: Border.all(
                color: SegColors.cyan,
                width: SegColors.outlineWidth,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.bodyMedium),
                if (slices.isNotEmpty)
                  Text(
                    'On slice ${formatSlices(slices)}',
                    style: theme.bodySmall,
                  ),
              ],
            ),
          ),
          Text('${volumeMl.toStringAsFixed(1)} mL', style: theme.bodyMedium),
        ],
      ),
    );
  }
}
