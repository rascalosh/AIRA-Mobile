import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../viewer/application/slice_providers.dart';
import '../data/annotation_repository.dart';
import '../utils/label_png.dart';

/// The versions of a study's mask (AI first, then corrections), refreshed after an edit with `ref.invalidate`.
final maskVersionsProvider = FutureProvider.autoDispose
    .family<List<MaskVersion>, String>(
      (ref, studyId) =>
          ref.watch(annotationRepositoryProvider).getVersions(studyId),
    );

/// One label slice of one mask version (a [SliceRequest] with the version id as `resourceId`).
final labelSliceProvider = FutureProvider.family<Uint8List, SliceRequest>(
  (ref, request) => ref
      .watch(annotationRepositoryProvider)
      .getLabelSlice(request.resourceId, request.index),
);

/// Dice, IoU and volumes between two versions: `(studyId, a, b)`.
final compareProvider = FutureProvider.autoDispose
    .family<CompareResult, (String, String, String)>(
      (ref, args) => ref
          .watch(annotationRepositoryProvider)
          .compare(args.$1, args.$2, args.$3),
    );

/// Where two versions differ on a slice, as one image: only in A, only in B, and in both. `(a, b, slice)`.
final differenceImageProvider = FutureProvider.autoDispose
    .family<ui.Image, (String, String, int)>((ref, args) async {
      final a = await decodeLabelPng(
        await ref.watch(
          labelSliceProvider(
            SliceRequest(resourceId: args.$1, index: args.$3),
          ).future,
        ),
      );
      final b = await decodeLabelPng(
        await ref.watch(
          labelSliceProvider(
            SliceRequest(resourceId: args.$2, index: args.$3),
          ).future,
        ),
      );
      final image = await differenceImage(a, b);
      ref.onDispose(image.dispose);
      return image;
    });
