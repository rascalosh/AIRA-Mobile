import 'dart:typed_data';

/// One axial mask slice at native resolution: a label per pixel (0 = background), row by row.
class MaskSlice {
  MaskSlice(this.width, this.height, [Uint8List? labels])
    : labels = labels ?? Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List labels;

  MaskSlice copy() => MaskSlice(width, height, Uint8List.fromList(labels));
}

bool sameLabels(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One undoable change to a slice: the pixels it touched with their values before and after.
/// Storing only the touched pixels (not a copy of the slice) keeps 50 undo steps cheap.
class EditOp {
  EditOp(this.indices, this.before, this.after);

  final Int32List indices;
  final Uint8List before;
  final Uint8List after;

  int get length => indices.length;

  /// The change that turns [from] into [to], or null when they are equal.
  static EditOp? diff(Uint8List from, Uint8List to) {
    final rec = OpRecorder();
    final scratch = Uint8List.fromList(from);
    for (var i = 0; i < to.length; i++) {
      rec.set(scratch, i, to[i]);
    }
    return rec.build();
  }

  void redo(Uint8List labels) {
    for (var i = 0; i < indices.length; i++) {
      labels[indices[i]] = after[i];
    }
  }

  void undo(Uint8List labels) {
    for (var i = 0; i < indices.length; i++) {
      labels[indices[i]] = before[i];
    }
  }
}

/// Applies pixel changes to a label array while remembering what it replaced.
class OpRecorder {
  final _indices = <int>[];
  final _before = <int>[];
  final _after = <int>[];

  void set(Uint8List labels, int index, int value) {
    final old = labels[index];
    if (old == value) return;
    _indices.add(index);
    _before.add(old);
    _after.add(value);
    labels[index] = value;
  }

  EditOp? build() => _indices.isEmpty
      ? null
      : EditOp(
          Int32List.fromList(_indices),
          Uint8List.fromList(_before),
          Uint8List.fromList(_after),
        );
}
