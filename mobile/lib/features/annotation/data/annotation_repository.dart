import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => AnnotationRepository(ref.watch(apiClientProvider)),
);

/// One version of a study's mask: the read-only AI output or a saved correction.
class MaskVersion {
  const MaskVersion({
    required this.versionId,
    required this.name,
    required this.source,
    required this.volumeMl,
    required this.readOnly,
    this.baseVersionId,
    this.labels = const {},
    this.editedSlices = const [],
    this.refinedSlices = const [],
    this.slicesWithMask = const [],
  });

  final String versionId;

  /// "AI", "Corrected v1", ...
  final String name;
  final String source;
  final String? baseVersionId;
  final Map<String, String> labels;
  final double volumeMl;
  final bool readOnly;
  final List<int> editedSlices;
  final List<int> refinedSlices;

  /// 0-based slices that contain mask.
  final List<int> slicesWithMask;

  bool get isAi => source == 'ai';

  factory MaskVersion.fromJson(Map<String, dynamic> json) {
    List<int> ints(String key) => [
      for (final i in (json[key] as List?) ?? const []) (i as num).toInt(),
    ];
    return MaskVersion(
      versionId: json['version_id'] as String,
      name: json['name'] as String,
      source: json['source'] as String,
      baseVersionId: json['base_version_id'] as String?,
      labels: {
        for (final e in ((json['labels'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      volumeMl: (json['volume_ml'] as num).toDouble(),
      readOnly: json['read_only'] as bool,
      editedSlices: ints('edited_slices'),
      refinedSlices: ints('refined_slices'),
      slicesWithMask: ints('slices_with_mask'),
    );
  }
}

class CompareResult {
  const CompareResult({
    required this.dice,
    required this.iou,
    required this.volumeMlA,
    required this.volumeMlB,
    required this.changedVoxels,
  });

  final double dice;
  final double iou;
  final double volumeMlA;
  final double volumeMlB;
  final int changedVoxels;

  double get volumeDeltaMl => volumeMlB - volumeMlA;

  factory CompareResult.fromJson(Map<String, dynamic> json) => CompareResult(
    dice: (json['dice'] as num).toDouble(),
    iou: (json['iou'] as num).toDouble(),
    volumeMlA: (json['volume_ml_a'] as num).toDouble(),
    volumeMlB: (json['volume_ml_b'] as num).toDouble(),
    changedVoxels: (json['changed_voxels'] as num).toInt(),
  );
}

class RefineResult {
  const RefineResult({
    required this.png,
    required this.changedPixels,
    required this.runtimeMs,
  });

  final Uint8List png;
  final int changedPixels;
  final int runtimeMs;
}

/// The mask-editing API: versions, label slices, saving, refinement and comparison.
class AnnotationRepository {
  AnnotationRepository(this._api);

  final ApiClient _api;

  Future<List<MaskVersion>> getVersions(String studyId) async {
    final json = await _api.getJson('/api/v1/studies/$studyId/mask/versions');
    return [
      for (final v in json['versions'] as List)
        MaskVersion.fromJson(v as Map<String, dynamic>),
    ];
  }

  /// A mask slice as a label PNG at native size (pixel value = label).
  Future<Uint8List> getLabelSlice(String versionId, int z) =>
      _api.getBytes('/api/v1/masks/$versionId/slices/$z');

  /// The MRI slice at native size, the same grid as the label slice (one image pixel per voxel).
  Future<Uint8List> getFullSlice(String resourceId, int z) =>
      _api.getBytes('/api/v1/resources/$resourceId/slices/$z?full=true');

  /// Saves edited slices ({slice: label PNG}) as a new version on top of [baseVersionId]. A 409
  /// `VERSION_CONFLICT` `ApiException` means a newer version exists.
  Future<MaskVersion> saveVersion(
    String studyId,
    String baseVersionId,
    Map<int, Uint8List> slices, {
    List<int> refined = const [],
  }) async {
    final form = FormData.fromMap({
      'base_version_id': baseVersionId,
      'refined_slices': refined.join(','),
    });
    for (final e in slices.entries) {
      final name = 'slice_${e.key.toString().padLeft(3, '0')}.png';
      form.files.add(
        MapEntry('slices', MultipartFile.fromBytes(e.value, filename: name)),
      );
    }
    return MaskVersion.fromJson(
      await _api.postMultipart('/api/v1/studies/$studyId/mask/versions', form),
    );
  }

  /// A refinement proposal for one edited slice. Nothing is stored on the server.
  Future<RefineResult> refine(
    String studyId,
    String baseVersionId,
    int z,
    Uint8List editedPng, {
    int label = 1,
    int bandWidth = 3,
  }) async {
    final form = FormData.fromMap({
      'base_version_id': baseVersionId,
      'slice_index': z,
      'label': label,
      'band_width_vox': bandWidth,
      'edited_slice': MultipartFile.fromBytes(editedPng, filename: 'edit.png'),
    });
    final json = await _api.postMultipart(
      '/api/v1/studies/$studyId/mask/refine',
      form,
    );
    return RefineResult(
      png: base64Decode(json['proposed_slice_png_base64'] as String),
      changedPixels: (json['changed_pixels'] as num).toInt(),
      runtimeMs: (json['runtime_ms'] as num).toInt(),
    );
  }

  Future<CompareResult> compare(String studyId, String a, String b) async =>
      CompareResult.fromJson(
        await _api.getJson('/api/v1/studies/$studyId/mask/compare?a=$a&b=$b'),
      );
}
