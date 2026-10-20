import 'package:aira_mobile/app/app.dart';
import 'package:aira_mobile/core/config/app_config.dart';
import 'package:aira_mobile/core/design_system/design_system.dart';
import 'package:aira_mobile/data/repositories/study_repository.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_study_repo.dart';

void main() {
  test('release builds refuse plain http, debug builds allow it', () {
    expect(
      () => AppConfig.assertSecure('http://10.0.2.2:8000', true),
      throwsStateError,
    );
    expect(
      () => AppConfig.assertSecure('https://api.example.org', true),
      returnsNormally,
    );
    expect(
      () => AppConfig.assertSecure('http://10.0.2.2:8000', false),
      returnsNormally,
    );
  });

  testWidgets(
    'Delete all my data asks first, then erases and clears the list',
    (tester) async {
      tester.view.physicalSize = const Size(
        1000,
        2400,
      ); // tall enough that the button needs no scrolling
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeStudyRepo([fakeStudy('aaaaaaaa11111111')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [studyRepositoryProvider.overrideWithValue(repo)],
          child: const AiraApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AiraBottomNav),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.widgetWithText(AiraButton, 'Delete all my data');
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Cancel: nothing is erased.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.erased, 0);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.erased, 1);
      expect(find.text('Your data was deleted.'), findsOneWidget);
    },
  );
}
