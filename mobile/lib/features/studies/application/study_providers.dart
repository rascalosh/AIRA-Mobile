import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/study.dart';
import '../../../data/repositories/study_repository.dart';

/// A study fetched from the backend by ID.
final studyProvider = FutureProvider.autoDispose.family<Study, String>(
  (ref, studyId) => ref.watch(studyRepositoryProvider).getStudy(studyId),
);

/// Studies opened in this app session (kept in memory only — no patient data is persisted).
class RecentStudies extends Notifier<List<Study>> {
  @override
  List<Study> build() => const [];

  void upsert(Study study) {
    state = [study, ...state.where((s) => s.studyId != study.studyId)].take(20).toList();
  }

  void remove(String studyId) {
    state = state.where((s) => s.studyId != studyId).toList();
  }
}

final recentStudiesProvider = NotifierProvider<RecentStudies, List<Study>>(RecentStudies.new);
