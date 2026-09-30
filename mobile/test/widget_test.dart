import 'package:aira_mobile/app/app.dart';
import 'package:aira_mobile/core/design_system/design_system.dart';
import 'package:aira_mobile/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows the empty hero and the add-study flow', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiraApp()));
    await tester.pumpAndSettle();

    expect(find.text('Add your first study'), findsOneWidget);
    expect(find.textContaining('Not intended for diagnosis'), findsOneWidget);

    await tester.tap(find.widgetWithText(AiraButton, 'Add study'));
    await tester.pumpAndSettle();
    expect(find.text('Choose MRI study files'), findsOneWidget);
    expect(find.text('Upload & convert'), findsOneWidget);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiraApp()));
    await tester.pumpAndSettle();

    Finder tab(String label) =>
        find.descendant(of: find.byType(AiraBottomNav), matching: find.text(label));

    await tester.tap(tab('Studies'));
    await tester.pumpAndSettle();
    expect(find.text('No studies yet'), findsOneWidget);

    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Image-processing API'), findsOneWidget);
  });

  testWidgets('every StatusChip shows an icon and a label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.standard(),
        home: Scaffold(
          body: Column(children: [for (final s in ChipStatus.values) StatusChip(s)]),
        ),
      ),
    );
    for (final s in ChipStatus.values) {
      expect(find.text(s.label), findsWidgets);
    }
    expect(find.byType(Icon), findsNWidgets(ChipStatus.values.length));
  });
}
