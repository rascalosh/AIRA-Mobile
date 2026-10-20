import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/status_views.dart';
import '../application/study_providers.dart';

/// What to show in place of the studies list while it first loads, or when loading failed.
class StudiesLoadState extends ConsumerWidget {
  const StudiesLoadState({super.key, required this.error});

  /// Null while loading.
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (error == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: LoadingView(message: 'Loading studies…'),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      child: InlineAlert(
        tone: AlertTone.danger,
        title: 'Could not load your studies',
        message: error is ApiException
            ? (error! as ApiException).message
            : 'Please check your connection and try again.',
        action: AiraButton(
          label: 'Retry',
          variant: AiraButtonVariant.secondary,
          expand: false,
          onPressed: () => ref.invalidate(recentStudiesProvider),
        ),
      ),
    );
  }
}
