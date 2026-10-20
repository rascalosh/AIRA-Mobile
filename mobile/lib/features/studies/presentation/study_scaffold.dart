import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/aira_icon_button.dart';
import '../../../core/widgets/status_views.dart';
import '../../../data/models/study.dart';
import '../application/study_providers.dart';
import 'study_format.dart';

/// Shared shell for full-screen per-study screens: loads the study, draws the
/// back header, and optionally switches the subtree to Reading mode (dark).
class StudyScaffold extends ConsumerWidget {
  const StudyScaffold({
    super.key,
    required this.studyId,
    required this.title,
    required this.builder,
    this.subtitle,
    this.reading = false,
    this.actionsBuilder,
    this.onBack,
  });

  final String studyId;
  final String title;

  /// Second header line. Defaults to the study label when null.
  final String? subtitle;
  final bool reading;

  /// Header actions; only called once the study has loaded.
  final List<Widget> Function(BuildContext context, Study study)?
  actionsBuilder;
  final Widget Function(BuildContext context, Study study) builder;

  /// Replaces the default back behaviour (e.g. to ask before leaving unsaved edits).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final study = ref.watch(studyProvider(studyId));
    final theme = reading ? AppTheme.reading() : Theme.of(context);

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final textTheme = Theme.of(context).textTheme;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (reading
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark)
                    .copyWith(statusBarColor: Colors.transparent),
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leadingWidth: 64,
                leading: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: AiraIconButton(
                    icon: LucideIcons.arrowLeft,
                    label: 'Back',
                    onPressed:
                        onBack ??
                        () => context.canPop()
                            ? context.pop()
                            : context.go(Routes.home),
                  ),
                ),
                titleSpacing: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: context.aira.textTitle,
                      ),
                    ),
                    Text(
                      subtitle ??
                          switch (study) {
                            AsyncData(:final value) => studyLabel(value),
                            _ => 'Loading…',
                          },
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
                actions: [
                  if (actionsBuilder != null && study is AsyncData<Study>)
                    ...actionsBuilder!(context, study.value),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
              body: SafeArea(
                child: switch (study) {
                  AsyncData(:final value) => builder(context, value),
                  AsyncError(:final error) => ErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(studyProvider(studyId)),
                  ),
                  _ => const LoadingView(message: 'Loading study…'),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
