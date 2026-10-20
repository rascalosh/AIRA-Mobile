import 'dart:math' as math;
import 'dart:ui';

import '../domain/mask_slice.dart';

// Points are in voxel space: the slice spans (0, 0) to (width, height) and pixel (x, y) has its centre at
// (x + 0.5, y + 0.5). Each function changes the slice in place and returns the edit (null if nothing changed).

/// Paints a round brush of [radius] voxels along [points], setting every pixel whose centre is within the brush to
/// [value] (0 erases). Each segment is covered by distance to the segment, so a fast stroke has no gaps.
EditOp? paintStroke(
  MaskSlice slice,
  List<Offset> points, {
  required double radius,
  required int value,
}) {
  if (points.isEmpty) return null;
  final rec = OpRecorder();
  final r2 = radius * radius;
  final segments = points.length == 1
      ? [(points.first, points.first)]
      : [
          for (var i = 0; i + 1 < points.length; i++)
            (points[i], points[i + 1]),
        ];

  for (final (a, b) in segments) {
    // The pixel under the point always counts, even for a brush smaller than a pixel.
    _setPixel(slice, rec, a.dx.floor(), a.dy.floor(), value);
    final x0 = math.max((math.min(a.dx, b.dx) - radius).floor(), 0);
    final x1 = math.min(
      (math.max(a.dx, b.dx) + radius).ceil(),
      slice.width - 1,
    );
    final y0 = math.max((math.min(a.dy, b.dy) - radius).floor(), 0);
    final y1 = math.min(
      (math.max(a.dy, b.dy) + radius).ceil(),
      slice.height - 1,
    );
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (_distanceSquared(Offset(x + 0.5, y + 0.5), a, b) <= r2) {
          _setPixel(slice, rec, x, y, value);
        }
      }
    }
  }
  return rec.build();
}

/// Fills the closed polygon [vertices] (even-odd rule) with [value]: the lasso.
EditOp? fillPolygon(
  MaskSlice slice,
  List<Offset> vertices, {
  required int value,
}) {
  if (vertices.length < 3) return null;
  final rec = OpRecorder();
  final top = math.max(vertices.map((v) => v.dy).reduce(math.min).floor(), 0);
  final bottom = math.min(
    vertices.map((v) => v.dy).reduce(math.max).ceil(),
    slice.height - 1,
  );

  for (var y = top; y <= bottom; y++) {
    final yc = y + 0.5;
    final crossings = <double>[];
    for (var i = 0; i < vertices.length; i++) {
      final p = vertices[i];
      final q = vertices[(i + 1) % vertices.length];
      if ((p.dy <= yc && yc < q.dy) || (q.dy <= yc && yc < p.dy)) {
        crossings.add(p.dx + (yc - p.dy) * (q.dx - p.dx) / (q.dy - p.dy));
      }
    }
    crossings.sort();
    for (var i = 0; i + 1 < crossings.length; i += 2) {
      final from = math.max((crossings[i] - 0.5).ceil(), 0);
      final to = math.min((crossings[i + 1] - 0.5).floor(), slice.width - 1);
      for (var x = from; x <= to; x++) {
        _setPixel(slice, rec, x, y, value);
      }
    }
  }
  return rec.build();
}

void _setPixel(MaskSlice slice, OpRecorder rec, int x, int y, int value) {
  if (x < 0 || y < 0 || x >= slice.width || y >= slice.height) return;
  rec.set(slice.labels, y * slice.width + x, value);
}

double _distanceSquared(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  final t = len2 == 0
      ? 0.0
      : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  final d = p - (a + ab * t);
  return d.dx * d.dx + d.dy * d.dy;
}

/// Only the boundary of [slice]'s mask: set pixels that have a background (or off-slice) neighbour. Used to show
/// the user's outline next to a refinement proposal.
MaskSlice outline(MaskSlice slice) {
  final out = MaskSlice(slice.width, slice.height);
  bool on(int x, int y) =>
      x >= 0 &&
      y >= 0 &&
      x < slice.width &&
      y < slice.height &&
      slice.labels[y * slice.width + x] != 0;
  for (var y = 0; y < slice.height; y++) {
    for (var x = 0; x < slice.width; x++) {
      if (on(x, y) &&
          !(on(x - 1, y) && on(x + 1, y) && on(x, y - 1) && on(x, y + 1))) {
        out.labels[y * slice.width + x] = 1;
      }
    }
  }
  return out;
}
