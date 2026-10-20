import 'dart:typed_data';

import 'package:aira_mobile/core/network/api_client.dart';
import 'package:aira_mobile/features/annotation/data/annotation_repository.dart';
import 'package:aira_mobile/features/annotation/domain/mask_slice.dart';
import 'package:aira_mobile/features/annotation/utils/label_png.dart';
import 'package:dio/dio.dart';

const maskW = 24, maskH = 20, maskSlices = 3;

MaskVersion maskVersion(
  String id,
  String name, {
  bool ai = false,
  List<int> marks = const [],
}) => MaskVersion(
  versionId: id,
  name: name,
  source: ai ? 'ai' : 'manual_correction',
  volumeMl: 0.1,
  readOnly: ai,
  labels: const {'1': 'Lesion'},
  slicesWithMask: marks,
);

/// A stand-in server: serves label slices per version and records saves and refinement requests.
class FakeAnnotationRepo extends AnnotationRepository {
  FakeAnnotationRepo() : super(ApiClient(Dio()));

  List<MaskVersion> versions = [
    maskVersion('ai', 'AI', ai: true, marks: [1]),
  ];
  final Map<String, Map<int, MaskSlice>> masks = {};
  Object? saveFailure; // thrown by the next saveVersion
  Object? refineFailure;
  MaskSlice Function(MaskSlice edited)? refineWith;
  final saves =
      <({String base, Map<int, Uint8List> slices, List<int> refined})>[];
  final refineCalls = <int>[];

  MaskSlice _slice(String version, int z) {
    final stored = (masks[version] ??= {})[z];
    if (stored != null) return stored.copy();
    final s = MaskSlice(maskW, maskH);
    if (z == 1) {
      for (var y = 8; y < 11; y++) {
        for (var x = 10; x < 13; x++) {
          s.labels[y * maskW + x] = 1; // a 3x3 lesion on slice 1
        }
      }
    }
    return s;
  }

  @override
  Future<List<MaskVersion>> getVersions(String studyId) async => versions;

  @override
  Future<Uint8List> getLabelSlice(String versionId, int z) =>
      encodeLabelPng(_slice(versionId, z));

  @override
  Future<Uint8List> getFullSlice(String resourceId, int z) =>
      encodeLabelPng(MaskSlice(maskW, maskH)); // any valid image

  @override
  Future<MaskVersion> saveVersion(
    String studyId,
    String baseVersionId,
    Map<int, Uint8List> slices, {
    List<int> refined = const [],
  }) async {
    final failure = saveFailure;
    if (failure != null) {
      saveFailure = null;
      throw failure;
    }
    saves.add((base: baseVersionId, slices: slices, refined: refined));
    final saved = maskVersion('v${saves.length}', 'Corrected v${saves.length}');
    versions = [...versions, saved];
    for (final e in slices.entries) {
      (masks[saved.versionId] ??= {})[e.key] = await decodeLabelPng(e.value);
    }
    return saved;
  }

  @override
  Future<RefineResult> refine(
    String studyId,
    String baseVersionId,
    int z,
    Uint8List editedPng, {
    int label = 1,
    int bandWidth = 3,
  }) async {
    refineCalls.add(bandWidth);
    final failure = refineFailure;
    if (failure != null) throw failure;
    final edited = await decodeLabelPng(editedPng);
    final proposed = refineWith!(edited);
    var changed = 0;
    for (var i = 0; i < proposed.labels.length; i++) {
      if (proposed.labels[i] != edited.labels[i]) changed++;
    }
    return RefineResult(
      png: await encodeLabelPng(proposed),
      changedPixels: changed,
      runtimeMs: 5,
    );
  }
}
