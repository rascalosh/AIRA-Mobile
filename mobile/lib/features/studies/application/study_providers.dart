import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/study.dart';
import '../../../data/repositories/study_repository.dart';

/// A study fetched from the backend by ID.
final studyProvider = FutureProvider.autoDispose.family<Study, String>(
  (ref, studyId) => ref.watch(studyRepositoryProvider).getStudy(studyId),
);

/// The user's studies, loaded from the server (newest first) so they survive an app restart.
/// `upsert` updates the list in place after an upload, segmentation or open-by-ID.
class RecentStudies extends AsyncNotifier<List<Study>> {
  @override
  Future<List<Study>> build() =>
      ref.watch(studyRepositoryProvider).listStudies();

  void upsert(Study study) {
    final current = state.value ?? const <Study>[];
    state = AsyncData([
      study,
      ...current.where((s) => s.studyId != study.studyId),
    ]);
  }
}

final recentStudiesProvider = AsyncNotifierProvider<RecentStudies, List<Study>>(
  RecentStudies.new,
);
