import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/models/study.dart';
import '../../../data/repositories/study_repository.dart';
import '../../studies/application/study_providers.dart';

enum ImportPhase { selecting, uploading, converting, done, error }

class StudyImportState {
  const StudyImportState({
    this.files = const [],
    this.phase = ImportPhase.selecting,
    this.uploadProgress = 0,
    this.study,
    this.errorMessage,
  });

  final List<LocalFile> files;
  final ImportPhase phase;
  final double uploadProgress;
  final Study? study;
  final String? errorMessage;

  bool get isBusy => phase == ImportPhase.uploading || phase == ImportPhase.converting;
  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  StudyImportState copyWith({
    List<LocalFile>? files,
    ImportPhase? phase,
    double? uploadProgress,
    Study? study,
    String? errorMessage,
  }) =>
      StudyImportState(
        files: files ?? this.files,
        phase: phase ?? this.phase,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        study: study ?? this.study,
        errorMessage: errorMessage,
      );
}

class StudyImportController extends Notifier<StudyImportState> {
  CancelToken? _cancelToken;

  @override
  StudyImportState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    return const StudyImportState();
  }

  /// Opens the system picker. DICOM files often have no extension, so any file type is allowed;
  /// a `.zip` of the study folder is also accepted by the backend.
  Future<void> pickFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    if (result.isEmpty || !ref.mounted) return;

    final picked = <LocalFile>[];
    for (final f in result) {
      final size = f.lengthSync() ?? await f.length();
      if (size == null) continue; // unreadable file
      picked.add(LocalFile(id: f.uri.toString(), name: f.name, size: size, openRead: f.readAsByteStream));
    }
    if (!ref.mounted) return;

    final existing = {for (final f in state.files) f.id};
    state = state.copyWith(
      files: [...state.files, ...picked.where((f) => !existing.contains(f.id))],
      phase: ImportPhase.selecting,
    );
  }

  void removeFile(LocalFile file) {
    if (state.isBusy) return;
    state = state.copyWith(files: state.files.where((f) => f.id != file.id).toList());
  }

  void clearFiles() {
    if (state.isBusy) return;
    state = const StudyImportState();
  }

  /// Uploads the selected files, then asks the backend to convert them to NIfTI.
  Future<void> uploadAndConvert() async {
    if (state.files.isEmpty || state.isBusy) return;
    final repository = ref.read(studyRepositoryProvider);
    final recent = ref.read(recentStudiesProvider.notifier);

    try {
      var study = state.study;
      if (study == null) {
        _cancelToken = CancelToken();
        state = state.copyWith(phase: ImportPhase.uploading, uploadProgress: 0);
        study = await repository.uploadStudy(
          state.files,
          cancelToken: _cancelToken,
          onProgress: (p) {
            if (ref.mounted) state = state.copyWith(uploadProgress: p);
          },
        );
        if (!ref.mounted) return;
        recent.upsert(study);
        state = state.copyWith(study: study, uploadProgress: 1);
      }

      state = state.copyWith(phase: ImportPhase.converting);
      final converted = await repository.convertStudy(study.studyId);
      if (!ref.mounted) return;
      final merged = study.copyWith(status: converted.status, niftiFiles: converted.niftiFiles);
      recent.upsert(merged);
      state = state.copyWith(study: merged, phase: ImportPhase.done);
    } on ApiException catch (e) {
      if (ref.mounted) state = state.copyWith(phase: ImportPhase.error, errorMessage: e.message);
    }
  }

  void cancelUpload() => _cancelToken?.cancel();
}

final studyImportControllerProvider =
    NotifierProvider.autoDispose<StudyImportController, StudyImportState>(StudyImportController.new);
