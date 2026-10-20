import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/study_repository.dart';
import '../application/study_providers.dart';

/// Asks for a Study ID, fetches it from the backend, remembers it for this
/// session and opens its detail screen. [prefill] seeds the field (used when a
/// search finds no local match).
Future<void> openStudyById(
  BuildContext context,
  WidgetRef ref, {
  String? prefill,
}) async {
  final studyId = await showDialog<String>(
    context: context,
    builder: (context) => _OpenStudyDialog(initial: prefill),
  );
  if (studyId == null || studyId.isEmpty || !context.mounted) return;

  try {
    final study = await ref.read(studyRepositoryProvider).getStudy(studyId);
    ref.read(recentStudiesProvider.notifier).upsert(study);
    if (context.mounted) context.push(Routes.study(study.studyId));
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The prompt is its own [StatefulWidget] so it owns its controller's
/// lifecycle. `showDialog`'s Future resolves when `Navigator.pop` is called,
/// not when the closing transition finishes, so a controller disposed by the
/// caller right after the `await` races the still-animating [TextField]
/// (a `_dependents.isEmpty` assertion). A `State.dispose()` runs at the
/// correct point in the unmount sequence.
class _OpenStudyDialog extends StatefulWidget {
  const _OpenStudyDialog({this.initial});

  final String? initial;

  @override
  State<_OpenStudyDialog> createState() => _OpenStudyDialogState();
}

class _OpenStudyDialogState extends State<_OpenStudyDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open study'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Study ID'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
