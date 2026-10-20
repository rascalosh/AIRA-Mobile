import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../../studies/presentation/study_scaffold.dart';
import '../application/annotation_controller.dart';
import '../data/annotation_repository.dart';
import 'widgets/editor_panel.dart';
import 'widgets/mask_canvas.dart';

/// Lets the header's back arrow ask the editor body whether leaving would lose edits.
class _LeaveGuard {
  Future<bool> Function()? confirm;
}

/// Mask editor (Reading mode): draw and erase on the T2W reference grid, undo, refine, and save a new version.
class MaskEditorScreen extends StatefulWidget {
  const MaskEditorScreen({super.key, required this.studyId});

  final String studyId;

  @override
  State<MaskEditorScreen> createState() => _MaskEditorScreenState();
}

class _MaskEditorScreenState extends State<MaskEditorScreen> {
  final _guard = _LeaveGuard();

  Future<void> _leave() async {
    final ok = await (_guard.confirm?.call() ?? Future.value(true));
    if (!ok || !mounted) return;
    // `context.pop` pops the route directly (it does not consult PopScope), so there is no second prompt.
    context.canPop() ? context.pop() : context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return StudyScaffold(
      studyId: widget.studyId,
      title: 'Edit mask',
      subtitle: 'T2W reference grid',
      reading: true,
      onBack: _leave,
      builder: (context, study) =>
          _EditorBody(study: study, guard: _guard, onLeave: _leave),
    );
  }
}

class _EditorBody extends ConsumerStatefulWidget {
  const _EditorBody({
    required this.study,
    required this.guard,
    required this.onLeave,
  });

  final Study study;
  final _LeaveGuard guard;
  final Future<void> Function() onLeave;

  @override
  ConsumerState<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<_EditorBody> {
  AnnotationController? _controller;

  @override
  void initState() {
    super.initState();
    final t2w = widget.study.niftiFiles
        .where((n) => n.modality == MriModality.t2w)
        .firstOrNull;
    if (t2w == null || t2w.shape.length < 3) return;
    _controller = AnnotationController(
      repository: ref.read(annotationRepositoryProvider),
      studyId: widget.study.studyId,
      t2wResourceId: t2w.resourceId,
      sliceCount: t2w.shape[2],
      voxelMm: t2w.voxelSpacing.isEmpty ? 1 : t2w.voxelSpacing.first,
    )..load();
    widget.guard.confirm = _confirmLeave;
  }

  @override
  void dispose() {
    widget.guard.confirm = null;
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _ask(String title, String message, String confirm) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmLeave() async {
    if (!(_controller?.hasUnsavedChanges ?? false)) return true;
    return _ask(
      'Leave without saving?',
      'Your edits on ${_controller!.dirtySlices.length} slice(s) will be lost.',
      'Leave',
    );
  }

  Future<void> _discard() async {
    if (await _ask(
      'Discard all edits?',
      'Every unsaved edit will be removed.',
      'Discard',
    )) {
      _controller?.discardAll();
    }
  }

  Future<void> _save() async {
    final controller = _controller!;
    final saved = await controller.save();
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved as ${controller.savedName}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'No T2W volume',
        message: 'The mask can only be edited on the T2W reference grid.',
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const LoadingView(message: 'Loading mask…');
        }
        if (controller.loadError != null) {
          return ErrorView(
            message: controller.loadError!,
            onRetry: controller.reloadLatest,
          );
        }
        return PopScope(
          canPop: !controller.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) widget.onLeave();
          },
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MaskCanvas(controller: controller),
                    Positioned(
                      left: AppSpacing.s3,
                      top: AppSpacing.sm,
                      child: _InfoChip(
                        controller: controller,
                        side: _Side.slice,
                      ),
                    ),
                    Positioned(
                      right: AppSpacing.s3,
                      top: AppSpacing.sm,
                      child: _InfoChip(
                        controller: controller,
                        side: _Side.tool,
                      ),
                    ),
                  ],
                ),
              ),
              EditorPanel(
                controller: controller,
                onSave: _save,
                onDiscard: _discard,
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _Side { slice, tool }

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.controller, required this.side});

  final AnnotationController controller;
  final _Side side;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = switch (side) {
      _Side.slice =>
        'Slice ${c.z + 1} / ${c.sliceCount}${c.isCurrentSliceDirty ? ' · edited' : ''}',
      _Side.tool => switch (c.tool) {
        EditTool.lasso => 'Lasso',
        EditTool.eraser => 'Eraser · ${c.brushSize.round()} vox',
        EditTool.brush => 'Brush · ${c.brushSize.round()} vox',
      },
    };
    return IgnorePointer(
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
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: context.aira.textPrimary),
        ),
      ),
    );
  }
}
