import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/study_repository.dart';

/// Identifies one slice of one NIfTI volume — the key for [sliceProvider].
class SliceRequest {
  const SliceRequest({required this.resourceId, required this.index});

  final String resourceId;
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SliceRequest && other.resourceId == resourceId && other.index == index);

  @override
  int get hashCode => Object.hash(resourceId, index);
}

/// Fetches (and caches, for the app session) one rendered slice image.
///
/// Riverpod's `.family` caches by request equality on its own, so scrubbing
/// back to an already-fetched slice is instant and re-triggers no network
/// call — this is the whole caching layer, no extra bookkeeping needed.
final sliceProvider = FutureProvider.family<Uint8List, SliceRequest>((ref, request) {
  return ref.watch(studyRepositoryProvider).getSlice(request.resourceId, request.index);
});
