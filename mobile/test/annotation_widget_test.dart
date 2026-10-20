import 'package:aira_mobile/app/app.dart';
import 'package:aira_mobile/app/theme.dart';
import 'package:aira_mobile/core/design_system/design_system.dart';
import 'package:aira_mobile/features/annotation/application/annotation_controller.dart';
import 'package:aira_mobile/features/annotation/presentation/widgets/editor_panel.dart';
import 'package:aira_mobile/data/repositories/study_repository.dart';
import 'package:aira_mobile/features/annotation/data/annotation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_annotation_repo.dart';
import 'support/fake_study_repo.dart';

const _id = 'aaaaaaaa11111111';

Future<FakeAnnotationRepo> _open(WidgetTester tester, String path) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final annotations = FakeAnnotationRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studyRepositoryProvider.overrideWithValue(
          FakeStudyRepo([fakeStudy(_id, segmented: true)]),
        ),
        annotationRepositoryProvider.overrideWithValue(annotations),
      ],
      child: const AiraApp(),
    ),
  );
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
  return annotations;
}

void main() {
  testWidgets('results offers Edit mask and Compare for the shown version', (
    tester,
  ) async {
    await _open(tester, '/studies/$_id/results');
    expect(find.text('Results'), findsOneWidget);
    await tester.tap(find.text('Mask'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AiraButton, 'Edit mask'), findsOneWidget);
    expect(find.widgetWithText(AiraButton, 'Compare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor panel: tools follow the mode, Save appears after an edit',
    (tester) async {
      final repo = FakeAnnotationRepo();
      final c = AnnotationController(
        repository: repo,
        studyId: 's',
        t2wResourceId: 't2w',
        sliceCount: maskSlices,
        voxelMm: 0.5,
      );
      addTearDown(c.dispose);
      await tester.runAsync(c.load); // image codecs need real async
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.reading(),
          home: Scaffold(
            body: EditorPanel(controller: c, onSave: () {}, onDiscard: () {}),
          ),
        ),
      );

      for (final label in ['Brush', 'Eraser', 'Lasso', 'Undo', 'Redo']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      final save = find.widgetWithText(AiraButton, 'Save as v1');
      expect(tester.widget<AiraButton>(save).onPressed, isNull);

      c.startStroke(const Offset(4.5, 4.5));
      c.endStroke();
      await tester.pump();
      expect(c.canUndo, isTrue);
      expect(tester.widget<AiraButton>(save).onPressed, isNotNull);

      await tester.tap(find.text('Navigate').first);
      await tester.pump();
      expect(c.editMode, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
