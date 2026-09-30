import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../data/models/study.dart';
import '../application/study_providers.dart';
import 'open_study.dart';
import 'study_format.dart';

enum _StudyFilter { all, ready, needsAction }

class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> {
  final _search = TextEditingController();
  var _query = '';
  var _filter = _StudyFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Study s) {
    final filterOk = switch (_filter) {
      _StudyFilter.all => true,
      _StudyFilter.ready => chipStatusFor(s) == ChipStatus.ready,
      _StudyFilter.needsAction => needsAction(s),
    };
    return filterOk && s.studyId.toLowerCase().contains(_query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(recentStudiesProvider);
    final studies = all.where(_matches).toList();
    final theme = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: 'Studies',
            trailing: AiraIconButton(
              icon: LucideIcons.plus,
              label: 'Add study',
              onPressed: () => context.push(Routes.importStudy),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              children: [
                SearchField(
                  hint: 'Search Study ID',
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: AppSpacing.s3),
                AiraSegmentedControl<_StudyFilter>(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                  options: const [
                    (_StudyFilter.all, 'All'),
                    (_StudyFilter.ready, 'Ready'),
                    (_StudyFilter.needsAction, 'Needs action'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${studies.length} ${studies.length == 1 ? 'study' : 'studies'} · most recent first',
                        style: theme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => openStudyById(context, ref),
                      child: const Text('Open by ID'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: studies.isEmpty
                ? _Empty(hasAny: all.isNotEmpty, query: _query)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.sm,
                      AppSpacing.screenH,
                      AppSpacing.lg,
                    ),
                    itemCount: studies.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s3),
                    itemBuilder: (context, i) {
                      final s = studies[i];
                      return StudyRow(
                        title: studyLabel(s),
                        lines: [
                          if (formatDate(s.createdAt) != null) formatDate(s.createdAt)!,
                          modalitiesText(s),
                        ],
                        status: chipStatusFor(s),
                        onTap: () => context.push(Routes.study(s.studyId)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.hasAny, required this.query});

  final bool hasAny;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasAny) {
      return EmptyState(
        icon: LucideIcons.scanLine,
        title: 'No studies yet',
        message: 'Studies you add or open appear here for this session.',
        action: AiraButton(
          label: 'Add study',
          icon: LucideIcons.plus,
          expand: false,
          onPressed: () => context.push(Routes.importStudy),
        ),
      );
    }
    return EmptyState(
      icon: LucideIcons.search,
      title: query.isEmpty ? 'Nothing in this filter' : 'No match for "$query"',
      message: query.isEmpty
          ? 'Try another filter.'
          : 'If this study is on the server, you can open it by its ID.',
      action: query.isEmpty
          ? null
          : AiraButton(
              label: 'Open by ID',
              variant: AiraButtonVariant.secondary,
              expand: false,
              onPressed: () => openStudyById(context, ref, prefill: query),
            ),
    );
  }
}
