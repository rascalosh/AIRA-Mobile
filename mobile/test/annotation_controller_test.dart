import 'package:aira_mobile/core/network/api_exception.dart';
import 'package:aira_mobile/features/annotation/application/annotation_controller.dart';
import 'package:aira_mobile/features/annotation/domain/mask_slice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_annotation_repo.dart';

AnnotationController _controller(FakeAnnotationRepo repo) =>
    AnnotationController(
      repository: repo,
      studyId: 's',
      t2wResourceId: 't2w',
      sliceCount: maskSlices,
      voxelMm: 0.5,
    );

int _count(AnnotationController c, [int v = 1]) =>
    c.currentSlice!.labels.where((l) => l == v).length;

void _tap(AnnotationController c, double x, double y) {
  c.startStroke(Offset(x, y));
  c.endStroke();
}

/// Runs [body] with real async (image codecs need it) and a loaded controller.
void _test(
  String name,
  Future<void> Function(FakeAnnotationRepo repo, AnnotationController c) body,
) {
  testWidgets(name, (tester) async {
    await tester.runAsync(() async {
      final repo = FakeAnnotationRepo();
      final c = _controller(repo);
      await c.load();
      await body(repo, c);
      c.dispose();
    });
  });
}

void main() {
  _test('loads the latest version and opens on the first slice that has mask', (
    repo,
    c,
  ) async {
    expect(c.loadError, isNull);
    expect(c.base!.versionId, 'ai');
    expect((c.z, c.width, c.height), (1, maskW, maskH));
    expect(c.ready, isTrue);
    expect(_count(c), 9);
    expect(c.hasUnsavedChanges, isFalse);
    expect(c.nextVersionName, 'Corrected v1');
  });

  testWidgets(
    'asks for segmentation first when the study has no mask version',
    (tester) async {
      await tester.runAsync(() async {
        final repo = FakeAnnotationRepo()..versions = [];
        final c = _controller(repo);
        await c.load();
        expect(c.loadError, contains('segmentation'));
        expect(c.ready, isFalse);
        c.dispose();
      });
    },
  );

  _test('a brush stroke edits the mask; undo and redo move through it', (
    repo,
    c,
  ) async {
    c.setBrushSize(4);
    _tap(c, 3.5, 3.5);

    expect(_count(c), 9 + 13); // radius 2 dot: 13 pixels
    expect(c.dirtySlices, [1]);
    expect(c.undoSteps, 1);

    c.undo();
    expect(_count(c), 9);
    expect(
      c.hasUnsavedChanges,
      isFalse,
    ); // back to the saved state: nothing to save
    expect((c.canUndo, c.canRedo), (false, true));

    c.redo();
    expect(_count(c), 22);
    expect(c.hasUnsavedChanges, isTrue);
  });

  _test('the eraser removes pixels and the lasso fills a region', (
    repo,
    c,
  ) async {
    c.setTool(EditTool.eraser);
    c.setBrushSize(10);
    _tap(c, 11.5, 9.5);
    expect(_count(c), 0);

    c.setTool(EditTool.lasso);
    for (final p in const [
      Offset(2, 2),
      Offset(8, 2),
      Offset(8, 6),
      Offset(2, 6),
    ]) {
      if (c.livePoints.isEmpty) {
        c.startStroke(p);
      } else {
        c.extendStroke(p);
      }
    }
    c.endStroke();
    expect(_count(c), 24);
  });

  _test(
    'a stroke that is cancelled, or made outside edit mode, changes nothing',
    (repo, c) async {
      c.startStroke(const Offset(3, 3));
      c.extendStroke(const Offset(6, 6));
      c.cancelStroke();
      c.endStroke();
      expect(c.hasUnsavedChanges, isFalse);

      c.setEditMode(false);
      _tap(c, 3.5, 3.5);
      expect(c.hasUnsavedChanges, isFalse);
    },
  );

  _test('history keeps the last 50 steps per slice', (repo, c) async {
    c.setBrushSize(1);
    for (var i = 0; i < 55; i++) {
      _tap(c, 0.5 + i % 24, 0.5 + i ~/ 24 * 3); // 55 distinct single pixels
    }
    expect(c.undoSteps, 50);
    while (c.canUndo) {
      c.undo();
    }
    // The 5 oldest steps can no longer be undone, so those pixels remain.
    expect(_count(c), 9 + 5);
    expect(c.hasUnsavedChanges, isTrue);
  });

  _test('reset puts the slice back to the saved version and can be undone', (
    repo,
    c,
  ) async {
    _tap(c, 3.5, 3.5);
    final edited = _count(c);
    expect(edited, greaterThan(9));

    c.resetSlice();
    expect(_count(c), 9);
    expect(c.hasUnsavedChanges, isFalse);

    c.undo(); // undoing the reset brings the edit back
    expect(_count(c), edited);
    expect(c.hasUnsavedChanges, isTrue);
  });

  _test('edits on one slice survive moving to another and back', (
    repo,
    c,
  ) async {
    _tap(c, 3.5, 3.5);
    await c.goToSlice(0);
    expect((c.z, _count(c)), (0, 0));
    _tap(c, 5.5, 5.5);
    await c.goToSlice(1);
    expect(c.dirtySlices, [0, 1]);
    expect(_count(c), greaterThan(9));
    await c.goToSlice(99); // clamped to the last slice
    expect(c.z, maskSlices - 1);
  });

  _test(
    'saving uploads only the edited slices on the latest version, then starts clean',
    (repo, c) async {
      expect(await c.save(), isFalse); // nothing to save
      expect(repo.saves, isEmpty);

      _tap(c, 3.5, 3.5);
      await c.goToSlice(2);
      _tap(c, 5.5, 5.5);
      await c.goToSlice(0); // visited but untouched

      expect(await c.save(), isTrue);

      final call = repo.saves.single;
      expect(call.base, 'ai');
      expect(call.slices.keys.toList()..sort(), [1, 2]); // not slice 0
      expect(call.refined, isEmpty);
      expect(c.hasUnsavedChanges, isFalse);
      expect(c.base!.name, 'Corrected v1');
      expect(c.savedName, 'Corrected v1');
      expect(c.nextVersionName, 'Corrected v2');
      expect(c.undoSteps, 0);

      // The saved edit is the new baseline: a further edit then undo returns to it, not to the AI mask.
      await c.goToSlice(1);
      final saved = _count(c);
      _tap(c, 18.5, 14.5);
      c.undo();
      expect(_count(c), saved);
      expect(c.hasUnsavedChanges, isFalse);
    },
  );

  _test('a version conflict keeps the edits and offers a reload', (
    repo,
    c,
  ) async {
    _tap(c, 3.5, 3.5);
    repo.saveFailure = const ApiException(
      'newer version',
      code: 'VERSION_CONFLICT',
      statusCode: 409,
    );

    expect(await c.save(), isFalse);

    expect(c.conflict, isTrue);
    expect(c.saveError, isNull);
    expect(c.hasUnsavedChanges, isTrue); // nothing lost

    repo.versions = [
      ...repo.versions,
      maskVersion('v9', 'Corrected v1', marks: [1]),
    ];
    await c.reloadLatest();
    expect(c.conflict, isFalse);
    expect(c.base!.versionId, 'v9');
    expect(c.hasUnsavedChanges, isFalse);
  });

  _test('a network failure keeps the edits, and retrying works', (
    repo,
    c,
  ) async {
    _tap(c, 3.5, 3.5);
    repo.saveFailure = const ApiException(
      'Unable to reach the processing server.',
      code: 'NETWORK_ERROR',
    );

    expect(await c.save(), isFalse);
    expect(c.saveError, contains('Unable to reach'));
    expect(c.conflict, isFalse);
    expect(c.hasUnsavedChanges, isTrue);

    expect(await c.save(), isTrue);
    expect(c.saveError, isNull);
    expect(repo.saves, hasLength(1));
  });

  _test('discard drops every unsaved edit', (repo, c) async {
    _tap(c, 3.5, 3.5);
    await c.goToSlice(2);
    _tap(c, 5.5, 5.5);

    c.discardAll();

    expect(c.hasUnsavedChanges, isFalse);
    expect(c.undoSteps, 0);
    expect(_count(c), 0);
    await c.goToSlice(1);
    expect(_count(c), 9);
  });

  _test(
    'refine: the proposal changes nothing until accepted, then it is one undoable edit',
    (repo, c) async {
      repo.refineWith = (edited) {
        final out = edited.copy();
        for (var i = 0; i < out.labels.length; i++) {
          if (out.labels[i] == 1 && i % 7 == 0) {
            out.labels[i] = 0; // "fit" by trimming some pixels
          }
        }
        return out;
      };
      c.setBrushSize(6);
      _tap(c, 4.5, 4.5);
      final edited = _count(c);
      c.setRefineBand(5);

      await c.refine();

      expect(repo.refineCalls, [5]);
      expect(c.proposal, isNotNull);
      expect(c.proposal!.changedPixels, greaterThan(0));
      expect(_count(c), edited); // still the user's edit

      c.acceptRefine();
      expect(c.proposal, isNull);
      expect(_count(c), lessThan(edited));
      expect(c.undoSteps, 2); // the stroke and the refinement

      c.undo(); // undoing the refinement restores the sloppy edit
      expect(_count(c), edited);

      c.redo();
      expect(await c.save(), isTrue);
      expect(repo.saves.single.refined, [1]);
    },
  );

  _test('rejecting a proposal, or a failed refine, leaves the edit alone', (
    repo,
    c,
  ) async {
    repo.refineWith = (edited) => MaskSlice(maskW, maskH);
    _tap(c, 4.5, 4.5);
    final edited = _count(c);

    await c.refine();
    c.rejectRefine();
    expect(c.proposal, isNull);
    expect(_count(c), edited);
    expect(c.undoSteps, 1);

    repo.refineFailure = const ApiException(
      'Refinement took too long. Your edit is unchanged.',
      code: 'REFINE_TIMEOUT',
    );
    await c.refine();
    expect(c.refineError, contains('took too long'));
    expect(c.proposal, isNull);
    expect(_count(c), edited);
  });

  _test(
    'refine needs an edit, and a proposal is dropped when the user moves on',
    (repo, c) async {
      repo.refineWith = (edited) => edited.copy();
      await c.refine(); // no edit on this slice
      expect(repo.refineCalls, isEmpty);

      _tap(c, 4.5, 4.5);
      await c.refine();
      expect(c.proposal, isNotNull);
      await c.goToSlice(2);
      expect(c.proposal, isNull);
    },
  );
}
