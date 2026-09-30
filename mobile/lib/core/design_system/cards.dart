import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../widgets/app_surface.dart';
import 'aira_button.dart';
import 'status_chip.dart';

/// The single gradient surface: the most recent study on Home. Standard
/// theme only.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.title,
    required this.meta,
    required this.actionLabel,
    required this.onAction,
    this.isNew = false,
  });

  final String label;
  final String title;
  final String meta;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s5),
        decoration: BoxDecoration(
          gradient: AiraColors.heroGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.labelMedium?.copyWith(color: Indigo.c100)),
                ),
                if (isNew) const NewBadge(),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: theme.headlineLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xs),
            Text(meta, style: theme.bodyMedium?.copyWith(color: Indigo.c100)),
            const SizedBox(height: AppSpacing.md),
            _HeroAction(label: actionLabel, onTap: onAction),
          ],
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A white button on the gradient: AiraButton's secondary variant is
    // already a white surface with indigo text.
    return AiraButton(
      label: label,
      icon: LucideIcons.sparkles,
      variant: AiraButtonVariant.secondary,
      onPressed: onTap,
    );
  }
}

/// A study in a list: leading tile, ID, meta lines, status chip, chevron.
/// Meta lines each get their own row so long modality lists never wrap
/// unevenly.
class StudyRow extends StatelessWidget {
  const StudyRow({
    super.key,
    required this.title,
    required this.status,
    this.lines = const [],
    this.isNew = false,
    this.onTap,
  });

  final String title;
  final ChipStatus status;
  final List<String> lines;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return AppSurface(
      onTap: onTap,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.infoBg, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(LucideIcons.scanLine, size: 20, color: c.primary),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title, style: theme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (isNew) ...[const SizedBox(width: AppSpacing.sm), const NewBadge()],
                  ],
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: theme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                StatusChip(status),
              ],
            ),
          ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s3, left: AppSpacing.sm),
              child: Icon(LucideIcons.chevronRight, size: 18, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// One modality (T2W / DWI / ADC) in a list, with a status chip.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.title,
    required this.status,
    this.subtitle,
    this.statusLabel,
  });

  final String title;
  final String? subtitle;
  final ChipStatus status;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s3),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Icon(LucideIcons.layers, size: 22, color: c.textTitle),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.titleMedium?.copyWith(color: c.textTitle)),
                if (subtitle != null) Text(subtitle!, style: theme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusChip(status, label: statusLabel),
        ],
      ),
    );
  }
}

/// Label above a large tabular value, optional unit.
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppSurface(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Semantics(
        label: '$label $value${unit == null ? '' : ' $unit'}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                text: value,
                style: theme.displaySmall,
                children: [
                  if (unit != null) TextSpan(text: ' $unit', style: theme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
