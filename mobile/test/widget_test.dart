import 'package:aira_mobile/app/app.dart';
import 'package:aira_mobile/app/theme.dart';
import 'package:aira_mobile/core/design_system/design_system.dart';
import 'package:aira_mobile/data/repositories/study_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_study_repo.dart';

Future<void> _pump(WidgetTester tester, FakeStudyRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [studyRepositoryProvider.overrideWithValue(repo)],
      child: const AiraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(AiraBottomNav), matching: find.text(label));

void main() {
  testWidgets('home shows the empty hero and the add-study flow', (
    tester,
  ) async {
    await _pump(tester, FakeStudyRepo([]));

    expect(find.text('Add your first study'), findsOneWidget);
    expect(find.textContaining('Not intended for diagnosis'), findsOneWidget);

    await tester.tap(find.widgetWithText(AiraButton, 'Add study'));
    await tester.pumpAndSettle();
    expect(find.text('Choose MRI study files'), findsOneWidget);
    expect(find.text('Upload & convert'), findsOneWidget);
  });

  testWidgets('studies saved on the server show up after a restart', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeStudyRepo([
        fakeStudy('aaaaaaaa11111111', segmented: true),
        fakeStudy('bbbbbbbb22222222'),
      ]),
    );

    // Home: the newest study is the hero and the list comes from the server.
    expect(find.text('Study aaaaaaaa'), findsWidgets);
    expect(find.text('Add your first study'), findsNothing);

    await tester.tap(_tab('Studies'));
    await tester.pumpAndSettle();
    expect(find.text('Study aaaaaaaa'), findsOneWidget);
    expect(find.text('Study bbbbbbbb'), findsOneWidget);
    expect(find.text('2 studies · most recent first'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Ready to segment'), findsOneWidget);
  });

  testWidgets('a failed load shows the error and Retry loads the studies', (
    tester,
  ) async {
    final repo = FakeStudyRepo([fakeStudy('cccccccc33333333')], fail: true);
    await _pump(tester, repo);

    expect(find.text('Could not load your studies'), findsOneWidget);
    expect(find.text('Unable to reach the processing server.'), findsOneWidget);
    // An error is not "no studies".
    expect(find.text('Add your first study'), findsNothing);

    repo.fail = false;
    await tester.tap(find.widgetWithText(AiraButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your studies'), findsNothing);
    expect(find.text('Study cccccccc'), findsWidgets);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await _pump(tester, FakeStudyRepo([]));

    await tester.tap(_tab('Studies'));
    await tester.pumpAndSettle();
    expect(find.text('No studies yet'), findsOneWidget);

    await tester.tap(_tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Image-processing API'), findsOneWidget);
  });

  testWidgets('every StatusChip shows an icon and a label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.standard(),
        home: Scaffold(
          body: Column(
            children: [for (final s in ChipStatus.values) StatusChip(s)],
          ),
        ),
      ),
    );
    for (final s in ChipStatus.values) {
      expect(find.text(s.label), findsWidgets);
    }
    expect(find.byType(Icon), findsNWidgets(ChipStatus.values.length));
  });

  testWidgets('a slider with marked slices builds and still moves', (
    tester,
  ) async {
    var value = 5.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.reading(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LabeledSlider(
              icon: Icons.layers,
              label: 'Slice',
              valueText: '${value.round() + 1} / 21',
              value: value,
              min: 0,
              max: 20,
              divisions: 20,
              marks: const {5, 6},
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();
    expect(value, greaterThan(5));
  });
}
