import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/nifti_slice_view.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../../studies/presentation/study_scaffold.dart';

/// Screen 5 — Result viewer with Original / Mask / Overlay / Features tabs.
/// Original shows the real converted volume; Mask/Overlay/Features wait on
/// segmentation (Phase 3).
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: studyId,
      title: 'Results',
      reading: true,
      builder: (context, study) => _ResultsBody(study: study),
    );
  }
}

class _ResultsBody extends StatefulWidget {
  const _ResultsBody({required this.study});

  final Study study;

  @override
  State<_ResultsBody> createState() => _ResultsBodyState();
}

class _ResultsBodyState extends State<_ResultsBody> {
  double _opacity = 0.5;
  bool _showMask = true;

  /// The volume Original shows: T2W when available (it's the anatomical
  /// reference series), else whichever modality was converted.
  NiftiFile? get _primaryVolume {
    final files = widget.study.niftiFiles;
    if (files.isEmpty) return null;
    for (final file in files) {
      if (file.modality == MriModality.t2w) return file;
    }
    return files.first;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Original'),
              Tab(text: 'Mask'),
              Tab(text: 'Overlay'),
              Tab(text: 'Features'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _originalPane(),
                _pane(LucideIcons.layers, 'Segmentation mask', dark: true),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: SegColors.cyan, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Whole gland',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _pane(LucideIcons.layers, 'MRI + mask overlay', dark: true)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                      child: Row(
                        children: [
                          Text('Opacity', style: Theme.of(context).textTheme.bodyMedium),
                          Expanded(
                            child: Slider(
                              value: _opacity,
                              onChanged: _showMask ? (v) => setState(() => _opacity = v) : null,
                            ),
                          ),
                          Switch(value: _showMask, onChanged: (v) => setState(() => _showMask = v)),
                        ],
                      ),
                    ),
                  ],
                ),
                _pane(LucideIcons.chartColumn, 'Optional shape / intensity / texture features'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _originalPane() {
    final volume = _primaryVolume;
    if (volume == null) {
      return _pane(
        LucideIcons.image,
        'Original MRI',
        dark: true,
        subtitle: 'Convert the study to NIfTI to view the original MRI.',
      );
    }
    final middleSlice = volume.shape.length >= 3 ? volume.shape[2] ~/ 2 : 0;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: NiftiSliceView(resourceId: volume.resourceId, index: middleSlice),
      ),
    );
  }

  Widget _pane(
    IconData icon,
    String title, {
    bool dark = false,
    String subtitle = 'Available after segmentation (Phases 3–5).',
  }) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: PlaceholderPanel(icon: icon, title: title, subtitle: subtitle, dark: dark),
  );
}
