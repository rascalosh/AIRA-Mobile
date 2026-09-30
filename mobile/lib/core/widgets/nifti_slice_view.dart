import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../features/viewer/application/slice_providers.dart';
import 'pressable.dart';

/// Displays one slice of a converted NIfTI volume.
///
/// Rendering happens on the backend (see `slice_service.py`) — this widget
/// just fetches and displays the resulting PNG, on the conventional black
/// viewport background used for greyscale medical imagery.
class NiftiSliceView extends ConsumerWidget {
  const NiftiSliceView({super.key, required this.resourceId, required this.index});

  final String resourceId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = SliceRequest(resourceId: resourceId, index: index);
    final slice = ref.watch(sliceProvider(request));
    // A plain FutureProvider.family caches a failed fetch just like a
    // successful one, so without an explicit retry a transient network
    // error would leave this exact slice broken for the rest of the session.
    void retry() => ref.invalidate(sliceProvider(request));

    return ColoredBox(
      color: AiraColors.reading.background,
      child: switch (slice) {
        AsyncData(:final value) => Semantics(
          image: true,
          label: 'MRI slice ${index + 1}',
          child: Image.memory(
            value,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _SliceError(onRetry: retry),
          ),
        ),
        AsyncError() => _SliceError(onRetry: retry),
        _ => Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.reading.primary),
          ),
        ),
      },
    );
  }
}

class _SliceError extends StatelessWidget {
  const _SliceError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Pressable(
        onTap: onRetry,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.refreshCw, size: 28, color: AiraColors.reading.textSecondary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unable to load this slice — tap to retry',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AiraColors.reading.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
