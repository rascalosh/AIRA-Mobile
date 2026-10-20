import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../application/annotation_controller.dart';

/// Everything under the canvas: mode, tools, sizes, refinement, slice slider, and Save / Discard.
class EditorPanel extends StatelessWidget {
  const EditorPanel({
    super.key,
    required this.controller,
    required this.onSave,
    required this.onDiscard,
  });

  final AnnotationController controller;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Container(
        color: c.background,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.sm,
                  AppSpacing.screenH,
                  AppSpacing.sm,
                ),
                child: _Controls(controller: controller),
              ),
            ),
            _ActionBar(
              controller: controller,
              onSave: onSave,
              onDiscard: onDiscard,
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final AnnotationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context).textTheme;
    final mm = (c.brushSize * c.voxelMm).toStringAsFixed(1);
    final dirty = c.dirtySlices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dirty.isEmpty
              ? (c.savedName == null
                    ? 'No unsaved changes'
                    : 'Saved as ${c.savedName}')
              : '${dirty.length} ${dirty.length == 1 ? 'slice' : 'slices'} edited, not saved · ${c.undoSteps} undo steps',
          style: theme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s3),
        AiraSegmentedControl<bool>(
          value: c.editMode,
          onChanged: c.setEditMode,
          options: const [(false, 'Navigate'), (true, 'Edit')],
        ),
        const SizedBox(height: AppSpacing.s3),
        Row(
          children: [
            for (final (tool, icon, label) in const [
              (EditTool.brush, LucideIcons.brush, 'Brush'),
              (EditTool.eraser, LucideIcons.eraser, 'Eraser'),
              (EditTool.lasso, LucideIcons.lassoSelect, 'Lasso'),
            ])
              Expanded(
                child: _ToolButton(
                  icon: icon,
                  label: label,
                  selected: c.tool == tool && c.editMode,
                  onTap: () {
                    c.setTool(tool);
                    c.setEditMode(true);
                  },
                ),
              ),
            Expanded(
              child: _ToolButton(
                icon: LucideIcons.undo2,
                label: 'Undo',
                onTap: c.canUndo ? c.undo : null,
              ),
            ),
            Expanded(
              child: _ToolButton(
                icon: LucideIcons.redo2,
                label: 'Redo',
                onTap: c.canRedo ? c.redo : null,
              ),
            ),
            Expanded(
              child: _ToolButton(
                icon: LucideIcons.rotateCcw,
                label: 'Reset',
                onTap: c.isCurrentSliceDirty ? c.resetSlice : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        if (c.tool != EditTool.lasso)
          LabeledSlider(
            icon: LucideIcons.circleDot,
            label: 'Brush size',
            valueText: '${c.brushSize.round()} vox · $mm mm',
            value: c.brushSize,
            min: 1,
            max: 40,
            divisions: 39,
            onChanged: c.setBrushSize,
          ),
        LabeledSlider(
          icon: LucideIcons.droplet,
          label: 'Mask opacity',
          valueText: '${(c.opacity * 100).round()}%',
          value: c.opacity,
          min: 0.1,
          max: 1,
          onChanged: c.setOpacity,
        ),
        const SizedBox(height: AppSpacing.sm),
        _RefineCard(controller: c),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            AiraIconButton(
              icon: LucideIcons.chevronLeft,
              label: 'Previous slice',
              onPressed: c.z > 0 ? () => c.goToSlice(c.z - 1) : null,
            ),
            Expanded(
              child: LabeledSlider(
                icon: LucideIcons.layers,
                label: 'Slice',
                valueText:
                    '${c.z + 1} / ${c.sliceCount}${c.isCurrentSliceDirty ? ' · edited' : ''}',
                value: c.z.toDouble(),
                min: 0,
                max: (c.sliceCount - 1).clamp(1, 1 << 20).toDouble(),
                divisions: c.sliceCount > 1 ? c.sliceCount - 1 : null,
                marks: {...dirty},
                markColor: SegColors.amber,
                onChanged: c.sliceCount > 1
                    ? (v) => c.goToSlice(v.round())
                    : null,
              ),
            ),
            AiraIconButton(
              icon: LucideIcons.chevronRight,
              label: 'Next slice',
              onPressed: c.z < c.sliceCount - 1
                  ? () => c.goToSlice(c.z + 1)
                  : null,
            ),
          ],
        ),
        if (c.conflict) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineAlert(
            tone: AlertTone.warning,
            title: 'This mask has newer changes',
            message:
                'Reload the latest version to continue. Your unsaved edits will be discarded.',
            action: AiraButton(
              label: 'Reload latest',
              icon: LucideIcons.refreshCw,
              variant: AiraButtonVariant.secondary,
              expand: false,
              onPressed: c.reloadLatest,
            ),
          ),
        ],
        if (c.saveError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineAlert(
            tone: AlertTone.danger,
            title: 'Your changes could not be saved',
            message:
                '${c.saveError} Your edits are still on this device. Please try again.',
          ),
        ],
      ],
    );
  }
}

