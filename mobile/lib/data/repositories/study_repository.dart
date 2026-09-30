import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../models/study.dart';

final studyRepositoryProvider = Provider<StudyRepository>(
  (ref) => StudyRepository(ref.watch(apiClientProvider)),
);

/// A file chosen by the user for upload.
///
/// Files are read as a byte stream rather than by path, because Android pickers may return
/// `content://` URIs that have no local file path.
class LocalFile {
  const LocalFile({required this.id, required this.name, required this.size, required this.openRead});

  /// Unique identity of the picked file (its URI), used to avoid duplicates.
  final String id;
  final String name;
  final int size;
  final Stream<List<int>> Function() openRead;
}

class StudyRepository {
  StudyRepository(this._api);

  final ApiClient _api;

  Future<Study> uploadStudy(
    List<LocalFile> files, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData();
    for (final file in files) {
      form.files.add(
        MapEntry('files', MultipartFile.fromStream(file.openRead, file.size, filename: file.name)),
      );
    }
    final json = await _api.postMultipart(
      '/api/v1/studies/upload',
      form,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    return Study.fromJson(json);
  }

  Future<Study> convertStudy(String studyId) async =>
      Study.fromJson(await _api.postJson('/api/v1/studies/$studyId/convert'));

  Future<Study> getStudy(String studyId) async =>
      Study.fromJson(await _api.getJson('/api/v1/studies/$studyId'));

  Future<void> deleteStudy(String studyId) => _api.delete('/api/v1/studies/$studyId');

  /// One slice of a converted NIfTI volume, rendered server-side to a PNG —
  /// the phone never decodes raw NIfTI/gzip data itself.
  Future<Uint8List> getSlice(String resourceId, int index) =>
      _api.getBytes('/api/v1/resources/$resourceId/slices/$index');
}
