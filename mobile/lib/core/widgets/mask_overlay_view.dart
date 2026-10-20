import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/viewer/application/slice_providers.dart';

/// One mask slice as a transparent PNG. It is the same size as the T2W slice PNG, so stacking it on a
/// [NiftiSliceView] with the same `BoxFit.contain` lines the two up exactly.
class MaskOverlayView extends ConsumerWidget {
  const MaskOverlayView({super.key, required this.maskResourceId, required this.index});

  final String maskResourceId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = SliceRequest(resourceId: maskResourceId, index: index);
    return switch (ref.watch(overlayProvider(request))) {
      AsyncData(:final value) => ExcludeSemantics(
          child: Image.memory(value, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      // Keep the previous slice's overlay (gaplessPlayback) while loading; nothing to show on error.
      _ => const SizedBox.shrink(),
    };
  }
}
