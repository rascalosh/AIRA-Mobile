import 'dart:convert';
import 'dart:typed_data';

import 'package:aira_mobile/features/annotation/domain/mask_slice.dart';
import 'package:aira_mobile/features/annotation/utils/coordinate_mapper.dart';
import 'package:aira_mobile/features/annotation/utils/label_png.dart';
import 'package:aira_mobile/features/annotation/utils/rasterizer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

int count(MaskSlice s, [int value = 1]) =>
    s.labels.where((v) => v == value).length;
bool at(MaskSlice s, int x, int y) => s.labels[y * s.width + x] != 0;

void main() {
  group('VoxelMapper', () {
    // A 100 x 75 slice shown in a 400 x 300 viewport: 4 screen px per voxel.
    final fit = fitImage(const Size(400, 300), 100, 75);

    VoxelMapper mapper(Matrix4 m, {Rect? rect}) =>
        VoxelMapper(matrix: m, imageRect: rect ?? fit, width: 100, height: 75);

    test('identity: the image fills the viewport', () {
      expect(fit, const Rect.fromLTWH(0, 0, 400, 300));
      expect(
        mapper(Matrix4.identity()).screenToVoxel(const Offset(200, 150)),
        const Offset(50, 37.5),
      );
      expect(
        mapper(Matrix4.identity()).screenToVoxel(Offset.zero),
        Offset.zero,
      );
    });

    test(
      'a taller viewport letterboxes the image and the offset is removed',
      () {
        final rect = fitImage(const Size(400, 600), 100, 75);
        expect(rect, const Rect.fromLTWH(0, 150, 400, 300));
        expect(
          mapper(
            Matrix4.identity(),
            rect: rect,
          ).screenToVoxel(const Offset(200, 300)),
          const Offset(50, 37.5),
        );
      },
    );

    test('zoomed', () {
      final m = Matrix4.diagonal3Values(2, 2, 1);
      expect(
        mapper(m).screenToVoxel(const Offset(200, 150)),
        const Offset(25, 18.75),
      );
    });

    test('panned', () {
      final m = Matrix4.translationValues(50, 30, 0);
      expect(
        mapper(m).screenToVoxel(const Offset(250, 180)),
        const Offset(50, 37.5),
      );
    });

    test('zoomed and panned', () {
      // screen = 2 * scene - (100, 60)
      final m =
          Matrix4.translationValues(-100, -60, 0) *
          Matrix4.diagonal3Values(2, 2, 1);
      final mp = mapper(m);
      expect(mp.screenToVoxel(const Offset(300, 240)), const Offset(50, 37.5));
      expect(mp.screenToVoxel(const Offset(-100, -60)), Offset.zero);
    });

    test(
      'round trip: voxel -> screen -> voxel for a zoomed and panned view',
      () {
        final m =
            Matrix4.translationValues(-137, 42, 0) *
            Matrix4.diagonal3Values(3.3, 3.3, 1);
        final mp = mapper(m);
        for (final v in const [
          Offset(0, 0),
          Offset(12.5, 60.25),
          Offset(99.9, 74.9),
          Offset(50, 37.5),
        ]) {
          final screen = MatrixUtils.transformPoint(m, mp.voxelToScene(v));
          final back = mp.screenToVoxel(screen);
          expect((back - v).distance, lessThan(1e-9));
        }
      },
    );

    test('a degenerate matrix falls back to identity instead of throwing', () {
      expect(
        mapper(Matrix4.zero()).screenToVoxel(const Offset(200, 150)),
        const Offset(50, 37.5),
      );
    });

    test('contains tells whether a point is on the slice', () {
      final mp = mapper(Matrix4.identity());
      expect(mp.contains(const Offset(0, 0)), isTrue);
      expect(mp.contains(const Offset(99.9, 74.9)), isTrue);
      expect(mp.contains(const Offset(100, 10)), isFalse);
      expect(mp.contains(const Offset(-0.1, 10)), isFalse);
    });
  });

  group('paintStroke', () {
    test('a tap paints a round, centred dot of the brush radius', () {
      final s = MaskSlice(21, 21);
      final op = paintStroke(
        s,
        const [Offset(10.5, 10.5)],
        radius: 2.5,
        value: 1,
      )!;
      expect(
        count(s),
        21,
      ); // all pixels within 2.5 of the centre of pixel (10, 10)
      expect(
        at(s, 10, 10) &&
            at(s, 8, 10) &&
            at(s, 12, 10) &&
            at(s, 10, 8) &&
            at(s, 10, 12),
        isTrue,
      );
      expect(
        at(s, 8, 8),
        isFalse,
      ); // the corner of the 5x5 square is outside the circle
      expect(op.length, 21);
    });

    test('a fast stroke (two far-apart points) leaves no gaps', () {
      final s = MaskSlice(50, 10);
      paintStroke(
        s,
        const [Offset(2.5, 5.5), Offset(40.5, 5.5)],
        radius: 1,
        value: 1,
      );
      for (var x = 2; x <= 40; x++) {
        expect(at(s, x, 5), isTrue, reason: 'gap at x=$x');
      }
      expect(at(s, 41, 5) && at(s, 42, 5), isFalse);
    });

    test('a diagonal stroke is connected', () {
      final s = MaskSlice(40, 40);
      paintStroke(
        s,
        const [Offset(2.5, 2.5), Offset(35.5, 30.5)],
        radius: 1,
        value: 1,
      );
      // Every column between the ends has painted pixels.
      for (var x = 3; x <= 35; x++) {
        expect(
          [for (var y = 0; y < 40; y++) at(s, x, y)].contains(true),
          isTrue,
          reason: 'column $x',
        );
      }
    });

    test('a brush smaller than a pixel still paints the pixel under it', () {
      final s = MaskSlice(10, 10);
      paintStroke(s, const [Offset(3.0, 3.0)], radius: 0.2, value: 1);
      expect(count(s), greaterThanOrEqualTo(1));
    });

    test('painting past the edge is clipped, not an error', () {
      final s = MaskSlice(10, 10);
      final op = paintStroke(
        s,
        const [Offset(-5, 5), Offset(15, 5)],
        radius: 2,
        value: 1,
      )!;
      expect(op.indices.every((i) => i >= 0 && i < 100), isTrue);
      expect(at(s, 0, 5) && at(s, 9, 5), isTrue);
    });

    test('the eraser (value 0) removes only what is under it', () {
      final s = MaskSlice(20, 20);
      paintStroke(
        s,
        const [Offset(5.5, 10.5), Offset(15.5, 10.5)],
        radius: 3,
        value: 1,
      );
      final before = count(s);
      final op = paintStroke(
        s,
        const [Offset(10.5, 10.5)],
        radius: 2,
        value: 0,
      )!;
      expect(count(s), before - op.length);
      expect(at(s, 10, 10), isFalse);
      expect(at(s, 5, 10) && at(s, 15, 10), isTrue);
    });

    test('painting what is already painted changes nothing', () {
      final s = MaskSlice(10, 10);
      paintStroke(s, const [Offset(5.5, 5.5)], radius: 2, value: 1);
      expect(
        paintStroke(s, const [Offset(5.5, 5.5)], radius: 2, value: 1),
        isNull,
      );
      expect(paintStroke(s, const [], radius: 2, value: 1), isNull);
    });

    test(
      'the other labels are replaced with the painted label, and undo restores them',
      () {
        final s = MaskSlice(10, 10)..labels[55] = 2;
        final op = paintStroke(
          s,
          const [Offset(5.5, 5.5)],
          radius: 1,
          value: 1,
        )!;
        expect(s.labels[55], 1);
        op.undo(s.labels);
        expect(s.labels[55], 2);
      },
    );
  });

  group('fillPolygon (lasso)', () {
    test('a rectangle fills exactly the pixels whose centres are inside', () {
      final s = MaskSlice(12, 12);
      fillPolygon(s, const [
        Offset(2, 2),
        Offset(8, 2),
        Offset(8, 6),
        Offset(2, 6),
      ], value: 1);
      expect(count(s), 6 * 4);
      expect(at(s, 2, 2) && at(s, 7, 5), isTrue);
      expect(at(s, 8, 2) || at(s, 2, 6) || at(s, 1, 3), isFalse);
    });

    test('a triangle has roughly its geometric area', () {
      final s = MaskSlice(60, 60);
      fillPolygon(s, const [
        Offset(5, 5),
        Offset(45, 5),
        Offset(5, 45),
      ], value: 1);
      expect(count(s), closeTo(40 * 40 / 2, 40));
    });

    test('a concave polygon keeps its notch empty (even-odd fill)', () {
      final s = MaskSlice(20, 20);
      // A "U": the inner rectangle x 6..13, y 2..10 is open at the top.
      fillPolygon(s, const [
        Offset(2, 2),
        Offset(6, 2),
        Offset(6, 10),
        Offset(13, 10),
        Offset(13, 2),
        Offset(17, 2),
        Offset(17, 14),
        Offset(2, 14),
      ], value: 1);
      expect(at(s, 3, 5) && at(s, 15, 5) && at(s, 9, 12), isTrue);
      expect(at(s, 9, 5), isFalse);
    });

    test('fewer than three points do nothing', () {
      expect(
        fillPolygon(MaskSlice(5, 5), const [
          Offset(1, 1),
          Offset(3, 3),
        ], value: 1),
        isNull,
      );
    });

    test('a polygon larger than the slice is clipped', () {
      final s = MaskSlice(10, 10);
      fillPolygon(s, const [
        Offset(-5, -5),
        Offset(20, -5),
        Offset(20, 20),
        Offset(-5, 20),
      ], value: 1);
      expect(count(s), 100);
    });
  });

  group('EditOp', () {
    test('undo and redo restore exactly the touched pixels', () {
      final s = MaskSlice(10, 10);
      final original = Uint8List.fromList(s.labels);
      final op = paintStroke(s, const [Offset(5.5, 5.5)], radius: 2, value: 1)!;
      final painted = Uint8List.fromList(s.labels);

      op.undo(s.labels);
      expect(sameLabels(s.labels, original), isTrue);
      op.redo(s.labels);
      expect(sameLabels(s.labels, painted), isTrue);
    });

    test('diff turns one slice into another, and is null for equal slices', () {
      final a = Uint8List.fromList([0, 1, 1, 0, 2]);
      final b = Uint8List.fromList([0, 0, 1, 1, 2]);
      final op = EditOp.diff(a, b)!;
      expect(op.indices.toList(), [1, 3]);
      final work = Uint8List.fromList(a);
      op.redo(work);
      expect(work, b);
      op.undo(work);
      expect(work, a);
      expect(EditOp.diff(a, a), isNull);
    });
  });

  group('label PNG codec', () {
    testWidgets('every label value survives encode then decode', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = MaskSlice(16, 16);
        for (var i = 0; i < s.labels.length; i++) {
          s.labels[i] = i; // 0..255, all values
        }
        final back = await decodeLabelPng(await encodeLabelPng(s));
        expect((back.width, back.height), (16, 16));
        expect(back.labels, s.labels);
      });
    });

    testWidgets('decodes the gray PNG the server produces (Pillow, mode L)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const serverPng =
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAAAAABawyK/AAAAEklEQVR4nGNkYGRkZGBh/fcfAANDAgsSFU8MAAAAAElFTkSuQmCC';
        final s = await decodeLabelPng(base64Decode(serverPng));
        expect((s.width, s.height), (4, 2));
        expect(s.labels, [0, 1, 2, 3, 4, 5, 254, 255]);
      });
    });

    testWidgets(
      'the mask image has the slice size and only labelled pixels are visible',
      (tester) async {
        await tester.runAsync(() async {
          final s = MaskSlice(8, 4)..labels[5] = 1;
          final image = await maskToImage(s, const Color(0xFF22D3EE));
          expect((image.width, image.height), (8, 4));
          image.dispose();
        });
      },
    );
  });
}
