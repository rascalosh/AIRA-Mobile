import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Large screen title for tab screens, with an optional trailing action.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, trailing == null ? AppSpacing.screenH : AppSpacing.s3, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small section title used above lists ("Recent studies", "Modalities").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Centered empty state: icon tile, title, one line of guidance, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.aira;
    final theme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.infoBg, borderRadius: BorderRadius.circular(AppRadius.xl)),
              child: Icon(icon, size: 28, color: c.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.titleMedium?.copyWith(color: c.textTitle), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: theme.bodyMedium?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}
