import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/design_system/design_system.dart';

/// Exports tab. Nothing can be exported until segmentation results exist, so
/// this is an honest empty state rather than a list of disabled options.
class ExportsScreen extends StatelessWidget {
  const ExportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(title: 'Exports'),
          Expanded(
            child: EmptyState(
              icon: LucideIcons.upload,
              title: 'No exports yet',
              message: 'Reports, masks and overlays appear here once a study has been segmented.',
            ),
          ),
        ],
      ),
    );
  }
}