/// Refinement: ask the server to fit the edit to the image edge, then review the proposal before accepting it.
class _RefineCard extends StatelessWidget {
  const _RefineCard({required this.controller});

  final AnnotationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = context.aira;
    final theme = Theme.of(context).textTheme;
    final proposal = c.proposal;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: proposal != null
          ? _review(context, c, proposal, theme)
          : _ask(c, theme),
    );
  }

  Widget _ask(AnnotationController c, TextTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Refine edges', style: theme.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Fits your own edit to the image edge. The AI mask is never changed.',
          style: theme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        LabeledSlider(
          icon: LucideIcons.wandSparkles,
          label: 'Refine strength',
          valueText: '±${c.refineBand.round()} vox',
          value: c.refineBand,
          min: 1,
          max: 8,
          divisions: 7,
          onChanged: c.setRefineBand,
        ),
        AiraButton(
          label: c.refining ? 'Refining…' : 'Refine',
          icon: LucideIcons.wandSparkles,
          variant: AiraButtonVariant.secondary,
          onPressed: c.isCurrentSliceDirty && !c.refining ? c.refine : null,
        ),
        if (!c.isCurrentSliceDirty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Draw or erase on this slice first.',
              style: theme.bodySmall,
            ),
          ),
        if (c.refineError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: InlineAlert(
              tone: AlertTone.warning,
              title: 'Refinement did not finish',
              message: c.refineError!,
            ),
          ),
      ],
    );
  }

  Widget _review(
    BuildContext context,
    AnnotationController c,
    RefineProposal proposal,
    TextTheme theme,
  ) {
    final nothing = proposal.changedPixels == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review proposed edges', style: theme.titleSmall),
        const SizedBox(height: 2),
        Text(
          nothing
              ? 'Your edit already follows the image edge. Nothing to change.'
              : 'Your outline is amber, the proposal is cyan. ${proposal.changedPixels} pixels would change. '
                    'Accepting is one step you can undo.',
          style: theme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: AiraButton(
                label: nothing ? 'OK' : 'Reject',
                icon: nothing ? null : LucideIcons.x,
                variant: AiraButtonVariant.secondary,
                onPressed: c.rejectRefine,
              ),
            ),
            if (!nothing) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AiraButton(
                  label: 'Accept',
                  icon: LucideIcons.check,
                  onPressed: c.acceptRefine,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.onSave,
    required this.onDiscard,
  });

  final AnnotationController controller;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = context.aira;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: AiraButton(
              label: 'Discard',
              variant: AiraButtonVariant.secondary,
              onPressed: c.hasUnsavedChanges && !c.saving ? onDiscard : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: AiraButton(
              label: c.saving
                  ? 'Saving…'
                  : 'Save as ${c.nextVersionName.replaceFirst('Corrected ', '')}',
              icon: LucideIcons.save,
              onPressed: c.hasUnsavedChanges && !c.saving && !c.conflict
                  ? onSave
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A square-ish tool tile: icon over label, at least 56dp tall.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TapTarget(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, pressed, focused) {
          final fg = selected
              ? c.onPrimary
              : (enabled
                    ? c.textPrimary
                    : c.textSecondary.withValues(alpha: 0.5));
          return Container(
            height: 58,
            decoration: BoxDecoration(
              color: selected
                  ? c.primary
                  : (pressed ? c.border : c.surfaceMuted),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: focused ? Border.all(color: c.focus, width: 2) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: fg),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
