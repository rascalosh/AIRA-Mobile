import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../data/annotation_repository.dart';

/// Chooses between the versions of a mask ("AI · read-only", "Corrected v1 · 3 slices edited", ...).
class VersionPicker extends StatelessWidget {
  const VersionPicker({
    super.key,
    required this.versions,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MaskVersion> versions;
  final String selectedId;
  final ValueChanged<String> onSelected;

  static String subtitle(MaskVersion v) {
    if (v.isAi) return 'read-only';
    final n = v.editedSlices.length;
    return '$n ${n == 1 ? 'slice' : 'slices'} edited';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final v in versions)
          TapTarget(
            onTap: () => onSelected(v.versionId),
            semanticLabel:
                '${v.name}, ${subtitle(v)}${v.versionId == selectedId ? ', selected' : ''}',
            builder: (context, pressed, focused) {
              final selected = v.versionId == selectedId;
              final fg = selected ? c.onPrimary : c.textPrimary;
              return Container(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? c.primary
                      : (pressed ? c.border : c.surfaceMuted),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: focused ? Border.all(color: c.focus, width: 2) : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: theme.labelLarge?.copyWith(color: fg)),
                    Text(
                      subtitle(v),
                      style: theme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
